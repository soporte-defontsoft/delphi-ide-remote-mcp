# -*- coding: utf-8 -*-
"""La captura de delphi_desktop sin out=, trabajo nuestro (1.18.2, puntos 2i
y 2af).

Sin out=, la captura es nuestra: se baja a nuestra casa de capturas (la
temporal del servidor, por workspace y agente) y se devuelve; nunca toca el
workspace. Hasta la 1.18.2 la casa estaba en el __delphi-temp de la primera
raiz escribible y la colocaba un escritor que preguntaba a la jaula: a un
agente confinado la jaula le niega __delphi-temp y, sin raiz escribible, la
temporal del servidor esta fuera de las raices. Medido contra el Zorin el
11-oct-2026: DESK-019 en los dos (con GUARD-015 y GUARD-002 dentro).

Necesita el Zorin encendido (perfil zorin-desktop, 192.168.1.177) con una
sesion grafica: si no contesta, la bateria lo dice (NOTA) y solo mide D0c.
Solo captura: nunca pulsa ni teclea en su escritorio. Por stdio la captura
sin out= viaja EN LINEA (2ai): se mide por la respuesta (consumed) y por la
carpeta del agente en nuestra casa.

  D0c sin destino (un perfil que no existe): inline=false sin out= por stdio
      se niega (CAPT-012) ANTES de la puerta de control remoto (2ai)
  D0  control: raiz escribible, sin out=: la captura en nuestra casa, nada en la raiz
  D0b inline=false sin out= contra el Zorin: CAPT-012 y nada en la casa (2ai)
  D1  agente confinado, sin out=: en nuestra casa, con su carpeta (antes DESK-019)
  D2  sin raiz escribible, sin out=: en nuestra casa (antes DESK-019)
  D3  confinado y con window= (el recorte, que se coloca desde memoria):
      en su casa, con el tamano de la ventana; si el Zorin no tiene ninguna
      ventana con rectangulo, NOTA
  D4  control de la jaula: un out= fuera de las raices se sigue negando
  D4b confinado y con out= en SU carpeta: se coloca alli (el out= es del
      agente y lo juzga la jaula, no la casa: colocarlo con el lugar de la
      casa lo negaria)
  D5  la raiz en 8.3 y su entrada de ReadOnlyPaths en largo: la captura en la
      temporal del servidor, NO dentro de la raiz de solo lectura (la casa
      comparaba ReadOnlyPaths por su texto crudo; revisor del 2i, medido)
  En cada una, ninguna carpeta de descarga (__tmp-) se queda en la casa.

Uso:  python tests/test_desktop_casa_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import atexit, glob, json, os, shutil
import mcp_cliente as mc
from mcp_cliente import check

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PERFIL, HOST = 'zorin-desktop', '192.168.1.177'
BASE = mc.carpeta('desktop_casa_1182')
atexit.register(mc.borra, BASE)
JAIL = os.path.join(BASE, 'jail')
SOLO = os.path.join(BASE, 'solo')
for d in (JAIL, SOLO):
    os.makedirs(d, exist_ok=True)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
# el nodo viaja con el servidor (Lsp.RemoteRun: ServerDir('node'))
shutil.copytree(os.path.join(REPO, 'node'), os.path.join(BASE, 'srv', 'node'))
COMUN = {'DELPHI_MCP_REMOTE_HOSTS': HOST, 'DELPHI_MCP_ALLOW_REMOTE_RUN': '1',
         'DELPHI_MCP_REMOTE_RUN_PROJECTS': 'all'}


def entorno(extra):
    e = dict(COMUN)
    e.update(extra)
    return mc.entorno(e)


def J(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


def captura(srv, **kw):
    # en linea y pequena: por stdio una captura sin out= solo sale asi (2ai de
    # la 1.18.2: inline=false se niega antes de capturar). Que cayo en NUESTRA
    # casa lo dice consumed (solo se consume una nuestra) y la carpeta del
    # agente que alli queda
    a = {'command': 'screenshot', 'profile': PERFIL, 'maxwidth': 320}
    a.update(kw)
    return srv.call('delphi_desktop', a, t=240)


def en_casa(r):
    return J(r).get('consumed') is True and J(r).get('inlineImage') is True


CASA_ANA = os.path.join(mc.casa_de_capturas(os.path.join(BASE, 'srv'), 'ana', ''), 'desktop')


def nuevas(patron, antes):
    return sorted(set(glob.glob(patron, recursive=True)) - antes)


# nuestra casa de capturas (la temporal del servidor), y lo que NO debe haber
# nunca: una captura en el workspace
CASA_SRV = os.path.join(mc.casa_de_capturas(os.path.join(BASE, 'srv')), '**', 'desktop', '*.png')
TEMP_JAULA = os.path.join(JAIL, mc.TEMPORALES)


def bajadas():
    # las carpetas de descarga (Lsp.Casa: '__tmp-' + 8 hex) que se hubieran quedado
    return [p for base in (JAIL, os.path.join(BASE, 'srv'), SOLO)
            for p in glob.glob(os.path.join(base, '**', '__tmp-*'), recursive=True)]

# ------------------------------------------- servidor A: raiz escribible
srv = mc.Stdio(EXE, entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='ana', t=240)
try:
    # D0c: la negativa del 2ai no necesita destino - llega antes de la puerta
    # de control remoto (CAPT-012 abre la respuesta) - y se mide siempre
    r0 = srv.call('delphi_desktop', {'command': 'screenshot', 'profile': 'zz-no-existe', 'inline': False}, t=60)
    check('D0c inline=false sin out= por stdio, sin destino: CAPT-012 ANTES de la puerta de control remoto (2ai)',
          mc.abre(r0, 'SR_CAPTURE_SIN_SALIDA'), r0[:300])
    st = srv.call('delphi_desktop', {'command': 'status', 'profile': PERFIL}, t=120)
    # vivo = su status dice reachable (desde la 1.22.1 un destino caido es reachable=false, no un fallo)
    vivo = mc.como_json(st).get('reachable') is True
    if vivo:
        antes = set(glob.glob(CASA_SRV, recursive=True))
        r = captura(srv)
        n = nuevas(CASA_SRV, antes)
        check('D0 control: raiz escribible, sin out=: en nuestra casa, nada en la raiz, sin bajada que se quede',
              not mc.fallo(r) and en_casa(r) and not n and not os.path.exists(TEMP_JAULA) and not bajadas(),
              (r[:300], n, os.path.exists(TEMP_JAULA), bajadas()))
        # 2ai de la 1.18.2: inline=false sin out= por stdio no tendria por donde
        # salir: se niega ANTES de ir al destino (CAPT-012), sin nada en la casa
        antes = set(glob.glob(CASA_SRV, recursive=True))
        r2 = captura(srv, inline=False)
        check('D0b inline=false sin out= por stdio: CAPT-012 antes de ir al destino, nada en nuestra casa (2ai)',
              mc.rechazado(r2) and mc.es(r2, 'SR_CAPTURE_SIN_SALIDA') and not nuevas(CASA_SRV, antes),
              r2[:300])
        ventanas = [v for v in (J(r).get('windows') or []) if isinstance(v, dict) and
                    v.get('title') and (v.get('w') or v.get('width'))]
        # D4: el out= es del agente y lo juzga la jaula, como siempre
        r = captura(srv, out=os.path.join(SOLO, 'x.png'))
        check('D4 control de la jaula: un out= fuera de las raices se sigue negando, sin dejar nada',
              mc.rechazado(r) and not os.path.exists(os.path.join(SOLO, 'x.png')), r[:300])
finally:
    srv.cierra()

if not vivo:
    print('NOTA el Zorin (%s, %s) no contesta: la bateria no mide nada. %s' % (PERFIL, HOST, st[:200]))
    mc.fin('desktop casa 1182', sin_checks='el Zorin no contesta (perfil %s)' % PERFIL)

# ------------------------------------------- servidor B: agente confinado
srv = mc.Stdio(EXE, entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_AGENT_CONFINEMENT': '1'}),
               nombre='ana', t=240)
try:
    # la carpeta de ana la dejo D0 (el servidor A se llama igual): sin
    # borrarla, isdir pasaria en vacio (revisor del 2ai)
    shutil.rmtree(CASA_ANA, ignore_errors=True)
    antes = set(glob.glob(CASA_SRV, recursive=True))
    r = captura(srv)
    n = nuevas(CASA_SRV, antes)
    check('D1 agente confinado, sin out=: en nuestra casa, con su carpeta, nada en la raiz (antes DESK-019)',
          not mc.fallo(r) and en_casa(r) and not n and os.path.isdir(CASA_ANA) and
          not os.path.exists(TEMP_JAULA) and not bajadas(), (r[:400], n, os.path.isdir(CASA_ANA), bajadas()))
    SUYA = os.path.join(JAIL, 'ana', 'caps')
    r = captura(srv, out=SUYA + os.sep)
    n = glob.glob(os.path.join(SUYA, '*.png'))
    check('D4b confinado y con out= en SU carpeta: se coloca alli (lo juzga la jaula)',
          not mc.fallo(r) and len(n) == 1 and not bajadas(), (r[:400], n, bajadas()))
    if ventanas:
        titulo = ventanas[0]['title']
        antes = set(glob.glob(CASA_SRV, recursive=True))
        r = captura(srv, window=titulo)
        n = nuevas(CASA_SRV, antes)
        j = J(r)
        check('D3 confinado y con window=: el recorte en su casa',
              not mc.fallo(r) and en_casa(r) and not n and j.get('croppedFrom') and j.get('origin') is not None,
              (titulo, r[:400], n))
    else:
        print('NOTA D3 sin medir: el Zorin no lista ninguna ventana con rectangulo (window= necesita una)')
finally:
    srv.cierra()

# ------------------------------------------- servidor C: sin raiz escribible
srv = mc.Stdio(EXE, entorno({'DELPHI_MCP_ROOTS': SOLO, 'DELPHI_MCP_READONLY_PATHS': SOLO}),
               nombre='ana', t=240)
try:
    antes = set(glob.glob(CASA_SRV, recursive=True))
    r = captura(srv)
    n = nuevas(CASA_SRV, antes)
    check('D2 sin raiz escribible, sin out=: la captura en nuestra casa (antes DESK-019)',
          not mc.fallo(r) and en_casa(r) and not n and not bajadas(), (r[:400], n, bajadas()))
finally:
    srv.cierra()

# ------------- servidor D: la raiz en 8.3 y su entrada de solo lectura en largo
srv = mc.Stdio(EXE, entorno({'DELPHI_MCP_ROOTS': SOLO, 'DELPHI_MCP_READONLY_PATHS': mc.larga(SOLO)}),
               nombre='ana', t=240)
try:
    antes = set(glob.glob(CASA_SRV, recursive=True))
    r = captura(srv)
    n = nuevas(CASA_SRV, antes)
    check('D5 la raiz en 8.3 y su entrada en largo: en nuestra casa, NO dentro de la raiz',
          SOLO.lower() != mc.larga(SOLO).lower() and not mc.fallo(r) and en_casa(r) and not n and
          not os.path.exists(os.path.join(SOLO, mc.TEMPORALES)),
          (r[:400], n, os.path.exists(os.path.join(SOLO, mc.TEMPORALES))))
finally:
    srv.cierra()

mc.fin('desktop casa 1182')
