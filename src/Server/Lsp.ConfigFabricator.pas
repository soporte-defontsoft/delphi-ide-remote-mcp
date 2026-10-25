unit Lsp.ConfigFabricator;

{ The settings file (.delphilsp.json) the engine runs with, ALWAYS ours,
  mined from the .dproj for the configuration and platform the project has
  SELECTED - what the IDE and msbuild build while nobody asks for another.
  It is written to the server's cache (%LOCALAPPDATA%) - user projects are
  never written to.

  The IDE's own .delphilsp.json is never read (1.20.2, David 17-oct-2026:
  "the IDE maintains that json and we do not use the IDE, so we maintain
  ours and ignore the IDE's"): it is written only when the IDE re-sends its
  settings, so on a server it was stale as soon as an agent touched the
  .dproj, and a copy of a project carried one naming the original (measured,
  M4 and Fable 1). Ours is made again on EVERY request, outside the lock that
  keeps its writer, and written only when it changed; Lsp.Session gives it
  again to an engine that is running (which reloads it, the compiler too:
  measured Win64 -> Win32 on a live engine, 18-oct-2026).

  The properties come from THE evaluator of the build (Lsp.Dproj.
  EffectiveProperty: the groups that apply to that build, self-references
  expanded); what CodeGear.Delphi.Targets adds on its own is added here:
  FRAMEWORK_$(FrameworkType) when it is not None (line 151 of the 37.0
  targets), and the library as its lines 132-137 put it (the project's search
  path, then the DelphiLibraryPath of EnvOptions.proj - the IDE's Library
  Path -, and its Debug DCU Path in front with DCC_DebugDCUs). Chaining every
  DCC_Define of every group gave DEBUG and RELEASE at once, a configuration
  that does not exist (measured, T2/M9). }

interface

uses
  System.SysUtils,
  System.Classes, // TStrings: la tabla de macros de CleanPathList
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

{ The project (main source, a path) a settings file names in
  settings.project; '' when the file cannot be read or names none. The
  inverse of what FabricateSettings writes there. The engine makes THAT
  file's folder its current directory when it loads the settings (measured
  2026-09-29), so it is the folder an engine holds. }
function ProjectOfSettings(const ASettingsFile: string): string;

{ El PROYECTO con el que contesto el motor, como lo nombran las demas tools:
  el .dproj de ProjectOfSettings (su fuente principal si no hay .dproj); ''
  si los ajustes no nombran ninguno. Lo dicen diagnostics, references y
  rename: una unidad que no lista nadie toma el de mas arriba, y lo que el
  motor dice de ella depende de el. Nunca lanza. }
function ProyectoDeLosAjustes(const ASettingsFile: string): string;

{ The settings file for ADprojPath, made again from the .dproj, the IDE's
  library and the jail every time it is asked, and written to the cache only
  when its bytes change: the path stays, its disk stamp moves. Returns the
  cached .delphilsp.json path. Raises if the .dproj cannot be mined. }
function FabricateSettings(const ADprojPath: string;
  const AInfo: TRadStudioInfo): string;

{ Si el motor puede ENSENAR lo que dice de APath: es de lo que esta sesion
  puede leer (la jaula), de los lugares del IDE o de su zona de biblioteca,
  este o no encendida para los agentes (la firma de un metodo de la VCL sale
  como siempre). EL juez de lo que se recorta de los ajustes del motor y de
  lo que las tools del motor niegan (LSP-038, LSP-039). }
function MotorPuedeEnsenar(const APath: string): Boolean;
{ Las units que el .dpr del proyecto nombra con ruta (in '...') FUERA de lo
  que esta sesion puede leer, por su nombre. No se pueden recortar (son el
  proyecto): completion y signature, que contestan nombres sin decir de
  donde, se niegan (LSP-039). Nunca lanza. }
function UnitsDeFueraDelProyecto(const ADprojPath: string): TArray<string>;
{ La nota de unos ajustes del motor recortados (LSP-037), leida del NOMBRE
  que les pone FabricateSettings (su inversa); '' si no se recorto nada. }
function NotaDeRecorte(const ASettingsFile: string): string;
{ La nota de AFile si cuelga por DEBAJO de la carpeta del proyecto de
  ASettingsFile (LSP-046): de esa unidad el motor publica los errores y nunca
  los warnings ni los hints (medido el 15-oct-2026 con el motor solo; en la
  carpeta del proyecto y en una hermana publica todo). '' en otro caso, y
  nunca lanza: es una nota, no puede costar la respuesta. }
function NotaDeDebajoDelProyecto(const ASettingsFile, AFile: string): string;
{ Las carpetas de una lista de search path (a;b;c) como las ve el motor: los
  macros expandidos con AVars (la tabla del IDE, IdeMacroVars, con Platform y
  Config) ANTES de partir - uno que expande a una lista son varias carpetas -,
  sin lo que no expande ni lo vacio, lo relativo contra ABaseDir, cada una una
  vez. Expuesta para medirla (LspTests.Motor). }
function CleanPathList(const ARaw, ABaseDir: string; AVars: TStrings): TArray<string>;

implementation

uses
  System.StrUtils,
  System.IOUtils,
  System.JSON,
  System.Hash,
  System.Generics.Collections,
  Lsp.Client, // PathToUri / UriToPath
  Lsp.Guard,  // CrearCarpeta
  Lsp.Dproj,
  Lsp.Texts,
  Lsp.NetDrives,  // shared tolerant .dproj parser (AllTagValues/MergeProperty/XmlUnescape)
  Lsp.Json,
  System.RegularExpressions,
  Lsp.ProjectUnits, // las units que nombra el .dpr
  Lsp.Patch,  // LeeTexto: la puerta de leer
  Lsp.Casa,   // la casa del servidor (EscribeEnCasaDelServidor vive en Lsp.Patch)
  Lsp.Rutas;  // RutaDesde: EL resolutor de una ruta leida de un fichero

const
  STANDARD_ALIASES =
    'Generics.Collections=System.Generics.Collections;' +
    'Generics.Defaults=System.Generics.Defaults;' +
    'WinTypes=Winapi.Windows;WinProcs=Winapi.Windows;' +
    'DbiTypes=BDE;DbiProcs=BDE;DbiErrs=BDE';

{ AllTagValues / XmlUnescape now live in Lsp.Dproj (shared); MergeProperty is
  gone: the value of ONE build is EffectiveProperty (1.22.0). }

{ Expand variables, THEN split the ;-list, drop unexpanded/$-laden or empty entries,
  absolutize relative entries against ABaseDir, keep only unique. AVars: LA
  tabla de macros del IDE (Lsp.Discovery.IdeMacroVars) con la plataforma y la
  configuracion de los ajustes. Aqui habia otra con cuatro clavadas (BDS,
  BDSLIB, Platform y Config, y Config a fuego en Release): un
  $(BDSCatalogRepository) o un $(BDSCOMMONDIR) en el search path de un
  proyecto se tiraba, y msbuild si lo compila (revision del 18-oct-2026). }
function CleanPathList(const ARaw, ABaseDir: string; AVars: TStrings): TArray<string>;
var
  List: TList<string>;
  Item, Expanded: string;
begin
  List := TList<string>.Create;
  try
    // expandido ANTES de partir: un macro que expande a una lista ($(Path),
    // una variable del entorno con dos carpetas) era UN trozo con ';' dentro,
    // una carpeta que no existe, y el motor no veia las que nombraba (revisor
    // C, 21-oct-2026). EL troceador, el de la puerta del build (TrozosDeLista)
    for Item in TrozosDeLista(ExpandIdeMacros(ARaw, AVars)) do
    begin
      if (Item = '') or Item.Contains('$(') then
        Continue;
      // como la lee el motor, que corre en la carpeta del proyecto (EL
      // resolutor: "\x" y "X:y" se resolvian contra el PROCESO del servidor)
      Expanded := RutaDesde(ABaseDir, Item);
      if Expanded = '' then
        Continue;
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
  // 2 = GetIt catalog macros expanded (v0.42.2); 3 = the selected
  // configuration and platform, by the build's evaluator (1.20.2); 4 = the
  // library as msbuild puts it and the IDE's macro table (1.20.2, review)
  FABRICATOR_GEN = 4;
  // la marca del recorte en el nombre de unos ajustes: -r<cuantas>x<huella>,
  // antes de la generacion. La huella separa dos sesiones que no ven lo mismo
  // (cada una sus ajustes, y por ellos su motor: Lsp.Session.ClientKey)
  RECORTE_FMT = '-r%dx%.8x';
  RECORTE_PATRON = '-r(\d+)x[0-9A-F]{8}-g\d+\.delphilsp\.json$';
  // ...y la generacion, al final: su lector (PurgaGeneracionesViejas)
  GENERACION_PATRON = '-g(\d+)\.delphilsp\.json$';

{ La plataforma que se le da al motor: la SELECCIONADA si es de Windows; si
  no, Win32 (Code Insight itself is a Windows front-end, y las tools del
  motor lo dicen: delphi_symbols parsea como el compilador de Windows). }
function PlataformaDelMotor(const AProyecto: TDprojInfo): string;
begin
  // la tabla de las plataformas lo dice (Lsp.Dproj): eran dos literales aqui
  // (P9 de la revision de la 1.22.0)
  Result := PlataformaParaElMotor(AProyecto.PlataformaPorDefecto);
end;

{ The IDE's global Library Search Path (registry), cleaned: INSTALLED
  COMPONENT packages (third-party) register their paths there, and projects
  rarely repeat them in the .dproj. NUNCA se recortan: son del IDE (la zona
  de biblioteca), no del proyecto. }
function CarpetasDelIde(const AInfo: TRadStudioInfo; const APlat, ACfg: string): TArray<string>;
begin
  // por EL lector de esa lista (Lsp.Discovery.IdePlatformLibraryPaths), con la
  // configuracion de estos ajustes para las entradas con $(Config): aqui habia
  // otra lectura del registro y otra expansion con su propia tabla de macros
  // (regla del paisaje, 18-oct-2026; medido que daban lo mismo en las 13
  // plataformas de esta maquina, sin entradas relativas ni con $(Config))
  Result := IdePlatformLibraryPaths(AInfo, APlat, 'Search Path', ACfg);
end;

function MotorPuedeEnsenar(const APath: string): Boolean;
begin
  Result := LugarDeLecturaDenegado(APath, LUGARES_DEL_MOTOR) = '';
end;

{ Las carpetas del search path del proyecto para ESE build (APlat/ACfg, por
  EL evaluador) como las ve el motor (CleanPathList), partidas en las que
  puede ensenar y las que no. Las de fuera se quedan fuera de los ajustes: el
  motor veia por ellas lo que ninguna tool deja leer (medido el 9-oct-2026: el
  VALOR de una constante de fuera en completion, su firma y su ruta en
  hover). David: "recortar y negar", coherente con LSP-014. }
procedure CarpetasDelProyecto(const AXml, ADprojDir, APlat, ACfg: string;
  const AInfo: TRadStudioInfo; out ADentro, AFuera: TArray<string>);
var
  Vars: TStringList;
begin
  ADentro := nil;
  AFuera := nil;
  Vars := TStringList.Create;
  try
    IdeMacroVars(AInfo, Vars);
    Vars.Values['Platform'] := APlat;
    Vars.Values['Config'] := ACfg;
    for var P in CleanPathList(EffectiveProperty(AXml, 'DCC_UnitSearchPath', APlat, ACfg),
      ADprojDir, Vars) do
      if MotorPuedeEnsenar(P) then
        ADentro := ADentro + [P]
      else
        AFuera := AFuera + [P];
  finally
    Vars.Free;
  end;
end;

function UnitsDeFueraDelProyecto(const ADprojPath: string): TArray<string>;
var
  Dpr, Dproj: string;
begin
  Result := nil;
  if ResolveProjectPair(ADprojPath, Dpr, Dproj) <> '' then
    Exit;
  // CERRADO, no abierto (revisor de P2a, PA-M1; medido, F7b): un .dpr que
  // no se deja leer AHORA (otro proceso lo tiene) sube, y la tool contesta
  // con eso en vez de con nombres; y cada entrada se juzga sola - un try para
  // toda la lista la vaciaba con una ruta que no se deja juzgar ('a|b.pas'),
  // y completion soltaba el VALOR de una constante de la unit de fuera
  for var U in ProjectUnits(Dpr, False) do
  begin
    var Ensenable := False;
    try
      // por EL lector de lo que lista un .dpr: la que no se resuelve, de fuera
      var Ruta := RutaDeInclude(Dpr, U.Include);
      Ensenable := (Ruta <> '') and MotorPuedeEnsenar(Ruta);
    except
      // la ruta que no se deja juzgar cuenta como de fuera
    end;
    if not Ensenable then
      Result := Result + [U.UnitName];
  end;
end;

function NotaDeRecorte(const ASettingsFile: string): string;
var
  M: TMatch;
begin
  Result := '';
  M := TRegEx.Match(TPath.GetFileName(ASettingsFile), RECORTE_PATRON, [roIgnoreCase]);
  if M.Success then
    Result := MsgFmt(SN_LSP_RECORTE_FMT, [StrToIntDef(M.Groups[1].Value, 0)]);
end;

function NotaDeDebajoDelProyecto(const ASettingsFile, AFile: string): string;
begin
  Result := '';
  try
    // la carpeta del proyecto es la que el motor hace suya al cargar los
    // ajustes (ProjectOfSettings); DEBAJO es dentro y no la misma, y la misma
    // es la que cae dentro en los dos sentidos (un lector: DentroDeSiMismo)
    var Proyecto := ProjectOfSettings(ASettingsFile);
    if Proyecto = '' then
      Exit;
    var DeProyecto := TPath.GetDirectoryName(Proyecto);
    var DeUnidad := TPath.GetDirectoryName(TPath.GetFullPath(AFile));
    if DentroDeSiMismo(DeProyecto, DeUnidad) and not DentroDeSiMismo(DeUnidad, DeProyecto) then
      Result := MsgText(SN_LSP_DEBAJO_DEL_PROYECTO);
  except
    Result := '';
  end;
end;

var
  // ONE writer of a settings file at a time. Two first requests on a cold
  // project (a hover and a diagnostics, two agents) both wrote the same file:
  // the second answered SYS-027, "Cannot create file" (measured 2026-09-29).
  // Only the write: what is written is composed outside (revision del
  // 18-oct-2026), and the one that waits finds the same bytes and writes
  // nothing.
  GFabLock: TObject;
  // Si el motor puede ensenar cada carpeta del Browsing Path del IDE (su ruta
  // en minusculas -> si): preguntarlo en cada peticion costaba 26-31 ms por
  // las 58 carpetas, mas que todo lo demas (medido el 18-oct-2026, FabProbe).
  // Es POR CARPETA, no una foto de la lista: una que el operador registre
  // con el servidor en marcha (la zona de biblioteca se recarga desde la
  // 1.21.4) se pregunta la primera vez que aparece, y una que quite deja una
  // entrada que nadie lee. Bajo su propio cerrojo (TMonitor del diccionario).
  GNavegable: TDictionary<string, Boolean>;

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
  // el del IDE, junto al proyecto, o el que fabrico el servidor en su casa
  Root := ObjetoJson(LeeTexto(ASettingsFile, [ltJaula, ltCasa]));
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

function ProyectoDeLosAjustes(const ASettingsFile: string): string;
begin
  Result := ProjectOfSettings(ASettingsFile);
  if (Result <> '') and FileExists(DprojDe(Result)) then
    Result := DprojDe(Result);
end;

{ Una lista ;-separada como la quiere el motor: sin vacios, sin repetidos y
  sin lo que no es un identificador (una macro sin resolver, una ruta:
  gramatica propia, declarada aqui; el juez seria el motor). Los defines y
  los ambitos. Los trozos, por EL troceador de las listas de msbuild
  (Lsp.Dproj.TrozosDeLista; aqui habia otro Split, P8 de la revision de
  Opus 5.5). }
function ListaDeNombres(const ARaw: string): string;
begin
  Result := '';
  for var P in TrozosDeLista(ARaw) do
    if not P.Contains('$(') and not P.Contains('\') and
       not (';' + Result + ';').ToLower.Contains(';' + P.ToLower + ';') then
      if Result = '' then
        Result := P
      else
        Result := Result + ';' + P;
end;

{ Los ajustes de ESTE proyecto (APrefijo, el principio de su nombre) de una
  generacion mas VIEJA que la de ahora -la de un servidor mas nuevo no es de
  este-, con mas de una hora: la regla nueva los deja huerfanos en la casa del
  servidor (revision del 18-oct-2026; el disenador purga asi sus tablas,
  PurgaTablasViejas). Se lista por EntradasDeCarpeta (la de la guarda: lo que
  no se deja listar no se toma por vacio) y se borra por la puerta de borrar,
  con la casa como lugar. Limpiar nunca tumba nada. }
procedure PurgaGeneracionesViejas(const ADir, APrefijo: string);
var
  M: TMatch;
  Edad: TDateTime;
begin
  try
    for var F in EntradasDeCarpeta(ADir) do
    begin
      if not StartsText(APrefijo, TPath.GetFileName(F)) then
        Continue;
      M := TRegEx.Match(TPath.GetFileName(F), GENERACION_PATRON, [roIgnoreCase]);
      if M.Success and (StrToIntDef(M.Groups[1].Value, FABRICATOR_GEN) < FABRICATOR_GEN) and
         FileAge(F, Edad) and (Now - Edad > 1 / 24) then
        BorraFichero(F, ltCasa);
    end;
  except
    // limpiar nunca tumba nada
  end;
end;

function FabricateSettings(const ADprojPath: string;
  const AInfo: TRadStudioInfo): string;
var
  Xml, DprojDir, MainSource, DprPath, Plat, Cfg, Suffix, DllName, Lib: string;
  Defines, Namespaces, Recorte, Marco, Prefijo, Contenido: string;
  UnitPaths, Fuentes, IdePaths, ProjDentro, ProjFuera, Depuracion, Ensenables,
    Navegacion: TArray<string>;
  CacheDir, CacheFile: string;
  Proyecto: TDprojInfo;
  Root, Settings: TJSONObject;
  Browsing: TJSONArray;
  P, PathsJoined, Opts: string;
  Values: TArray<string>;
begin
  if not FileExists(ADprojPath) then
    raise ELspConfigFabricator.Create(MsgFmt(SR_BUILD_DPROJ_NO_EXISTE_FMT, [ADprojPath]));
  if not AInfo.Found then
    raise ELspConfigFabricator.Create(MsgText(SE_BUILD_RAD_STUDIO_INSTALLATION_DISCOVERED));

  DprojDir := TPath.GetDirectoryName(TPath.GetFullPath(ADprojPath));

  // Todo se compone FUERA del cerrojo, que guarda solo la escritura: cogido
  // durante la fabricacion entera -el registro, rsvars.bat, cada carpeta del
  // search path por la jaula, un .dproj en una unidad de red- cada peticion
  // del motor de cada sesion esperaba a la de otra (revision del 18-oct-2026).
  // El .dproj UNA vez para todas las preguntas, y la pareja que compilan el
  // IDE y msbuild sin que nadie pida otra (los selectores del proyecto)
  Xml := LeeTexto(ADprojPath, [ltJaula]);
  Proyecto := InfoDeDproj(Xml);
  Plat := PlataformaDelMotor(Proyecto);
  Cfg := Proyecto.ConfigPorDefecto;
  IdePaths := CarpetasDelIde(AInfo, Plat, Cfg);
  CarpetasDelProyecto(Xml, DprojDir, Plat, Cfg, AInfo, ProjDentro, ProjFuera);
  // lo que se recorta de su search path entra en el nombre (dos sesiones que
  // no ven lo mismo, dos ajustes y dos motores)
  Recorte := '';
  if Length(ProjFuera) > 0 then
    Recorte := Format(RECORTE_FMT, [Length(ProjFuera),
      THashFNV1a32.GetHashValue(string.Join(';', ProjFuera).ToLower)]);

  // Cache: <name>-<pathhash>.delphilsp.json under LOCALAPPDATA, made again
  // EVERY time (the .dproj is not all it depends on: the IDE's library, the
  // jail) and written below only when its bytes change
  CacheDir := ServerCacheDir('configs');
  Prefijo := Format('%s-%x-', [TPath.GetFileNameWithoutExtension(ADprojPath),
    THashFNV1a32.GetHashValue(TPath.GetFullPath(ADprojPath).ToLower)]);
  CacheFile := TPath.Combine(CacheDir, Prefijo + Format('%s%s-g%d.delphilsp.json',
    [AInfo.Version.Replace('.', '_'), Recorte, FABRICATOR_GEN]));

  Values := AllTagValues(Xml, 'MainSource');
  if Length(Values) > 0 then
    MainSource := Values[0]
  else
    // la de al lado por EL inverso (DprDe: el .dpr, o el .dpk de un paquete);
    // se componia <nombre>.dpr a mano y un paquete salia con un .dpr que no hay
    MainSource := TPath.GetFileName(DprDe(ADprojPath));
  // como la lee msbuild, desde la carpeta del .dproj; una que no se resuelve
  // ("X:y" de otra unidad) vale lo que no tenerla: la de al lado
  DprPath := RutaDesde(DprojDir, MainSource);
  if DprPath = '' then
    DprPath := DprDe(ADprojPath);

  // EL sufijo de su compilador, el que HAY en su bin (TRadStudioInfo). Antes
  // se componia del numero BDS, de dos formas en dos sitios, y solo acertaba
  // desde la 13.
  Suffix := AInfo.SufijoCompilador;
  if SameText(Plat, 'Win64') then
    DllName := 'dcc64' + Suffix + '.dll'
  else
    DllName := 'dcc32' + Suffix + '.dll';

  // La biblioteca, como la pone msbuild (CodeGear.Delphi.Targets:132-137): el
  // search path del proyecto delante de la DelphiLibraryPath -la de
  // EnvOptions.proj, que es el Library Path del IDE y empieza por
  // $(BDSLIB)\$(Platform)\release-, y con DCC_DebugDCUs las carpetas de
  // depuracion del IDE (su Debug DCU Path) delante de todo. Medido el
  // 18-oct-2026 (registro y EnvOptions.proj de la 37.0): la de la biblioteca
  // es release tambien en Debug; el $(BDSLIB)\$(PLATFORM)\$(CONFIG) de la
  // linea 43 de los targets es su RESPALDO (Condition DelphiLibraryPath=='')
  // y no lo que compila msbuild. release va aunque el Library Path no la
  // traiga (un servicio sin el HKCU del IDE).
  Lib := PrefijoSinBarra(AInfo.RootDir) + '\lib\' + Plat + '\release';
  Depuracion := nil;
  if EsVerdadDeMsbuild(EffectiveProperty(Xml, 'DCC_DebugDCUs', Plat, Cfg)) then // como msbuild (A33)
    Depuracion := IdePlatformLibraryPaths(AInfo, Plat, 'Debug DCU Path', Cfg);
  UnitPaths := nil;
  for P in Depuracion + ProjDentro + [Lib] + IdePaths do
    if IndexText(P, UnitPaths) < 0 then
      UnitPaths := UnitPaths + [P];
  // las de fuente: las del proyecto que se pueden leer y las del IDE, sin
  // repetir (el orden de siempre: primero el proyecto); las del proyecto que
  // no, fuera
  Fuentes := nil;
  for P in ProjDentro + IdePaths do
    if IndexText(P, Fuentes) < 0 then
      Fuentes := Fuentes + [P];

  // Los defines de ESA configuracion (EL evaluador: DEBUG;$(DCC_Define) es lo
  // de antes mas DEBUG) y el que ponen los targets por su cuenta:
  // FRAMEWORK_$(FrameworkType) si no es None (CodeGear.Delphi.Targets:151)
  Marco := EffectiveProperty(Xml, 'FrameworkType', Plat, Cfg);
  Defines := EffectiveProperty(Xml, 'DCC_Define', Plat, Cfg);
  if (Marco <> '') and not SameText(Marco, 'None') then
    Defines := Defines + ';FRAMEWORK_' + Marco;
  Defines := ListaDeNombres(Defines);

  Namespaces := ListaDeNombres(EffectiveProperty(Xml, 'DCC_Namespace', Plat, Cfg));
  if Namespaces = '' then
    Namespaces := DEFAULT_NAMESPACES;

  PathsJoined := string.Join(';', UnitPaths);
  Opts := '--no-config -A' + STANDARD_ALIASES;
  if Defines <> '' then
    Opts := Opts + ' -D' + Defines;
  Opts := Opts + ' -NS' + Namespaces + ';';
  Opts := Opts + Format(' -U"%s" -O"%s" -R"%s" -I"%s"',
    [PathsJoined, PathsJoined, PathsJoined, PathsJoined]);

  // Las carpetas de navegacion (el fuente que el motor ensena de lo que solo
  // esta compilado): las del IDE, su Browsing Path del registro (EL lector,
  // Lsp.Discovery), y las del search path. Era una lista de 14 subcarpetas a
  // mano (regla 6; el IDE tiene 58, medido el 17-oct-2026). De las del IDE,
  // solo las de sus lugares y su biblioteca, que el motor puede ensenar:
  // recortar y negar, como las del proyecto. Sin la jaula, que es de cada
  // sesion: el nombre de los ajustes no la lleva y dos sesiones se pisarian
  // el fichero. Medido el 18-oct-2026 en esta maquina: 0 de 58 fuera.
  // El cerrojo, solo para el diccionario: el juicio de cada carpeta (rutas
  // reales: una de la biblioteca en red con el NAS caido espera al timeout)
  // va FUERA, o todas las sesiones esperarian detras de esa (lectura del diff
  // propio, 18-oct-2026). Dos que la juzguen a la vez dicen lo mismo.
  Ensenables := nil;
  for P in IdePlatformLibraryPaths(AInfo, Plat, 'Browsing Path') do
  begin
    var Ensena, Sabido: Boolean;
    System.TMonitor.Enter(GNavegable);
    try
      Sabido := GNavegable.TryGetValue(P.ToLower, Ensena);
    finally
      System.TMonitor.Exit(GNavegable);
    end;
    if not Sabido then
    begin
      Ensena := LugarDeLecturaDenegado(P, [ltIde, ltBiblioteca]) = '';
      System.TMonitor.Enter(GNavegable);
      try
        GNavegable.AddOrSetValue(P.ToLower, Ensena);
      finally
        System.TMonitor.Exit(GNavegable);
      end;
    end;
    if Ensena then
      Ensenables := Ensenables + [P];
  end;
  Navegacion := nil;
  for P in Ensenables + Fuentes do
    if (IndexText(P, Navegacion) < 0) and TDirectory.Exists(P) then
      Navegacion := Navegacion + [P];

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
    for P in Navegacion do
      Browsing.Add(TLspClient.PathToUri(P));
    Contenido := Root.Format(1);
  finally
    Root.Free;
  end;

  // Whole or not at all, ONE writer at a time: an engine reads this file the
  // moment it is named to it, and another thread may be reading it. The same
  // bytes are not written again (EscribeBytes): its stamp moves only when it
  // changes, which is how Lsp.Session knows to give it again to a running
  // engine.
  System.TMonitor.Enter(GFabLock);
  try
    CrearCarpeta(CacheDir);
    EscribeEnCasaDelServidor(CacheFile, Contenido);
    PurgaGeneracionesViejas(CacheDir, Prefijo);
    PurgaIntermediosViejos(CacheDir); // los de un escritor que murio a medias
  finally
    System.TMonitor.Exit(GFabLock);
  end;
  Result := CacheFile;
end;

initialization
  GFabLock := TObject.Create;
  GNavegable := TDictionary<string, Boolean>.Create;

finalization
  GNavegable.Free;
  GFabLock.Free;

end.
