# -*- coding: utf-8 -*-
"""La PUERTA DE ESCRIBIR (bloque de las puertas de la 1.18.0, P3): lo que el
servidor escribe en SUS lugares - la casa: los informes, las caches - pasa por
Lsp.Patch.EscribeTexto, que pregunta el lugar por su forma larga y sin enlaces
en el camino. Cada caso planta una UNION hacia una victima de FUERA de las
raices: la victima tiene que salir intacta (CLAUDE.md, "Nothing outside the
workspace").

R1 un informe de un agente cuya carpeta (reports\\<workspace>\\<agente>) es una union:
   GUARD-034 ANTES de crear nada, y nada en la victima. El lugar MISMO
   (reports\\) puede ser una union - es decision del operador, como mover la
   cache a otro disco -; lo que no, un enlace DENTRO. (Desde este entorno,
   crear un fichero NUEVO por una union da ERROR_FILE_EXISTS, medido el
   9-oct-2026: la reserva del nombre del binario viejo no llegaba a escribir
   detras; el rojo contra el viejo es que no decia GUARD-034.)
C1 la cache de las tablas del disenador (designer\\) que es una union: la
   generacion falla con su motivo (DSGN-053 con el GUARD-034) y nada en la
   victima (hasta 4f10790 las tablas se escribian detras).
R2 el control: sin la union, el informe se escribe entero, en UTF-8 con BOM.

Uso:  python tests/test_puerta_escribir.py [ruta-de-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('puerta-escribir')
VICTIMA = mc.carpeta('puerta-escribir-victima')  # FUERA de la raiz del servidor
LOCAL = mc.carpeta('puerta-escribir-local')      # su LOCALAPPDATA: su cache, solo suya
RAIZ_SRV = os.path.join(BASE, 'raiz')
os.makedirs(RAIZ_SRV, exist_ok=True)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
SRVDIR = os.path.dirname(EXE)
env = mc.entorno({'DELPHI_MCP_ROOTS': RAIZ_SRV, 'LOCALAPPDATA': LOCAL})


def detras():
    """Lo que haya llegado a la victima."""
    return [os.path.join(r, f) for r, _, fs in os.walk(VICTIMA) for f in fs]


AGENTE = 'por-union'
union_r = mc.buzon(os.path.join(SRVDIR, 'reports'), AGENTE)  # el del proceso local
os.makedirs(os.path.dirname(union_r), exist_ok=True)
union_d = mc.cache_servidor('designer', LOCAL)
os.makedirs(os.path.dirname(union_d), exist_ok=True)
check('R0 la union de reports\\<workspace>\\<agente> se planta', mc.junction(union_r, VICTIMA), union_r)
check('C0 la union de la cache del disenador se planta', mc.junction(union_d, VICTIMA), union_d)
srv = mc.Stdio(EXE, env, nombre='puerta-escribir')
try:
    r = srv.call('delphi_report', {'message': 'por la union', 'kind': 'bug', 'agent': AGENTE})
    check('R1 un informe cuya carpeta es una union: GUARD-034, y nada detras',
          mc.es(r, 'SR_GUARD_FUERA_DE_LUGARES_FMT') and not detras(), (detras(), r[:300]))

    r = mc.espera_info(srv.call, {'command': 'info', 'classname': 'TButton', 'framework': 'vcl'},
                       lambda x: mc.tiene(x, 'DSGN-053'))
    check('C1 la cache de tablas que es una union: la generacion falla con su motivo, y nada detras',
          mc.tiene(r, 'DSGN-053') and 'GUARD-034' in r and not detras(), (detras(), r[:300]))

    # P4-a de la 1.18.0: el ESCRITOR de la jaula juzga tambien DONDE nace su
    # temporal (la carpeta real + el nombre, RutaDelEnlace). Una carpeta de la raiz
    # que es una union a la victima, con un ENLACE DE FICHERO dentro que vuelve a
    # la raiz: la ruta real del fichero esta dentro y pasaba, el temporal nacia en
    # la victima y el renombre dejaba alli lo escrito. Un enlace de fichero pide
    # el privilegio o el modo desarrollador: sin el, no se mide (NOTA)
    _real = os.path.join(RAIZ_SRV, 'real')
    os.makedirs(_real, exist_ok=True)
    _u = os.path.join(_real, 'U.pas')
    open(_u, 'wb').write(b'unit U;\r\ninterface\r\nimplementation\r\nend.\r\n')
    _v = os.path.join(VICTIMA, 'v')
    os.makedirs(_v, exist_ok=True)
    _j = os.path.join(RAIZ_SRV, 'j')
    try:
        os.symlink(_u, os.path.join(_v, 'U.pas'))
        _hay_enlace = True
    except OSError:
        _hay_enlace = False
    _hay_union = _hay_enlace and mc.junction(_j, _v)
    if _hay_union:
        r = srv.call('delphi_edit', {'path': os.path.join(_j, 'U.pas'), 'old': 'interface',
                                     'new': 'interface // por la union'})
        check('W1 un fichero de la raiz por una union afuera con un enlace de vuelta: GUARD-037 y la victima '
              'sigue con su enlace', mc.abre(r, 'SR_SUSTITUCION_CARPETA_REAL_FMT') and
              os.path.islink(os.path.join(_v, 'U.pas')) and
              b'por la union' not in open(_u, 'rb').read(), r[:300])
        mc.borra(_j)
    elif not _hay_enlace:
        print('NOTA W1 (P4-a) no se mide: esta cuenta no puede crear un enlace de FICHERO (privilegio o '
              'modo desarrollador); el caso lo cierra Lsp.Guard.SustitucionDenegada con RutaDelEnlace')
    else:
        check('W1 la union de la prueba se planta', False, _j)
    for _f in (os.path.join(_v, 'U.pas'),):
        if os.path.lexists(_f):
            os.remove(_f)  # el enlace, no lo de detras

    # el control: la misma escritura sin la union
    mc.borra(union_r)
    r = srv.call('delphi_report', {'message': 'sin union: acentuación', 'kind': 'bug', 'title': 'control',
                                   'agent': AGENTE})
    escritos = [os.path.join(union_r, f) for f in os.listdir(union_r)] if os.path.isdir(union_r) else []
    cuerpo = open(escritos[0], 'rb').read() if len(escritos) == 1 else b''
    check('R2 sin la union, el informe se escribe entero en UTF-8 con BOM',
          len(escritos) == 1 and cuerpo.startswith(b'\xef\xbb\xbf') and
          'acentuación' in cuerpo.decode('utf-8-sig'), (r[:200], escritos))
finally:
    srv.cierra()
    # las uniones como uniones: lo de detras no se toca
    mc.borra(union_r)
    mc.borra(union_d)
    mc.borra(BASE)
    mc.borra(LOCAL)
    mc.borra(VICTIMA)
# W2: ...y una RAIZ declarada por una union (decision del operador, como mover la
# cache a otro disco) se sigue escribiendo: la pregunta de P4-a compara la ruta
# REAL de la carpeta con la ruta real de cada raiz. Su primera version la pasaba
# por la puerta de TEXTO, que la compara con la raiz DECLARADA, y negaba todo
# (GUARD-002, medido el 10-oct-2026 con la sonda: crear y editar). El crear, que
# este entorno deja hacer por una union (P3-L4), es el que la mide
BASE2 = mc.carpeta('puerta-escribir-raiz-union')
_t2 = os.path.join(BASE2, 'destino')
_j2 = os.path.join(BASE2, 'raiz-union')
os.makedirs(_t2)
check('W2 la union de la raiz se planta', mc.junction(_j2, _t2), _j2)
srv2 = mc.Stdio(mc.copia_exe(os.path.join(BASE2, 'srv')), mc.entorno({'DELPHI_MCP_ROOTS': _j2}),
                nombre='puerta-escribir-raiz-union')
try:
    r = srv2.call('delphi_textedit', {'path': os.path.join(_j2, 'nota.txt'), 'create': True, 'content': 'hola'})
    check('W2 en una raiz declarada por una union se crea un fichero (no GUARD-002)',
          not mc.fallo(r) and os.path.exists(os.path.join(_t2, 'nota.txt')), r[:300])
finally:
    srv2.cierra()
    if os.path.isdir(_j2):
        os.rmdir(_j2)  # la union como union
    mc.borra(BASE2)
mc.fin('puerta de escribir')
