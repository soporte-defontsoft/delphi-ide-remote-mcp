# -*- coding: utf-8 -*-
"""El lint y el preview de una VISTA FMX, y el componente sin campo (1.20.2).

Medido el 18-oct-2026, con la corpus por fin con sus renderizadores: 31 de las
78 vistas FMX de los Samples (<unidad>.<Vista>.fmx) "no cargaban" - DSGN-038
"Ancestor for 'X' not found" - y delphi_edit tras un cambio en una vista
gritaba EDIT-127 "the app dies creating the form - on Android". El IDE carga la
vista ENCIMA de su maestro (<unidad>.fmx), y lo declara en el .pas del maestro
con la directiva R '*.<Vista>.fmx'; el renderizador la leia sola. Y el lint de
un Sample de Embarcadero que compila y corre daba "has no published field"
como si no cargara: TReader no necesita el campo, solo encontrar la CLASE
(System.Classes: GetFieldClass, por los campos publicados, o GetClass, por las
registradas).

  V1 una vista que el .pas del maestro declara: LINT CLEAN (leida sobre el
     maestro; el FontColor obliga a preguntar al lector del IDE)
  V2 su preview la dibuja (Edit1 sale) sin nada ignorado
  V3 control: un 'inherited Fantasma' que el maestro NO tiene sigue siendo un
     aviso (DSGN-038, "Ancestor for 'Fantasma' not found")
  V4 la misma vista con la directiva COMENTADA: leida sin ancestro, DSGN-154
     "no confirmado" con su motivo - nunca "no carga"
  V5 su preview: la nota DSGN-156, no DSGN-114 ("no abrira")
  V6 un {$R} sin argumento delante de la directiva de la vista: CLEAN (el
     primer trozo, por EL troceador de Lsp.Pascal; un Split()[0] leia fuera
     del array y el renderizador caia con un EAccessViolation)
  B1 VCL: Label2 sin campo, con Label1 (un TLabel) con el: ningun aviso
  B2 ...y Memo1 sin campo y sin ningun campo TMemo: el aviso, condicional
     (EClassNotFound si la clase no esta registrada)
  B3 FMX: un TMainMenu y un TComboEdit sin campo ni otro campo de su clase:
     ningun aviso, que sus unidades los registran al ejecutar (hecho R de la
     tabla, RegisterFmxClasses; cuatro Samples salian como que no cargaban)
  G1 un TCalendar de la VCL (Vcl.Samples.Calendar, no estandar: se cargan los
     paquetes del IDE) con su Color: LINT CLEAN. Un paquete FMX activaba el grupo
     de clases de FMX (RegisterFmxClasses) y GetClass daba el TCalendar de FMX:
     "Color does not exist" (100 avisos falsos de la corpus eran esto)
  G2 su preview lo dibuja como control (no sale en nonVisual)
  R1 un modulo de datos .dfm de un proyecto FMX (su .pas lo dice con el grupo
     de clases que escribe el IDE, CLASSGROUP 'FMX.Controls.TControl') con el
     Source y el Destination de un TImageList de FMX: no "no carga" (se
     juzgaba con la VCL: "Property Source does not exist")
  R1b control: el mismo con el grupo de la VCL: el aviso de Source
  R2 una raiz TForm3D (UsingDesignCamera, que su form no tiene): no "no carga"
     (el lector la lee en una form; lo de su clase lo juzga la tabla)
  R2b control: una propiedad que TForm3D no tiene: el aviso
  S1 (si hay Samples) la vista Delphi de ListCollections CLEAN (leida sin su
     ancestro la miden V4/V5; C++ no: este MCP es solo de Delphi)
  S2 el TitlebarPanel de la VCL: el lector se salta "No ActionBand style unit"
     y un AV de vclactnband, excepciones que NO son suyas (el ayudante lo dice
     por la clase, IGNORED=<de quien>|...: el codigo de un componente en este
     entorno): DSGN-154 con el motivo, no un aviso. V3 es su control: un
     "Ancestor for X not found" SI es del lector y sigue siendo aviso
  S3 el IBX2FDMigration: "InterBase library gds32.dll not found", igual
  S4 el ListViewMultiDetailAppearance: su ItemAppearanceClassName es una clase
     del PROYECTO (la registra MultiDetailAppearanceU) que el lector no carga:
     lo saltado bajo ItemAppearanceObjects no se confirma (DSGN-154), no es
     un aviso; y su preview lo dice (DSGN-163) en vez de "no abrira"
  (S2-S4, ROJAS contra h1c: salian como avisos del form en el corpus)

V1, V2 y V4 son ROJAS contra bb246ed (la vista se leia sola); B1 tambien.
V6, contra el renderizador con el Split()[0]: el AV medido en vivo contra
produccion el 18-oct-2026, antes y despues de desplegar el troceador.

Uso:  python tests/test_lint_vistas_1202.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('lint-vistas-1202')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='lint-vistas', t=300)
PARCIAL = mc.catalogo()['SF_DSGN_LECTOR_SIN_ANCESTRO_FMT'].split('(')[0].strip()


def dsg(args, t=200):
    return S.call('delphi_designer', args, t=t)


def escribe(ruta, texto):
    with open(ruta, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write(texto)


try:
    check('preparacion: las tablas del disenador estan',
          all(mc.tabla_lista(r) for _, r in mc.espera_tablas(S.call)))
    # ---------------------------------------------------------------- vistas
    PF = os.path.join(JAIL, 'fmx')
    r = S.call('delphi_create', {'kind': 'project-fmx', 'name': 'PVista', 'dir': PF})
    check('preparacion: proyecto FMX', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    MAESTRO = os.path.join(PF, 'UMain.fmx')
    PAS = os.path.join(PF, 'UMain.pas')
    r = dsg({'command': 'insert', 'path': MAESTRO, 'classname': 'TEdit', 'component': 'Edit1'})
    check('preparacion: Edit1 en el maestro, con su campo', mc.como_json(r).get('inserted') == 'Edit1', r[:200])
    pas = open(PAS, encoding='utf-8-sig').read()
    check('preparacion: el .pas del maestro lleva su R *.fmx', '{$R *.fmx}' in pas, pas[:300])
    # la vista como la escribe el IDE: la directiva en el .pas y el fichero
    escribe(PAS, pas.replace('{$R *.fmx}', '{$R *.fmx}\n{$R *.SmXhdpiPh.fmx ANDROID}'))
    VISTA = os.path.join(PF, 'UMain.SmXhdpiPh.fmx')
    CUERPO = ('inherited FormMain_SmXhdpiPh: TFormMain_SmXhdpiPh\n'
              '  ClientHeight = 480\n  ClientWidth = 320\n  DesignerMasterStyle = 0\n'
              '  inherited Edit1: TEdit\n    FontColor = claRed\n  end\n%send\n')
    escribe(VISTA, CUERPO % '')
    r = dsg({'command': 'lint', 'path': VISTA})
    check('V1 una vista que el .pas del maestro declara: LINT CLEAN (leida sobre su maestro)',
          mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT') and 'Ancestor for' not in r, r[:400])
    j = mc.como_json(dsg({'command': 'preview', 'path': VISTA, 'inline': False, 'out': os.path.join(JAIL, 'v.png')}))
    check('V2 su preview la dibuja (Edit1) sin nada ignorado',
          (j.get('components') or 0) >= 1 and not j.get('ignored'), str(j)[:400])
    escribe(VISTA, CUERPO % '  inherited Fantasma: TButton\n  end\n')
    r = dsg({'command': 'lint', 'path': VISTA})
    check('V3 control: un inherited que el maestro NO tiene sigue siendo un aviso (DSGN-038)',
          mc.abre(r, 'SN_DESIGNER_LINT_BAD_FMT') and 'Fantasma' in r, r[:400])
    escribe(VISTA, CUERPO % '')
    escribe(PAS, pas.replace('{$R *.fmx}', '{$R *.fmx}\n// {$R *.SmXhdpiPh.fmx ANDROID}'))
    r = dsg({'command': 'lint', 'path': VISTA})
    check('V4 con la directiva COMENTADA: leida sin ancestro, DSGN-154 "no confirmado" (nunca "no carga")',
          mc.abre(r, 'SN_DESIGNER_LINT_SIN_LECTOR_FMT') and PARCIAL in r and not mc.es(r, 'SN_DESIGNER_LINT_BAD_FMT'),
          r[:400])
    j = mc.como_json(dsg({'command': 'preview', 'path': VISTA, 'inline': False, 'out': os.path.join(JAIL, 'v4.png')}))
    check('V5 su preview: la nota DSGN-156 (leida sin un ancestro), no DSGN-114 ("no abrira")',
          mc.es(j.get('ignoredNote') or '', 'SN_DESIGNER_PREVIEW_IGNORADAS_PARCIAL_FMT')
          and not mc.es(j.get('ignoredNote') or '', 'SN_DESIGNER_PREVIEW_IGNORADAS'), str(j)[:400])
    escribe(PAS, pas.replace('{$R *.fmx}', '{$R *.fmx}\n{$R}\n{$R *.SmXhdpiPh.fmx ANDROID}'))
    r = dsg({'command': 'lint', 'path': VISTA})
    check('V6 un {$R} vacio delante de la directiva de la vista: LINT CLEAN, sin AV del renderizador',
          mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT') and 'Access violation' not in r, r[:400])

    # ------------------------------------------------- componente sin campo
    PV = os.path.join(JAIL, 'vcl')
    r = S.call('delphi_create', {'kind': 'project-vcl', 'name': 'PCampos', 'dir': PV})
    check('preparacion: proyecto VCL', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    DFM = os.path.join(PV, 'UMain.dfm')
    PASV = os.path.join(PV, 'UMain.pas')
    for clase, nombre in (('TLabel', 'Label1'), ('TLabel', 'Label2'), ('TMemo', 'Memo1')):
        r = dsg({'command': 'insert', 'path': DFM, 'classname': clase, 'component': nombre})
        check('preparacion: %s con su campo' % nombre, mc.como_json(r).get('inserted') == nombre, r[:200])
    pasv = open(PASV, encoding='utf-8-sig').read()
    sin = re.sub(r'(?m)^\s*(Label2: TLabel|Memo1: TMemo);\r?\n', '', pasv)
    check('preparacion: Label2 y Memo1 sin campo (Label1 lo conserva)',
          'Label2: TLabel' not in sin and 'Memo1: TMemo' not in sin and 'Label1: TLabel' in sin, sin[:500])
    escribe(PASV, sin)
    r = dsg({'command': 'lint', 'path': DFM})
    check('B1 Label2 sin campo, con otro campo TLabel en la clase: ningun aviso suyo (el lint contesto, con el de Memo1)',
          'Label2' not in r and mc.es(r, 'SN_DESIGNER_LINT_BAD_FMT'), r[:500])
    check('B2 Memo1 sin campo y sin ningun campo TMemo: el aviso, que dice cuando carga (EClassNotFound)',
          mc.abre(r, 'SN_DESIGNER_LINT_BAD_FMT') and 'Memo1' in r and 'EClassNotFound' in r, r[:500])
    # B3: lo mismo en FMX con clases que su unidad registra al ejecutar
    # (FMX.Menus, FMX.ComboEdit: RegisterFmxClasses): TReader las crea sin campo
    PRG = os.path.join(JAIL, 'registradas')
    os.makedirs(PRG)
    escribe(os.path.join(PRG, 'UReg.pas'),
            'unit UReg;\n\ninterface\n\nuses\n  System.SysUtils, System.Classes, FMX.Types, FMX.Controls, FMX.Forms,\n'
            '  FMX.Menus, FMX.Edit, FMX.ComboEdit;\n\ntype\n  TFormReg = class(TForm)\n  private\n  public\n  end;\n\n'
            'var\n  FormReg: TFormReg;\n\nimplementation\n\n{$R *.fmx}\n\nend.\n')
    escribe(os.path.join(PRG, 'UReg.fmx'),
            'object FormReg: TFormReg\n  Left = 0\n  Top = 0\n  Caption = \'Reg\'\n  ClientHeight = 300\n'
            '  ClientWidth = 400\n  FormFactor.Width = 320\n  FormFactor.Height = 480\n'
            '  FormFactor.Devices = [Desktop]\n  DesignerMasterStyle = 0\n  object MainMenu1: TMainMenu\n  end\n'
            '  object ComboEdit1: TComboEdit\n    Position.X = 40.000000000000000000\n'
            '    Position.Y = 40.000000000000000000\n  end\nend\n')
    r = dsg({'command': 'lint', 'path': os.path.join(PRG, 'UReg.fmx')})
    check('B3 FMX: MainMenu1 y ComboEdit1 sin campo, con sus clases registradas al ejecutar: LINT CLEAN',
          'MainMenu1' not in r and 'ComboEdit1' not in r and mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:500])

    # ------------------------------------ grupos de clases de la RTL (VCL/FMX)
    PGR = os.path.join(JAIL, 'grupos')
    r = S.call('delphi_create', {'kind': 'project-vcl', 'name': 'PGrupos', 'dir': PGR})
    check('preparacion: proyecto VCL de grupos', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    DFMG = os.path.join(PGR, 'UMain.dfm')
    r = dsg({'command': 'insert', 'path': DFMG, 'classname': 'TCalendar', 'component': 'Calendar1'})
    check('preparacion: Calendar1, un TCalendar de la VCL, con su campo', mc.como_json(r).get('inserted') == 'Calendar1',
          r[:200])
    r = dsg({'command': 'set', 'path': DFMG, 'component': 'Calendar1', 'prop': 'Color', 'value': 'clInfoBk'})
    check('preparacion: su Color (la tabla VCL lo publica)', not mc.fallo(r) and 'clInfoBk' in open(DFMG).read(), r[:200])
    r = dsg({'command': 'lint', 'path': DFMG})
    check('G1 un TCalendar de la VCL con su Color: LINT CLEAN (no el TCalendar de FMX)',
          mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT') and 'does not exist' not in r, r[:400])
    j = mc.como_json(dsg({'command': 'preview', 'path': DFMG, 'inline': False, 'out': os.path.join(JAIL, 'g.png')}))
    check('G2 su preview lo dibuja como control (no sale en nonVisual) sin nada ignorado',
          j.get('components') and not j.get('ignored') and
          not any(n.get('name') == 'Calendar1' for n in (j.get('nonVisual') or [])), str(j)[:400])

    # ------------------------------------- raices que no son una form (1.20.2)
    PR = os.path.join(JAIL, 'raices')
    os.makedirs(PR)
    PAS_DM = ('unit UDm;\n\ninterface\n\nuses\n  System.SysUtils, System.Classes, System.ImageList, FMX.ImgList;\n\n'
              'type\n  TDm = class(TDataModule)\n    ImageList1: TImageList;\n  end;\n\nvar\n  Dm: TDm;\n\n'
              'implementation\n\n{%%CLASSGROUP \'%s\'}\n\n{$R *.dfm}\n\nend.\n')
    DFM_DM = ('object Dm: TDm\n  Height = 150\n  Width = 215\n  object ImageList1: TImageList\n'
              '    Source = <>\n    Destination = <>\n    Left = 40\n    Top = 24\n  end\nend\n')
    escribe(os.path.join(PR, 'UDm.pas'), PAS_DM % 'FMX.Controls.TControl')
    escribe(os.path.join(PR, 'UDm.dfm'), DFM_DM)
    r = dsg({'command': 'lint', 'path': os.path.join(PR, 'UDm.dfm')})
    check('R1 un modulo de datos .dfm de un proyecto FMX (su CLASSGROUP): Source/Destination de FMX, no "no carga"',
          not mc.es(r, 'SN_DESIGNER_LINT_BAD_FMT') and 'Source' not in r, r[:400])
    escribe(os.path.join(PR, 'UDm.pas'), PAS_DM % 'Vcl.Controls.TControl')
    r = dsg({'command': 'lint', 'path': os.path.join(PR, 'UDm.dfm')})
    check('R1b control: el mismo con el grupo de la VCL: el aviso de Source (el marco lo dice la marca)',
          mc.es(r, 'SN_DESIGNER_LINT_BAD_FMT') and 'Source' in r, r[:400])
    PAS_3D = ('unit UTresD;\n\ninterface\n\nuses\n  System.SysUtils, System.Classes, FMX.Types, FMX.Controls, FMX.Forms3D, '
              'FMX.Types3D;\n\ntype\n  TFormTresD = class(TForm3D)\n    Timer1: TTimer;\n  end;\n\nvar\n  FormTresD: TFormTresD;\n\n'
              'implementation\n\n{$R *.fmx}\n\nend.\n')
    FMX_3D = ('object FormTresD: TFormTresD\n  Left = 0\n  Top = 0\n  Caption = \'Tres D\'\n  ClientHeight = 200\n'
              '  ClientWidth = 300\n  UsingDesignCamera = False\n%s  FormFactor.Width = 320\n  FormFactor.Height = 480\n'
              '  FormFactor.Devices = [Desktop]\n'
              # Left/Top de un no visual: guardados por codigo, la tabla no los
              # juzga y se pregunta al lector (sin el, R2 pasaba tambien contra
              # el servidor de antes: no media nada)
              '  object Timer1: TTimer\n    Left = 24\n    Top = 16\n  end\nend\n')
    escribe(os.path.join(PR, 'UTresD.pas'), PAS_3D)
    escribe(os.path.join(PR, 'UTresD.fmx'), FMX_3D % '')
    r = dsg({'command': 'lint', 'path': os.path.join(PR, 'UTresD.fmx')})
    check('R2 una raiz TForm3D (UsingDesignCamera, que su form no tiene): no "no carga"',
          not mc.es(r, 'SN_DESIGNER_LINT_BAD_FMT'), r[:400])
    escribe(os.path.join(PR, 'UTresD.fmx'), FMX_3D % '  Colorr = claBlack\n')
    r = dsg({'command': 'lint', 'path': os.path.join(PR, 'UTresD.fmx')})
    check('R2b control: una propiedad que TForm3D no tiene sigue siendo un aviso',
          mc.es(r, 'SN_DESIGNER_LINT_BAD_FMT') and 'Colorr' in r, r[:400])

    # -------------------------------------------------- Samples, si los hay
    SAM = os.path.join(mc.variable_de_rsvars(S.call, 'BDSCOMMONDIR'), 'Samples')
    DEL = os.path.join(SAM, 'Object Pascal', 'Multi-Device Samples', 'User Interface', 'ListCollections',
                       'ListExpressionsSampleFormUnit1.SmXhdpiPh.fmx')
    if os.path.isfile(DEL):
        r = dsg({'command': 'lint', 'path': DEL})
        check('S1 la vista Delphi de un Sample (ListCollections): LINT CLEAN', mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:300])
    else:
        print('NOTA: S1 no se mide: no estan los Samples de esta instalacion')
    # lo que el lector dice de un Sample y NO es del fichero: se copia el
    # proyecto entero a la jaula (el lint lee el .pas de al lado)
    import shutil
    for clave, carpeta, form, pista in (
            ('S2', os.path.join('Object Pascal', 'VCL', 'Titlebar', 'TitlebarPanel'), 'Main.dfm', 'ActionBand'),
            ('S3', os.path.join('Object Pascal', 'Database', 'FireDAC', 'Tool', 'reFind', 'IBX2FDMigration', 'Demo'),
             'DataMod.dfm', 'gds32'),
            ('S4', os.path.join('Object Pascal', 'Multi-Device Samples', 'User Interface', 'ListView',
                                'ListViewMultiDetailAppearance'), 'MultiDetailMainFormU.fmx', 'TMultiDetailItemAppearance')):
        origen = os.path.join(SAM, carpeta)
        if not os.path.isfile(os.path.join(origen, form)):
            print('NOTA: %s no se mide: no esta %s' % (clave, os.path.join(carpeta, form)))
            continue
        destino = os.path.join(JAIL, clave)
        shutil.copytree(origen, destino, ignore=shutil.ignore_patterns('__history', '__recovery', 'Win32', 'Win64'))
        r = dsg({'command': 'lint', 'path': os.path.join(destino, form)}, t=300)
        check('%s %s: lo que el lector dijo no es del fichero (%s): DSGN-154 con el motivo, no un aviso'
              % (clave, form, pista),
              mc.abre(r, 'SN_DESIGNER_LINT_SIN_LECTOR_FMT') and pista in r and not mc.es(r, 'SN_DESIGNER_LINT_BAD_FMT'),
              r[:500])
        if clave == 'S4':
            j = mc.como_json(dsg({'command': 'preview', 'path': os.path.join(destino, form), 'inline': False,
                                  'out': os.path.join(JAIL, 's4.png')}, t=300))
            check('S4 su preview: DSGN-163 (no confirmado), no DSGN-114 ("no abrira")',
                  mc.es(j.get('ignoredUnconfirmedNote') or '', 'SN_DESIGNER_PREVIEW_IGNORADAS_NO_CONFIRMADAS_FMT')
                  and not mc.es(j.get('ignoredNote') or '', 'SN_DESIGNER_PREVIEW_IGNORADAS'), str(j)[:500])
finally:
    S.cierra()
    mc.borra(BASE)
mc.fin('lint de vistas y campos 1202')
