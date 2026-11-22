# -*- coding: utf-8 -*-
"""D20 de la 1.29.3 (caso de campo, 17-nov): buscando un boton de una botonera en el Fedora, un agente pulso tres
vecinos -cada uno abrio un dialogo modal- porque el tooltip que dice que boton es solo se ve DESPUES de pulsar.
Ahora command=hover lleva el puntero a x,y SIN pulsar (la orden "pasa" del nodo, NodeProtocolo.inc) y la respuesta
es un recorte 1:1 alrededor del puntero -no la captura entera de un 3440, que llenaba el contexto-, con entera cada
ventana de "windows" que toca el recuadro y cabe en el (el tooltip de FMX en Linux es una ventana propia), y una
nota que dice donde quedo el puntero en ese recorte.

Sin PAServer: el paclient falso corre el lanzador real sobre un "nodo" de mentira que repite sus argumentos (linea
con etiqueta, como test_rueda_1293), dice CAPTURE= y lista dos ventanas: una grande (0,0,1280,720) y un "tooltip"
(1000,330,165,59).

  H0 el contrato: command anuncia hover (ROJO contra produccion: no hay)
  H1 hover sin y: DESK-013 que nombra hover, y el nodo NO corre
  H2 hover x=100 y=50: el nodo recibe "pasa 100 50"; recorte 0,0,580,210 (el recuadro 640x240 ajustado al lienzo),
     origen 0,0, su frame y la nota DESK-034 con el puntero en (100,50) del recorte; "windows" entera
  H3 hover x=600 y=300: el recuadro 440,220 640x240 crece hasta el "tooltip" que lo toca y cabe (725 de ancho); la
     ventana grande, que no cabe, no lo agranda; el puntero en (160,80) del recorte
  H4 con frame, x,y son de la imagen que se miro: 300,150 de 640x360 -> "pasa 600 300" y el mismo recorte de H3
  H5 clicks con hover: DESK-025, y el nodo NO corre
  H6 double-tap sin x: DESK-013 ya dice "double-tap" (decia "tap")
  H7 control: un tap sigue trayendo la captura entera (sin region ni hoverNote)

Uso:  python tests/test_hover_1293.py [ruta-a-DelphiLspMcp.exe]
"""
import os, shutil, struct, zlib
import mcp_cliente as mc
from mcp_cliente import check

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
BASE = mc.carpeta('hover_1293')
SERVERDIR = os.path.join(BASE, 'server')
os.makedirs(os.path.join(SERVERDIR, 'node'))
EXE = mc.copia_exe(SERVERDIR)
for f in ('McpRunJob', 'McpRunJob.exe'):
    shutil.copy(os.path.join(REPO, 'node', f), os.path.join(SERVERDIR, 'node', f))
RUNJOB_EXE = os.path.join(SERVERDIR, 'node', 'McpRunJob.exe')
SCRATCH = os.path.join(BASE, 'scratch')
os.makedirs(SCRATCH)
PROFILE = 'hover1293'  # SOLO de esta bateria: el tamano recordado (D17) va por workspace y perfil
NOMBRE = 'NodoHover'
PRJDIR = os.path.join(BASE, 'proj')
DPROJ = os.path.join(PRJDIR, NOMBRE + '.dproj')
DEPLOY = os.path.join(SCRATCH, NOMBRE)
CAPTURA = os.path.join(DEPLOY, 'captura.png')  # donde el servidor la pide (medido en test_escritorio_tamano_1293)
RECUERDO = mc.cache_servidor(os.path.join('desktops', '_local', PROFILE + '.txt'))
if os.path.exists(RECUERDO):
    os.remove(RECUERDO)

STUB = mc.paclient_falso('hover_1293')  # fuera de la jaula (1.27)
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


def png(w, h):
    """Un PNG de verdad (gris) de w x h: el servidor lo lee, lo recorta y lo escala."""
    filas = b''.join(b'\x00' + b'\x80\x80\x80' * w for _ in range(h))

    def trozo(tipo, datos):
        return struct.pack('>I', len(datos)) + tipo + datos + struct.pack('>I', zlib.crc32(tipo + datos) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + trozo(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) +
            trozo(b'IDAT', zlib.compress(filas, 6)) + trozo(b'IEND', b''))


def gesto(srv, cmd, **extra):
    a = {'command': cmd, 'profile': PROFILE, 'project': DPROJ, 'inline': False, 'out': os.path.join(BASE, 'g.png')}
    a.update(extra)
    return srv.call('delphi_desktop', a, t=240)


def args_del_nodo(r):
    """Lo que el nodo de mentira recibio, de su linea ARGS: en la respuesta ('' si el nodo no corrio)."""
    for linea in r.replace('\\n', '\n').replace('\\r', '\n').splitlines():
        if 'ARGS:' in linea:
            return linea.split('ARGS:', 1)[1].split('"')[0].strip()
    return ''


srv = mc.Stdio(EXE, env, nombre='hover', t=300)
try:
    tools = srv.request('tools/list', {})['result']['tools']
    d = next((x for x in tools if x['name'] == 'delphi_desktop'), {})
    cmd_desc = d.get('inputSchema', {}).get('properties', {}).get('command', {}).get('description', '')
    check('H0 el contrato: command anuncia hover (ROJO: no hay)', '| hover (' in cmd_desc, cmd_desc[:200])

    r = srv.call('delphi_create', {'kind': 'project-console', 'name': NOMBRE, 'dir': PRJDIR}, t=120)
    check('preparacion: el proyecto del nodo de mentira', not mc.fallo(r), r[:200])
    open(os.path.join(PRJDIR, NOMBRE + '.dpr'), 'w', encoding='utf-8', newline='\r\n').write(
        "program %s;\n\n{$APPTYPE CONSOLE}\n\nvar\n  I: Integer;\n  S: string;\n\nbegin\n  S := '';\n"
        "  for I := 2 to ParamCount do\n    S := S + ' ' + ParamStr(I);\n  Writeln('[NODE-990] ARGS:' + S);\n"
        "  Writeln('CAPTURE=/tmp/captura.png');\n  Writeln('  2 visible windows:');\n"
        "  Writeln('  WINDOW 0 0 1280 720 Grande');\n  Writeln('  WINDOW 1000 330 165 59 Tip');\nend.\n" % NOMBRE)
    b = mc.como_json(srv.call('delphi_build', {'project': DPROJ, 'platform': 'Win64'}, t=600)) or {}
    salida = b.get('output', '')
    check('preparacion: el nodo de mentira compila', b.get('success') is True and os.path.isfile(mc.real(salida)),
          (b.get('success'), salida, b.get('errors')))
    os.makedirs(DEPLOY)
    shutil.copy(mc.real(salida), os.path.join(DEPLOY, NOMBRE + '.exe'))
    open(CAPTURA, 'wb').write(png(1280, 720))

    r = gesto(srv, 'hover', x='100')
    check('H1 hover sin y: DESK-013 que nombra hover, y el nodo no corre',
          mc.abre(r, 'SR_DESKTOP_NEEDXY_FMT') and 'hover needs' in r and not args_del_nodo(r), r[:300])

    r = gesto(srv, 'hover', x='100', y='50')
    j = mc.como_json(r) or {}
    nota = j.get('hoverNote', '')
    check('H2 hover 100,50: "pasa 100 50", recorte 0,0,580,210 con su origen y su frame, y el puntero en (100,50)',
          args_del_nodo(r) == 'pasa 100 50' and j.get('region') == '0,0,580,210' and
          j.get('origin') == {'x': 0, 'y': 0} and j.get('frame', '').startswith('580x210@580x210+0+0') and
          mc.abre(nota, 'SN_DESKTOP_HOVER_FMT') and '(100,50)' in nota and len(j.get('windows', [])) == 2,
          (args_del_nodo(r), j.get('region'), j.get('origin'), j.get('frame'), nota[:80], len(j.get('windows', []))))

    r = gesto(srv, 'hover', x='600', y='300')
    j = mc.como_json(r) or {}
    check('H3 hover 600,300: el recuadro crece hasta el tooltip que lo toca (440,220,725,240); la grande no; '
          'el puntero en (160,80)',
          args_del_nodo(r) == 'pasa 600 300' and j.get('region') == '440,220,725,240' and
          '(160,80)' in j.get('hoverNote', ''), (args_del_nodo(r), j.get('region'), j.get('hoverNote', '')[:80]))

    r = gesto(srv, 'hover', x='300', y='150', frame='640x360@1280x720+0+0')
    j = mc.como_json(r) or {}
    check('H4 con frame: 300,150 de 640x360 -> "pasa 600 300" y el recorte de H3',
          args_del_nodo(r) == 'pasa 600 300' and j.get('region') == '440,220,725,240',
          (args_del_nodo(r), j.get('region')))

    r = gesto(srv, 'hover', x='10', y='20', clicks='3')
    check('H5 clicks con hover: DESK-025 que lo nombra, y el nodo no corre',
          mc.abre(r, 'SR_DESKTOP_NO_VA_CON_COMANDO_FMT') and '"clicks"' in r and not args_del_nodo(r), r[:300])
    r = gesto(srv, 'double-tap', y='20')
    check('H6 double-tap sin x: DESK-013 dice "double-tap needs" (decia "tap")',
          mc.abre(r, 'SR_DESKTOP_NEEDXY_FMT') and 'double-tap needs' in r, r[:200])

    r = gesto(srv, 'tap', x='600', y='300')
    j = mc.como_json(r) or {}
    check('H7 control: un tap trae la captura entera, sin region ni hoverNote',
          args_del_nodo(r) == '600 300' and 'region' not in j and 'hoverNote' not in j and
          j.get('frame', '').startswith('1280x720@1280x720+0+0'), (args_del_nodo(r), j.get('frame'), sorted(j)))
finally:
    srv.cierra()

if os.path.exists(RECUERDO):
    os.remove(RECUERDO)
mc.borra(BASE)
mc.fin('delphi_desktop pasa por encima sin pulsar 1.29.3 (D20)')
