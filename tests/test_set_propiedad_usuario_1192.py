# -*- coding: utf-8 -*-
"""set escribe una propiedad que publica una clase del USUARIO en la raiz del
form (1.19.2; declarado para la 1.20 desde el H8 y cerrado aqui, David: "en
1.19 asentamos").

TFormMain = class(TBaseForm), con TBaseForm publicando Modo: Integer, Nombre:
string, Activo: Boolean, Lado: TAlign, Tono: TTono (un enumerado suyo), Tonos:
TTonos (un conjunto suyo), Tinte: TColor y Cosa: TCosa (una clase suya). lint
ya callaba esas propiedades; set las negaba TODAS como "Modo does not exist in
TForm" (DSGN-087), porque la tabla no las conoce. Ahora set juzga el valor por
el tipo escrito, con los mismos jueces que los de la tabla (HojaDelUsuario): un
tipo del compilador, uno que la tabla conoce por su nombre, o un enumerado o
conjunto declarado en la unidad de la clase; lo que nadie puede juzgar (TCosa)
se niega diciendo por que, y una ruta dentro de una (Modo.X) tambien.

  S1  Modo=2: escrito                     (ROJO en produccion: negado)
  S2  Modo=abc: DSGN-093, un entero
  S3  Nombre='Hola': escrito como literal (ROJO)
  S4  Activo=True: escrito                (ROJO)
  S5  Activo=Quiza: negado, False, True
  S6  Lado=alClient: escrito              (ROJO)
  S7  Lado=alNada: negado, no es un valor de TAlign
  S8  Tono=toOscuro: escrito              (ROJO)
  S9  Tono=toRojo: negado, toClaro, toOscuro
  S10 Tonos=[toClaro]: escrito            (ROJO)
  S11 Tonos=toClaro: negado, es un SET
  S11b Tonos=[toRojo]: negado con los elementos validos (toClaro, toOscuro; 1.20.1)
  S12 Tinte=clRed: escrito                (ROJO)
  S13 Tinte=clNada: negado
  S14 Cosa=X: negado diciendo que TCosa no lo puede juzgar nadie, delphi_edit (ROJO: "no existe en TForm")
  S15 Modo.X=1: negado, no sigue una ruta (ROJO)
  S16 lint con todo lo escrito: CLEAN
  S17 preview: las publicadas por la base en ignored, con la nota DSGN-152 (ROJO: sin nota)

Uso:  python tests/test_set_propiedad_usuario_1192.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('set_propiedad_usuario_1192')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)

s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='set-propiedad-usuario', t=300)

UBASE = ('unit UB_Base;\n\ninterface\n\nuses\n  Vcl.Forms, Vcl.Controls, Vcl.Graphics;\n\ntype\n'
         '  TTono = (toClaro, toOscuro);\n  TTonos = set of TTono;\n  TCosa = class(TObject)\n  end;\n\n'
         '  TBaseForm = class(TForm)\n  private\n    FModo: Integer;\n    FNombre: string;\n    FActivo: Boolean;\n'
         '    FLado: TAlign;\n    FTono: TTono;\n    FTonos: TTonos;\n    FTinte: TColor;\n    FCosa: TCosa;\n'
         '  published\n    property Modo: Integer read FModo write FModo;\n'
         '    property Nombre: string read FNombre write FNombre;\n'
         '    property Activo: Boolean read FActivo write FActivo;\n'
         '    property Lado: TAlign read FLado write FLado;\n'
         '    property Tono: TTono read FTono write FTono;\n'
         '    property Tonos: TTonos read FTonos write FTonos;\n'
         '    property Tinte: TColor read FTinte write FTinte;\n'
         '    property Cosa: TCosa read FCosa write FCosa;\n  end;\n\nimplementation\n\nend.\n')


def pon(prop, valor):
    return s.call('delphi_designer', {'command': 'set', 'path': DFM, 'component': 'FormMain', 'prop': prop,
                                      'value': valor}, t=300)


def escrito(r, linea):
    return not mc.fallo(r) and linea in mc.lee(DFM)


def negado(r, *textos):
    return mc.fallo(r) and all(t in r for t in textos)


try:
    listas = mc.espera_tablas(lambda tool, args, t=120: s.call(tool, args, t=t))
    check('fixture: las tablas del disenador estan listas',
          all(not mc.tiene(r, 'DSGN-051') and not mc.fallo(r) for _, r in listas), str(listas)[:300])

    p = os.path.join(JAIL, 'p')
    s.call('delphi_create', {'kind': 'project-vcl', 'name': 'PSet1192', 'dir': p}, t=120)
    DPR = os.path.join(p, 'PSet1192.dpr')
    s.call('delphi_create', {'kind': 'unit', 'name': 'UB_Base', 'project': DPR, 'content': UBASE}, t=120)
    PAS = os.path.join(p, 'UMain.pas')
    DFM = os.path.join(p, 'UMain.dfm')
    s.call('delphi_edit', {'path': PAS, 'old': '  TFormMain = class(TForm)', 'new': '  TFormMain = class(TBaseForm)'})
    s.call('delphi_edit', {'path': PAS, 'adduses': 'UB_Base', 'section': 'interface'})

    r = pon('Modo', '2')
    check('S1 Modo=2 (Integer de la base del usuario): escrito', escrito(r, 'Modo = 2'), r[:400])
    r = pon('Modo', 'abc')
    check('S2 Modo=abc: negado, un entero (DSGN-093)', negado(r, 'DSGN-093') and 'Modo = abc' not in mc.lee(DFM), r[:400])
    r = pon('Nombre', "'Hola'")
    check("S3 Nombre='Hola' (string): escrito como literal", escrito(r, "Nombre = 'Hola'"), r[:400])
    r = pon('Activo', 'True')
    check('S4 Activo=True (Boolean): escrito', escrito(r, 'Activo = True'), r[:400])
    r = pon('Activo', 'Quiza')
    check('S5 Activo=Quiza: negado, False, True', negado(r, 'DSGN-087', 'False, True'), r[:400])
    r = pon('Lado', 'alClient')
    check('S6 Lado=alClient (TAlign, de la tabla): escrito', escrito(r, 'Lado = alClient'), r[:400])
    r = pon('Lado', 'alNada')
    check('S7 Lado=alNada: negado, no es un valor de TAlign', negado(r, 'DSGN-087', 'TAlign'), r[:400])
    r = pon('Tono', 'toOscuro')
    check('S8 Tono=toOscuro (enumerado del usuario): escrito', escrito(r, 'Tono = toOscuro'), r[:400])
    r = pon('Tono', 'toRojo')
    check('S9 Tono=toRojo: negado, toClaro, toOscuro', negado(r, 'DSGN-087', 'toClaro, toOscuro'), r[:400])
    r = pon('Tonos', '[toClaro]')
    check('S10 Tonos=[toClaro] (conjunto del usuario): escrito', escrito(r, 'Tonos = [toClaro]'), r[:400])
    r = pon('Tonos', 'toClaro')
    check('S11 Tonos=toClaro: negado, es un SET', negado(r, 'DSGN-087', 'SET'), r[:400])
    r = pon('Tonos', '[toRojo]')
    check('S11b Tonos=[toRojo]: negado con los elementos validos, como un enumerado (1.20.1)',
          negado(r, 'DSGN-087', 'toRojo', 'valid: toClaro, toOscuro'), r[:400])
    r = pon('Tinte', 'clRed')
    check('S12 Tinte=clRed (TColor): escrito', escrito(r, 'Tinte = clRed'), r[:400])
    r = pon('Tinte', 'clNada')
    check('S13 Tinte=clNada: negado', mc.fallo(r) and 'Tinte = clNada' not in mc.lee(DFM), r[:400])
    r = pon('Cosa', 'X')
    check('S14 Cosa=X (una clase del usuario): negado diciendo que TCosa no lo puede juzgar, delphi_edit',
          negado(r, 'DSGN-087', 'TCosa', 'delphi_edit') and 'does not exist in TForm' not in r, r[:400])
    r = pon('Modo.X', '1')
    check('S15 Modo.X=1: negado, set no sigue una ruta dentro de una propiedad de la base',
          negado(r, 'DSGN-087', 'path', 'delphi_edit') and 'does not exist in TForm' not in r, r[:400])
    r = s.call('delphi_designer', {'command': 'lint', 'path': DFM}, t=300)
    check('S16 lint con todo lo escrito: CLEAN', mc.es(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:400])

    r = s.call('delphi_designer', {'command': 'preview', 'path': DFM, 'maxwidth': 100}, t=300)
    try:
        j = json.loads(r)
    except Exception:
        j = {}
    ign = [i.get('property') for i in j.get('ignored', []) if i.get('component') == 'FormMain']
    check('S17 preview: las publicadas por la base en ignored, con la nota DSGN-152 (no es un error del form)',
          'Modo' in ign and 'DSGN-152' in j.get('ignoredUserNote', '') and 'TBaseForm' in j.get('ignoredUserNote', ''),
          (ign, j.get('ignoredUserNote'), r[:300]))
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('set con propiedades publicadas por el usuario (1.19.2)')
