# -*- coding: utf-8 -*-
"""Que un valor es un NUMERO lo decia una regex (Lsp.DesignerBin.EsNumeroDeForm)
sin los sufijos que su parser lee y su escritor pone: 41488.4481893519d (un
TDate que una propiedad escribe por CODIGO, WriteDate: AccessTokenExpiryDate de
TOAuth2Authenticator en RESTDemo\\uMain_frm.dfm), 34700d (un TDate en un
Variant, IBX2FDMigration), 1.5s, 12.5c. Medido el 18-oct-2026 en produccion:
set de un valor asi -> DSGN-092 "not a one-line form value", sin preguntar al
lector, que lo carga (ReadDate). Ahora lo dice el parser del IDE (DesignerAFlujo)
con el tipo con que deja el valor; y una propiedad de coma flotante PUBLICADA
toma solo lo que lee ReadFloat (sin sufijo: cae a ReadInt64 y el form no carga,
medido en el RTL), y lo dice.

  N1 set de AccessTokenExpiryDate (por codigo) = 41500.5d: escrito y el form
     carga (ROJO en produccion: DSGN-092)
  N2 un TDate PUBLICADO (DateTimePicker1.Date) con 45123.5d: negado diciendo
     que ReadFloat no toma el sufijo, nada escrito (ROJO: la gramatica, sin el)
  N3 controles: Left = 34700d y Date = abc negados; Date = 45200.25 escrito

Uso:  python tests/test_numero_del_parser_1202.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('numero_parser_1202')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
APPDATA = os.path.join(BASE, 'appdata')
os.makedirs(APPDATA)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'LOCALAPPDATA': APPDATA}), nombre='numero', t=300)
call = srv.call


def lee(ruta):
    return open(ruta, 'rb').read()


try:
    PROY = os.path.join(JAIL, 'num')
    DFM = os.path.join(PROY, 'UMain.dfm')
    PAS = os.path.join(PROY, 'UMain.pas')
    r = call('delphi_create', {'kind': 'project-vcl', 'name': 'PNum', 'dir': PROY}, t=120)
    check('fixture: el proyecto VCL', not mc.fallo(r) and os.path.isfile(DFM), r[:200])
    mc.espera_info(call, {'command': 'info', 'classname': 'TDateTimePicker', 'framework': 'vcl', 'filter': 'Date'},
                   cond=lambda r: '"Date"' in r, tope=300)
    r = call('delphi_designer', {'command': 'insert', 'path': DFM, 'classname': 'TDateTimePicker'})
    check('fixture: un TDateTimePicker', not mc.fallo(r) and b'DateTimePicker1' in lee(DFM), r[:200])
    # un no visual a mano (insert es para los visuales), con su campo y su unidad,
    # como lo deja el IDE en RESTDemo
    t = lee(DFM).decode('utf-8-sig')
    i = t.rstrip().rfind('end')
    t = (t[:i] + '  object OAuth2: TOAuth2Authenticator\r\n    AccessTokenExpiryDate = 41488.4481893519d\r\n'
         '    Left = 100\r\n    Top = 100\r\n  end\r\n' + t[i:])
    open(DFM, 'w', encoding='utf-8-sig', newline='').write(t)
    p = lee(PAS).decode('utf-8-sig')
    p = p.replace('    DateTimePicker1: TDateTimePicker;', '    DateTimePicker1: TDateTimePicker;\r\n'
                  '    OAuth2: TOAuth2Authenticator;', 1)
    p = p.replace('Vcl.ComCtrls', 'Vcl.ComCtrls, REST.Authenticator.OAuth', 1)
    open(PAS, 'w', encoding='utf-8-sig', newline='').write(p)
    r = call('delphi_designer', {'command': 'lint', 'path': DFM})
    check('fixture: el form con el autenticador carga (lint)', mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:250])

    # ------------------------------------------------------------------ N1
    r = call('delphi_designer', {'command': 'set', 'path': DFM, 'component': 'OAuth2',
                                 'prop': 'AccessTokenExpiryDate', 'value': '41500.5d'})
    check('N1 set de una fecha que la clase escribe por codigo (41500.5d): escrita',
          not mc.rechazado(r) and b'AccessTokenExpiryDate = 41500.5d' in lee(DFM), r[:250])
    r = call('delphi_designer', {'command': 'lint', 'path': DFM})
    check('N1 ...y el form carga', mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:250])

    # ------------------------------------------------------------------ N2
    antes = lee(DFM)
    r = call('delphi_designer', {'command': 'set', 'path': DFM, 'component': 'DateTimePicker1',
                                 'prop': 'Date', 'value': '45123.5d'})
    check('N2 un TDate PUBLICADO con el sufijo: negado diciendo por que (ReadFloat), nada escrito',
          mc.rechazado(r) and 'ReadFloat' in r and lee(DFM) == antes, r[:300])

    # ------------------------------------------------------------------ N3
    r = call('delphi_designer', {'command': 'set', 'path': DFM, 'component': 'DateTimePicker1',
                                 'prop': 'Left', 'value': '34700d'})
    check('N3 un entero no toma un TDate: negado y nada escrito', mc.rechazado(r) and lee(DFM) == antes, r[:250])
    r = call('delphi_designer', {'command': 'set', 'path': DFM, 'component': 'DateTimePicker1',
                                 'prop': 'Date', 'value': 'abc'})
    check('N3 un TDate no toma texto: negado y nada escrito', mc.rechazado(r) and lee(DFM) == antes, r[:250])
    r = call('delphi_designer', {'command': 'set', 'path': DFM, 'component': 'DateTimePicker1',
                                 'prop': 'Date', 'value': '45200.25'})
    check('N3 control: sin sufijo, como siempre', not mc.rechazado(r) and b'Date = 45200.25' in lee(DFM), r[:250])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('un numero por el parser del IDE 1202')
