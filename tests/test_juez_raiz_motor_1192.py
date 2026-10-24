# -*- coding: utf-8 -*-
"""El juez de la raiz del form y los componentes heredados, por EL MOTOR
(1.19.2, medido el 15-oct en hermes1191\\watch tras el H8).

"Que clase es este ancestro" (el TBaseForm de 'TFormMain = class(TBaseForm)')
lo decide el compilador: la unidad del uses que lo declara, el ultimo gana, y
un nombre cualificado lo dice solo. El juez de la raiz (ClaseDeJuezDeRaiz) y
los componentes heredados (NombresHeredados) lo decidian por un barrido de la
CARPETA del form: la primera unidad en orden de ficheros que declaraba el
nombre. Con una homonima delante (UA_Base.pas sin la propiedad, UB_Base.pas
con ella), lint negaba 'Modo' con DSGN-038, set lo negaba e insert elegia
Button1 (el campo de la base real) para un boton nuevo. Ahora la cadena de
ancestros la contesta el motor (Lsp.Herencia), y entra solo cuando la cadena
sale de la unidad: un form sobre TForm no lo arranca.

  R1 lint con la homonima delante: CLEAN (ROJO en produccion: DSGN-038 Modo)
  R2 control: set Caption en esa raiz: escrito (set sigue negando lo que publica la base
     del usuario, a proposito: punto declarado para la 1.20)
  R3 ModalResult = mrOK en esa raiz: lint lo nombra (el juez llega a TForm por la base real)
  R4 insert de un TButton: Button2 (Button1 es de la base real) (ROJO: Button1)
  R5 la base en una SUBCARPETA del proyecto (base\\UBase2): juzgada - ModalResult
     nombrado y Alto (publicada) no (ROJO: sin juzgar, CLEAN)
  R6 sin ajustes de proyecto (ni .dpr ni .dproj): la raiz no se juzga, CLEAN sin error

Uso:  python tests/test_juez_raiz_motor_1192.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('juez_raiz_motor_1192')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
# con sus renderizadores, como en el zip: desde la 1.20 el lint dice CLEAN solo
# si el lector del IDE carga lo que la tabla no juzga (DSGN-061, DSGN-154)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)

s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='juez-raiz-motor', t=300)

HOMONIMA = ('unit UA_Base;\n\ninterface\n\nuses\n  Vcl.Forms;\n\ntype\n'
            '  // la HOMONIMA: la misma clase, en otra unidad, sin la propiedad ni el boton\n'
            '  TBaseForm = class(TForm)\n  end;\n\nimplementation\n\nend.\n')
REAL = ('unit UB_Base;\n\ninterface\n\nuses\n  Vcl.Forms, Vcl.StdCtrls;\n\ntype\n'
        '  // la base REAL del form: publica Modo y tiene un Button1\n'
        '  TBaseForm = class(TForm)\n    Button1: TButton;\n  private\n    FModo: Integer;\n  published\n'
        '    property Modo: Integer read FModo write FModo;\n  end;\n\nimplementation\n\nend.\n')
SUBCARPETA = ('unit UBase2;\n\ninterface\n\nuses\n  Vcl.Forms;\n\ntype\n  TBase2 = class(TForm)\n  private\n'
              '    FAlto: Integer;\n  published\n    property Alto: Integer read FAlto write FAlto;\n  end;\n\n'
              'implementation\n\nend.\n')
SOLA = ('unit USoloBase;\n\ninterface\n\nuses\n  Vcl.Forms;\n\ntype\n  TBaseS = class(TForm)\n  private\n'
        '    FZeta: Integer;\n  published\n    property Zeta: Integer read FZeta write FZeta;\n  end;\n\n'
        'implementation\n\nend.\n')


def lint(fichero):
    return s.call('delphi_designer', {'command': 'lint', 'path': fichero}, t=300)


def limpio(r):
    return mc.es(r, 'SN_DESIGNER_LINT_OK_FMT')


def hereda(pas, dfm, base_unit, base_clase, lineas_dfm):
    """El form de delphi_create pasa a heredar de base_clase (uses base_unit) y
    su .dfm recibe lineas_dfm debajo del Caption."""
    clase = next(l for l in mc.lee(pas).splitlines() if l.strip().endswith('= class(TForm)'))
    s.call('delphi_edit', {'path': pas, 'old': clase, 'new': clase.replace('(TForm)', '(%s)' % base_clase)})
    s.call('delphi_edit', {'path': pas, 'adduses': base_unit, 'section': 'interface'})
    caption = next(l for l in mc.lee(dfm).splitlines() if l.strip().startswith('Caption = '))
    s.call('delphi_edit', {'path': dfm, 'old': caption, 'new': caption + '\n' + '\n'.join(lineas_dfm)})


try:
    listas = mc.espera_tablas(lambda tool, args, t=120: s.call(tool, args, t=t))
    check('fixture: las tablas del disenador estan listas',
          all(mc.tabla_lista(r) for _, r in listas), str(listas)[:300])

    p = os.path.join(JAIL, 'p')
    s.call('delphi_create', {'kind': 'project-vcl', 'name': 'P1192', 'dir': p}, t=120)
    DPR = os.path.join(p, 'P1192.dpr')
    for nombre, texto in (('UA_Base', HOMONIMA), ('UB_Base', REAL)):
        s.call('delphi_create', {'kind': 'unit', 'name': nombre, 'project': DPR, 'content': texto}, t=120)
    PAS = os.path.join(p, 'UMain.pas')
    DFM = os.path.join(p, 'UMain.dfm')
    hereda(PAS, DFM, 'UB_Base', 'TBaseForm', ['  Modo = 1'])

    r = lint(DFM)
    check('R1 lint con la homonima (UA_Base) delante en la carpeta: CLEAN (Modo lo publica la base real)',
          limpio(r), r[:400])
    # (set juzga Modo por el tipo que declara la base del usuario, HojaDelUsuario:
    # test_set_propiedad_usuario_1192 mide cada tipo; aqui, que llega a la base real)
    r = s.call('delphi_designer', {'command': 'set', 'path': DFM, 'component': 'FormMain', 'prop': 'Modo',
                                   'value': '2'}, t=300)
    check('R2 set Modo=2 en la raiz (publicada por la base real): escrito',
          not mc.fallo(r) and 'Modo = 2' in mc.lee(DFM), r[:400])
    s.call('delphi_edit', {'path': DFM, 'old': '  Modo = 2', 'new': '  Modo = 2\n  ModalResult = mrOK'})
    r = lint(DFM)
    check('R3 ModalResult = mrOK en esa raiz: lint lo nombra (el juez llega a TForm por la base real)',
          'ModalResult' in r and not limpio(r) and 'Modo' not in r.replace('ModalResult', ''), r[:500])
    r = s.call('delphi_designer', {'command': 'insert', 'path': DFM, 'classname': 'TButton'}, t=300)
    check('R4 insert de un TButton en el form heredado: Button2 (Button1 es un campo de la base real)',
          'Button2' in r and 'object Button2: TButton' in mc.lee(DFM) and 'object Button1' not in mc.lee(DFM),
          r[:400])

    # R5: la base en una subcarpeta del proyecto, que el barrido de la carpeta del form no veia
    s.call('delphi_create', {'kind': 'unit', 'name': 'UBase2', 'dir': 'base', 'project': DPR, 'content': SUBCARPETA},
           t=120)
    s.call('delphi_create', {'kind': 'form-vcl', 'name': 'UDos', 'project': DPR}, t=120)
    PAS2 = os.path.join(p, 'UDos.pas')
    DFM2 = os.path.join(p, 'UDos.dfm')
    hereda(PAS2, DFM2, 'UBase2', 'TBase2', ['  Alto = 1', '  ModalResult = mrOK'])
    r = lint(DFM2)
    check('R5 la base en base\\: la raiz se juzga - ModalResult nombrado, Alto (publicada por la base) no',
          'ModalResult' in r and not limpio(r) and 'Alto' not in r, r[:500])

    # R6: sin ajustes de proyecto no hay motor: la raiz se queda sin juzgar, sin error falso
    solo = os.path.join(JAIL, 'solo')
    s.call('delphi_create', {'kind': 'project-vcl', 'name': 'PSolo', 'dir': solo}, t=120)
    s.call('delphi_create', {'kind': 'unit', 'name': 'USoloBase', 'dir': solo, 'content': SOLA}, t=120)
    PAS3 = os.path.join(solo, 'UMain.pas')
    DFM3 = os.path.join(solo, 'UMain.dfm')
    hereda(PAS3, DFM3, 'USoloBase', 'TBaseS', ['  Zeta = 1'])
    for f in ('PSolo.dproj', 'PSolo.dpr'):
        r = s.call('delphi_delete', {'path': os.path.join(solo, f)}, t=120)
        assert 'FILE-021' in r, r
    r = lint(DFM3)
    check('R6 sin .dpr ni .dproj: la raiz no se juzga (sin motor), CLEAN y sin error',
          limpio(r), r[:400])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('el juez de la raiz y los heredados, por el motor (1.19.2)')
