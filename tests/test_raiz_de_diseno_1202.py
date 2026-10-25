# -*- coding: utf-8 -*-
"""Lo que es la raiz de un designer para el IDE, por sus JUECES (1.20.2).

Lsp.ProjectUnits la decidia con una lista de nombres (TFrame, TCustomFrame,
TDataModule, TForm, TCustomForm, TForm3D) por las clases de la propia unidad
y, si la cadena salia de ella, por el SUFIJO de la ultima clase vista (TBaseFrame
= frame); el ayudante, sin --root, por el nombre ('frame' dentro); check-binding
por otra lista (RAICES_DE_FORM). Medido el 18-oct-2026 contra las 654 unidades
con designer de los .dproj de los Samples: la lista fallaba en las 39 cuya
cadena sale de la unidad (una base del usuario en otra unidad, TAndroidService,
TDSServerModule, TWebModule). Ahora, por orden: lo que dice quien la crea
(delphi_create), el registro del IDE (<DesignClass> del .dproj que la lista) y,
sin el, la cadena por el motor hasta la primera clase que la tabla conoce, con
su categoria por la jerarquia de la tabla. Lo que no se sabe, se dice (CFG-122).

  P1 un data module sobre una base del usuario en OTRA unidad (TBaseDM):
     {Datos: TDataModule}, <DesignClass>TDataModule, CreateForm (ROJO: sin
     DesignClass, era una form)
  P2 un frame sobre una base del usuario en otra unidad (TBaseMarco): TFrame y
     SIN CreateForm (ROJO: el sufijo no decia frame, y le ponia CreateForm)
  P3 un TWebModule: {WM: TWebModule} y su DesignClass (ROJO: una form)
  P4 una form sobre TPanelFrame (otra unidad, = class(TForm)): form con
     CreateForm (ROJO: el sufijo Frame la hacia frame, sin CreateForm)
  P5 una base que nadie declara: la nota CFG-122 con su porque, registrada como
     form (ROJO: sin nota)
  P6 el registro del IDE: la base que el IDE nombra en un .dproj (TBaseDM) pasa
     al otro proyecto que la registra (ROJO: TDataModule o nada)
  P7 ...y un rename de la unidad no la pierde: desde V19 (1.23) un move es el
     del operador y no toca el .dproj (antes se re-apuntaba, y en la 1.20.2 la
     perdia); la nota nombra el proyecto y el .dfm que se quedo atras
  P8 preview de P2: el ayudante lo lee en un FRAME (root.kind) (ROJO: form)
  P9 check-binding del TWebModule con un componente sin campo: completo, lo
     nombra (ROJO: TWebModule no estaba en la lista; a medias y callado)
  C1 control: un frame sobre TFrame directo sigue sin CreateForm

Uso:  python tests/test_raiz_de_diseno_1202.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('raiz-de-diseno-1202')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='raiz-diseno', t=300)


def escribe(ruta, texto):
    with open(ruta, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write(texto)


def unidad(dir_, nombre, uses, tipos, var=''):
    escribe(os.path.join(dir_, nombre + '.pas'),
            'unit %s;\n\ninterface\n\nuses\n  %s;\n\ntype\n%s\n%simplementation\n\n{$R *.dfm}\n\nend.\n'
            % (nombre, uses, tipos, ('var\n  %s\n\n' % var) if var else ''))


def add_unit(proyecto, pas):
    return S.call('delphi_config', {'project': proyecto, 'command': 'add-unit', 'path': pas}, t=300)


def entrada_dproj(dproj, include):
    m = re.search(r'<DCCReference Include="%s">(.*?)</DCCReference>' % re.escape(include), mc.lee(dproj), re.S)
    return m.group(1) if m else ''


try:
    check('preparacion: las tablas del disenador estan',
          all(mc.tabla_lista(r) for _, r in mc.espera_tablas(S.call)))
    PV = os.path.join(JAIL, 'vcl')
    r = S.call('delphi_create', {'kind': 'project-vcl', 'name': 'PRaiz', 'dir': PV})
    check('preparacion: proyecto VCL', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    DPR = os.path.join(PV, 'PRaiz.dpr')
    DPROJ = os.path.join(PV, 'PRaiz.dproj')

    # P1: la base del usuario en otra unidad (la sigue el motor)
    unidad(PV, 'UBaseDM', 'System.Classes', '  TBaseDM = class(TDataModule)\n  end;\n')
    escribe(os.path.join(PV, 'UBaseDM.dfm'), 'object BaseDM: TBaseDM\n  Height = 150\n  Width = 215\nend\n')
    unidad(PV, 'UDatos', 'System.Classes, UBaseDM', '  TDatos = class(TBaseDM)\n  end;\n', 'Datos: TDatos;')
    escribe(os.path.join(PV, 'UDatos.dfm'), 'inherited Datos: TDatos\nend\n')
    r = add_unit(DPROJ, os.path.join(PV, 'UDatos.pas'))
    dpr = mc.lee(DPR)
    check('P1 data module sobre una base de otra unidad: {Datos: TDataModule} y CreateForm',
          "UDatos in 'UDatos.pas' {Datos: TDataModule}" in dpr and 'CreateForm(TDatos, Datos)' in dpr, r[:300] + dpr)
    check('P1 ...y <DesignClass>TDataModule en el .dproj',
          '<DesignClass>TDataModule</DesignClass>' in entrada_dproj(DPROJ, 'UDatos.pas'), entrada_dproj(DPROJ, 'UDatos.pas'))

    # P2: un frame sobre una base de otra unidad cuyo nombre no dice frame
    unidad(PV, 'UBaseMarco', 'Vcl.Forms', '  TBaseMarco = class(TFrame)\n  end;\n')
    escribe(os.path.join(PV, 'UBaseMarco.dfm'),
            'object BaseMarco: TBaseMarco\n  Left = 0\n  Top = 0\n  Width = 320\n  Height = 240\n  TabOrder = 0\nend\n')
    unidad(PV, 'UMarcoHijo', 'Vcl.Forms, UBaseMarco', '  TMarcoHijo = class(TBaseMarco)\n  end;\n')
    escribe(os.path.join(PV, 'UMarcoHijo.dfm'), 'inherited MarcoHijo: TMarcoHijo\nend\n')
    r = add_unit(DPROJ, os.path.join(PV, 'UMarcoHijo.pas'))
    dpr = mc.lee(DPR)
    check('P2 frame sobre una base de otra unidad: {MarcoHijo: TFrame} y SIN CreateForm',
          "{MarcoHijo: TFrame}" in dpr and 'CreateForm(TMarcoHijo' not in dpr, r[:300] + dpr)

    # P3: un TWebModule
    unidad(PV, 'UWeb', 'System.Classes, Web.HTTPApp', '  TWM = class(TWebModule)\n  end;\n', 'WM: TWM;')
    escribe(os.path.join(PV, 'UWeb.dfm'),
            'object WM: TWM\n  Actions = <>\n  Height = 230\n  Width = 415\n'
            '  object Timer1: TTimer\n    Left = 24\n    Top = 16\n  end\nend\n')
    r = add_unit(DPROJ, os.path.join(PV, 'UWeb.pas'))
    dpr = mc.lee(DPR)
    check('P3 un TWebModule: {WM: TWebModule} y su DesignClass',
          '{WM: TWebModule}' in dpr and '<DesignClass>TWebModule</DesignClass>' in entrada_dproj(DPROJ, 'UWeb.pas'),
          r[:300] + dpr)

    # P4: el sufijo no es un hecho
    unidad(PV, 'UPanelFrame', 'Vcl.Forms', '  TPanelFrame = class(TForm)\n  end;\n')
    escribe(os.path.join(PV, 'UPanelFrame.dfm'),
            'object PanelFrame: TPanelFrame\n  Left = 0\n  Top = 0\n  ClientHeight = 100\n  ClientWidth = 100\nend\n')
    unidad(PV, 'UHostF', 'Vcl.Forms, UPanelFrame', '  TFormHostF = class(TPanelFrame)\n  end;\n',
           'FormHostF: TFormHostF;')
    escribe(os.path.join(PV, 'UHostF.dfm'), 'inherited FormHostF: TFormHostF\nend\n')
    r = add_unit(DPROJ, os.path.join(PV, 'UHostF.pas'))
    dpr = mc.lee(DPR)
    check('P4 una form sobre TPanelFrame (= class(TForm)): {FormHostF} y CreateForm',
          "{FormHostF}" in dpr and 'CreateForm(TFormHostF, FormHostF)' in dpr, r[:300] + dpr)

    # P5: sin juez, se dice
    unidad(PV, 'UFantasma', 'Vcl.Forms', '  TFantasmaHija = class(TNoLaDeclaraNadie)\n  end;\n',
           'FantasmaHija: TFantasmaHija;')
    escribe(os.path.join(PV, 'UFantasma.dfm'), 'object FantasmaHija: TFantasmaHija\nend\n')
    r = add_unit(DPROJ, os.path.join(PV, 'UFantasma.pas'))
    dpr = mc.lee(DPR)
    check('P5 una base que nadie declara: la nota con la clase en que se acaba, y registrada como form',
          mc.es(r, 'SN_UNIT_RAIZ_SIN_JUEZ_FMT') and 'TNoLaDeclaraNadie' in r and '{FantasmaHija}' in dpr, r[:500])

    # P6: el registro del IDE manda; aqui, la base del usuario que a veces
    # nombra (TdmlMainComp en los Samples), escrita en el .dproj de PRaiz
    xml = mc.lee(DPROJ)
    viejo = entrada_dproj(DPROJ, 'UDatos.pas')
    with open(DPROJ, 'w', encoding='utf-8', newline='') as f:
        f.write(xml.replace(viejo, viejo.replace('<DesignClass>TDataModule</DesignClass>',
                                                 '<DesignClass>TBaseDM</DesignClass>')))
    # (en una carpeta hermana: el registro lo encuentra subiendo desde la unidad)
    PD = os.path.join(JAIL, 'dos')
    r = S.call('delphi_create', {'kind': 'project-vcl', 'name': 'PDos', 'dir': PD})
    check('preparacion: un segundo proyecto al lado', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    DPROJ2 = os.path.join(PD, 'PDos.dproj')
    r = add_unit(DPROJ2, os.path.join(PV, 'UDatos.pas'))
    check('P6 el registro del IDE de OTRO proyecto: {Datos: TBaseDM} y su DesignClass',
          '{Datos: TBaseDM}' in mc.lee(os.path.join(PD, 'PDos.dpr')) and
          '<DesignClass>TBaseDM</DesignClass>' in entrada_dproj(DPROJ2, '..\\vcl\\UDatos.pas'),
          r[:300] + entrada_dproj(DPROJ2, '..\\vcl\\UDatos.pas'))

    # P7: un rename de la unidad, como un operador: el .dproj no se toca (lo que registro el
    # IDE se queda donde estaba) y la nota lo dice, con el .dfm que se quedo atras
    antes7 = open(DPROJ, 'rb').read()
    r = S.call('delphi_move', {'path': os.path.join(PV, 'UDatos.pas'), 'dest': os.path.join(PV, 'UDatosB.pas')})
    check('P7 rename: el .dproj byte a byte (con su <DesignClass>TBaseDM), la nota nombra el proyecto y el .dfm',
          open(DPROJ, 'rb').read() == antes7 and
          '<DesignClass>TBaseDM</DesignClass>' in entrada_dproj(DPROJ, 'UDatos.pas') and
          (mc.virtual(mc.larga(DPR)) + ' (1 ').lower() in r.lower() and
          mc.es(r, 'SN_FILE_PAR_PARTIDO_FMT') and 'UDatos.dfm' in r, r[-800:])

    # P8: el --root del preview, por el mismo juez
    r = S.call('delphi_designer', {'command': 'preview', 'path': os.path.join(PV, 'UMarcoHijo.dfm')}, t=300)
    d = mc.como_json(r) or {}
    check('P8 preview del frame de P2: el ayudante lo lee en un frame',
          (d.get('root') or {}).get('kind') == 'frame', r[:400])

    # P9: check-binding del TWebModule: completo
    r = S.call('delphi_designer', {'command': 'check-binding', 'path': os.path.join(PV, 'UWeb.dfm')})
    d = mc.como_json(r) or {}
    check('P9 check-binding de un TWebModule: completo, nombra el Timer1 sin campo',
          not d.get('partialNote') and any('Timer1' in x for x in d.get('componentsWithoutField') or []), r[:500])

    # C1: control
    r = S.call('delphi_create', {'kind': 'frame-vcl', 'name': 'UMarcoDirecto', 'project': DPROJ})
    dpr = mc.lee(DPR)
    check('C1 control: un frame de delphi_create sigue con TFrame y sin CreateForm',
          '{FrameUMarcoDirecto: TFrame}' in dpr and 'CreateForm(TFrameUMarcoDirecto' not in dpr, r[:300])
finally:
    S.cierra()
    mc.borra(BASE)
mc.fin('raiz de diseno por sus jueces 1202')
