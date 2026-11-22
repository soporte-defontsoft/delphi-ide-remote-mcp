# -*- coding: utf-8 -*-
"""Las tres capacidades pequenas del punto B de la 1.29.3, con la demanda medida en el state.db de Hermes desde el
12-nov (David, 21-nov: "adelante con tus recomendaciones").

delphi_read cuenta lineas y lee el final. 13 SYS-015 contaban las lineas en vez de dar la ultima (offset+limit, el
vocabulario de vault_read, 8; maxlines con startline o fromline, 4) y 2 pedian el final de un log (tail=40, readtype=tail).
  L1  fromline + limit: esas lineas (ROJO sin el arreglo: SYS-015)
  L1b limit sin fromline: desde la 1
  L2  offset + limit (alias de vault_read) y startline + maxlines: lo mismo
  L3  limit con toline: READ-012, nada leido
  L4  tail=3: las 3 ultimas (ROJO sin el arreglo)
  L4b tail mayor que el fichero: el fichero entero, sin nota
  L5  tail con fromline: READ-013
  L6  tail=1000 de 1000 lineas: las 400 ultimas (601-1000) y READ-014
  L7  limit enorme: sin desbordar, 400 lineas desde fromline y la nota de siempre (EDIT-064)
  L8  tail de un fichero vacio: la lectura vacia de siempre
  L9  control: fromline/toline, como antes

delphi_designer tree component= (D29: cuatro veces el 17 y el 18-nov, y DSGN-047 le mandaba a get).
  T1  tree component=Panel1: su subarbol, con el en la raiz (ROJO sin el arreglo: DSGN-047)
  T2  ...con maxdepth=1: los niveles cuentan desde el (childrenCount)
  T3  component que no esta: DSGN-078, la negativa de get y de los que escriben
  T4  control: tree sin component, el form en la raiz
  T5  control: get component= (su buscador ahora es el de tree) da su bloque, y DSGN-078 si no esta
  T6  DSGN-059 manda a component= (el subarbol)

delphi_build out= (los 10 SYS-015 querian el log ENTERO del build en un .log, como remote-run out=, y 5 iban con
verbosity=quiet: la respuesta corta y el log en el fichero; la consola en quiet no escribe nada en un build limpio).
  B1  out=<.log> en quiet (la de siempre): el build y logfile/lines/size/logfileNote (BUILD-078); el fichero con
      el log de msbuild (normal), no la consola vacia (ROJO sin el arreglo: SYS-015)
  B1b lines es como delphi_read cuenta el fichero, y tail lo lee
  B1c verbose: el fichero no nombra la casa del servidor (lo que la respuesta tapa con su filtro)
  B1d los dos ficheros, como la respuesta: ninguna letra real (D:, C:), la ruta del proyecto con su unidad virtual
      (medido en vivo el 21-nov-2026: el log decia D: donde la respuesta del mismo build decia srvd:)
  B2  out=<.exe>: BUILD-077 antes de compilar (el binario no se toca)
  B3  out fuera de las raices: negado, nada escrito alli
  B4  out por un junction de la jaula a una victima fuera: negado, la victima intacta
  B5  out sobre un fichero que ya estaba: sustituido
  B6  un build que falla con out=: el fichero con su error, success=false
  B7  control: sin out, ni logfile ni logfileNote

Uso:  python tests/test_capacidades_b_1293.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('capacidades_b_1293')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
FUERA = mc.carpeta('capacidades_b_1293-fuera')
VICTIMA = os.path.join(FUERA, 'victima')
os.makedirs(VICTIMA)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

DIEZ = os.path.join(JAIL, 'diez.txt')
open(DIEZ, 'w', newline='\n').write(''.join('linea %d\n' % i for i in range(1, 11)))
MIL = os.path.join(JAIL, 'mil.log')
open(MIL, 'w', newline='\n').write(''.join('l%d\n' % i for i in range(1, 1001)))
VACIO = os.path.join(JAIL, 'vacio.txt')
open(VACIO, 'w').close()
DFM = os.path.join(JAIL, 'UForm.dfm')
open(DFM, 'w', newline='\r\n').write(
    "object Form1: TForm1\n  Left = 0\n  Top = 0\n  Caption = 'Form1'\n  ClientHeight = 200\n"
    "  ClientWidth = 300\n  object Panel1: TPanel\n    Left = 8\n    Top = 8\n    Width = 200\n"
    "    Height = 100\n    TabOrder = 0\n    object Button1: TButton\n      Left = 8\n      Top = 8\n"
    "      Width = 75\n      Height = 25\n      Caption = 'Button1'\n      TabOrder = 0\n    end\n  end\nend\n")
LOGS = os.path.join(JAIL, 'logs')
os.makedirs(LOGS)
ENLACE = os.path.join(JAIL, 'enlace')
HAY_ENLACE = mc.junction(ENLACE, VICTIMA)

RANGO = re.compile(r'Lines (\d+)-(\d+) of (\d+)')


def rango(t):
    m = RANGO.search(t or '')
    return tuple(int(x) for x in m.groups()) if m else None


def nodo(t):
    return (mc.como_json(t) or {}).get('root') or {}


def nombres(n):
    return [k.get('name') for k in n.get('children') or []]


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='capacidades-b', t=180)
call = srv.call
try:
    # --- delphi_read: limit y tail ---
    r = call('delphi_read', {'path': DIEZ, 'fromline': 3, 'limit': 2})
    check('L1 fromline=3 limit=2: las lineas 3-4 (ROJO sin el arreglo)', rango(r) == (3, 4, 10), r[:300])
    r = call('delphi_read', {'path': DIEZ, 'limit': 4})
    check('L1b limit=4 sin fromline: 1-4', rango(r) == (1, 4, 10), r[:300])
    r = call('delphi_read', {'path': DIEZ, 'offset': 6, 'limit': 3})
    r2 = call('delphi_read', {'path': DIEZ, 'startline': 2, 'maxlines': 5})
    check('L2 offset=6 limit=3 (como vault_read) da 6-8, y startline=2 maxlines=5 da 2-6',
          rango(r) == (6, 8, 10) and rango(r2) == (2, 6, 10), (r[:200], r2[:200]))
    r = call('delphi_read', {'path': DIEZ, 'fromline': 2, 'toline': 5, 'limit': 2})
    check('L3 limit con toline: READ-012, nada leido', mc.abre(r, 'SR_READ_LIMIT_Y_TOLINE') and 'linea' not in r,
          r[:300])
    r = call('delphi_read', {'path': DIEZ, 'tail': 3})
    check('L4 tail=3: las 3 ultimas, 8-10 (ROJO sin el arreglo)',
          rango(r) == (8, 10, 10) and 'linea 10' in r and 'linea 7' not in r, r[:300])
    r = call('delphi_read', {'path': DIEZ, 'tail': 50})
    check('L4b tail=50 de un fichero de 10: entero, sin nota de corte',
          rango(r) == (1, 10, 10) and not mc.es(r, 'SN_READ_TAIL_CORTADO_FMT'), r[:300])
    r = call('delphi_read', {'path': DIEZ, 'tail': 3, 'fromline': 2})
    check('L5 tail con fromline: READ-013', mc.abre(r, 'SR_READ_TAIL_SOLO'), r[:300])
    r = call('delphi_read', {'path': MIL, 'tail': 1000})
    check('L6 tail=1000 de 1000 lineas: las 400 ULTIMAS (601-1000) y READ-014',
          rango(r) == (601, 1000, 1000) and mc.es(r, 'SN_READ_TAIL_CORTADO_FMT') and '|l1000' in r, r[-400:])
    r = call('delphi_read', {'path': MIL, 'fromline': 5, 'limit': 2147483647})
    check('L7 limit enorme: sin desbordar, 5-404 y EDIT-064',
          rango(r) == (5, 404, 1000) and mc.es(r, 'SN_EDIT_RECORTADO_EN_LINEA_FMT'), r[:200] + r[-300:])
    r = call('delphi_read', {'path': VACIO, 'tail': 5})
    check('L8 tail de un fichero vacio: la lectura vacia de siempre', mc.es(r, 'SK_EDIT_LECTURA_VACIO_FMT'), r[:300])
    r = call('delphi_read', {'path': DIEZ, 'fromline': 2, 'toline': 3})
    check('L9 control: fromline=2 toline=3, como antes', rango(r) == (2, 3, 10), r[:300])

    # --- delphi_designer tree component= ---
    r = call('delphi_designer', {'command': 'tree', 'path': DFM, 'component': 'Panel1'})
    n = nodo(r)
    check('T1 tree component=Panel1: su subarbol, el en la raiz (ROJO sin el arreglo)',
          n.get('name') == 'Panel1' and nombres(n) == ['Button1'], r[:400])
    r = call('delphi_designer', {'command': 'tree', 'path': DFM, 'component': 'Panel1', 'maxdepth': 1})
    n = nodo(r)
    check('T2 ...maxdepth=1 cuenta desde el: Panel1 con childrenCount=1',
          n.get('name') == 'Panel1' and n.get('childrenCount') == 1 and 'children' not in n, r[:400])
    r = call('delphi_designer', {'command': 'tree', 'path': DFM, 'component': 'NoEsta'})
    check('T3 component que no esta: DSGN-078', mc.abre(r, 'SR_DESIGNER_COMPONENTE_NO_ESTA_FMT'), r[:300])
    r = call('delphi_designer', {'command': 'tree', 'path': DFM})
    n = nodo(r)
    check('T4 control: tree sin component, el form en la raiz',
          n.get('name') == 'Form1' and nombres(n) == ['Panel1'], r[:300])
    r = call('delphi_designer', {'command': 'get', 'path': DFM, 'component': 'Panel1'})
    r2 = call('delphi_designer', {'command': 'get', 'path': DFM, 'component': 'NoEsta'})
    check('T5 control: get component=Panel1 da su bloque, y DSGN-078 si no esta',
          'object Panel1: TPanel' in r and 'Button1' in r and mc.abre(r2, 'SR_DESIGNER_COMPONENTE_NO_ESTA_FMT'),
          (r[:300], r2[:200]))
    r = call('delphi_designer', {'command': 'tree', 'path': DFM, 'maxdepth': 1})
    nota = (mc.como_json(r) or {}).get('maxDepthNote', '')
    check('T6 DSGN-059 manda al subarbol con component=', mc.es(nota, 'SN_DESIGNER_TREE_MAXDEPTH_FMT') and
          'subtree' in nota and 'component=<name>' in nota, nota)

    # --- delphi_build out= ---
    PB = os.path.join(JAIL, 'PB')
    call('delphi_create', {'kind': 'project-console', 'name': 'PB', 'dir': PB}, t=120)
    DPROJ = os.path.join(PB, 'PB.dproj')
    LOG = os.path.join(LOGS, 'build.log')
    r = call('delphi_build', {'project': DPROJ, 'out': LOG}, t=600)
    d = mc.como_json(r) or {}
    txt = open(LOG, encoding='utf-8-sig').read() if os.path.isfile(LOG) else ''
    check('B1 out=<.log>: build bueno, logfile/lines/size y BUILD-078; el fichero con lo de msbuild (ROJO sin el arreglo)',
          d.get('success') is True and mc.larga(mc.real(d.get('logfile', ''))).lower() == mc.larga(LOG).lower()
          and d.get('size') == os.path.getsize(LOG) and mc.es(d.get('logfileNote', ''), 'SN_BUILD_LOGFILE')
          and len(txt.splitlines()) > 3 and 'PB.dproj' in txt, (r[:600], txt[:300]))
    r2 = call('delphi_read', {'path': LOG, 'tail': 5})
    rg = rango(r2)
    check('B1b lines = como delphi_read cuenta el fichero, y tail lo lee',
          rg is not None and d.get('lines') == rg[2] and rg[1] == rg[2], (d.get('lines'), r2[:300]))
    LOGV = os.path.join(LOGS, 'verbose.log')
    r = call('delphi_build', {'project': DPROJ, 'out': LOGV, 'verbosity': 'verbose'}, t=600)
    txtv = open(LOGV, encoding='utf-8-sig').read() if os.path.isfile(LOGV) else ''
    casas = [c for c in (mc.cache_servidor(), os.path.join(BASE, 'srv')) if c]
    check('B1c verbose: el fichero entero (mas que la cola) y sin la casa del servidor',
          len(txtv.splitlines()) > 120 and 'dcc64' in txtv.lower()
          and not any(mc.larga(c).lower() in txtv.lower() or c.lower() in txtv.lower() for c in casas)
          and mc.cadena_del_fuente('Server/Lsp.BuildRunner.pas', 'BUILD_LOGS_SUB') not in txtv,
          (len(txtv.splitlines()), [c for c in casas if c.lower() in txtv.lower()]))
    # lo que tapo el nombrador, para saberlo: '<server' en el fichero es que msbuild nombro la casa
    mc.imprime('    (B1c: el nombrador de la casa tapo algo: %s)' % ('<server' in txtv))
    fugas = mc.fuga_de_letra(txt) + mc.fuga_de_letra(txtv)
    check('B1d los ficheros, como la respuesta: ninguna letra real, el proyecto con su unidad virtual (ROJO sin el arreglo)',
          not fugas and mc.virtual(mc.larga(DPROJ)).lower() in txt.lower(),
          (fugas[:5], mc.virtual(mc.larga(DPROJ)), txt[:300]))
    EXEPB = os.path.join(PB, 'Win64', 'Debug', 'PB.exe')
    antes = os.path.getmtime(EXEPB) if os.path.isfile(EXEPB) else None
    r = call('delphi_build', {'project': DPROJ, 'out': os.path.join(LOGS, 'mal.exe')}, t=600)
    check('B2 out=<.exe>: BUILD-077 antes de compilar, el binario sin tocar',
          mc.abre(r, 'SR_BUILD_OUT_LOG') and not os.path.exists(os.path.join(LOGS, 'mal.exe'))
          and antes is not None and (os.path.getmtime(EXEPB) if os.path.isfile(EXEPB) else None) == antes,
          (antes, r[:300]))
    r = call('delphi_build', {'project': DPROJ, 'out': os.path.join(FUERA, 'fuera.log')}, t=600)
    check('B3 out fuera de las raices: negado, nada escrito alli',
          mc.fallo(r) and not mc.es(r, 'SR_SYS_UNKNOWN_PARAM_FMT') and not os.path.exists(os.path.join(FUERA, 'fuera.log')),
          r[:300])
    if HAY_ENLACE:
        r = call('delphi_build', {'project': DPROJ, 'out': os.path.join(ENLACE, 'por-el-enlace.log')}, t=600)
        check('B4 out por un junction a una victima fuera: negado, la victima intacta',
              mc.fallo(r) and not mc.es(r, 'SR_SYS_UNKNOWN_PARAM_FMT') and os.listdir(VICTIMA) == [],
              (r[:300], os.listdir(VICTIMA)))
    else:
        check('B4 out por un junction (no se pudo plantar el junction)', False, 'mklink /J fallo')
    open(LOG, 'w').write('VIEJO\n')
    r = call('delphi_build', {'project': DPROJ, 'out': LOG}, t=600)
    nuevo = open(LOG, encoding='utf-8-sig').read()
    check('B5 out sobre un fichero que ya estaba: sustituido', 'VIEJO' not in nuevo and len(nuevo) > 10, nuevo[:200])
    DPR = os.path.join(PB, 'PB.dpr')
    src = open(DPR, encoding='utf-8-sig').read()
    open(DPR, 'w', encoding='utf-8', newline='\r\n').write(src.replace('begin', 'begin\n  NoExisteNada;', 1))
    LOGE = os.path.join(LOGS, 'error.log')
    r = call('delphi_build', {'project': DPROJ, 'out': LOGE}, t=600)
    d = mc.como_json(r) or {}
    txte = open(LOGE, encoding='utf-8-sig').read() if os.path.isfile(LOGE) else ''
    check('B6 un build que falla con out=: success=false y el fichero con su error',
          d.get('success') is False and 'NoExisteNada' in txte and d.get('logfile'), (r[:300], txte[-300:]))
    open(DPR, 'w', encoding='utf-8', newline='\r\n').write(src)
    r = call('delphi_build', {'project': DPROJ}, t=600)
    d = mc.como_json(r) or {}
    check('B7 control: sin out, ni logfile ni logfileNote',
          d.get('success') is True and 'logfile' not in d and 'logfileNote' not in d, r[:300])
finally:
    srv.cierra()
mc.borra(BASE)
mc.borra(FUERA)
mc.fin('capacidades del punto B de la 1.29.3 (read limit/tail, tree component=, build out=)')
