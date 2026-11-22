# -*- coding: utf-8 -*-
"""1.29.3, revisor del paisaje del diff (21-nov): el dueno de un trabajo de remote-run era su perfil y su proyecto,
sin el workspace. Otro workspace con el mismo proyecto en sus raices y el mismo perfil (en la VM, Claude y Hermes
comparten srvn:\\CodeSandBox) podia, con el id, leer la salida de un trabajo ajeno - y leida entera se BORRA del
destino - o pararlo; y desde D32 (la lista de los trabajos que valen en RUN-021/RUN-001/PAS-002) se le ENSENABAN los
ids. Ahora el dueno es workspace + perfil + proyecto (Lsp.RemoteRun.DuenoDeTrabajo, EL compositor de los tres:
ApuntaTrabajo, TrabajoNuestro y TrabajosDe). David, 21-nov: "arreglar ya".

Sin PAServer: el banco de test_remoterun_out_1291 (paclient_stub.py arranca el lanzador de verdad) y el servidor HTTP
de dos workspaces de test_git_otro_workspace_128, los dos con la MISMA raiz y el mismo perfil.

  W0 control: A lanza un trabajo que sigue vivo y le da su id
  W1 B, kill sin job: la lista NO trae el trabajo de A (ROJO sin el arreglo: lo trae)
  W2 B, output con el id de A: RUN-021, nada leido (ROJO: le daba la salida)
  W3 B, kill con el id de A: RUN-021, nada parado (ROJO: lo paraba)
  W4 control: A, kill sin job: su lista trae su trabajo
  W5 control: A, output de su trabajo: lo lee y sigue vivo
  W6 control: A, kill de su trabajo: lo para

Uso:  python tests/test_trabajos_por_workspace_1293.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import shutil
import sys
import mcp_cliente as mc
from mcp_cliente import check

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('trabajos_ws_1293')
SERVERDIR = os.path.join(BASE, 'server')
os.makedirs(os.path.join(SERVERDIR, 'node'))
EXE = mc.copia_exe(SERVERDIR, src=exe_src)
for f in ('McpRunJob', 'McpRunJob.exe'):
    shutil.copy(os.path.join(REPO, 'node', f), os.path.join(SERVERDIR, 'node', f))
RUNJOB_EXE = os.path.join(SERVERDIR, 'node', 'McpRunJob.exe')
SCRATCH = os.path.join(BASE, 'scratch')
os.makedirs(SCRATCH)
PROFILE = 'perfil'
PROJNAME = 'Largo'
DEPLOY = os.path.join(SCRATCH, PROJNAME)
os.makedirs(DEPLOY)
shutil.copy(sys.executable, os.path.join(DEPLOY, PROJNAME + '.exe'))
open(os.path.join(DEPLOY, 'largo.py'), 'w', encoding='utf-8').write(
    'import time\nprint("empiezo", flush=True)\ntime.sleep(60)\n')
RAIZ = os.path.join(BASE, 'raiz')  # la raiz COMPARTIDA por los dos workspaces
PRJDIR = os.path.join(RAIZ, 'proj')
os.makedirs(PRJDIR)
DPROJ = os.path.join(PRJDIR, PROJNAME + '.dproj')
open(DPROJ, 'w', encoding='utf-8').write('<Project/>')
STUB = mc.paclient_falso('trabajos_ws_1293')  # fuera de la jaula (1.27)
_ad, _host = mc.appdata_perfil(BASE, PROFILE, '127.0.0.1')

TA, TB = 'trabajos-ws-a', 'trabajos-ws-b'
SECCION = 'Token=%s\nRoots=%s\nAllowRemoteRun=1\nRemoteRunProjects=%s\nRemoteHosts=%s\n'
with open(os.path.join(SERVERDIR, 'settings.ini'), 'w') as f:
    f.write('[Workspace.A]\n' + SECCION % (TA, RAIZ, DPROJ, _host) + '\n')
    f.write('[Workspace.B]\n' + SECCION % (TB, RAIZ, DPROJ, _host))
env = mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1', 'DELPHI_MCP_PACLIENT': STUB, 'MCP_STUB_SCRATCH': SCRATCH,
                  'MCP_STUB_RUNJOB_EXE': RUNJOB_EXE, 'APPDATA': _ad})
puerto = mc.puerto_libre()
proc = mc.lanza_http(EXE, puerto, env)


# los trozos SF_ no llevan etiqueta (mc.es es para las que si): su texto fijo, del catalogo del fuente
NINGUNO = mc.trozo_de_formato('SF_REMOTERUN_NINGUN_TRABAJO', 0).strip()
LISTA = mc.trozo_de_formato('SF_REMOTERUN_TRABAJOS_FMT', 0).strip()


def cliente(token, agente):
    c = mc.Http(puerto, token)
    assert c.session(agente), (token, agente)
    return c


def pas(c, comando, job=None, **extra):
    a = {'command': comando, 'name': PROFILE, 'project': DPROJ}
    if job is not None:
        a['job'] = job
    a.update(extra)
    r = c.call('delphi_paserver', a, t=300)
    return r, mc.como_json(r) or {}


try:
    a = cliente(TA, 'agente-a')
    b = cliente(TB, 'agente-b')
    r, j = pas(a, 'remote-run', exe=PROJNAME + '.exe', args='largo.py', timeoutms=3000)
    JA = j.get('jobId', '')
    check('W0 control: A lanza un trabajo que sigue vivo y tiene su id',
          bool(JA) and j.get('stillRunning') is True, r[:400])

    r, j = pas(b, 'kill')
    check('W1 B, kill sin job: la lista no trae el trabajo de A, y dice que B no arranco ninguno (ROJO sin el '
          'arreglo: trae el de A)',
          bool(JA) and JA not in r and NINGUNO in r, r[:400])
    r, j = pas(b, 'output', job=JA)
    check('W2 B, output con el id de A: RUN-021, y nada de su salida (ROJO: se la daba, y leida se borra)',
          mc.abre(r, 'SR_REMOTERUN_JOB_AJENO_FMT') and 'empiezo' not in r, r[:400])
    r, j = pas(b, 'kill', job=JA)
    check('W3 B, kill con el id de A: RUN-021, nada parado (ROJO: lo paraba)',
          mc.abre(r, 'SR_REMOTERUN_JOB_AJENO_FMT'), r[:400])

    r, j = pas(a, 'kill')
    check('W4 control: A, kill sin job: su lista trae su trabajo', JA in r and LISTA in r,
          r[:400])
    r, j = pas(a, 'output', job=JA)
    check('W5 control: A lee la salida de su trabajo, que sigue vivo (B no lo paro)',
          'empiezo' in r and j.get('stillRunning') is True, r[:400])
    r, j = pas(a, 'kill', job=JA)
    check('W6 control: A para su trabajo', not mc.fallo(r) and not mc.es(r, 'SR_REMOTERUN_JOB_AJENO_FMT'), r[:400])
finally:
    proc.kill()

mc.recoge_huellas()
mc.borra(BASE)
mc.fin('un trabajo de remote-run es del workspace que lo arranco 1.29.3 (revisor del paisaje)')
