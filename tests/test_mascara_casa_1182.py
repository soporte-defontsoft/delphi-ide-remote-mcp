# -*- coding: utf-8 -*-
"""La casa del servidor no sale en ninguna respuesta (1.18.2, punto 2ag).

David, 12-oct-2026: "nuestros procesos internos y nuestro temp, los agentes
no deben ni olerlo ni saber que existe"; 13-oct: el enmascarador de la casa
va en el MISMO filtro de salida que la letra de unidad y cambia solo el
prefijo de la casa por un nombre - <server> (la carpeta del exe) y
<server-cache> (la cache, LOCALAPPDATA\\DelphiLspMcp) -; lo de debajo se
queda, y la salida cruda sigue diciendo que fichero fallo.

  C1  delphi_workspace: server.exe es <server>\\DelphiLspMcp.exe, sin la
      carpeta real del servidor en ninguna forma (larga, 8.3, ni con su
      unidad virtual)
  C2  una negativa que nombraba la casa (preview sin los renderizadores,
      DSGN-060): <server>, no la ruta
  C3  el CONTENIDO no se enmascara: un fichero del agente que cita la ruta
      real del servidor se lee tal cual (delphi_read)
  C5  la ruta de la casa que el agente nombra le vuelve con su nombre: una
      negativa de la jaula sobre la cache y sobre la carpeta del exe, en su
      forma larga y en la 8.3
  C4  la casa DENTRO de una raiz que declaro el operador no se enmascara: es
      del agente ("si le das acceso, tu sabras"), y sale con su unidad
      virtual, que el agente puede devolver

Uso:  python tests/test_mascara_casa_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('mascara_casa_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
SRV = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRV)  # sin renderizadores: C2 los echa en falta
FORM = os.path.join(JAIL, 'Casa.dfm')
open(FORM, 'w', encoding='ascii').write("object Casa: TForm\n  Caption = 'c'\nend\n")
# la cache del servidor de las baterias (LOCALAPPDATA\DelphiLspMcp): existe
# antes de arrancar, para que tenga su forma 8.3 (C5)
CACHE = mc.cache_servidor()
os.makedirs(CACHE, exist_ok=True)
CITA = os.path.join(JAIL, 'cita.txt')
open(CITA, 'w', encoding='utf-8').write('el servidor vive en %s\n' % mc.larga(SRV))


def formas(ruta):
    """Las formas en que puede salir una ruta (larga, 8.3, y las dos con su
    unidad virtual), en minusculas, para buscarlas en un texto ya aplanado."""
    r = []
    for f in {mc.larga(ruta), mc.corta(ruta) or mc.larga(ruta), ruta}:
        r += [f.lower(), mc.virtual(f).lower()]
    return r


def plano(t):
    # un JSON escribe cada barra doble
    return (t or '').lower().replace('\\\\', '\\')


def nombra(t, ruta):
    return [f for f in formas(ruta) if f in plano(t)]


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='casa', t=120)
try:
    r = srv.call('delphi_workspace', {})
    exe = (mc.como_json(r).get('server') or {}).get('exe', '')
    check('C1 delphi_workspace: server.exe es <server>\\DelphiLspMcp.exe, sin la carpeta del servidor en ninguna forma',
          exe == '<server>\\DelphiLspMcp.exe' and not nombra(r, SRV), (exe, nombra(r, SRV)))
    r = srv.call('delphi_designer', {'command': 'preview', 'path': FORM})
    check('C2 DSGN-060 (sin los renderizadores): sin la carpeta del servidor, ni enmascarada',
          mc.es(r, 'SR_DESIGNER_SIN_RENDER_FMT') and '<server>' not in r and not nombra(r, SRV),
          (r[:300], nombra(r, SRV)))
    r = srv.call('delphi_read', {'path': CITA})
    check('C3 el contenido no se enmascara: la ruta real del servidor citada en un fichero sale tal cual',
          mc.larga(SRV) in r and '<server>' not in r, r[:300])
    # C5: una negativa de la jaula repite la ruta que se le dio: la de la
    # cache (<server-cache>) y la del exe (<server>), en su forma larga y en
    # la 8.3 - las dos formas que el enmascarador conoce de cada casa
    for nombre, raiz, sub in (('<server-cache>', CACHE, 'x.txt'), ('<server>', SRV, 'settings.ini')):
        for forma in {mc.larga(raiz), mc.corta(raiz) or mc.larga(raiz)}:
            r = srv.call('delphi_read', {'path': os.path.join(forma, sub)})
            check('C5 la jaula niega %s y la repite como %s\\%s (forma %s)' % (sub, nombre, sub, forma[-28:]),
                  mc.rechazado(r) and (nombre + '\\' + sub) in r.replace('\\\\', '\\') and not nombra(r, raiz),
                  (r[:300], nombra(r, raiz)))
finally:
    srv.cierra()

# --------------------------- C4: la casa dentro de una raiz del operador
SRV4 = os.path.join(JAIL, 'srvdentro')
EXE4 = mc.copia_exe(SRV4)
srv4 = mc.Stdio(EXE4, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='casa', t=120)
try:
    r = srv4.call('delphi_workspace', {})
    exe = (mc.como_json(r).get('server') or {}).get('exe', '')
    check('C4 la casa dentro de una raiz no se enmascara: server.exe con su unidad virtual, que el agente puede devolver',
          exe.lower().startswith('srv') and exe.lower().endswith('\\srvdentro\\delphilspmcp.exe') and
          '<server>' not in exe, exe)
finally:
    srv4.cierra()

# --------------------------- revisor del 2ag: raices que EMPIEZAN como la casa
def raices_de(cli):
    return (mc.como_json(cli.call('delphi_workspace', {})).get('roots') or [])


for clave, nombre_srv, nombre_raiz in (('C6', 'srvv', 'srvv x'), ('C7', 'srvd', os.path.join('srvd', 'ws'))):
    srvdir = os.path.join(BASE, nombre_srv)
    raiz = os.path.join(BASE, nombre_raiz)
    os.makedirs(raiz, exist_ok=True)
    open(os.path.join(raiz, 'a.pas'), 'w').write('unit a;\ninterface\nimplementation\nend.\n')
    exe_r = mc.copia_exe(srvdir)
    cli = mc.Stdio(exe_r, mc.entorno({'DELPHI_MCP_ROOTS': raiz}), nombre='casa', t=120)
    try:
        rs = raices_de(cli)
        r = cli.call('delphi_list', {'root': rs[0] if rs else ''})
        check('%s una raiz %s de la casa (%s): sale con su unidad virtual y el agente la puede devolver'
              % (clave, 'VECINA con un espacio' if clave == 'C6' else 'DENTRO', nombre_raiz),
              len(rs) == 1 and rs[0].lower().startswith('srv') and '<server>' not in rs[0] and
              'a.pas' in r and not mc.rechazado(r), (rs, r[:300]))
    finally:
        cli.cierra()

# C8: una casa con letras que el JSON escribe como \uXXXX (un usuario Jose)
SRV8 = os.path.join(BASE, 'srvñé')
cli = mc.Stdio(mc.copia_exe(SRV8), mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='casa', t=120)
try:
    r = cli.call('delphi_workspace', {})
    exe = (mc.como_json(r).get('server') or {}).get('exe', '')
    check('C8 una casa con letras no ASCII (en el JSON, \\u00f1) tambien es <server>',
          exe == '<server>\\DelphiLspMcp.exe' and 'srv\\u00f1' not in r.lower() and not nombra(r, SRV8), (exe, r[:300]))
finally:
    cli.cierra()

# C9: el nombre de vuelta como ruta: una negativa que lo dice, no "ruta relativa"
cli = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='casa', t=120)
try:
    for nombre in ('<server>', '<server-cache>'):
        r = cli.call('delphi_read', {'path': nombre + '\\settings.ini'})
        check('C9 %s\\settings.ini de vuelta: GUARD-039 (es un nombre, no una ruta), no GUARD-021' % nombre,
              mc.rechazado(r) and mc.es(r, 'SR_GUARD_CASA_DEL_SERVIDOR_FMT') and
              not mc.es(r, 'SR_GUARD_RUTA_RELATIVA_FMT'), r[:300])
finally:
    cli.cierra()

mc.borra(BASE)
mc.fin('mascara de la casa 1182')
