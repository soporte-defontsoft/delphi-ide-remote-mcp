# -*- coding: utf-8 -*-
r"""Textos que llevaban al sitio equivocado o callaban el camino (1.23.1: V146 y la seccion K).

Cada uno se compara con SU texto del catalogo (Lsp.Texts), que contra el build anterior no esta.

  X1 V146 EDIT-019 (un rango que toma el fichero entero) dice tambien como REEMPLAZAR, no solo como
     borrar
  X2 V133 GIT-038 de command=branch con create/name dice como se crea una rama (switch create=true)
  X3 V138 la descripcion de delphi_completion dice que reubica la columna tras el punto (LSP-027)
  X4 V139 delphi_move copy=true de un fichero con extension a un dest sin ella: MOVE-025 (dest es la
     ruta final; si querias una carpeta, ...)
  X5 V140 una unidad virtual que no se sirve (srvq:) con la misma cola bajo una que si: CFG-006 y
     READ-011 con la buena
  X6 V182 el parametro character de delphi_signature dice lo que su descripcion: DENTRO de los
     parentesis de la llamada (ROJA contra b48699c: el generico de posicion, "inside the identifier",
     y ahi el motor no contesta)
(V132a, el alcance de RENAME-021, en test_rename.)

Uso:  python tests/test_textos_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import subprocess
import sys
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('textos-1231')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=sys.argv[1] if len(sys.argv) > 1 else None)
CAT = mc.catalogo()
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='textos-1231', t=120)
try:
    pas = os.path.join(JAIL, 'UTres.pas')
    with open(pas, 'w', newline='') as f:
        f.write('unit UTres;\r\ninterface\r\nimplementation\r\nend.\r\n')
    r = srv.call('delphi_edit', {'path': pas, 'old': 'unit UTres;', 'toline': 4, 'new': 'unit UOtra;'})
    check('X1 EDIT-019 dice tambien como reemplazar (V146)',
          mc.es(r, 'SR_RANGE_WHOLE_FMT') and (CAT['SR_RANGE_WHOLE_FMT'] % 4) in r, r[:500])

    repo = os.path.join(JAIL, 'repo')
    os.makedirs(repo)
    subprocess.run(['git', 'init', '-q', repo], check=True)
    r = srv.call('delphi_git', {'command': 'branch', 'repo': repo, 'create': True, 'name': 'prueba1'})
    check('X2 GIT-038 de branch con create/name dice como se crea una rama (V133)',
          mc.es(r, 'SR_GIT_NO_VA_CON_COMANDO_FMT') and CAT['SF_GIT_RAMA_NUEVA'].strip() in r, r[:500])
    r = srv.call('delphi_git', {'command': 'log', 'repo': repo, 'name': 'x'})
    check('X2 ...y no en otro comando', mc.es(r, 'SR_GIT_NO_VA_CON_COMANDO_FMT') and
          CAT['SF_GIT_RAMA_NUEVA'].strip() not in r, r[:300])

    m = srv.request('tools/list', {}, 30)
    desc = next((t.get('description', '') for t in m['result']['tools'] if t['name'] == 'delphi_completion'), '')
    check('X3 la descripcion de delphi_completion es la del catalogo, con la columna reubicada (V138)',
          CAT['SD_LSP_COMPLETION'] in desc and mc.id_de('SN_COMPLETION_SNAPPED_FMT') in desc, desc)
    sig = next((t for t in m['result']['tools'] if t['name'] == 'delphi_signature'), {})
    car = ((sig.get('inputSchema') or {}).get('properties') or {}).get('character', {}).get('description', '')
    check('X6 el character de delphi_signature es el suyo: DENTRO de los parentesis, como su descripcion (V182)',
          car == CAT['SP_LSP_SIGNATURE_CHARACTER'] and 'parentheses' in sig.get('description', ''), car)

    fmx = os.path.join(JAIL, 'UMain.fmx')
    with open(fmx, 'w', newline='') as f:
        f.write('object F: TForm\r\nend\r\n')
    r = srv.call('delphi_move', {'path': fmx, 'dest': os.path.join(JAIL, 'copias'), 'copy': True})
    check('X4 un fichero con extension a un dest sin ella: MOVE-025 (V139)',
          mc.es(r, 'SN_MOVE_DESTINO_SIN_EXTENSION_FMT') and 'UMain.fmx' in r, r[:400])
    r = srv.call('delphi_move', {'path': fmx, 'dest': os.path.join(JAIL, 'otra.fmx'), 'copy': True})
    check('X4 ...y no con un dest con extension', not mc.es(r, 'SN_MOVE_DESTINO_SIN_EXTENSION_FMT'), r[:300])

    # la misma cola bajo una unidad que no se sirve (q no es la del sandbox de las baterias)
    letra = os.path.splitdrive(JAIL)[0][0].lower()
    assert letra != 'q', letra
    falsa = 'srvq:' + pas[2:]
    r = srv.call('delphi_read', {'path': falsa})
    check('X5 una unidad que no se sirve: CFG-006 y READ-011 con la misma ruta bajo la buena (V140)',
          mc.es(r, 'SR_UNIT_UNKNOWN_FMT') and mc.es(r, 'SN_READ_OTRA_UNIDAD_FMT') and
          ('srv%s:' % letra) in r, r[:500])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('textos 1.23.1 (V146, V133, V138, V139, V140, V182)')
