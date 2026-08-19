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

{ Whether a project file's XML carries constructs that would EXECUTE a shell
  during a build: a custom MSBuild <Target> or <Exec> task, a non-empty RAD
  Studio build-event command (Pre/PostBuildEvent, Pre/PostLinkEvent), or an
  <Import> of a foreign targets file (UNC or an absolute path with no $(...)
  macro). A stock RAD Studio project has NONE of these. Their presence turns
  "build" into "run", which a compile-only server must refuse unless the
  operator opted into execution (field round 7: delphi_upload could plant such
  a .dproj and delphi_build would run it). Returns the offending construct, or
  '' when the project is safe to build. }
function DprojBuildHazard(const AXml: string): string;

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

function CanonicalPlatform(const AName: string): string;
var
  P: string;
begin
  Result := '';
  for P in KNOWN_PLATFORMS do
    if SameText(P, AName.Trim) then
      Exit(P); // canonical casing, and proven metachar-free
end;

function DprojBuildHazard(const AXml: string): string;
var
  Low, V, Proj: string;
begin
  Result := '';
  Low := LowerCase(AXml);
  // Custom MSBuild target / shell task: a stock .dproj has neither.
  if Low.Contains('<target ') or Low.Contains('<target>') then
    Exit('a custom MSBuild <Target> (runs during build)');
  if Low.Contains('<exec ') or Low.Contains('<exec>') then
    Exit('an <Exec> task (runs a shell command during build)');
  // RAD Studio build-event commands: only a NON-EMPTY one runs a shell.
  for var Tag in ['PreBuildEvent', 'PostBuildEvent', 'PreLinkEvent',
                  'PostLinkEvent', 'BuildEvent'] do
    for V in AllTagValues(AXml, Tag) do
      if V.Trim <> '' then
        Exit(Format('a non-empty <%s> shell command', [Tag]));
  // <Import> of a foreign targets file: UNC, or an absolute path that is not a
  // macro-based ($(BDS)...) or relative import. The stock imports use $(...).
  for Proj in AllTagAttr(AXml, 'Import', 'Project') do
  begin
    V := Proj.Trim;
    if V.StartsWith('\\') then
      Exit('an <Import> from a UNC path (' + V + ')');
    if (Length(V) >= 2) and (V[2] = ':') and not V.Contains('$(') then
      Exit('an <Import> from an absolute path (' + V + ')');
  end;
end;

end.
