# -*- coding: utf-8 -*-
r"""El move de delphi_changeset por LA regla del move (revisor del paisaje de la 1.27).

delphi_move juzga un move con MovidoDenegado (Lsp.Guard): la escritura de los dos lados, los lugares
protegidos y que origen y destino esten en la misma unidad REAL, porque entre volumenes Windows "mueve"
copiando y borrando (y una copia lee lo que haya detras, un enlace duro incluido). El move de un changeset
solo preguntaba la escritura del destino y movia con TFile.Move: un segundo emisor de la regla.

Dos raices en dos VOLUMENES: la jaula (en %TEMP%, C:) y una carpeta unica del sandbox de pruebas en vivo
(D:), creada y quitada por esta bateria. (Una letra de subst no sirve: es el mismo volumen, y la regla
compara la unidad REAL, con razon: alli Windows renombra.)

  M1 (control) delphi_move a la otra unidad: negado (la regla de la mudanza)
  M2 el move de un changeset a la otra unidad: negado igual, al apilarlo, y el fichero sigue donde estaba

Uso:  python tests/test_changeset_move_127.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import shutil
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('changeset-move-127')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
OTRA = r'D:\SandBox-lsp\testsserver\changeset-move-127-%d' % os.getpid()
assert os.path.splitdrive(OTRA)[0].upper() != os.path.splitdrive(mc.larga(JAIL))[0].upper(), 'dos volumenes'
os.makedirs(OTRA)
A = os.path.join(JAIL, 'a.txt')
open(A, 'w').write('a\n')
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL + ';' + OTRA}), nombre='changeset-move-127', t=120)
try:
    r = srv.call('delphi_move', {'path': A, 'dest': os.path.join(OTRA, 'b.txt')})
    check('M1 control: delphi_move a otra unidad, negado por la regla de la mudanza',
          mc.es(r, 'SR_MUDANZA_OTRA_UNIDAD_FMT') and os.path.isfile(A), r[:300])

    r = srv.call('delphi_changeset', {'command': 'begin'})
    cid = mc.id_changeset(r)
    check('M2 fixture: un changeset abierto', bool(cid), r[:200])
    r = srv.call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'move', 'path': A,
                                      'dest': os.path.join(OTRA, 'b.txt')})
    if not mc.rechazado(r):
        srv.call('delphi_changeset', {'command': 'preview', 'id': cid})
        r = srv.call('delphi_changeset', {'command': 'commit', 'id': cid})
    check('M2 el move de un changeset a otra unidad: negado por la misma regla, y a.txt donde estaba',
          mc.es(r, 'SR_MUDANZA_OTRA_UNIDAD_FMT') and os.path.isfile(A) and not os.path.exists(os.path.join(OTRA, 'b.txt')),
          r[:400])
finally:
    srv.cierra()
    shutil.rmtree(OTRA, ignore_errors=True)

mc.borra(BASE)
mc.fin('el move de un changeset por la regla del move 1.27')
