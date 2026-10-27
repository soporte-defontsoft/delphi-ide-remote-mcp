# -*- coding: utf-8 -*-
"""V80 de la 1.23.1: la salida de remote-run lleva EL recorte de la casa.

remote-run devolvia ENTERA la salida del programa remoto, y la leia entera del
fichero traido del destino (Lsp.RemoteRun.TraeSalida): un programa que escribe
megas inundaba el contexto del agente y la memoria del servidor. El tope por el
contexto estaba escrito a mano tres veces (build, delphi_test, el logcat de
adb) y aqui no. Ahora va su cola (Lsp.Listas.ColaDeSalida: las ultimas lineas y
como mucho unos caracteres), con outputTruncated y RUN-023, y del fichero se
lee su primera linea (la del entorno) y su final, no entero.

Sin PAServer: el banco de test_remoterun (paclient_stub.py arranca el lanzador
de verdad sobre una carpeta local que hace de destino).

  C1  5000 lineas: van las ultimas (400 como mucho), la ultima si y la primera
      no; outputTruncated y RUN-023 con el tamano de la salida
  C2  una linea sola de 2 MB: va su final, acotado en caracteres
  C3  64 MB de salida: el servidor no la lee entera (su pico de memoria privada
      no sube lo que pesa) y la respuesta trae el final y el codigo de salida
  C4  control: 3 lineas van enteras, sin outputTruncated ni RUN-023
  C5  output de un trabajo que acabo despues de su remote-run: el mismo recorte

Uso:  python tests/test_cola_salida_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import json, os, re, shutil, sys, time
import mcp_cliente as mc
from mcp_cliente import check

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
BASE = mc.carpeta('cola_salida_1231')
# el servidor bajo prueba: una copia con node\ (los lanzadores) al lado
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
# el "binario desplegado": python copiado (un nativo de verdad), que corre el
# guion que se le pasa
shutil.copy(sys.executable, os.path.join(DEPLOY, PROJNAME + '.exe'))
PRJDIR = os.path.join(BASE, 'proj'); os.makedirs(PRJDIR)
DPROJ = os.path.join(PRJDIR, PROJNAME + '.dproj')
open(DPROJ, 'w', encoding='utf-8').write('<Project/>')
STUB = os.path.join(BASE, 'paclient.cmd')
open(STUB, 'w').write('@echo off\r\npython "%s" %%*\r\n' % os.path.join(HERE, 'paclient_stub.py'))

GUIONES = {
    'muchas.py': 'for i in range(1, 5001):\n    print("linea %05d" % i)\n',
    'larga.py': 'import sys\nsys.stdout.write("A" * 2000000 + "FIN-DE-LA-LINEA")\n',
    'enorme.py': 'import sys\nfor i in range(64):\n    sys.stdout.write(("x" * 1023 + "\\n") * 1024)\n'
                 'print("ULTIMA-LINEA")\nsys.exit(5)\n',
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


def corre(srv, guion, timeoutms=60000):
    r = srv.call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ,
                                     'exe': PROJNAME + '.exe', 'args': guion, 'timeoutms': timeoutms}, t=300)
    return r, mc.como_json(r)


def lineas(j):
    return (j.get('output') or '').splitlines()


def bytes_de_la_nota(j):
    m = re.search(r'(\d+) bytes', j.get('outputTruncatedNote') or '')
    return int(m.group(1)) if m else -1


srv = mc.Stdio(EXE, env, nombre='cola')

# C1
r, j = corre(srv, 'muchas.py')
ls = lineas(j)
check('C1 5000 lineas: van 400 como mucho (ROJO contra 1.23.x: iban las 5000)', 0 < len(ls) <= 400,
      (len(ls), r[:200]))
check('C1 ...las ULTIMAS: la 5000 si y la 1 no', 'linea 05000' in ls and 'linea 00001' not in ls, r[-300:])
check('C1 outputTruncated y RUN-023 con el tamano de la salida (mas de las 5000 lineas de 12 bytes)',
      j.get('outputTruncated') is True and mc.es(j.get('outputTruncatedNote'), 'SN_REMOTERUN_COLA_FMT')
      and bytes_de_la_nota(j) >= 5000 * 12 and ('%d lines' % len(ls)) in (j.get('outputTruncatedNote') or ''),
      {k: v for k, v in j.items() if k != 'output'})
check('C1 el codigo de salida sigue llegando (0)', j.get('exitCode') == 0, r[:200])

# C2
r, j = corre(srv, 'larga.py')
out = j.get('output') or ''
check('C2 una linea de 2 MB: va acotada en caracteres (ROJO: iba entera)', 0 < len(out) <= 70000, len(out))
check('C2 ...con su FINAL', out.endswith('FIN-DE-LA-LINEA') and j.get('outputTruncated') is True,
      (out[-60:], j.get('outputTruncated')))

# C4
r, j = corre(srv, 'pocas.py')
check('C4 control: 3 lineas van enteras, sin outputTruncated ni nota',
      lineas(j) == ['uno', 'dos', 'tres'] and 'outputTruncated' not in j and 'outputTruncatedNote' not in j, r[:300])

# C5
open(ESPERA, 'w').write('1')
r, j = corre(srv, 'tarde.py', timeoutms=2000)
os.remove(ESPERA)
job = j.get('jobId') or ''
check('C5 (preparacion) remote-run vuelve con el programa vivo', j.get('stillRunning') is True and job, r[:300])
dl = time.time() + 60
while True:
    time.sleep(2)
    r = srv.call('delphi_paserver', {'command': 'output', 'name': PROFILE, 'project': DPROJ, 'job': job}, t=120)
    jo = mc.como_json(r)
    if jo.get('stillRunning') is not True or time.time() > dl:
        break
ls = lineas(jo)
check('C5 output de un trabajo acabado: el mismo recorte, las ultimas y outputTruncated (ROJO: iban todas)',
      jo.get('stillRunning') is False and 0 < len(ls) <= 400 and 'tarde 05000' in ls and 'tarde 00001' not in ls
      and jo.get('outputTruncated') is True and mc.es(jo.get('outputTruncatedNote'), 'SN_REMOTERUN_COLA_FMT'),
      (len(ls), {k: v for k, v in jo.items() if k != 'output'}))
srv.mata()

# C3: en un servidor propio, para que su pico sea solo de esto
srv3 = mc.Stdio(EXE, env, nombre='enorme')
corre(srv3, 'pocas.py')   # lo que cuesta arrancar remote-run, fuera de la medida
antes = mc.memoria_pico(srv3.p.pid)
r, j = corre(srv3, 'enorme.py', timeoutms=180000)
despues = mc.memoria_pico(srv3.p.pid)
sube = (despues - antes) // (1024 * 1024)
check('C3 64 MB de salida: el pico de memoria privada del servidor sube menos de 32 MB (ROJO: la leia entera)',
      sube < 32, '%d MB (antes %d MB, despues %d MB)' % (sube, antes // 2 ** 20, despues // 2 ** 20))
check('C3 ...y la respuesta trae el final y el codigo de salida (5)',
      lineas(j)[-1:] == ['ULTIMA-LINEA'] and j.get('exitCode') == 5 and j.get('outputTruncated') is True
      and bytes_de_la_nota(j) >= 64 * 1024 * 1024, ({k: v for k, v in j.items() if k != 'output'}, lineas(j)[-2:]))
srv3.mata()

mc.fin('la cola de la salida 1.23.1 (V80)')
