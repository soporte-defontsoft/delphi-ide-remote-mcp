# -*- coding: utf-8 -*-
"""La PUERTA DE ESCRIBIR (bloque de las puertas de la 1.18.0, P3): lo que el
servidor escribe en SUS lugares - la casa: los informes, las caches - pasa por
Lsp.Patch.EscribeTexto, que pregunta el lugar por su forma larga y sin enlaces
en el camino. Cada caso planta una UNION hacia una victima de FUERA de las
raices: la victima tiene que salir intacta (CLAUDE.md, "Nothing outside the
workspace").

R1 un informe de un agente cuya carpeta (reports\\<agente>) es una union:
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
os.makedirs(os.path.join(SRVDIR, 'reports'), exist_ok=True)
union_r = os.path.join(SRVDIR, 'reports', AGENTE)
union_d = mc.cache_servidor('designer', LOCAL)
os.makedirs(os.path.dirname(union_d), exist_ok=True)
check('R0 la union de reports\\<agente> se planta', mc.junction(union_r, VICTIMA), union_r)
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
mc.fin('puerta de escribir')
