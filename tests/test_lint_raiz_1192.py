# -*- coding: utf-8 -*-
"""H8 de la 1.19.2 (Hermes sobre la 1.19.1, informe 111720; medido el 15-oct en
hermes1191\\lintmodal): lint, y el aviso de delphi_edit (EDIT-076), no juzgaban la
RAIZ del form. `ModalResult = mrOK` (un TForm no lo publica) y `Color = clNoExiste`
en la raiz de un form VCL: lint DSGN-020 CLEAN y la edicion sin aviso, mientras el
cargador los ignora (preview DSGN-114: el form no abre). set SI juzga la raiz: por
la cadena de ancestros de su .pas, hasta la primera clase que la tabla conoce
(TForm), nunca por su nombre (un TForm1 de las demos se llama igual: la 1.12.0
dejo la raiz sin juzgar por eso). Ahora lint la juzga igual, con el mismo
recorredor; y calla lo que publican las clases del USUARIO de esa cadena (un
TBaseForm con su property Foo: la clase real la lee, la tabla no la conoce).

  L1 VCL, raiz con ModalResult = mrOK: la edicion avisa (EDIT-076) y lint lo
     nombra (ROJO en produccion)
  L2 VCL, raiz con Color = clNoExiste: lint lo nombra (ROJO)
  L3 FMX, raiz con una propiedad que no existe: lint la nombra (ROJO)
  L4 la base del usuario publica Foo: Foo = 1 en la raiz NO se nombra, y
     ModalResult = mrOK al lado si
  C1-C5 control: los esqueletos de delphi_create (form VCL, form FMX, frame VCL,
     frame FMX, data module) siguen CLEAN

Uso:  python tests/test_lint_raiz_1192.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('lint_raiz_1192')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
# con sus renderizadores, como en el zip: desde la 1.20 el lint dice CLEAN solo
# si el lector del IDE carga lo que la tabla no juzga (DSGN-061, DSGN-154)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)

s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='lint-raiz', t=300)


def lint(fichero):
    return s.call('delphi_designer', {'command': 'lint', 'path': fichero}, t=300)


def limpio(r):
    return mc.es(r, 'SN_DESIGNER_LINT_OK_FMT')


def mete(fichero, ancla, nueva):
    """Una linea debajo de ancla, con delphi_edit como un agente: su respuesta."""
    return s.call('delphi_edit', {'path': fichero, 'old': ancla, 'new': ancla + '\n' + nueva})


def primera_propiedad(fichero):
    return next(l for l in mc.lee(fichero).splitlines()[1:] if '=' in l)


try:
    listas = mc.espera_tablas(lambda tool, args, t=120: s.call(tool, args, t=t))
    check('fixture: las tablas del disenador estan listas',
          all(not mc.tiene(r, 'DSGN-051') and not mc.fallo(r) for _, r in listas), str(listas)[:300])

    vcl = os.path.join(JAIL, 'vcl')
    s.call('delphi_create', {'kind': 'project-vcl', 'name': 'RaizVcl', 'dir': vcl})
    DPROJ = os.path.join(vcl, 'RaizVcl.dproj')
    DFM = os.path.join(vcl, 'UMain.dfm')
    s.call('delphi_create', {'kind': 'frame-vcl', 'name': 'UMarco', 'project': DPROJ})
    s.call('delphi_create', {'kind': 'datamodule', 'name': 'UDatos', 'project': DPROJ})
    fmx = os.path.join(JAIL, 'fmx')
    s.call('delphi_create', {'kind': 'project-fmx', 'name': 'RaizFmx', 'dir': fmx})
    FMX = os.path.join(fmx, 'UMain.fmx')
    s.call('delphi_create', {'kind': 'frame-fmx', 'name': 'UMarcoF', 'project': os.path.join(fmx, 'RaizFmx.dproj')})

    # los controles primero, con los esqueletos sin tocar
    for n, f in (('C1 form VCL', DFM), ('C2 form FMX', FMX), ('C3 frame VCL', os.path.join(vcl, 'UMarco.dfm')),
                 ('C4 frame FMX', os.path.join(fmx, 'UMarcoF.fmx')), ('C5 data module', os.path.join(vcl, 'UDatos.dfm'))):
        r = lint(f)
        check('%s: el esqueleto de delphi_create sigue CLEAN' % n, limpio(r), r[:400])

    e = mete(DFM, '  TextHeight = 15', '  ModalResult = mrOK')
    r = lint(DFM)
    check('L1 VCL, raiz con ModalResult = mrOK: la edicion avisa (EDIT-076) y lint lo nombra',
          mc.tiene(e, 'EDIT-076') and 'ModalResult' in e and not limpio(r) and 'ModalResult' in r,
          (e[-300:], r[:300]))
    s.call('delphi_edit', {'path': DFM, 'old': '  Color = clBtnFace', 'new': '  Color = clNoExiste'})
    r = lint(DFM)
    check('L2 VCL, raiz con Color = clNoExiste: lint lo nombra', 'clNoExiste' in r and not limpio(r), r[:400])
    s.call('delphi_edit', {'path': DFM, 'old': '  Color = clNoExiste', 'new': '  Color = clBtnFace'})

    mete(FMX, primera_propiedad(FMX), '  Frobnica = 1')
    r = lint(FMX)
    check('L3 FMX, raiz con una propiedad que no existe: lint la nombra', 'Frobnica' in r and not limpio(r), r[:400])

    # L4: una base del usuario que publica su propiedad
    s.call('delphi_create', {'kind': 'unit', 'name': 'UBase', 'project': DPROJ, 'content':
        'unit UBase;\n\ninterface\n\nuses\n  Vcl.Forms;\n\ntype\n  TBaseForm = class(TForm)\n  private\n'
        '    FFoo: Integer;\n  published\n    property Foo: Integer read FFoo write FFoo;\n  end;\n\n'
        'implementation\n\nend.\n'})
    PAS = os.path.join(vcl, 'UMain.pas')
    s.call('delphi_edit', {'path': PAS, 'old': '  TFormMain = class(TForm)', 'new': '  TFormMain = class(TBaseForm)'})
    s.call('delphi_edit', {'path': PAS, 'adduses': 'UBase', 'section': 'interface'})
    mete(DFM, '  TextHeight = 15', '  Foo = 1')
    r = lint(DFM)
    check('L4 lo que publica la base del usuario (Foo) no se nombra; ModalResult a su lado si',
          'Foo = 1' not in r and 'ModalResult' in r, r[:500])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('lint de la raiz del form 1.19.2 (H8)')
