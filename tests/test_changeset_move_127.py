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
  M3 ...y otra vez al aplicarlo: un destino de la jaula que entre el preview y el commit pasa a ser un
     junction a la otra unidad, negado en el commit (sin la regla del commit, el fichero se iba)

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
# La OTRA unidad, el sandbox de pruebas en vivo de la casa. Sin el, o en el mismo volumen que la jaula, no hay
# nada que medir y se DICE (sin_checks): era un assert y una ruta que se daba por supuesta; y el makedirs y
# el servidor iban antes del try, sin el finally que quita OTRA (revisor de baterias de la 1.27)
# dentro de test-mcp-server: la carpeta de las pruebas, que se vacia entera al limpiar (David, 9-nov-2026)
SANDBOX = r'D:\SandBox-lsp\testsserver\test-mcp-server'
OTRA = os.path.join(SANDBOX, 'changeset-move-127-%d' % os.getpid())
SIN = None
if not os.path.isdir(SANDBOX):
    SIN = 'no hay sandbox de pruebas en vivo (%s) en esta maquina' % SANDBOX
elif os.path.splitdrive(OTRA)[0].upper() == os.path.splitdrive(mc.larga(JAIL))[0].upper():
    SIN = 'la jaula (%s) y el sandbox estan en la misma unidad: no hay dos volumenes' % JAIL
A = os.path.join(JAIL, 'a.txt')
C = os.path.join(JAIL, 'c.txt')
PUENTE = os.path.join(JAIL, 'puente')
srv = None
if not SIN:
    try:
        os.makedirs(OTRA)
        open(A, 'w').write('a\n')
        open(C, 'w').write('c\n')
        srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL + ';' + OTRA}), nombre='changeset-move-127', t=120)
        r = srv.call('delphi_move', {'path': A, 'dest': os.path.join(OTRA, 'b.txt')})
        check('M1 control: delphi_move a otra unidad, negado por la regla de la mudanza',
              mc.es(r, 'SR_MUDANZA_OTRA_UNIDAD_FMT') and os.path.isfile(A), r[:300])

        r = srv.call('delphi_changeset', {'command': 'begin'})
        cid = mc.id_changeset(r)
        check('M2 fixture: un changeset abierto', bool(cid), r[:200])
        r = srv.call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'move', 'path': A,
                                          'dest': os.path.join(OTRA, 'b.txt')})
        # AL APILAR, como dice el docstring: con el commit detras de respaldo, quitar la regla del stage
        # (Lsp.Changeset, la del apilado) seguia verde porque la del commit la paraba; M3 mide esa otra
        # (revisor de baterias de la 1.27)
        check('M2 el move de un changeset a otra unidad: negado por la misma regla al apilarlo, y a.txt donde estaba',
              mc.es(r, 'SR_MUDANZA_OTRA_UNIDAD_FMT') and os.path.isfile(A) and
              not os.path.exists(os.path.join(OTRA, 'b.txt')), r[:400])

        # M3: la regla OTRA VEZ al aplicar. El destino es una carpeta de la jaula al apilar y al ensayar, y
        # entre el preview y el commit pasa a ser un junction a la otra unidad (entre stage y commit pueden
        # pasar 30 minutos): la regla del apilado ya hablo y solo la del commit lo ve
        os.makedirs(PUENTE)
        r = srv.call('delphi_changeset', {'command': 'begin'})
        cid3 = mc.id_changeset(r)
        r = srv.call('delphi_changeset', {'command': 'stage', 'id': cid3, 'kind': 'move', 'path': C,
                                          'dest': os.path.join(PUENTE, 'c.txt')})
        rp = srv.call('delphi_changeset', {'command': 'preview', 'id': cid3})
        check('M3 fixture: apilado y ensayado con el destino DENTRO de la jaula',
              bool(cid3) and not mc.fallo(r) and not mc.fallo(rp), (r[:200], rp[:200]))
        os.rmdir(PUENTE)
        puente = mc.junction(PUENTE, OTRA)
        r = srv.call('delphi_changeset', {'command': 'commit', 'id': cid3})
        check('M3 el commit vuelve a juzgar el move: su destino ya es otra unidad (un junction), negado y c.txt '
              'donde estaba',
              puente and mc.es(r, 'SR_MUDANZA_OTRA_UNIDAD_FMT') and os.path.isfile(C) and
              not os.path.exists(os.path.join(OTRA, 'c.txt')), r[:400])
    finally:
        if srv:
            srv.cierra()
        mc.borra(PUENTE)   # el enlace como enlace, nunca lo de detras
        shutil.rmtree(OTRA, ignore_errors=True)

mc.borra(BASE)
mc.fin('el move de un changeset por la regla del move 1.27', sin_checks=SIN)
