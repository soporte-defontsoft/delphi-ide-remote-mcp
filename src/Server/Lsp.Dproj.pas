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

  { Una carpeta donde un build deja ficheros, tal como la declara el proyecto. }
  TBuildOutputDir = record
    Tag: string;   // DCC_ExeOutput, DCC_DcuOutput...
    Value: string; // el valor tal como esta escrito
    Dir: string;   // absoluto y resuelto; '' si no se sabe resolver
  end;

{ ---- tolerant XML primitives (shared) ---- }

{ Inner texts of <ATag ...>...</ATag>, in document order. SIN distinguir
  mayusculas y con cualquier blanco tras el nombre: MSBuild no distingue
  mayusculas en el nombre de una propiedad, y una puerta lee con esta. }
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

{ Una carpeta RELATIVA al proyecto, apta para acabar escrita DENTRO de un
  .dproj o de un .dpr: nombre simple o con niveles (Compiled, bin\out,
  Dominio\Modelos), sin unidad ni ruta absoluta, sin "..", y solo con
  caracteres de una lista blanca - para que nada pueda inyectarse en el XML
  del .dproj como hizo R5-B. Devuelve el token limpio en AClean.

  Vivia en Mcp.Tools.Config, privada, para set-output. Se sube aqui el
  2026-09-21 porque delphi_create necesita EXACTAMENTE la misma regla para la
  subcarpeta donde crea una unit (su ruta acaba en DCCReference Include=".."
  y en el in '..' del .dpr): iba a escribirse una hermana a mano, SIN la
  lista blanca. Lo paro David: "cuidado que no exista ya algo parecido". }
function ValidOutputFolder(const AFolder: string; out AClean: string): Boolean;

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

{ El valor de una propiedad DE PLATAFORMA (PlatformSDK, Profile...): la del
  PropertyGroup de esa plataforma ('$(Base_<Plat>)'!=''), que es donde la
  escriben el IDE y delphi_config set-sdk / set-profile. Si ahi no hay, vale
  una puesta en un grupo SIN plataforma (base o incondicional); la del grupo
  de OTRA plataforma, nunca. Es la inversa de los escritores: leer "el primer
  <PlatformSDK> del fichero" le daba a un build OSX64 el SDK de Linux64
  (paisaje del 2026-09-22). '' si no hay. }
function PlatformProperty(const AXml, APlatform, ATag: string): string;

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
{ AIgnoreBuildEvents: no contar los eventos pre/post build (firma, copia):
  delphi_build los SALTA en vez de rechazar el proyecto, vaciandolos en la
  linea de msbuild, y lo dice (David, 24-sep-2026: "una cosa es compilar la
  version final, otra poder trabajar y ejecutar mientras tanto"). }
function DprojBuildHazard(const AXml, AProjectPath: string;
  AIgnoreBuildEvents: Boolean = False): string;

{ The artifact a build just produced, found ON DISK (truth of the moment,
  never an index): candidate output dirs are every DCC_ExeOutput /
  DCC_BplOutput declared in the .dproj plus the IDE default
  .\$(Platform)\$(Config), with the common macros expanded; the newest
  existing <project>.exe/.dll/.bpl among them wins. Returns '' when nothing
  is there (build failed, macro we cannot resolve, unusual layout). }
function ResolveBuildOutput(const ADprojPath, APlatform, AConfig: string): string;

{ TODAS las carpetas donde un build de ADprojPath (APlatform/AConfig) deja
  ficheros, tal como las declaran el .dproj y lo que importa del proyecto
  (un .optset): cada valor de cada DCC_*Output, en CUALQUIER grupo - las
  condiciones no se evaluan: una de mas es prudencia, una de menos es una
  puerta -, con las macros comunes expandidas y resuelto contra la carpeta
  del proyecto. Dir = '' cuando el valor no se sabe resolver (una macro, un
  escape): quien pregunta decide, y la puerta de build lo rechaza. Una
  etiqueta ausente o vacia no sale: es la del IDE por defecto. }
function BuildOutputDirs(const ADprojPath, APlatform, AConfig: string): TArray<TBuildOutputDir>;

{ La carpeta de salida que este proyecto NO declara y que el IDE pondria
  fuera de el, o '' si declara todas las que usa: sin DCC_DcuOutput los .dcu
  caen junto a cada fuente (tambien las de una referencia de solo lectura);
  un paquete sin DCC_BplOutput/DCC_DcpOutput los deja en las carpetas
  globales del IDE, y la salida C++ (DCC_CBuilderOutput) sin DCC_HppOutput
  deja alli los .hpp (los .obj y .bpi van a la del .dcp). Decidido con David
  (25-sep-2026): se rechaza y se pide declararla. Medido: 1 de 22 proyectos
  de nuestras raices. Se mira PARA ESTE BUILD (APlatform/AConfig): cada
  plataforma y config puede tener su carpeta, o heredar la global
  (EffectiveProperty). }
function BuildOutputUndeclared(const ADprojPath, APlatform, AConfig: string): string;

{ La propiedad de ENTORNO del IDE que este proyecto -o algo que importa-
  REDEFINE, o '' si no toca ninguna. Los <Import> de CodeGear.Common.Targets
  (EnvironmentSettings/EnvOptions/Profiles/GlobalOptionFile) y de
  CodeGear.Profiles.Targets, mas el UserTools.proj de todo .dproj, resuelven A
  TRAVES de estas propiedades el fichero que cargan; el servidor confia esos
  <Import> del IDE sin leerlos (IsStockImport), asi que redefinir una las
  desvia a un fichero elegido por el proyecto: codigo cargado y ejecutado en el
  build SIN un <Import> visible. Se mira la misma cadena que
  BuildOutputUndeclared (el .dproj y lo que importa del proyecto). Es la parte
  2 del gate del build, hermana de BuildOutputUndeclared (la 1). }
function RedefinedIdeImportProperty(const ADprojPath: string): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.IOUtils,
  System.Generics.Collections;

{ El '>' que cierra la etiqueta abierta antes de AFrom, saltando lo que va
  entre comillas: un Condition="'$(A)'>'1'" no la cierra. 0 si no hay. }
function FinDeEtiqueta(const AXml: string; AFrom: Integer): Integer;
var
  Q: Char;
begin
  Q := #0;
  Result := AFrom;
  while Result <= Length(AXml) do
  begin
    if Q <> #0 then
    begin
      if AXml[Result] = Q then
        Q := #0;
    end
    else if CharInSet(AXml[Result], ['"', '''']) then
      Q := AXml[Result]
    else if AXml[Result] = '>' then
      Exit;
    Inc(Result);
  end;
  Result := 0;
end;

function AllTagValues(const AXml, ATag: string): TArray<string>;
var
  List: TList<string>;
  Low, Open, CloseOpen: string;
  P, After, TagEnd, CloseP, Q: Integer;
begin
  // SIN distinguir mayusculas y con cualquier blanco tras el nombre: con esta
  // funcion lee la puerta de las carpetas de salida (BuildOutputDirs), y ni
  // <DCC_EXEOUTPUT>, ni un salto de linea antes de Condition=, ni un '>'
  // dentro de una condicion pueden saltarsela (25-sep-2026). LowerCase solo
  // toca A..Z: las posiciones de Low valen en AXml.
  List := TList<string>.Create;
  try
    Low := LowerCase(AXml);
    Open := '<' + LowerCase(ATag);
    CloseOpen := '</' + LowerCase(ATag);
    P := 1;
    while True do
    begin
      P := Pos(Open, Low, P);
      if P = 0 then
        Break;
      After := P + Length(Open);
      if (After > Length(Low)) or
         not CharInSet(Low[After], ['>', '/', ' ', #9, #13, #10]) then
      begin
        P := After; // <Platforms> no es <Platform>
        Continue;
      end;
      TagEnd := FinDeEtiqueta(Low, After);
      if TagEnd = 0 then
        Break;
      P := TagEnd + 1;
      if Low[TagEnd - 1] = '/' then
        Continue; // <Tag/> o <Tag Condition="..."/>: vacia
      // el cierre, admitiendo blancos antes del '>' (</Tag >)
      CloseP := P;
      Q := 0;
      while True do
      begin
        CloseP := Pos(CloseOpen, Low, CloseP);
        if CloseP = 0 then
          Break;
        Q := CloseP + Length(CloseOpen);
        while (Q <= Length(Low)) and CharInSet(Low[Q], [' ', #9, #13, #10]) do
          Inc(Q);
        if (Q <= Length(Low)) and (Low[Q] = '>') then
          Break;
        CloseP := Q;
      end;
      if CloseP = 0 then
        Break;
      List.Add(Copy(AXml, P, CloseP - P));
      P := Q + 1;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function AllTagAttr(const AXml, ATag, AAttr: string): TArray<string>;
var
  List: TList<string>;
  Low, Open, Attr, Nombre: string;
  P, After, TagEnd, A, K, ValEnd: Integer;
begin
  // Mismo criterio que AllTagValues: sin distinguir mayusculas, con cualquier
  // blanco, y el valor entre comillas dobles O simples (las dos son XML).
  // Los atributos se leen uno a uno: 'Include' no casa dentro de 'XInclude'.
  List := TList<string>.Create;
  try
    Low := LowerCase(AXml);
    Open := '<' + LowerCase(ATag);
    Attr := LowerCase(AAttr);
    P := 1;
    while True do
    begin
      P := Pos(Open, Low, P);
      if P = 0 then
        Break;
      After := P + Length(Open);
      if (After > Length(Low)) or not CharInSet(Low[After], [' ', #9, #13, #10]) then
      begin
        P := After;
        Continue;
      end;
      TagEnd := FinDeEtiqueta(Low, After);
      if TagEnd = 0 then
        Break;
      A := After;
      while A < TagEnd do
      begin
        while (A < TagEnd) and CharInSet(Low[A], [' ', #9, #13, #10, '/']) do
          Inc(A);
        K := A;
        while (K < TagEnd) and not CharInSet(Low[K], ['=', ' ', #9, #13, #10, '/']) do
          Inc(K);
        Nombre := Copy(Low, A, K - A);
        while (K < TagEnd) and CharInSet(Low[K], [' ', #9, #13, #10]) do
          Inc(K);
        if (K >= TagEnd) or (Low[K] <> '=') then
          Break; // no es un atributo bien formado
        Inc(K);
        while (K < TagEnd) and CharInSet(Low[K], [' ', #9, #13, #10]) do
          Inc(K);
        if (K >= TagEnd) or not CharInSet(Low[K], ['"', '''']) then
          Break;
        ValEnd := Pos(Low[K], Low, K + 1);
        if (ValEnd = 0) or (ValEnd > TagEnd) then
          Break;
        if Nombre = Attr then
          List.Add(Copy(AXml, K + 1, ValEnd - K - 1));
        A := ValEnd + 1;
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
  // that uses ANY of these needs AllowBuildScripts en su workspace. Local names,
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

function ValidOutputFolder(const AFolder: string; out AClean: string): Boolean;
var
  C: Char;
  Seg: string;
begin
  Result := False;
  AClean := AFolder.Trim.Trim(['"']).Trim;
  AClean := AClean.Replace('/', '\');
  while AClean.StartsWith('\') do AClean := AClean.Substring(1);
  while AClean.EndsWith('\') do AClean := AClean.Substring(0, AClean.Length - 1);
  if AClean = '' then Exit;
  if AClean.Contains('..') or AClean.Contains(':') then Exit; // no escape, no drive
  for C in AClean do
    if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', ' ', '\']) then
      Exit;
  for Seg in AClean.Split(['\']) do
    if Seg.Trim = '' then Exit; // no empty segments (\\ , trailing, etc.)
  Result := True;
end;

function CanonicalPlatform(const AName: string): string;
var
  P: string;
begin
  Result := '';
  for P in KNOWN_PLATFORMS do
    if SameText(P, AName.Trim) then
      Exit(P); // canonical casing, and proven metachar-free
end;

function PlatformProperty(const AXml, APlatform, ATag: string): string;
var
  Low, Open1, Cond, Valor, Reserva: string;
  P, TagEnd, CloseP, G, GEnd, Q: Integer;
begin
  Result := '';
  Reserva := '';
  Low := LowerCase(AXml);
  Open1 := LowerCase('<' + ATag + '>');
  P := Pos(Open1, Low);
  while P > 0 do
  begin
    TagEnd := P + Length(Open1);
    CloseP := Pos(LowerCase('</' + ATag + '>'), Low, TagEnd);
    if CloseP = 0 then
      Break;
    // el PropertyGroup que lo contiene: el ultimo abierto antes del tag
    G := 0;
    Q := Pos('<propertygroup', Low);
    while (Q > 0) and (Q < P) do
    begin
      G := Q;
      Q := Pos('<propertygroup', Low, Q + 1);
    end;
    Cond := '';
    if G > 0 then
    begin
      GEnd := Pos('>', Low, G);
      if GEnd > 0 then
        Cond := Copy(Low, G, GEnd - G + 1);
      if not Cond.Contains('base_') then
        Cond := ''; // grupo base o incondicional: no es de ninguna plataforma
    end;
    Valor := Trim(Copy(AXml, TagEnd, CloseP - TagEnd));
    if Cond = '' then
    begin
      if Reserva = '' then
        Reserva := Valor;
    end
    else if Cond.Contains(LowerCase('base_' + APlatform + ')')) then
      Exit(Valor);
    P := Pos(Open1, Low, CloseP);
  end;
  Result := Reserva;
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

const
  // Las propiedades con las que dcc decide DONDE deja lo que produce:
  // -E exe/dll, -NU dcu, -LE bpl, -LN dcp, -NH hpp, -NO obj, -NB bpi.
  BUILD_OUTPUT_TAGS: array [0 .. 6] of string = (
    'DCC_ExeOutput', 'DCC_DcuOutput', 'DCC_BplOutput', 'DCC_DcpOutput',
    'DCC_HppOutput', 'DCC_ObjOutput', 'DCC_BpiOutput');

{ Las macros comunes de una carpeta de salida, para una plataforma/config.
  Lo que conserva '$(' no se sabe resolver aqui. UNA copia: la usan
  ResolveBuildOutput (buscar el binario) y BuildOutputDirs (la puerta). }
function ExpandOutputMacros(const AValue, ADir, ABase, APlatform,
  AConfig: string): string;
begin
  Result := AValue;
  Result := Result.Replace('$(Platform)', APlatform, [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('$(Config)', AConfig, [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('$(MSBuildProjectDirectory)', ADir, [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('$(ProjectDir)', ADir, [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('$(MSBuildProjectName)', ABase, [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('$(SanitizedProjectName)', ABase, [rfReplaceAll, rfIgnoreCase]);
end;

{ El texto del .dproj y el de cada fichero DEL PROYECTO que importa (un
  .optset), recursivo hasta 4 niveles: lo que un build lee de este proyecto.
  Los del IDE no se leen (IsStockImport); lo que no se resuelve se salta
  aqui y lo rechaza DprojBuildHazard. UN lector para las dos preguntas sobre
  la salida (BuildOutputDirs, BuildOutputUndeclared). }
function ProjectXmlChain(const ADprojPath: string): TArray<string>;
var
  List: TList<string>;

  procedure Lee(const AFile: string; ADepth: Integer);
  var
    Xml, V, Resolved: string;
  begin
    try
      Xml := TFile.ReadAllText(AFile);
    except
      Exit;
    end;
    List.Add(Xml);
    if ADepth >= 4 then
      Exit;
    for V in AllTagAttr(Xml, 'Import', 'Project') do
    begin
      if IsStockImport(LowerCase(V.Trim)) then
        Continue;
      Resolved := ResolveImportPath(V.Trim, AFile);
      if (Resolved <> '') and TFile.Exists(Resolved) then
        Lee(Resolved, ADepth + 1);
    end;
  end;

begin
  Result := nil;
  if (ADprojPath = '') or not TFile.Exists(ADprojPath) then
    Exit;
  List := TList<string>.Create;
  try
    Lee(TPath.GetFullPath(ADprojPath), 0);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function BuildOutputDirs(const ADprojPath, APlatform, AConfig: string): TArray<TBuildOutputDir>;
var
  List: TList<TBuildOutputDir>;
  Dir, Base, Xml, V, Cand: string;
  Item: TBuildOutputDir;
begin
  Result := nil;
  if (ADprojPath = '') or not TFile.Exists(ADprojPath) then
    Exit;
  Dir := ExtractFileDir(TPath.GetFullPath(ADprojPath));
  Base := TPath.GetFileNameWithoutExtension(ADprojPath);
  List := TList<TBuildOutputDir>.Create;
  try
    // Un valor relativo se resuelve contra la carpeta del PROYECTO aunque
    // venga de un .optset: dcc trabaja alli.
    for Xml in ProjectXmlChain(ADprojPath) do
      for var Tag in BUILD_OUTPUT_TAGS do
        for V in AllTagValues(Xml, Tag) do
        begin
          Item.Tag := Tag;
          Item.Value := V.Trim;
          Item.Dir := '';
          Cand := ExpandOutputMacros(XmlUnescape(Item.Value), Dir, Base,
            APlatform, AConfig).Trim;
          if Cand = '' then
            Continue; // vacia: la del IDE por defecto (BuildOutputUndeclared)
          // Una macro sin resolver, un escape de MSBuild (%3A), una entidad
          // numerica (&#58;) o un CDATA: msbuild lo leeria distinto que
          // nosotros, y lo que no se puede comprobar no se aprueba.
          if not (Cand.Contains('$(') or Cand.Contains('@(') or
                  Cand.Contains('%') or Item.Value.Contains('&#') or
                  Cand.Contains('<')) then
          begin
            if not TPath.IsPathRooted(Cand) then
              Cand := TPath.Combine(Dir, Cand);
            try
              Item.Dir := TPath.GetFullPath(Cand);
            except
              Item.Dir := '';
            end;
          end;
          List.Add(Item);
        end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{ La clave (Cfg_N) con la que el .dproj nombra una configuracion:
  <BuildConfiguration Include="Debug"><Key>Cfg_2</Key>. No se supone: en
  lo que escribe delphi_create, Cfg_1 es Release. '' si no esta. }
function ConfigKey(const AXml, AConfig: string): string;
var
  Low: string;
  P, TagEnd, CloseP: Integer;
begin
  Result := '';
  Low := LowerCase(AXml);
  P := 1;
  while True do
  begin
    P := Pos('<buildconfiguration', Low, P);
    if P = 0 then
      Exit;
    TagEnd := FinDeEtiqueta(Low, P + 1);
    if TagEnd = 0 then
      Exit;
    CloseP := Pos('</buildconfiguration', Low, TagEnd);
    for var Incl in AllTagAttr(Copy(AXml, P, TagEnd - P + 1), 'BuildConfiguration', 'Include') do
      if SameText(Incl.Trim, AConfig) and (CloseP > 0) then
        for var K in AllTagValues(Copy(AXml, TagEnd + 1, CloseP - TagEnd - 1), 'Key') do
          Exit(K.Trim);
    P := TagEnd + 1;
  end;
end;

{ El valor EFECTIVO de ATag para un build APlatform/AConfig: los grupos del
  .dproj con las condiciones que escribe el IDE - ninguna, '$(Base)' (la
  global: todas las configs y plataformas), '$(Base_<plataforma>)',
  '$(Cfg_N)' y '$(Cfg_N_<plataforma>)' -, en orden de documento, y el
  ultimo que lo fija gana, como en MSBuild: sin definicion particular se
  hereda la global, y una particular vacia la anula. Cada plataforma y
  config puede tener su carpeta (David, 25-sep-2026). Un grupo con otra
  condicion NO cuenta: lo que no se sabe si se aplica no se da por
  declarado. }
function EffectiveProperty(const AXml, ATag, APlatform, AConfig: string): string;
var
  Low, Plat, Key, Cond, V: string;
  Validas: TArray<string>;
  P, Ini, After, TagEnd, CloseP: Integer;
begin
  Result := '';
  Low := LowerCase(AXml);
  Plat := LowerCase(APlatform);
  Key := LowerCase(ConfigKey(AXml, AConfig));
  Validas := ['', '''$(base)''!=''''', '''$(base_' + Plat + ')''!=''''' ];
  if Key <> '' then
    Validas := Validas + ['''$(' + Key + ')''!=''''',
      '''$(' + Key + '_' + Plat + ')''!=''''' ];
  P := 1;
  while True do
  begin
    Ini := Pos('<propertygroup', Low, P);
    if Ini = 0 then
      Break;
    After := Ini + Length('<propertygroup');
    if (After > Length(Low)) or
       not CharInSet(Low[After], ['>', '/', ' ', #9, #13, #10]) then
    begin
      P := After;
      Continue;
    end;
    TagEnd := FinDeEtiqueta(Low, After);
    if TagEnd = 0 then
      Break;
    P := TagEnd + 1;
    if Low[TagEnd - 1] = '/' then
      Continue; // <PropertyGroup/>: vacio
    CloseP := Pos('</propertygroup', Low, P);
    if CloseP = 0 then
      Break;
    Cond := '';
    for V in AllTagAttr(Copy(AXml, Ini, TagEnd - Ini + 1), 'PropertyGroup', 'Condition') do
      Cond := LowerCase(XmlUnescape(V)).Replace(' ', '', [rfReplaceAll])
        .Replace(#9, '', [rfReplaceAll]).Replace(#13, '', [rfReplaceAll])
        .Replace(#10, '', [rfReplaceAll]);
    if MatchStr(Cond, Validas) then
      for V in AllTagValues(Copy(AXml, P, CloseP - P), ATag) do
        Result := XmlUnescape(V).Trim; // el ultimo gana
    P := CloseP + 1;
  end;
end;

function BuildOutputUndeclared(const ADprojPath, APlatform, AConfig: string): string;
var
  Chain: TArray<string>;

  // Declarada PARA ESTE BUILD en el .dproj: la global o la particular que
  // se aplica. Un .optset no cuenta aqui: se importa con su condicion y no
  // se sabe si se aplica.
  function Declara(const ATag: string): Boolean;
  begin
    Result := EffectiveProperty(Chain[0], ATag, APlatform, AConfig) <> '';
  end;

var
  Xml, V: string;
  Paquete, Cpp: Boolean;
begin
  Result := '';
  Chain := ProjectXmlChain(ADprojPath);
  if Chain = nil then
    Exit;
  // Paquete o salida C++ con que UN sitio lo diga: se exige su carpeta
  // (una de mas es prudencia).
  Paquete := False;
  Cpp := False;
  for Xml in Chain do
  begin
    for V in AllTagValues(Xml, 'AppType') do
      if SameText(XmlUnescape(V).Trim, 'Package') then
        Paquete := True;
    for V in AllTagValues(Xml, 'DCC_CBuilderOutput') do
      if (XmlUnescape(V).Trim <> '') and not SameText(XmlUnescape(V).Trim, 'None') then
        Cpp := True;
  end;
  if not Declara('DCC_DcuOutput') then
    Exit('DCC_DcuOutput');
  if Paquete and not Declara('DCC_BplOutput') then
    Exit('DCC_BplOutput');
  if (Paquete or Cpp) and not Declara('DCC_DcpOutput') then
    Exit('DCC_DcpOutput');
  if Cpp and not Declara('DCC_HppOutput') then
    Exit('DCC_HppOutput');
end;

const
  // Las propiedades de ENTORNO con las que los <Import> propios del IDE
  // localizan lo que cargan: los cuatro punteros a fichero de
  // CodeGear.Common.Targets (<Import Project="$(EnvironmentSettings)"> y sus
  // hermanos EnvOptions/Profiles/GlobalOptionFile), y la raiz
  // $(APPDATA)\Embarcadero\$(BDSAPPDATABASEDIR)\$(ProductVersion) con la que
  // CodeGear.Profiles.Targets importa el .sdk y todo .dproj importa
  // UserTools.proj. Un proyecto NUNCA las define: las pone el entorno del IDE.
  // PlatformSDK queda fuera aposta - esa SI la fija el proyecto (delphi_config
  // set-sdk) y vive en proyectos reales; rechazarla romperia builds legitimos.
  // Y BDS: la raiz de los propios imports del IDE ($(BDS)\Bin\CodeGear.*.Targets),
  // que IsStockImport reconoce por el texto (medido el 25-sep-2026).
  RESERVED_IDE_IMPORT_PROPS: array [0 .. 7] of string = (
    'EnvironmentSettings', 'EnvOptions', 'Profiles', 'GlobalOptionFile',
    'APPDATA', 'BDSAPPDATABASEDIR', 'ProductVersion', 'BDS');

function RedefinedIdeImportProperty(const ADprojPath: string): string;
var
  Xml, Prop: string;
begin
  Result := '';
  // El .dproj y lo que importa del proyecto (ProjectXmlChain, el mismo lector
  // que BuildOutputUndeclared). Una definicion <Prop>...</Prop> en cualquier
  // fichero de la cadena cuenta, sin evaluar su condicion (una de mas es
  // prudencia); una referencia $(Prop) no es una definicion y AllTagValues no
  // la ve, asi que el $(APPDATA)\...\UserTools.proj de todo .dproj no cuenta.
  for Xml in ProjectXmlChain(ADprojPath) do
    for Prop in RESERVED_IDE_IMPORT_PROPS do
      if Length(AllTagValues(Xml, Prop)) > 0 then
        Exit(Prop);
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
    Result := ExpandOutputMacros(AValue, Dir, Base, APlatform, AConfig);
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

function HazardScan(const AXml, AProjectFile: string; ADepth: Integer;
  AIgnoreBuildEvents: Boolean): string; forward;

function DprojBuildHazard(const AXml, AProjectPath: string;
  AIgnoreBuildEvents: Boolean): string;
begin
  Result := HazardScan(AXml, AProjectPath, 0, AIgnoreBuildEvents);
end;

function HazardScan(const AXml, AProjectFile: string; ADepth: Integer;
  AIgnoreBuildEvents: Boolean): string;
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
  // AllowBuildScripts del workspace (checked by the caller), never here.
  for var Danger in DANGER_TASKS do
    if HasElement(Low, Danger) then
      Exit(Format('a <%s> task (executes a program or writes files during build)',
        [Danger]));

  // RAD Studio build-event commands: only a NON-EMPTY one runs a shell.
  // Con AIgnoreBuildEvents no cuentan: el runner los vacia al compilar.
  if not AIgnoreBuildEvents then
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
        Result := HazardScan(Imported, Resolved, ADepth + 1, AIgnoreBuildEvents);
        if Result <> '' then
          Exit(Format('%s, brought in by <Import> "%s"', [Result, V]));
      end;
    end;
    Scan := TagEnd + 1;
  end;
end;

end.
