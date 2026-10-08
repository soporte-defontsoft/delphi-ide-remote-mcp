unit Lsp.Scaffold;

{ Scaffolder: creates NEW Delphi projects (console / VCL / FMX) and NEW forms
  (VCL / FMX) from IDE-equivalent skeletons, so a remote agent can start work
  from zero. Rules of the house apply: new files are UTF-8 with BOM + CRLF,
  nothing is ever overwritten, and the .dpr registration of a new form is
  done through the same encoding-preserving machinery as delphi_edit.
  The .dproj written for a new project is minimal and MSBuild-buildable; the
  IDE enriches it the first time the user opens the project. }

interface

function CreateDelphiProject(const ADir, AName, AKind: string): string;
{ AKind: console | vcl | fmx | package (a runtime package: .dpk + .dproj,
  requires rtl, no contains yet - the first kind=unit opens it) | test (un
  runner DUnitX de consola + su primer fixture, lo que delphi_test corre). }
{ AKind: vcl | fmx (forms) | frame-vcl | frame-fmx | datamodule. }
function CreateDelphiForm(const ADprPath, AUnitName, AFormName, AKind: string;
  const ASubDir: string = ''): string;
{ A plain unit (interface/implementation skeleton) registered in the project. }
function CreateDelphiUnit(const ADprPath, AUnitName, AContent: string;
  const ASubDir: string = ''): string;

{ Un .inc con su content: en la subcarpeta ADir del proyecto dado o, sin
  proyecto, en la carpeta ABSOLUTA ADir. No se registra en ningun sitio. }
function CreateDelphiInclude(const ADprPath, AName, AContent, ADir: string): string;

{ LA regla de un nombre de unit NUEVO: un identificador (con puntos), y
  ningun tramo palabra reservada, ni una unit de la RTL, ni colgando de un
  espacio de nombres de Embarcadero. '' si vale; si no, la negativa. La usan
  delphi_create, la creacion de units de delphi_edit y el move que renombra
  una unit: los dos ultimos solo miraban que fuera un identificador, y
  'Begin.pas' o 'System.pas' pasaban (revision de paisaje del 4-oct-2026). }
function BadUnitName(const AName: string): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.IOUtils,
  System.RegularExpressions,
  Lsp.Patch,
  Lsp.Dproj,
  Lsp.ProjectUnits,
  Lsp.Texts,
  Lsp.Guard,
  Lsp.Pascal,
  Lsp.DesignerBin, // el literal y el flotante: sus compositores
  Lsp.DesignerForma, // la linea de objeto: su compositor
  Lsp.Casa;

const
  CRLF = #13#10;

function NewGuidStr: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := GUIDToString(G);
end;

procedure WriteNewFile(const APath, AText: string);
var
  Enc, Ext: string;
begin
  if TFile.Exists(APath) then
    raise Exception.Create(MsgFmt(SR_CREATE_YA_EXISTE_SOBREESCRIBE_FMT, [APath]));
  CrearCarpeta(TPath.GetDirectoryName(TPath.GetFullPath(APath)));
  Ext := LowerCase(TPath.GetExtension(APath));
  if Ext = '.dproj' then
    Enc := 'utf8-bom' // MSBuild XML declares utf-8: not subject to IDE taste
  else if TPath.GetFileName(APath).ToLower = '.gitignore' then
    Enc := 'utf8'     // git does NOT strip a BOM: it would break the 1st rule
  else
    Enc := NewFileEncName; // sources honour the IDE's configured default
  PatchSaveText(APath, AText, Enc);
end;

function DprojTemplate(const AName, AGuid, AAppType, AFramework,
  AFormUnit, AFormName, AFormType: string): string;
var
  FormRef, MainExt, ProjectType, PkgProps: string;
begin
  // Un paquete se diferencia en cuatro cosas, medidas contra un .dproj de
  // paquete del IDE (FMXDefontsoft, 2026-09-23): el fuente principal es el
  // .dpk, AppType/ProjectType = Package, GenDll+GenPackage+AppFileExt=bpl,
  // y el BPL y el DCP se quedan en la carpeta del proyecto (el IDE los
  // manda por defecto a la carpeta publica Bpl/Dcp de Embarcadero: fuera de
  // la jaula, y ademas eso es "instalar", que no hacemos).
  MainExt := '.dpr';
  ProjectType := 'Application';
  PkgProps := '';
  if SameText(AAppType, 'Package') then
  begin
    MainExt := '.dpk';
    ProjectType := 'Package';
    PkgProps :=
      '        <DCC_BplOutput>.\$(Platform)\$(Config)</DCC_BplOutput>' + CRLF +
      '        <DCC_DcpOutput>.\$(Platform)\$(Config)</DCC_DcpOutput>' + CRLF +
      '        <GenDll>true</GenDll>' + CRLF +
      '        <GenPackage>true</GenPackage>' + CRLF +
      '        <AppFileExt>bpl</AppFileExt>' + CRLF +
      '        <DCC_E>false</DCC_E>' + CRLF +
      '        <DCC_N>false</DCC_N>' + CRLF +
      '        <DCC_S>false</DCC_S>' + CRLF +
      '        <DCC_F>false</DCC_F>' + CRLF +
      '        <DCC_K>false</DCC_K>' + CRLF;
  end;
  FormRef := '';
  if (AFormUnit <> '') and (AFormName = '') then
    // Una unit sin form (el fixture de un proyecto de test): la referencia
    // a secas, como la escribe el IDE para un .pas cualquiera.
    FormRef := '        <DCCReference ' + XmlAtributo('Include', AFormUnit + '.pas') + '/>' + CRLF
  else if AFormUnit <> '' then
    FormRef :=
      '        <DCCReference ' + XmlAtributo('Include', AFormUnit + '.pas') + '>' + CRLF +
      '            ' + XmlElemento('Form', AFormName) + CRLF +
      '            ' + XmlElemento('FormType', AFormType) + CRLF +
      '        </DCCReference>' + CRLF;
  Result :=
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + CRLF +
    '    <PropertyGroup>' + CRLF +
    '        ' + XmlElemento('ProjectGuid', AGuid) + CRLF +
    '        ' + XmlElemento('MainSource', AName + MainExt) + CRLF +
    '        <Base>True</Base>' + CRLF +
    '        <Config Condition="''$(Config)''==''''">Debug</Config>' + CRLF +
    '        <ProjectName Condition="''$(ProjectName)''==''''">' + XmlEscape(AName) + '</ProjectName>' + CRLF +
    '        <TargetedPlatforms>3</TargetedPlatforms>' + CRLF +
    '        ' + XmlElemento('AppType', AAppType) + CRLF +
    '        ' + XmlElemento('FrameworkType', AFramework) + CRLF +
    '        <ProjectVersion>20.4</ProjectVersion>' + CRLF +
    '        <Platform Condition="''$(Platform)''==''''">Win64</Platform>' + CRLF +
    '    </PropertyGroup>' + CRLF +
    '    <PropertyGroup Condition="''$(Config)''==''Base'' or ''$(Base)''!=''''">' + CRLF +
    '        <Base>true</Base>' + CRLF +
    '    </PropertyGroup>' + CRLF +
    '    <PropertyGroup Condition="(''$(Platform)''==''Win32'' and ''$(Base)''==''true'') or ''$(Base_Win32)''!=''''">' + CRLF +
    '        <Base_Win32>true</Base_Win32>' + CRLF +
    '        <CfgParent>Base</CfgParent>' + CRLF +
    '        <Base>true</Base>' + CRLF +
    '    </PropertyGroup>' + CRLF +
    '    <PropertyGroup Condition="(''$(Platform)''==''Win64'' and ''$(Base)''==''true'') or ''$(Base_Win64)''!=''''">' + CRLF +
    '        <Base_Win64>true</Base_Win64>' + CRLF +
    '        <CfgParent>Base</CfgParent>' + CRLF +
    '        <Base>true</Base>' + CRLF +
    '    </PropertyGroup>' + CRLF +
    '    <PropertyGroup Condition="''$(Config)''==''Release'' or ''$(Cfg_1)''!=''''">' + CRLF +
    '        <Cfg_1>true</Cfg_1>' + CRLF +
    '        <CfgParent>Base</CfgParent>' + CRLF +
    '        <Base>true</Base>' + CRLF +
    '    </PropertyGroup>' + CRLF +
    '    <PropertyGroup Condition="''$(Config)''==''Debug'' or ''$(Cfg_2)''!=''''">' + CRLF +
    '        <Cfg_2>true</Cfg_2>' + CRLF +
    '        <CfgParent>Base</CfgParent>' + CRLF +
    '        <Base>true</Base>' + CRLF +
    '    </PropertyGroup>' + CRLF +
    '    <PropertyGroup Condition="''$(Base)''!=''''">' + CRLF +
    '        ' + XmlElemento('SanitizedProjectName', AName) + CRLF +
    '        <DCC_ExeOutput>.\$(Platform)\$(Config)</DCC_ExeOutput>' + CRLF +
    '        <DCC_DcuOutput>.\$(Platform)\$(Config)\dcu</DCC_DcuOutput>' + CRLF +
    PkgProps +
    '        <VerInfo_Locale>1033</VerInfo_Locale>' + CRLF +
    '        <DCC_Namespace>Winapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win;System;Xml;Data;Datasnap;Web;Soap;Vcl;Vcl.Imaging;Vcl.Touch;Vcl.Samples;Vcl.Shell;$(DCC_Namespace)</DCC_Namespace>' + CRLF +
    '    </PropertyGroup>' + CRLF +
    '    <ItemGroup>' + CRLF +
    '        <DelphiCompile Include="$(MainSource)">' + CRLF +
    '            <MainSource>MainSource</MainSource>' + CRLF +
    '        </DelphiCompile>' + CRLF +
    FormRef +
    '        <BuildConfiguration Include="Base">' + CRLF +
    '            <Key>Base</Key>' + CRLF +
    '        </BuildConfiguration>' + CRLF +
    '        <BuildConfiguration Include="Release">' + CRLF +
    '            <Key>Cfg_1</Key>' + CRLF +
    '            <CfgParent>Base</CfgParent>' + CRLF +
    '        </BuildConfiguration>' + CRLF +
    '        <BuildConfiguration Include="Debug">' + CRLF +
    '            <Key>Cfg_2</Key>' + CRLF +
    '            <CfgParent>Base</CfgParent>' + CRLF +
    '        </BuildConfiguration>' + CRLF +
    '    </ItemGroup>' + CRLF +
    '    <ProjectExtensions>' + CRLF +
    '        <Borland.Personality>Delphi.Personality.12</Borland.Personality>' + CRLF +
    '        ' + XmlElemento('Borland.ProjectType', ProjectType) + CRLF +
    '        <BorlandProject>' + CRLF +
    '            <Delphi.Personality>' + CRLF +
    '                <Source>' + CRLF +
    '                    <Source Name="MainSource">' + XmlEscape(AName + MainExt) + '</Source>' + CRLF +
    '                </Source>' + CRLF +
    '            </Delphi.Personality>' + CRLF +
    '            <Platforms>' + CRLF +
    '                <Platform value="Win32">True</Platform>' + CRLF +
    '                <Platform value="Win64">True</Platform>' + CRLF +
    '            </Platforms>' + CRLF +
    '        </BorlandProject>' + CRLF +
    '    </ProjectExtensions>' + CRLF +
    '    <Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets" Condition="Exists(''$(BDS)\Bin\CodeGear.Delphi.Targets'')"/>' + CRLF +
    '    <Import Project="$(APPDATA)\Embarcadero\$(BDSAPPDATABASEDIR)\$(PRODUCTVERSION)\UserTools.proj" Condition="Exists(''$(APPDATA)\Embarcadero\$(BDSAPPDATABASEDIR)\$(PRODUCTVERSION)\UserTools.proj'')"/>' + CRLF +
    '</Project>' + CRLF;
end;

function VclFormPas(const AUnitName, AFormName: string): string;
begin
  Result :=
    'unit ' + AUnitName + ';' + CRLF + CRLF +
    'interface' + CRLF + CRLF +
    'uses' + CRLF +
    '  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,' + CRLF +
    '  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs;' + CRLF + CRLF +
    'type' + CRLF +
    '  T' + AFormName + ' = class(TForm)' + CRLF +
    '  private' + CRLF +
    '  public' + CRLF +
    '  end;' + CRLF + CRLF +
    'var' + CRLF +
    '  ' + AFormName + ': T' + AFormName + ';' + CRLF + CRLF +
    'implementation' + CRLF + CRLF +
    '{$R *.dfm}' + CRLF + CRLF +
    'end.' + CRLF;
end;

function VclFormDfm(const AFormName: string): string;
begin
  Result :=
    ComponeLineaDeObjeto('object', AFormName, 'T' + AFormName) + CRLF +
    '  Left = 0' + CRLF +
    '  Top = 0' + CRLF +
    string.Join(CRLF, LineasDePropiedad('  ', 'Caption', TrozosDeLiteral(AFormName))) + CRLF +
    '  ClientHeight = 420' + CRLF +
    '  ClientWidth = 620' + CRLF +
    '  Color = clBtnFace' + CRLF +
    '  Font.Charset = DEFAULT_CHARSET' + CRLF +
    '  Font.Color = clWindowText' + CRLF +
    '  Font.Height = -12' + CRLF +
    '  Font.Name = ''Segoe UI''' + CRLF +
    '  Font.Style = []' + CRLF +
    '  TextHeight = 15' + CRLF +
    'end' + CRLF;
end;

function FmxFormPas(const AUnitName, AFormName: string): string;
begin
  Result :=
    'unit ' + AUnitName + ';' + CRLF + CRLF +
    'interface' + CRLF + CRLF +
    'uses' + CRLF +
    '  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,' + CRLF +
    '  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs;' + CRLF + CRLF +
    'type' + CRLF +
    '  T' + AFormName + ' = class(TForm)' + CRLF +
    '  private' + CRLF +
    '  public' + CRLF +
    '  end;' + CRLF + CRLF +
    'var' + CRLF +
    '  ' + AFormName + ': T' + AFormName + ';' + CRLF + CRLF +
    'implementation' + CRLF + CRLF +
    '{$R *.fmx}' + CRLF + CRLF +
    'end.' + CRLF;
end;

function FmxFormFmx(const AFormName: string): string;
begin
  Result :=
    ComponeLineaDeObjeto('object', AFormName, 'T' + AFormName) + CRLF +
    '  Left = 0' + CRLF +
    '  Top = 0' + CRLF +
    string.Join(CRLF, LineasDePropiedad('  ', 'Caption', TrozosDeLiteral(AFormName))) + CRLF +
    '  ClientHeight = 480' + CRLF +
    '  ClientWidth = 640' + CRLF +
    '  FormFactor.Width = 320' + CRLF +
    '  FormFactor.Height = 480' + CRLF +
    '  FormFactor.Devices = [Desktop]' + CRLF +
    '  DesignerMasterStyle = 0' + CRLF +
    'end' + CRLF;
end;

function VclFramePas(const AUnitName, AFrameName: string): string;
begin
  Result :=
    'unit ' + AUnitName + ';' + CRLF + CRLF +
    'interface' + CRLF + CRLF +
    'uses' + CRLF +
    '  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,' + CRLF +
    '  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs;' + CRLF + CRLF +
    'type' + CRLF +
    '  T' + AFrameName + ' = class(TFrame)' + CRLF +
    '  private' + CRLF +
    '  public' + CRLF +
    '  end;' + CRLF + CRLF +
    'implementation' + CRLF + CRLF +
    '{$R *.dfm}' + CRLF + CRLF +
    'end.' + CRLF;
end;

function VclFrameDfm(const AFrameName: string): string;
begin
  Result :=
    ComponeLineaDeObjeto('object', AFrameName, 'T' + AFrameName) + CRLF +
    '  Left = 0' + CRLF +
    '  Top = 0' + CRLF +
    '  Width = 320' + CRLF +
    '  Height = 240' + CRLF +
    '  TabOrder = 0' + CRLF +
    'end' + CRLF;
end;

function FmxFramePas(const AUnitName, AFrameName: string): string;
begin
  Result :=
    'unit ' + AUnitName + ';' + CRLF + CRLF +
    'interface' + CRLF + CRLF +
    'uses' + CRLF +
    '  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,' + CRLF +
    '  FMX.Types, FMX.Graphics, FMX.Controls, FMX.Forms, FMX.Dialogs, FMX.StdCtrls;' + CRLF + CRLF +
    'type' + CRLF +
    '  T' + AFrameName + ' = class(TFrame)' + CRLF +
    '  private' + CRLF +
    '  public' + CRLF +
    '  end;' + CRLF + CRLF +
    'implementation' + CRLF + CRLF +
    '{$R *.fmx}' + CRLF + CRLF +
    'end.' + CRLF;
end;

function FmxFrameFmx(const AFrameName: string): string;
begin
  Result :=
    ComponeLineaDeObjeto('object', AFrameName, 'T' + AFrameName) + CRLF +
    '  Size.Width = ' + FlotanteFmx(320) + CRLF +
    '  Size.Height = ' + FlotanteFmx(240) + CRLF +
    '  Size.PlatformDefault = False' + CRLF +
    'end' + CRLF;
end;

{ A data module is framework-neutral Pascal; only the class group differs
  (it tells the designer which control set the module belongs to). }
function DataModulePas(const AUnitName, AModuleName: string; AFmx: Boolean): string;
begin
  Result :=
    'unit ' + AUnitName + ';' + CRLF + CRLF +
    'interface' + CRLF + CRLF +
    'uses' + CRLF +
    '  System.SysUtils, System.Classes;' + CRLF + CRLF +
    'type' + CRLF +
    '  T' + AModuleName + ' = class(TDataModule)' + CRLF +
    '  private' + CRLF +
    '  public' + CRLF +
    '  end;' + CRLF + CRLF +
    'var' + CRLF +
    '  ' + AModuleName + ': T' + AModuleName + ';' + CRLF + CRLF +
    'implementation' + CRLF + CRLF +
    IfThen(AFmx, '{%CLASSGROUP ''FMX.Controls.TControl''}', '{%CLASSGROUP ''Vcl.Controls.TControl''}') + CRLF + CRLF +
    '{$R *.dfm}' + CRLF + CRLF +
    'end.' + CRLF;
end;

function DataModuleDfm(const AModuleName: string): string;
begin
  Result :=
    ComponeLineaDeObjeto('object', AModuleName, 'T' + AModuleName) + CRLF +
    '  Height = 480' + CRLF +
    '  Width = 640' + CRLF +
    'end' + CRLF;
end;

{ Why a syntactically valid identifier can still be a terrible unit name.
  Measured, field round 8: `delphi_create kind=unit name=begin` was accepted
  and the next build died with 17 cascading errors on the .dpr; `name=System`
  was accepted and quietly hijacked the RTL's own unit. The old check only
  asked "is this an identifier", which both of those pass. }
function BadUnitName(const AName: string): string;
const
  // Units of the RTL/VCL/FMX habitually reached unqualified. A file with one
  // of these names next to the project shadows the real one, and the error
  // the compiler then gives points anywhere but here.
  RTL: array [0 .. 27] of string = ('System', 'SysUtils', 'Classes', 'Types',
    'Variants', 'Math', 'Windows', 'Messages', 'Forms', 'Controls',
    'Graphics', 'Dialogs', 'StdCtrls', 'ExtCtrls', 'ComCtrls', 'Menus',
    'Buttons', 'DB', 'IniFiles', 'Registry', 'StrUtils', 'DateUtils',
    'IOUtils', 'Character', 'Generics', 'Threading', 'JSON', 'Contnrs');
  // The namespaces the compiler itself owns: anything under them belongs to
  // Embarcadero, and a file of ours with that name wins over theirs.
  NAMESPACES: array [0 .. 13] of string = ('System', 'Vcl', 'FMX', 'Data',
    'Datasnap', 'Web', 'Soap', 'Xml', 'Bde', 'IBX', 'REST', 'Winapi',
    'Posix', 'FireDAC');
var
  W, Head: string;
begin
  Result := '';
  // Ident(.Ident)*: dotted namespaces are legal Delphi (MyApp.Forms.Main);
  // EL identificador (Lsp.Pascal), con letras de cualquier alfabeto
  if not EsIdentificador(AName, True) then
    Exit(MsgFmt(SR_CREATE_BADNAME_FMT, [AName]));
  // every dotted segment must be clean, not just the whole thing: a reserved
  // word (the lexicon's list, Lsp.Pascal) in a .dpr uses clause is E2029
  for Head in AName.Split(['.']) do
    if EsPalabraReservada(Head) then
      Exit(MsgFmt(SR_CREATE_RESERVED_FMT, [Head, AName]));
  for W in RTL do
    if SameText(AName, W) then
      Exit(MsgFmt(SR_CREATE_RTLNAME_FMT, [AName, AName, AName]));
  // "a namespaced name shadows nothing" was wrong, and the refusal above even
  // RECOMMENDED adding a dot: `name=System.SysUtils` was accepted and planted
  // an empty System.SysUtils.pas next to the .dpr, after which `Exception`
  // stopped existing (measured 2026-08-25). A first segment that IS an RTL
  // namespace is the same hijack with more letters.
  Head := PrimerTrozo(AName, ['.']);
  if AName.Contains('.') then
    for W in NAMESPACES do
      if SameText(Head, W) then
        Exit(MsgFmt(SR_CREATE_RTLNS_FMT, [AName, Head, Head]));
end;

function CreateDelphiProject(const ADir, AName, AKind: string): string;
var
  Kind, Dir, Dpr, Dproj, MainUnit, MainForm, Clash: string;
  Files: TStringList;
begin
  Kind := AKind.Trim.ToLower;
  if (Kind <> 'console') and (Kind <> 'vcl') and (Kind <> 'fmx') and (Kind <> 'package') and
     (Kind <> 'test') then
    // The caller wrote "project-web": answering "console | vcl | fmx" sends
    // them to write kind=console, which is refused too. Name the values that
    // work (field round 10).
    Exit(MsgText(SR_CREATE_PROJECT_KIND));
  if not EsIdentificador(AName) then
    Exit(MsgFmt(SR_CREATE_IDENTIFICADOR_NOMBRE_PROYECTO_FMT, [AName]));

  Result := BadUnitName(AName);
  if Result <> '' then
    Exit;
  if ADir.Trim = '' then
    Exit(MsgText(SR_CREATE_NEED_DIR));
  // un PROYECTO nuevo va en una ruta absoluta: la relativa (que dir admite
  // dentro de un proyecto) se resolvia aqui contra la carpeta del proceso
  Result := RutaRelativaDenegada(ADir);
  if Result <> '' then
    Exit;

  Dir := TPath.GetFullPath(ADir);
  Result := WriteTargetDenied(Dir);
  if Result <> '' then
    Exit;
  Dpr := TPath.Combine(Dir, AName + IfThen(Kind = 'package', '.dpk', '.dpr'));
  Dproj := DprojDe(Dpr); // el .dproj de su .dpr/.dpk: el nombrador de la casa
  if TFile.Exists(Dpr) or TFile.Exists(Dproj) or
     TFile.Exists(TPath.Combine(Dir, AName + '.dpr')) or TFile.Exists(TPath.Combine(Dir, AName + '.dpk')) then
    Exit(MsgFmt(SR_CREATE_YA_EXISTE_PROYECTO_FMT, [AName, Dir]));
  // All or nothing. The files used to be written one by one, so a collision
  // on the THIRD of them (the UMain.pas of a project already living in that
  // folder) left an orphan .dpr behind - pointing at somebody else's unit,
  // with no .dproj, and blocking the retry with "ya existe un proyecto".
  // Measured, field round 8. Every target is checked BEFORE anything is
  // written, and the folder is not even created when the answer is no.
  MainUnit := 'UMain';
  MainForm := 'FormMain';
  if Kind = 'test' then
    MainUnit := 'U' + AName; // el primer fixture, con el nombre del proyecto
  if (Kind <> 'console') and (Kind <> 'package') then
  begin
    Clash := '';
    if TFile.Exists(TPath.Combine(Dir, MainUnit + '.pas')) then
      Clash := MainUnit + '.pas'
    else if (Kind = 'vcl') and TFile.Exists(TPath.Combine(Dir, MainUnit + '.dfm')) then
      Clash := MainUnit + '.dfm'
    else if (Kind = 'fmx') and TFile.Exists(TPath.Combine(Dir, MainUnit + '.fmx')) then
      Clash := MainUnit + '.fmx';
    if Clash <> '' then
      Exit(MsgFmt(SR_CREATE_CLASH_FMT, [Clash, Dir, AName]));
  end;
  CrearCarpeta(Dir);

  Files := TStringList.Create;
  try
    if Kind = 'package' then
    begin
      // Un paquete RUNTIME propio: requires rtl y sin contains (una clausula
      // contains vacia no es legal; la primera kind=unit la escribe). Ni se
      // instala ni se registra en el IDE: se compila a BPL+DCP en su carpeta.
      // Hermes, bateria 1.2 caso 1 (2026-09-23): sin esto un agente no podia
      // empezar un paquete propio.
      WriteNewFile(Dpr,
        'package ' + AName + ';' + CRLF + CRLF +
        '{$R *.res}' + CRLF +
        '{$IMPLICITBUILD ON}' + CRLF + CRLF +
        'requires' + CRLF +
        '  rtl;' + CRLF + CRLF +
        'end.' + CRLF);
      WriteNewFile(Dproj,
        DprojTemplate(AName, NewGuidStr, 'Package', 'None', '', '', ''));
      Files.Add(AName + '.dpk');
      Files.Add(TPath.GetFileName(Dproj));
    end
    else if Kind = 'console' then
    begin
      WriteNewFile(Dpr,
        'program ' + AName + ';' + CRLF + CRLF +
        '{$APPTYPE CONSOLE}' + CRLF + CRLF +
        'uses' + CRLF +
        '  System.SysUtils;' + CRLF + CRLF +
        'begin' + CRLF +
        '  try' + CRLF +
        '    Writeln(''' + AName + ' running'');' + CRLF +
        '  except' + CRLF +
        '    on E: Exception do' + CRLF +
        '      Writeln(E.ClassName, '': '', E.Message);' + CRLF +
        '  end;' + CRLF +
        'end.' + CRLF);
      WriteNewFile(Dproj,
        DprojTemplate(AName, NewGuidStr, 'Console', 'None', '', '', ''));
      Files.Add(AName + '.dpr');
      Files.Add(TPath.GetFileName(Dproj));
    end
    else if Kind = 'test' then
    begin
      // Un proyecto de TEST: el runner DUnitX de consola que el IDE genera
      // con su asistente, y el primer fixture ya registrado, verde al nacer.
      // DUnitX viene con RAD Studio (Library Path): no se instala nada.
      // Hermes se quedo sin saber montarlo (test 27, 22-sep-2026) y el
      // esqueleto viajo por nota; ahora lo escribe la tool y delphi_test
      // lo reconoce (usa DUnitX) y lo corre. Sale con ExitCode 1 si algo
      // falla: el veredicto de delphi_test no depende de leer la consola.
      // CheckCommandLine es lo que lee --run: sin el, el filter de
      // delphi_test corria TODOS los tests (quinta revision).
      WriteNewFile(Dpr,
        'program ' + AName + ';' + CRLF + CRLF +
        '{$APPTYPE CONSOLE}' + CRLF + CRLF +
        'uses' + CRLF +
        '  System.SysUtils,' + CRLF +
        '  DUnitX.TestFramework,' + CRLF +
        '  DUnitX.Loggers.Console,' + CRLF +
        '  ' + MainUnit + ' in ''' + MainUnit + '.pas'';' + CRLF + CRLF +
        'var' + CRLF +
        '  Runner: ITestRunner;' + CRLF +
        '  Logger: ITestLogger;' + CRLF +
        '  Results: IRunResults;' + CRLF + CRLF +
        'begin' + CRLF +
        '  try' + CRLF +
        '    // --run:<filter> (delphi_test''s filter) is read here' + CRLF +
        '    TDUnitX.CheckCommandLine;' + CRLF +
        '    Runner := TDUnitX.CreateRunner;' + CRLF +
        '    Logger := TDUnitXConsoleLogger.Create(True);' + CRLF +
        '    Runner.AddLogger(Logger);' + CRLF +
        '    Results := Runner.Execute;' + CRLF +
        '    if not Results.AllPassed then' + CRLF +
        '      ExitCode := 1;' + CRLF +
        '  except' + CRLF +
        '    on E: Exception do' + CRLF +
        '    begin' + CRLF +
        '      Writeln(E.ClassName, '': '', E.Message);' + CRLF +
        '      ExitCode := 2;' + CRLF +
        '    end;' + CRLF +
        '  end;' + CRLF +
        'end.' + CRLF);
      WriteNewFile(TPath.Combine(Dir, MainUnit + '.pas'),
        'unit ' + MainUnit + ';' + CRLF + CRLF +
        'interface' + CRLF + CRLF +
        'uses' + CRLF +
        '  DUnitX.TestFramework;' + CRLF + CRLF +
        'type' + CRLF +
        '  [TestFixture]' + CRLF +
        '  T' + AName + ' = class' + CRLF +
        '  public' + CRLF +
        '    [Test]' + CRLF +
        '    procedure Skeleton;' + CRLF +
        '  end;' + CRLF + CRLF +
        'implementation' + CRLF + CRLF +
        'procedure T' + AName + '.Skeleton;' + CRLF +
        'begin' + CRLF +
        '  Assert.AreEqual(4, 2 + 2, ''the test project skeleton runs'');' + CRLF +
        'end;' + CRLF + CRLF +
        'initialization' + CRLF +
        '  TDUnitX.RegisterTestFixture(T' + AName + ');' + CRLF + CRLF +
        'end.' + CRLF);
      WriteNewFile(Dproj,
        DprojTemplate(AName, NewGuidStr, 'Console', 'None', MainUnit, '', ''));
      Files.Add(AName + '.dpr');
      Files.Add(TPath.GetFileName(Dproj));
      Files.Add(MainUnit + '.pas');
    end
    else
    begin
      MainUnit := 'UMain';
      MainForm := 'FormMain';
      if Kind = 'vcl' then
      begin
        WriteNewFile(Dpr,
          'program ' + AName + ';' + CRLF + CRLF +
          'uses' + CRLF +
          '  Vcl.Forms,' + CRLF +
          '  ' + MainUnit + ' in ''' + MainUnit + '.pas'' {' + MainForm + '};' + CRLF + CRLF +
          '{$R *.res}' + CRLF + CRLF +
          'begin' + CRLF +
          '  Application.Initialize;' + CRLF +
          '  Application.MainFormOnTaskbar := True;' + CRLF +
          '  Application.CreateForm(T' + MainForm + ', ' + MainForm + ');' + CRLF +
          '  Application.Run;' + CRLF +
          'end.' + CRLF);
        WriteNewFile(TPath.Combine(Dir, MainUnit + '.pas'), VclFormPas(MainUnit, MainForm));
        WriteNewFile(TPath.Combine(Dir, MainUnit + '.dfm'), VclFormDfm(MainForm));
        WriteNewFile(Dproj,
          DprojTemplate(AName, NewGuidStr, 'Application', 'VCL', MainUnit, MainForm, 'dfm'));
      end
      else // fmx
      begin
        WriteNewFile(Dpr,
          'program ' + AName + ';' + CRLF + CRLF +
          'uses' + CRLF +
          '  System.StartUpCopy,' + CRLF +
          '  FMX.Forms,' + CRLF +
          '  ' + MainUnit + ' in ''' + MainUnit + '.pas'' {' + MainForm + '};' + CRLF + CRLF +
          '{$R *.res}' + CRLF + CRLF +
          'begin' + CRLF +
          '  Application.Initialize;' + CRLF +
          '  Application.CreateForm(T' + MainForm + ', ' + MainForm + ');' + CRLF +
          '  Application.Run;' + CRLF +
          'end.' + CRLF);
        WriteNewFile(TPath.Combine(Dir, MainUnit + '.pas'), FmxFormPas(MainUnit, MainForm));
        WriteNewFile(TPath.Combine(Dir, MainUnit + '.fmx'), FmxFormFmx(MainForm));
        WriteNewFile(Dproj,
          DprojTemplate(AName, NewGuidStr, 'Application', 'FMX', MainUnit, MainForm, 'fmx'));
      end;
      Files.Add(AName + '.dpr');
      Files.Add(TPath.GetFileName(Dproj));
      Files.Add(MainUnit + '.pas');
      if Kind = 'vcl' then Files.Add(MainUnit + '.dfm') else Files.Add(MainUnit + '.fmx');
    end;

    // A basic .gitignore so the first commit stays clean of build artifacts
    // and tool backups; the agent may edit it later with delphi_textedit.
    if not TFile.Exists(TPath.Combine(Dir, '.gitignore')) then
    begin
      { Esta lista y la del propio repo del servidor son la misma cosa escrita
        dos veces, y se habian separado: aqui faltaban los .map -decenas de MB
        en un proyecto de verdad, y ademas publican la disposicion de simbolos-
        junto con los .drc, los .rsm, los binarios y las carpetas de salida que
        no son Win32/Win64. Lo vio David el 2026-09-21 mirando esta misma linea
        ("donde has dejado los maps?"). Si se anade algo aqui, va tambien al
        .gitignore del repo, y al reves. }
      WriteNewFile(TPath.Combine(Dir, '.gitignore'),
        'Compiled/' + CRLF + 'Win32/' + CRLF + 'Win64/' + CRLF +
        'Linux64/' + CRLF + 'Android/' + CRLF + 'Android64/' + CRLF +
        'OSX64/' + CRLF + 'Debug/' + CRLF + 'Release/' + CRLF +
        '*.dcu' + CRLF + '*.dcp' + CRLF + '*.bpl' + CRLF +
        '*.exe' + CRLF + '*.dll' + CRLF +
        '*.map' + CRLF + '*.drc' + CRLF + '*.rsm' + CRLF +
        '*.local' + CRLF + '*.identcache' + CRLF + '*.projdata' + CRLF +
        '*.tvsconfig' + CRLF + '*.stat' + CRLF + '*.~*' + CRLF +
        TrashFolderName + '/' + CRLF + TempFolderName + '/' + CRLF +
        '__history/' + CRLF + '__recovery/' + CRLF +
        '*-deploy.zip' + CRLF + '*.delphilsp.json' + CRLF);
      Files.Add('.gitignore');
    end;

    Result := MsgFmt(SK_CREATE_CREADO_PROYECTO_FMT,
      [AName, Kind, Dir, string.Join(', ', Files.ToStringArray), NewFileEncName,
       IfThen(Kind = 'package', #10 + MsgText(SN_CREATE_PACKAGE_NOTE),
         IfThen(Kind = 'test', #10 + MsgFmt(SN_CREATE_TEST_NOTE_FMT, [AName, MainUnit]), ''))]);
  finally
    Files.Free;
  end;
end;

{ Which framework a project belongs to, read from its own source ('vcl',
  'fmx', or '' when it cannot be told). The .dpr says it plainly in its uses
  clause, and the .dpr is the file a new form gets registered in. }
function ProjectFramework(const APath: string): string;
var
  Dpr, Txt, Enc: string;
begin
  Result := '';
  Dpr := APath;
  if SameText(TPath.GetExtension(Dpr), '.dproj') then
    Dpr := TPath.ChangeExtension(Dpr, '.dpr');
  if not TFile.Exists(Dpr) then
    Exit;
  try
    Txt := PatchLoadText(Dpr, Enc);
  except
    Exit;
  end;
  if TRegEx.IsMatch(Txt, '(?i)\bFMX\.Forms\b') then
    Result := 'fmx'
  else if TRegEx.IsMatch(Txt, '(?i)\bVcl\.Forms\b') then
    Result := 'vcl';
end;

{ DONDE CAE LO QUE SE CREA DENTRO DE UN PROYECTO: la estructura de carpetas la
  decide el programador (o el agente), no el scaffolder. Hasta la v1.0.14 una
  unit, un form, un frame o un data module caian SIEMPRE junto al .dpr, y el
  "dir" que un agente pasaba de forma natural se IGNORABA EN SILENCIO - la
  respuesta decia "CREADA" con la unit en otro sitio (medido en vivo el
  2026-09-21; el 25-ago ya se habia visto a los agentes pasarlo, y entonces
  solo se mejoro el mensaje). David: "tenemos que poder hacer una estructura
  de subcarpetas a gusto del programador", y "tienen que ser carpetas dentro
  de la jaula".

  ASubDir es RELATIVO a la carpeta del proyecto, con los niveles que se
  quiera (Dominio\Modelos\Dto). QUE es una carpeta relativa valida no se
  decide aqui: lo decide ValidOutputFolder (Lsp.Dproj), la misma regla de
  set-output - sin unidad, sin absolutas, sin ".." y con su lista blanca de
  caracteres, porque esta ruta acaba escrita en el DCCReference del .dproj y
  en el in '..' del .dpr. La primera version de esta funcion la reescribia a
  mano y SIN la lista blanca: habria reabierto la inyeccion R5-B. Aqui solo
  queda lo propio: colgarla del proyecto y pasar la jaula - PathDenied mide
  con RealPath, asi que un junction dentro del proyecto tampoco sirve para
  salirse. La usan las DOS gemelas (unit y form/frame/datamodule); registrar
  lo hace AddProjectUnit, que ya componia bien el in 'sub\X.pas'. }
function CarpetaEnElProyecto(const ADprPath, ASubDir: string;
  out ADir: string): string;
var
  S: string;
begin
  Result := '';
  ADir := TPath.GetDirectoryName(TPath.GetFullPath(ADprPath));
  if ASubDir.Trim = '' then
    Exit;
  if not ValidOutputFolder(ASubDir, S) then
    Exit(MsgFmt(SR_CREATE_SUBDIR_REL_FMT, [ASubDir]));
  ADir := TPath.Combine(ADir, S);
  Result := WriteTargetDenied(ADir); // jaula + carpetas muertas, UNA puerta
end;

function CreateDelphiForm(const ADprPath, AUnitName, AFormName, AKind: string;
  const ASubDir: string): string;
var
  Kind, Dir, FormName, PasPath, DesignerExt, Have, Want, FrameworkNote: string;
  Fmx: Boolean;
begin
  Kind := AKind.Trim.ToLower;
  if (Kind <> 'vcl') and (Kind <> 'fmx') and (Kind <> 'frame-vcl') and
     (Kind <> 'frame-fmx') and (Kind <> 'datamodule') then
    Exit(MsgText(SR_CREATE_KIND_DEBE_SER_FORM));
  Result := WriteTargetDenied(ADprPath);
  if Result <> '' then
    Exit;
  // "project" tiene que ser un PROYECTO antes de escribir nada: con un .txt
  // se creaban el .pas y el .dfm y luego no se podian registrar
  if not MatchText(TPath.GetExtension(ADprPath), ['.dpr', '.dproj', '.dpk']) then
    Exit(MsgFmt(SR_UNIT_PROJECT_EXT_FMT, [ADprPath]));
  if not TFile.Exists(ADprPath) then
    Exit(NoEsFichero(ADprPath, MsgFmt(SR_CREATE_NO_EXISTE_PROYECTO_FMT, [ADprPath])));
  Result := BadUnitName(AUnitName);
  if Result <> '' then
    Exit;
  // A form of the OTHER framework used to be accepted silently, which put an
  // FMX form and its Application.CreateForm inside a .dpr that uses Vcl.Forms
  // (field round 8). The project says which one it is in its own uses clause.
  if Kind <> 'datamodule' then
  begin
    Have := ProjectFramework(ADprPath);
    Want := IfThen(Kind.EndsWith('fmx'), 'fmx', 'vcl');
    if (Have <> '') and (Have <> Want) then
      Exit(MsgFmt(SR_CREATE_FRAMEWORK_FMT,
        [AKind, TPath.GetFileName(ADprPath), UpperCase(Have)]));
    // A CONSOLE project has no framework at all, so the mismatch check above
    // says nothing - and a form went in without a word (field round 10). It
    // compiles; it just never shows, because there is no Application to run
    // it. Allowed, because turning a console project into a GUI one is a
    // real thing to do, but never silently.
    if Have = '' then
      FrameworkNote := MsgText(SN_CREATE_CONSOLE_FORM);
  end;
  FormName := AFormName.Trim;
  if FormName = '' then
  begin
    if Kind.StartsWith('frame') then
      FormName := 'Frame' + AUnitName
    else if Kind = 'datamodule' then
      FormName := 'DM' + AUnitName
    else
      FormName := 'Form' + AUnitName;
  end;
  if TRegEx.IsMatch(FormName, '\A' + PATRON_NOMBRE_TIPO) then
    FormName := FormName.Substring(1); // the T prefix goes on the class only
  if not EsIdentificador(FormName) then
    Exit(MsgFmt(SR_CREATE_IDENTIFICADOR_FORM_FMT, [FormName]));

  Result := CarpetaEnElProyecto(ADprPath, ASubDir, Dir);
  if Result <> '' then
    Exit;
  PasPath := TPath.Combine(Dir, AUnitName + '.pas');
  if TFile.Exists(PasPath) then
    Exit(MsgFmt(SR_CREATE_YA_EXISTE_SOBREESCRIBE_FMT, [PasPath]));
  // ...y su designer: un .dfm/.fmx que ya estaba hacia saltar el SEGUNDO
  // WriteNewFile con el .pas ya escrito (sexta revision). Todo se mira
  // ANTES de escribir nada, como en CreateDelphiProject.
  if MatchText(Kind, ['fmx', 'frame-fmx']) then
    DesignerExt := '.fmx'
  else
    DesignerExt := '.dfm';
  if TFile.Exists(TPath.Combine(Dir, AUnitName + DesignerExt)) then
    Exit(MsgFmt(SR_CREATE_YA_EXISTE_SOBREESCRIBE_FMT,
      [TPath.Combine(Dir, AUnitName + DesignerExt)]));

  // TODO O NADA (quinta revision): si el registro no se puede (o lanza: un
  // .dproj que otro proceso tiene abierto), el par creado se quita. Quedaba
  // creado, la respuesta decia "repite" y repetir chocaba con "ya existe".
  var FotoCrea: TFotoDeFicheros;
  FotoCrea.Toma([PasPath, TPath.Combine(Dir, AUnitName + '.dfm'),
    TPath.Combine(Dir, AUnitName + '.fmx')]);
  // 1) the pair of files - y si uno de los dos no se puede escribir (un
  // disco, un permiso), el otro no se queda: la misma foto lo deshace
  DesignerExt := '.dfm';
  try
  if Kind = 'vcl' then
  begin
    WriteNewFile(PasPath, VclFormPas(AUnitName, FormName));
    WriteNewFile(TPath.Combine(Dir, AUnitName + '.dfm'), VclFormDfm(FormName));
  end
  else if Kind = 'fmx' then
  begin
    DesignerExt := '.fmx';
    WriteNewFile(PasPath, FmxFormPas(AUnitName, FormName));
    WriteNewFile(TPath.Combine(Dir, AUnitName + '.fmx'), FmxFormFmx(FormName));
  end
  else if Kind = 'frame-vcl' then
  begin
    WriteNewFile(PasPath, VclFramePas(AUnitName, FormName));
    WriteNewFile(TPath.Combine(Dir, AUnitName + '.dfm'), VclFrameDfm(FormName));
  end
  else if Kind = 'frame-fmx' then
  begin
    DesignerExt := '.fmx';
    WriteNewFile(PasPath, FmxFramePas(AUnitName, FormName));
    WriteNewFile(TPath.Combine(Dir, AUnitName + '.fmx'), FmxFrameFmx(FormName));
  end
  else
  begin
    // data module: the designer file is a .dfm on BOTH frameworks
    Fmx := SameText(ReadDproj(DprojDe(TPath.GetFullPath(ADprPath))).FrameworkType, 'FMX');
    WriteNewFile(PasPath, DataModulePas(AUnitName, FormName, Fmx));
    WriteNewFile(TPath.Combine(Dir, AUnitName + '.dfm'), DataModuleDfm(FormName));
  end;
  except
    on E: Exception do
    begin
      var NoVolvioPar := FotoCrea.Restaura;
      if NoVolvioPar <> '' then
        Exit(MsgFmt(SR_FOTO_NO_VOLVIO_FMT, [NoVolvioPar, E.Message]));
      if EsFallo(E.Message) then
        Exit(E.Message); // la negativa de WriteNewFile, tal cual
      Exit(MsgExcepcion(E.ClassName, E.Message));
    end;
  end;

  // 2) register in the .dpr (uses + CreateForm) and the .dproj (DCCReference)
  try
    Result := AddProjectUnit(ADprPath, PasPath);
  except
    on E: Exception do
      Result := MsgExcepcion(E.ClassName, E.Message);
  end;
  if EsFallo(Result) then
  begin
    var NoVolvio := FotoCrea.Restaura;
    if NoVolvio <> '' then
      Exit(MsgFmt(SR_FOTO_NO_VOLVIO_FMT, [NoVolvio, Result]));
    Result := MsgConCausa(SR_CREATE_CREADOS_NO_REGISTRADOS_FMT, Result, [AUnitName, DesignerExt, Result]);
  end
  else
    Result := MsgFmt(SK_CREATE_CREADO_FORM_FMT,
      [IfThen(Kind.StartsWith('frame'), MsgText(SF_CREATE_CLASE_FRAME), IfThen(Kind = 'datamodule', MsgText(SF_CREATE_CLASE_DATA_MODULE), MsgText(SF_CREATE_CLASE_FORM))),
       AUnitName, FormName, Kind, AUnitName + DesignerExt, Result,
       IfThen(FrameworkNote <> '', #10 + FrameworkNote, '')]);
end;

{ El fuente de una unit: el content del agente, comprobado (su `unit X;` es
  el nombre, acaba en `end.`) y con CRLF; sin content, el esqueleto vacio. ''
  en ABody y el motivo en el resultado si no vale. UNA regla para la unit de
  un proyecto y para la suelta. }
function CuerpoDeUnit(const AUnitName, AContent: string; out ABody: string): string;
begin
  Result := '';
  ABody := AContent;
  if ABody.Trim <> '' then
  begin
    // la regla del content, la de delphi_edit createunit (Lsp.Patch)
    Result := ContenidoDeUnitNoValido(AUnitName, ABody);
    if Result <> '' then
      Exit;
    ABody := ConSalto(ABody, CRLF); // el normalizador de todos (Lsp.Patch)
    if not ABody.EndsWith(CRLF) then
      ABody := ABody + CRLF;
  end
  else
    ABody :=
      'unit ' + AUnitName + ';' + CRLF + CRLF +
      'interface' + CRLF + CRLF +
      'implementation' + CRLF + CRLF +
      'end.' + CRLF;
end;

{ Un fuente SUELTO en una carpeta ABSOLUTA de la jaula, que ningun proyecto
  lista todavia: una unit que comparten dos programas desde ramas IFDEF de
  sus uses, o un .inc. No habia tool para crearlo (el muro del 26-sep-2026:
  delphi_textedit rechaza las extensiones Delphi y kind=unit exigia
  proyecto). Misma puerta, mismo escritor y la misma codificacion que todo lo
  que crea el scaffolder; jamas sobreescribe. }
function CreaFuenteSuelto(const ADir, ANombre, AExt, ABody: string; out ARuta: string): string;
begin
  ARuta := '';
  Result := BadUnitName(ANombre);
  if Result <> '' then
    Exit;
  if (ADir.Trim = '') or not EsRutaAbsoluta(ADir.Trim) then
    Exit(MsgText(SR_CREATE_SUELTO_DIR));
  ARuta := TPath.Combine(TPath.GetFullPath(ADir.Trim), ANombre + AExt);
  Result := WriteTargetDenied(ARuta);
  if Result <> '' then
    Exit;
  if TFile.Exists(ARuta) then
    Exit(MsgFmt(SR_CREATE_YA_EXISTE_SOBREESCRIBE_FMT, [ARuta]));
  WriteNewFile(ARuta, ABody);
end;

function CreateDelphiUnit(const ADprPath, AUnitName, AContent: string;
  const ASubDir: string): string;
var
  Dir, PasPath, Body: string;
begin
  // kind=unit takes "project"; "dir" is the SUBFOLDER of that project (see
  // CarpetaEnElProyecto). Passing dir= without project answered "RECHAZADO:
  // ruta invalida: " with an empty path and cost four calls to decode
  // (measured 2026-08-25). Sin proyecto y con una carpeta ABSOLUTA, la unit
  // se crea SUELTA: nadie la lista todavia (el muro del 26-sep-2026).
  if ADprPath.Trim = '' then
  begin
    if (ASubDir.Trim = '') or not EsRutaAbsoluta(ASubDir.Trim) then
      Exit(MsgText(SR_CREATE_UNIT_NEED_PROJECT));
    Result := CuerpoDeUnit(AUnitName, AContent, Body);
    if Result <> '' then
      Exit;
    Result := CreaFuenteSuelto(ASubDir, AUnitName, '.pas', Body, PasPath);
    if Result <> '' then
      Exit;
    // el content es del agente: lo audita el mismo aviso que delphi_edit
    Exit(ConAvisosDeLlaves(MsgFmt(SN_CREATE_UNIT_SUELTA_FMT,
      [AUnitName, PasPath, Length(LineasDelTexto(Body))]), PasPath, Body));
  end;
  Result := WriteTargetDenied(ADprPath);
  if Result <> '' then
    Exit;
  if not MatchText(TPath.GetExtension(ADprPath), ['.dpr', '.dproj', '.dpk']) then
    Exit(MsgFmt(SR_UNIT_PROJECT_EXT_FMT, [ADprPath]));
  if not TFile.Exists(ADprPath) then
    Exit(NoEsFichero(ADprPath, MsgFmt(SR_CREATE_NO_EXISTE_PROYECTO_FMT, [ADprPath])));
  Result := BadUnitName(AUnitName);
  if Result <> '' then
    Exit;
  Result := CarpetaEnElProyecto(ADprPath, ASubDir, Dir);
  if Result <> '' then
    Exit;
  PasPath := TPath.Combine(Dir, AUnitName + '.pas');
  if TFile.Exists(PasPath) then
    Exit(MsgFmt(SR_CREATE_UNIT_YA_EXISTE_ADD_UNIT_FMT, [PasPath]));
  // With content: create AND fill in one call. Two calls (create the skeleton,
  // then rewrite it whole) was the commonest sequence of all and the one an
  // anchor-based editor serves worst - there is nothing to anchor to in an
  // empty unit (field round 8). The name still has to agree with the file:
  // registering UFoo.pas whose source says `unit UBar` is a lie the compiler
  // discovers much later.
  Result := CuerpoDeUnit(AUnitName, AContent, Body);
  if Result <> '' then
    Exit;
  // todo o nada, como el form: si no se registra, la unit creada se quita
  var FotoCrea: TFotoDeFicheros;
  FotoCrea.Toma([PasPath]);
  WriteNewFile(PasPath, Body);
  try
    Result := AddProjectUnit(ADprPath, PasPath);
  except
    on E: Exception do
      Result := MsgExcepcion(E.ClassName, E.Message);
  end;
  if EsFallo(Result) then
  begin
    var NoVolvio := FotoCrea.Restaura;
    if NoVolvio <> '' then
      Exit(MsgFmt(SR_FOTO_NO_VOLVIO_FMT, [NoVolvio, Result]));
    Result := MsgConCausa(SR_CREATE_CREADA_NO_REGISTRADA_FMT, Result, [AUnitName, Result]);
  end
  else
    Result := ConAvisosDeLlaves(MsgFmt(SK_CREATE_CREADA_UNIT_LINEAS_FMT,
      [AUnitName, PasPath, Length(LineasDelTexto(Body)), Result]), PasPath, Body);
end;

function CreateDelphiInclude(const ADprPath, AName, AContent, ADir: string): string;
var
  Dir, Nombre, Ruta, Body: string;
begin
  // un .inc no se registra en ningun sitio: se usa con {$I} desde una unit
  Nombre := AName.Trim;
  if SameText(TPath.GetExtension(Nombre), '.inc') then
    Nombre := TPath.ChangeExtension(Nombre, '').TrimRight(['.']);
  if AContent.Trim = '' then
    Exit(MsgText(SR_CREATE_INCLUDE_CONTENT));
  Body := ConSalto(AContent, CRLF);
  if not Body.EndsWith(CRLF) then
    Body := Body + CRLF;
  Dir := ADir;
  if ADprPath.Trim <> '' then
  begin
    // con proyecto, "dir" es su subcarpeta, como para una unit
    Result := WriteTargetDenied(ADprPath);
    if Result <> '' then
      Exit;
    if not TFile.Exists(ADprPath) then
      Exit(NoEsFichero(ADprPath, MsgFmt(SR_CREATE_NO_EXISTE_PROYECTO_FMT, [ADprPath])));
    Result := CarpetaEnElProyecto(ADprPath, ADir, Dir);
    if Result <> '' then
      Exit;
  end;
  Result := CreaFuenteSuelto(Dir, Nombre, '.inc', Body, Ruta);
  if Result <> '' then
    Exit;
  // las lineas como delphi_read: contaba la fantasma del salto final (septima revision)
  Result := ConAvisosDeLlaves(MsgFmt(SN_CREATE_INCLUDE_FMT,
    [Nombre, Ruta, Length(LineasDelTexto(Body)), Nombre]), Ruta, Body);
end;

end.
