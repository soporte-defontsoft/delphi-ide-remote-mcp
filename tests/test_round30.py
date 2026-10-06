# -*- coding: utf-8 -*-
"""Round 30 - delphi_adb_linux: el escritorio Linux de un target, como
delphi_adb da el de un Android (v0.96, nacida la noche del 18-sep despues de
construir y medir el nodo contra el Fedora real).

Aqui se comprueba el CONTRATO, que es lo que un agente ve antes de tener
target: que la tool existe, que su descripcion ENSENA el flujo (capturar,
mirar, medir, pulsar), y que rechaza con motivo claro lo que no puede hacer.
Lo que necesita maquina viva -capturar y pulsar de verdad- se prueba a mano
contra el Fedora; aqui no se finge.

Usage:  python tests/test_round30.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

# su carpeta: la jaula, su PROPIA copia del servidor (antes corria el
# compilado en su sitio) y el cebo de fuera de la jaula
CASA = mc.carpeta('round30')
DIR = os.path.join(CASA, 'jail')
os.makedirs(DIR)
EXE = mc.copia_exe(os.path.join(CASA, 'srv'))

CRLF = '\r\n'
BASE = CRLF.join([
    'unit Round30;', '',
    'interface', '',
    'type',
    '  TCosa = class',
    '  private',
    '    FValor: Integer;',
    '  public',
    '    procedure Existente;',
    '    procedure Preparada(Sender: TObject);',
    '  end;', '',
    'implementation', '',
    'procedure TCosa.Existente;',
    'begin',
    '  FValor := 1;',
    'end;', '',
    'end.', ''])

env = {}
env['DELPHI_MCP_ROOTS'] = DIR
# v0.98: delphi_adb_linux pasa por los MISMOS interruptores que remote-run
env['DELPHI_MCP_ALLOW_REMOTE_RUN'] = '1'
env['DELPHI_MCP_REMOTE_RUN_PROJECTS'] = 'all'
srv = mc.Stdio(EXE, mc.entorno(env), nombre='r28')
call = srv.call



def tool_info(nombre):
    r = srv.request('tools/list', t=30)
    for t in (r or {}).get('result', {}).get('tools', []):
        if t['name'] == nombre:
            return t
    return None

# 1.0.16: la tool es delphi_desktop (el destino es el perfil, Linux o Windows);
# delphi_adb_linux quedo un par de releases como alias en desuso y ya no existe.
T = tool_info('delphi_desktop')
check('la tool existe', T is not None, 'no aparece en tools/list')
A = tool_info('delphi_adb_linux')
# ausente del censo que SI se leyo (delphi_desktop esta): un tools/list
# fallido tambien devolvia None para el alias
check('el alias delphi_adb_linux ya no esta registrado',
      T is not None and A is None, (A or {}).get('description', '')[:120])

# 1.13.0 (revisor de tokens): lo que el parametro command ya explica no se
# repite en la descripcion; el contrato es la descripcion MAS sus parametros,
# y estos checks miran los dos
desc = (T or {}).get('description', '') + ' ' + \
    (T or {}).get('inputSchema', {}).get('properties', {}).get('command', {}).get('description', '')
check('su descripcion ensena el flujo (captura -> mide -> pulsa)',
      'screenshot' in desc and 'measured on' in desc.lower(), desc[:200])
check('avisa de que la escala la convierte el nodo',
      'node handles the screen scale' in desc, desc[:200])
check('dice que el escritorio es del TARGET, no del agente',
      'PAServer profile' in desc, desc[:200])
check('cuenta como alcanzar una ventana tapada',
      'covers' in desc.lower() or 'covered' in desc.lower(), desc[:240])

props = (T or {}).get('inputSchema', {}).get('properties', {})
for p in ('command', 'profile', 'project', 'x', 'y', 'code', 'text'):
    check('el esquema declara "%s"' % p, p in props, sorted(props))
check('el parametro x dice que se mide SOBRE la captura',
      'SCREENSHOT' in props.get('x', {}).get('description', '').upper(), props.get('x'))
check('el parametro text avisa de que con x,y pulsa antes',
      'presses there first' in props.get('text', {}).get('description', ''), props.get('text'))
check('el command cuenta que type con x,y es UN solo viaje',
      'pays the startup once' in desc, desc[:300])

check('el parametro code avisa de que son codigos Linux, no X11',
      'X11' in props.get('code', {}).get('description', ''), props.get('code'))

PROJ = os.path.join(DIR, 'Nodo.dproj')
open(PROJ, 'w', encoding='utf-8').write('<Project/>')

r = call('delphi_desktop', {"command": "bailar", "profile": "x", "project": PROJ})
check('un command inventado se rechaza con la lista buena',
      mc.rechazado(r) and mc.es(r, 'SR_ADBLINUX_CMD'), r[:160])

r = call('delphi_desktop', {"command": "tap", "profile": "x", "project": PROJ})
check('tap sin coordenadas se rechaza diciendo de donde salen',
      mc.rechazado(r) and mc.es(r, 'SR_ADBLINUX_NEEDXY'), r[:160])

r = call('delphi_desktop', {"command": "type", "profile": "x", "project": PROJ})
check('type sin texto se rechaza y explica el gesto de un solo viaje',
      mc.rechazado(r) and mc.es(r, 'SR_ADBLINUX_NEEDTEXT'), r[:200])

r = call('delphi_desktop', {"command": "key", "profile": "x", "project": PROJ})
check('key sin codigo se rechaza con ejemplos',
      mc.rechazado(r) and mc.es(r, 'SR_ADBLINUX_NEEDCODE'), r[:160])

# El cebo va en una carpeta PROPIA y se recoge. Estaba suelto en la raiz de
# %TEMP% y ahi se quedaba: un .dproj de 10 bytes llamado literalmente
# "fuera-de-la-jaula" que el 2026-09-21 resulto ser el proyecto que adoptaban
# las units de OTRAS baterias, porque la busqueda de configuracion subia ocho
# niveles sin mirar la jaula. Tres baterias pasaban en verde apoyadas en la
# basura de esta. Una bateria no deja nada en la maquina, y menos fuera de
# una jaula. Ahora vive en la carpeta de ESTA bateria, al lado de la jaula
# (no por encima: la subida no la cruza), y se recoge igual.
cebo = os.path.join(CASA, 'fuera')
os.makedirs(cebo, exist_ok=True)
fuera = os.path.join(cebo, 'fuera-de-la-jaula.dproj')
open(fuera, 'w', encoding='utf-8').write('<Project/>')
try:
    r = call('delphi_desktop', {"command": "screenshot", "profile": "x", "project": fuera})
    # por la JAULA, no por cualquier cosa (el perfil "x" tampoco existe)
    check('un proyecto fuera de la jaula se rechaza',
          mc.rechazado(r) and mc.es(r, 'SR_JAIL_FMT'), r[:160])
finally:
    mc.borra(cebo)

print()
# 1.0.18: key takes modifiers by name on both targets; an unknown one is
# refused naming the valid four, before anything travels to any target
r = call('delphi_desktop', {'command': 'key', 'profile': 'x', 'code': '37', 'modifiers': 'hyper'})
check('key modifiers=hyper rechazado nombrando los validos',
      mc.rechazado(r) and mc.es(r, 'SR_ADBLINUX_MODIFIERS_BAD_FMT') and 'hyper' in r, r[:200])
srv.cierra()
mc.fin('round30')
