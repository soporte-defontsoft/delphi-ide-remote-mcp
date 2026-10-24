# -*- coding: utf-8 -*-
r"""Textos que mentian o callaban lo util (V27 y V28 de la 1.23: Fable y Opus sobre la 1.22.2).

Cada caso, medido en produccion antes de arreglarlo (24-oct-2026):

  T1  delphi_adb devices device=x: ADB-005 (la puerta juzga todo device dado) dice que se quite
  T2  delphi_styles view de un .bin.style: STYLE-003 ya no dice "this server cannot READ it"
      (es una cabecera FMX_STYLE y un flujo TPF0, que el servidor lee en un .dfm)
  T3  delphi_search pattern=*.pas;*.dfm busca en los dos (decia WS-005: una sola mascara),
      como delphi_list: UN lector del pattern
  T4  ...y un trozo que no es mascara se niega en los dos (list lo tomaba sin mirar), y las
      llaves de una expansion, WS-006 en los dos
  T5  add-searchpath %2E%2E\<carpeta que existe>: se anade (CFG-018 decia que no existia: se
      juzgaba sin desescapar, y msbuild lee ..)
  T6  ...lo desescapado pasa por la jaula: %2E%2E hacia fuera de las raices se niega por ella
  T7  ...y un %3B (un ';' que parte la lista de msbuild) se niega por sus caracteres
  T8  set FMX TextSettings.Font.Style: storedIn con el StyleExt que escribe el IDE (decia
      DSGN-165 "no se guarda")
  T9  delphi_diagnostics de un .inc: LSP-051 al momento (se quedaba en "in-progress": medido
      seis minutos con tres lineas)

Mutante: produccion antes de este bloque (r1222ar): T1-T9 rojos.

Uso:  python tests/test_textos_1230.py [exe]
"""
import glob, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('textos1230')
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
os.makedirs(JAIL)
os.makedirs(FUERA)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)


def escribe(p, datos):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'wb').write(datos)
    return p


antes_atomos = mc.atomos_rtl_nombres()
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='textos1230', t=900)
try:
    # --- T1 ------------------------------------------------------------------------
    r = srv.call('delphi_adb', {'command': 'devices', 'device': 'emulator-5554'})
    check('T1 adb devices device=x: ADB-005 dice que, si la orden no usa uno, se quite',
          mc.abre(r, 'SR_ADB_ALLOWLIST_FMT') and 'leave it out' in r, r[:400])

    # --- T2 ------------------------------------------------------------------------
    BIN = escribe(os.path.join(JAIL, 'sty', 'Prueba.bin.style'),
                  b'FMX_STYLE 2.0TPF0\x0fTStyleContainer\x00\x00\x00')
    r = srv.call('delphi_styles', {'command': 'view', 'path': BIN})
    check('T2 styles view de un .bin.style: STYLE-003 sin "cannot READ" (el servidor lee un TPF0)',
          mc.abre(r, 'SR_STYLES_BINARY_FMT') and 'cannot READ' not in r and 'TEXT .style' in r, r[:400])

    # --- T3, T4 --------------------------------------------------------------------
    BUS = os.path.join(JAIL, 'busca')
    escribe(os.path.join(BUS, 'UUno.pas'), b'unit UUno;\r\n// MARCA_T3\r\ninterface\r\nimplementation\r\nend.\r\n')
    escribe(os.path.join(BUS, 'UUno.dfm'), b"object F: TF\r\n  Caption = 'MARCA_T3'\r\nend\r\n")
    escribe(os.path.join(BUS, 'Otro.txt'), b'MARCA_T3\r\n')
    r = srv.call('delphi_search', {'query': 'MARCA_T3', 'path': BUS, 'pattern': '*.pas;*.dfm'})
    j = mc.como_json(r)
    check('T3 search pattern=*.pas;*.dfm: busca en los dos (y no en el .txt), como list',
          not mc.fallo(r) and j.get('total') == 2 and 'UUno.pas' in r and 'UUno.dfm' in r
          and 'Otro.txt' not in r, r[:400])
    r = srv.call('delphi_search', {'query': 'MARCA_T3', 'path': BUS, 'pattern': '*.pas;..\\*.txt'})
    r2 = srv.call('delphi_list', {'root': BUS, 'pattern': '*.pas;..\\*.txt'})
    check('T4 un trozo que no es una mascara (..\\*.txt): WS-005 en search Y en list',
          mc.abre(r, 'SR_WS_PATTERN_DEBE_SER_MASCARA') and mc.abre(r2, 'SR_WS_PATTERN_DEBE_SER_MASCARA'),
          (r[:200], r2[:200]))
    r = srv.call('delphi_search', {'query': 'MARCA_T3', 'path': BUS, 'pattern': '*.{pas,dfm}'})
    r2 = srv.call('delphi_list', {'root': BUS, 'pattern': '*.{pas,dfm}'})
    check('T4 ...y las llaves de una expansion, WS-006 en los dos',
          mc.abre(r, 'SR_WS_PATTERN_ADMITE_LLAVES_EXPANSION')
          and mc.abre(r2, 'SR_WS_PATTERN_ADMITE_LLAVES_EXPANSION'), (r[:200], r2[:200]))
    # un espacio en el nombre no abre ninguna ruta, y list lo tomaba (no se le quita)
    escribe(os.path.join(BUS, 'My Unit1.pas'), b'unit MyUnit1;\r\n// MARCA_T3\r\ninterface\r\nimplementation\r\nend.\r\n')
    r = srv.call('delphi_search', {'query': 'MARCA_T3', 'path': BUS, 'pattern': 'My Unit*.pas'})
    r2 = srv.call('delphi_list', {'root': BUS, 'pattern': 'My Unit*.pas'})
    check('T4 ...una mascara con espacio (My Unit*.pas) vale en los dos',
          mc.como_json(r).get('total') == 1 and mc.como_json(r2).get('total') == 1, (r[:200], r2[:200]))

    # --- T5, T6, T7 ----------------------------------------------------------------
    PDIR = os.path.join(JAIL, 'proy')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Sp', 'dir': PDIR})
    DPROJ = os.path.join(PDIR, 'Sp.dproj')
    os.makedirs(os.path.join(JAIL, 'lib1'))
    r = srv.call('delphi_config', {'command': 'add-searchpath', 'project': DPROJ, 'path': '%2E%2E\\lib1'})
    dp = open(DPROJ, 'rb').read().decode('utf-8-sig')
    check('T5 add-searchpath %2E%2E\\lib1 (lib1 existe junto al proyecto): se anade, como lo leera msbuild',
          mc.abre(r, 'SN_CONFIG_PATH_ADDED_FMT') and '%2E%2E\\lib1' in dp, r[:400])
    a = open(DPROJ, 'rb').read()
    r = srv.call('delphi_config', {'command': 'add-searchpath', 'project': DPROJ,
                                   'path': '%2E%2E\\%2E%2E\\fuera'})
    check('T6 ...%2E%2E\\%2E%2E\\fuera (FUERA de las raices, y existe): la jaula lo niega, nada escrito',
          mc.rechazado(r) and not mc.abre(r, 'SR_CONFIG_PATH_MISSING_FMT')
          and open(DPROJ, 'rb').read() == a, r[:400])
    r = srv.call('delphi_config', {'command': 'add-searchpath', 'project': DPROJ, 'path': 'lib1%3B..\\..\\fuera'})
    check('T7 ...un %3B (el ";" que parte la lista de msbuild): negado por sus caracteres, nada escrito',
          mc.abre(r, 'SR_CONFIG_PATH_CHARS') and open(DPROJ, 'rb').read() == a, r[:400])

    # --- T8 ------------------------------------------------------------------------
    FDIR = os.path.join(JAIL, 'fmx')
    srv.call('delphi_create', {'kind': 'project-fmx', 'name': 'Fx', 'dir': FDIR})
    fmx = [f for f in glob.glob(os.path.join(FDIR, '*.fmx'))]
    FMX = fmx[0] if fmx else os.path.join(FDIR, 'no-hay.fmx')
    mc.espera_info(srv.call, {'command': 'info', 'classname': 'TLabel', 'framework': 'fmx'})
    srv.call('delphi_designer', {'command': 'insert', 'path': FMX, 'classname': 'TLabel', 'component': 'Label9'}, t=300)
    r = srv.call('delphi_designer', {'command': 'set', 'path': FMX, 'component': 'Label9',
                                     'prop': 'TextSettings.Font.Style', 'value': '[fsBold]'}, t=300)
    t = open(FMX, 'rb').read().decode('utf-8-sig')
    check('T8 FMX TextSettings.Font.Style=[fsBold]: storedIn con el StyleExt que escribe el IDE, no notStored',
          not mc.fallo(r) and 'notStored' not in r and 'StyleExt' in mc.como_json(r).get('storedIn', '')
          and 'TextSettings.Font.StyleExt' in t, (r[:500], fmx))

    # --- T9 ------------------------------------------------------------------------
    INC = escribe(os.path.join(PDIR, 'Defs.inc'), b'const\r\n  CINC = 1;\r\n')
    r = srv.call('delphi_diagnostics', {'path': INC})
    check('T9 diagnostics de un .inc junto a su .dproj: LSP-051 al momento (no "in-progress")',
          mc.abre(r, 'SR_LSP_LINT_INCLUDE_FMT'), r[:300])
finally:
    srv.cierra()
    print('atomos RTL nuevos de procesos muertos:', mc.atomos_rtl_dejados(antes_atomos))
    try:
        mc.fin('bateria de los textos que mentian (V27, V28)')
    finally:
        mc.borra(BASE)
