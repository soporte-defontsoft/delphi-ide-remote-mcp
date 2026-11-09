# -*- coding: utf-8 -*-
"""Textos que confundian a un agente (bloque 6 de la 1.24). Cada uno nacio de una
llamada medida de Hermes: la herramienta hizo lo correcto y la respuesta no lo decia.

  T1 V221 delphi_move de un fichero a una carpeta que existe: era LSP-016, el de leer,
     que manda a delphi_list; ahora MOVE-026 con la ruta final. Nada se mueve
  T2 V157 delphi_styles lint de un project sin .fmx ni .pas: lookupsUsed 0, sin decir
     que no miro ningun form; con forms, la nota no sale
  T3 V179 delphi_styles set de un color sin la x: STYLE-050, ahora con la forma del
     color; a otra propiedad o a otro valor no se le dice
  T4 V156 delphi_designer lint de un frame con StyleLookup: CLEAN no habla de ellos, y
     ahora lo dice; un form corriente, no
  T5 V158 MOVE-025 dice que crea las carpetas padre
  T6 V148 edits en un form: el informe de cada entrada dice en que objeto cayo
  T7 V189 edits sobre una linea larga: el eco la corta y lo dice (...); una corta, entera
  T8 V190 delphi_signature null: sus causas, no "dentro de un identificador" de LSP-029

Uso:  python tests/test_textos_124.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('textos_124')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True, con_render=True)


def escribe(rel, texto):
    ruta = os.path.join(JAIL, rel)
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    open(ruta, 'wb').write(texto.replace('\n', '\r\n').encode('ascii'))
    return ruta


def J(r):
    try:
        return json.loads(r)
    except ValueError:
        return {}


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='textos', t=300)
try:
    # ---- T1
    F = escribe('mover\\a.txt', 'hola\n')
    CARPETA = os.path.join(JAIL, 'mover', 'dentro')
    os.makedirs(CARPETA)
    r = srv.call('delphi_move', {'path': F, 'dest': CARPETA})
    check('T1 V221 un fichero a una carpeta que existe: MOVE-026, con la ruta final y sin mandar a delphi_list; nada se mueve',
          mc.abre(r, 'SR_MOVE_DEST_ES_CARPETA_FMT') and 'a.txt' in r and 'delphi_list' not in r and
          os.path.exists(F) and not os.listdir(CARPETA), r[:300])
    r = srv.call('delphi_move', {'path': F, 'dest': os.path.join(CARPETA, 'a.txt')})
    check('T1b ...y la ruta que propone es la que vale', not mc.rechazado(r) and os.path.exists(os.path.join(CARPETA, 'a.txt')), r[:300])

    # ---- T7
    LARGA = 'const X = ' + "'" + 'z' * 120 + "'" + ';'
    P7 = escribe('eco\\U7.pas', 'unit U7;\ninterface\n// una\n// dos\nimplementation\nend.\n')
    r = srv.call('delphi_edit', {'path': P7, 'edits': [{'old': '// una', 'new': LARGA}, {'old': '// dos', 'new': '// corta'}]})
    check('T7 V189 el eco de una linea larga dice que la corta, y una corta sale entera',
          not mc.rechazado(r) and 'z' * 60 + '...' in r and '|// corta' in r and 'z' * 120 not in r, r[:500])

    # ---- T8
    P8 = escribe('firma\\U8.pas', 'unit U8;\ninterface\nimplementation\nend.\n')
    r = srv.call('delphi_signature', {'path': P8, 'line': 0, 'character': 0}, 240)
    check('T8 V190 signature null: sus causas, sin el "dentro de un identificador" de LSP-029',
          mc.abre(r, 'SN_LSP_NULL_SIGNATURE_NOTE') and 'INSIDE an identifier' not in r and 'delphi_hover' in r, r[:400])

    # ---- T5
    G = escribe('mover\\b.txt', 'hola\n')
    r = srv.call('delphi_move', {'path': G, 'dest': os.path.join(JAIL, 'mover', 'sinext')})
    check('T5 V158 MOVE-025 dice que las carpetas padre se crean', mc.es(r, 'SN_MOVE_DESTINO_SIN_EXTENSION_FMT') and 'parent folders' in r, r[:400])
    check('T5 ...y la carpeta de dest ya existia: sin MOVE-027', not mc.es(r, 'SN_MOVE_CARPETA_CREADA_FMT'), r[:400])
    # P6 de la 1.29.1: la carpeta que dest necesita y no existe se crea, y ahora se dice
    H = escribe('mover\\c.txt', 'hola\n')
    r = srv.call('delphi_move', {'path': H, 'dest': os.path.join(JAIL, 'mover', 'nueva', 'sub', 'c.txt')})
    check('T5b una carpeta de dest que no existia: se crea y MOVE-027 la nombra',
          mc.es(r, 'SN_MOVE_CARPETA_CREADA_FMT') and 'sub' in r and
          os.path.isfile(os.path.join(JAIL, 'mover', 'nueva', 'sub', 'c.txt')), r[:400])

    # ---- T2 y T3: un .style de verdad
    ESTILO = ("object TStyleContainer\n  object TLayout\n    StyleName = 'cardstyle'\n  end\n"
              "  object TRectangle\n    StyleName = 'fondo'\n    Fill.Color = xFFF6ECDB\n  end\nend\n")
    PLANO = escribe('plano\\estilos\\t.style', ESTILO)
    os.makedirs(os.path.join(JAIL, 'vacio'))
    r = srv.call('delphi_styles', {'command': 'lint', 'path': os.path.dirname(PLANO), 'project': os.path.join(JAIL, 'vacio')}, t=120)
    j = J(r)
    check('T2 V157 un project sin forms: lookupsUsed 0 y lo dice (STYLE-064)',
          j.get('lookupsUsed') == 0 and mc.es(j.get('noFormsNote', ''), 'SN_STYLES_SIN_FORMS_FMT'), r[:500])
    escribe('solopas\\U.pas', 'unit U;\ninterface\nimplementation\nend.\n')
    r = srv.call('delphi_styles', {'command': 'lint', 'path': os.path.dirname(PLANO), 'project': os.path.join(JAIL, 'solopas')}, t=120)
    check('T2c un .pas sin ningun .fmx: tampoco miro un form, y lo dice', mc.es(J(r).get('noFormsNote', ''), 'SN_STYLES_SIN_FORMS_FMT'), r[:500])
    escribe('confrm\\U.fmx', "object Form1: TForm1\n  Left = 0\n  Top = 0\n  ClientHeight = 100\n  ClientWidth = 100\nend\n")
    r = srv.call('delphi_styles', {'command': 'lint', 'path': os.path.dirname(PLANO), 'project': os.path.join(JAIL, 'confrm')}, t=120)
    check('T2b con un form mirado no sale', bool(J(r)) and 'noFormsNote' not in J(r), r[:500])

    r = srv.call('delphi_styles', {'command': 'set', 'path': PLANO, 'style': 'fondo', 'prop': 'Fill.Color', 'value': 'fff7dfc5'}, t=120)
    check('T3 V179 un color sin la x: STYLE-050 y su forma', mc.abre(r, 'SR_STYLES_FMX_LO_IGNORARIA_FMT') and mc.es(r, 'SN_STYLES_COLOR_SIN_X'), r[:400])
    r = srv.call('delphi_styles', {'command': 'set', 'path': PLANO, 'style': 'fondo', 'prop': 'Fill.Color', 'value': 'NoEsColor'}, t=120)
    # sobre la MISMA negativa (STYLE-050), la que lleva la pista cuando toca: un set que fallara por
    # otra cosa tampoco la traia (revisor de baterias de la 1.27)
    check('T3b ...a otro valor no se le dice',
          mc.abre(r, 'SR_STYLES_FMX_LO_IGNORARIA_FMT') and not mc.es(r, 'SN_STYLES_COLOR_SIN_X'), r[:400])

    # ---- T4
    escribe('fr\\UFr.pas', 'unit UFr;\n\ninterface\n\nuses\n  System.Classes, FMX.Forms, FMX.Controls, FMX.StdCtrls, FMX.Types;\n\ntype\n'
            '  TFrame1 = class(TFrame)\n    Button1: TButton;\n  end;\n\nimplementation\n\n{$R *.fmx}\n\nend.\n')
    FRAME = escribe('fr\\UFr.fmx', "object Frame1: TFrame1\n  Size.Width = 200.000000000000000000\n  Size.Height = 100.000000000000000000\n"
                    "  object Button1: TButton\n    StyleLookup = 'cardstyle'\n    TabOrder = 0\n    Text = 'B'\n  end\nend\n")
    r = srv.call('delphi_designer', {'command': 'lint', 'path': FRAME}, t=240)
    check('T4 V156 un frame con StyleLookup: lo dice sin que la nota sea un aviso (DSGN-178)',
          mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_JUZGAR_FMT') and '1 StyleLookup' in r, r[:600])
    escribe('fo\\UFo.pas', 'unit UFo;\n\ninterface\n\nuses\n  System.Classes, FMX.Forms, FMX.Controls, FMX.StdCtrls, FMX.Types;\n\ntype\n'
            '  TForm2 = class(TForm)\n    Button1: TButton;\n  end;\n\nimplementation\n\n{$R *.fmx}\n\nend.\n')
    # con un StyleLookup: el T4b sin el pasaba igual sin la condicion del StyleBook
    FORM = escribe('fo\\UFo.fmx', "object Form2: TForm2\n  Left = 0\n  Top = 0\n  ClientHeight = 100\n  ClientWidth = 100\n"
                   "  object Button1: TButton\n    StyleLookup = 'cardstyle'\n    TabOrder = 0\n    Text = 'B'\n  end\nend\n")
    r = srv.call('delphi_designer', {'command': 'lint', 'path': FORM}, t=240)
    # con su control: el StyleLookup SE JUZGO (DSGN-175, ningun estilo que el form ve lo define); una
    # negativa o un lint que no mirara los lookups tampoco traian el DSGN-178 (revisor de baterias
    # de la 1.27)
    check('T4b un form corriente con StyleLookup y sin StyleBook: se juzga, no sale DSGN-178',
          mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_ESTILO_FMT') and not mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_JUZGAR_FMT'),
          r[:400])

    # ---- T6: edits con occurrence en un form: en que objeto cayo
    DOS = escribe('dos\\UDos.dfm', "object FormDos: TFormDos\n  Left = 0\n  Top = 0\n  Caption = 'D'\n  ClientHeight = 200\n  ClientWidth = 300\n"
                  "  object Button1: TButton\n    Left = 8\n    Top = 8\n    Width = 75\n    Height = 25\n    TabOrder = 0\n  end\n"
                  "  object Button2: TButton\n    Left = 8\n    Top = 40\n    Width = 75\n    Height = 25\n    TabOrder = 1\n  end\nend\n")
    r = srv.call('delphi_edit', {'path': DOS, 'edits': [{'old': 'Width = 75', 'new': 'Width = 90', 'occurrence': 2}]}, t=120)
    check('T6 V148 el informe de una entrada dice en que objeto cayo', '(in Button2)' in r, r[:500])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('textos 1.24')
