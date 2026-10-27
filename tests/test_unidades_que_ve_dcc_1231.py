# -*- coding: utf-8 -*-
"""Que unidad es un nombre en un uses: la que dcc ENCUENTRA, tambien sin que
nadie la liste (V107, 1.23.1). El juez de V79 (TResolutorDeUnidades) solo
contaba como del proyecto las que su .dpr lista con in, y dcc encuentra
ademas por su nombre lo que hay en la carpeta del proyecto y en su search
path. Medido con dcc el 27-oct (MideV107): un Graphics.pas sin listar al lado
del .dpr es Graphics, no Vcl.Graphics - "uses Vcl.Graphics ... uses Graphics"
compila -, y lo mismo en una carpeta del search path o con un Graphics.dcu en
la carpeta del proyecto; en una subcarpeta que no esta en el search path dcc
no lo ve (E2004: es Vcl.Graphics). Contra el build anterior: adduses decia
USES-009, removeuses=Graphics quitaba Vcl.Graphics, remove-unit de un
Graphics.pas que no listaba nadie quitaba Vcl.Graphics del .dpr, y removeuses
en el .dpr mandaba a remove-unit una unidad de la biblioteca (USES-025).

  A1 al lado del .dpr: adduses Graphics con Vcl.Graphics en el interface entra
  A2 dcc compila "uses Vcl.Graphics ... uses Graphics" (dos unidades)
  A3 removeuses Graphics del interface: no esta, y Vcl.Graphics se queda
  A4 removeuses Graphics del implementation: quita esa, Vcl.Graphics se queda
  B1 en una subcarpeta fuera del search path: adduses Graphics = Vcl.Graphics, nada escrito
  B2 dcc lo confirma: a mano, E2004 Identifier redeclared
  B3 removeuses Graphics en el .dpr con Vcl.Graphics: la quita (no USES-025)
  B4 remove-unit de Sub\\Graphics.pas, que nadie lista: no esta, Vcl.Graphics se queda
  D1 un Graphics.dcu en la carpeta del proyecto: adduses Graphics entra
  C1 con la subcarpeta en el search path: adduses Graphics entra
  C2 dcc compila

Uso:  python tests/test_unidades_que_ve_dcc_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import shutil
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('unidades_que_ve_dcc_1231')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='unidades-dcc', t=300)

GRAPHICS = ('unit Graphics;\r\n\r\ninterface\r\n\r\nconst\r\n  MarcaV107 = 107;\r\n\r\n'
            'implementation\r\n\r\nend.\r\n')


def bytes_de(p):
    return open(p, 'rb').read()


def compila(r):
    return '"success":true' in r.replace(' ', '')


try:
    call = srv.call
    PROY = os.path.join(JAIL, 'Ven')
    r = call('delphi_create', {'kind': 'project-vcl', 'name': 'Ven', 'dir': PROY}, t=120)
    check('preparacion: un proyecto VCL nuevo', not mc.fallo(r), r[:300])
    DPR = os.path.join(PROY, 'Ven.dpr')
    DPROJ = os.path.join(PROY, 'Ven.dproj')
    # la unidad del form principal: la que lleva Vcl.Graphics en su interface
    MAIN = ''
    for n in os.listdir(PROY):
        if n.lower().endswith('.pas') and b'Vcl.Graphics' in bytes_de(os.path.join(PROY, n)):
            MAIN = os.path.join(PROY, n)
    check('preparacion: la unidad principal usa Vcl.Graphics', MAIN != '', os.listdir(PROY))
    # cada caso parte del fuente original: lo que un caso rojo deja escrito no
    # hace pasar ni caer al siguiente (con un mutante, A3 quitaba Vcl.Graphics
    # y C1 entraba igual)
    ORIGINAL = bytes_de(MAIN)

    def original():
        with open(MAIN, 'wb') as f:
            f.write(ORIGINAL)

    def a_mano():
        # el uses del implementation escrito a mano: lo que se le pregunta a dcc
        with open(MAIN, 'wb') as f:
            f.write(ORIGINAL.replace(b'implementation\r\n', b'implementation\r\n\r\nuses\r\n  Graphics;\r\n', 1))

    r = call('delphi_create', {'kind': 'unit', 'name': 'Graphics', 'dir': PROY, 'content': GRAPHICS})
    check('preparacion: un Graphics.pas suelto al lado del .dpr, que no lista nadie',
          not mc.fallo(r) and b'Graphics' not in bytes_de(DPR), r[:300])

    r = call('delphi_edit', {'path': MAIN, 'adduses': 'Graphics', 'section': 'implementation'})
    m = bytes_de(MAIN)
    check('A1 al lado del .dpr: adduses Graphics con Vcl.Graphics en el interface ENTRA (era USES-009)',
          mc.abre(r, 'SN_ADDUSES_ADDED_FMT') and re.search(rb'implementation\s+uses\s+Graphics;', m), r[:300])
    a_mano()
    r = call('delphi_build', {'project': DPROJ, 'platform': 'Win32', 'config': 'Debug'}, t=240)
    check('A2 dcc compila "uses Vcl.Graphics ... uses Graphics": son dos unidades', compila(r), r[:600])
    # su Graphics.dcu, guardado para D1: el Build de B2 empieza con un Clean
    DCU = os.path.join(BASE, 'Graphics.dcu')
    for d, _, fs in os.walk(PROY):
        for n in fs:
            if n.lower() == 'graphics.dcu':
                shutil.copy(os.path.join(d, n), DCU)
    check('preparacion: el Graphics.dcu del build de A2', os.path.isfile(DCU), PROY)
    antes = bytes_de(MAIN)
    r = call('delphi_edit', {'path': MAIN, 'removeuses': 'Graphics', 'section': 'interface'})
    check('A3 removeuses Graphics del interface: no esta, y Vcl.Graphics se queda (quitaba Vcl.Graphics)',
          mc.abre(r, 'SN_REMOVEUSES_ABSENT_FMT') and bytes_de(MAIN) == antes, r[:300])
    a_mano()
    r = call('delphi_edit', {'path': MAIN, 'removeuses': 'Graphics', 'section': 'implementation'})
    m = bytes_de(MAIN)
    check('A4 removeuses Graphics del implementation: quita esa, Vcl.Graphics se queda',
          mc.abre(r, 'SN_REMOVEUSES_REMOVED_FMT') and b'Vcl.Graphics' in m
          and not re.search(rb'implementation\s+uses', m), r[:300])

    # el contraejemplo: en una subcarpeta que no esta en el search path dcc no lo ve
    SUB = os.path.join(PROY, 'Sub')
    r = call('delphi_move', {'path': os.path.join(PROY, 'Graphics.pas'), 'dest': os.path.join(SUB, 'Graphics.pas')})
    check('preparacion: Graphics.pas a Sub, fuera del search path', not mc.fallo(r), r[:300])
    original()
    r = call('delphi_edit', {'path': MAIN, 'adduses': 'Graphics', 'section': 'implementation'})
    check('B1 en una subcarpeta fuera del search path: adduses Graphics es Vcl.Graphics, nada escrito',
          mc.abre(r, 'SN_ADDUSES_PRESENT_OTHER_FMT') and bytes_de(MAIN) == ORIGINAL, r[:300])
    # el juez: escrito a mano, dcc dice que es la misma
    a_mano()
    r = call('delphi_build', {'project': DPROJ, 'platform': 'Win32', 'config': 'Debug'}, t=240)
    check('B2 dcc lo confirma: a mano, E2004 Identifier redeclared', not compila(r) and 'E2004' in r, r[:600])
    original()

    r = call('delphi_edit', {'path': DPR, 'adduses': 'Vcl.Graphics'})
    check('preparacion: Vcl.Graphics en el uses del .dpr', mc.abre(r, 'SN_ADDUSES_ADDED_FMT'), r[:300])
    r = call('delphi_edit', {'path': DPR, 'removeuses': 'Graphics'})
    check('B3 removeuses Graphics en el .dpr con Vcl.Graphics: la quita (mandaba a remove-unit, USES-025)',
          mc.abre(r, 'SN_REMOVEUSES_REMOVED_FMT') and b'Graphics' not in bytes_de(DPR), r[:300])
    r = call('delphi_edit', {'path': DPR, 'adduses': 'Vcl.Graphics'})
    r = call('delphi_config', {'project': DPROJ, 'command': 'remove-unit', 'path': os.path.join(SUB, 'Graphics.pas')})
    check('B4 remove-unit de Sub\\Graphics.pas, que nadie lista: no esta, y Vcl.Graphics se queda (la quitaba)',
          mc.abre(r, 'SN_UNIT_ABSENT_FMT') and b'Vcl.Graphics' in bytes_de(DPR), r[:300])
    r = call('delphi_edit', {'path': DPR, 'removeuses': 'Vcl.Graphics'})
    check('preparacion: el .dpr sin Vcl.Graphics otra vez', b'Graphics' not in bytes_de(DPR), r[:300])

    # un .dcu en la carpeta del proyecto tambien es una unidad que dcc encuentra
    if os.path.isfile(DCU):
        shutil.copy(DCU, os.path.join(PROY, 'Graphics.dcu'))
    r = call('delphi_edit', {'path': MAIN, 'adduses': 'Graphics', 'section': 'implementation'})
    check('D1 un Graphics.dcu en la carpeta del proyecto: adduses Graphics entra',
          mc.abre(r, 'SN_ADDUSES_ADDED_FMT') and b'Vcl.Graphics' in bytes_de(MAIN), r[:300])
    if os.path.isfile(os.path.join(PROY, 'Graphics.dcu')):
        os.remove(os.path.join(PROY, 'Graphics.dcu'))
    original()

    r = call('delphi_config', {'project': DPROJ, 'command': 'add-searchpath', 'path': 'Sub'})
    check('preparacion: Sub en el search path', not mc.fallo(r), r[:300])
    r = call('delphi_edit', {'path': MAIN, 'adduses': 'Graphics', 'section': 'implementation'})
    check('C1 con Sub en el search path: adduses Graphics entra (era USES-009)',
          mc.abre(r, 'SN_ADDUSES_ADDED_FMT') and b'Vcl.Graphics' in bytes_de(MAIN), r[:300])
    a_mano()
    r = call('delphi_build', {'project': DPROJ, 'platform': 'Win32', 'config': 'Debug'}, t=240)
    check('C2 dcc compila: el Graphics del search path es otra unidad', compila(r), r[:600])
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('las unidades que ve dcc 1.23.1 (V107)')
