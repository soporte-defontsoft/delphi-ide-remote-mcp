# -*- coding: utf-8 -*-
"""A un destino macOS no se le sube un binario de Linux (revisor del paisaje de la 1.29.3).

Los binarios que viajan con el servidor (node\\McpRunJob, el lanzador de remote-run y kill, y node\\McpDesktopNode,
el nodo de delphi_desktop) son ELF de Linux y .exe de Windows. EL nombrador (Lsp.RemoteRun.EmpaquetadoConElServidor)
los nombraba por la extension del ejecutable del destino, y la de macOS es '' como la de Linux: a un perfil OSX64 le
subia el ELF de Linux (medido con el paclient falso y su log, sonda_macos del 21-nov-2026: remote-run puso
node\\McpRunJob con flag 3, y delphi_desktop puso node\\McpDesktopNode). Ahora ese nombrador no da binario a un
sistema para el que la distribucion no lo trae, y cada camino lo dice con su texto.

  M1 remote-run con un perfil OSX64: RUN-037, que nombra el perfil y la plataforma, y NADA subido (ROJO sin el arreglo)
  M1b ...y ese trabajo no queda en la lista de los que valen para kill y output (RUN-021 dice que no hay ninguno)
  M2 delphi_desktop screenshot con un perfil OSX64: DESK-021 (no hay nodo empaquetado para ese sistema) y NADA
     subido (ROJO sin el arreglo)
  M3 control: con un perfil Linux64, remote-run sube el lanzador ELF (node\\McpRunJob)
  M4 control: con un perfil Linux64, delphi_desktop sube el nodo ELF (node\\McpDesktopNode)

Lo que el lanzador haria luego aqui (el stub corre su gemelo Win64) no se mide: solo que se sube y que no.

Uso:  python tests/test_macos_sin_binarios_1293.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import shutil
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('macos_sin_binarios_1293')
SERVERDIR = os.path.join(BASE, 'server')
os.makedirs(os.path.join(SERVERDIR, 'node'))
EXE = mc.copia_exe(SERVERDIR)
for f in ('McpRunJob', 'McpRunJob.exe', 'McpDesktopNode', 'McpDesktopNode.exe'):
    shutil.copy(os.path.join(mc.REPO, 'node', f), os.path.join(SERVERDIR, 'node', f))
SCRATCH = os.path.join(BASE, 'scratch')
os.makedirs(os.path.join(SCRATCH, 'Saluda'))
# lo que espera el stub a que el trabajo remate (ver test_remoterun): poco, aqui no se mide el trabajo
open(os.path.join(SCRATCH, '_espera'), 'w').write('2')
PRJDIR = os.path.join(BASE, 'proj')
os.makedirs(PRJDIR)
DPROJ = os.path.join(PRJDIR, 'Saluda.dproj')
open(DPROJ, 'w', encoding='utf-8').write('<Project/>')
STUB = mc.paclient_falso('macos_sin_binarios_1293')
LOG = os.path.join(os.path.dirname(STUB), 'paclient.log')

env = mc.entorno()
env.update({'DELPHI_MCP_ROOTS': BASE, 'DELPHI_MCP_PACLIENT': STUB, 'MCP_STUB_SCRATCH': SCRATCH, 'MCP_STUB_LOG': LOG,
            'MCP_STUB_RUNJOB_EXE': os.path.join(SERVERDIR, 'node', 'McpRunJob.exe'),
            'DELPHI_MCP_ALLOW_REMOTE_RUN': '1', 'DELPHI_MCP_REMOTE_RUN_PROJECTS': DPROJ,
            'DELPHI_MCP_DESKTOP_HOSTS': '*'})
PERFIL_MAC, PERFIL_LINUX = 'perfil-mac', 'perfil-linux'
_ad, _host = mc.appdata_perfil(BASE, PERFIL_MAC, '127.0.0.1', platform='OSX64')
mc.appdata_perfil(BASE, PERFIL_LINUX, '127.0.0.1', platform='Linux64')
env['APPDATA'] = _ad
env['DELPHI_MCP_REMOTE_HOSTS'] = _host
s = mc.Stdio(EXE, env, nombre='macos-1293', t=180)
_vistas = [0]


def subidas():
    """Los --put que el servidor le pidio al paclient desde la ultima vez (cada uno, su linea del log)."""
    lineas = open(LOG, encoding='utf-8').read().splitlines() if os.path.exists(LOG) else []
    nuevas, _vistas[0] = lineas[_vistas[0]:], len(lineas)
    return [x for x in nuevas if '--put' in x]


def sin_nodo_en_el_destino():
    """El paclient falso no distingue perfiles (un destino para los dos): el nodo que subiera un paso, con su
    sello, haria que el siguiente lo viera al dia y no subiera nada, y el control saldria rojo (o un rechazo
    verde) por el orden. Cada paso de delphi_desktop empieza sin nodo en el destino."""
    shutil.rmtree(os.path.join(SCRATCH, 'McpDesktopNode'), ignore_errors=True)


def sube(puts, binario):
    """True si alguno de esos --put sube node\\<binario> (exacto: McpRunJob no es McpRunJob.exe)."""
    marca = os.path.join('node', binario) + ','
    return any(marca in p for p in puts)


try:
    r = s.call('delphi_paserver', {'command': 'remote-run', 'profile': PERFIL_MAC, 'project': DPROJ,
                                   'timeoutms': 5000})
    p = subidas()
    check('M1 remote-run con un perfil OSX64: RUN-037 con el perfil y la plataforma, y nada subido (ROJO sin el '
          'arreglo: subia node\\McpRunJob, el ELF de Linux)',
          mc.es(r, 'SR_REMOTERUN_SIN_LANZADOR_FMT') and PERFIL_MAC in r and 'OSX64' in r and not p, (r[:300], p))
    # ...y un trabajo que no se lanzo no queda entre los que valen para kill y output (D32): se apuntaba ANTES de
    # mirar el lanzador
    r = s.call('delphi_paserver', {'command': 'output', 'profile': PERFIL_MAC, 'project': DPROJ,
                                   'job': '20991231-235959999-deadbeef'})
    check('M1b ...y no deja un trabajo en la lista de los que valen (RUN-021: ninguno) (ROJO sin el arreglo)',
          mc.es(r, 'SR_REMOTERUN_JOB_AJENO_FMT')
          and mc.trozos_de_formato('SF_REMOTERUN_NINGUN_TRABAJO')[0].strip() in r, r[:400])
    sin_nodo_en_el_destino()
    r = s.call('delphi_desktop', {'command': 'screenshot', 'profile': PERFIL_MAC}, 120)
    p = subidas()
    check('M2 delphi_desktop con un perfil OSX64: DESK-021 y nada subido (ROJO sin el arreglo: subia '
          'node\\McpDesktopNode, el ELF de Linux)',
          mc.es(r, 'SR_ADBLINUX_NONODE') and not p, (r[:300], p))
    r = s.call('delphi_paserver', {'command': 'remote-run', 'profile': PERFIL_LINUX, 'project': DPROJ,
                                   'timeoutms': 5000})
    p = subidas()
    check('M3 control: con un perfil Linux64, remote-run sube el lanzador ELF',
          sube(p, 'McpRunJob') and not mc.es(r, 'SR_REMOTERUN_SIN_LANZADOR_FMT'), (r[:300], p))
    sin_nodo_en_el_destino()
    r = s.call('delphi_desktop', {'command': 'screenshot', 'profile': PERFIL_LINUX}, 120)
    p = subidas()
    check('M4 control: con un perfil Linux64, delphi_desktop sube el nodo ELF',
          sube(p, 'McpDesktopNode') and not mc.es(r, 'SR_ADBLINUX_NONODE'), (r[:300], p))
finally:
    s.mata()
mc.recoge_huellas()
mc.borra(BASE)
mc.fin('a macOS no se le sube un binario de Linux 1.29.3')
