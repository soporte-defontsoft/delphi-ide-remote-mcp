# -*- coding: utf-8 -*-
"""Un literal que preview niega se dice cuando se escribe y en el lint.

Un valor que es una ruta bajo Program Files o Windows (DSGN-115, por su texto): set y delphi_edit lo escribian, lint
decia CLEAN y solo preview lo negaba, despues, con la form entera. El form es valido y compila: se avisa, no se niega.
El juez es el de preview, uno; el valor nunca se ensena. Tras una edicion, solo lo que ella trae.

Usage:  python tests/test_literal_nota_125.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

NOTA = 'SN_DESIGNER_LITERAL_QUE_PREVIEW_NIEGA_FMT'
NIEGA = 'SR_DESIGNER_LITERAL_FUERA_FMT'
BASE = mc.carpeta('literal-nota-125')
EXE = mc.copia_exe(BASE, con_render=True)
RAIZ = os.path.join(BASE, 'raiz')
os.makedirs(RAIZ)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': RAIZ}), nombre='literal-nota', t=240)
call = srv.call

PAS = ('unit %(u)s;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms, Vcl.StdCtrls, System.Classes, Vcl.Controls;\r\n\r\ntype\r\n'
       '  T%(u)s = class(TForm)\r\n    Label1: TLabel;\r\n    Label2: TLabel;\r\n    Lista: TListBox;\r\n  end;\r\n\r\n'
       'implementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n')
DFM = ("object %(u)s: T%(u)s\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'F'\r\n  ClientHeight = 100\r\n  ClientWidth = 200\r\n"
       "  object Label1: TLabel\r\n    Left = 8\r\n    Top = 8\r\n    Width = 50\r\n    Height = 13\r\n    Caption = 'Uno'\r\n  end\r\n"
       "  object Label2: TLabel\r\n    Left = 8\r\n    Top = 28\r\n    Width = 50\r\n    Height = 13\r\n    Caption = 'Dos'\r\n  end\r\n"
       "  object Lista: TListBox\r\n    Left = 8\r\n    Top = 48\r\n    Width = 80\r\n    Height = 40\r\n    TabOrder = 0\r\n  end\r\nend\r\n")


def form(carpeta, nombre='UF'):
    d = os.path.join(RAIZ, carpeta)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, nombre + '.pas'), 'w', newline='') as f:
        f.write(PAS % {'u': nombre})
    p = os.path.join(d, nombre + '.dfm')
    with open(p, 'w', newline='') as f:
        f.write(DFM % {'u': nombre})
    return p


def poner(p, valor, comp='Label1', prop='Caption'):
    return call('delphi_designer', {'command': 'set', 'path': p, 'component': comp, 'prop': prop, 'value': valor})


def lint(p):
    return call('delphi_designer', {'command': 'lint', 'path': p})


def preview(p):
    return call('delphi_designer', {'command': 'preview', 'path': p, 'out': p + '.png', 'inline': False})


try:
    D = form('Uno')
    t = lint(D)
    check('sin literales, CLEAN y sin nota', mc.es(t, 'SN_DESIGNER_LINT_OK_FMT') and not mc.es(t, NOTA), t[:300])

    for valor in ('C:\\Program Files\\foo.png', 'C:\\Windows\\foo'):
        t = poner(D, valor)
        check('set de %s: lo escribe y lo dice' % valor, not mc.fallo(t) and mc.es(t, NOTA), t[:400])
        check('...sin ensenar el valor en la nota', 'foo' not in ' '.join((mc.como_json(t) or {}).get('lint') or ['foo']), t[:600])
        t = lint(D)
        check('lint de %s: no CLEAN, nota con la propiedad y su linea' % valor,
              mc.es(t, NOTA) and not mc.es(t, 'SN_DESIGNER_LINT_OK_FMT') and 'Caption' in t and 'line 12' in t and 'foo' not in t, t[:500])
        t = preview(D)
        check('preview lo sigue negando: el mismo juez', mc.es(t, NIEGA), t[:300])

    for valor in ('Abrir C:\\Program Files\\foo', '.\\foo.png', 'foo.png'):
        t = poner(D, valor)
        check('set de %s: sin nota' % valor, not mc.fallo(t) and not mc.es(t, NOTA), t[:400])
        t = lint(D)
        check('lint de %s: CLEAN' % valor, mc.es(t, 'SN_DESIGNER_LINT_OK_FMT'), t[:300])
        t = preview(D)
        check('preview de %s: se dibuja' % valor, not mc.fallo(t) and not mc.es(t, NIEGA), t[:300])

    # solo lo que la edicion trae; lint, todo
    D = form('Dos')
    poner(D, 'C:\\Program Files\\foo.png')
    t = poner(D, 'Otro', comp='Label2')
    check('set de OTRA propiedad: no repite la nota de la que ya estaba', not mc.fallo(t) and not mc.es(t, NOTA), t[:400])
    check('...y el lint la sigue dando', mc.es(lint(D), NOTA))

    # delphi_edit escribe el mismo form: la misma nota
    D = form('Tres')
    t = call('delphi_edit', {'path': D, 'old': "    Caption = 'Uno'", 'new': "    Caption = 'C:\\Program Files\\foo.png'"})
    check('delphi_edit de un literal asi: lo dice', not mc.fallo(t) and mc.es(t, NOTA), t[:500])
    t = call('delphi_edit', {'path': D, 'old': "    Caption = 'Dos'", 'new': "    Caption = 'Tres'"})
    check('delphi_edit de otra linea: no lo repite', not mc.fallo(t) and not mc.es(t, NOTA), t[:500])

    # un elemento de una lista de cadenas
    D = form('Cuatro')
    with open(D, newline='') as f:
        txt = f.read()
    txt = txt.replace("    TabOrder = 0\r\n", "    Items.Strings = (\r\n      'uno'\r\n      'C:\\Program Files\\foo.png')\r\n    TabOrder = 0\r\n")
    with open(D, 'w', newline='') as f:
        f.write(txt)
    t = lint(D)
    check('lint: un elemento de Items.Strings tambien', mc.es(t, NOTA) and 'Items.Strings' in t and 'foo' not in t, t[:500])

    # lo que dice la nota de los hermanos, medido
    D = form('Cinco')
    H = form('Cinco', 'UH')
    poner(H, 'C:\\Program Files\\foo.png')
    t = preview(D)
    check('la nota dice la verdad: un hermano con el literal niega el preview de esta', mc.es(t, NIEGA), t[:300])
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('literal note 1.25 battery')
