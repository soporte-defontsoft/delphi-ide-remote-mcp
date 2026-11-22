# -*- coding: utf-8 -*-
"""D17 de la 1.29.3 (caso de campo, 17-nov): el escritorio de un perfil cambio de tamano - de 1920x1080 a 3440x1440,
alguien entro por escritorio remoto desde un ultrapanoramico - y el agente siguio con las posiciones de antes ("como
ayer"): su primer toque cayo al lado y tardo veinte minutos en abrir un panel. delphi_desktop no decia nada. Ahora el
servidor recuerda, por workspace y por perfil y en SU casa (la cache: FicheroDeEscritorioVisto), el tamano del
escritorio entero de la ultima captura, y si la de ahora es otro lo dice: desktopSizeNote (DESK-030).

Sin PAServer: el paclient falso (tests/paclient_stub.py) corre el lanzador real sobre un "nodo" de mentira que esta
bateria compila (como test_desktop_ran_1291), que solo dice CAPTURE=/tmp/captura.png; la bateria pone ahi un PNG de
verdad del tamano que toca.

  Z0 control: la primera captura (1920x1080), sin nada de antes: sin nota
  Z1 control: otra del mismo tamano: sin nota
  Z2 la siguiente es de 3440x1440: desktopSizeNote DESK-030 con los dos tamanos (ROJO contra produccion: nada)
  Z3 control: otra de 3440x1440: sin nota (ya lo sabe)
  Z4 la captura de un GESTO (tap) tambien: de vuelta a 1920x1080, la nota
  Z5 sobrevive a un reinicio: otro servidor con la misma casa, una captura de 3440x1440 dice que era 1920x1080
  Z6 lo recordado vive en la casa del servidor (su cache), nunca en la raiz del agente

Uso:  python tests/test_escritorio_tamano_1293.py [ruta-a-DelphiLspMcp.exe]
"""
import os, shutil, struct, zlib
import mcp_cliente as mc
from mcp_cliente import check

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
BASE = mc.carpeta('escritorio_tamano_1293')
SERVERDIR = os.path.join(BASE, 'server')
os.makedirs(os.path.join(SERVERDIR, 'node'))
EXE = mc.copia_exe(SERVERDIR)
for f in ('McpRunJob', 'McpRunJob.exe'):
    shutil.copy(os.path.join(REPO, 'node', f), os.path.join(SERVERDIR, 'node', f))
RUNJOB_EXE = os.path.join(SERVERDIR, 'node', 'McpRunJob.exe')
SCRATCH = os.path.join(BASE, 'scratch')
os.makedirs(SCRATCH)
# un perfil SOLO de esta bateria: lo recordado va por workspace y perfil, y la cache de las baterias es comun
PROFILE = 'tamano1293'
NOMBRE = 'NodoTamano'
PRJDIR = os.path.join(BASE, 'proj')
DPROJ = os.path.join(PRJDIR, NOMBRE + '.dproj')
DEPLOY = os.path.join(SCRATCH, NOMBRE)
# donde el servidor la pide (medido con el registro del paclient falso: --get=NodoTamano/captura.png): la carpeta
# desplegada del proyecto del nodo, con el nombre de la que dijo CAPTURE=
CAPTURA = os.path.join(DEPLOY, 'captura.png')
# lo recordado: <cache>\desktops\<carpeta del workspace>\<perfil>.txt; por stdio no hay token y el workspace es '_local'
RECUERDO = mc.cache_servidor(os.path.join('desktops', '_local', PROFILE + '.txt'))
if os.path.exists(RECUERDO):
    os.remove(RECUERDO)  # de una vuelta anterior: Z0 mide "sin nada de antes"

STUB = mc.paclient_falso('escritorio_tamano_1293')  # fuera de la jaula (1.27)
env = mc.entorno()
env['DELPHI_MCP_ROOTS'] = BASE
env['DELPHI_MCP_PACLIENT'] = STUB
env['MCP_STUB_SCRATCH'] = SCRATCH
env['MCP_STUB_RUNJOB_EXE'] = RUNJOB_EXE
env['DELPHI_MCP_ALLOW_REMOTE_RUN'] = '1'
env['DELPHI_MCP_REMOTE_RUN_PROJECTS'] = DPROJ
env['DELPHI_MCP_DESKTOP_HOSTS'] = '*'
_ad, _host = mc.appdata_perfil(BASE, PROFILE, '127.0.0.1')
# revisor del paisaje de la 1.29.3: dos perfiles cuyo Slug es el mismo ('_' pasa a '-'): compartian lo recordado
CHOQUES = ('choque_1293', 'choque-1293')
for _p in CHOQUES:
    mc.appdata_perfil(BASE, _p, '127.0.0.1')
DESKTOPS = os.path.dirname(RECUERDO)


def sin_recuerdos_de_choque():
    if os.path.isdir(DESKTOPS):
        for _f in os.listdir(DESKTOPS):
            if _f.startswith('choque'):
                os.remove(os.path.join(DESKTOPS, _f))


sin_recuerdos_de_choque()
env['APPDATA'] = _ad
env['DELPHI_MCP_REMOTE_HOSTS'] = _host


def png(w, h):
    """Un PNG de verdad (gris) de w x h: el servidor lee su cabecera y lo escala."""
    filas = b''.join(b'\x00' + b'\x80\x80\x80' * w for _ in range(h))

    def trozo(tipo, datos):
        return struct.pack('>I', len(datos)) + tipo + datos + struct.pack('>I', zlib.crc32(tipo + datos) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + trozo(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) +
            trozo(b'IDAT', zlib.compress(filas, 6)) + trozo(b'IEND', b''))


PNG_1920 = png(1920, 1080)
PNG_3440 = png(3440, 1440)


def captura(srv, datos, args=None):
    open(CAPTURA, 'wb').write(datos)
    a = {'command': 'screenshot', 'profile': PROFILE, 'project': DPROJ, 'inline': False,
         'out': os.path.join(BASE, 'salida.png')}
    a.update(args or {})
    return mc.como_json(srv.call('delphi_desktop', a, t=240)) or {}


srv = mc.Stdio(EXE, env, nombre='escritorio-tamano', t=300)
try:
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': NOMBRE, 'dir': PRJDIR}, t=120)
    check('preparacion: el proyecto del nodo de mentira', not mc.fallo(r), r[:200])
    open(os.path.join(PRJDIR, NOMBRE + '.dpr'), 'w', encoding='utf-8', newline='\r\n').write(
        "program %s;\n\n{$APPTYPE CONSOLE}\n\nbegin\n  Writeln('CAPTURE=/tmp/captura.png');\nend.\n" % NOMBRE)
    b = mc.como_json(srv.call('delphi_build', {'project': DPROJ, 'platform': 'Win64'}, t=600)) or {}
    salida = b.get('output', '')
    check('preparacion: el nodo de mentira compila', b.get('success') is True and os.path.isfile(mc.real(salida)),
          (b.get('success'), salida, b.get('errors')))
    os.makedirs(DEPLOY)
    shutil.copy(mc.real(salida), os.path.join(DEPLOY, NOMBRE + '.exe'))

    j = captura(srv, PNG_1920)
    check('Z0 control: la primera captura (1920x1080), sin nada de antes: sin nota',
          'desktopSizeNote' not in j and '@1920x1080+0+0' in j.get('frame', ''), j)
    j = captura(srv, PNG_1920)
    # 'frame' in j: una captura que fallo tampoco trae nota (revisor del paisaje del diff de la 1.29.3, 21-nov)
    check('Z1 control: otra del mismo tamano, sin nota', 'frame' in j and 'desktopSizeNote' not in j, j)
    j = captura(srv, PNG_3440)
    nota = j.get('desktopSizeNote', '')
    check('Z2 la siguiente es de 3440x1440: DESK-030 con los dos tamanos (ROJO: nada)',
          mc.abre(nota, 'SN_DESKTOP_CAMBIO_DE_TAMANO_FMT') and '1920x1080' in nota and '3440x1440' in nota, j)
    j = captura(srv, PNG_3440)
    check('Z3 control: otra de 3440x1440, sin nota (ya lo sabe)', 'frame' in j and 'desktopSizeNote' not in j, j)
    open(CAPTURA, 'wb').write(PNG_1920)
    j = mc.como_json(srv.call('delphi_desktop', {'command': 'tap', 'profile': PROFILE, 'project': DPROJ,
                                                 'x': '10', 'y': '10', 'inline': False,
                                                 'out': os.path.join(BASE, 'gesto.png')}, t=240)) or {}
    nota = j.get('desktopSizeNote', '')
    check('Z4 la captura de un gesto tambien: de vuelta a 1920x1080, la nota',
          mc.abre(nota, 'SN_DESKTOP_CAMBIO_DE_TAMANO_FMT') and '3440x1440' in nota and '1920x1080' in nota, j)
finally:
    srv.cierra()

srv = mc.Stdio(EXE, env, nombre='escritorio-tamano-2', t=300)
try:
    j = captura(srv, PNG_3440)
    nota = j.get('desktopSizeNote', '')
    check('Z5 sobrevive a un reinicio: otro servidor, una de 3440x1440 dice que era 1920x1080',
          mc.abre(nota, 'SN_DESKTOP_CAMBIO_DE_TAMANO_FMT') and '1920x1080' in nota, j)
    dentro = [os.path.join(d, f) for d, _, fs in os.walk(BASE) for f in fs if f == PROFILE + '.txt']
    check('Z6 lo recordado vive en la casa del servidor (su cache), nunca en la raiz del agente',
          os.path.isfile(RECUERDO) and open(RECUERDO, encoding='utf-8-sig').read().strip() == '3440x1440'
          and not dentro, (RECUERDO, dentro))

    # el paso 1 de D17, sin tocar el nodo: (a) el frame lleva el escritorio entero de la captura detras, '/WxH'
    # (FrameOf; el de una con region= no es su srcWxsrcH); (b) ANTES de pulsar, un frame de otro escritorio que el
    # recordado se niega, solo cuando se sabe; (c) DESPUES, la captura del gesto de otro tamano que su frame, se dice
    check('F1 (a) la captura entera lleva el escritorio en el frame: .../3440x1440',
          j.get('frame', '').endswith('@3440x1440+0+0/3440x1440'), j.get('frame'))
    j = captura(srv, PNG_3440, {'region': '10,20,200,100'})
    check('F1b ...y la de una region tambien, detras de su recorte: 200x100@200x100+10+20/3440x1440',
          j.get('frame') == '200x100@200x100+10+20/3440x1440', j.get('frame'))

    def toque(frame, x='10', y='10'):
        return mc.como_json(srv.call('delphi_desktop', {'command': 'tap', 'profile': PROFILE, 'project': DPROJ,
                                                        'x': x, 'y': y, 'frame': frame, 'inline': False,
                                                        'out': os.path.join(BASE, 'gesto.png')}, t=240)) or {}

    j = toque('1280x536@3440x1440+0+0')
    check('F2 (a) un frame de antes, sin escritorio detras: pulsa como siempre, sin negativa ni nota',
          j.get('ran') is True and 'gestureFrameNote' not in j and 'error' not in j, j)
    r = srv.call('delphi_desktop', {'command': 'tap', 'profile': PROFILE, 'project': DPROJ, 'x': '10', 'y': '10',
                                    'frame': '1280x720@1920x1080+0+0/1920x1080'}, t=240)
    check('F3 (b) recordado 3440x1440 y un frame de 1920x1080: DESK-031 y NO pulsa (ROJO: CAPT-004 en produccion)',
          mc.abre(r, 'SR_DESKTOP_FRAME_OTRO_ESCRITORIO_FMT') and '1920x1080' in r and '3440x1440' in r
          and '"ran"' not in r, r[:400])
    j = toque('1280x536@3440x1440+0+0/3440x1440')
    check('F4 (b) control: el frame del escritorio recordado pulsa, sin nota', j.get('ran') is True
          and 'gestureFrameNote' not in j, j)
    open(CAPTURA, 'wb').write(PNG_1920)  # el escritorio cambia sin una captura en medio
    j = toque('1280x536@3440x1440+0+0/3440x1440')
    nota = j.get('gestureFrameNote', '')
    check('F5 (c) cambio sin captura en medio: pulsa, y su captura (1920x1080) contra su frame (3440x1440) se dice',
          j.get('ran') is True and mc.abre(nota, 'SN_DESKTOP_GESTO_OTRO_ESCRITORIO_FMT') and '1920x1080' in nota
          and '3440x1440' in nota and 'desktopSizeNote' in j, j)
    if os.path.exists(RECUERDO):
        os.remove(RECUERDO)
    j = toque('1280x536@3440x1440+0+0/3440x1440')
    check('F6 (b) sin nada recordado no se adivina: pulsa', j.get('ran') is True and 'error' not in j, j)

    # revisor del paisaje de la 1.29.3. Lo recordado es ahora 1920x1080 (la captura de F6). Regla 7: DESK-031 lo
    # recorrian solo los tap; los demas gestos con x,y pasan por el mismo sitio
    OTRO = '1280x536@3440x1440+0+0/3440x1440'
    for g, extra in (('double-tap', {}), ('drag', {'tox': '20', 'toy': '20'}), ('scroll', {'clicks': 2}),
                     ('hover', {}), ('type', {'text': 'a'})):
        a = {'command': g, 'profile': PROFILE, 'project': DPROJ, 'x': '10', 'y': '10', 'frame': OTRO}
        a.update(extra)
        r = srv.call('delphi_desktop', a, t=240)
        check('F7 %s con el frame de otro escritorio: DESK-031 y no se hace' % g,
              mc.abre(r, 'SR_DESKTOP_FRAME_OTRO_ESCRITORIO_FMT') and '"ran"' not in r, r[:300])
    j = mc.como_json(srv.call('delphi_desktop', {'command': 'type', 'profile': PROFILE, 'project': DPROJ,
                                                 'text': 'a', 'frame': OTRO, 'inline': False,
                                                 'out': os.path.join(BASE, 'gesto.png')}, t=240)) or {}
    check('F8 type SIN x,y con un frame: no apunta a nada, ni DESK-031 ni DESK-032 (ROJO sin el arreglo: DESK-032)',
          j.get('ran') is True and 'error' not in j and 'gestureFrameNote' not in j, j)

    # R3: dos perfiles con el mismo Slug, cada uno con lo suyo
    open(CAPTURA, 'wb').write(PNG_1920)
    j = mc.como_json(srv.call('delphi_desktop', {'command': 'screenshot', 'profile': CHOQUES[0], 'project': DPROJ,
                                                 'inline': False, 'out': os.path.join(BASE, 'salida.png')},
                              t=240)) or {}
    # sin esta captura no hay nada que heredar y F9 pasaria aunque se quitara NombreSinChoques (revisor del paisaje)
    check('F9 fixture: la captura de choque_1293 se hizo (deja su tamano recordado)', 'frame' in j, j)
    open(CAPTURA, 'wb').write(PNG_3440)
    j = mc.como_json(srv.call('delphi_desktop', {'command': 'screenshot', 'profile': CHOQUES[1], 'project': DPROJ,
                                                 'inline': False, 'out': os.path.join(BASE, 'salida.png')},
                              t=240)) or {}
    check('F9 la primera captura de choque-1293 no hereda lo de choque_1293 (mismo Slug): sin DESK-030 (ROJO sin el '
          'arreglo)', 'frame' in j and 'desktopSizeNote' not in j, j)
finally:
    srv.cierra()

# R6: la casa se lee DESPUES de la puerta: un servidor que no deja ese escritorio (DesktopHosts sin su host) dice
# su negativa, no DESK-031 (que miraba lo recordado antes de preguntar). Lo recordado de PROFILE: 1920x1080
env_no = dict(env)
env_no['DELPHI_MCP_DESKTOP_HOSTS'] = '192.0.2.1'
srv = mc.Stdio(EXE, env_no, nombre='escritorio-tamano-3', t=300)
try:
    r = srv.call('delphi_desktop', {'command': 'tap', 'profile': PROFILE, 'project': DPROJ, 'x': '10', 'y': '10',
                                    'frame': '1280x536@3440x1440+0+0/3440x1440'}, t=240)
    check('F10 un escritorio que el operador no deja: su negativa, no DESK-031 (ROJO sin el arreglo: DESK-031)',
          mc.rechazado(r) and not mc.abre(r, 'SR_DESKTOP_FRAME_OTRO_ESCRITORIO_FMT') and '"ran"' not in r, r[:300])
finally:
    srv.cierra()
sin_recuerdos_de_choque()

if os.path.exists(RECUERDO):
    os.remove(RECUERDO)
mc.borra(BASE)
mc.fin('delphi_desktop dice que el escritorio cambio de tamano 1.29.3 (D17)')
