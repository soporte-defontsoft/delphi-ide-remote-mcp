unit Lsp.ConfigFabricator;

{ Fabricates a .delphilsp.json settings file for a project that has none (or
  a stale one), by mining the .dproj. The fabricated file is written to a
  cache under %LOCALAPPDATA% - user projects are never written to.

  The .dproj is MSBuild XML; instead of a full MSBuild evaluation we do a
  tolerant scan: collect every occurrence of the DCC_* properties across all
  PropertyGroups, accumulate self-references ($(DCC_UnitSearchPath) inside a
  value means "what previous groups said"), expand the handful of variables
  that matter ($(BDS), $(Platform), $(Config)) and drop whatever still has
  unexpanded $() after that. Good enough for Code Insight paths - the
  compiler never runs from these settings. }

interface

uses
  System.SysUtils,
  Lsp.Discovery;

type
  ELspConfigFabricator = class(Exception);

const
  { Los prefijos de unidad (unit scope names) del compilador cuando un
    proyecto no dice los suyos: con ellos 'Classes' es System.Classes. Los
    usa tambien el generador de las tablas del disenador para los uses sin
    prefijo del fuente de terceros (Lsp.DesignerMetaGen): una lista, dos
    lectores. }
  DEFAULT_NAMESPACES =
    'Winapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win;' +
    'System;Xml;Data;Datasnap;Web;Soap';

{ True when an existing .delphilsp.json is unusable: its project file no
  longer exists, or it was generated for a different compiler generation. }
function IsSettingsStale(const ASettingsFile: string;
  const AInfo: TRadStudioInfo): Boolean;

{ The project (main source, a path) a settings file names in
  settings.project; '' when the file cannot be read or names none. The
  inverse of what FabricateSettings writes there. The engine makes THAT
  file's folder its current directory when it loads the settings (measured
  2026-09-29), so it is the folder an engine holds. }
function ProjectOfSettings(const ASettingsFile: string): string;

{ Builds (or reuses from cache) a settings file for ADprojPath. Returns the
  cached .delphilsp.json path. Raises if the .dproj cannot be mined. }
function FabricateSettings(const ADprojPath: string;
  const AInfo: TRadStudioInfo): string;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Hash,
  System.Generics.Collections,
  Lsp.Client, // PathToUri / UriToPath
  Lsp.Guard,  // ExpandIdeMacros, EscribeEnCasaDelServidor (entero o nada)
  Lsp.Dproj,
  Lsp.Texts,
  Lsp.NetDrives,  // shared tolerant .dproj parser (AllTagValues/MergeProperty/XmlUnescape)
  Lsp.Json;

const
  STANDARD_ALIASES =
    'Generics.Collections=System.Generics.Collections;' +
    'Generics.Defaults=System.Generics.Defaults;' +
    'WinTypes=Winapi.Windows;WinProcs=Winapi.Windows;' +
    'DbiTypes=BDE;DbiProcs=BDE;DbiErrs=BDE';

  BROWSING_SUBDIRS: array [0 .. 13] of string = (
    'source\rtl\common', 'source\rtl\sys', 'source\rtl\win',
    'source\rtl\net', 'source\vcl', 'source\fmx', 'source\data',
    'source\data\ado', 'source\data\firedac', 'source\data\rest',
    'source\Internet', 'source\soap', 'source\xml', 'source\indy10\Core');

{ AllTagValues / MergeProperty / XmlUnescape now live in Lsp.Dproj (shared). }

{ Split a ;-list, expand variables, drop unexpanded/$-laden or empty entries,
  absolutize relative entries against ABaseDir, keep only unique. }
function CleanPathList(const ARaw, ABaseDir, ABdsRoot, APlatform: string): TArray<string>;
var
  List: TList<string>;
  Item, Expanded: string;
begin
  List := TList<string>.Create;
  try
    for Item in ARaw.Split([';']) do
    begin
      Expanded := Item.Trim
        .Replace('$(BDS)', PrefijoSinBarra(ABdsRoot), [rfReplaceAll, rfIgnoreCase])
        .Replace('$(BDSLIB)', PrefijoSinBarra(ABdsRoot) + '\lib', [rfReplaceAll, rfIgnoreCase])
        .Replace('$(Platform)', APlatform, [rfReplaceAll, rfIgnoreCase])
        .Replace('$(Config)', 'Release', [rfReplaceAll, rfIgnoreCase]);
      if (Expanded = '') or Expanded.Contains('$(') then
        Continue;
      if not TPath.IsPathRooted(Expanded) then
      try
        Expanded := TPath.GetFullPath(TPath.Combine(ABaseDir, Expanded));
      except
        Continue;
      end;
      if not List.Contains(Expanded) then
        List.Add(Expanded);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

const
  // Bump when the fabrication rules change: cached settings older than the
  // rule are otherwise reused as long as they are newer than the .dproj.
  FABRICATOR_GEN = 2; // 2 = GetIt catalog macros expanded (v0.42.2)

var
  // ONE fabrication at a time. Two first requests on a cold project (a hover
  // and a diagnostics, two agents) both found no cache and both wrote the
  // same file: the second answered SYS-027, "Cannot create file" (measured
  // 2026-09-29). The one that waits finds the file made.
  GFabLock: TObject;

{ ---- public API ---- }

{ THE reader of a settings file: the project it names (a path) and its
  dllname. False when the file is not there or names no project. A file that
  is there and cannot be READ (the IDE rewriting it) raises, as it always
  did: read as "names no project" it made the settings stale, and that answer
  was cached until the .dproj changed. }
function ReadSettings(const ASettingsFile: string; out AProject, ADll: string): Boolean;
var
  Root: TJSONObject;
begin
  Result := False;
  AProject := '';
  ADll := '';
  if not FileExists(ASettingsFile) then
    Exit;
  // un fichero que no es un objeto, o cuyo "settings" no lo es, no nombra
  // proyecto: se fabrica el nuestro (salia SYS-006 INTERNAL en cada tool del
  // motor: ObjetoJson)
  Root := ObjetoJson(TFile.ReadAllText(ASettingsFile));
  if Root = nil then
    Exit;
  try
    if not (Root.GetValue('settings') is TJSONObject) then
      Exit;
    var Settings := TJSONObject(Root.GetValue('settings'));
    var ProjVal := Settings.GetValue('project');
    if ProjVal = nil then
      Exit;
    AProject := TLspClient.UriToPath(ProjVal.Value);
    var DllVal := Settings.GetValue('dllname');
    if DllVal <> nil then
      ADll := DllVal.Value;
    Result := AProject <> '';
  finally
    Root.Free;
  end;
end;

function ProjectOfSettings(const ASettingsFile: string): string;
var
  Dll: string;
begin
  // Never raises: it is asked while an engine is being started, and a
  // settings file of an unexpected shape must not cost the request.
  try
    if not ReadSettings(ASettingsFile, Result, Dll) then
      Result := '';
  except
    Result := '';
  end;
end;

function IsSettingsStale(const ASettingsFile: string;
  const AInfo: TRadStudioInfo): Boolean;
var
  Proj, Dll, Suffix: string;
begin
  Result := True; // not there, or names no project = stale (unreadable raises)
  if not ReadSettings(ASettingsFile, Proj, Dll) then
    Exit;
  begin
    if not FileExists(Proj) then
      Exit; // points at a project that is gone (old drive, moved tree)
    // el de su compilador, leido del disco (no del numero BDS: la 12 es
    // BDS 23.0 y su dcc32290.dll; revision R1, 5-oct-2026)
    Suffix := AInfo.SufijoCompilador;
    if (Dll <> '') and not Dll.Contains(Suffix) then
      Exit; // generated by another compiler generation
    Result := False;
  end;
end;

function FabricateSettings(const ADprojPath: string;
  const AInfo: TRadStudioInfo): string;
var
  Xml, DprojDir, MainSource, DprPath, Plat, Suffix, DllName, Lib: string;
  SearchRaw, Defines, Namespaces: string;
  SearchPaths: TArray<string>;
  CacheDir, CacheFile: string;
  Root, Settings: TJSONObject;
  Browsing: TJSONArray;
  Sub, P, PathsJoined, Opts: string;
  Values: TArray<string>;
begin
  if not FileExists(ADprojPath) then
    raise ELspConfigFabricator.Create(MsgFmt(SR_BUILD_DPROJ_NO_EXISTE_FMT, [ADprojPath]));
  if not AInfo.Found then
    raise ELspConfigFabricator.Create(MsgText(SE_BUILD_RAD_STUDIO_INSTALLATION_DISCOVERED));

  DprojDir := TPath.GetDirectoryName(TPath.GetFullPath(ADprojPath));

  System.TMonitor.Enter(GFabLock);
  try
  // Cache: <name>-<pathhash>.delphilsp.json under LOCALAPPDATA. Reuse when
  // newer than the .dproj (and same tool generation baked into the name).
  CacheDir := ServerCacheDir('configs');
  CrearCarpeta(CacheDir);
  CacheFile := TPath.Combine(CacheDir, Format('%s-%x-%s-g%d.delphilsp.json',
    [TPath.GetFileNameWithoutExtension(ADprojPath),
     THashFNV1a32.GetHashValue(TPath.GetFullPath(ADprojPath).ToLower),
     AInfo.Version.Replace('.', '_'), FABRICATOR_GEN]));
  if FileExists(CacheFile) and
     (TFile.GetLastWriteTime(CacheFile) > TFile.GetLastWriteTime(ADprojPath)) then
    Exit(CacheFile);

  Xml := TFile.ReadAllText(ADprojPath);

  Values := AllTagValues(Xml, 'MainSource');
  if Length(Values) > 0 then
    MainSource := Values[0]
  else
    MainSource := TPath.GetFileNameWithoutExtension(ADprojPath) + '.dpr';
  DprPath := TPath.GetFullPath(TPath.Combine(DprojDir, MainSource));

  Values := AllTagValues(Xml, 'Platform');
  if Length(Values) > 0 then
    Plat := Values[0].Trim
  else
    Plat := 'Win32';
  if not SameText(Plat, 'Win32') and not SameText(Plat, 'Win64') then
    Plat := 'Win32'; // Code Insight itself is a Windows front-end

  // EL sufijo de su compilador, el que HAY en su bin (TRadStudioInfo); el
  // mismo que mira IsSettingsStale. Antes se componia del numero BDS, de dos
  // formas en dos sitios, y solo acertaba desde la 13.
  Suffix := AInfo.SufijoCompilador;
  if SameText(Plat, 'Win64') then
    DllName := 'dcc64' + Suffix + '.dll'
  else
    DllName := 'dcc32' + Suffix + '.dll';

  Lib := PrefijoSinBarra(AInfo.RootDir) + '\lib\' + Plat + '\release';

  SearchRaw := MergeProperty(Xml, 'DCC_UnitSearchPath');

  // Merge the IDE's global Library Search Path (registry): INSTALLED
  // COMPONENT packages (third-party) register their paths there, and
  // projects rarely repeat them in the .dproj. Expand the user-dir
  // variables here; CleanPathList expands the BDS ones and drops leftovers.
  var IdeLib := IdeLibrarySearchPath(AInfo.Version, Plat);
  if IdeLib <> '' then
  begin
    // Authoritative dirs from rsvars.bat (never composed by hand: the
    // Documents branding changes between eras). Unresolved $() entries
    // are dropped by CleanPathList.
    var UserDocs := BdsUserDir(AInfo);
    var CommonDocs := BdsCommonDir(AInfo);
    if UserDocs <> '' then
      IdeLib := IdeLib.Replace('$(BDSUSERDIR)', UserDocs, [rfReplaceAll, rfIgnoreCase]);
    if CommonDocs <> '' then
      IdeLib := IdeLib.Replace('$(BDSCOMMONDIR)', CommonDocs, [rfReplaceAll, rfIgnoreCase]);
    // The rest of the IDE's table ($(BDSCatalogRepository) and its AllUsers
    // twin are where EVERY GetIt package lives - LockBox, FmxLinux...; a unit
    // using one of them lints as 'could not compile used unit' otherwise).
    var Vars := TStringList.Create;
    try
      IdeEnvironmentVars(AInfo.Version, Vars);
      if (Vars.Values['BDSCatalogRepository'] = '') and (UserDocs <> '') then
        Vars.Values['BDSCatalogRepository'] :=
          IncludeTrailingPathDelimiter(UserDocs) + 'CatalogRepository';
      if (Vars.Values['BDSCatalogRepositoryAllUsers'] = '') and (CommonDocs <> '') then
        Vars.Values['BDSCatalogRepositoryAllUsers'] :=
          IncludeTrailingPathDelimiter(CommonDocs) + 'CatalogRepository';
      IdeLib := ExpandIdeMacros(IdeLib, Vars);
    finally
      Vars.Free;
    end;
    SearchRaw := SearchRaw + ';' + IdeLib;
  end;

  SearchPaths := CleanPathList(SearchRaw, DprojDir, AInfo.RootDir, Plat);

  // Defines: keep simple identifiers only (unexpanded $() and junk dropped).
  Defines := '';
  for P in MergeProperty(Xml, 'DCC_Define').Split([';']) do
    if (P.Trim <> '') and not P.Contains('$(') and not P.Contains('\') then
      if Defines = '' then
        Defines := P.Trim
      else if not (';' + Defines + ';').Contains(';' + P.Trim + ';') then
        Defines := Defines + ';' + P.Trim;

  Namespaces := MergeProperty(Xml, 'DCC_Namespace')
    .Replace('$(DCC_Namespace)', '', [rfReplaceAll, rfIgnoreCase]).Trim([';']);
  if Namespaces = '' then
    Namespaces := DEFAULT_NAMESPACES;

  PathsJoined := Lib;
  for P in SearchPaths do
    PathsJoined := PathsJoined + ';' + P;

  Opts := '--no-config -A' + STANDARD_ALIASES;
  if Defines <> '' then
    Opts := Opts + ' -D' + Defines;
  Opts := Opts + ' -NS' + Namespaces + ';';
  Opts := Opts + Format(' -U"%s" -O"%s" -R"%s" -I"%s"',
    [PathsJoined, PathsJoined, PathsJoined, PathsJoined]);

  Root := TJSONObject.Create;
  try
    Settings := TJSONObject.Create;
    Root.AddPair('settings', Settings);
    Settings.AddPair('project', TLspClient.PathToUri(DprPath));
    Settings.AddPair('dllname', DllName);
    Settings.AddPair('dccOptions', Opts);
    Settings.AddPair('projectFiles', TJSONArray.Create);
    Settings.AddPair('includeDCUsInUsesCompletion', TJSONBool.Create(True));
    Settings.AddPair('enableKeyWordCompletion', TJSONBool.Create(True));
    Browsing := TJSONArray.Create;
    Settings.AddPair('browsingPaths', Browsing);
    for Sub in BROWSING_SUBDIRS do
    begin
      P := PrefijoSinBarra(AInfo.RootDir) + '\' + Sub;
      if TDirectory.Exists(P) then
        Browsing.Add(TLspClient.PathToUri(P));
    end;
    for P in SearchPaths do
      if TDirectory.Exists(P) then
        Browsing.Add(TLspClient.PathToUri(P));

    // Whole or not at all: an engine reads this file the moment it is named
    // to it, and another thread may be reading it to know if it is stale.
    // Somebody that has it open keeps the one that is there.
    EscribeEnCasaDelServidor(CacheFile, Root.Format(1));
  finally
    Root.Free;
  end;
  Result := CacheFile;
  finally
    System.TMonitor.Exit(GFabLock);
  end;
end;

initialization
  GFabLock := TObject.Create;

finalization
  GFabLock.Free;

end.
