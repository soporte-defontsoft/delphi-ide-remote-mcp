# -*- coding: utf-8 -*-
"""UNA regla de "ya esta en el uses": la de dcc, con los ambitos del proyecto
(V79, 1.23.1). adduses comparaba el nombre exacto (LocateEntry), el .dpr con
su propio bucle, e insert y check-binding el ultimo trozo de cualquier ambito
(UnidadEnUses). Medido con dcc el 26-oct: adduses=StdCtrls sobre un uses con
Vcl.StdCtrls entraba (USES-013) y el build daba E2004 "Identifier redeclared".
dcc resuelve un nombre TAL CUAL si esa unidad existe y, si no, con el primero
de los ambitos del proyecto (DCC_Namespace) con el que exista: medido el
27-oct, un proyecto con SU unidad Messages compila "uses Winapi.Messages,
Messages".

  U1 adduses Forms (interface) con Vcl.Forms en el interface: ya esta, nada escrito
  U2 adduses Forms (implementation) con Vcl.Forms en el interface: en la otra, nada escrito
  U3 adduses Messages con Winapi.Messages en un proyecto con SU Messages: entra (otra unidad)
  U4 adduses Vcl.Forms;Forms en una unidad sin ellas: entra UNA
  U5 removeuses Forms quita Vcl.Forms (la misma unidad)
  U6 el proyecto compila despues de todo (sin E2004)

Uso:  python tests/test_uses_ambitos_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('uses_ambitos_1231')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='uses-ambitos', t=300)


def bytes_de(p):
    return open(p, 'rb').read()


try:
    call = srv.call
    PROY = os.path.join(JAIL, 'Amb')
    r = call('delphi_create', {'kind': 'project-vcl', 'name': 'Amb', 'dir': PROY}, t=120)
    check('preparacion: un proyecto VCL nuevo', not mc.fallo(r), r[:300])
    DPR = os.path.join(PROY, 'Amb.dpr')
    # la unidad del form principal: la que lleva Vcl.Forms en su interface
    MAIN = ''
    for n in os.listdir(PROY):
        if n.lower().endswith('.pas') and b'Vcl.Forms' in bytes_de(os.path.join(PROY, n)):
            MAIN = os.path.join(PROY, n)
    check('preparacion: la unidad principal usa Vcl.Forms', MAIN != '', os.listdir(PROY))

    antes = bytes_de(MAIN)
    r = call('delphi_edit', {'path': MAIN, 'adduses': 'Forms', 'section': 'interface'})
    check('U1 adduses Forms con Vcl.Forms en el interface: ya esta (era USES-013 y el build E2004), nada escrito',
          mc.abre(r, 'SN_ADDUSES_PRESENT_FMT') and bytes_de(MAIN) == antes, r[:300])
    r = call('delphi_edit', {'path': MAIN, 'adduses': 'Forms', 'section': 'implementation'})
    check('U2 adduses Forms en implementation con Vcl.Forms en el interface: en la otra, nada escrito',
          mc.abre(r, 'SN_ADDUSES_PRESENT_OTHER_FMT') and bytes_de(MAIN) == antes, r[:300])

    # el contraejemplo medido: con SU unidad Messages, Messages es otra unidad
    r = call('delphi_create', {'kind': 'unit', 'name': 'Messages', 'project': DPR,
                               'content': 'unit Messages;\r\n\r\ninterface\r\n\r\nconst\r\n  PROPIA = 1;\r\n\r\n'
                                          'implementation\r\n\r\nend.\r\n'})
    check('preparacion: la unidad Messages del proyecto', not mc.fallo(r), r[:300])
    r = call('delphi_create', {'kind': 'unit', 'name': 'UUsa', 'project': DPR,
                               'content': 'unit UUsa;\r\n\r\ninterface\r\n\r\nuses\r\n  Winapi.Messages;\r\n\r\n'
                                          'const\r\n  DOS = WM_USER;\r\n\r\nimplementation\r\n\r\nend.\r\n'})
    USA = os.path.join(PROY, 'UUsa.pas')
    r = call('delphi_edit', {'path': USA, 'adduses': 'Messages', 'section': 'interface'})
    check('U3 adduses Messages con Winapi.Messages y SU unidad Messages en el proyecto: entra (otra unidad)',
          mc.abre(r, 'SN_ADDUSES_ADDED_FMT') and re.search(rb'Winapi\.Messages,\s*Messages;', bytes_de(USA)),
          r[:300])

    r = call('delphi_create', {'kind': 'unit', 'name': 'UVacia', 'project': DPR})
    VACIA = os.path.join(PROY, 'UVacia.pas')
    r = call('delphi_edit', {'path': VACIA, 'adduses': 'Vcl.Forms;Forms', 'section': 'implementation'})
    v = bytes_de(VACIA)
    check('U4 adduses Vcl.Forms;Forms en una unidad sin ellas: entra UNA (las dos son la misma)',
          mc.abre(r, 'SN_ADDUSES_ADDED_FMT') and v.count(b'Forms') == 1, (r[:300], v[-200:]))
    r = call('delphi_edit', {'path': VACIA, 'removeuses': 'Forms', 'section': 'implementation'})
    check('U5 removeuses Forms quita la que hay (Vcl.Forms, la misma unidad)',
          mc.abre(r, 'SN_REMOVEUSES_REMOVED_FMT') and b'Forms' not in bytes_de(VACIA), r[:300])

    r = call('delphi_build', {'project': DPR, 'platform': 'Win32', 'config': 'Debug'}, t=240)
    check('U6 el proyecto compila despues de todo (sin E2004)', '"success":true' in r.replace(' ', ''), r[:600])
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('uses con los ambitos del proyecto 1.23.1 (V79)')
