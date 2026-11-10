# -*- coding: utf-8 -*-
"""RUN-023 de Hermes (9-nov, 1.29.1): la salida de remote-run en la respuesta es su COLA (las ultimas 400
lineas, V80), y la de un programa que escribe su veredicto en la CABEZA (el -mapa de su arnes, ~412 lineas)
se perdia sin vuelta atras: la salida leida se borra del destino. Ahora remote-run y output toman out=, un
.txt/.log de la jaula donde va ENTERO lo que escribio el programa, con sus bytes y sin las dos lineas del
lanzador (___ENV y ___RC): RUN-028, y la respuesta lo nombra en vez de traer la cola.

Sin PAServer: el banco de test_cola_salida_1231 (paclient_stub.py arranca el lanzador de verdad sobre una
carpeta local que hace de destino).

  O1  remote-run de 5000 lineas con out=: el fichero las trae TODAS, la primera tambien (ROJO contra la
      1.29.1 sin out=: "out" no va con remote-run); lines y size, RUN-028, y sin la cola en la respuesta
  O2  ...sin las lineas del lanzador, y con los bytes del programa (sus CRLF)
  O3  un programa que sigue al acabar el plazo: no se escribe nada aun, RUN-030; output con out= mientras
      sigue escribe lo que lleva (RUN-029) y, al acabar, todo (RUN-028); y la salida ya no esta en el destino
  O4  out= que no acaba en .txt/.log: PAS-077 y no se lanza nada
  O5  out= fuera de la jaula: negado y nada escrito fuera
  O6  out= con kill: no va con el comando
  O7  control: sin out=, la cola de siempre (RUN-023, que ahora dice como quedarse con todo)
  O8  (Hermes, 10-nov) RUN-023 cuenta los bytes del PROGRAMA, los mismos que el size del fichero de O1
      (contaba el fichero del destino, con las dos lineas del lanzador: 12527 frente a 12508)

Uso:  python tests/test_remoterun_out_1291.py [ruta-a-DelphiLspMcp.exe]
"""
import os, shutil, sys, time
import mcp_cliente as mc
from mcp_cliente import check

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
BASE = mc.carpeta('remoterun_out_1291')
SERVERDIR = os.path.join(BASE, 'server'); os.makedirs(os.path.join(SERVERDIR, 'node'))
EXE = mc.copia_exe(SERVERDIR)
for f in ('McpRunJob', 'McpRunJob.exe'):
    shutil.copy(os.path.join(REPO, 'node', f), os.path.join(SERVERDIR, 'node', f))
RUNJOB_EXE = os.path.join(SERVERDIR, 'node', 'McpRunJob.exe')
SCRATCH = os.path.join(BASE, 'scratch'); os.makedirs(SCRATCH)
ESPERA = os.path.join(SCRATCH, '_espera')
PROFILE = 'perfil'
PROJNAME = 'Saluda'
DEPLOY = os.path.join(SCRATCH, PROJNAME)
os.makedirs(DEPLOY)
shutil.copy(sys.executable, os.path.join(DEPLOY, PROJNAME + '.exe'))
PRJDIR = os.path.join(BASE, 'proj'); os.makedirs(PRJDIR)
DPROJ = os.path.join(PRJDIR, PROJNAME + '.dproj')
open(DPROJ, 'w', encoding='utf-8').write('<Project/>')
STUB = mc.paclient_falso('remoterun_out_1291')  # fuera de la jaula (1.27)
SALIDAS = os.path.join(BASE, 'salidas'); os.makedirs(SALIDAS)
FUERA = os.path.join(os.path.dirname(BASE), 'remoterun_out_1291_fuera.txt')
if os.path.exists(FUERA):
    os.remove(FUERA)

GUIONES = {
    'muchas.py': 'for i in range(1, 5001):\n    print("linea %05d" % i)\n',
    'pocas.py': 'print("uno")\nprint("dos")\nprint("tres")\n',
    'tarde.py': 'import time\nprint("antes del plazo", flush=True)\ntime.sleep(6)\n'
                'for i in range(1, 5001):\n    print("tarde %05d" % i)\n',
}
for nombre, texto in GUIONES.items():
    open(os.path.join(DEPLOY, nombre), 'w', encoding='utf-8').write(texto)

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


def corre(srv, guion, out=None, timeoutms=60000):
    a = {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ, 'exe': PROJNAME + '.exe', 'args': guion,
         'timeoutms': timeoutms}
    if out is not None:
        a['out'] = out
    r = srv.call('delphi_paserver', a, t=300)
    return r, mc.como_json(r)


def salida(srv, job, out=None):
    a = {'command': 'output', 'name': PROFILE, 'project': DPROJ, 'job': job}
    if out is not None:
        a['out'] = out
    r = srv.call('delphi_paserver', a, t=120)
    return r, mc.como_json(r)


def sin_salida(j):
    return {k: v for k, v in j.items() if k != 'output'}


def lee(path):
    return open(path, 'rb').read() if os.path.isfile(path) else None


def bytes_de_la_nota(j):
    import re
    m = re.search(r'(\d+) bytes', j.get('outputTruncatedNote') or '')
    return int(m.group(1)) if m else -1


srv = mc.Stdio(EXE, env, nombre='out1291')
try:
    # O1 / O2
    f1 = os.path.join(SALIDAS, 'muchas.txt')
    r, j = corre(srv, 'muchas.py', f1)
    b = lee(f1)
    ls = b.decode('ascii').splitlines() if b is not None else []
    check('O1 remote-run con out=: el fichero trae las 5000 lineas, la PRIMERA tambien (ROJO: out no iba)',
          len(ls) == 5000 and ls[0] == 'linea 00001' and ls[-1] == 'linea 05000', (len(ls), r[:300]))
    check('O1 ...lines y size del fichero, RUN-028, y sin la cola en la respuesta',
          j.get('lines') == 5000 and j.get('size') == len(b or b'') and os.path.basename(str(j.get('logfile'))) ==
          'muchas.txt' and mc.es(j.get('logfileNote'), 'SN_REMOTERUN_LOGFILE') and 'output' not in j
          and j.get('exitCode') == 0, sin_salida(j))
    check('O2 ...sin las lineas del lanzador (___ENV, ___RC)', b is not None and b'___ENV' not in b and b'___RC' not in b,
          (b or b'')[:80])
    size1 = j.get('size')
    f2 = os.path.join(SALIDAS, 'pocas.log')
    r, j = corre(srv, 'pocas.py', f2)
    b2 = lee(f2)
    check('O2 ...con los bytes del programa, su salto final incluido', b2 in (b'uno\r\ndos\r\ntres\r\n', b'uno\ndos\ntres\n'),
          (b2, sin_salida(j)))

    # O3
    f3 = os.path.join(SALIDAS, 'tarde.txt')
    open(ESPERA, 'w').write('1')
    r, j = corre(srv, 'tarde.py', f3, timeoutms=2000)
    os.remove(ESPERA)
    job = j.get('jobId') or ''
    check('O3 un programa que sigue al acabar el plazo: nada escrito aun y RUN-030',
          j.get('stillRunning') is True and job and not os.path.exists(f3)
          and mc.es(j.get('logfileNote'), 'SN_REMOTERUN_OUT_PENDIENTE'), sin_salida(j))
    vivo, fin = None, None
    dl = time.time() + 90
    while time.time() < dl:
        time.sleep(1)
        r, jo = salida(srv, job, f3)
        if jo.get('stillRunning') is True and vivo is None:
            vivo = (jo, lee(f3))
        if jo.get('stillRunning') is False:
            fin = (jo, lee(f3))
            break
    check('O3 ...output con out= mientras sigue: lo que lleva escrito y RUN-029',
          vivo is not None and vivo[1] is not None and vivo[1].startswith(b'antes del plazo')
          and mc.es(vivo[0].get('logfileNote'), 'SN_REMOTERUN_LOGFILE_VIVO'),
          (sin_salida(vivo[0]) if vivo else None, (vivo[1] or b'')[:60] if vivo else None))
    lt = fin[1].decode('ascii').splitlines() if fin and fin[1] is not None else []
    check('O3 ...y al acabar, TODO (la cabeza y el final) con RUN-028',
          fin is not None and len(lt) == 5001 and lt[0] == 'antes del plazo' and lt[-1] == 'tarde 05000'
          and mc.es(fin[0].get('logfileNote'), 'SN_REMOTERUN_LOGFILE') and 'output' not in fin[0],
          (sin_salida(fin[0]) if fin else None, len(lt)))
    r, jd = salida(srv, job)
    check('O3 ...y la salida ya no esta en el destino (leida entera, se borra: RUN-018)',
          mc.es(r, 'SR_REMOTERUN_NO_OUTPUT_FMT'), r[:300])

    # O4
    r, j = corre(srv, 'pocas.py', os.path.join(SALIDAS, 'mal.csv'))
    check('O4 out= que no acaba en .txt/.log: PAS-077 y no se lanza nada',
          mc.es(r, 'SR_PASERVER_OUT_LOG') and 'jobId' not in j and not os.path.exists(os.path.join(SALIDAS, 'mal.csv')),
          r[:300])

    # O5
    r, j = corre(srv, 'pocas.py', FUERA)
    # la negativa de LA JAULA (GUARD-002), no un "parametro desconocido": contra el build sin out= pasaba
    check('O5 out= fuera de la jaula: la jaula lo niega, sin lanzar, y nada escrito fuera',
          mc.es(r, 'SR_JAIL_FMT') and 'jobId' not in j and not os.path.exists(FUERA), r[:300])

    # O6
    r = srv.call('delphi_paserver', {'command': 'kill', 'name': PROFILE, 'project': DPROJ, 'job': job,
                                     'out': os.path.join(SALIDAS, 'kill.txt')}, t=60)
    check('O6 out= con kill: no va con el comando', mc.es(r, 'SR_PASERVER_NO_VA_CON_COMANDO_FMT') and 'out' in r, r[:300])

    # O7
    r, j = corre(srv, 'muchas.py')
    lc = (j.get('output') or '').splitlines()
    check('O7 control: sin out=, la cola de siempre (RUN-023), que dice como quedarse con todo',
          0 < len(lc) <= 400 and mc.es(j.get('outputTruncatedNote'), 'SN_REMOTERUN_COLA_FMT')
          and 'out=' in (j.get('outputTruncatedNote') or '') and 'logfile' not in j, sin_salida(j))
    check('O8 RUN-023 cuenta los bytes del programa: los del fichero de O1 (ROJO: contaba las lineas del lanzador)',
          isinstance(size1, int) and bytes_de_la_nota(j) == size1, (bytes_de_la_nota(j), size1))
finally:
    srv.mata()
    if os.path.exists(FUERA):
        os.remove(FUERA)
    mc.borra(BASE)
mc.fin('el out= de remote-run y output (1.29.1, RUN-023 de Hermes)')
