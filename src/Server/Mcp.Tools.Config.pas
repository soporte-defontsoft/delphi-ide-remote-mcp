unit Mcp.Tools.Config;

{ delphi_config: see and manage a project's build configurations and target
  platforms - the "which configuration do I want to build" question.

  - view (read-only): framework (VCL/FMX/console), configurations (Debug,
    Release, custom), and every platform with whether it is enabled, whether
    THIS project can target it (VCL is Windows-only), and whether it needs a
    remote PAServer profile.
  - add-platform (read-write): enable a platform in the .dproj <Platforms>
    block - a CURATED edit that touches only that block, never the rest of the
    MSBuild structure. Refuses a platform the framework cannot target.

  Reads the .dproj through the shared Lsp.Dproj parser (no second parser) and
  writes it through Lsp.Patch (encoding-preserving, atomic, auto-backup). }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts,
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

const
  { El section que publica el esquema por defecto: el mismo valor en el
    atributo y en la regla de "lo que no va" (que no lo cuenta como enviado). }
  CFG_SECTION_POR_DEFECTO = 'summary';

type
  TDelphiConfigParams = class
  private
    FProject: string;
    FCommand: string;
    FPlatform: string;
    FSdk: string;
    FProfile: string;
    FOutput: string;
    FPath: string;
    FPaths: string;
    FRemoteDir: string;
    FSection: string;
    FVersion: string;
    FInclude: Boolean;
    FRequires: string;
    FConfig: string;
    FName: string;
    FValue: string;
  public
    [SchemaDescription(SP_CFG_PROJECT)]
    [Required]
    [RutaDelServidor]
    property Project: string read FProject write FProject;
    [SchemaDescription(SP_CFG_COMMAND)]
    [SchemaDefault('view')]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_CFG_PLATFORM)]
    property Platform: string read FPlatform write FPlatform;
    [SchemaDescription(SP_CONFIG_SDK)]
    property Sdk: string read FSdk write FSdk;
    [SchemaDescription(SP_CONFIG_PROFILE)]
    property Profile: string read FProfile write FProfile;
    // Ruta NUESTRA en sus tres usos: add-unit la pasa por PathDenied, y
    // search/deploy por ReadPathDenied (que ya perdona la zona de
    // biblioteca, su destino legitimo). Se quedo sin marca en la primera
    // pasada y el censo salio 37+2 cuando es 39+2 (auditoria 2026-09-21).
    [SchemaDescription(SP_CONFIG_PATH)]
    [RutaDelServidor]
    [RutaRelativa] // relativa al proyecto, o una macro del IDE ($(BDS)...)
    // ...y en los remove-* es la ENTRADA que se quita, tal como la lista el
    // proyecto: ni se lee ni se escribe, asi que el suelo no la juzga (una de
    // fuera, que BUILD-050 pide quitar, se quita; 21-oct-2026)
    [NombreSiComando('remove-unit,remove-searchpath,remove-project')]
    property Path: string read FPath write FPath;
    // VARIAS carpetas de add/remove-searchpath en una llamada (1.21.4), una
    // LISTA como paths de delphi_git: la jaula juzga cada una, y en
    // remove-searchpath son las entradas que se quitan, como path
    [SchemaDescription(SP_CONFIG_PATHS)]
    [JsonComoTexto('string')]
    [RutaDelServidor]
    [RutaRelativa]
    [NombreSiComando('remove-searchpath')]
    property Paths: string read FPaths write FPaths;
    [SchemaDescription(SP_CONFIG_SECTION)]
    [SchemaDefault(CFG_SECTION_POR_DEFECTO)]
    property Section: string read FSection write FSection;
    // SIN marca, y es una de las dos unicas excepciones de todo el contrato:
    // esta carpeta esta EN LA MAQUINA DESTINO. Comprobarla contra nuestra
    // jaula seria rechazar una llamada correcta.
    [SchemaDescription(SP_CONFIG_REMOTEDIR)]
    property RemoteDir: string read FRemoteDir write FRemoteDir;
    [SchemaDescription(SP_CONFIG_VERSION)]
    property Version: string read FVersion write FVersion;
    [SchemaDescription(SP_CONFIG_INCLUDE)]
    property Include: Boolean read FInclude write FInclude;
    [SchemaDescription(SP_CFG_OUTPUT)]
    property Output: string read FOutput write FOutput;
    [SchemaDescription(SP_CFG_REQUIRES)]
    property Requires: string read FRequires write FRequires;
    [SchemaDescription(SP_CFG_CONFIG)]
    property Config: string read FConfig write FConfig;
    // set-property / remove-property / get-property (1.22.0): UNA propiedad
    // del .dproj por su nombre, en el grupo del build que digan platform y
    // config. El nombre solo elige (lo que no es una opcion se niega) y el
    // valor lo juzga la puerta del build cuando ese build lo lea
    [SchemaDescription(SP_CFG_NAME)]
    property Name: string read FName write FName;
    [SchemaDescription(SP_CFG_VALUE)]
    property Value: string read FValue write FValue;
  end;

  TDelphiConfigTool = class(TMCPToolBase<TDelphiConfigParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiConfigParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.JSON,
  System.IOUtils,
  System.StrUtils,
  System.Classes,
  System.Generics.Collections,
  System.RegularExpressions,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.Discovery,
  Lsp.Dproj,
  Lsp.BuildRunner,
  Lsp.ProjectUnits,
  Lsp.Patch,
  Lsp.Regex,
  Lsp.TodoONada,
  Lsp.Rutas,
  Lsp.Json,          // ListaDeTextos: paths es una LISTA, como en delphi_git
  Lsp.DesignerMeta,  // MetaTable: la tabla que juzga la raiz de un add-unit
  Lsp.DesignerForma; // DesignersDeUnidad, EsDesignerFmx: de que marco es

constructor TDelphiConfigTool.Create;
begin
  inherited;
  FName := 'delphi_config';
  FDescription := SD_CFG_CONFIG;
end;

procedure AddSearchPathsView(const AXml: string; AReturn: TJSONObject); forward;
procedure AddDeployFilesView(const ADproj: string; AReturn: TJSONObject); forward;

{ Un Deploy de APlatform necesita un perfil de PAServer: las remotas que
  despliegan por el (Android no: su .apk lo instala delphi_adb; y view decia
  needsProfileForDeploy=true con "Android takes no profile" al lado). }
function PlatformNeedsProfile(const APlatform: string): Boolean;
begin
  Result := not IsLocalPlatform(APlatform) and (SistemaDelPAServer(APlatform) <> spDesconocido);
end;

{ Lo que es un .groupproj: sus proyectos (<Projects Include>), por el lector
  de atributos de la casa (Lsp.Dproj.AllTagAttr), con la ruta absoluta y si
  esta - solo si la sesion puede leer ahi: de fuera no se dice ni que
  existe. }
function ViewGroup(const AGroup: string): string;
var
  O, E: TJSONObject;
  Arr: TJSONArray;
  Lista: TArray<string>;
  Dir, Incl, Abs: string;
  Faltan: Integer;
begin
  try
    Lista := ProyectosDeGrupo(AGroup); // EL lector de grupos (Lsp.ProjectUnits)
  except
    on E: Exception do
      Exit(MsgEnvuelve(SR_CONFIG_GROUP_READ_FMT, E.Message, [AGroup, E.Message]));
  end;
  Dir := TPath.GetDirectoryName(AGroup);
  Faltan := 0;
  O := TJSONObject.Create;
  try
    O.AddPair('group', AGroup);
    Arr := TJSONArray.Create;
    O.AddPair('projects', Arr);
    for Incl in Lista do
    begin
      E := TJSONObject.Create;
      Arr.Add(E);
      E.AddPair('include', Incl);
      try
        Abs := TPath.GetFullPath(TPath.Combine(Dir, Incl));
      except
        Abs := '';
      end;
      if (Abs <> '') and (ReadPathDenied(Abs) = '') then
      begin
        E.AddPair('path', Abs);
        E.AddPair('exists', TJSONBool.Create(TFile.Exists(Abs)));
        if not TFile.Exists(Abs) then
          Inc(Faltan);
      end
      else
        E.AddPair('outsideWorkspace', TJSONBool.Create(True));
    end;
    O.AddPair('note', MsgFmt(SN_CONFIG_GROUP_VIEW_FMT, [Arr.Count, Faltan]));
    Result := O.ToJSON;
  finally
    O.Free;
  end;
end;

function ViewConfig(const ADproj, ASection: string): string;
var
  Info: TDprojInfo;
  Return: TJSONObject;
  Cfgs, Plats, Remotos: TJSONArray;
  C, Reason: string;
  P: TDprojPlatform;
  Obj: TJSONObject;
  Sec, Xml: string;
  Rad: TRadStudioInfo;
  RadVisto: Boolean;

  { Con que SDK y que PAServer compila y despliega ESA plataforma, y de donde
    sale cada cosa. Faltaba: view ensenaba el default del IDE y los perfiles
    globales, y el agente tenia que deducir lo que el proyecto fija (prueba
    de campo de hermes, 2026-09-21). Inversa de set-sdk / set-profile. }
  procedure PonDestino(AObj: TJSONObject; const APlat: string);
  var
    V, Cfg: string;
  begin
    if Xml = '' then
      Xml := LeeTexto(ADproj, [ltJaula]);
    if not RadVisto then
    begin
      Rad := DiscoverRadStudio;
      RadVisto := True;
    end;
    // lo que lee el build por defecto de esa plataforma (la config que el
    // proyecto compila por defecto), con el lector del build
    Cfg := InfoDeDproj(Xml).ConfigPorDefecto;
    V := EffectiveProperty(Xml, 'PlatformSDK', APlat, Cfg);
    // valores CORTOS (project | ide-default | none): cinco destinos con la
    // explicacion repetida en cada uno hacian del resumen un tocho; la
    // explicacion va UNA vez, en remoteTargetsNote
    if V <> '' then
    begin
      AObj.AddPair('sdk', V);
      AObj.AddPair('sdkSource', 'project');
    end
    else
    begin
      V := SdkPorDefectoDelIde(Rad.Version, APlat);
      AObj.AddPair('sdk', V);
      if V <> '' then
        AObj.AddPair('sdkSource', 'ide-default')
      else
        AObj.AddPair('sdkSource', 'none');
    end;
    // el PAServer solo existe en las plataformas que despliegan por el:
    // Android va por adb y no tiene perfil que fijar
    if SistemaDelPAServer(APlat) = spDesconocido then
      Exit;
    V := EffectiveProperty(Xml, 'Profile', APlat, Cfg);
    AObj.AddPair('profile', V);
    if V <> '' then
      AObj.AddPair('profileSource', 'project')
    else
      AObj.AddPair('profileSource', 'none');
  end;

begin
  Xml := '';
  RadVisto := False;
  Sec := ASection.Trim.ToLower;
  if Sec = '' then
    Sec := 'summary';
  if not MatchText(Sec, ['summary', 'platforms', 'searchpaths', 'deploy',
    'units', 'all']) then
    Exit(MsgText(SR_CFG_SECTION_DEBE_SER_SUMMARY));
  // A bare .dpr with no .dproj beside it: the units CAN be read (they are in
  // the .dpr itself) but the framework, the platforms and the configurations
  // cannot - they live in the .dproj. Answering with all of them empty plus
  // a cheerful crossPlatform "yes" was an answer shaped like knowledge that
  // was not (field round 8). Say what is readable, and say what is not.
  if SameText(TPath.GetExtension(ADproj), '.dpr') then
  begin
    Return := TJSONObject.Create;
    try
      Return.AddPair('project', ADproj);
      Return.AddPair('hasDproj', TJSONBool.Create(False));
      AddUnitsView(ADproj, Return);
      Return.AddPair('note', MsgText(SN_CONFIG_DPR_ONLY));
      Exit(Return.ToJSON);
    finally
      Return.Free;
    end;
  end;
  Info := ReadDproj(ADproj);
  Return := TJSONObject.Create;
  try
    Return.AddPair('project', ADproj);
    if (Sec = 'summary') or (Sec = 'all') then
    begin
      Return.AddPair('frameworkType', Info.FrameworkType);
      Return.AddPair('appType', Info.AppType);
      if SameText(Info.FrameworkType, 'VCL') then
        Return.AddPair('crossPlatform', MsgText(SF_CFG_NO_VCL_WINDOWS_ONLY))
      else
        Return.AddPair('crossPlatform', MsgText(SF_CFG_YES_FMX_CONSOLE_TARGET));
    end;
    if (Sec = 'summary') or (Sec = 'all') or (Sec = 'platforms') then
    begin
      Cfgs := TJSONArray.Create;
      Return.AddPair('configurations', Cfgs);
      for C in Info.Configs do
        Cfgs.Add(C);
      // la que delphi_build y delphi_test compilan sin platform=, con el MISMO
      // lector: no habia forma de saberla sin compilar (Hermes, validacion de
      // la 1.16.0); y la configuracion, igual (set-active las cambia)
      Return.AddPair('defaultPlatform', Info.PlataformaPorDefecto);
      Return.AddPair('defaultConfig', Info.ConfigPorDefecto);
    end;
    if (Sec = 'all') or (Sec = 'platforms') then
    begin
      Plats := TJSONArray.Create;
      Return.AddPair('platforms', Plats);
      for P in Info.Platforms do
      begin
        Obj := TJSONObject.Create;
        Plats.AddElement(Obj);
        Obj.AddPair('name', P.Name);
        Obj.AddPair('enabled', TJSONBool.Create(P.Enabled));
        Obj.AddPair('canTarget', TJSONBool.Create(Info.CanTarget(P.Name, Reason)));
        if not Info.CanTarget(P.Name, Reason) then
          Obj.AddPair('reason', Reason);
        // One flag asked two questions and small models heard "a Build
        // needs a profile" (hermes' blind eval, 2026-08-26): building for a
        // remote platform is LOCAL against the SDK; the profile is only for
        // shipping. Two names, two questions.
        Obj.AddPair('needsSDKForBuild', TJSONBool.Create(not IsLocalPlatform(P.Name)));
        Obj.AddPair('needsProfileForDeploy', TJSONBool.Create(PlatformNeedsProfile(P.Name)));
        if not IsLocalPlatform(P.Name) then
          PonDestino(Obj, P.Name);
      end;
      Return.AddPair('remoteTargetsNote', MsgText(SN_CONFIG_REMOTE_NOTE));
    end
    else if Sec = 'summary' then
    begin
      // enabled platforms by name; state and reasons are one section= away
      Plats := TJSONArray.Create;
      Return.AddPair('platformsEnabled', Plats);
      var Disabled := 0;
      for P in Info.Platforms do
        if P.Enabled then
          Plats.Add(P.Name)
        else
          Inc(Disabled);
      if Disabled > 0 then
        Return.AddPair('platformsDisabled', TJSONNumber.Create(Disabled));
      // las remotas ACTIVAS, con su SDK y su PAServer: es lo que decide con
      // que se compila y a donde se despliega, y no estaba en ningun sitio
      Remotos := TJSONArray.Create;
      Return.AddPair('remoteTargets', Remotos);
      for P in Info.Platforms do
        if P.Enabled and not IsLocalPlatform(P.Name) then
        begin
          Obj := TJSONObject.Create;
          Remotos.AddElement(Obj);
          Obj.AddPair('platform', P.Name);
          PonDestino(Obj, P.Name);
        end;
      Return.AddPair('remoteTargetsNote', MsgText(SN_CONFIG_REMOTE_NOTE));
    end;
    if (Sec = 'all') or (Sec = 'searchpaths') then
      AddSearchPathsView(LeeTexto(ADproj, [ltJaula]), Return);
    if (Sec = 'all') or (Sec = 'deploy') then
      AddDeployFilesView(ADproj, Return);
    if (Sec = 'all') or (Sec = 'units') then
      AddUnitsView(ADproj, Return);
    if Sec = 'summary' then
    begin
      // Counts only - the detail of each area is one section= away. The old
      // all-in-one view measured 11.7k chars on a real project (hermes,
      // release audit 2026-08-26): it drowned small models before they had
      // done anything with it.
      var Tmp := TJSONObject.Create;
      try
        AddSearchPathsView(LeeTexto(ADproj, [ltJaula]), Tmp);
        AddDeployFilesView(ADproj, Tmp);
        AddUnitsView(ADproj, Tmp);
        var Counts := TJSONObject.Create;
        Return.AddPair('counts', Counts);
        var N := 0;
        var SPObj := Tmp.GetValue('searchPaths');
        if SPObj is TJSONObject then
          for var Pair in TJSONObject(SPObj) do
            if Pair.JsonValue is TJSONArray then
              N := N + TJSONArray(Pair.JsonValue).Count;
        Counts.AddPair('searchPaths', TJSONNumber.Create(N));
        N := 0;
        var DFObj := Tmp.GetValue('deployFiles');
        if DFObj is TJSONObject then
          for var Pair in TJSONObject(DFObj) do
            if Pair.JsonValue is TJSONArray then
              N := N + TJSONArray(Pair.JsonValue).Count;
        Counts.AddPair('deployFiles', TJSONNumber.Create(N));
        N := 0;
        var UArr := Tmp.GetValue('units');
        if UArr is TJSONArray then
          N := TJSONArray(UArr).Count;
        Counts.AddPair('units', TJSONNumber.Create(N));
      finally
        Tmp.Free;
      end;
      Return.AddPair('sections', MsgText(SN_CONFIG_SECTIONS));
    end;
    if (Sec = 'summary') or (Sec = 'all') or (Sec = 'platforms') then
      Return.AddPair('note', MsgText(SN_CFG_BUILD_DELPHI_BUILD_PROJECT));
    Result := Return.ToJSON;
  finally
    Return.Free;
  end;
end;

function AddPlatform(const ADproj, ARawPlatform: string): string;
var
  Info: TDprojInfo;
  Reason, Enc, Xml, Indent, APlatform: string;
  P: TDprojPlatform;
  Bloque: TTramoXml;
begin
  if ARawPlatform.Trim = '' then
    Exit(MsgText(SR_CFG_ADD_PLATFORM_NECESITA_PLATFORM));
  // WHITELIST: a platform name is a fixed, known token. Rejecting anything
  // else makes it impossible to inject XML into the .dproj through this
  // parameter (measured RCE via a crafted <Import> - field round 5, R5-B).
  APlatform := CanonicalPlatform(ARawPlatform);
  if APlatform = '' then
    Exit(MsgFmt(SR_CONFIG_SDK_PLATFORM_FMT, [ARawPlatform.Trim, KnownPlatformsList]));
  Info := ReadDproj(ADproj);
  if Info.FrameworkType = '' then
    Exit(MsgText(SR_CFG_PUEDO_LEER_FRAMEWORK_DPROJ));
  if not Info.CanTarget(APlatform, Reason) then
    Exit(MsgEnvuelve(SR_RECHAZADO_FMT, Reason));
  for P in Info.Platforms do
    if SameText(P.Name, APlatform) then
    begin
      if P.Enabled then
        Exit(MsgFmt(SN_CFG_PLATAFORMA_ESTA_HABILITADA_PROYECTO_FMT, [APlatform, APlatform]));
      Break;
    end;

  Xml := PatchLoadText(ADproj, Enc);
  // Enable an existing-but-disabled platform: flip its value to True, en su
  // sitio (EL lector del bloque: era un Pos de '<Platform value="X">' con las
  // comillas dobles y el value el primero)
  for var D in PlataformasDelBloque(Xml) do
    if SameText(D.Nombre, APlatform) then
    begin
      Xml := Copy(Xml, 1, D.Tramo.Ini - 1) + 'True' + Copy(Xml, D.Tramo.Fin, MaxInt);
      PatchSaveConSuSalto(ADproj, Xml, Enc);
      Exit(MsgFmt(SN_CFG_HABILITADA_PLATAFORMA_ESTABA_DECLARAD_FMT, [APlatform]));
    end;

  // Insert a new <Platform value="X">True</Platform> before </Platforms>,
  // copying the indentation of the existing entries.
  if not BloqueDePlataformas(Xml, Bloque) then
    Exit(MsgText(SR_CFG_NO_ENCUENTRO_BLOQUE_PLATFORMS));
  // la sangria (solo el blanco) de la linea de </Platforms>, y la entrada
  // nueva JUSTO delante de </Platforms>. Con </Platforms> lo primero de su
  // linea (lo normal) sale igual que antes; con otra etiqueta delante en esa
  // linea (un .dproj editado a mano) se copiaba esa etiqueta como sangria y
  // la entrada nueva podia quedar fuera del bloque (revisor de la 1.15.0)
  Indent := SangriaDeLaLineaEn(Xml, Bloque.Fin);
  Xml := Copy(Xml, 1, Bloque.Fin - 1) + '    ' +
    XmlPlataformaDelBloque(APlatform, True) + sLineBreak + Indent +
    Copy(Xml, Bloque.Fin, MaxInt);
  PatchSaveConSuSalto(ADproj, Xml, Enc);
  Result := MsgFmt(SK_CFG_ANADIDA_PLATAFORMA_DPROJ_FMT, [APlatform, APlatform]);
end;

{ Disable a platform (flip its <Platform value="X">True</Platform> to False).
  Reversible and non-destructive - the safe inverse of add-platform. }
function RemovePlatform(const ADproj, ARawPlatform: string): string;
var
  Enc, Xml, APlatform: string;
  Plats: TArray<TPlataformaDelBloque>;
  Activas: Integer;
begin
  APlatform := CanonicalPlatform(ARawPlatform);
  if APlatform = '' then
    Exit(MsgFmt(SR_CFG_PLATAFORMA_DELPHI_VALIDA_FMT, [ARawPlatform.Trim]));
  Xml := PatchLoadText(ADproj, Enc);
  // EL lector del bloque, el de ReadDproj y add-platform: eran un Pos de
  // '<Platform value="X">' y una regex para contar las activas
  Plats := PlataformasDelBloque(Xml);
  Activas := 0;
  for var D in Plats do
    if D.Activa then
      Inc(Activas);
  for var D in Plats do
    if SameText(D.Nombre, APlatform) then
    begin
      // Idempotence, like add-platform already had: repeating the call used to
      // answer "DESHABILITADA" again and take a backup of a no-op, filling the
      // trash with identical copies of an unchanged .dproj (field round 8).
      if not D.Activa then
        Exit(MsgFmt(SN_CONFIG_PLAT_ALREADY_FMT, [APlatform]));
      // ...and never leave a project with nothing to build for. Three calls in a
      // row used to disable every platform, and the next delphi_build compiled
      // anyway without a word, so nothing ever pointed back here.
      if Activas <= 1 then
        Exit(MsgFmt(SR_CONFIG_PLAT_LAST_FMT, [APlatform]));
      Xml := Copy(Xml, 1, D.Tramo.Ini - 1) + 'False' + Copy(Xml, D.Tramo.Fin, MaxInt);
      PatchSaveConSuSalto(ADproj, Xml, Enc); // backs up the .dproj to __delphi-patch first
      Exit(MsgFmt(SN_CFG_DESHABILITADA_PLATAFORMA_QUEDA_DECLAR_FMT, [APlatform]));
    end;
  Result := MsgFmt(SN_CFG_PLATAFORMA_ESTA_DECLARADA_PROYECTO_FMT, [APlatform]);
end;

{ ValidOutputFolder (la regla de "carpeta relativa al proyecto, apta para
  escribirse en un .dproj") vive ahora en Lsp.Dproj: delphi_create necesita
  la misma para sus subcarpetas, y una regla asi no se escribe dos veces. }
{ "valor in the group X" / "valor in a group with no condition": la pieza de
  LoQueHabia (set-output) y de DondeEsta (get-property). }
function ValorEnGrupo(const AValor, AGrupo: string): string;
var
  Valor: string;
begin
  Valor := IfThen(AValor = '', MsgText(SF_CFG_SIN_DEFINIR), AValor);
  if AGrupo.Trim = '' then
    Result := MsgFmt(SF_CFG_VALOR_EN_GRUPO_SIN_CONDICION_FMT, [Valor])
  else
    Result := MsgFmt(SF_CFG_VALOR_EN_GRUPO_FMT, [Valor, AGrupo]);
end;

{ El "before" de CFG-081: el valor que tenia; si estaba en mas de un grupo, o
  en uno que no es el base, cada uno con su grupo - una config con su propia
  carpeta que set-output ha reescrito se dice, no se calla. }
function LoQueHabia(const ACambios: TArray<TValorReescrito>): string;
var
  Trozos: TArray<string>;
begin
  if Length(ACambios) = 0 then
    Exit(MsgText(SF_CFG_SIN_DEFINIR));
  if (Length(ACambios) = 1) and ACambios[0].EnBase and (ACambios[0].Antes <> '') then
    Exit(ACambios[0].Antes);
  Trozos := [];
  for var C in ACambios do
    Trozos := Trozos + [ValorEnGrupo(C.Antes, C.Grupo)];
  Result := string.Join('; ', Trozos);
end;

{ Put every build artifact of the project under one folder (default Compiled),
  matching the common RAD Studio convention:
    DCC_ExeOutput = .\<folder>\$(Platform)\$(Config)
    DCC_DcuOutput = .\<folder>\Dcu\$(Platform)\$(Config)
  in the base PropertyGroup AND in every group that sets its own
  (FijaPropiedadParaTodos); the .dproj is backed up. }
function SetOutput(const ADproj, ARawFolder: string): string;
var
  Enc, Xml, Clean, ExeInner, DcuInner: string;
  Exes, Dcus: TArray<TValorReescrito>;
  Restore: Boolean;
begin
  Restore := SameText(ARawFolder.Trim, 'default') or SameText(ARawFolder.Trim, 'reset');
  if Restore then
  begin
    Clean := MsgText(SF_CFG_RAD_STUDIO_DEFAULT);
    ExeInner := IDE_OUTPUT_DEFAULT; // lo que escribe el IDE en un proyecto nuevo (un literal, Lsp.Dproj)
    DcuInner := IDE_OUTPUT_DEFAULT + '\dcu';
  end
  else
  begin
    if ARawFolder.Trim = '' then
      Clean := 'Compiled' // sensible default
    else if not ValidOutputFolder(ARawFolder, Clean) then
      // NOT echoing what was sent: whatever comes back goes through the
        // drive mask, so writing C:\Temp\Salida got answered about
        // "srvc:\Temp\Salida" and read like a different error entirely
        // (field round 8). Say the RULE instead of the value.
      Exit(MsgText(SR_CONFIG_OUTPUT_INVALID));
    ExeInner := '.\' + Clean + '\$(Platform)\$(Config)';
    DcuInner := '.\' + Clean + '\Dcu\$(Platform)\$(Config)';
  end;

  Xml := PatchLoadText(ADproj, Enc);
  // TODAS las que haya, en el grupo que sea: una config con su propia carpeta
  // se quedaba con ella y la respuesta decia lo contrario (D4, 1.20.1). La
  // Dcu primero: cada una que falte se escribe al principio del grupo base, y
  // asi la Exe queda delante, como antes. Si una falla no se guarda nada.
  if not FijaPropiedadParaTodos(Xml, 'DCC_DcuOutput', DcuInner, Dcus) or
     not FijaPropiedadParaTodos(Xml, 'DCC_ExeOutput', ExeInner, Exes) then
    Exit(MsgText(SR_CFG_NO_ENCUENTRO_PROPERTYGROUP_BASE));

  PatchSaveConSuSalto(ADproj, Xml, Enc); // backs up the .dproj to __delphi-patch first
  Result := MsgFmt(SN_CFG_SALIDA_BINARIOS_FIJADA_AHORA_FMT,
    [Clean, sLineBreak, ExeInner, LoQueHabia(Exes),
     sLineBreak, DcuInner, LoQueHabia(Dcus), sLineBreak]);
end;

{ ---- unit search paths ---------------------------------------------------
  The IDE's Project Options > Search path, per platform. Field 2026-08-21: a
  real FMX app (41 units) built for Linux64 except ONE unit - the installed
  component's folder was registered in the IDE's library path for Win/Android
  only, and a platform added to a project inherits no search path from the
  others. The .dproj had NO DCC_UnitSearchPath and NO Base_Linux64 groups at
  all (add-platform only touches <Platforms>), so the edit must create the
  platform's property groups exactly as the IDE lays them out:

    <PropertyGroup Condition="('$(Platform)'=='X' and '$(Base)'=='true') or '$(Base_X)'!=''">
        <Base_X>true</Base_X>   <CfgParent>Base</CfgParent>   <Base>true</Base>
    </PropertyGroup>                                 (the DEFINER, after its siblings)
    <PropertyGroup Condition="'$(Base_X)'!=''">
        <DCC_UnitSearchPath>path;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>
    </PropertyGroup>                                 (the VALUES, after the Base values)

  MSBuild evaluates property groups in order, which is why the definer sits
  before the values and the values after the base values (so the macro
  $(DCC_UnitSearchPath) picks up the base list). Paths are vetted like any
  read: they must resolve (macros expanded with the IDE's own environment
  table) inside the workspace roots or the read-only library zone, and exist. }

{ Las Condition de los grupos (GroupCondition, DefinerCondition), el grupo de
  un build (GrupoDelBuild; AseguraGrupoDelBuild lo crea con su definidor como
  lo crea el IDE si falta) y EL escritor de una propiedad de un build
  (PonPropiedadDelBuild) viven en Lsp.Dproj: EL analisis del .dproj, el mismo
  que lee el build. Aqui eran un buscador del grupo letra a letra y otro de
  la etiqueta exacta (D4 de la auditoria de la 1.20.1), y luego
  EnsurePlatformGroups (solo plataforma) y PonPropiedadDePlataforma (set-sdk /
  set-profile), con add-searchpath eligiendo el grupo por su cuenta; en un
  grupo de configuracion no escribia nadie (unificacion de la 1.22.0). }

{ La pareja de un build con nombre ("Win64 Debug"; una mitad sola, ella):
  UN compositor, el de las respuestas y el de la vista de los search paths. }
function ParejaDelBuild(const APlatform, AConfig: string): string;
begin
  Result := (APlatform + ' ' + AConfig).Trim;
end;

{ El nombre de un build en las respuestas: la base, una plataforma, una
  configuracion o la pareja. }
function NombreDelBuild(const APlatform, AConfig: string): string;
begin
  if (APlatform = '') and (AConfig = '') then
    Result := MsgText(SF_CFG_TODAS_PLATAFORMAS_BASE)
  else if AConfig = '' then
    Result := APlatform
  else if APlatform = '' then
    Result := MsgFmt(SF_CFG_BUILD_CONFIG_FMT, [AConfig])
  else
    Result := ParejaDelBuild(APlatform, AConfig);
end;

{ La configuracion ARaw con el nombre que declara el proyecto (una que se
  compila: Base no): lo que teclea el agente solo elige (set-active,
  set-property...). La negativa, con las que declara, si no es ninguna. }
function ConfigDeclarada(const AXml, ARaw: string; out AConfig: string): string;
var
  Validas: string;
begin
  Result := '';
  AConfig := '';
  Validas := '';
  for var N in InfoDeDproj(AXml).Compilables do
  begin
    Validas := IfThen(Validas = '', N, Validas + ', ' + N);
    if SameText(N, ARaw.Trim) then
      AConfig := N;
  end;
  if AConfig = '' then
    Result := MsgFmt(SR_CFG_SET_ACTIVE_CONFIG_FMT, [ARaw.Trim, ONinguno(Validas)]);
end;

{ La negativa de un build sin grupo de valores (AseguraGrupoDelBuild), con
  lo que le falta. }
function MensajeDeFalta(AFalta: TFaltaDeGrupo; const AXml, APlatform, AConfig, ATag: string): string;
begin
  case AFalta of
    fgConfigNoDeclarada:
      Result := MsgFmt(SR_CFG_SET_ACTIVE_CONFIG_FMT,
        [AConfig, ONinguno(string.Join(', ', InfoDeDproj(AXml).Compilables))]);
    fgSinDefinidor:
      Result := MsgFmt(SR_CFG_SIN_DEFINIDOR_FMT, [NombreDelBuild(APlatform, AConfig)]);
    fgSinGrupoBase:
      Result := MsgText(SR_CFG_NO_ENCUENTRO_PROPERTYGROUP_BASE);
    fgInconsistente:
      Result := MsgFmt(SR_CFG_QUEDO_INCONSISTENTE_FMT, [ATag]);
    fgClaveInvalida:
      Result := MsgFmt(SR_CFG_CLAVE_INVALIDA_FMT, [ClaveDelBuild(AXml, AConfig), AConfig]);
  else
    Result := '';
  end;
end;

{ Las rutas de una lista ESCRITA en el .dproj (con sus entidades: el ';' de
  un &amp; no separa), sin blancos ni vacias. Cada una sigue escrita:
  XmlUnescape da su valor. }
function SplitPaths(const AList: string): TArray<string>;
var
  L: TList<string>;
  P: string;
begin
  L := TList<string>.Create;
  try
    for P in TrozosEscritos(AList) do
      if P.Trim <> '' then
        L.Add(P.Trim);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

{ Los caracteres que no caben en una ruta de delphi_config: los de control,
  el ';' (separa listas) y < > " | &, los de una linea de ordenes. Eran
  tres copias del mismo veto (search path, fichero desplegado y su
  carpeta remota). Un & en una ruta que SOLO acaba en el XML del .dproj
  (un search path) ya no rompe nada desde que el escritor escapa
  (XmlElemento): ahi se admite, y una carpeta R&D se puede anadir. Lo que
  VIAJA al destino (el fichero desplegado y su carpeta remota) lo sigue
  vetando: ese camino hasta PAServer no esta medido (David, 26-sep-2026). }
function CaracterVetado(const ARaw: string; AAdmiteAmpersand: Boolean;
  const AMas: TSysCharSet = []): Boolean;
var
  C: Char;
begin
  Result := False;
  for C in ARaw do
    if (Ord(C) < 32) or CharInSet(C, ['<', '>', '"', ';', '|'] + AMas) or
       ((C = '&') and not AAdmiteAmpersand) then
      Exit(True);
end;

{ Una ruta que el agente da en "path" RELATIVA a la carpeta del proyecto, o
  completa: su forma completa en AFull, o la negativa (AEco es lo que el
  agente escribio, para el texto). Estaba escrita a mano tres veces -search
  path, add-deployfile, remove-deployfile- con TPath.IsPathRooted, que da por
  completas "\x", "/x" y "C:x" y las resolvia contra la unidad del PROCESO:
  ni la carpeta del proyecto ni una que el agente nombrase (CFG-109). }
function RutaEnLaCarpeta(const ACarpeta, AValor, AEco: string;
  out AFull: string): string;
var
  P: string;
begin
  AFull := '';
  Result := '';
  P := AValor.Trim;
  try
    if not EsRutaAbsoluta(P) then
    begin
      if TPath.IsPathRooted(P) then
        Exit(MsgFmt(SR_CONFIG_PATH_A_MEDIAS_FMT, [AEco.Trim]));
      P := TPath.Combine(ACarpeta, P);
    end;
    AFull := TPath.GetFullPath(P);
  except
    on E: Exception do
      Exit(MsgFmt(SR_CONFIG_PATH_MACRO_FMT, [AEco.Trim]));
  end;
end;

{ Vets a search path the way every read is vetted: expand the IDE's macros,
  resolve relative to the project, then the read jail (roots + library zone)
  and existence. Returns '' when fine, else the refusal. AShow is the
  resolved path for messages. }
function SearchPathDenied(const ADproj, ARaw: string; out AShow: string): string;
var
  Info: TRadStudioInfo;
  Vars: TStringList;
  Expanded: string;
begin
  AShow := '';
  if ARaw.Trim = '' then
    Exit(MsgText(SR_CONFIG_NEED_PATH));
  if Length(ARaw) > 400 then
    Exit(MsgText(SR_CONFIG_PATH_CHARS));
  if CaracterVetado(ARaw, True) then
    Exit(MsgText(SR_CONFIG_PATH_CHARS));
  Expanded := ARaw.Trim;
  if Expanded.Contains('$(') then
  begin
    Info := DiscoverRadStudio;
    Vars := TStringList.Create;
    try
      // IdeMacroVars, NOT IdeEnvironmentVars: the registry key alone does not
      // carry $(BDS), $(BDSLIB) or $(BDSUSERDIR) - the ones the schema
      // promises and an agent reaches for first. Every $(BDS...) path was
      // refused with a message that recommended $(BDS) (field round 8).
      if Info.Found then
        IdeMacroVars(Info, Vars);
      Expanded := ExpandIdeMacros(Expanded, Vars);
    finally
      Vars.Free;
    end;
    if Expanded.Contains('$(') then
      Exit(MsgFmt(SR_CONFIG_PATH_MACRO_FMT, [ARaw.Trim]));
  end;
  Result := RutaEnLaCarpeta(TPath.GetDirectoryName(ADproj), Expanded, ARaw, AShow);
  if Result <> '' then
    Exit;
  Expanded := AShow;
  Result := ReadPathDenied(Expanded);
  if Result <> '' then
    Exit;
  if not TDirectory.Exists(Expanded) then
    Exit(MsgFmt(SR_CONFIG_PATH_MISSING_FMT, [Expanded]));
end;

{ Las carpetas de add/remove-searchpath: path (una) y paths (una LISTA, como
  en delphi_git), juntas; '' = bien, si no el rechazo (1.21.4: la copia de un
  proyecto real pedia 19 llamadas de add-searchpath platform=Win64, una por
  carpeta de un componente). }
function RutasDeSearchPath(const P: TDelphiConfigParams; out ARutas: TArray<string>): string;
begin
  Result := '';
  if not ListaDeTextos(P.Paths, ARutas) then
    Exit(MsgText(SR_CONFIG_PATHS_NO_ES_LISTA));
  if P.Path.Trim <> '' then
    ARutas := [P.Path] + ARutas;
end;

{ add-searchpath con una o VARIAS carpetas: cada una se juzga ANTES de tocar
  nada y es todo o nada; las que ya estaban se dicen; UNA escritura del
  .dproj, delante de lo que habia, como la de una. Con una sola, lo de siempre
  (CFG-019/020). }
function AddSearchPath(const ADproj, ARawPlatform: string;
  const ARawPaths: TArray<string>): string;
var
  Enc, Xml, Plat, Etiqueta, Compila, Crudo, P: string;
  Shows, Actuales, Nuevos, YaEstaban: TArray<string>;
  G: TGrupoXml;
  Tramos: TArray<TTramoXml>;
  VS: Integer;
  Falta: TFaltaDeGrupo;

  // ya listada en el proyecto, o repetida en la misma llamada
  function Listada(const APath: string): Boolean;
  begin
    for var A in Actuales do
      if SameText(XmlUnescape(A), APath) then
        Exit(True);
    Result := IndexText(APath, Nuevos) >= 0;
  end;

begin
  Plat := '';
  if ARawPlatform.Trim <> '' then
  begin
    Plat := CanonicalPlatform(ARawPlatform);
    if Plat = '' then
      Exit(MsgFmt(SR_CFG_PLATAFORMA_DELPHI_VALIDA_VALIDAS_FMT, [ARawPlatform.Trim, KnownPlatformsList]));
  end;
  if Length(ARawPaths) = 0 then
    Exit(MsgText(SR_CONFIG_NEED_PATH));
  // todas juzgadas antes de tocar nada: todo o nada
  SetLength(Shows, Length(ARawPaths));
  for var I := 0 to High(ARawPaths) do
  begin
    Result := SearchPathDenied(ADproj, ARawPaths[I], Shows[I]);
    if Result <> '' then
    begin
      if Length(ARawPaths) > 1 then
        Result := Result + ' ' + MsgFmt(SN_CONFIG_PATHS_NADA_FMT, [Length(ARawPaths)]);
      Exit;
    end;
  end;
  Etiqueta := NombreDelBuild(Plat, '');

  Xml := PatchLoadText(ADproj, Enc);
  // el grupo de valores de esa plataforma (o la base), creado con su
  // definidor como lo crea el IDE si falta (EL creador, Lsp.Dproj)
  if not AseguraGrupoDelBuild(Xml, Plat, '', G, Falta) then
    Exit(MensajeDeFalta(Falta, Xml, Plat, '', 'DCC_UnitSearchPath'));
  Tramos := TramosEnGrupo(Xml, 'DCC_UnitSearchPath', G);
  Actuales := nil;
  if Length(Tramos) > 0 then
    Actuales := SplitPaths(Copy(Xml, Tramos[0].Ini, Tramos[0].Fin - Tramos[0].Ini));
  Nuevos := nil;
  YaEstaban := nil;
  for var R in ARawPaths do
  begin
    P := R.Trim;
    if Listada(P) then
      YaEstaban := YaEstaban + [P]
    else
      Nuevos := Nuevos + [P];
  end;
  if Length(Nuevos) = 0 then
  begin
    // todas estaban: lo de siempre, una linea por carpeta
    Result := '';
    for P in YaEstaban do
      Result := Result + IfThen(Result = '', '', sLineBreak) +
        MsgFmt(SN_CONFIG_PATH_PRESENT_FMT, [P, Etiqueta]);
    Exit;
  end;
  Crudo := string.Join(';', Nuevos) + ';';
  if Length(Tramos) > 0 then
  begin
    VS := Tramos[0].Ini;
    Xml := Copy(Xml, 1, VS - 1) + XmlEscape(Crudo) + Copy(Xml, VS, MaxInt);
  end
  else
    // al FINAL del grupo, como la pone el IDE (Lsp.Dproj.AnadeAlGrupo); la
    // ponia al principio. (XmlElemento escapa el valor: aqui va crudo)
    AnadeAlGrupo(Xml, G, XmlElemento('DCC_UnitSearchPath', Crudo + '$(DCC_UnitSearchPath)'));
  PatchSaveConSuSalto(ADproj, Xml, Enc); // backs up the .dproj to __delphi-patch first
  // en el grupo base, la que el proyecto compila sin platform= (era Win64 a
  // fuego: el build que se proponia no era el del proyecto)
  Compila := IfThen(Plat = '', InfoDeDproj(Xml).PlataformaPorDefecto, Plat);
  if Length(ARawPaths) = 1 then
    Result := MsgFmt(SN_CONFIG_PATH_ADDED_FMT, [Nuevos[0], Etiqueta, Shows[0], Compila])
  else
    Result := MsgFmt(SN_CONFIG_PATHS_ADDED_FMT, [Length(Nuevos), Etiqueta,
      string.Join(', ', Nuevos), IfThen(Length(YaEstaban) = 0, '',
      MsgFmt(SF_CONFIG_PATHS_YA_ESTABAN_FMT, [string.Join(', ', YaEstaban)])), Compila]);
end;

function DondeEsta(const AXml, ATag: string; const ASoloCon: TArray<string> = nil): string; forward;

{ La entrada de un search path del proyecto es una de las carpetas pedidas:
  como la escribio el agente, sin el escape del XML. LA regla de
  remove-searchpath, y la de los grupos que nombra CFG-022 (DondeEsta). }
function EsEntradaPedida(const AEntrada: string; const APedidas: TArray<string>): Boolean;
begin
  for var R in APedidas do
    if SameText(XmlUnescape(AEntrada), R.Trim) then
      Exit(True);
  Result := False;
end;

{ remove-searchpath con una o VARIAS: las que no estaban se dicen; UNA
  escritura. Con una sola, lo de siempre (CFG-021/022). }
function RemoveSearchPath(const ADproj, ARawPlatform: string;
  const ARawPaths: TArray<string>): string;
var
  Enc, Xml, Plat, Etiqueta, Rest, P: string;
  Quitadas, NoEstaban: TArray<string>;
  G: TGrupoXml;
  Tramos: TArray<TTramoXml>;
  Keep: TList<string>;

  // la entrada del proyecto es una de las pedidas
  function Pedida(const AEntrada: string): Boolean;
  begin
    Result := EsEntradaPedida(AEntrada, ARawPaths);
  end;

begin
  Plat := '';
  if ARawPlatform.Trim <> '' then
  begin
    Plat := CanonicalPlatform(ARawPlatform);
    if Plat = '' then
      Exit(MsgFmt(SR_CFG_PLATAFORMA_DELPHI_VALIDA_FMT, [ARawPlatform.Trim]));
  end;
  if Length(ARawPaths) = 0 then
    Exit(MsgText(SR_CONFIG_NEED_PATH));
  for var R in ARawPaths do
    if R.Trim = '' then
      Exit(MsgText(SR_CONFIG_NEED_PATH));
  Etiqueta := NombreDelBuild(Plat, '');
  Xml := PatchLoadText(ADproj, Enc);
  Tramos := [];
  if GrupoDelBuild(Xml, Plat, '', G) then // EL lector del grupo (Lsp.Dproj)
    Tramos := TramosEnGrupo(Xml, 'DCC_UnitSearchPath', G);
  Quitadas := nil;
  NoEstaban := nil;
  Keep := TList<string>.Create;
  try
    if Length(Tramos) > 0 then
      for P in SplitPaths(Copy(Xml, Tramos[0].Ini, Tramos[0].Fin - Tramos[0].Ini)) do
        if Pedida(P) then
          Quitadas := Quitadas + [XmlUnescape(P)]
        else
          Keep.Add(P);
    for var R in ARawPaths do
      if (IndexText(R.Trim, Quitadas) < 0) and (IndexText(R.Trim, NoEstaban) < 0) then
        NoEstaban := NoEstaban + [R.Trim];
    if Length(Quitadas) = 0 then
    begin
      // ninguna estaba: lo de siempre, una linea por carpeta; y si alguna esta
      // en el search path de OTRO grupo (el de una configuracion, que escribe
      // set-property con config=), donde y con que se quita: este comando solo
      // cambia el de la plataforma (Hermes, dirigido de la 1.22.0: "no esta"
      // le costo dos turnos)
      Result := '';
      for P in NoEstaban do
        Result := Result + IfThen(Result = '', '', sLineBreak) +
          MsgFmt(SN_CONFIG_PATH_ABSENT_FMT, [P, Etiqueta]);
      // ...una ENTRADA de ese search path, con la regla con la que se quita
      // (Pedida): como texto, lib casaba con lib2 o con C:\x\lib\y (revisor
      // Opus de la 1.22.0, H7). Aqui ninguna estaba: las pedidas son NoEstaban.
      // Y se nombran SOLO los grupos que la tienen: salian todos los que tienen
      // search path, el de la plataforma pedida incluido, y el mensaje parecia
      // decir que alli si estaba (dirigido de Opus de la 1.22.1)
      var Donde := DondeEsta(Xml, 'DCC_UnitSearchPath', NoEstaban);
      if Donde <> '' then
        Result := Result + MsgFmt(SF_CONFIG_PATH_EN_OTRO_GRUPO_FMT, [Donde]);
      Exit;
    end;
    Rest := string.Join(';', Keep.ToArray);
  finally
    Keep.Free;
  end;
  if (Rest = '') or SameText(Rest, '$(DCC_UnitSearchPath)') then
    // nothing of ours left: drop the whole element, its line included
    QuitaConSuLinea(Xml, Tramos[0].Abre, Tramos[0].Cierra)
  else
    Xml := Copy(Xml, 1, Tramos[0].Ini - 1) + Rest + Copy(Xml, Tramos[0].Fin, MaxInt);
  PatchSaveConSuSalto(ADproj, Xml, Enc);
  if Length(ARawPaths) = 1 then
    Result := MsgFmt(SN_CONFIG_PATH_REMOVED_FMT, [ARawPaths[0].Trim, Etiqueta])
  else
    Result := MsgFmt(SN_CONFIG_PATHS_REMOVED_FMT, [Length(Quitadas), Etiqueta,
      string.Join(', ', Quitadas), IfThen(Length(NoEstaban) = 0, '',
      MsgFmt(SF_CONFIG_PATHS_NO_ESTABAN_FMT, [string.Join(', ', NoEstaban)]))]);
end;

{ view: the search paths per group, as the .dproj states them (macros kept). }
procedure AddSearchPathsView(const AXml: string; AReturn: TJSONObject);
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  Name, P, Plat, Cfg: string;
  Tramos: TArray<TTramoXml>;
  Any: Boolean;
begin
  Obj := TJSONObject.Create;
  Any := False;
  for var G in GruposDePropiedades(AXml) do
  begin
    // cada grupo de valores de un build, por EL lector inverso de Lsp.Dproj
    // (BuildDelGrupo): la base, una plataforma y, desde la 1.22.0, tambien una
    // configuracion ("Debug") o la pareja ("Win64 Debug"), donde escribe
    // set-property (era una regex propia; luego solo base y plataformas)
    if not BuildDelGrupo(AXml, G.Condicion, Plat, Cfg) then
      Continue;
    if (Plat = '') and (Cfg = '') then
      Name := 'base'
    else
      Name := ParejaDelBuild(Plat, Cfg);
    Tramos := TramosEnGrupo(AXml, 'DCC_UnitSearchPath', G);
    if Length(Tramos) = 0 then
      Continue;
    Arr := TJSONArray.Create;
    for P in SplitPaths(Copy(AXml, Tramos[0].Ini, Tramos[0].Fin - Tramos[0].Ini)) do
      Arr.Add(XmlUnescape(P));
    Obj.AddPair(Name, Arr);
    Any := True;
  end;
  AReturn.AddPair('searchPaths', Obj);
  if not Any then
    AReturn.AddPair('searchPathsNote', MsgText(SN_CONFIG_NO_PATHS));
end;

{ ---- deployment files ---------------------------------------------------
  The IDE's Deployment Manager, per platform: files that must travel with
  the binary - the native library a component loads at runtime (field
  2026-08-22: OBR for FireMonkey is STATIC on Android/iOS but a runtime
  libzbar.so on Linux / .dylib on macOS, and the project's .deployproj had
  no Linux64 entries because it had never been deployed there).

  Entries follow the IDE's own shape, one ItemGroup per platform:
    <ItemGroup Condition="'$(Platform)'=='Linux64'">
        <DeployFile Include="<server path>" Condition="'$(Config)'=='Debug'">
            <RemoteDir>Project\</RemoteDir>  <RemoteName>libzbar.so</RemoteName>
            <DeployClass>File</DeployClass>  <Operation>0</Operation> ...
  One entry per configuration (Debug and Release), as the IDE writes them.
  A project without a manifest gets the standard one generated first
  (EnsureDeployManifest). The file is vetted like any read: workspace or
  library zone, and it must exist. RemoteDir defaults to the project folder
  on the target (next to the binary); on Android a .so defaults to the apk's
  library\lib\<abi>\ folder. }

function DeployProjPath(const ADproj: string): string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(ADproj),
    TPath.GetFileNameWithoutExtension(ADproj) + '.deployproj');
end;

function DefaultRemoteDir(const AProjectName, APlatform, AFile: string): string;
begin
  Result := AProjectName + '\';
  if SameText(TPath.GetExtension(AFile), '.so') then
    Result := Result + CarpetaDeLibreriasDelApk(APlatform); // '' fuera de Android
end;

{ '' = fine; else the refusal. AFull receives the resolved file. }
function DeployFileDenied(const ADproj, ARaw: string; out AFull: string): string;
var
  P: string;
begin
  AFull := '';
  if ARaw.Trim = '' then
    Exit(MsgText(SR_CONFIG_DEPLOY_NEED_PATH));
  if Length(ARaw) > 400 then
    Exit(MsgText(SR_CONFIG_PATH_CHARS));
  if CaracterVetado(ARaw, False) then
      Exit(MsgText(SR_CONFIG_PATH_CHARS));
  Result := RutaEnLaCarpeta(TPath.GetDirectoryName(ADproj), ARaw, ARaw, P);
  if Result <> '' then
    Exit;
  AFull := P;
  Result := ReadPathDenied(P);
  if Result <> '' then
    Exit;
  if TDirectory.Exists(P) then
    Exit(MsgFmt(SR_CONFIG_DEPLOY_NOT_FILE_FMT, [P]));
  if not TFile.Exists(P) then
    Exit(NoEsFichero(P, MsgFmt(SR_CONFIG_DEPLOY_MISSING_FMT, [P])));
end;

function RemoteDirDenied(const ARaw: string): string;
begin
  Result := '';
  if Length(ARaw) > 200 then
    Exit(MsgText(SR_CONFIG_REMOTEDIR_CHARS));
  if CaracterVetado(ARaw, False, [':']) then
    Exit(MsgText(SR_CONFIG_REMOTEDIR_CHARS));
  if ARaw.Contains('..') or ARaw.StartsWith('\') or ARaw.StartsWith('/') then
    Exit(MsgText(SR_CONFIG_REMOTEDIR_CHARS));
end;

{ Every DeployFile element of the manifest whose Include matches AFile
  (case-insensitive) inside an ItemGroup of APlatform: their spans. }
{ Resolve a .deployproj Include the way the IDE reads it: relative entries
  hang off the project folder. Without this, remove-deployfile could not find
  the very entries the server itself had generated (they are relative), and
  add-deployfile could add a second copy of a file already there under the
  other spelling (field round 8). }
function SameDeployFile(const AInclude, ABaseDir, AFullPath: string): Boolean;
var
  Resolved: string;
begin
  Resolved := AInclude.Trim;
  if Resolved = '' then
    Exit(False);
  if not TPath.IsPathRooted(Resolved) then
    Resolved := TPath.Combine(ABaseDir, Resolved);
  try
    Resolved := TPath.GetFullPath(Resolved);
  except
    Exit(SameText(AInclude, AFullPath));
  end;
  Result := SameText(Resolved, AFullPath);
end;

function FindDeployEntries(const AXml, APlatform, AFile, ABaseDir: string): TArray<TPair<Integer, Integer>>;
begin
  // the enclosing ItemGroup decides the platform, and each entry is matched
  // by its Include - por EL analisis: era una regex con el Include primero y
  // "el ultimo <itemgroup antes", y un <DeployFile .../> vacio se comia la
  // entrada siguiente hasta su </DeployFile>
  Result := [];
  for var G in GruposDe(AXml, 'ItemGroup') do
    if SameText(PlataformaDeGrupoDeDespliegue(G.Condicion), APlatform) then
      for var T in TramosEnGrupo(AXml, 'DeployFile', G, True) do
        if SameDeployFile(AtributoDeTramo(AXml, T, 'DeployFile', 'Include'), ABaseDir, AFile) then
          Result := Result + [TPair<Integer, Integer>.Create(T.Abre, T.Cierra - T.Abre)];
end;

function AddDeployFile(const ADproj, ARawPlatform, ARawPath, ARawRemoteDir: string): string;
var
  Plat, Full, RemoteDir, DeployProj, Enc, Xml, Block, Include, BaseDir: string;
  Info: TRadStudioInfo;
  Generated: Boolean;
  ClosePos: Integer;
begin
  Plat := CanonicalPlatform(ARawPlatform);
  if Plat = '' then
    Exit(MsgFmt(SR_CONFIG_DEPLOY_PLATFORM_FMT, [ARawPlatform.Trim]));
  Result := DeployFileDenied(ADproj, ARawPath, Full);
  if Result <> '' then
    Exit;
  RemoteDir := ARawRemoteDir.Trim;
  if RemoteDir = '' then
    RemoteDir := DefaultRemoteDir(TPath.GetFileNameWithoutExtension(ADproj), Plat, Full)
  else
  begin
    Result := RemoteDirDenied(RemoteDir);
    if Result <> '' then
      Exit;
    RemoteDir := RemoteDir.Replace('/', '\');
    if not RemoteDir.EndsWith('\') then
      RemoteDir := RemoteDir + '\';
  end;

  DeployProj := DeployProjPath(ADproj);
  Generated := False;
  if not TFile.Exists(DeployProj) then
  begin
    Info := DiscoverRadStudio;
    if not Info.Found then
      Exit(MsgText(SR_COMPONENTS_MISSING));
    try
      EnsureDeployManifest(ADproj, Plat, Info.RootDir, Generated);
    except
      on E: Exception do
        Exit(MsgEnvuelve(SR_CFG_NO_PUDE_GENERAR_MANIFIESTO_FMT, E.Message));
    end;
    if not TFile.Exists(DeployProj) then
      Exit(NoEsFichero(DeployProj, MsgFmt(SR_CFG_NO_EXISTE_NO_PUDO_GENERAR_FMT, [DeployProj])));
  end;

  Xml := PatchLoadText(DeployProj, Enc);
  if Length(FindDeployEntries(Xml, Plat, Full,
       TPath.GetDirectoryName(TPath.GetFullPath(DeployProj)))) > 0 then
    Exit(MsgFmt(SN_CONFIG_DEPLOY_PRESENT_FMT, [Full, Plat]));
  ClosePos := CierreDelProyecto(Xml);
  if ClosePos = 0 then
    Exit(MsgText(SR_CFG_DEPLOYPROJ_SIN_CIERRE_PROJECT));
  // The IDE writes `UMain.pas`, not `D:\proyectos\x\UMain.pas`: an absolute
  // Include makes the .deployproj stop being portable and stop matching what
  // the IDE itself generates for the same file (field round 8). Relative
  // whenever the file lives under the project; absolute only when it does not.
  Include := Full;
  BaseDir := TPath.GetDirectoryName(TPath.GetFullPath(DeployProj));
  if Full.ToLower.StartsWith(IncludeTrailingPathDelimiter(BaseDir).ToLower) then
    Include := Full.Substring(Length(IncludeTrailingPathDelimiter(BaseDir)));
  // EL escritor del grupo de una plataforma del .deployproj (Lsp.Dproj)
  Block := '    ' + XmlGrupoDeDespliegue(DeployGroupCondition(Plat),
    XmlDeployFile(Include, 'Debug', RemoteDir, TPath.GetFileName(Include), 'File', 0, True) +
    XmlDeployFile(Include, 'Release', RemoteDir, TPath.GetFileName(Include), 'File', 0, True)) + sLineBreak;
  Xml := Copy(Xml, 1, ClosePos - 1) + Block + Copy(Xml, ClosePos, MaxInt);
  PatchSaveConSuSalto(DeployProj, Xml, Enc); // __delphi-patch copy first
  Result := MsgFmt(SN_CONFIG_DEPLOY_ADDED_FMT,
    [Plat, Full, RemoteDir, TPath.GetFileName(Full),
     IfThen(Generated, MsgText(SF_CONFIG_DEPLOY_GENERATED) + ' ', ''), Plat]);
end;

function RemoveDeployFile(const ADproj, ARawPlatform, ARawPath: string): string;
var
  Plat, Full, DeployProj, Enc, Xml: string;
  Spans: TArray<TPair<Integer, Integer>>;
  I: Integer;
begin
  Plat := CanonicalPlatform(ARawPlatform);
  if Plat = '' then
    Exit(MsgFmt(SR_CONFIG_DEPLOY_PLATFORM_FMT, [ARawPlatform.Trim]));
  if ARawPath.Trim = '' then
    Exit(MsgText(SR_CONFIG_DEPLOY_NEED_PATH));
  Result := RutaEnLaCarpeta(TPath.GetDirectoryName(ADproj), ARawPath, ARawPath, Full);
  if Result <> '' then
    Exit;
  DeployProj := DeployProjPath(ADproj);
  if not TFile.Exists(DeployProj) then
    Exit(MsgFmt(SN_CONFIG_DEPLOY_ABSENT_FMT, [Full, Plat]));
  Xml := PatchLoadText(DeployProj, Enc);
  Spans := FindDeployEntries(Xml, Plat, Full,
    TPath.GetDirectoryName(TPath.GetFullPath(DeployProj)));
  if Length(Spans) = 0 then
    Exit(MsgFmt(SN_CONFIG_DEPLOY_ABSENT_FMT, [Full, Plat]));
  // remove from the end so earlier spans stay valid; eat the element's line
  for I := High(Spans) downto 0 do
    QuitaConSuLinea(Xml, Spans[I].Key, Spans[I].Key + Spans[I].Value);
  // an ItemGroup left empty is dropped too (the IDE keeps empty ones, but
  // ours were added by us): the platform's own, '$(Platform)'=='X', with
  // nothing but blanks inside - from the last, so the earlier stay put
  var Grupos := GruposDe(Xml, 'ItemGroup');
  for var K := High(Grupos) downto 0 do
    if (CondicionNormalizada(Grupos[K].Condicion) = CondicionNormalizada(DeployGroupCondition(Plat))) and
       (Copy(Xml, Grupos[K].Ini, Grupos[K].Fin - Grupos[K].Ini).Trim = '') then
      QuitaConSuLinea(Xml, Grupos[K].Abre, Grupos[K].Cierra);
  PatchSaveConSuSalto(DeployProj, Xml, Enc);
  Result := MsgFmt(SN_CONFIG_DEPLOY_REMOVED_FMT, [Full, Plat, Length(Spans)]);
end;

{ view: the deployment entries per platform (Include + RemoteDir), from the
  manifest next to the project - '' when there is none. }
procedure AddDeployFilesView(const ADproj: string; AReturn: TJSONObject);
var
  DeployProj, Xml, Plat: string;
  Obj: TJSONObject;
  Arr: TJSONArray;
begin
  DeployProj := DeployProjPath(ADproj);
  if not TFile.Exists(DeployProj) then
  begin
    AReturn.AddPair('deployFilesNote', MsgText(SN_CONFIG_NO_DEPLOYPROJ));
    Exit;
  end;
  Xml := LeeTexto(DeployProj, [ltJaula]);
  Obj := TJSONObject.Create;
  // el ItemGroup decide la plataforma y cada DeployFile dice su Include, por
  // EL analisis (era una regex con el Include primero y "el ultimo <itemgroup
  // antes", y otra para sacar la plataforma de la Condition)
  for var G in GruposDe(Xml, 'ItemGroup') do
  begin
    Plat := PlataformaDeGrupoDeDespliegue(G.Condicion);
    if Plat = '' then
      Continue;
    for var T in TramosEnGrupo(Xml, 'DeployFile', G, True) do
    begin
      if Obj.GetValue(Plat) = nil then
        Obj.AddPair(Plat, TJSONArray.Create);
      Arr := Obj.GetValue(Plat) as TJSONArray;
      // one line per file (the IDE writes one entry per configuration); un
      // DeployFile sin <RemoteDir> deja el destino vacio (lanzaba "Index out
      // of bounds (1)", el gemelo del de Lsp.BuildRunner, 2026-09-23)
      var Remoto := '';
      for var R in AllTagValues(Copy(Xml, T.Ini, T.Fin - T.Ini), 'RemoteDir') do
      begin
        Remoto := R;
        Break;
      end;
      var Line := AtributoDeTramo(Xml, T, 'DeployFile', 'Include') + ' -> ' + Remoto;
      var Dup := False;
      for var V in Arr do
        if SameText(V.Value, Line) then
        begin
          Dup := True;
          Break;
        end;
      if not Dup then
        Arr.Add(Line);
    end;
  end;
  AReturn.AddPair('deployFiles', Obj);
end;

{ ---- el SDK del proyecto -------------------------------------------------
  En Delphi se registran tantos SDK como haga falta (uno por maquina destino,
  desde 2026-09-20) y **es el PROYECTO el que elige** cual usa - la propiedad
  PlatformSDK, que es la que lee CodeGear.Profiles.Targets. El "por defecto"
  de cada plataforma existe (la entrada en negrita del SDK Manager) pero es un
  ultimo recurso. El servidor ya RESPETABA lo que dijera el proyecto; esto es
  lo que faltaba para poder decirlo. }
{ La VERSION del proyecto: los cuatro numeros del VERSIONINFO de Windows
  (VerInfo_MajorVer/MinorVer/Release/Build) y las claves FileVersion y
  ProductVersion de VerInfo_Keys. Son sitios distintos que tienen que decir lo
  mismo, y el gate de release los compara uno a uno: descuadrarlos es el fallo
  clasico de subir una version a mano.

  Por que CURADA y no por ancla: las dos tools de edicion vetan el .dproj a
  proposito, y con razon - es XML con grupos de propiedades repetidos por
  plataforma y configuracion, donde un ancla como "la linea que dice
  <VerInfo_MinorVer>0</...>" acierta en el grupo equivocado sin avisar. Lo que
  faltaba no era permiso: era la operacion que sabe QUE esta tocando, igual
  que set-sdk. Medido el 2026-09-20: subir de version era lo UNICO del ritual
  de release que obligaba a salir del MCP.

  Lo que NO toca: Android (versionCode/versionName) e iOS (CFBundleVersion).
  Esa numeracion es otra cosa - versionCode es un entero que solo puede subir
  y una tienda lo rechaza si baja -, asi que cambiarla de rebote seria una
  sorpresa, no un favor. }
function SetVersion(const ADproj, ARawVersion: string; AIncluir: Boolean): string;
var
  Enc, Xml, Pedida, Sufijo, Cuatro, AntesNum, AntesKey, Nota, Eol: string;
  Partes, Tags: TArray<string>;
  N: array [0 .. 3] of Integer;
  I: Integer;
  Previo: string;
  SinNumeros: Boolean;

  { Cuantos caracteres del valor de AClave son su numero (los digitos y
    puntos del principio): lo que cambiaba FileVersion=[\d.]*. }
  function Numerico(const AXml: string; const AClave: TClaveDeVersion): Integer;
  begin
    Result := 0;
    while (AClave.Ini + Result < AClave.Fin) and
          CharInSet(AXml[AClave.Ini + Result], ['0'..'9', '.']) do
      Inc(Result);
  end;

  { Si alguna de AClaves es una FileVersion que empieza en [ADesde, AHasta). }
  function ConFileVersion(const AClaves: TArray<TClaveDeVersion>; ADesde, AHasta: Integer): Boolean;
  begin
    for var C in AClaves do
      if SameText(C.Nombre, 'FileVersion') and (C.Ini >= ADesde) and (C.Ini < AHasta) then
        Exit(True);
    Result := False;
  end;

  { Si el proyecto mete la version en sus binarios en alguna configuracion. }
  function IncluyeVersion(const AXml: string): Boolean;
  begin
    for var T in TramosDeEtiqueta(AXml, 'VerInfo_IncludeVerInfo') do
      if SameText(ValorDeTramo(AXml, T).Trim, 'true') then
        Exit(True);
    Result := False;
  end;

begin
  Pedida := ARawVersion.Trim;
  if Pedida = '' then
    Exit(MsgText(SR_CONFIG_VERSION_VACIA));
  Sufijo := '';
  I := Pedida.IndexOf('-');
  if I > 0 then
  begin
    Sufijo := Pedida.Substring(I);
    Pedida := Pedida.Substring(0, I);
  end;
  Partes := Pedida.Split(['.']);
  if (Length(Partes) < 2) or (Length(Partes) > 4) then
    Exit(MsgFmt(SR_CONFIG_VERSION_FORMATO_FMT, [ARawVersion.Trim]));
  for I := 0 to 3 do
    N[I] := 0;
  for I := 0 to High(Partes) do
    if not TryStrToInt(Partes[I].Trim, N[I]) or (N[I] < 0) or (N[I] > 65535) then
      Exit(MsgFmt(SR_CONFIG_VERSION_FORMATO_FMT, [ARawVersion.Trim]));
  Cuatro := Format('%d.%d.%d.%d', [N[0], N[1], N[2], N[3]]);

  Xml := PatchLoadText(ADproj, Enc);
  // por EL analisis del .dproj (los numeros, sus tramos; las claves,
  // ClavesDeVersion): eran siete regex, y las de las claves buscaban
  // FileVersion= en TODO el texto, un evento de build incluido.
  // La version del binario la saca el build de la clave FileVersion (la
  // tarea CreateRcFile; medido el 17-oct-2026: con los numeros a 2.3.4.5 y la
  // clave a 9.8.7.6 el exe sale 9.8.7.6), y los numeros VerInfo_MajorVer...
  // el IDE solo los escribe cuando dejan de ser 1.0.0.0: exigirlos dejaba
  // fuera todo proyecto nuevo del IDE y 284 de los 296 .dproj de los Samples
  // de la 37.0 con la version incluida (Hermes, dirigido de la 1.20.1).
  SinNumeros := Length(TramosDeEtiqueta(Xml, 'VerInfo_MajorVer')) = 0;
  var Claves0 := ClavesDeVersion(Xml);
  if SinNumeros and not ConFileVersion(Claves0, 1, MaxInt) then
    Exit(MsgText(SR_CONFIG_VERSION_SIN_VERINFO));
  Eol := SaltoDominante(Xml); // el salto del fichero, la regla de todos

  // Lo que habia, para poder decirlo: los numeros por un lado y la clave por
  // otro, que es donde se ve si estaban descuadrados.
  AntesNum := '';
  Tags := ['VerInfo_MajorVer', 'VerInfo_MinorVer', 'VerInfo_Release',
    'VerInfo_Build'];
  for I := 0 to 3 do
  begin
    var V := AllTagValues(Xml, Tags[I]);
    if Length(V) > 0 then
      AntesNum := AntesNum + IfThen(AntesNum = '', '', '.') + V[0]
    else
      AntesNum := AntesNum + IfThen(AntesNum = '', '', '.') + '0';
  end;
  AntesKey := MsgText(SF_NINGUNO);
  for var C in Claves0 do
    if SameText(C.Nombre, 'FileVersion') and (Numerico(Xml, C) > 0) then
    begin
      AntesKey := Copy(Xml, C.Ini, Numerico(Xml, C));
      Break;
    end;

  // Sin numeros (un proyecto que nadie subio de 1.0.0.0) lo que tenia es lo
  // que decia la clave, y los cuatro entran en cada grupo que la lleva,
  // delante de su VerInfo_Keys: juntos, como los deja el IDE al subir la
  // version (el .dproj de este servidor, en Base) y como escribe su propia
  // tarea de autoincremento (VerInfo_Build y VerInfo_Keys en un grupo). Del
  // ultimo grupo al primero, para que los de delante no se muevan.
  if SinNumeros then
  begin
    AntesNum := AntesKey;
    var Grupos := GruposDePropiedades(Xml);
    for var G := High(Grupos) downto 0 do
      for var T in TramosEnGrupo(Xml, 'VerInfo_Keys', Grupos[G]) do
        if ConFileVersion(Claves0, T.Ini, T.Fin) then
        begin
          var Nuevos := '';
          for I := 0 to 3 do
            if Length(TramosEnGrupo(Xml, Tags[I], Grupos[G])) = 0 then
              Nuevos := Nuevos + XmlElemento(Tags[I], N[I].ToString) + Eol +
                SangriaDeLaLineaEn(Xml, T.Abre);
          Xml := Copy(Xml, 1, T.Abre - 1) + Nuevos + Copy(Xml, T.Abre, MaxInt);
          Break;
        end;
  end;

  // Los numeros: se sustituyen donde ya estan (en TODOS los grupos que los
  // lleven) y el que falte entra justo detras del anterior de la serie, que
  // es como los escribe el IDE. De la ultima a la primera, para que las de
  // delante no se muevan.
  Previo := '';
  for I := 0 to 3 do
  begin
    var Ts := TramosDeEtiqueta(Xml, Tags[I]);
    if Length(Ts) > 0 then
      for var K := High(Ts) downto 0 do
        Xml := Copy(Xml, 1, Ts[K].Ini - 1) + XmlEscape(N[I].ToString) + Copy(Xml, Ts[K].Fin, MaxInt)
    else if Previo <> '' then
    begin
      var Ps := TramosDeEtiqueta(Xml, Previo);
      for var K := High(Ps) downto 0 do
        Xml := Copy(Xml, 1, Ps[K].Cierra - 1) + Eol + SangriaDeLaLineaEn(Xml, Ps[K].Abre) +
          XmlElemento(Tags[I], N[I].ToString) + Copy(Xml, Ps[K].Cierra, MaxInt);
    end;
    Previo := Tags[I];
  end;

  // Y las claves de texto, solo donde ya existen: las de Android e iOS no
  // llevan FileVersion ni ProductVersion, asi que no las roza. Se cambia la
  // parte numerica del valor, en su sitio.
  var Claves := ClavesDeVersion(Xml);
  for var K := High(Claves) downto 0 do
    if MatchText(Claves[K].Nombre, ['FileVersion', 'ProductVersion']) then
      Xml := Copy(Xml, 1, Claves[K].Ini - 1) + Cuatro +
        Copy(Xml, Claves[K].Ini + Numerico(Xml, Claves[K]), MaxInt);

  // include=true: lo que escribe la casilla "Include version information"
  // del IDE, en cada grupo que lleva la version (el de la clave FileVersion):
  // VerInfo_IncludeVerInfo a true donde ya esta y, donde no, delante de los
  // numeros del grupo o de su VerInfo_Keys, como lo deja el IDE (el .dproj de
  // este servidor, en Base). Android e iOS no llevan FileVersion: no se rozan.
  // Del ultimo grupo al primero, para que los de delante no se muevan.
  var Incluidos := 0;
  if AIncluir then
  begin
    var ClavesI := ClavesDeVersion(Xml);
    var Grupos := GruposDePropiedades(Xml);
    for var G := High(Grupos) downto 0 do
      for var T in TramosEnGrupo(Xml, 'VerInfo_Keys', Grupos[G]) do
        if ConFileVersion(ClavesI, T.Ini, T.Fin) then
        begin
          var Ya := TramosEnGrupo(Xml, 'VerInfo_IncludeVerInfo', Grupos[G]);
          if Length(Ya) > 0 then
            for var K := High(Ya) downto 0 do
              Xml := Copy(Xml, 1, Ya[K].Ini - 1) + 'true' + Copy(Xml, Ya[K].Fin, MaxInt)
          else
          begin
            var Delante := T.Abre;
            for var M in TramosEnGrupo(Xml, 'VerInfo_MajorVer', Grupos[G]) do
              if M.Abre < Delante then
                Delante := M.Abre;
            Xml := Copy(Xml, 1, Delante - 1) + XmlElemento('VerInfo_IncludeVerInfo', 'true') + Eol +
              SangriaDeLaLineaEn(Xml, Delante) + Copy(Xml, Delante, MaxInt);
          end;
          Inc(Incluidos);
          Break;
        end;
  end;

  PatchSaveConSuSalto(ADproj, Xml, Enc);
  Nota := '';
  if Sufijo <> '' then
    Nota := Eol + MsgFmt(SF_CFG_SUFIJO_NO_VA_DPROJ_FMT, [Sufijo]);
  if Incluidos > 0 then
    Nota := Nota + Eol + MsgFmt(SF_CFG_VERSION_INCLUIDA_FMT, [Incluidos])
  else if not IncluyeVersion(Xml) then
    Nota := Nota + Eol + MsgText(SF_CFG_VERSION_NO_INCLUIDA);
  Result := MsgFmt(SN_CONFIG_VERSION_OK_FMT,
    [Cuatro, IfThen(AntesNum = AntesKey, AntesNum,
     MsgFmt(SF_CFG_EN_NUMEROS_Y_CLAVES_FMT, [AntesNum, AntesKey])), Nota]);
end;

function SetSdk(const ADproj, ARawPlatform, ARawSdk: string): string;
var
  APlatform, Sdk, Enc, Xml, Antes, Disponibles: string;
  Info: TRadStudioInfo;
  Quitar: Boolean;
  Falta: TFaltaDeGrupo;
begin
  APlatform := CanonicalPlatform(ARawPlatform);
  if APlatform = '' then
    Exit(MsgFmt(SR_CONFIG_SDK_PLATFORM_FMT, [ARawPlatform.Trim, KnownPlatformsList]));
  // la regla de su gemela set-profile: Win64 contestaba "Registered for
  // Win64: ." (quinta revision)
  if IsLocalPlatform(APlatform) then
    Exit(MsgFmt(SR_CONFIG_SDK_LOCAL_FMT, [APlatform]));
  Info := DiscoverRadStudio;
  if not Info.Found then
    Exit(MsgText(SR_COMPONENTS_MISSING));
  Disponibles := ONinguno(string.Join(', ', SdksDePlataforma(Info.Version, APlatform)));

  Sdk := ARawSdk.Trim;
  // sin sdk quitaba el que el proyecto tuviera fijado contestando exito: para
  // quitarlo esta "none" (tercera revision, 27-sep-2026)
  if Sdk = '' then
    Exit(MsgFmt(SR_CFG_NEED_SDK_FMT, [APlatform, Disponibles]));
  Quitar := SameText(Sdk, 'none') or SameText(Sdk, 'default');
  if not Quitar then
  begin
    Sdk := NombreDeSdk(Sdk);
    // No basta con que exista: CADA .sdk declara SU plataforma (por eso el
    // dialogo del IDE empieza preguntandola y la lista sale agrupada), asi
    // que un SDK de Android no puede acabar puesto en Linux64.
    if not MatchText(Sdk, SdksDePlataforma(Info.Version, APlatform)) then
      Exit(MsgFmt(SR_CONFIG_SDK_NOEXISTE_FMT, [Sdk, APlatform, Disponibles]));
  end;

  Xml := PatchLoadText(ADproj, Enc);
  // EL escritor de una propiedad de un build (Lsp.Dproj): el grupo de
  // valores de la plataforma, creado como lo crea el IDE si falta
  if not PonPropiedadDelBuild(Xml, 'PlatformSDK', Sdk, APlatform, '', Quitar, Antes, Falta) then
    Exit(MensajeDeFalta(Falta, Xml, APlatform, '', 'PlatformSDK'));

  PatchSaveConSuSalto(ADproj, Xml, Enc);
  if Quitar then
    Result := MsgFmt(SN_CONFIG_SDK_QUITADO_FMT,
      [APlatform, ONinguno(Antes), Disponibles])
  else
    Result := MsgFmt(SN_CONFIG_SDK_PUESTO_FMT,
      [APlatform, Sdk, ONinguno(Antes)]);
end;

{ El PAServer del proyecto. La mitad gemela de set-sdk: en el IDE, "anadir a
  un proyecto" es dar de alta a la vez la conexion (el perfil) y el SDK que ya
  existen. msbuild lo lee igual - $(Profile) sale del proyecto si lo declara y
  del activo de la plataforma si no -, asi que se escribe en el mismo sitio:
  el PropertyGroup de esa plataforma. }
function SetProfile(const ADproj, ARawPlatform, ARawProfile: string): string;
var
  APlatform, Perfil, Enc, Xml, Antes, Disponibles: string;
  Info: TRadStudioInfo;
  Quitar: Boolean;
  Falta: TFaltaDeGrupo;
begin
  APlatform := CanonicalPlatform(ARawPlatform);
  if APlatform = '' then
    Exit(MsgFmt(SR_CONFIG_SDK_PLATFORM_FMT, [ARawPlatform.Trim, KnownPlatformsList]));
  if IsLocalPlatform(APlatform) then
    Exit(MsgFmt(SR_CONFIG_PROFILE_LOCAL_FMT, [APlatform]));
  // Android no despliega por PAServer: lo aceptaba, decia "will deploy and
  // run Android64 through profile zorin-desktop", el primer Deploy fallaba
  // E8712 y los siguientes decian "Deployed through profile" con el .apk
  // aqui (medido el 18-oct-2026)
  if SistemaDelPAServer(APlatform) = spDesconocido then
    Exit(MsgFmt(SR_CONFIG_PROFILE_SIN_PASERVER_FMT, [APlatform]));
  Info := DiscoverRadStudio;
  if not Info.Found then
    Exit(MsgText(SR_COMPONENTS_MISSING));
  // EL lector de la lista de perfiles (Lsp.Discovery.PerfilesDelIde)
  Disponibles := ONinguno(string.Join(', ', PerfilesDelIde(Info.Version))); // nunca "Registered: ."

  Perfil := ARawProfile.Trim;
  if Perfil = '' then
    Exit(MsgFmt(SR_CFG_NEED_PROFILE_FMT, [APlatform, Disponibles]));
  Quitar := SameText(Perfil, 'none') or SameText(Perfil, 'default');
  if not Quitar then
  begin
    if BadProfileName(Perfil) then // la regla de la puerta de build y paserver
      Exit(MsgFmt(SR_PASERVER_NAME_FMT, [Perfil]));
    // uno de la lista, con SU nombre: es el que se escribe en el .dproj (2an)
    var Elegido := PerfilDelIde(Info.Version, Perfil);
    if Elegido = '' then
      Exit(MsgFmt(SR_CONFIG_PROFILE_NOEXISTE_FMT, [Perfil, Disponibles]));
    Perfil := Elegido;
    // la gemela de set-sdk: cada .profile declara SU plataforma, y uno de
    // Windows no despliega un Linux64 (lo aceptaba, medido el 18-oct-2026)
    Result := PerfilQueNoSirve(Info.Version, Perfil, APlatform);
    if Result <> '' then
      Exit;
  end;

  Xml := PatchLoadText(ADproj, Enc);
  // EL escritor de una propiedad de un build (Lsp.Dproj), como set-sdk
  if not PonPropiedadDelBuild(Xml, 'Profile', Perfil, APlatform, '', Quitar, Antes, Falta) then
    Exit(MensajeDeFalta(Falta, Xml, APlatform, '', 'Profile'));

  PatchSaveConSuSalto(ADproj, Xml, Enc);
  if Quitar then
    Result := MsgFmt(SN_CONFIG_PROFILE_QUITADO_FMT,
      [APlatform, ONinguno(Antes), Disponibles])
  else
    Result := MsgFmt(SN_CONFIG_PROFILE_PUESTO_FMT,
      [APlatform, Perfil, ONinguno(Antes)]);
end;

{ La pareja que el proyecto compila mientras nadie pide otra: sus dos
  SELECTORES (<Config Condition="'$(Config)'==''"> y el de Platform, los que
  lee Lsp.Dproj.SelectorDe), lo que deja "Activate" en el Project Manager del
  IDE. Solo lo que el proyecto declara - una configuracion suya que se
  compila (Base no) y una plataforma que tiene activa y su framework puede -,
  con el nombre que el proyecto le da. Todo o nada: con las dos, una que no
  vale no deja escrita la otra. Lo leen delphi_build y delphi_test sin config
  ni platform, el IDE y los ajustes del motor (Lsp.ConfigFabricator). }
function SetActive(const ADproj, ARawConfig, ARawPlatform: string): string;
type
  TCambio = record
    Tag, Valor, Antes: string;
    Tramo: TTramoXml;
  end;
var
  Info: TDprojInfo;
  Enc, Xml, Razon, Hecho, Ya: string;
  Cambios, Quedan: TArray<TCambio>;
  C: TCambio;

  function Pon(const ATag, AValor: string): string;
  var
    X: TCambio;
  begin
    Result := '';
    if not SelectorDe(Xml, ATag, X.Tramo) then
      Exit(MsgFmt(SR_CFG_SET_ACTIVE_SIN_SELECTOR_FMT, [TPath.GetFileName(ADproj), ATag]));
    X.Tag := ATag;
    X.Valor := AValor;
    X.Antes := ValorDeTramo(Xml, X.Tramo).Trim;
    Cambios := Cambios + [X];
  end;

begin
  if (ARawConfig.Trim = '') and (ARawPlatform.Trim = '') then
    Exit(MsgText(SR_CFG_SET_ACTIVE_NECESITA));
  Xml := PatchLoadText(ADproj, Enc);
  Info := InfoDeDproj(Xml);
  Cambios := nil;
  if ARawConfig.Trim <> '' then
  begin
    // una que declara, con SU nombre: lo que teclea el agente solo elige
    // (ConfigDeclarada, la regla de set-property tambien)
    var Cfg: string;
    Result := ConfigDeclarada(Xml, ARawConfig, Cfg);
    if Result <> '' then
      Exit;
    Result := Pon('Config', Cfg);
    if Result <> '' then
      Exit;
  end;
  if ARawPlatform.Trim <> '' then
  begin
    // las reglas del build: la que su framework puede y el proyecto tiene activa
    var Plat := CanonicalPlatform(ARawPlatform);
    if Plat = '' then
      Exit(MsgFmt(SR_CONFIG_SDK_PLATFORM_FMT, [ARawPlatform.Trim, KnownPlatformsList]));
    if not Info.CanTarget(Plat, Razon) then
      Exit(MsgEnvuelve(SR_RECHAZADO_FMT, Razon));
    Result := PlataformaNoDeclarada(Info, Plat);
    if Result <> '' then
      Exit;
    Result := Pon('Platform', Plat);
    if Result <> '' then
      Exit;
  end;
  // lo que ya era: no se escribe, ni copia (como CFG-020, la carpeta que ya
  // estaba en el search path; revision del 18-oct-2026)
  Ya := '';
  Quedan := nil;
  for C in Cambios do
    if C.Antes = C.Valor then
      Ya := IfThen(Ya = '', '', Ya + ', ') + MsgFmt(SF_CFG_SET_ACTIVE_ACTUAL_FMT, [LowerCase(C.Tag), C.Valor])
    else
      Quedan := Quedan + [C];
  if Length(Quedan) = 0 then
    Exit(MsgFmt(SN_CFG_SET_ACTIVE_YA_FMT, [TPath.GetFileName(ADproj), Ya]));
  Cambios := Quedan;
  // del ultimo al primero: las posiciones de los de delante siguen valiendo
  if (Length(Cambios) = 2) and (Cambios[0].Tramo.Ini < Cambios[1].Tramo.Ini) then
  begin
    C := Cambios[0];
    Cambios[0] := Cambios[1];
    Cambios[1] := C;
  end;
  Hecho := '';
  for C in Cambios do
  begin
    Xml := Copy(Xml, 1, C.Tramo.Ini - 1) + XmlEscape(C.Valor) + Copy(Xml, C.Tramo.Fin, MaxInt);
    Hecho := MsgFmt(SF_CFG_SET_ACTIVE_PIEZA_FMT, [LowerCase(C.Tag), C.Valor, ONinguno(C.Antes)]) +
      IfThen(Hecho = '', '', ', ' + Hecho);
  end;
  PatchSaveConSuSalto(ADproj, Xml, Enc); // backs up the .dproj to __delphi-patch first
  Result := MsgFmt(SN_CFG_SET_ACTIVE_FMT, [TPath.GetFileName(ADproj), Hecho]);
end;

{ ---- set-property / remove-property / get-property (1.22.0) -------------
  UNA propiedad del .dproj por su nombre, en el grupo del build que digan
  platform y config (sin ninguno, la base), por EL escritor de Lsp.Dproj
  (PonPropiedadDelBuild): la casa del keystore de Android (PF_KeyStoreDebug,
  PF_AliasKeyDebug... en '$(Cfg_1_Android64)'!='') y de lo que venga - un
  agente con un keystore de fuera de las raices no tenia tool que lo quitase
  ni re-apuntase (21-oct-2026). El nombre lo teclea el agente, pero solo
  elige: lo que es estructura del .dproj (los selectores, las claves y sus
  banderas) tiene su comando o no se toca, y un evento de build o una opcion
  libre es texto que este servidor nunca pasa a un programa (el build los
  vacia o los niega). El VALOR no se juzga aqui: lo juzga la puerta del build
  cuando ESE build lo lea (BUILD-050), como lo que entra por delphi_upload. }

{ Lo que no es una opcion sino la ESTRUCTURA del .dproj: los selectores
  (Config, Platform: set-active), las claves de los builds que declara ESTE
  proyecto y sus banderas de plataforma (ClavesDelProyecto, el juez: Base y
  Cfg_N o como se llamen, y Base_X / Cfg_N_X; era un StartsWith('Cfg_') que
  imitaba al juez y dejaba pasar una clave renombrada), CfgParent, lo que
  identifica el proyecto (ProjectGuid, ProjectVersion, MainSource,
  FrameworkType, AppType, ProjectType, TargetedPlatforms), las propiedades
  por las que los <Import> del IDE resuelven lo que cargan (BDS, APPDATA...:
  el build las niega con BUILD-019; aqui, la segunda barrera) y los nombres
  que msbuild se reserva (MSBuild*: MSB4004 al escribir MSBuildProjectName
  en un PropertyGroup, medido el 21-oct-2026). }
function EsClaveDeEstructura(const AXml, ANombre: string): Boolean;
begin
  Result := MatchText(ANombre, ['Config', 'Platform', 'CfgParent', 'ProjectGuid',
    'ProjectVersion', 'MainSource', 'FrameworkType', 'AppType', 'ProjectType',
    'TargetedPlatforms']) or EsPropiedadReservadaDelIde(ANombre) or
    StartsText('MSBuild', ANombre);
  if Result then
    Exit;
  for var K in ClavesDelProyecto(AXml) do
    if SameText(ANombre, K) or ANombre.StartsWith(K + '_', True) then
      Exit(True);
end;

{ En que grupos del .dproj esta <ATag> y con que valor, en orden de
  documento, como lo cuenta set-output (ValorEnGrupo); '' si en ninguno. Con
  ASoloCon, una lista de rutas (un search path), solo los grupos donde una de
  sus entradas es una de esas (EsEntradaPedida). }
function DondeEsta(const AXml, ATag: string; const ASoloCon: TArray<string> = nil): string;
var
  Trozos: TArray<string>;

  function LaLleva(const AValor: string): Boolean;
  begin
    for var E in SplitPaths(AValor) do
      if EsEntradaPedida(E, ASoloCon) then
        Exit(True);
    Result := False;
  end;

begin
  Trozos := [];
  for var G in GruposDePropiedades(AXml) do
    for var T in TramosEnGrupo(AXml, ATag, G, True) do
      if (ASoloCon = nil) or LaLleva(Copy(AXml, T.Ini, T.Fin - T.Ini)) then
        Trozos := Trozos + [ValorEnGrupo(ValorDeTramo(AXml, T), G.Condicion)];
  Result := string.Join('; ', Trozos);
end;

{ ...como coletilla de una respuesta (" Set in: ..."), o nada. }
function EnOtrosGrupos(const AXml, ATag: string): string;
begin
  Result := DondeEsta(AXml, ATag);
  if Result <> '' then
    Result := MsgFmt(SF_CFG_PROPERTY_DONDE_FMT, [Result]);
end;

{ El build que nombran platform y config de la llamada: la plataforma
  canonica y la configuracion con el nombre que declara el proyecto ('' =
  sin esa mitad); la negativa si no valen. }
function BuildDeLaLlamada(const AXml, ARawPlatform, ARawConfig: string;
  out APlatform, AConfig: string): string;
begin
  Result := '';
  APlatform := '';
  AConfig := '';
  if ARawPlatform.Trim <> '' then
  begin
    APlatform := CanonicalPlatform(ARawPlatform);
    if APlatform = '' then
      Exit(MsgFmt(SR_CFG_PLATAFORMA_DELPHI_VALIDA_VALIDAS_FMT, [ARawPlatform.Trim, KnownPlatformsList]));
  end;
  if ARawConfig.Trim <> '' then
    Result := ConfigDeclarada(AXml, ARawConfig, AConfig);
end;

function SetProperty(const ADproj, ARawName, ARawValue, ARawPlatform, ARawConfig: string;
  AQuitar: Boolean): string;
var
  Nombre, Valor, Enc, Xml, Original, Plat, Cfg, Antes, Donde, Grupo, Leido, Pisada: string;
  Falta: TFaltaDeGrupo;
begin
  Nombre := ARawName.Trim;
  if Nombre = '' then
    Exit(MsgText(SR_CFG_NEED_NAME));
  if not EsNombreDeEtiqueta(Nombre) then
    Exit(MsgFmt(SR_CFG_NAME_NO_ES_PROPIEDAD_FMT, [Nombre]));
  Xml := PatchLoadText(ADproj, Enc);
  if EsClaveDeEstructura(Xml, Nombre) then
    Exit(MsgFmt(SR_CFG_NAME_ES_ESTRUCTURA_FMT, [Nombre]));
  if EsTextoLibreDelBuild(Nombre) then
    Exit(MsgFmt(SR_CFG_NAME_ES_TEXTO_LIBRE_FMT, [Nombre]));
  Valor := ARawValue.Trim;
  if not AQuitar then
  begin
    if Valor = '' then
      Exit(MsgText(SR_CFG_NEED_VALUE));
    for var C in Valor do
      if Ord(C) < 32 then
        Exit(MsgText(SR_CFG_VALUE_CON_CONTROL));
  end;
  Result := BuildDeLaLlamada(Xml, ARawPlatform, ARawConfig, Plat, Cfg);
  if Result <> '' then
    Exit;
  Original := Xml;
  if not PonPropiedadDelBuild(Xml, Nombre, Valor, Plat, Cfg, AQuitar, Antes, Falta) then
    Exit(MensajeDeFalta(Falta, Xml, Plat, Cfg, Nombre));
  Donde := NombreDelBuild(Plat, Cfg);
  Grupo := GroupCondition(Plat, ClaveDelBuild(Xml, Cfg)); // el nombrador, para decirlo
  if AQuitar then
  begin
    if Xml = Original then
      Exit(MsgFmt(SN_CFG_PROPERTY_NO_ESTABA_FMT, [Nombre, Donde, Grupo, EnOtrosGrupos(Xml, Nombre)]));
    PatchSaveConSuSalto(ADproj, Xml, Enc); // backs up the .dproj to __delphi-patch first
    Exit(MsgFmt(SN_CFG_PROPERTY_QUITADA_FMT,
      [Nombre, Donde, Grupo, ONinguno(Antes), EnOtrosGrupos(Xml, Nombre)]));
  end;
  // con el build entero nombrado, lo que msbuild lee para el: se escribe en
  // el ULTIMO grupo con esa Condition, pero un elemento con SU Condition en
  // ese grupo, o un grupo de otra forma mas abajo, gana; se dice (revisor D,
  // 21-oct-2026). Un valor con $(Nombre) dentro se lee expandido: no se compara
  Pisada := '';
  if (Plat <> '') and (Cfg <> '') and not ContainsText(Valor, '$(' + Nombre + ')') then
  begin
    Leido := EffectiveProperty(Xml, Nombre, Plat, Cfg);
    if Leido <> Valor then
      Pisada := MsgFmt(SF_CFG_PROPERTY_PISADA_FMT, [ONinguno(Leido)]);
  end;
  // un $(X) del valor que queda ENCIMA de la definicion de X: msbuild lo lee
  // vacio ahi (de arriba abajo; F2613 sin aviso, Opus en Hermes 22-oct-2026).
  // En el build pedido, o en el que el proyecto hace por defecto
  var Info := InfoDeDproj(Xml);
  var Vacias := UsadasAntesDeDefinirse(Xml, Nombre, Valor,
    IfThen(Plat <> '', Plat, Info.PlataformaPorDefecto), IfThen(Cfg <> '', Cfg, Info.ConfigPorDefecto));
  if Length(Vacias) > 0 then
  begin
    for var I := 0 to High(Vacias) do
      Vacias[I] := '$(' + Vacias[I] + ')';
    Pisada := Pisada + MsgFmt(SF_CFG_PROPERTY_ANTES_DE_DEFINIR_FMT, [string.Join(', ', Vacias), Nombre]);
  end;
  // lo que ya era no se escribe, ni copia (como set-active)
  if Xml = Original then
    Exit(MsgFmt(SN_CFG_PROPERTY_YA_FMT, [Nombre, Valor, Donde, Grupo]) + Pisada);
  PatchSaveConSuSalto(ADproj, Xml, Enc); // backs up the .dproj to __delphi-patch first
  Result := MsgFmt(SN_CFG_PROPERTY_PUESTA_FMT, [Nombre, Valor, Donde, Grupo, ONinguno(Antes)]) + Pisada;
end;

function GetProperty(const ADproj, ARawName, ARawPlatform, ARawConfig: string): string;
var
  Nombre, Enc, Xml, Plat, Cfg, Valor, Donde: string;
  Info: TDprojInfo;
begin
  Nombre := ARawName.Trim;
  if Nombre = '' then
    Exit(MsgText(SR_CFG_NEED_NAME));
  if not EsNombreDeEtiqueta(Nombre) then
    Exit(MsgFmt(SR_CFG_NAME_NO_ES_PROPIEDAD_FMT, [Nombre]));
  Xml := PatchLoadText(ADproj, Enc);
  Result := BuildDeLaLlamada(Xml, ARawPlatform, ARawConfig, Plat, Cfg);
  if Result <> '' then
    Exit;
  // el build que se lee: el pedido y, sin pedirlo, el que el proyecto
  // compila por defecto (lo que hace delphi_build sin platform= / config=)
  Info := InfoDeDproj(Xml);
  // lo que no se pidio: el build por defecto entero, o solo su mitad
  if (Plat = '') and (Cfg = '') then
    Donde := MsgText(SF_CFG_BUILD_POR_DEFECTO)
  else if Plat = '' then
    Donde := MsgText(SF_CFG_BUILD_PLATAFORMA_POR_DEFECTO)
  else if Cfg = '' then
    Donde := MsgText(SF_CFG_BUILD_CONFIG_POR_DEFECTO)
  else
    Donde := '';
  if Plat = '' then
    Plat := Info.PlataformaPorDefecto;
  if Cfg = '' then
    Cfg := Info.ConfigPorDefecto;
  // EL juez de una propiedad por grupos (EffectiveProperty, el del build)
  Valor := EffectiveProperty(Xml, Nombre, Plat, Cfg);
  if Valor = '' then
    Valor := MsgText(SF_CFG_PROPERTY_SIN_VALOR);
  Result := MsgFmt(SN_CFG_PROPERTY_GET_FMT, [Nombre, Plat, Cfg, Donde, Valor, EnOtrosGrupos(Xml, Nombre)]);
end;

{ Los parametros de CADA comando, ademas de project y command. Uno que no es
  del comando se dice: set-output con path=".\bin" contestaba "puesto en
  Compiled" (su valor por defecto) ignorando lo que se pidio (sexta revision).
  En UNA tabla: el comando que se anada lleva su fila, y nada mas. La regla
  es la de todas las tools de varios modos (Lsp.Guard.ParametroQueNoVa); el
  section por defecto no cuenta como enviado (septima revision). }
function ParametroQueSobra(const ACmd: string; const P: TDelphiConfigParams;
  out ASuyos, AVaCon: string): string;
const
  COMANDOS: array [0 .. 41] of string = (
    'view', 'section',
    'add-platform', 'platform sdk profile',
    'remove-platform', 'platform',
    'set-output', 'output',
    'add-searchpath', 'platform path paths',
    'remove-searchpath', 'platform path paths',
    'add-deployfile', 'platform path remotedir',
    'remove-deployfile', 'platform path',
    'set-version', 'version include',
    'set-sdk', 'platform sdk',
    'set-profile', 'platform profile',
    'set-active', 'config platform',
    'set-property', 'name value platform config',
    'remove-property', 'name platform config',
    'get-property', 'name platform config',
    'add-requires', 'requires',
    'add-unit', 'path',
    'remove-unit', 'path',
    'fix-references', '',
    'add-project', 'path',
    'remove-project', 'path');
begin
  Result := ParametroQueNoVa(IfThen(ACmd = '', 'view', ACmd), COMANDOS,
    ['platform', P.Platform, '', 'sdk', P.Sdk, '', 'profile', P.Profile, '',
     'path', P.Path, '', 'paths', P.Paths, '', 'section', P.Section, CFG_SECTION_POR_DEFECTO,
     'remotedir', P.RemoteDir, '', 'version', P.Version, '',
     'include', IfThen(P.Include, 'true'), '',
     'output', P.Output, '', 'requires', P.Requires, '',
     'config', P.Config, '', 'name', P.Name, '', 'value', P.Value, ''], ASuyos, AVaCon);
end;

function TDelphiConfigTool.ExecuteWithParams(const Params: TDelphiConfigParams): string;
var
  Cmd, Proj, Sibling: string;
  Rutas: TArray<string>;
begin
  if Params.Project.Trim = '' then
    Exit(MsgText(SR_CFG_DELPHI_CONFIG_NECESITA_PROJECT));
  Cmd := Params.Command.Trim.ToLower;
  // un parametro que no es de este comando se dice, no se ignora
  var Suyos, VaCon: string;
  var Sobra := ParametroQueSobra(Cmd, Params, Suyos, VaCon);
  if Sobra <> '' then
    Exit(MsgFmt(SR_CONFIG_NO_ES_DEL_COMANDO_FMT, [Sobra, IfThen(Cmd = '', 'view', Cmd),
      IfThen(Cmd = '', 'view', Cmd), ONinguno(Suyos)]) + VaCon);
  // view y get-property solo LEEN el .dproj (y valen en un proyecto de
  // REFERENCIA); todo lo demas lo escribe y pasa por la puerta de escritura.
  if (Cmd = '') or (Cmd = 'view') or (Cmd = 'get-property') then
    Result := ReadPathDenied(Params.Project)
  else
    Result := WriteTargetDenied(Params.Project);
  if Result <> '' then
    Exit;
  Result := CarpetaEnVezDeFichero(Params.Project);
  if Result <> '' then
    Exit;
  if not TFile.Exists(Params.Project) then
    Exit(NoEsFichero(Params.Project, MsgFmt(SR_CFG_NO_EXISTE_PROYECTO_FMT, [Params.Project])));
  // Arriving with the .dpr in hand is the common case - delphi_create's own
  // schema says its "project" takes ".dpr (or .dproj)". `view` used to answer
  // for it anyway, with an empty framework, no platforms, no configurations
  // and a cheerful crossPlatform "yes": an answer shaped like knowledge that
  // was not (field round 8). Configuration lives in the .dproj, so resolve
  // the sibling - and when there is none, say that instead of inventing.
  Proj := Params.Project;
  // Un GRUPO no es un proyecto: view contestaba como si fuera uno vacio (el
  // mismo "conocimiento inventado" que el .dpr suelto de arriba), y una
  // orden de escritura lo habria tocado como un .dproj (26-sep-2026).
  if SameText(TPath.GetExtension(Proj), '.groupproj') then
  begin
    if (Cmd = '') or (Cmd = 'view') then
    begin
      // view de un GRUPO no tiene secciones: section se ignoraba (septima
      // revision). La misma regla, con la fila del grupo
      var SuyosG, VaConG: string;
      var SobraG := ParametroQueNoVa('view', ['view', ''],
        ['section', Params.Section, CFG_SECTION_POR_DEFECTO], SuyosG, VaConG);
      if SobraG <> '' then
        Exit(MsgFmt(SR_CONFIG_NO_ES_DEL_COMANDO_FMT, [SobraG, 'view (.groupproj)',
          'view (.groupproj)', MsgText(SF_NINGUNO)]) + VaConG);
      Exit(ViewGroup(Proj));
    end;
    // Las de un grupo (1.6.0): add-project y remove-project escriben lo que
    // "Add existing project" del IDE; fix-references re-apunta lo que ya no
    // esta donde dice. El proyecto de "path" solo se NOMBRA.
    if MatchText(Cmd, ['add-project', 'remove-project', 'fix-references']) then
    begin
      if Cmd = 'fix-references' then
        Exit(ArreglaReferencias(Proj));
      if Params.Path.Trim = '' then
        Exit(MsgText(SR_GRUPO_NECESITA_PATH));
      // add-project lee el .dproj que entra; remove-project solo quita la
      // entrada tal como la lista el grupo (uno movido fuera, o que ya no esta)
      if Cmd = 'add-project' then
      begin
        Result := ReadPathDenied(Params.Path);
        if Result <> '' then
          Exit;
      end;
      EnterFileEdit;
      try
        if Cmd = 'add-project' then
          Result := AnadeProyectoAGrupo(Proj, Params.Path)
        else
          Result := QuitaProyectoDeGrupo(Proj, Params.Path);
      finally
        LeaveFileEdit;
      end;
      Exit;
    end;
    Exit(MsgFmt(SR_CONFIG_GROUP_FMT, [TPath.GetFileName(Proj), Cmd]));
  end;
  if MatchText(TPath.GetExtension(Proj), ['.dpr', '.dpk']) then
  begin
    Sibling := DprojDe(Proj);
    if TFile.Exists(Sibling) then
      Proj := Sibling
    else if not MatchText(Cmd, ['', 'view', 'add-unit', 'remove-unit', 'add-requires']) then
      Exit(MsgFmt(SR_CONFIG_NO_DPROJ_FMT,
        [TPath.GetFileName(Proj), TPath.GetFileName(Sibling)]));
  end;
  // Y lo que no es un proyecto no se lee ni se escribe como si lo fuera.
  if not MatchText(TPath.GetExtension(Proj), ['.dproj', '.dpr', '.dpk']) then
    Exit(MsgFmt(SR_CONFIG_NOT_PROJECT_FMT, [TPath.GetFileName(Proj)]));
  if (Cmd = '') or (Cmd = 'view') then
    Exit(ViewConfig(Proj, Params.Section));
  if Cmd = 'get-property' then
    Exit(GetProperty(Proj, Params.Name, Params.Platform, Params.Config));

  // add-unit juzga la raiz de un designer contra la tabla de su marco
  // (Lsp.ProjectUnits.JuzgaRaizDeDiseno), y la tabla se espera FUERA del
  // cerrojo, como la del disenador: dentro se paraban todas las ediciones
  // del servidor mientras se generaba. Sin ella, lo que no se sepa se dice
  if (Cmd = 'add-unit') and (Params.Path.Trim <> '') and (ReadPathDenied(Params.Path) = '') then
    for var D in DesignersDeUnidad(TPath.GetFullPath(Params.Path)) do
      if TFile.Exists(D) then
      begin
        var Falta: TFaltaTabla;
        MetaTable(EsDesignerFmx(D), Falta);
        Break;
      end;

  // Todo lo demas ESCRIBE el .dproj leyendolo, cambiandolo y guardandolo, asi
  // que va bajo el mismo cerrojo que las demas ediciones: dos agentes tocando
  // la configuracion del mismo proyecto a la vez perdian el cambio de uno con
  // exito reportado (medido 2026-09-20, bateria de concurrencia).
  EnterFileEdit;
  try
    if Cmd = 'add-platform' then
    begin
      // Anadir un destino a un proyecto es UN gesto: el dialogo del IDE pide
      // plataforma, perfil y SDK a la vez. Si el agente los trae, se dejan
      // puestos aqui mismo en vez de exigir dos llamadas mas. Y un gesto es
      // TODO O NADA: un SDK o un perfil que no valen dejaban la plataforma
      // anadida con el rechazo detras (medio gesto; visto al endurecer
      // test_sdk el 26-sep, David: "si ya tenemos el rechazo, la quitamos").
      // El .dproj vuelve byte a byte, como una tanda.
      var Foto: TFotoDeFicheros;
      Foto.Toma([Proj]);
      Result := AddPlatform(Proj, Params.Platform);
      if not EsFallo(Result) then
      begin
        var Pega := '';
        // un paso que LANZA es un fallo como el que se devuelve: se saltaba
        // el deshacer y la plataforma quedaba anadida (segunda revision,
        // 27-sep-2026; el grupo que falta ya no lanza: MensajeDeFalta)
        try
          if Params.Sdk.Trim <> '' then
            Pega := SetSdk(Proj, Params.Platform, Params.Sdk);
          if (Params.Profile.Trim <> '') and not EsFallo(Pega) then
            Pega := string.Join(sLineBreak, [Pega,
              SetProfile(Proj, Params.Platform, Params.Profile)]).Trim;
        except
          on E: Exception do
            Pega := MsgExcepcion(E.ClassName, E.Message);
        end;
        var Rechazo := '';
        for var L in Pega.Replace(sLineBreak, #10).Split([#10]) do
          // EsFallo, no EsRechazo: un INTERNAL (sin RAD Studio para el
          // SDK) dejaba la plataforma anadida sin deshacer (revision
          // 27-sep-2026)
          if EsFallo(L) then
            Rechazo := L;
        if Rechazo <> '' then
        begin
          var NoVolvio := Foto.Restaura;
          Result := Rechazo + ' ' + MsgText(SN_CONFIG_ADDPLATFORM_NADA);
          if NoVolvio <> '' then
            Result := MsgFmt(SR_FOTO_NO_VOLVIO_FMT, [NoVolvio, Rechazo]);
        end
        else if Pega <> '' then
          Result := Result + sLineBreak + Pega;
      end;
    end
    else if Cmd = 'remove-platform' then
      Result := RemovePlatform(Proj, Params.Platform)
    else if Cmd = 'set-output' then
      Result := SetOutput(Proj, Params.Output)
    else if Cmd = 'add-searchpath' then
    begin
      Result := RutasDeSearchPath(Params, Rutas);
      if Result = '' then
        Result := AddSearchPath(Proj, Params.Platform, Rutas);
    end
    else if Cmd = 'remove-searchpath' then
    begin
      Result := RutasDeSearchPath(Params, Rutas);
      if Result = '' then
        Result := RemoveSearchPath(Proj, Params.Platform, Rutas);
    end
    else if Cmd = 'add-deployfile' then
      Result := AddDeployFile(Proj, Params.Platform, Params.Path, Params.RemoteDir)
    else if Cmd = 'remove-deployfile' then
      Result := RemoveDeployFile(Proj, Params.Platform, Params.Path)
    else if Cmd = 'set-version' then
      Result := SetVersion(Proj, Params.Version, Params.Include)
    else if Cmd = 'set-sdk' then
      Result := SetSdk(Proj, Params.Platform, Params.Sdk)
    else if Cmd = 'set-profile' then
      Result := SetProfile(Proj, Params.Platform, Params.Profile)
    else if Cmd = 'set-active' then
      Result := SetActive(Proj, Params.Config, Params.Platform)
    else if (Cmd = 'set-property') or (Cmd = 'remove-property') then
      Result := SetProperty(Proj, Params.Name, Params.Value, Params.Platform, Params.Config,
        Cmd = 'remove-property')
    else if Cmd = 'add-requires' then
    begin
      Result := WriteTargetDenied(Params.Project);
      if Result = '' then
        Result := AddPackageRequires(Params.Project, Params.Requires);
    end
    else if (Cmd = 'add-unit') or (Cmd = 'remove-unit') then
    begin
      if Params.Path.Trim = '' then
        Exit(MsgText(SR_UNIT_NEED_PATH));
      Result := WriteTargetDenied(Params.Project);
      // add-unit: la unit solo se NOMBRA y la pregunta es la de LEER (una de
      // una referencia o de vendor va al .dpr propio y no se le escribe nada;
      // duodecima revision, r12a). remove-unit: la ruta es la ENTRADA que se
      // quita, tal como la lista el proyecto, y no se lee ni se escribe: una
      // de fuera (BUILD-050 pide quitarla) o que ya no existe se quita igual
      // (21-oct-2026; el nucleo no la abre si esta fuera)
      if (Result = '') and (Cmd = 'add-unit') then
        Result := ReadPathDenied(Params.Path);
      if Result <> '' then
        Exit;
      if Cmd = 'add-unit' then
        Result := AddProjectUnit(Params.Project, Params.Path)
      else
        Result := RemoveProjectUnit(Params.Project, Params.Path);
    end
    else if Cmd = 'fix-references' then
      Result := ArreglaReferencias(Params.Project)
    else if (Cmd = 'add-project') or (Cmd = 'remove-project') then
      Result := MsgFmt(SR_GRUPO_SOLO_GRUPO_FMT, [Cmd, TPath.GetFileName(Proj)])
    else
      Result := MsgText(SR_CFG_COMMAND_DEBE_SER_VIEW);
  finally
    LeaveFileEdit;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_config',
    function: IMCPTool begin Result := TDelphiConfigTool.Create; end);

end.
