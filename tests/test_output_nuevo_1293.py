# -*- coding: utf-8 -*-
"""D18 de la 1.29.3 (caso de campo, 17-nov): delphi_paserver output devuelve todo lo que el programa escribio desde
el arranque, sin nada que marque lo nuevo. Un agente leyo a las 20:23 una salida que a las 20:08 tenia 9 lineas y ya
traia, mezclado con todo, lo que su app escribio tras uno de sus tres toques: no supo a cual correspondia. Ahora el
servidor recuerda, por workspace y por trabajo y en memoria, hasta donde le enseno la salida (remote-run cuenta como
primera lectura), y output anade, en campos APARTE, lo nuevo desde entonces: lastReadAt, newSinceLastRead, newLines
y su nota (RUN-034), o que no hay nada nuevo (RUN-035). "output" sigue igual.

Sin PAServer: el banco de test_remoterun_out_1291 (paclient_stub.py arranca el lanzador de verdad; el "programa" es
python con un guion que escribe en tandas segun aparecen dos ficheros de control).

  N0 control: remote-run de un trabajo que sigue vivo: su primera lectura, sin lastReadAt
  N1 output enseguida: nada nuevo (newLines 0, RUN-035) y lastReadAt (ROJO contra produccion: nada)
  N2 escribe dos lineas mas: newSinceLastRead trae SOLO esas dos y newLines 2; output sigue trayendo todo
  N3 output otra vez: nada nuevo
  N4 acaba escribiendo una mas: el output del trabajo acabado trae esa como lo nuevo
  N5 control: el remote-run de OTRO trabajo es su primera lectura: sin lastReadAt

Uso:  python tests/test_output_nuevo_1293.py [ruta-a-DelphiLspMcp.exe]
"""
import os, shutil, sys, time
import mcp_cliente as mc
from mcp_cliente import check

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
BASE = mc.carpeta('output_nuevo_1293')
SERVERDIR = os.path.join(BASE, 'server')
os.makedirs(os.path.join(SERVERDIR, 'node'))
EXE = mc.copia_exe(SERVERDIR)
for f in ('McpRunJob', 'McpRunJob.exe'):
    shutil.copy(os.path.join(REPO, 'node', f), os.path.join(SERVERDIR, 'node', f))
RUNJOB_EXE = os.path.join(SERVERDIR, 'node', 'McpRunJob.exe')
SCRATCH = os.path.join(BASE, 'scratch')
os.makedirs(SCRATCH)
ESPERA = os.path.join(SCRATCH, '_espera')
PROFILE = 'perfil'
PROJNAME = 'Tandas'
DEPLOY = os.path.join(SCRATCH, PROJNAME)
os.makedirs(DEPLOY)
shutil.copy(sys.executable, os.path.join(DEPLOY, PROJNAME + '.exe'))
PRJDIR = os.path.join(BASE, 'proj')
os.makedirs(PRJDIR)
DPROJ = os.path.join(PRJDIR, PROJNAME + '.dproj')
open(DPROJ, 'w', encoding='utf-8').write('<Project/>')
SEGUNDA = os.path.join(DEPLOY, 'segunda.txt')
FIN = os.path.join(DEPLOY, 'fin.txt')
open(os.path.join(DEPLOY, 'tandas.py'), 'w', encoding='utf-8').write(
    'import os, time\nprint("uno", flush=True)\n'
    'while not os.path.exists(%r):\n    time.sleep(0.2)\n'
    'print("dos", flush=True)\nprint("tres", flush=True)\n'
    'while not os.path.exists(%r):\n    time.sleep(0.2)\n'
    'print("cuatro", flush=True)\n' % (SEGUNDA, FIN))
open(os.path.join(DEPLOY, 'pocas.py'), 'w', encoding='utf-8').write('print("una")\n')
# revisor del paisaje de la 1.29.3: con mas de una cola (256 KB) de salida, lo nuevo se media en caracteres de un
# texto que es '...' + la cola, y la cola se desliza: dos lineas nuevas salian como "nada nuevo"
G2, G3, G4 = (os.path.join(DEPLOY, n) for n in ('grande2.txt', 'grande3.txt', 'grande4.txt'))
open(os.path.join(DEPLOY, 'grande.py'), 'w', encoding='utf-8').write(
    'import os, time\n'
    'for i in range(3000):\n    print("linea-%%04d " %% i + "x" * 90)\n'
    'print("fin-de-la-primera", flush=True)\n'
    'while not os.path.exists(%r):\n    time.sleep(0.2)\n'
    'print("nueva-1", flush=True)\nprint("nueva-2", flush=True)\n'
    'while not os.path.exists(%r):\n    time.sleep(0.2)\n'
    'for i in range(3000):\n    print("mas-%%04d " %% i + "y" * 90)\n'
    'print("tras-cola", flush=True)\n'
    'while not os.path.exists(%r):\n    time.sleep(0.2)\n' % (G2, G3, G4))
STUB = mc.paclient_falso('output_nuevo_1293')  # fuera de la jaula (1.27)

env = mc.entorno()
env['DELPHI_MCP_ROOTS'] = BASE
env['DELPHI_MCP_PACLIENT'] = STUB
env['MCP_STUB_SCRATCH'] = SCRATCH
env['MCP_STUB_RUNJOB_EXE'] = RUNJOB_EXE
env['DELPHI_MCP_ALLOW_REMOTE_RUN'] = '1'
env['DELPHI_MCP_REMOTE_RUN_PROJECTS'] = DPROJ
_ad, _host = mc.appdata_perfil(BASE, PROFILE, '127.0.0.1')
env['APPDATA'] = _ad
env['DELPHI_MCP_REMOTE_HOSTS'] = _host


def lineas(texto):
    return [l for l in (texto or '').splitlines() if l.strip()]


srv = mc.Stdio(EXE, env, nombre='output-nuevo', t=300)
try:
    open(ESPERA, 'w').write('1')
    j = mc.como_json(srv.call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ,
                                                  'exe': PROJNAME + '.exe', 'args': 'tandas.py',
                                                  'timeoutms': 2000}, t=300)) or {}
    os.remove(ESPERA)
    job = j.get('jobId') or ''
    check('N0 control: remote-run de un trabajo vivo es su primera lectura, sin lastReadAt',
          j.get('stillRunning') is True and job and 'lastReadAt' not in j and 'uno' in lineas(j.get('output')), j)

    def salida():
        return mc.como_json(srv.call('delphi_paserver', {'command': 'output', 'name': PROFILE, 'project': DPROJ,
                                                         'job': job}, t=120)) or {}

    j = salida()
    check('N1 output enseguida: nada nuevo (newLines 0, RUN-035) y lastReadAt (ROJO: nada)',
          j.get('stillRunning') is True and 'lastReadAt' in j and j.get('newLines') == 0
          and 'newSinceLastRead' not in j and mc.abre(j.get('newSinceLastReadNote', ''), 'SN_REMOTERUN_NADA_NUEVO_FMT'),
          j)
    open(SEGUNDA, 'w').write('1')
    time.sleep(3)
    j = salida()
    check('N2 escribe dos lineas mas: newSinceLastRead trae SOLO esas, newLines 2, y output sigue trayendo todo',
          lineas(j.get('newSinceLastRead')) == ['dos', 'tres'] and j.get('newLines') == 2
          and mc.abre(j.get('newSinceLastReadNote', ''), 'SN_REMOTERUN_LO_NUEVO_FMT')
          and lineas(j.get('output')) == ['uno', 'dos', 'tres'], j)
    j = salida()
    check('N3 output otra vez: nada nuevo', j.get('newLines') == 0 and 'newSinceLastRead' not in j, j)
    open(FIN, 'w').write('1')
    time.sleep(3)
    j = salida()
    check('N4 acaba con una linea mas: el output del trabajo acabado la trae como lo nuevo',
          j.get('stillRunning') is False and lineas(j.get('newSinceLastRead')) == ['cuatro']
          and j.get('newLines') == 1, j)
    j = mc.como_json(srv.call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ,
                                                  'exe': PROJNAME + '.exe', 'args': 'pocas.py',
                                                  'timeoutms': 60000}, t=300)) or {}
    check('N5 control: el remote-run de OTRO trabajo es su primera lectura, sin lastReadAt',
          j.get('stillRunning') is False and 'lastReadAt' not in j and 'newSinceLastRead' not in j, j)

    # ---- con mas de una cola de salida (revisor del paisaje de la 1.29.3) ----
    open(ESPERA, 'w').write('1')
    j = mc.como_json(srv.call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ,
                                                  'exe': PROJNAME + '.exe', 'args': 'grande.py',
                                                  'timeoutms': 6000}, t=300)) or {}
    os.remove(ESPERA)
    job = j.get('jobId') or ''
    check('G0 control: un trabajo con mas de 256 KB de salida, vivo, y su salida va recortada',
          j.get('stillRunning') is True and job and j.get('outputTruncated') is True
          and 'fin-de-la-primera' in lineas(j.get('output')), {k: v for k, v in j.items() if k != 'output'})
    open(G2, 'w').write('1')
    time.sleep(3)
    j = salida()
    check('G1 dos lineas nuevas tras mas de una cola: lo nuevo son ESAS dos (ROJO sin el arreglo: "nada nuevo")',
          lineas(j.get('newSinceLastRead')) == ['nueva-1', 'nueva-2'] and j.get('newLines') == 2
          and 'newSinceLastReadTruncated' not in j, {k: v for k, v in j.items() if k != 'output'})
    open(G3, 'w').write('1')
    time.sleep(4)
    j = salida()
    nuevas = lineas(j.get('newSinceLastRead'))
    check('G2 mas de una cola entre dos lecturas: lo nuevo acaba en lo ultimo y se dice cortado (ROJO sin el '
          'arreglo)', nuevas[-1:] == ['tras-cola'] and j.get('newSinceLastReadTruncated') is True
          and 'nueva-2' not in nuevas, {k: v for k, v in j.items() if k != 'output'})
    open(G4, 'w').write('1')
    time.sleep(3)
    salida()  # acaba y se lee entero: su salida se borra del destino
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('output dice lo nuevo desde la ultima lectura 1.29.3 (D18)')
