"""E2E battery for v0.77.0-beta - hermes' release audit P1.5: compact outputs.

Measured walls (hermes, 2026-08-26, live runtime over a real project):
`delphi_config view` answered 11.7k chars and `delphi_symbols` 37.5k chars for
a 912-line unit - a small model drowned before doing anything. Now:

  - delphi_config view defaults to a SUMMARY (framework, configurations,
    enabled platforms, counts) and `section=platforms|searchpaths|deploy|
    units|all` brings each detail on demand.
  - delphi_symbols on a FILE: big trees answer with a compact skeleton
    (mode summary, auto above 6k chars of full tree), `mode=full` keeps the
    old complete tree, and `filter=name` finds symbols without the tree.

  C1..C7  config sections
  S1..S5  symbols modes and filter

Usage:  python tests/test_round16.py [path-to-DelphiLspMcp.exe]
"""
import json, time, os, shutil, glob
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('round16')
EXE = mc.copia_exe(BASE)
# a real big unit for the symbols wall (typ. >30k chars of full tree)
shutil.copy(os.path.join(mc.REPO, 'src', 'Server', 'Lsp.Guard.pas'),
            os.path.join(BASE, 'Big.pas'))
open(os.path.join(BASE, 'Small.pas'), 'w').write(
    'unit Small;\ninterface\nprocedure Uno;\nimplementation\n'
    'procedure Uno;\nbegin\nend;\nend.\n')

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='round16')
call = srv.call


def jload(s):
    try:
        return json.loads(s)
    except Exception:
        return {}


time.sleep(0.3)

# ---- config sections -------------------------------------------------------
r = call('delphi_create', {'kind': 'project-console', 'name': 'SecCfg', 'dir': BASE})
check('scaffold para config', 'CREADO' in r, r)
dproj = glob.glob(os.path.join(BASE, '**', 'SecCfg.dproj'), recursive=True)[0]

rsum = call('delphi_config', {'project': dproj})
j = jload(rsum)
check('C1 view por defecto = summary (marco, configs, plataformas, counts)',
      j.get('frameworkType') is not None and 'configurations' in j and
      'platformsEnabled' in j and 'counts' in j and 'sections' in j, rsum[:300])
check('C1 el summary NO arrastra el detalle (ni units ni searchPaths ni platforms)',
      'units' not in j and 'searchPaths' not in j and 'platforms' not in j, list(j.keys()))

j = jload(call('delphi_config', {'project': dproj, 'section': 'units'}))
check('C2 section=units trae las units y solo eso',
      isinstance(j.get('units'), list) and
      'counts' not in j and 'searchPaths' not in j, list(j.keys()))

j = jload(call('delphi_config', {'project': dproj, 'section': 'platforms'}))
check('C3 section=platforms trae el detalle por plataforma',
      isinstance(j.get('platforms'), list) and
      all('enabled' in p and 'canTarget' in p for p in j['platforms']),
      list(j.keys()))
# hermes' blind eval (v0.79): one merged flag asked two questions and a small
# model heard "a Build needs a profile". Now two names, two questions.
check('C3b needsSDKForBuild y needsProfileForDeploy sustituyen al flag mezclado',
      j.get('platforms') and
      all('needsSDKForBuild' in p and 'needsProfileForDeploy' in p and
          'needsRemoteProfile' not in p for p in j['platforms']),
      j.get('platforms', [{}])[0])

j = jload(call('delphi_config', {'project': dproj, 'section': 'searchpaths'}))
check('C4 section=searchpaths responde su area',
      ('searchPaths' in j) or ('searchPathsNote' in j), list(j.keys()))

rall = call('delphi_config', {'project': dproj, 'section': 'all'})
j = jload(rall)
check('C5 section=all lo trae todo junto (la vista antigua)',
      'units' in j and 'platforms' in j and
      ('searchPaths' in j or 'searchPathsNote' in j) and
      j.get('frameworkType') is not None, list(j.keys()))
check('C6 el summary pesa bastante menos que all',
      len(rsum) < len(rall), (len(rsum), len(rall)))
r = call('delphi_config', {'project': dproj, 'section': 'Marte'})
check('C7 section invalida se rechaza con la lista',
      r.startswith('error: section debe ser') and 'summary' in r and 'units' in r, r)

# ---- symbols modes ---------------------------------------------------------
big = os.path.join(BASE, 'Big.pas')
small = os.path.join(BASE, 'Small.pas')

rbig = call('delphi_symbols', {'path': big})
j = jload(rbig)
check('S1 arbol grande por defecto = summary compacto con secciones',
      j.get('mode') == 'summary' and isinstance(j.get('sections'), list) and
      j.get('totalSymbols', 0) > 50 and 'autoNote' in j, rbig[:260])
# the fixture is Lsp.Guard.pas itself, which grows with the server: assert
# compact relative to a hard ceiling, not to last month's size.
#
# El techo subio de 12k a 14k el 2026-09-20, A PROPOSITO y medido: desde la
# v1.0.7 el resumen da la declaracion REAL del fuente en vez de la firma que
# renderiza DelphiLSP, que se come los valores por defecto y los rangos de los
# arrays. La verdad es mas larga. Medido sobre Lsp.Guard.pas: 11.9k antes,
# 17.3k sin acotar, 12.9k con el tope de 110 por etiqueta y sin el ';' final.
# O sea que decir la verdad cuesta un 7%, y el arbol completo sigue pasando de
# 38k. No se sube el techo para callar el fallo: se sube porque el trato
# cambio y este es su precio.
# Y de 14k a 16k el 2026-09-21, por un motivo distinto: esta vez no cambio
# el trato sino el FIXTURE. Lsp.Guard crecio de verdad con la auditoria
# (TMotivoVeto y PathDenied con motivo, BorraArbol, la purga con instancia
# unica). Medido: 14.198 justo despues. El margen es para que la unidad
# respire sin que cada release toque este numero.
# Y de 16k a 18k el 2026-09-25, por el mismo motivo que la anterior: el
# FIXTURE crecio de verdad. ReadOnlyRoots (WorkspaceReadOnlyRoots,
# ReadOnlyRootOf) y la clasificacion de git en una funcion
# (GitCommandIsQuery), sacada de ToolCallDenied para que la compartan la
# credencial de solo lectura y los proyectos de referencia. Medido: 16.163.
# Y el 2026-09-25 (noche), a PROPORCION: el techo fijo se quedo corto por
# tercera vez por el mismo motivo - el fixture es Lsp.Guard y crece con la
# puerta (MueveArbol y compania: 18.370). Un numero que hay que subir cada
# vez que la unidad crece no mide nada. Lo que importa es que el resumen
# sea COMPACTO frente al arbol completo, y eso no depende del tamano de la
# unidad. Medido ese dia: 18.210 frente a 111.608 (16%). Techo: 25%.
# (David: 'la proporcion, adelante'.)
rfull = call('delphi_symbols', {'path': big, 'mode': 'full'})
check('S1 y de verdad es compacto (el resumen pesa < 25% del arbol completo)',
      len(rfull) > 0 and len(rbig) < 0.25 * len(rfull), (len(rbig), len(rfull)))
check('S2 mode=full conserva el arbol completo con rangos',
      rfull.lstrip().startswith('[') and 'selectionRange' in rfull and
      len(rfull) > 20000, len(rfull))

# hermes (2026-08-26): full must stay byte-stable on an unchanged unit - the
# compaction is additive, never a rewrite of the full tree.
rfull2 = call('delphi_symbols', {'path': big, 'mode': 'full'})
check('S2b mode=full es byte-estable sobre una unit invariante',
      rfull2 == rfull, (len(rfull), len(rfull2)))

rsmall = call('delphi_symbols', {'path': small})
check('S3 un arbol pequeno sigue viniendo entero sin pedirlo',
      rsmall.lstrip().startswith('[') and 'selectionRange' in rsmall, rsmall[:200])

j = jload(call('delphi_symbols', {'path': big, 'filter': 'pathdenied'}))
ms = j.get('matches', [])
check('S4 filter encuentra el simbolo con kind, linea y contenedor',
      j.get('total', 0) >= 2 and ms and
      all('pathdenied' in m['name'].lower() and 'line' in m for m in ms) and
      any('in' in m for m in ms), str(j)[:260])

r = call('delphi_symbols', {'path': big, 'mode': 'arbol'})
check('S5 mode invalido se rechaza explicando los validos',
      r.startswith('error: mode debe ser') and 'summary' in r and 'full' in r, r)

srv.mata()
mc.fin('round-16 battery')
