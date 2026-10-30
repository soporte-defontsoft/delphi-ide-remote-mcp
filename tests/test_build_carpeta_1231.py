"""Lo que las herramientas del IDE buscan en la carpeta del proyecto (V218 de la 1.23.1). msbuild pone a sus
tareas en esa carpeta, que escribe el agente, y un build solo compila. Medido el 30-oct-2026 con Process Monitor:
cgrc mira PRIMERO ahi su resinator.exe, y dccaarm64 busca ahi un LNKDFM380.DLL que el IDE no trae. Las sondas de
aqui son inertes: solo dejan un fichero que dice que corrieron.

  C1 control: el proyecto compila sin nada plantado.
  C2 un resinator.exe en la carpeta del proyecto: el build se NIEGA (BUILD-065) y no se ejecuta (ROJA contra
     12c3aa6: se ejecuta con la cuenta del servicio y el build sale verde).
  C3 el mismo programa en una SUBcarpeta no estorba: compila y no se ejecuta.
  C4 quitado de la carpeta, el proyecto compila otra vez.
  C5 un LNKDFM380.DLL en la carpeta de un proyecto FMX, compilado para Android64: no se carga y compila (ROJA
     contra 12c3aa6: dccaarm64 lo carga y el build cae con E2141). Sin SDK de Android, no se mide.

Uso:  python tests/test_build_carpeta_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import shutil
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('build_carpeta_1231')
SRV = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRV, src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
PUERTO = mc.puerto_libre()
TOKEN = 'build-carpeta-1231-0123456789'
open(os.path.join(SRV, 'settings.ini'), 'w').write('[Workspace.S]\nToken=%s\nRoots=%s\n' % (TOKEN, JAIL))
MARCA = 'SONDA_CORRIO.txt'

SONDA = """%s %s;
%s
uses
  System.SysUtils, System.IOUtils;
begin
  TFile.WriteAllText(TPath.Combine(GetCurrentDir, '%s'), ParamStr(0));
end.
"""


def proyecto(cli, kind, nombre):
    d = os.path.join(JAIL, nombre)
    cli.call('delphi_create', {'kind': kind, 'name': nombre, 'dir': d})
    return d, os.path.join(d, nombre + '.dproj')


def sonda(cli, nombre, es_dll, plataforma):
    # un programa o una biblioteca que solo escribe el marcador en su carpeta actual
    d, dproj = proyecto(cli, 'project-console', nombre)
    open(os.path.join(d, nombre + '.dpr'), 'w').write(
        SONDA % ('library' if es_dll else 'program', nombre, '' if es_dll else '{$APPTYPE CONSOLE}', MARCA))
    r = cli.call('delphi_build', {'project': dproj, 'platform': plataforma})
    salida = os.path.join(d, plataforma, 'Debug', nombre + '.exe')
    assert os.path.exists(salida), r[:400]
    return salida


def verde(r):
    return '"success":true' in r.replace(' ', '')


proc = mc.lanza_http(EXE, PUERTO, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'}))
try:
    cli = mc.Http(PUERTO, TOKEN, t=600)
    cli.session('agente')

    prog = sonda(cli, 'SondaExe', False, 'Win64')
    d, dproj = proyecto(cli, 'project-console', 'Cons')
    marca = os.path.join(d, MARCA)
    r = cli.call('delphi_build', {'project': dproj, 'platform': 'Win64'})
    check('C1 control: compila sin nada plantado', verde(r) and not os.path.exists(marca), r[:300])

    plantado = os.path.join(d, 'resinator.exe')
    shutil.copy(prog, plantado)
    r = cli.call('delphi_build', {'project': dproj, 'platform': 'Win64'})
    check('C2 un resinator.exe en la carpeta del proyecto NO se ejecuta', not os.path.exists(marca), r[:300])
    check('C2 ...y el build lo niega y dice por que', mc.rechazado(r) and mc.es(r, 'SR_BUILD_PROGRAMA_EN_SU_CARPETA_FMT'), r[:300])
    if os.path.exists(marca):
        os.remove(marca)

    sub = os.path.join(d, 'lib')
    os.makedirs(sub)
    os.replace(plantado, os.path.join(sub, 'resinator.exe'))
    r = cli.call('delphi_build', {'project': dproj, 'platform': 'Win64'})
    check('C3 en una subcarpeta no estorba: compila y no se ejecuta',
          verde(r) and not os.path.exists(marca) and not os.path.exists(os.path.join(sub, MARCA)), r[:300])
    shutil.rmtree(sub)
    r = cli.call('delphi_build', {'project': dproj, 'platform': 'Win64'})
    check('C4 sin el, el proyecto compila otra vez', verde(r), r[:300])

    biblio = sonda(cli, 'LNKDFM380', True, 'Win32')
    f, fdproj = proyecto(cli, 'project-fmx', 'Fmx')
    fmarca = os.path.join(f, MARCA)
    shutil.copy(biblio, os.path.join(f, 'LNKDFM380.DLL'))
    cli.call('delphi_config', {'project': fdproj, 'command': 'add-platform', 'platform': 'Android64'})
    r = cli.call('delphi_build', {'project': fdproj, 'platform': 'Android64'})
    if 'SDK' in r and not verde(r) and 'E2141' not in r:
        print('NOTA C5 no se mide: esta maquina no compila Android64 (%s)' % r[:160])
    else:
        check('C5 un LNKDFM380.DLL en la carpeta del proyecto no se carga', not os.path.exists(fmarca), r[:300])
        check('C5 ...y Android64 compila', verde(r), r[:300])
finally:
    proc.kill()

mc.borra(BASE)
mc.fin('lo que el IDE busca en la carpeta del proyecto 1231 (V218)')
