# -*- coding: utf-8 -*-
"""ran=false de delphi_desktop dice por que (dirigido final de Hermes de la 1.29.1, 11-nov-2026).

Tras reiniciar el Fedora, una captura de Hermes llego perfecta con "ran": false y nada mas: delphi_desktop copiaba el
success del remote-run que corre el nodo y no su exitCode ni su stillRunning, asi que el agente no sabia si el nodo
habia fallado, si seguia vivo o si la captura valia.

Sin PAServer: el paclient falso (tests/paclient_stub.py) corre el lanzador real sobre un "nodo" de mentira que esta
bateria compila, como test_desktop_salida_1231: imprime CAPTURE= y despues sale con el codigo que le pide su fichero
de modo, o se queda vivo pasado el plazo de la llamada (apunta su PID, y la bateria lo mata por ese PID).

  R0 control: un nodo que sale con 0 da ran=true y ni exitCode ni ranNote
  R1 un nodo que sale con 3 tras capturar: ran=false, exitCode 3 y DESK-028; reachable sigue true
     (ROJO contra 39ba35a4: ran=false a secas)
  R2 un nodo que sigue vivo al plazo: ran=false, stillRunning y DESK-029 con los segundos del plazo
     (ROJO contra 39ba35a4)

Uso:  python tests/test_desktop_ran_1291.py [ruta-a-DelphiLspMcp.exe]
"""
import os, shutil, time
import mcp_cliente as mc
from mcp_cliente import check

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
BASE = mc.carpeta('desktop_ran_1291')
SERVERDIR = os.path.join(BASE, 'server')
os.makedirs(os.path.join(SERVERDIR, 'node'))
EXE = mc.copia_exe(SERVERDIR)
for f in ('McpRunJob', 'McpRunJob.exe'):
    shutil.copy(os.path.join(REPO, 'node', f), os.path.join(SERVERDIR, 'node', f))
RUNJOB_EXE = os.path.join(SERVERDIR, 'node', 'McpRunJob.exe')
SCRATCH = os.path.join(BASE, 'scratch')
os.makedirs(SCRATCH)
PROFILE = 'perfil'
NOMBRE = 'NodoRan'
PRJDIR = os.path.join(BASE, 'proj')
DPROJ = os.path.join(PRJDIR, NOMBRE + '.dproj')
DEPLOY = os.path.join(SCRATCH, NOMBRE)
MODO = os.path.join(DEPLOY, 'modo.txt')      # lo que hace el nodo: un codigo de salida, o "vive"
PIDF = os.path.join(DEPLOY, 'pid.txt')       # el PID del nodo que se queda vivo, para matarlo por el

STUB = mc.paclient_falso('desktop_ran_1291')  # fuera de la jaula (1.27)
env = mc.entorno()
env['DELPHI_MCP_ROOTS'] = BASE
env['DELPHI_MCP_PACLIENT'] = STUB
env['MCP_STUB_SCRATCH'] = SCRATCH
env['MCP_STUB_RUNJOB_EXE'] = RUNJOB_EXE
env['DELPHI_MCP_ALLOW_REMOTE_RUN'] = '1'
env['DELPHI_MCP_REMOTE_RUN_PROJECTS'] = DPROJ
env['DELPHI_MCP_DESKTOP_HOSTS'] = '*'
_ad, _host = mc.appdata_perfil(BASE, PROFILE, '127.0.0.1')
env['APPDATA'] = _ad
env['DELPHI_MCP_REMOTE_HOSTS'] = _host
srv = mc.Stdio(EXE, env, nombre='desktop-ran', t=300)
call = srv.call
vivo = 0


def estado(modo):
    open(MODO, 'w', encoding='ascii').write(modo)
    return mc.como_json(call('delphi_desktop', {'command': 'status', 'profile': PROFILE, 'project': DPROJ},
                             t=240)) or {}


try:
    r = call('delphi_create', {'kind': 'project-console', 'name': NOMBRE, 'dir': PRJDIR}, t=120)
    check('preparacion: el proyecto del nodo de mentira', not mc.fallo(r), r[:200])
    open(os.path.join(PRJDIR, NOMBRE + '.dpr'), 'w', encoding='utf-8', newline='\r\n').write(
        'program %s;\n\n{$APPTYPE CONSOLE}\n\nuses\n  Winapi.Windows, System.SysUtils, System.IOUtils;\n\n'
        'var\n  Modo: string;\nbegin\n'
        "  Writeln('CAPTURE=/tmp/captura.png');\n"
        "  Modo := Trim(TFile.ReadAllText('modo.txt'));\n"
        "  if Modo = 'vive' then\n  begin\n"
        "    TFile.WriteAllText('pid.txt', IntToStr(GetCurrentProcessId));\n"
        '    Sleep(180000);\n  end\n'
        '  else\n    Halt(StrToIntDef(Modo, 0));\nend.\n' % NOMBRE)
    b = mc.como_json(call('delphi_build', {'project': DPROJ, 'platform': 'Win64'}, t=600)) or {}
    salida = b.get('output', '')
    check('preparacion: el nodo de mentira compila', b.get('success') is True and os.path.isfile(mc.real(salida)),
          (b.get('success'), salida, b.get('errors')))
    os.makedirs(DEPLOY)
    shutil.copy(mc.real(salida), os.path.join(DEPLOY, NOMBRE + '.exe'))

    j = estado('0')
    check('R0 control: un nodo que sale con 0 da ran=true, sin exitCode ni ranNote',
          j.get('ran') is True and 'exitCode' not in j and 'ranNote' not in j and j.get('reachable') is True, j)

    j = estado('3')
    check('R1 un nodo que sale con 3 tras capturar: ran=false, exitCode 3 y DESK-028 (ROJO: ran=false a secas)',
          j.get('ran') is False and j.get('exitCode') == 3 and mc.abre(j.get('ranNote', ''), 'SN_DESKTOP_NODO_CODIGO_FMT')
          and '3' in j.get('ranNote', ''), j)
    check('R1b ...y la captura que hizo cuenta: reachable sigue true, sin error', j.get('reachable') is True
          and 'error' not in j, j)

    # el paclient falso vuelve en 1 s con el nodo vivo (como O3 de test_remoterun_out_1291); el servidor espera
    # su plazo entero (60 s) y lo da por vivo
    open(os.path.join(SCRATCH, '_espera'), 'w').write('1')
    j = estado('vive')
    os.remove(os.path.join(SCRATCH, '_espera'))
    vivo = int(open(PIDF).read().strip()) if os.path.isfile(PIDF) else 0
    check('R2 un nodo vivo al plazo: ran=false, stillRunning y DESK-029 con los 60 s (ROJO: ran=false a secas)',
          j.get('ran') is False and j.get('stillRunning') is True
          and mc.abre(j.get('ranNote', ''), 'SN_DESKTOP_NODO_SIGUE_FMT') and '60' in j.get('ranNote', ''), j)
finally:
    # el nodo que se quedo vivo, por SU PID (el que el mismo apunto), nunca por nombre
    if vivo and mc.pid_vivo(vivo):
        try:
            os.kill(vivo, 9)
        except OSError:
            pass
        time.sleep(1)
    srv.cierra()

check('el nodo vivo de R2 acabo muerto (por su PID)', not (vivo and mc.pid_vivo(vivo)), vivo)
mc.borra(BASE)
mc.fin('desktop: ran=false dice por que (1.29.1)')
