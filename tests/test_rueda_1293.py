# -*- coding: utf-8 -*-
"""D19 de la 1.29.3 (caso de campo, 17-nov): un agente no podia recorrer una lista larga del escritorio del Fedora -
delphi_desktop no tenia rueda y el pulgar de la barra, a escala 37 %, eran 5-6 px que su drag no acertaba. Ahora
command=scroll gira la rueda "clicks" muescas en x,y (positivo abajo, negativo arriba): el servidor compone la orden
del nodo (NODO_ORDEN_RUEDA, NodeProtocolo.inc) con las muescas validadas contra el tope del protocolo, y el nodo la
gira en su escritorio (SendInput en Windows, ei_device_scroll_discrete en Linux).

Sin PAServer: el paclient falso corre el lanzador real sobre un "nodo" de mentira que esta bateria compila y que
REPITE los argumentos que recibe (menos la clave) en una linea ARGS:, y dice CAPTURE= como el de verdad. La linea
lleva etiqueta: de un gesto que salio bien, el servidor quita las del nodo que no la llevan (SalidaParaElAgente).

  R0 el contrato: delphi_desktop anuncia scroll y el parametro clicks, entero CON SIGNO: sin el minimum 0 que llevan
     los demas (un cliente que valida no mandaria -2), y x lo sigue llevando (ROJO contra produccion: no hay)
  R1 sin clicks, con 0, con 51 y con -51, y sin x: DESK-033 con el tope, y el nodo NO corre
  R2 scroll x=10 y=20 clicks=3: el nodo recibe "rueda 10 20 3" y la respuesta trae su captura (frame)
  R3 clicks=-2: "rueda 10 20 -2" (arriba)
  R4 con frame, x,y son de la imagen que se miro: 640x360 de 1280x720 -> "rueda 20 40 3"
  R5 clicks con tap y tox con scroll: DESK-025, y el nodo NO corre
  R6 control: tap sigue mandando "x y" sin orden, y drag su "arrastra" (PuntoDelGesto, el helper nuevo)

Uso:  python tests/test_rueda_1293.py [ruta-a-DelphiLspMcp.exe]
"""
import os, shutil, struct, zlib
import mcp_cliente as mc
from mcp_cliente import check

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
BASE = mc.carpeta('rueda_1293')
SERVERDIR = os.path.join(BASE, 'server')
os.makedirs(os.path.join(SERVERDIR, 'node'))
EXE = mc.copia_exe(SERVERDIR)
for f in ('McpRunJob', 'McpRunJob.exe'):
    shutil.copy(os.path.join(REPO, 'node', f), os.path.join(SERVERDIR, 'node', f))
RUNJOB_EXE = os.path.join(SERVERDIR, 'node', 'McpRunJob.exe')
SCRATCH = os.path.join(BASE, 'scratch')
os.makedirs(SCRATCH)
# un perfil SOLO de esta bateria: el tamano recordado (D17) va por workspace y perfil
PROFILE = 'rueda1293'
NOMBRE = 'NodoRueda'
PRJDIR = os.path.join(BASE, 'proj')
DPROJ = os.path.join(PRJDIR, NOMBRE + '.dproj')
DEPLOY = os.path.join(SCRATCH, NOMBRE)
CAPTURA = os.path.join(DEPLOY, 'captura.png')  # donde el servidor la pide (medido en test_escritorio_tamano_1293)
RECUERDO = mc.cache_servidor(os.path.join('desktops', '_local', PROFILE + '.txt'))
if os.path.exists(RECUERDO):
    os.remove(RECUERDO)

STUB = mc.paclient_falso('rueda_1293')  # fuera de la jaula (1.27)
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
    """Un PNG de verdad (gris) de w x h: el servidor lee su cabecera y lo escala."""
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


srv = mc.Stdio(EXE, env, nombre='rueda', t=300)
try:
    tools = srv.request('tools/list', {})['result']['tools']
    d = next((x for x in tools if x['name'] == 'delphi_desktop'), {})
    props = d.get('inputSchema', {}).get('properties', {})
    check('R0 el contrato: scroll en command, clicks entero sin minimum y x con su minimum 0 (ROJO: no hay)',
          'scroll' in props.get('command', {}).get('description', '') and
          props.get('clicks', {}).get('type') == 'integer' and 'minimum' not in props.get('clicks', {}) and
          props.get('x', {}).get('minimum') == 0, (props.get('clicks'), props.get('x', {}).get('minimum')))

    r = srv.call('delphi_create', {'kind': 'project-console', 'name': NOMBRE, 'dir': PRJDIR}, t=120)
    check('preparacion: el proyecto del nodo de mentira', not mc.fallo(r), r[:200])
    open(os.path.join(PRJDIR, NOMBRE + '.dpr'), 'w', encoding='utf-8', newline='\r\n').write(
        "program %s;\n\n{$APPTYPE CONSOLE}\n\nvar\n  I: Integer;\n  S: string;\n\nbegin\n  S := '';\n"
        "  for I := 2 to ParamCount do\n    S := S + ' ' + ParamStr(I);\n  Writeln('[NODE-990] ARGS:' + S);\n"
        "  Writeln('CAPTURE=/tmp/captura.png');\nend.\n" % NOMBRE)
    b = mc.como_json(srv.call('delphi_build', {'project': DPROJ, 'platform': 'Win64'}, t=600)) or {}
    salida = b.get('output', '')
    check('preparacion: el nodo de mentira compila', b.get('success') is True and os.path.isfile(mc.real(salida)),
          (b.get('success'), salida, b.get('errors')))
    os.makedirs(DEPLOY)
    shutil.copy(mc.real(salida), os.path.join(DEPLOY, NOMBRE + '.exe'))
    open(CAPTURA, 'wb').write(png(1280, 720))

    malos = [('sin clicks', dict(x='10', y='20')), ('clicks=0', dict(x='10', y='20', clicks='0')),
             ('clicks=51', dict(x='10', y='20', clicks='51')), ('clicks=-51', dict(x='10', y='20', clicks='-51')),
             ('sin x', dict(y='20', clicks='3'))]
    for nombre, extra in malos:
        r = gesto(srv, 'scroll', **extra)
        check('R1 %s: DESK-033 con el tope (50), y el nodo no corre' % nombre,
              mc.abre(r, 'SR_DESKTOP_SCROLL_NEED_FMT') and '50' in r and not args_del_nodo(r) and '"ran"' not in r,
              r[:300])

    r = gesto(srv, 'scroll', x='10', y='20', clicks='3')
    j = mc.como_json(r) or {}
    check('R2 scroll x=10 y=20 clicks=3: el nodo recibe "rueda 10 20 3" y vuelve su captura',
          args_del_nodo(r) == 'rueda 10 20 3' and j.get('ran') is True and j.get('frame', '').startswith('1280x720'),
          (args_del_nodo(r), r[:400]))
    r = gesto(srv, 'scroll', x='10', y='20', clicks='-2')
    check('R3 clicks=-2: "rueda 10 20 -2"', args_del_nodo(r) == 'rueda 10 20 -2', (args_del_nodo(r), r[:300]))
    r = gesto(srv, 'scroll', x=10, y=20, clicks=-2)
    check('R3b ...y como numeros JSON, lo que manda un cliente que sigue el esquema: "rueda 10 20 -2"',
          args_del_nodo(r) == 'rueda 10 20 -2', (args_del_nodo(r), r[:300]))
    r = gesto(srv, 'scroll', x='10', y='20', clicks='3', frame='640x360@1280x720+0+0')
    check('R4 con frame: 640x360 de 1280x720 -> "rueda 20 40 3"', args_del_nodo(r) == 'rueda 20 40 3',
          (args_del_nodo(r), r[:300]))

    r = gesto(srv, 'tap', x='10', y='20', clicks='3')
    check('R5 clicks con tap: DESK-025 que lo nombra, y el nodo no corre',
          mc.abre(r, 'SR_DESKTOP_NO_VA_CON_COMANDO_FMT') and '"clicks"' in r and not args_del_nodo(r), r[:300])
    r = gesto(srv, 'scroll', x='10', y='20', clicks='3', tox='5')
    check('R5b tox con scroll: DESK-025, y el nodo no corre',
          mc.abre(r, 'SR_DESKTOP_NO_VA_CON_COMANDO_FMT') and '"tox"' in r and not args_del_nodo(r), r[:300])

    r = gesto(srv, 'tap', x='10', y='20', frame='640x360@1280x720+0+0')
    check('R6 control: tap con frame sigue mandando "20 40", sin orden', args_del_nodo(r) == '20 40',
          (args_del_nodo(r), r[:300]))
    r = gesto(srv, 'drag', x='10', y='20', tox='30', toy='40', frame='640x360@1280x720+0+0')
    check('R6b control: drag con frame, "arrastra 20 40 60 80"', args_del_nodo(r) == 'arrastra 20 40 60 80',
          (args_del_nodo(r), r[:300]))

    # revisor del paisaje de la 1.29.3: un [NumeroComoTexto] pasa por LA regla del entero del binder (MotivoEntero)
    # y llega canonico. Cada tool lo leia con StrToIntDef: 10.0 (entero para JSON Schema y para esa regla) era -1
    r = gesto(srv, 'tap', x=10.0, y=20)
    check('R7 tap x=10.0 (un numero JSON entero): el nodo recibe "10 20" (ROJO sin el arreglo: "-1 20")',
          args_del_nodo(r) == '10 20', (args_del_nodo(r), r[:300]))
    r = gesto(srv, 'scroll', x=10, y=20, clicks=2.0)
    check('R7b scroll clicks=2.0: "rueda 10 20 2" (ROJO sin el arreglo: DESK-033)',
          args_del_nodo(r) == 'rueda 10 20 2', (args_del_nodo(r), r[:300]))
    r = gesto(srv, 'tap', x='-5', y='20')
    check('R7c tap x=-5: la regla del entero lo niega (sin signo: minimum 0) y el nodo no corre (ROJO sin el '
          'arreglo: el nodo recibia "-5 20")', mc.es(r, 'SR_SYS_PARAM_VALUE_FMT') and '"x"' in r.replace('\\"', '"')
          and not args_del_nodo(r), r[:300])
    r = gesto(srv, 'scroll', x='10', y='20', clicks=2.5)
    check('R7d clicks=2.5 no es entero: la regla lo niega por su nombre y el nodo no corre (sin el arreglo: '
          'DESK-033, que pedia "clicks" como si no estuviera)',
          mc.es(r, 'SR_SYS_PARAM_VALUE_FMT') and not args_del_nodo(r), r[:300])
finally:
    srv.cierra()

if os.path.exists(RECUERDO):
    os.remove(RECUERDO)
mc.borra(BASE)
mc.fin('delphi_desktop gira la rueda 1.29.3 (D19)')
