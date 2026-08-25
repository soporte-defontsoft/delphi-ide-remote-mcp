unit Lsp.Dproj;

{ The ONE place that reads a Delphi .dproj (tolerant XML scanning, no MSBuild
  engine). Both the LSP config fabricator and the project/platform tools use
  it - never a second parser (measured house rule: do not reinvent wheels).

  A .dproj is MSBuild XML. What matters here:
  - <Platform value="Win64">True</Platform>  under <Platforms>  -> declared platforms
  - <BuildConfiguration Include="Debug"><Key>Cfg_2</Key>...     -> build configurations
  - <FrameworkType>VCL|FMX|None</FrameworkType>                 -> which UI framework
  - <AppType>Application|Console</AppType>
  Accumulating property lists (search paths) are merged with MergeProperty. }

interface

type
  TDprojPlatform = record
    Name: string;     // 'Win32', 'Win64', 'Linux64', 'OSX64', 'Android64'...
    Enabled: Boolean; // the value in <Platform value="X">VALUE</Platform>
  end;

  TDprojInfo = record
    FrameworkType: string; // 'VCL' | 'FMX' | 'None' | '' (unknown)
    AppType: string;       // 'Application' | 'Console' | ''
    Configs: TArray<string>;         // 'Base','Debug','Release',...
    Platforms: TArray<TDprojPlatform>;
    function HasConfig(const AName: string): Boolean;
    function HasPlatform(const AName: string): Boolean;
    { True if this project's framework can target APlatform. VCL is Windows
      only; FMX and non-visual (console/None) cross platforms. }
    function CanTarget(const APlatform: string; out AReason: string): Boolean;
  end;

{ ---- tolerant XML primitives (shared) ---- }

{ Inner texts of <ATag ...>...</ATag>, in document order. }
function AllTagValues(const AXml, ATag: string): TArray<string>;

{ Value of one attribute across every <ATag attr="...">, in document order. }
function AllTagAttr(const AXml, ATag, AAttr: string): TArray<string>;

{ Merge an accumulating MSBuild property (each value may embed $(Prop) = the
  value so far). }
function MergeProperty(const AXml, APropName: string): string;

function XmlUnescape(const S: string): string;

{ ---- .dproj reading ---- }

{ Reads a .dproj file. Missing file / unreadable -> empty record (all fields
  blank), never raises. }
function ReadDproj(const ADprojPath: string): TDprojInfo;

{ True when APlatform is one that never needs a remote profile/SDK (it builds
  natively on this Windows host). }
function IsLocalPlatform(const APlatform: string): Boolean;

{ The CANONICAL set of Delphi target platforms. add-platform validates
  against this: a platform name is a fixed, known token, so anything else is
  rejected outright - which also makes it impossible to inject XML into the
  .dproj through the platform name (measured RCE vector, field round 5).
  Returns the correctly-cased canonical name, or '' if unknown. }
function CanonicalPlatform(const AName: string): string;

const
  { The platforms paclient.exe accepts for --platform= (its own help lists
    exactly these). Narrower than CanonicalPlatform - Android deploys without
    PAServer. One definition, shared by the gate and delphi_paserver. }
  PACLIENT_PLATFORMS: array[0..4] of string =
    ('Win32', 'Win64', 'WinARM64EC', 'OSX64', 'Linux64');

{ Value of <ATag>...</ATag> in a small TRUSTED XML (our own .profile/.sdk
  files, written by paclient or by this server). Not a general parser on
  purpose. One definition, shared by delphi_paserver and delphi_adb. }
function TagValue(const AXml, ATag: string): string;

{ Whether a project would EXECUTE a shell during a build: a custom MSBuild
  <Target> or <Exec> task (with or without an XML namespace prefix), a
  non-empty RAD Studio build-event command, or an <Import> of anything that is
  not one of the IDE's own targets files. A stock RAD Studio project has none
  of these. Their presence turns "build" into "run", which a compile-only
  server must refuse unless the operator opted into execution.

  Imports are FOLLOWED: an import that resolves to a readable file inside the
  project is scanned too, recursively. Field round 8 defeated a rule that only
  looked at the .dproj by importing "$(MSBuildProjectDirectory)\payload.targets"
  - macro-based, so it passed a naive macro check, while resolving to a file
  uploaded right next to the project. Only the IDE's own imports are trusted
  without reading them; anything unresolvable is refused rather than assumed
  harmless.

  AProjectPath is the .dproj being built (used to resolve the imports).
  Returns the offending construct, or '' when the project is safe to build. }
function DprojBuildHazard(const AXml, AProjectPath: string): string;

{ The artifact a build just produced, found ON DISK (truth of the moment,
  never an index): candidate output dirs are every DCC_ExeOutput /
  DCC_BplOutput declared in the .dproj plus the IDE default
  .\$(Platform)\$(Config), with the common macros expanded; the newest
  existing <project>.exe/.dll/.bpl among them wins. Returns '' when nothing
  is there (build failed, macro we cannot resolve, unusual layout). }
function ResolveBuildOutput(const ADprojPath, APlatform, AConfig: string): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.IOUtils,
  System.Generics.Collections;

function AllTagValues(const AXml, ATag: string): TArray<string>;
var
  List: TList<string>;
  P, TagEnd, CloseP: Integer;
  Open1, Open2, CloseTag: string;
begin
  List := TList<string>.Create;
  try
    Open1 := '<' + ATag + '>';
    Open2 := '<' + ATag + ' ';
    CloseTag := '</' + ATag + '>';
    P := 1;
    while P <= Length(AXml) do
    begin
      var P1 := Pos(Open1, AXml, P);
      var P2 := Pos(Open2, AXml, P);
      if (P1 = 0) and (P2 = 0) then
        Break;
      if (P1 = 0) or ((P2 > 0) and (P2 < P1)) then
      begin
        TagEnd := Pos('>', AXml, P2);
        if TagEnd = 0 then
          Break;
        if AXml[TagEnd - 1] = '/' then
        begin
          P := TagEnd + 1;
          Continue;
        end;
        P := TagEnd + 1;
      end
      else
        P := P1 + Length(Open1);
      CloseP := Pos(CloseTag, AXml, P);
      if CloseP = 0 then
        Break;
      List.Add(Copy(AXml, P, CloseP - P));
      P := CloseP + Length(CloseTag);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function AllTagAttr(const AXml, ATag, AAttr: string): TArray<string>;
var
  List: TList<string>;
  P, TagEnd, AttrP, ValStart, ValEnd: Integer;
  Open, Needle: string;
begin
  List := TList<string>.Create;
  try
    Open := '<' + ATag + ' ';
    Needle := AAttr + '="';
    P := 1;
    while P <= Length(AXml) do
    begin
      P := Pos(Open, AXml, P);
      if P = 0 then
        Break;
      TagEnd := Pos('>', AXml, P);
      if TagEnd = 0 then
        Break;
      AttrP := Pos(Needle, AXml, P);
      if (AttrP > 0) and (AttrP < TagEnd) then
      begin
        ValStart := AttrP + Length(Needle);
        ValEnd := Pos('"', AXml, ValStart);
        if (ValEnd > 0) and (ValEnd <= TagEnd) then
          List.Add(Copy(AXml, ValStart, ValEnd - ValStart));
      end;
      P := TagEnd + 1;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function MergeProperty(const AXml, APropName: string): string;
var
  V: string;
begin
  Result := '';
  for V in AllTagValues(AXml, APropName) do
    Result := V.Replace('$(' + APropName + ')', Result, [rfReplaceAll, rfIgnoreCase]);
end;

function XmlUnescape(const S: string): string;
begin
  Result := S.Replace('&amp;', '&').Replace('&lt;', '<').Replace('&gt;', '>')
    .Replace('&quot;', '"').Replace('&apos;', '''');
end;

{ TDprojInfo }

function TDprojInfo.HasConfig(const AName: string): Boolean;
var
  C: string;
begin
  for C in Configs do
    if SameText(C, AName) then
      Exit(True);
  Result := False;
end;

function TDprojInfo.HasPlatform(const AName: string): Boolean;
var
  P: TDprojPlatform;
begin
  for P in Platforms do
    if SameText(P.Name, AName) then
      Exit(True);
  Result := False;
end;

function TDprojInfo.CanTarget(const APlatform: string; out AReason: string): Boolean;
begin
  AReason := '';
  // VCL is Windows-only: Vcl.Forms does not exist on Linux/macOS/mobile.
  if SameText(FrameworkType, 'VCL') and not IsLocalPlatform(APlatform) then
  begin
    AReason := Format('el proyecto es VCL y VCL solo existe en Windows ' +
      '(Vcl.Forms no compila para %s). Para multiplataforma con interfaz usa ' +
      'FMX; sin interfaz, una app de consola.', [APlatform]);
    Exit(False);
  end;
  Result := True;
end;

function ReadDproj(const ADprojPath: string): TDprojInfo;
var
  Xml, Low: string;
  Plats: TList<TDprojPlatform>;
  P: TDprojPlatform;
  Scan, Op, NameStart, NameEnd, TagEnd, CloseP: Integer;
const
  Needle = '<platform value="';
begin
  Result := Default(TDprojInfo);
  if (ADprojPath = '') or not TFile.Exists(ADprojPath) then
    Exit;
  try
    Xml := TFile.ReadAllText(ADprojPath);
  except
    Exit;
  end;
  var Fw := AllTagValues(Xml, 'FrameworkType');
  if Length(Fw) > 0 then
    Result.FrameworkType := Fw[0].Trim;
  var At := AllTagValues(Xml, 'AppType');
  if Length(At) > 0 then
    Result.AppType := At[0].Trim;
  // Build configurations: <BuildConfiguration Include="Debug">
  Result.Configs := AllTagAttr(Xml, 'BuildConfiguration', 'Include');
  // Platforms: <Platform value="Win64">True</Platform> under <Platforms>.
  // Parse each tag as a UNIT so the name (value attr) and enabled (inner text)
  // always come from the SAME element. A separate attr-list + value-list drift
  // apart because the .dproj also carries a selector
  // <Platform Condition="'$(Platform)'==''">Win64</Platform> that has NO value
  // attribute but DOES have inner text, shifting the value list by one and
  // mislabelling every platform's enabled flag (field round 6, R6-A). Matching
  // only '<Platform value="' also ignores that selector cleanly.
  Low := LowerCase(Xml);
  Plats := TList<TDprojPlatform>.Create;
  try
    Scan := 1;
    while True do
    begin
      Op := Pos(Needle, Low, Scan);
      if Op = 0 then
        Break;
      NameStart := Op + Length(Needle);
      NameEnd := Pos('"', Xml, NameStart);
      TagEnd := Pos('>', Xml, NameStart);
      if (NameEnd = 0) or (TagEnd = 0) then
        Break;
      CloseP := Pos('</platform>', Low, TagEnd);
      P.Name := Copy(Xml, NameStart, NameEnd - NameStart).Trim;
      if CloseP > 0 then
        P.Enabled := SameText(Copy(Xml, TagEnd + 1, CloseP - TagEnd - 1).Trim, 'True')
      else
        P.Enabled := False;
      if P.Name <> '' then
        Plats.Add(P);
      Scan := TagEnd + 1;
    end;
    Result.Platforms := Plats.ToArray;
  finally
    Plats.Free;
  end;
end;

function IsLocalPlatform(const APlatform: string): Boolean;
begin
  Result := MatchText(APlatform,
    ['Win32', 'Win64', 'Win64x', 'WinARM64EC']);
end;

const
  KNOWN_PLATFORMS: array [0 .. 12] of string = (
    'Win32', 'Win64', 'Win64x', 'WinARM64EC',
    'OSX64', 'OSXARM64', 'Linux64',
    'Android', 'Android64',
    'iOSDevice32', 'iOSDevice64', 'iOSSimARM64', 'iOSSimulator');

  // MSBuild tasks whose presence turns a build into arbitrary execution or an
  // out-of-tree file write. A <Target> that uses NONE of these (only Message,
  // PropertyGroup, ItemGroup, CallTarget...) is inert and allowed to build; one
  // that uses ANY of these needs [Security] AllowBuildScripts. Local names,
  // lowercase; HasElement matches them with or without a namespace prefix.
  //   exec/usingtask/code  -> run a shell / load a task assembly / inline code
  //   copy..touch          -> plant, move or delete files by arbitrary path
  //   write*/downloadfile   -> write a file (a payload, a .targets for later)
  //   unzip/zipdirectory    -> materialise files from an archive
  //   csc/vbc/fsc/xslt/genres-> invoke a compiler / transform = run a program
  DANGER_TASKS: array [0 .. 18] of string = (
    'exec', 'usingtask', 'code',
    'copy', 'move', 'delete', 'makedir', 'removedir', 'touch',
    'writelinestofile', 'writecodefragment', 'downloadfile',
    'unzip', 'zipdirectory',
    'csc', 'vbc', 'fsc', 'xslttransformation', 'generateresource');

function CanonicalPlatform(const AName: string): string;
var
  P: string;
begin
  Result := '';
  for P in KNOWN_PLATFORMS do
    if SameText(P, AName.Trim) then
      Exit(P); // canonical casing, and proven metachar-free
end;

function TagValue(const AXml, ATag: string): string;
var
  P, Q: Integer;
begin
  Result := '';
  P := Pos('<' + ATag + '>', AXml);
  if P = 0 then Exit;
  P := P + Length(ATag) + 2;
  Q := Pos('</' + ATag + '>', AXml);
  if Q > P then
    Result := Copy(AXml, P, Q - P).Trim;
end;

{ True when the XML contains an element whose LOCAL name is AName, with or
  without a namespace prefix (<Target>, <msb:Target>, <Target ...>). ALow must
  already be lowercase. A prefix is [A-Za-z0-9_.-]* before a ':'. }
function HasElement(const ALow, AName: string): Boolean;
var
  P, After: Integer;
begin
  Result := False;
  P := 1;
  while True do
  begin
    P := Pos(AName, ALow, P);
    if P = 0 then
      Exit;
    After := P + Length(AName);
    // Opened by '<' directly, or by a namespace prefix ("<msb:target"), and
    // closed by whitespace, '>' or '/' - so "targets" or "myTarget" do not match.
    if (P > 1) and CharInSet(ALow[P - 1], ['<', ':']) and
       ((After > Length(ALow)) or
        CharInSet(ALow[After], [' ', '>', #9, #13, #10, '/'])) then
      Exit(True);
    Inc(P);
  end;
end;

{ Expands the few MSBuild macros that point INSIDE the project, so an import
  written with them can be resolved and read. Returns '' when the path still
  carries a macro we cannot resolve (which the caller then refuses). }
function ResolveImportPath(const APath, AProjectFile: string): string;
var
  Dir, Name: string;
begin
  Dir := ExtractFileDir(AProjectFile);
  Name := TPath.GetFileNameWithoutExtension(AProjectFile);
  Result := APath;
  Result := Result.Replace('$(MSBuildProjectDirectory)', Dir, [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('$(MSBuildThisFileDirectory)',
    IncludeTrailingPathDelimiter(Dir), [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('$(MSBuildProjectName)', Name, [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('$(ProjectDir)', Dir, [rfReplaceAll, rfIgnoreCase]);
  if Result.Contains('$(') then
    Exit(''); // still macro-based: not resolvable here
  if not TPath.IsPathRooted(Result) then
    Result := TPath.Combine(Dir, Result);
  try
    Result := TPath.GetFullPath(Result);
  except
    Result := '';
  end;
end;

{ The IDE's OWN imports, trusted without reading them: they live in the RAD
  Studio installation or the user's IDE profile, not in the project. }
function IsStockImport(const APathLow: string): Boolean;
begin
  // A traversal disqualifies it outright: "$(BDS)\..\..\evil.targets" is
  // macro-based AND ends in .targets, and a looser rule trusted it (caught by
  // our own evasion test while fixing field round 8).
  if APathLow.Contains('..') then
    Exit(False);
  Result := (APathLow.Contains('$(bds)') and APathLow.Contains('\bin\codegear')
             and APathLow.EndsWith('.targets')) or
            APathLow.Contains('usertools.proj') or
            APathLow.EndsWith('.deployproj');
end;

function ResolveBuildOutput(const ADprojPath, APlatform, AConfig: string): string;
var
  Xml, Dir, Base, D, Cand, Ext, Artifact: string;
  ArtifactExts: TArray<string>;
  Dirs: TList<string>;
  Best: string;
  BestTime, T: TDateTime;

  function Expand(const AValue: string): string;
  begin
    Result := AValue;
    Result := Result.Replace('$(Platform)', APlatform, [rfReplaceAll, rfIgnoreCase]);
    Result := Result.Replace('$(Config)', AConfig, [rfReplaceAll, rfIgnoreCase]);
    Result := Result.Replace('$(MSBuildProjectDirectory)', Dir, [rfReplaceAll, rfIgnoreCase]);
    Result := Result.Replace('$(ProjectDir)', Dir, [rfReplaceAll, rfIgnoreCase]);
    Result := Result.Replace('$(MSBuildProjectName)', Base, [rfReplaceAll, rfIgnoreCase]);
    Result := Result.Replace('$(SanitizedProjectName)', Base, [rfReplaceAll, rfIgnoreCase]);
  end;

begin
  Result := '';
  if (ADprojPath = '') or not TFile.Exists(ADprojPath) then
    Exit;
  try
    Dir := ExtractFileDir(TPath.GetFullPath(ADprojPath));
    Xml := TFile.ReadAllText(ADprojPath);
  except
    Exit;
  end;
  Base := TPath.GetFileNameWithoutExtension(ADprojPath);
  // What a build leaves per platform family: Windows .exe/.dll/.bpl, Linux
  // an ELF WITHOUT extension (plus .so), macOS the same (plus .dylib),
  // Android/iOS a .so. Measured 2026-08-23: a Linux64 build declared no
  // output at all and the agent had to hunt the ELF with delphi_list.
  if APlatform.StartsWith('Win', True) then
    ArtifactExts := ['.exe', '.dll', '.bpl']
  else if APlatform.StartsWith('Linux', True) then
    ArtifactExts := ['', '.so']
  else if APlatform.StartsWith('OSX', True) then
    ArtifactExts := ['', '.dylib']
  else
    ArtifactExts := ['.so', ''];
  Best := '';
  BestTime := 0;
  Dirs := TList<string>.Create;
  try
    for D in AllTagValues(Xml, 'DCC_ExeOutput') do
      Dirs.Add(D.Trim);
    for D in AllTagValues(Xml, 'DCC_BplOutput') do
      Dirs.Add(D.Trim);
    Dirs.Add('.\$(Platform)\$(Config)'); // the IDE default when unset
    for D in Dirs do
    begin
      Cand := Expand(XmlUnescape(D));
      if (Cand = '') or Cand.Contains('$(') then
        Continue; // still macro-based: not resolvable here
      if not TPath.IsPathRooted(Cand) then
        Cand := TPath.Combine(Dir, Cand);
      try
        Cand := TPath.GetFullPath(Cand);
      except
        Continue;
      end;
      for Ext in ArtifactExts do
      begin
        // Android and iOS name the artifact lib<Project>.so, not <Project>.so,
        // so the search used to come up empty and delphi_build answered
        // success with no "output" at all - the agent had to guess the path
        // (field round 8).
        Artifact := TPath.Combine(Cand, Base + Ext);
        if not TFile.Exists(Artifact) and (Ext = '.so') then
          Artifact := TPath.Combine(Cand, 'lib' + Base + Ext);
        if TFile.Exists(Artifact) then
        begin
          T := TFile.GetLastWriteTime(Artifact);
          if (Best = '') or (T > BestTime) then
          begin
            Best := Artifact;
            BestTime := T;
          end;
        end;
      end;
    end;
  finally
    Dirs.Free;
  end;
  Result := Best;
end;

function HazardScan(const AXml, AProjectFile: string; ADepth: Integer): string; forward;

function DprojBuildHazard(const AXml, AProjectPath: string): string;
begin
  Result := HazardScan(AXml, AProjectPath, 0);
end;

function HazardScan(const AXml, AProjectFile: string; ADepth: Integer): string;
var
  Low, V, Resolved, Imported: string;
  Scan, TagEnd, CloseP, AttrP, ValStart, ValEnd: Integer;
begin
  Result := '';
  // The whole scan is CASE-INSENSITIVE on purpose. MSBuild itself is picky
  // about element casing, but a guard must not depend on that subtlety: the
  // cost of being insensitive is nil (no real project has a <PreBuildEvent>
  // in odd casing) and the cost of being wrong is arbitrary execution.
  Low := LowerCase(AXml);

  // A custom <Target> is NOT a hazard in itself. Real projects legitimately use
  // targets to copy their OWN output, print a message or set a property after a
  // build; refusing every target was a false positive as serious as a hole - it
  // broke legitimate projects, Authenticode signing among them (field round 9).
  // What turns "build" into "run" is a TASK that executes a program or plants/
  // deletes files. Scan for THOSE, wherever they sit (inside a target or not),
  // matched with or without a namespace prefix (<msb:Exec> passed a literal
  // "<Exec" check in field round 8; MSBuild rejected it, but the guard must not
  // depend on that). A trusted project that needs one of these enables it with
  // [Security] AllowBuildScripts (checked by the caller), never here.
  for var Danger in DANGER_TASKS do
    if HasElement(Low, Danger) then
      Exit(Format('a <%s> task (executes a program or writes files during build)',
        [Danger]));

  // RAD Studio build-event commands: only a NON-EMPTY one runs a shell.
  for var Tag in ['prebuildevent', 'postbuildevent', 'prelinkevent',
                  'postlinkevent', 'buildevent'] do
  begin
    Scan := 1;
    while True do
    begin
      Scan := Pos('<' + Tag, Low, Scan);
      if Scan = 0 then
        Break;
      TagEnd := Pos('>', Low, Scan);
      CloseP := Pos('</' + Tag + '>', Low, Scan);
      if (TagEnd = 0) or (CloseP = 0) then
        Break;
      if Copy(AXml, TagEnd + 1, CloseP - TagEnd - 1).Trim <> '' then
        Exit(Format('a non-empty <%s> shell command', [Tag]));
      Scan := CloseP + 1;
    end;
  end;

  // <Import> brings in another MSBuild file, which carries its own targets -
  // so the payload can sit one file away from the project. Being macro-based
  // proves nothing: "$(MSBuildProjectDirectory)\payload.targets" is a macro
  // AND resolves next to the project (field round 8, confirmed execution).
  // Rule: trust ONLY the IDE's own imports without reading them; resolve and
  // SCAN anything else; refuse what cannot be resolved.
  Scan := 1;
  while True do
  begin
    Scan := Pos('<import', Low, Scan);
    if Scan = 0 then
      Break;
    TagEnd := Pos('>', Low, Scan);
    if TagEnd = 0 then
      Break;
    AttrP := Pos('project="', Low, Scan);
    if (AttrP > 0) and (AttrP < TagEnd) then
    begin
      ValStart := AttrP + Length('project="');
      ValEnd := Pos('"', AXml, ValStart);
      if (ValEnd > 0) and (ValEnd <= TagEnd) then
      begin
        V := Copy(AXml, ValStart, ValEnd - ValStart).Trim;
        if V.StartsWith('\\') or V.StartsWith('//') then
          Exit('an <Import> from a UNC path (' + V + ')');
        if IsStockImport(LowerCase(V)) then
        begin
          Scan := TagEnd + 1;
          Continue; // the IDE's own targets: trusted, not read
        end;
        if ADepth >= 4 then
          Exit('an <Import> chain too deep to verify (' + V + ')');
        Resolved := ResolveImportPath(V, AProjectFile);
        if Resolved = '' then
          Exit('an <Import> whose path cannot be verified (' + V + ')');
        if not TFile.Exists(Resolved) then
          Exit('an <Import> of a file that is not there to be checked (' + V + ')');
        Imported := '';
        try
          Imported := TFile.ReadAllText(Resolved);
        except
          Exit('an <Import> that cannot be read to be checked (' + V + ')');
        end;
        // Recurse: the imported file is held to exactly the same standard.
        Result := HazardScan(Imported, Resolved, ADepth + 1);
        if Result <> '' then
          Exit(Format('%s, brought in by <Import> "%s"', [Result, V]));
      end;
    end;
    Scan := TagEnd + 1;
  end;
end;

end.
