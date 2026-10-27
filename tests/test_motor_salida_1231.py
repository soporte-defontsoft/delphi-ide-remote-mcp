# -*- coding: utf-8 -*-
"""V91 de la 1.23.1: el motor en Win32 no resolvia NADA de un programa que usa
LockBox (uTPLb_Codec), y el Code Insight del IDE si (David lo vio en el IDE,
27-oct-2026). Medido ese dia en esta maquina (13.1) con el motor a pelo: con
los ajustes que escribe el IDE resuelve y con los nuestros no, y de todo lo que
los diferencia decide UNA opcion, -NU (la carpeta de salida de las unidades),
que no dabamos. Con -NU apuntando a una carpeta VACIA ya resuelve y el motor
no escribe nada en ella; sin ella falla aunque no haya ningun .dcu junto a las
fuentes de LockBox. En Win64 no hace falta. La carpeta es nuestra (la cache
del servidor, lsp-dcu), nunca la del proyecto: el motor es proceso nuestro.

  N1 los ajustes fabricados llevan -NU, a la cache del servidor y no al
     proyecto (ROJO contra 1.23.x: no habia -NU)
  N2 con uTPLb_Codec en el uses del .dpr, hover de Application resuelve
     (ROJO contra 1.23.x)
  N3 ...y completar tras "Application." da sus miembros (lo que David vio en
     el IDE)
  N4 la carpeta de -NU sigue vacia despues: el motor no escribe en ella (lo
     medido, vigilado aqui)
  C1 control: un VCL sin LockBox resuelve Application (verde con los dos)

N2 y N3 piden LockBox (GetIt, LockBox-13) en la biblioteca del IDE: sin el,
se dice y no se miden.

Uso:  python tests/test_motor_salida_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import json, os, re, time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('motor_salida_1231')
JAIL = os.path.join(BASE, 'jail')
APPDATA = os.path.join(BASE, 'appdata')
os.makedirs(JAIL)
os.makedirs(APPDATA)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'LOCALAPPDATA': APPDATA}), nombre='motor-salida', t=300)
SALIDA = mc.cache_servidor('lsp-dcu', APPDATA)
LINEA = '  Application.Initialize;'


def vcl(nombre):
    # en Win32: un proyecto nuevo nace con Win64 seleccionada, y en Win64 el
    # motor resuelve sin -NU (medido; la primera pasada de esta bateria salio
    # verde en N2 contra 1.23.x por eso)
    d = os.path.join(JAIL, nombre.lower())
    r = s.call('delphi_create', {'kind': 'project-vcl', 'name': nombre, 'dir': d}, t=120)
    a = s.call('delphi_config', {'command': 'set-active', 'project': os.path.join(d, nombre + '.dproj'),
                                 'platform': 'Win32'})
    check('preparacion: VCL %s en Win32' % nombre, not mc.fallo(r) and not mc.fallo(a), (r[:200], a[:200]))
    return os.path.join(d, nombre + '.dpr')


def posicion(dpr):
    for i, l in enumerate(open(dpr, encoding='utf-8-sig').read().splitlines()):
        if l == LINEA:
            return i, l.index('Application')
    return -1, -1


def hover(dpr, tope=90):
    # el motor arranca con la primera pregunta: se repite hasta que contesta o
    # se agota el tope (contra 1.23.x no contesta nunca)
    l, c = posicion(dpr)
    t0 = time.time()
    while True:
        r = s.call('delphi_hover', {'path': dpr, 'line': l, 'character': c}, t=120)
        if 'TApplication' in r or time.time() - t0 > tope:
            return r
        time.sleep(3)


def ajustes(dpr):
    fab = mc.ajustes_fabricados(dpr, APPDATA)
    return json.load(open(fab, encoding='utf-8-sig'))['settings'] if fab else {}


def opcion(dpr, letra):
    m = re.search(r'-%s"([^"]*)"' % letra, ajustes(dpr).get('dccOptions', ''))
    return m.group(1) if m else None


try:
    sin = vcl('Sin')
    r = hover(sin)
    check('C1 control: un VCL sin LockBox resuelve Application', 'TApplication' in r, r[:300])

    con = vcl('ConLb')
    b = open(con, 'rb').read()
    assert b.count(b'  Vcl.Forms,\r\n') == 1, b[:200]
    open(con, 'wb').write(b.replace(b'  Vcl.Forms,\r\n', b'  Vcl.Forms,\r\n  uTPLb_Codec,\r\n'))
    r = hover(con)
    check('preparacion: el motor corre con el compilador de Win32', ajustes(con).get('dllname', '').startswith('dcc32'),
          ajustes(con).get('dllname'))
    nu = opcion(con, 'NU')
    larga = lambda p: os.path.normcase(mc.larga(p))
    check('N1 los ajustes llevan -NU, a la cache del servidor y no al proyecto (ROJO contra 1.23.x)',
          nu is not None and larga(nu) == larga(SALIDA) and not larga(nu).startswith(larga(JAIL)), (nu, SALIDA))
    lockbox = any(os.path.isfile(os.path.join(p, 'uTPLb_Codec.pas')) for p in (opcion(con, 'U') or '').split(';'))
    if lockbox:
        check('N2 con uTPLb_Codec en el uses, hover de Application resuelve (ROJO contra 1.23.x)',
              'TApplication' in r, r[:300])
        l, c = posicion(con)
        r = s.call('delphi_completion', {'path': con, 'line': l, 'character': c + len('Application.'),
                                         'trigger': '.'}, t=120)
        check('N3 ...y completar tras "Application." da sus miembros', 'BringToFront' in r, r[:300])
    else:
        print('  (N2 y N3 sin medir: LockBox no esta en la biblioteca del IDE de esta maquina)')
    check('N4 la carpeta de -NU sigue vacia: el motor no escribe en ella',
          os.path.isdir(SALIDA) and os.listdir(SALIDA) == [], os.listdir(SALIDA) if os.path.isdir(SALIDA) else 'no existe')
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('motor: la salida de unidades de sus ajustes 1.23.1 (V91)')
