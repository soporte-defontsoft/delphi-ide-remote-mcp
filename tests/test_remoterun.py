# -*- coding: utf-8 -*-
"""E2E battery for v0.47.0-beta - delphi_paserver command=remote-run: running
a program ON THE TARGET through PAServer's file transport (paclient has no
exec operation) sin NADA instalado alli: PAServer ARRANCA lo que se le sube.
Desde 1.0.16 eso es el lanzador nativo (src/RunJob) y un fichero .job: un
solo camino para Linux y Windows, sin shell.

PAServer is NOT needed: paclient.exe is replaced by tests/paclient_stub.py
(DELPHI_MCP_PACLIENT), which copies to a local folder playing the scratch dir
and RUNS the real launcher (its Win64 build, the same source as the ELF a
Linux gets). The server looks the launcher up in node\\ next to its own exe,
so the battery runs a COPY of the server from its temp folder with node\\
beside it - the build output stays untouched.

Usage:  python tests/test_remoterun.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, time, os, sys, shutil
import mcp_cliente as mc
from mcp_cliente import check

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
BASE = mc.carpeta('remoterun')
# the server under test: a copy with node\\ (the launchers) beside it
SERVERDIR = os.path.join(BASE, 'server'); os.makedirs(os.path.join(SERVERDIR, 'node'))
EXE = mc.copia_exe(SERVERDIR)
for f in ('McpRunJob', 'McpRunJob.exe'):
    shutil.copy(os.path.join(REPO, 'node', f), os.path.join(SERVERDIR, 'node', f))
RUNJOB_EXE = os.path.join(SERVERDIR, 'node', 'McpRunJob.exe')
SCRATCH = os.path.join(BASE, 'scratch'); os.makedirs(SCRATCH)
# Cuanto espera el stub a que el trabajo remate antes de devolver el control
# (sin el fichero, 20 s). Va por FICHERO: el stub hereda el entorno del
# servidor, no el de la bateria, y el os.environ que se ponia aqui despues de
# arrancarlo no le llegaba nunca (medido 2026-09-26).
ESPERA = os.path.join(SCRATCH, '_espera')

# the deploy folder the server derives: <windows user>-<profile>/<Project>/
PROFILE = 'perfil'
PROJNAME = 'Saluda'
# the runner's root IS the profile scratch folder (that is where _mcp-runner
# lives), so a deploy sits at <scratch>/<Project>/ - measured end to end
# against a real PAServer 2026-08-25
DEPLOY = os.path.join(SCRATCH, PROJNAME)
os.makedirs(DEPLOY)
# the "deployed binary": a real native executable (python itself, copied), so
# the runner's ELF/PE check passes; it prints and exits 7 through a wrapper
APP = os.path.join(DEPLOY, PROJNAME + '.exe')
shutil.copy(sys.executable, APP)
SCRIPT = os.path.join(DEPLOY, 'run.py')
open(SCRIPT, 'w', encoding='utf-8').write(
    'import sys\nprint("hola desde el target, args=", sys.argv[1:])\nsys.exit(7)\n')
# a script sitting in the same folder: must be REFUSED (not a native binary)
# the project on THIS server (remote-run takes the .dproj, not a path)
PRJDIR = os.path.join(BASE, 'proj'); os.makedirs(PRJDIR)
DPROJ = os.path.join(PRJDIR, PROJNAME + '.dproj')
open(DPROJ, 'w', encoding='utf-8').write('<Project/>')

# paclient stub: a .cmd that calls python on the stub script
STUB = os.path.join(BASE, 'paclient.cmd')
open(STUB, 'w').write('@echo off\r\npython "%s" %%*\r\n' % os.path.join(HERE, 'paclient_stub.py'))


env = mc.entorno()
env['DELPHI_MCP_ROOTS'] = BASE
env['DELPHI_MCP_PACLIENT'] = STUB
env['MCP_STUB_SCRATCH'] = SCRATCH
env['MCP_STUB_RUNJOB_EXE'] = RUNJOB_EXE   # el gemelo Win64 del lanzador que corre el stub
env['DELPHI_MCP_ALLOW_REMOTE_RUN'] = '1'   # v0.48.1: remote execution is opt-in
env['DELPHI_MCP_REMOTE_RUN_PROJECTS'] = 'Saluda'  # v0.98: lista vacia = NADA (fail closed)
srv = mc.Stdio(EXE, env, nombre='rr')
call = srv.call

# ---- the opt-in switch (a server without AllowRemoteRun) ----
env_off = dict(env); env_off.pop('DELPHI_MCP_ALLOW_REMOTE_RUN', None)
srv_off = mc.Stdio(EXE, env_off, nombre='off')
call_off = srv_off.call

# 1) needs name+exe
r = call('delphi_paserver', {'command': 'remote-run'})
check('sin name/exe rechazado', 'RECHAZADO' in r, r[:150])
# 2) shell metachar refused
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ, 'args': 'a; rm -rf /'})
check('metacaracter rechazado', 'RECHAZADO' in r and ';' in r, r[:150])

# 3) happy path
# exe=<nombre simple> de la MISMA carpeta de despliegue (en Linux el binario
# no lleva extension y basta project; aqui el "binario" es un .exe de Windows)
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ,
                             'exe': PROJNAME + '.exe',
                             'args': '"%s" uno dos' % SCRIPT.replace(chr(92), '/'),
                             'timeoutms': 30000}, t=180)
j = json.loads(r) if r.startswith('{') else {}
check('exitCode del programa (7)', j.get('exitCode') == 7, r[:300])
check('output capturado', 'hola desde el target' in (j.get('output') or ''), r[:300])
check('note explica el mecanismo', 'PAServer' in (j.get('note') or ''), r[:200])
# v1.0.16: el lanzador cuenta el entorno grafico y el servidor lo traduce. El
# que corre aqui es el de Windows, que dice en que SESION corre (la 0, de los
# servicios, no tiene escritorio); y la linea ___ENV= que lo trae nunca llega
# al output del programa.
check('graphicalEnv: el resultado dice en que sesion de Windows corrio el programa',
      'sesion' in (j.get('graphicalEnv') or '').lower(), r[:300])
check('graphicalEnv: la linea ___ENV= no se cuela en el output', '___ENV' not in (j.get('output') or ''), r[:300])
# v0.85: two agents firing in the same millisecond used to collide on a
# timestamp-only jobId; now it carries a GUID fragment
import re as _re
check('jobId lleva fragmento GUID (timestamp-only colisionaba)',
      bool(_re.match(r'^\d{8}-\d{9}-[0-9a-f]{8}$', j.get('jobId') or '')),
      j.get('jobId'))
# 3b) CADA argumento llega al programa TAL CUAL, como argv. Hasta 1.0.15 iban
# por un /bin/sh y el filtro de metacaracteres lo ponia quien llama (medido
# contra un Fedora el 2026-09-21: un texto con parentesis rompio la sintaxis
# del guion). Desde 1.0.16 no hay shell: van del .job al argv del lanzador.
# Aqui se mide el punto unico: parentesis, asterisco, almohadilla, virgulilla
# y comilla simple tienen que llegar LITERALES, y las comillas dobles siguen
# agrupando.
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ,
                             'exe': PROJNAME + '.exe',
                             'args': '"%s" (a) * #b ~ it\'s "dos palabras"' % SCRIPT.replace(chr(92), '/'),
                             'timeoutms': 30000}, t=180)
j = json.loads(r) if r.startswith('{') else {}
out = j.get('output') or ''
check('argumentos blindados: ( ) * # ~ y la comilla simple llegan literales',
      all(x in out for x in ("'(a)'", "'*'", "'#b'", "'~'", '"it\'s"')), r[:400])
check('...y las comillas dobles siguen agrupando un argumento con espacios',
      "'dos palabras'" in out, r[:400])
# 4) exe fuera de la scratch -> runnerError
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ, 'exe': '..\\..\\fuera.exe', 'timeoutms': 20000})
j = json.loads(r) if r.startswith('{') else {}
check('exe con separadores rechazado por el server', 'RECHAZADO' in r, r[:250])
# 5) exe inexistente -> runnerError
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ, 'exe': 'noexiste.exe', 'timeoutms': 20000}, t=180)
j = json.loads(r) if r.startswith('{') else {}
check('exe inexistente en target', 'no existe' in json.dumps(j), r[:250])

# 5b) un SCRIPT de la misma carpeta de despliegue: rechazado (no es nativo)
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ,
                             'exe': 'run.py', 'timeoutms': 20000}, t=180)
j = json.loads(r) if r.startswith('{') else {}
check('script en la carpeta de deploy rechazado (solo binario nativo)',
      'ejecutable nativo' in json.dumps(j), r[:300])
# 5c) proyecto inexistente
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE,
                             'project': os.path.join(PRJDIR, 'NoHay.dproj')})
check('proyecto inexistente rechazado', 'RECHAZADO' in r, r[:200])
# 5d) proyecto fuera de la jaula
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE,
                             'project': 'C:\\Windows\\x.dproj'})
check('proyecto fuera de la jaula rechazado', 'RECHAZADO' in r, r[:200])

# 6) un programa que NO termina: sigue vivo y devuelve su salida PARCIAL.
# Es el cambio de fondo al retirar el runner (19-sep-2026): antes se mataba
# al expirar el plazo y te quedabas sin proceso Y sin resultado; una
# aplicacion con ventana esta justo para quedarse.
LENTO = os.path.join(DEPLOY, 'lento.py')
PROGRAMA_LENTO = [
    'import sys, time',
    'print("arrancando", flush=True)',
    'time.sleep(30)',
]
open(LENTO, 'w', encoding='utf-8').write(chr(10).join(PROGRAMA_LENTO))
open(ESPERA, 'w').write('3')   # el stub no espera a que remate
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE,
                             'project': DPROJ, 'exe': PROJNAME + '.exe',
                             'args': 'lento.py', 'timeoutms': 4000}, t=180)
j = json.loads(r) if r.startswith('{') else {}
check('no termina: stillRunning en vez de matarlo', j.get('stillRunning') is True, r[:300])
check('no termina: devuelve la salida PARCIAL', 'arrancando' in (j.get('output') or ''), r[:300])
check('no termina: lo dice sin hablar de errores', 'SIGUE CORRIENDO' in (j.get('stillRunningNote') or ''), r[:300])
# 1.5.0: la salida de un programa que SIGUE vivo se queda en el target, y lo
# que escriba despues se lee con command=output (antes se borraba al volver:
# el AV de Galatea tras el login solo se veia en el journal de Zorin).
job6 = j.get('jobId') or ''
OUT6 = os.path.join(DEPLOY, job6 + '.out')
check('no termina: su salida SE QUEDA en el target para leerla despues', os.path.isfile(OUT6), os.listdir(DEPLOY))
check('no termina: la respuesta dice como leerla (outputNote)',
      'command=output' in (j.get('outputNote') or '') and job6 in (j.get('outputNote') or ''), r[:500])
r = call('delphi_paserver', {'command': 'output', 'name': PROFILE, 'project': DPROJ, 'job': job6}, t=120)
jo = json.loads(r) if r.startswith('{') else {}
check('output con el programa vivo: lo que lleva, stillRunning=true, y la salida sigue alli',
      jo.get('stillRunning') is True and 'arrancando' in (jo.get('output') or '') and os.path.isfile(OUT6), r[:300])
os.remove(ESPERA)

# 6b) kill: el trabajo vivo se mata por su .pid; y SIN .pid (un deploy fallido
# borra la carpeta antes de rendirse en el vigia, medido 2026-09-23 en
# 192.168.1.10 con dos GUI huerfanas) el vigia lleva el pid en su NOMBRE
# (<job>.wait.<pid>.exe) y kill lo saca de ahi. El stub corre el lanzador
# REAL de Windows, asi que esto mide el binario que viaja en node\.
job6 = j.get('jobId')
r = call('delphi_paserver', {'command': 'kill', 'name': PROFILE, 'project': DPROJ, 'job': job6}, t=180)
j = json.loads(r) if r.startswith('{') else {}
check("kill: mata el trabajo vivo por su .pid", j.get('killed') is True and 'por .pid' in (j.get('output') or ''), r[:900])
r = call('delphi_paserver', {'command': 'kill', 'name': PROFILE, 'project': DPROJ, 'job': job6}, t=180)
j = json.loads(r) if r.startswith('{') else {}
check('kill: repetido, ya no hay trabajo (killed=false, sin error)', j.get('killed') is False and 'ya termino' in (j.get('output') or ''), r[:300])
# el vigia remata la salida del matado con su ___RC: output la lee entera y la borra
dl = time.time() + 20
while True:
    r = call('delphi_paserver', {'command': 'output', 'name': PROFILE, 'project': DPROJ, 'job': job6}, t=120)
    jo = json.loads(r) if r.startswith('{') else {}
    if jo.get('stillRunning') is not True or time.time() > dl:
        break
    time.sleep(1)
check('output tras kill: terminado, con su codigo y lo que escribio',
      jo.get('stillRunning') is False and 'exitCode' in jo and 'arrancando' in (jo.get('output') or ''), r[:300])
check('output leido entero: la salida se BORRA del target (como el buzon)', not os.path.exists(OUT6), os.listdir(DEPLOY))
r = call('delphi_paserver', {'command': 'output', 'name': PROFILE, 'project': DPROJ, 'job': job6}, t=120)
jo = json.loads(r) if r.startswith('{') else {}
check('output otra vez: ya no hay nada, y lo dice', jo.get('success') is False and 'No hay salida' in (jo.get('error') or ''), r[:300])
r = call('delphi_paserver', {'command': 'output', 'name': PROFILE, 'project': DPROJ, 'job': '..\\x'})
check('output: un job que no es un id de este servidor se rechaza', 'RECHAZADO' in r, r[:200])
r = call('delphi_paserver', {'command': 'output', 'name': PROFILE, 'project': DPROJ})
check('output sin job: RECHAZADO, y dice que le falta', 'RECHAZADO' in r and 'output necesita' in r, r[:200])

# 6c) EL caso: un programa que escribe DESPUES de que vuelva su remote-run y
# termina con un codigo. Antes eso se escribia en un fichero ya borrado.
TARDE = os.path.join(DEPLOY, 'tarde.py')
open(TARDE, 'w', encoding='utf-8').write(
    'import sys, time\nprint("antes del plazo", flush=True)\ntime.sleep(25)\n'
    'print("DESPUES-DEL-PLAZO", flush=True)\nsys.exit(3)\n')
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ,
                             'exe': PROJNAME + '.exe', 'args': 'tarde.py', 'timeoutms': 2000}, t=180)
j = json.loads(r) if r.startswith('{') else {}
job6c = j.get('jobId') or ''
check('tarde: vuelve vivo, con lo de antes del plazo y nada de despues',
      j.get('stillRunning') is True and 'antes del plazo' in (j.get('output') or '')
      and 'DESPUES' not in (j.get('output') or ''), r[:300])
dl = time.time() + 45
while True:
    time.sleep(2)
    r = call('delphi_paserver', {'command': 'output', 'name': PROFILE, 'project': DPROJ, 'job': job6c}, t=120)
    jo = json.loads(r) if r.startswith('{') else {}
    if jo.get('stillRunning') is not True or time.time() > dl:
        break
check('tarde: output trae lo escrito DESPUES del plazo y su codigo de salida (3)',
      jo.get('stillRunning') is False and 'DESPUES-DEL-PLAZO' in (jo.get('output') or '')
      and jo.get('exitCode') == 3, r[:300])
check('tarde: leida entera, borrada', not os.path.exists(os.path.join(DEPLOY, job6c + '.out')), os.listdir(DEPLOY))
open(ESPERA, 'w').write('3')
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ,
                             'exe': PROJNAME + '.exe', 'args': 'lento.py', 'timeoutms': 4000}, t=180)
j = json.loads(r) if r.startswith('{') else {}
os.remove(ESPERA)
job6b = j.get('jobId') or ''
pidf = os.path.join(DEPLOY, job6b + '.pid')
_vigias = [f for f in os.listdir(DEPLOY) if f.startswith(job6b + '.wait.') and f.endswith('.exe')]
check('vigia con el pid en el nombre (<job>.wait.<pid>.exe) junto al .pid', j.get('stillRunning') is True and os.path.isfile(pidf) and len(_vigias) == 1 and _vigias[0][len(job6b) + 6:-4].isdigit(), (r[:150], os.listdir(DEPLOY)))
if os.path.isfile(pidf):
    os.remove(pidf)   # lo que hace un deploy fallido antes de rendirse
r = call('delphi_paserver', {'command': 'kill', 'name': PROFILE, 'project': DPROJ, 'job': job6b}, t=180)
j = json.loads(r) if r.startswith('{') else {}
check('kill sin .pid: lo mata por el nombre del vigia', j.get('killed') is True and 'nombre del vigia' in (j.get('output') or ''), r[:300])
check('kill sin .pid: el proceso ha muerto de verdad', not any(f.endswith('.pid') for f in os.listdir(DEPLOY)), os.listdir(DEPLOY))

# 7) sin AllowRemoteRun: remote-run RECHAZADO, install-runner permitido
r = call_off('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ})
check('sin AllowRemoteRun: remote-run rechazado', 'RECHAZADO' in r and 'AllowRemoteRun' in r, r[:250])
r = call_off('delphi_paserver', {'command': 'platforms'})
check('sin AllowRemoteRun: el resto del tool intacto', 'platforms' in r, r[:150])
srv_off.mata()

# 8) RemoteRunProjects: lista blanca de proyectos ejecutables. En el modo
# local la lista llega por el ENTORNO. Aqui se escribia un settings.ini con
# [Workspace] (sin punto), seccion IGNORADA entera desde la v0.98: el check
# pasaba por la lista VACIA (fail closed), no por un proyecto que falta en
# una lista que nombra otros, que es lo que dice (medido 2026-09-26).
env_wl = dict(env); env_wl['DELPHI_MCP_REMOTE_RUN_PROJECTS'] = 'OtroProyecto'
srv_wl = mc.Stdio(EXE, env_wl, nombre='wl')
call_wl = srv_wl.call
r = call_wl('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ})
check('proyecto fuera de RemoteRunProjects rechazado', 'RECHAZADO' in r and 'RemoteRunProjects' in r, r[:250])
r = call_wl('delphi_workspace', {})
check('LibraryZone=1 por defecto: zona anunciada', 'readableExtra' in r and 'RTL' in r, r[:200])
srv_wl.mata()

# 9) LibraryZone=0: la lectura se limita a los roots
env_lz = dict(env); env_lz['DELPHI_MCP_LIBRARY_ZONE'] = '0'
srv_lz = mc.Stdio(EXE, env_lz, nombre='lz')
call_lz = srv_lz.call
RTL = r'C:\Program Files (x86)\Embarcadero\Studio\37.0\source\rtl\sys\System.SysUtils.pas'
r = call_lz('delphi_read', {'path': RTL, 'fromline': 1, 'toline': 2})
check('LibraryZone=0: la RTL deja de ser legible', 'RECHAZADO' in r, r[:200])
r = call_lz('delphi_workspace', {})
check('LibraryZone=0: se anuncia apagada y sin carpetas', 'APAGADA' in r and '"readableExtra":[]' in r.replace(' ', ''), r[:300])
r = call_lz('delphi_read', {'path': SCRIPT, 'fromline': 1, 'toline': 1})
check('LibraryZone=0: el root sigue legible', 'RECHAZADO' not in r, r[:200])
srv_lz.mata()

srv.mata()
mc.fin('remote-run')
