# -*- coding: utf-8 -*-
"""GUARD-045 dice lo que el agente quiso (A3/A4 de la 1.29.3).

Un alias y su nombre real con valores distintos se niegan (V93 de la 1.23.1, test_alias_valor_1231). La negativa
era cierta y no decia el siguiente paso. Medido en el state.db de Hermes desde el 12-nov, siempre la misma
intencion: delphi_search con path=<un fichero> y root=<su carpeta> (28), delphi_build con command=build y
target=Deploy (12), delphi_list con path=<una mascara> y root=<la carpeta>. La pista vive en la cuarta columna de la
tabla de alias (Lsp.PuertaDeLaLlamada.ApplyArgAliases) y sale DETRAS de la negativa, que no cambia.

  P1  delphi_search path=<fichero> root=<su carpeta>: GUARD-045 y la pista de root (ROJO sin el arreglo)
  P1b ...y seguir la pista (root=<el fichero>, solo) busca dentro de el
  P2  delphi_build command=build target=Deploy: GUARD-045 y la pista de target (ROJO sin el arreglo), nada compilado
  P3  delphi_list path=*.pas root=<carpeta>: GUARD-045 y la pista de pattern (ROJO sin el arreglo)
  P3b ...y seguir la pista (root + pattern) lista
  P4  control: un alias sin pista (delphi_read from/fromline) da la negativa de siempre, sin ninguna de las tres
  P5  control: el mismo valor en alias y nombre real sigue valiendo (delphi_search root=A path=A)

Uso:  python tests/test_alias_pista_1293.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('alias_pista_1293')
JAIL = os.path.join(BASE, 'jail')
A = os.path.join(JAIL, 'A')
os.makedirs(A)
UA = os.path.join(A, 'UA.pas')
open(UA, 'w').write('unit UA;\ninterface\nconst MARCA_A = 1;\nimplementation\nend.\n')
DPROJ = os.path.join(A, 'P.dproj')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
PISTAS = ('SF_ALIAS_PISTA_SEARCH_ROOT', 'SF_ALIAS_PISTA_BUILD_TARGET', 'SF_ALIAS_PISTA_LIST_ROOT')


def texto(t):
    """El texto de la negativa: el campo "error" de una respuesta JSON, o el texto tal cual."""
    t = t or ''
    if t.lstrip().startswith('{'):
        e = mc.como_json(t).get('error')
        return e if isinstance(e, str) else ''
    return t


def acaba_en(t, nombre):
    """True si la negativa ACABA en esa pista del catalogo (va detras de la negativa, que no cambia)."""
    return texto(t).rstrip().endswith(mc.catalogo()[nombre].strip())


def alguna_pista(t):
    return any(mc.catalogo()[p].strip() in texto(t) for p in PISTAS)


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='alias-pista', t=120)
try:
    r = srv.call('delphi_search', {'path': UA, 'root': A, 'query': 'MARCA_'})
    check('P1 delphi_search path=<fichero> root=<su carpeta>: GUARD-045 y la pista de root (ROJO sin el arreglo)',
          mc.abre(r, 'SR_ARG_ALIAS_OTRO_VALOR_FMT') and acaba_en(r, 'SF_ALIAS_PISTA_SEARCH_ROOT'), r[:500])
    r = srv.call('delphi_search', {'root': UA, 'query': 'MARCA_'})
    check('P1b ...y seguir la pista (root=<el fichero>, solo) busca dentro de el',
          not mc.fallo(r) and 'UA.pas' in r and 'MARCA_A' in r, r[:400])
    r = srv.call('delphi_build', {'command': 'build', 'target': 'Deploy', 'project': DPROJ})
    check('P2 delphi_build command=build target=Deploy: GUARD-045 y la pista de target (ROJO sin el arreglo)',
          mc.abre(r, 'SR_ARG_ALIAS_OTRO_VALOR_FMT') and acaba_en(r, 'SF_ALIAS_PISTA_BUILD_TARGET'), r[:500])
    r = srv.call('delphi_list', {'path': '*.pas', 'root': A})
    check('P3 delphi_list path=*.pas root=<carpeta>: GUARD-045 y la pista de pattern (ROJO sin el arreglo)',
          mc.abre(r, 'SR_ARG_ALIAS_OTRO_VALOR_FMT') and acaba_en(r, 'SF_ALIAS_PISTA_LIST_ROOT'), r[:500])
    r = srv.call('delphi_list', {'root': A, 'pattern': '*.pas'})
    check('P3b ...y seguir la pista (root + pattern) lista el fichero',
          not mc.fallo(r) and 'UA.pas' in r, r[:400])
    r = srv.call('delphi_read', {'path': UA, 'from': 1, 'fromline': 2})
    check('P4 control: un alias sin pista (delphi_read from/fromline) niega como siempre, sin ninguna de las tres',
          mc.abre(r, 'SR_ARG_ALIAS_OTRO_VALOR_FMT') and not alguna_pista(r), r[:400])
    r = srv.call('delphi_search', {'root': A, 'path': A, 'query': 'MARCA_'})
    check('P5 control: el mismo valor en alias y nombre real sigue valiendo',
          not mc.fallo(r) and 'UA.pas' in r, r[:400])
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('GUARD-045 dice lo que el agente quiso 1.29.3 (A3/A4)')
