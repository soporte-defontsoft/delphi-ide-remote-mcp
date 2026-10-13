# -*- coding: utf-8 -*-
"""Medio caracter (un sustituto suelto) en el VALOR de cadena de un form no se
escribe (1.18.2, punto 4: el sustituto suelto que llega por el JSON). Los
escritores de texto ya lo negaban (EDIT-078: delphi_edit, textedit, create,
el preview del changeset), pero designer set y styles set lo pasan a literal
con TrozosDeLiteral - '#55296', ASCII - y el codificador ya no lo ve: medido en
produccion el 13-oct, Caption = 'a'#55296'b' en un .dfm y Hint en un .style.
Ahora la puerta que recibe el valor pregunta a SueltoEnLiteral (EL lector del
suelto de la casa, SiguienteSuelto) antes de componer: DSGN-146.

  L1 designer set con el suelto en crudo ('a\\ud800b'): DSGN-146, intacto
  L2 designer set con el suelto como #55296 dentro del literal: DSGN-146
  L3 el control: un PAR valido (un emoji) se escribe, como el IDE: #55357#56832
  L4 styles set con el suelto: DSGN-146, intacto
  L5 el control de styles: el par valido se escribe
  N1-N4 los NOMBRES (designer set Name, insert, styles StyleName, styles
     clone) con el suelto: no se escriben (los niega su validacion de nombre)

Uso:  python tests/test_literal_suelto_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('literal_suelto_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
S = '\ud800'
PAR = '\U0001F600'

DFM = b"object FormD: TFormD\r\n  object Label1: TLabel\r\n    Caption = 'x'\r\n  end\r\nend\r\n"
PAS = (b"unit UD;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms, Vcl.StdCtrls;\r\n\r\ntype\r\n  TFormD = class(TForm)\r\n"
       b"    Label1: TLabel;\r\n  end;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n")
STYLE = (b"object TStyleContainer\r\n  object TLayout\r\n    StyleName = 'cardstyle'\r\n    Hint = 'x'\r\n"
         b"  end\r\nend\r\n")


def form(nombre='UD'):
    d = os.path.join(JAIL, nombre + '.dfm')
    open(d, 'wb').write(DFM)
    open(os.path.join(JAIL, nombre + '.pas'), 'wb').write(PAS.replace(b'unit UD;', ('unit %s;' % nombre).encode()))
    return d


def estilo(nombre='E'):
    p = os.path.join(JAIL, nombre + '.style')
    open(p, 'wb').write(STYLE)
    return p


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='literal-suelto', t=120)
try:
    d = form('UL1')
    r = srv.call('delphi_designer', {'path': d, 'command': 'set', 'component': 'Label1', 'prop': 'Caption',
                                     'value': "'a" + S + "b'"})
    check('L1 designer set con medio caracter en crudo: DSGN-146 y el form intacto',
          mc.abre(r, 'SR_DSGN_LITERAL_SUELTO_FMT') and open(d, 'rb').read() == DFM, r[:300])

    d = form('UL2')
    r = srv.call('delphi_designer', {'path': d, 'command': 'set', 'component': 'Label1', 'prop': 'Caption',
                                     'value': "'a'#55296'b'"})
    check('L2 designer set con medio caracter como #55296 en el literal: DSGN-146 y el form intacto',
          mc.abre(r, 'SR_DSGN_LITERAL_SUELTO_FMT') and open(d, 'rb').read() == DFM, r[:300])

    d = form('UL3')
    r = srv.call('delphi_designer', {'path': d, 'command': 'set', 'component': 'Label1', 'prop': 'Caption',
                                     'value': "'a" + PAR + "b'"})
    check('L3 el control: un par valido se escribe como el IDE (#55357#56832)',
          not mc.rechazado(r) and b"'a'#55357#56832'b'" in open(d, 'rb').read(), (r[:200], open(d, 'rb').read()))

    p = estilo('L4')
    antes = open(p, 'rb').read()
    r = srv.call('delphi_styles', {'path': p, 'command': 'set', 'style': 'cardstyle', 'prop': 'Hint',
                                   'value': "'a" + S + "b'"})
    check('L4 styles set con medio caracter: DSGN-146 y el estilo intacto',
          mc.abre(r, 'SR_DSGN_LITERAL_SUELTO_FMT') and open(p, 'rb').read() == antes, r[:300])

    p = estilo('L5')
    r = srv.call('delphi_styles', {'path': p, 'command': 'set', 'style': 'cardstyle', 'prop': 'Hint',
                                   'value': "'a" + PAR + "b'"})
    check('L5 el control de styles: el par valido se escribe (#55357#56832)',
          not mc.rechazado(r) and b"#55357#56832" in open(p, 'rb').read(), (r[:200], open(p, 'rb').read()))

    # ---- los NOMBRES: su validacion los niega; que no se escriban
    d = form('UN1')
    r = srv.call('delphi_designer', {'path': d, 'command': 'set', 'component': 'Label1', 'prop': 'Name',
                                     'value': 'Bot' + S})
    check('N1 designer set Name con medio caracter: negado y el form intacto',
          mc.rechazado(r) and open(d, 'rb').read() == DFM, r[:300])

    d = form('UN2')
    r = srv.call('delphi_designer', {'path': d, 'command': 'insert', 'classname': 'TButton', 'component': 'Bot' + S})
    check('N2 designer insert con un nombre con medio caracter: negado y el form intacto',
          mc.rechazado(r) and open(d, 'rb').read() == DFM, r[:300])

    p = estilo('N3')
    antes = open(p, 'rb').read()
    r = srv.call('delphi_styles', {'path': p, 'command': 'set', 'style': 'cardstyle', 'prop': 'StyleName',
                                   'value': "'card" + S + "'"})
    check('N3 styles set StyleName con medio caracter: negado y el estilo intacto',
          mc.rechazado(r) and open(p, 'rb').read() == antes, r[:300])

    p = estilo('N4')
    antes = open(p, 'rb').read()
    r = srv.call('delphi_styles', {'path': p, 'command': 'clone', 'style': 'cardstyle', 'name': 'otra' + S})
    check('N4 styles clone con un nombre con medio caracter: negado y el estilo intacto',
          mc.rechazado(r) and open(p, 'rb').read() == antes, r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('literal sin medio caracter 1182')
