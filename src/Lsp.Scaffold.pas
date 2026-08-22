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
{ AKind: vcl | fmx (forms) | frame-vcl | frame-fmx | datamodule. }
function CreateDelphiForm(const ADprPath, AUnitName, AFormName, AKind: string): string;
{ A plain unit (interface/implementation skeleton) registered in the project. }
function CreateDelphiUnit(const ADprPath, AUnitName: string): string;

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
  Lsp.Guard;

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
    raise Exception.CreateFmt('%s YA EXISTE - el scaffolder jamas sobreescribe.', [APath]);
  TDirectory.CreateDirectory(TPath.GetDirectoryName(TPath.GetFullPath(APath)));
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
  FormRef: string;
begin
  FormRef := '';
  if AFormUnit <> '' then
    FormRef :=
      '        <DCCReference Include="' + AFormUnit + '.pas">' + CRLF +
      '            <Form>' + AFormName + '</Form>' + CRLF +
      '            <FormType>' + AFormType + '</FormType>' + CRLF +
      '        </DCCReference>' + CRLF;
  Result :=
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + CRLF +
    '    <PropertyGroup>' + CRLF +
    '        <ProjectGuid>' + AGuid + '</ProjectGuid>' + CRLF +
    '        <MainSource>' + AName + '.dpr</MainSource>' + CRLF +
    '        <Base>True</Base>' + CRLF +
    '        <Config Condition="''$(Config)''==''''">Debug</Config>' + CRLF +
    '        <ProjectName Condition="''$(ProjectName)''==''''">' + AName + '</ProjectName>' + CRLF +
    '        <TargetedPlatforms>3</TargetedPlatforms>' + CRLF +
    '        <AppType>' + AAppType + '</AppType>' + CRLF +
    '        <FrameworkType>' + AFramework + '</FrameworkType>' + CRLF +
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
    '        <SanitizedProjectName>' + AName + '</SanitizedProjectName>' + CRLF +
    '        <DCC_ExeOutput>.\$(Platform)\$(Config)</DCC_ExeOutput>' + CRLF +
    '        <DCC_DcuOutput>.\$(Platform)\$(Config)\dcu</DCC_DcuOutput>' + CRLF +
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
    '        <Borland.ProjectType>Application</Borland.ProjectType>' + CRLF +
    '        <BorlandProject>' + CRLF +
    '            <Delphi.Personality>' + CRLF +
    '                <Source>' + CRLF +
    '                    <Source Name="MainSource">' + AName + '.dpr</Source>' + CRLF +
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
    'object ' + AFormName + ': T' + AFormName + CRLF +
    '  Left = 0' + CRLF +
    '  Top = 0' + CRLF +
    '  Caption = ''' + AFormName + '''' + CRLF +
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
    'object ' + AFormName + ': T' + AFormName + CRLF +
    '  Left = 0' + CRLF +
    '  Top = 0' + CRLF +
    '  Caption = ''' + AFormName + '''' + CRLF +
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
    'object ' + AFrameName + ': T' + AFrameName + CRLF +
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
    'object ' + AFrameName + ': T' + AFrameName + CRLF +
    '  Size.Width = 320.000000000000000000' + CRLF +
    '  Size.Height = 240.000000000000000000' + CRLF +
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
    'object ' + AModuleName + ': T' + AModuleName + CRLF +
    '  Height = 480' + CRLF +
    '  Width = 640' + CRLF +
    'end' + CRLF;
end;

function CreateDelphiProject(const ADir, AName, AKind: string): string;
var
  Kind, Dir, Dpr, MainUnit, MainForm: string;
  Files: TStringList;
begin
  Kind := AKind.Trim.ToLower;
  if (Kind <> 'console') and (Kind <> 'vcl') and (Kind <> 'fmx') then
    Exit('RECHAZADO: kind debe ser console | vcl | fmx.');
  if not TRegEx.IsMatch(AName, '^[A-Za-z_]\w*$') then
    Exit('RECHAZADO: ''' + AName + ''' no es un identificador Pascal valido para nombre de proyecto.');

  Dir := TPath.GetFullPath(ADir);
  Result := PathDenied(Dir);
  if Result <> '' then
    Exit;
  TDirectory.CreateDirectory(Dir);
  Dpr := TPath.Combine(Dir, AName + '.dpr');
  if TFile.Exists(Dpr) or TFile.Exists(TPath.Combine(Dir, AName + '.dproj')) then
    Exit('RECHAZADO: ya existe un proyecto ' + AName + ' en ' + Dir + '. El scaffolder jamas sobreescribe.');

  Files := TStringList.Create;
  try
    if Kind = 'console' then
    begin
      WriteNewFile(Dpr,
        'program ' + AName + ';' + CRLF + CRLF +
        '{$APPTYPE CONSOLE}' + CRLF + CRLF +
        'uses' + CRLF +
        '  System.SysUtils;' + CRLF + CRLF +
        'begin' + CRLF +
        '  try' + CRLF +
        '    Writeln(''' + AName + ' funcionando'');' + CRLF +
        '  except' + CRLF +
        '    on E: Exception do' + CRLF +
        '      Writeln(E.ClassName, '': '', E.Message);' + CRLF +
        '  end;' + CRLF +
        'end.' + CRLF);
      WriteNewFile(TPath.Combine(Dir, AName + '.dproj'),
        DprojTemplate(AName, NewGuidStr, 'Console', 'None', '', '', ''));
      Files.Add(AName + '.dpr');
      Files.Add(AName + '.dproj');
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
        WriteNewFile(TPath.Combine(Dir, AName + '.dproj'),
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
        WriteNewFile(TPath.Combine(Dir, AName + '.dproj'),
          DprojTemplate(AName, NewGuidStr, 'Application', 'FMX', MainUnit, MainForm, 'fmx'));
      end;
      Files.Add(AName + '.dpr');
      Files.Add(AName + '.dproj');
      Files.Add(MainUnit + '.pas');
      if Kind = 'vcl' then Files.Add(MainUnit + '.dfm') else Files.Add(MainUnit + '.fmx');
    end;

    // A basic .gitignore so the first commit stays clean of build artifacts
    // and tool backups; the agent may edit it later with delphi_textedit.
    if not TFile.Exists(TPath.Combine(Dir, '.gitignore')) then
    begin
      WriteNewFile(TPath.Combine(Dir, '.gitignore'),
        'Win32/' + CRLF + 'Win64/' + CRLF + '*.dcu' + CRLF +
        '*.local' + CRLF + '*.identcache' + CRLF + '*.stat' + CRLF +
        '__delphi-patch/' + CRLF + '__history/' + CRLF + '__recovery/' + CRLF +
        '*-deploy.zip' + CRLF + '*.delphilsp.json' + CRLF);
      Files.Add('.gitignore');
    end;

    Result := Format('CREADO proyecto %s (%s) en %s'#10'  ficheros: %s'#10 +
      'Fuentes en %s (el encoding configurado en el IDE) + CRLF. Compilable ' +
      'ya con delphi_build (el IDE enriquecera el .dproj al abrirlo).',
      [AName, Kind, Dir, string.Join(', ', Files.ToStringArray), NewFileEncName]);
  finally
    Files.Free;
  end;
end;

function CreateDelphiForm(const ADprPath, AUnitName, AFormName, AKind: string): string;
var
  Kind, Dir, FormName, PasPath, DesignerExt: string;
  Fmx: Boolean;
begin
  Kind := AKind.Trim.ToLower;
  if (Kind <> 'vcl') and (Kind <> 'fmx') and (Kind <> 'frame-vcl') and
     (Kind <> 'frame-fmx') and (Kind <> 'datamodule') then
    Exit('RECHAZADO: kind debe ser form-vcl | form-fmx | frame-vcl | frame-fmx | datamodule.');
  Result := PathDenied(ADprPath);
  if Result <> '' then
    Exit;
  if not TFile.Exists(ADprPath) then
    Exit('RECHAZADO: no existe el .dpr ' + ADprPath);
  // Dotted namespaces are legal Delphi (e.g. MyApp.Forms.Main): Ident(.Ident)*.
  if not TRegEx.IsMatch(AUnitName, '^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*$') then
    Exit('RECHAZADO: ''' + AUnitName + ''' no es un identificador valido de unit.');
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
  if FormName.StartsWith('T') and (Length(FormName) > 1) and CharInSet(FormName[2], ['A'..'Z']) then
    FormName := FormName.Substring(1); // the T prefix goes on the class only
  if not TRegEx.IsMatch(FormName, '^[A-Za-z_]\w*$') then
    Exit('RECHAZADO: ''' + FormName + ''' no es un identificador valido de form.');

  Dir := TPath.GetDirectoryName(TPath.GetFullPath(ADprPath));
  PasPath := TPath.Combine(Dir, AUnitName + '.pas');
  if TFile.Exists(PasPath) then
    Exit('RECHAZADO: ' + PasPath + ' ya existe. El scaffolder jamas sobreescribe.');

  // 1) the pair of files
  DesignerExt := '.dfm';
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
    Fmx := SameText(ReadDproj(ChangeFileExt(TPath.GetFullPath(ADprPath), '.dproj')).FrameworkType, 'FMX');
    WriteNewFile(PasPath, DataModulePas(AUnitName, FormName, Fmx));
    WriteNewFile(TPath.Combine(Dir, AUnitName + '.dfm'), DataModuleDfm(FormName));
  end;

  // 2) register in the .dpr (uses + CreateForm) and the .dproj (DCCReference)
  Result := AddProjectUnit(ADprPath, PasPath);
  if Result.StartsWith('RECHAZADO') then
    Result := 'CREADOS ' + AUnitName + '.pas/' + DesignerExt + ' pero NO se pudo registrar: ' + Result
  else
    Result := Format('CREADO %s %s (T%s, %s) con su %s.'#10'%s',
      [IfThen(Kind.StartsWith('frame'), 'frame', IfThen(Kind = 'datamodule', 'data module', 'form')),
       AUnitName, FormName, Kind, AUnitName + DesignerExt, Result]);
end;

function CreateDelphiUnit(const ADprPath, AUnitName: string): string;
var
  Dir, PasPath: string;
begin
  Result := PathDenied(ADprPath);
  if Result <> '' then
    Exit;
  if not TFile.Exists(ADprPath) then
    Exit('RECHAZADO: no existe el proyecto ' + ADprPath);
  if not TRegEx.IsMatch(AUnitName, '^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*$') then
    Exit('RECHAZADO: ''' + AUnitName + ''' no es un identificador valido de unit.');
  Dir := TPath.GetDirectoryName(TPath.GetFullPath(ADprPath));
  PasPath := TPath.Combine(Dir, AUnitName + '.pas');
  if TFile.Exists(PasPath) then
    Exit('RECHAZADO: ' + PasPath + ' ya existe. El scaffolder jamas sobreescribe. ' +
      'Para registrarla en el proyecto usa delphi_config command=add-unit.');
  WriteNewFile(PasPath,
    'unit ' + AUnitName + ';' + CRLF + CRLF +
    'interface' + CRLF + CRLF +
    'implementation' + CRLF + CRLF +
    'end.' + CRLF);
  Result := AddProjectUnit(ADprPath, PasPath);
  if Result.StartsWith('RECHAZADO') then
    Result := 'CREADA ' + AUnitName + '.pas pero NO se pudo registrar: ' + Result
  else
    Result := Format('CREADA la unit %s (%s).'#10'%s', [AUnitName, PasPath, Result]);
end;

end.
