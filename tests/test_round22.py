# -*- coding: utf-8 -*-
"""E2E battery for v0.86.0-beta - the Linux64 outputTail over-masking.

sweep10 reported Linux64 build tails collapsed into "srvhost" everywhere;
reproduced 2026-08-26 with a real Linux64 link: 227 masks in one tail. Root
cause: the Linux64 linker echoes its command line with backslashes ALREADY
doubled; the JSON encoding doubles them again, and the masker's JSON-UNC rule
(four backslashes + letter) fired on EVERY re-doubled separator because its
look-behind only required "not a backslash". A genuine UNC never starts glued
to a letter - the rule now requires a delimiter before it, same as the raw
form.

  M1  linker-style re-doubled paths survive legibly (no srvhost cascade)
  M2  a genuine UNC host is still masked (after quote, raw and JSON forms)
  M3  drive letters still masked in the same text
  M4  (live, only if this machine holds the Linux64 SDK) a real Linux64 link
      asked with verbosity=verbose, the only mode that carries the whole line:
      outputTail carries ZERO srvhost and a legible "Linker command line"

Usage:  python tests/test_round22.py [path-to-DelphiLspMcp.exe]
"""
import json, os, glob
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('round22')
EXE = mc.copia_exe(BASE)

# plazo de 300 s: hay un link Linux64
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='round22', t=300)
call = srv.call

# The masker runs on every textual result, so delphi_read of a crafted file
# exercises it machine-independently. The file reproduces the linker-echo
# shape: paths with backslashes ALREADY doubled in the raw text.
BS = chr(92)
D2 = BS + BS          # doubled separator, as the linker echoes it
lines = [
    'Linker command line: -o .' + D2 + 'Linux64' + D2 + 'Debug' + D2 + 'App'
    + ' --sysroot C:' + D2 + 'Users' + D2 + 'yo' + D2 + 'Documents' + D2 + 'SDKs'
    + ' -L "C:' + D2 + 'Program Files (x86)' + D2 + 'Embarcadero' + D2 + 'lib"',
    'copia real en "' + BS + BS + 'nas01' + BS + 'backups' + BS + 'x.dcu"',
]
probe = os.path.join(BASE, 'echo.txt')
open(probe, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')

# El enmascarador corre sobre todo texto de salida MENOS el de las tools de
# fidelidad byte a byte: delphi_read, los aciertos de delphi_search, los
# lectores del vault y el eco de verificacion de delphi_edit/delphi_textedit.
# En todas ellas el texto es CONTENIDO DE FICHERO y un ancla copiada de ahi
# tiene que casar con el disco (v1.0.4-beta: el search enmascaraba dentro de
# la linea encontrada, asi que ningun ancla copiada de un resultado casaba).
# Antes esta sonda usaba delphi_search como canal enmascarado; ya no lo es,
# asi que va por una NEGATIVA, que se enmascara siempre y ademas prueba al
# enmascarador mas directamente: la ruta entra tal cual y vuelve tapada.
r = call('delphi_read', {'path': 'C:' + D2 + 'Users' + D2 + 'yo' + D2 +
                         'Linux64' + D2 + 'Embarcadero' + D2 + 'NoExiste.pas'})
check('M1 rutas re-dobladas legibles (cero cascada srvhost)',
      r.count('srvhost') == 0 and 'Linux64' in r and 'Users' in r and
      'Embarcadero' in r, 'srvhost x%d | %s' % (r.count('srvhost'), r[:220]))
r2 = call('delphi_read', {'path': BS + BS + 'nas01' + BS + 'backups' + BS +
                          'x.pas'})
check('M2 el UNC de verdad SI se enmascara (nas01 desaparece)',
      'nas01' not in r2 and 'srvhost' in r2, r2[:220])
check('M3 las unidades siguen enmascaradas (srvc:)',
      'srvc:' in r and 'C:' + D2 not in r, r[:220])
# ...y el contrato NUEVO, el que rompio a los de arriba: el texto de un
# acierto de delphi_search llega VERBATIM, con su letra de unidad real, para
# que sirva de ancla. La ruta del acierto si sale virtual.
rs = call('delphi_search', {'root': probe, 'query': 'copia real'})
check('M3b el TEXTO de un acierto de search llega verbatim (ancla valida)',
      'nas01' in rs, rs[:220])
check('M3c ...pero su campo path si viaja como unidad virtual',
      '"path":"srv' in rs.replace(' ', ''), rs[:220])

# La unidad SIN separador detras. El enmascarador pedia <letra>:<separador>,
# asi que "D:" a secas y "D:relativo\x" salian con la LETRA REAL en cada
# negativa que echoa el parametro de quien llama - en TODAS las tools, no solo
# en una (medido 2026-09-20). Y como C:\Windows si salia como srvc:, el lector
# deducia el mapeo entero. El arreglo va en MaskDriveText, que es el UNICO
# punto de salida: parchear los emisores uno a uno es como sobrevivio esto.
for sonda in ('D:', 'C:', 'D:relativo' + BS + 'x'):
    r = call('delphi_list', {'root': sonda})
    check('M5 la unidad sin separador no filtra la letra real (%r)' % sonda,
          ('"' + sonda[:2] + '"') not in r and (sonda[:2] + BS) not in r
          and 'srv' in r, r[:200])

# ...y el reves, que es el riesgo del arreglo: NO enmascarar de mas. Un dos
# puntos seguido de espacio no es una unidad.
r = call('delphi_workspace', {})
check('M5b no se enmascara de mas: la respuesta normal sigue siendo JSON '
      'valido y sin srvsrv',
      'srvsrv' not in r and r.lstrip().startswith('{'), r[:200])

# M4 live: a real Linux64 link on machines that hold the SDK
r = call('delphi_create', {'kind': 'project-console', 'name': 'TailM', 'dir': BASE})
dpr = glob.glob(os.path.join(BASE, '**', 'TailM.dpr'), recursive=True)
M4 = 'M4 link Linux64 real: outputTail sin srvhost y linker legible'
if not dpr:
    check(M4, False, 'no se pudo crear el proyecto de la prueba: ' + r[:200])
else:
    dproj = dpr[0][:-4] + '.dproj'
    call('delphi_config', {'project': dproj, 'command': 'add-platform',
                           'platform': 'Linux64'})
    # verbosity=verbose a proposito: lo que se comprueba aqui es que el
    # enmascarador NO mete srvhost en la linea del linker, y esa linea solo
    # viaja entera en verbose - en quiet (el defecto desde la v1.0.3) la cola
    # del build ni la trae, y en normal viene resumida a su --sysroot.
    out = call('delphi_build', {'project': dproj, 'platform': 'Linux64',
                                'verbosity': 'verbose',
                                'config': 'Debug'}, 600)
    try:
        j = json.loads(out)
    except Exception:
        j = {}
    if j.get('success') is True:
        tail = j.get('outputTail') or ''
        check(M4,
              'srvhost' not in tail and 'Linker command line' in tail
              and 'sysroot' in tail, 'srvhost x%d' % tail.count('srvhost'))
    elif 'success' in j and not j.get('sdk'):
        # SOLO esto es "sin SDK": el build CORRIO y el servidor no encontro
        # ningun SDK de Linux64 con el que enlazar (la respuesta de un build
        # con SDK lo nombra en "sdk")
        print('SKIP M4: esta maquina no tiene SDK de Linux64 (el build corrio sin '
              'ninguno); M1-M3 cubren el masker')
    else:
        # un build con SDK que falla, un RECHAZADO, un timeout...: eso no es
        # "esta maquina no linka", es un fallo
        check(M4, False, out[:300])

srv.mata()
mc.fin('round-22 battery')
