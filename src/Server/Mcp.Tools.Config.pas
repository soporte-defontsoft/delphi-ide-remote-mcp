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
    FRemoteDir: string;
    FSection: string;
    FVersion: string;
    FInclude: Boolean;
    FRequires: string;
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
    property Path: string read FPath write FPath;
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
  Lsp.Rutas;

constructor TDelphiConfigTool.Create;
begin
  inherited;
  FName := 'delphi_config';
  FDescription := SD_CFG_CONFIG;
end;

procedure AddSearchPathsView(const AXml: string; AReturn: TJSONObject); forward;
procedure AddDeployFilesView(const ADproj: string; AReturn: TJSONObject); forward;

function PlatformNeedsProfile(const APlatform: string): Boolean;
begin
  Result := not IsLocalPlatform(APlatform);
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
    V: string;
  begin
    if Xml = '' then
      Xml := LeeTexto(ADproj, [ltJaula]);
    if not RadVisto then
    begin
      Rad := DiscoverRadStudio;
      RadVisto := True;
    end;
    V := PlatformProperty(Xml, APlat, 'PlatformSDK');
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
    if APlat.StartsWith('Android', True) then
      Exit;
    V := PlatformProperty(Xml, APlat, 'Profile');
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
      // la 1.16.0)
      Return.AddPair('defaultPlatform', Info.PlataformaPorDefecto);
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
        Obj.AddPair('needsSDKForBuild', TJSONBool.Create(PlatformNeedsProfile(P.Name)));
        Obj.AddPair('needsProfileForDeploy', TJSONBool.Create(PlatformNeedsProfile(P.Name)));
        if PlatformNeedsProfile(P.Name) then
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
        if P.Enabled and PlatformNeedsProfile(P.Name) then
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
{ El "before" de CFG-081: el valor que tenia; si estaba en mas de un grupo, o
  en uno que no es el base, cada uno con su grupo - una config con su propia
  carpeta que set-output ha reescrito se dice, no se calla. }
function LoQueHabia(const ACambios: TArray<TValorReescrito>): string;
var
  Trozos: TArray<string>;
  Valor: string;
begin
  if Length(ACambios) = 0 then
    Exit(MsgText(SF_CFG_SIN_DEFINIR));
  if (Length(ACambios) = 1) and ACambios[0].EnBase and (ACambios[0].Antes <> '') then
    Exit(ACambios[0].Antes);
  Trozos := [];
  for var C in ACambios do
  begin
    Valor := IfThen(C.Antes = '', MsgText(SF_CFG_SIN_DEFINIR), C.Antes);
    if C.Grupo = '' then
      Trozos := Trozos + [MsgFmt(SF_CFG_VALOR_EN_GRUPO_SIN_CONDICION_FMT, [Valor])]
    else
      Trozos := Trozos + [MsgFmt(SF_CFG_VALOR_EN_GRUPO_FMT, [Valor, C.Grupo])];
  end;
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
    ExeInner := '.\$(Platform)\$(Config)';
    DcuInner := '.\$(Platform)\$(Config)\dcu';
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

{ Las Condition de los grupos (GroupCondition, DefinerCondition), el grupo por
  su Condition (GrupoConCondicion) y la etiqueta dentro de el (TramosEnGrupo)
  viven en Lsp.Dproj: EL analisis del .dproj, el mismo que lee el build. Aqui
  eran un buscador del grupo letra a letra y otro de la etiqueta exacta
  (D4 de la auditoria de la 1.20.1). }
{ Creates the definer and values groups of a platform when the .dproj lacks
  them (the IDE writes both the first time a platform option is touched). }
procedure EnsurePlatformGroups(var AXml: string; const APlatform: string);
var
  G: TGrupoXml;
  Tras: Integer;
begin
  if not GrupoConCondicion(AXml, DefinerCondition(APlatform), G) then
  begin
    // after the last platform definer (any platform), else after the Base one
    Tras := 0;
    for var D in GruposDePropiedades(AXml) do
      if PlataformaDeGrupo(D.Condicion, True) <> '' then
        Tras := D.Cierra;
    if (Tras = 0) and
       GrupoConCondicion(AXml, '''$(Config)''==''Base'' or ''$(Base)''!=''''', G) then
      Tras := G.Cierra;
    if Tras = 0 then
      raise Exception.Create(MsgText(SR_CFG_NO_ENCUENTRO_PROPERTYGROUP_CONFIG));
    AXml := Copy(AXml, 1, Tras - 1) + sLineBreak +
      '    <PropertyGroup ' + XmlAtributo('Condition', DefinerCondition(APlatform)) + '>' + sLineBreak +
      '        ' + XmlElemento('Base_' + APlatform, 'true') + sLineBreak +
      '        <CfgParent>Base</CfgParent>' + sLineBreak +
      '        <Base>true</Base>' + sLineBreak +
      '    </PropertyGroup>' + Copy(AXml, Tras, MaxInt);
  end;
  if not GrupoConCondicion(AXml, GroupCondition(APlatform), G) then
  begin
    if not GrupoConCondicion(AXml, GroupCondition(''), G) then
      raise Exception.Create(MsgText(SR_CFG_NO_ENCUENTRO_PROPERTYGROUP_BASE));
    AXml := Copy(AXml, 1, G.Cierra - 1) + sLineBreak +
      '    <PropertyGroup ' + XmlAtributo('Condition', GroupCondition(APlatform)) + '>' + sLineBreak +
      '    </PropertyGroup>' + Copy(AXml, G.Cierra, MaxInt);
  end;
end;

{ set-sdk y set-profile: ATag (PlatformSDK, Profile) en el grupo de valores de
  APlatform - donde la escribe el IDE y la lee msbuild para ella -, creado
  como lo crea el IDE si falta. Las que hubiera DENTRO de ese grupo se quitan
  con su linea (AAntes, la que valia: la ultima) y, si no es quitar, la nueva
  va al principio del grupo. Eran dos gemelas de treinta lineas que solo
  quitaban la primera: con dos, la otra seguia valiendo (D3 de la auditoria de
  la 1.20.1). '' o la negativa: AInconsistente si el grupo no aparece despues
  de quitarlas. }
function PonPropiedadDePlataforma(var AXml: string; const APlatform, ATag, AValor: string;
  AQuitar: Boolean; const AInconsistente: string; out AAntes: string): string;
var
  G: TGrupoXml;
  Tramos: TArray<TTramoXml>;
begin
  Result := '';
  AAntes := '';
  EnsurePlatformGroups(AXml, APlatform);
  if not GrupoConCondicion(AXml, GroupCondition(APlatform), G) then
    Exit(MsgFmt(SR_CFG_NO_ENCUENTRO_PROPERTYGROUP_DE_FMT, [APlatform]));
  // lo que hubiera DENTRO de ese grupo, no en cualquier sitio del fichero; de
  // la ultima a la primera, para que las de delante no se muevan
  Tramos := TramosEnGrupo(AXml, ATag, G);
  if Length(Tramos) > 0 then
  begin
    AAntes := ValorDeTramo(AXml, Tramos[High(Tramos)]);
    for var K := High(Tramos) downto 0 do
      QuitaConSuLinea(AXml, Tramos[K].Abre, Tramos[K].Cierra);
    if not GrupoConCondicion(AXml, GroupCondition(APlatform), G) then
      Exit(AInconsistente);
  end;
  if not AQuitar then
    AXml := Copy(AXml, 1, G.Ini - 1) + sLineBreak +
      '        ' + XmlElemento(ATag, AValor) + Copy(AXml, G.Ini, MaxInt);
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

function AddSearchPath(const ADproj, ARawPlatform, ARawPath: string): string;
var
  Enc, Xml, Plat, Show, Path, NewInner, P: string;
  G: TGrupoXml;
  Tramos: TArray<TTramoXml>;
  VS, VE: Integer;
begin
  Plat := '';
  if ARawPlatform.Trim <> '' then
  begin
    Plat := CanonicalPlatform(ARawPlatform);
    if Plat = '' then
      Exit(MsgFmt(SR_CFG_PLATAFORMA_DELPHI_VALIDA_VALIDAS_FMT, [ARawPlatform.Trim, KnownPlatformsList]));
  end;
  Result := SearchPathDenied(ADproj, ARawPath, Show);
  if Result <> '' then
    Exit;
  Path := ARawPath.Trim;

  Xml := PatchLoadText(ADproj, Enc);
  try
    if Plat <> '' then
      EnsurePlatformGroups(Xml, Plat);
  except
    on E: Exception do
      Exit(MsgExcepcion(E.ClassName, E.Message));
  end;
  if not GrupoConCondicion(Xml, GroupCondition(Plat), G) then
    Exit(MsgFmt(SR_CFG_NO_ENCUENTRO_PROPERTYGROUP_FMT, [GroupCondition(Plat)]));
  Tramos := TramosEnGrupo(Xml, 'DCC_UnitSearchPath', G);
  if Length(Tramos) > 0 then
  begin
    VS := Tramos[0].Ini;
    VE := Tramos[0].Fin;
    for P in SplitPaths(Copy(Xml, VS, VE - VS)) do
      if SameText(XmlUnescape(P), Path) then
        Exit(MsgFmt(SN_CONFIG_PATH_PRESENT_FMT,
          [Path, IfThen(Plat = '', MsgText(SF_CFG_TODAS_PLATAFORMAS_BASE), Plat)]));
    NewInner := XmlEscape(Path) + ';' + Copy(Xml, VS, VE - VS);
    Xml := Copy(Xml, 1, VS - 1) + NewInner + Copy(Xml, VE, MaxInt);
  end
  else
    Xml := Copy(Xml, 1, G.Ini - 1) + sLineBreak +
      '        ' + XmlElemento('DCC_UnitSearchPath', Path + ';$(DCC_UnitSearchPath)') +
      Copy(Xml, G.Ini, MaxInt);
  PatchSaveConSuSalto(ADproj, Xml, Enc); // backs up the .dproj to __delphi-patch first
  Result := MsgFmt(SN_CONFIG_PATH_ADDED_FMT,
    [Path, IfThen(Plat = '', MsgText(SF_CFG_TODAS_PLATAFORMAS_BASE), Plat), Show,
     IfThen(Plat = '', 'Win64', Plat)]);
end;

function RemoveSearchPath(const ADproj, ARawPlatform, ARawPath: string): string;
var
  Enc, Xml, Plat, Path, Rest, P: string;
  G: TGrupoXml;
  Tramos: TArray<TTramoXml>;
  Found: Boolean;
  Keep: TList<string>;
begin
  Plat := '';
  if ARawPlatform.Trim <> '' then
  begin
    Plat := CanonicalPlatform(ARawPlatform);
    if Plat = '' then
      Exit(MsgFmt(SR_CFG_PLATAFORMA_DELPHI_VALIDA_FMT, [ARawPlatform.Trim]));
  end;
  Path := ARawPath.Trim;
  if Path = '' then
    Exit(MsgText(SR_CONFIG_NEED_PATH));
  Xml := PatchLoadText(ADproj, Enc);
  Tramos := [];
  if GrupoConCondicion(Xml, GroupCondition(Plat), G) then
    Tramos := TramosEnGrupo(Xml, 'DCC_UnitSearchPath', G);
  if Length(Tramos) = 0 then
    Exit(MsgFmt(SN_CONFIG_PATH_ABSENT_FMT,
      [Path, IfThen(Plat = '', MsgText(SF_CFG_TODAS_PLATAFORMAS_BASE), Plat)]));
  Found := False;
  Keep := TList<string>.Create;
  try
    for P in SplitPaths(Copy(Xml, Tramos[0].Ini, Tramos[0].Fin - Tramos[0].Ini)) do
      if SameText(XmlUnescape(P), Path) then
        Found := True
      else
        Keep.Add(P);
    if not Found then
      Exit(MsgFmt(SN_CONFIG_PATH_ABSENT_FMT,
        [Path, IfThen(Plat = '', MsgText(SF_CFG_TODAS_PLATAFORMAS_BASE), Plat)]));
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
  Result := MsgFmt(SN_CONFIG_PATH_REMOVED_FMT,
    [Path, IfThen(Plat = '', MsgText(SF_CFG_TODAS_PLATAFORMAS_BASE), Plat)]);
end;

{ view: the search paths per group, as the .dproj states them (macros kept). }
procedure AddSearchPathsView(const AXml: string; AReturn: TJSONObject);
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  Name, P: string;
  Tramos: TArray<TTramoXml>;
  Any: Boolean;
begin
  Obj := TJSONObject.Create;
  Any := False;
  for var G in GruposDePropiedades(AXml) do
  begin
    // la base y el grupo de valores de cada plataforma, los que escriben el
    // IDE y add-searchpath, por EL analisis del .dproj (era una regex propia)
    if CondicionNormalizada(G.Condicion) = CondicionNormalizada(GroupCondition('')) then
      Name := 'base'
    else
      Name := PlataformaDeGrupo(G.Condicion, False);
    if Name = '' then
      Continue;
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
  begin
    if SameText(APlatform, 'Android64') then
      Result := Result + 'library\lib\arm64-v8a\'
    else if SameText(APlatform, 'Android') then
      Result := Result + 'library\lib\armeabi-v7a\';
  end;
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
  Block := '    <ItemGroup ' + XmlAtributo('Condition', DeployGroupCondition(Plat)) + '>' + sLineBreak +
    XmlDeployFile(Include, 'Debug', RemoteDir, TPath.GetFileName(Include), 'File', 0, True) +
    XmlDeployFile(Include, 'Release', RemoteDir, TPath.GetFileName(Include), 'File', 0, True) +
    '    </ItemGroup>' + sLineBreak;
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
  Result := PonPropiedadDePlataforma(Xml, APlatform, 'PlatformSDK', Sdk, Quitar,
    MsgText(SR_CFG_QUEDO_INCONSISTENTE_PLATFORMSDK), Antes);
  if Result <> '' then
    Exit;

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
begin
  APlatform := CanonicalPlatform(ARawPlatform);
  if APlatform = '' then
    Exit(MsgFmt(SR_CONFIG_SDK_PLATFORM_FMT, [ARawPlatform.Trim, KnownPlatformsList]));
  if IsLocalPlatform(APlatform) then
    Exit(MsgFmt(SR_CONFIG_PROFILE_LOCAL_FMT, [APlatform]));
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
  end;

  Xml := PatchLoadText(ADproj, Enc);
  Result := PonPropiedadDePlataforma(Xml, APlatform, 'Profile', Perfil, Quitar,
    MsgText(SR_CFG_QUEDO_INCONSISTENTE_PROFILE), Antes);
  if Result <> '' then
    Exit;

  PatchSaveConSuSalto(ADproj, Xml, Enc);
  if Quitar then
    Result := MsgFmt(SN_CONFIG_PROFILE_QUITADO_FMT,
      [APlatform, ONinguno(Antes), Disponibles])
  else
    Result := MsgFmt(SN_CONFIG_PROFILE_PUESTO_FMT,
      [APlatform, Perfil, ONinguno(Antes)]);
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
  COMANDOS: array [0 .. 33] of string = (
    'view', 'section',
    'add-platform', 'platform sdk profile',
    'remove-platform', 'platform',
    'set-output', 'output',
    'add-searchpath', 'platform path',
    'remove-searchpath', 'platform path',
    'add-deployfile', 'platform path remotedir',
    'remove-deployfile', 'platform path',
    'set-version', 'version include',
    'set-sdk', 'platform sdk',
    'set-profile', 'platform profile',
    'add-requires', 'requires',
    'add-unit', 'path',
    'remove-unit', 'path',
    'fix-references', '',
    'add-project', 'path',
    'remove-project', 'path');
begin
  Result := ParametroQueNoVa(IfThen(ACmd = '', 'view', ACmd), COMANDOS,
    ['platform', P.Platform, '', 'sdk', P.Sdk, '', 'profile', P.Profile, '',
     'path', P.Path, '', 'section', P.Section, CFG_SECTION_POR_DEFECTO,
     'remotedir', P.RemoteDir, '', 'version', P.Version, '',
     'include', IfThen(P.Include, 'true'), '',
     'output', P.Output, '', 'requires', P.Requires, ''], ASuyos, AVaCon);
end;

function TDelphiConfigTool.ExecuteWithParams(const Params: TDelphiConfigParams): string;
var
  Cmd, Proj, Sibling: string;
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
  // view solo LEE el .dproj (y vale en un proyecto de REFERENCIA); todo lo
  // demas lo escribe y pasa por la puerta de escritura.
  if (Cmd = '') or (Cmd = 'view') then
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
      Result := ReadPathDenied(Params.Path);
      if Result <> '' then
        Exit;
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
        // un paso que LANZA (EnsurePlatformGroups sin su PropertyGroup) es
        // un fallo como el que se devuelve: se saltaba el deshacer y la
        // plataforma quedaba anadida (segunda revision, 27-sep-2026)
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
      Result := AddSearchPath(Proj, Params.Platform, Params.Path)
    else if Cmd = 'remove-searchpath' then
      Result := RemoveSearchPath(Proj, Params.Platform, Params.Path)
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
      if Result = '' then
        // la unit solo se NOMBRA: la pregunta es la de LEER. Una unit de una
        // referencia o de vendor va al .dpr propio (su .dcu cae en la salida
        // del proyecto) y no se le escribe nada (duodecima revision, r12a)
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
