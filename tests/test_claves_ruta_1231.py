# -*- coding: utf-8 -*-
"""V82 de la 1.23.1: la clave de "ya visto" de una ruta, por el pliegue del disco.

Los recorredores de Lsp.Guard (WalkFiles, CopiaArbol, EnlaceAjenoEn) guardaban
las rutas reales ya recorridas en un TStringList ordenado y sin mayusculas, que
compara con AnsiCompareText: el locale da por IGUALES 22 pares de nombres que
NTFS separa (medido el 27-oct-2026 contra CompareStringOrdinal): ss y la eszett,
k y el signo Kelvin. Con dos enlaces a dos carpetas asi, el recorrido se saltaba
la segunda EN SILENCIO: delphi_list y delphi_search no la veian, y delphi_move
copy=true contestaba COPIED sin copiarla. Ahora la clave es ClaveDeRuta (Lsp.Rutas:
las mayusculas invariantes, que juntan lo que junta el disco) comparada exacta.

  R1 list por cuatro enlaces (a ss, eszett, k y Kelvin): los cuatro ficheros
     (ROJO contra 1.23.x: faltaban los de la eszett y Kelvin)
  R2 ...search entra en los cuatro (ROJO contra 1.23.x)
  R3 ...y copy=true los copia los cuatro (ROJO contra 1.23.x: COPIED sin dos)
  C1 control: NTFS tiene las cuatro carpetas a la vez (son cuatro entradas)
  C2 control: un enlace dos veces a la MISMA carpeta se recorre una vez (el
     corte de ciclos sigue: la clave junta lo que el disco junta)

Uso:  python tests/test_claves_ruta_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('claves_ruta_1231')
JAIL = os.path.join(BASE, 'jail')
REAL = os.path.join(JAIL, 'real')
PASEO = os.path.join(JAIL, 'paseo')
PARES = (('j1', 'ss', 'EnSs.pas'), ('j2', 'ß', 'EnEszett.pas'),
         ('j3', 'k', 'EnK.pas'), ('j4', 'K', 'EnKelvin.pas'))
TODOS = sorted(f for _, _, f in PARES)
os.makedirs(PASEO)
for j, d, f in PARES:
    os.makedirs(os.path.join(REAL, d))
    open(os.path.join(REAL, d, f), 'w', encoding='utf-8').write('unit %s;\ninterface\nimplementation\nend.\n' % f[:-4])
    mc.junction(os.path.join(PASEO, j), os.path.join(REAL, d))
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='claves-ruta', t=120)


def nombrados(r):
    return sorted(n for n in TODOS if n in r)


try:
    check('C1 control: NTFS tiene las cuatro carpetas a la vez',
          sorted(os.listdir(REAL)) == sorted(d for _, d, _ in PARES), [ascii(n) for n in os.listdir(REAL)])
    r = s.call('delphi_list', {'root': PASEO})
    check('R1 list por enlaces a ss, eszett, k y Kelvin: los cuatro ficheros (ROJO contra 1.23.x)',
          nombrados(r) == TODOS, (nombrados(r), r[:400]))
    r = s.call('delphi_search', {'root': PASEO, 'query': 'implementation'})
    check('R2 ...search entra en los cuatro (ROJO contra 1.23.x)', nombrados(r) == TODOS, (nombrados(r), r[:400]))
    COPIA = os.path.join(JAIL, 'copia')
    r = s.call('delphi_move', {'path': PASEO, 'dest': COPIA, 'copy': True})
    copiados = sorted(f for j, _, f in PARES if os.path.isfile(os.path.join(COPIA, j, f)))
    check('R3 ...y copy=true los copia los cuatro (ROJO contra 1.23.x: COPIED sin dos)',
          not mc.rechazado(r) and copiados == TODOS, (copiados, r[:300]))

    # el corte de ciclos sigue: dos enlaces a la MISMA carpeta, una sola vez
    DOBLE = os.path.join(JAIL, 'doble')
    os.makedirs(DOBLE)
    mc.junction(os.path.join(DOBLE, 'a'), os.path.join(REAL, 'ss'))
    mc.junction(os.path.join(DOBLE, 'b'), os.path.join(REAL, 'SS'))
    r = s.call('delphi_list', {'root': DOBLE})
    check('C2 control: dos enlaces a la misma carpeta (ss y SS) se recorren una vez', r.count('EnSs.pas') == 1, r[:400])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('la clave de una ruta, por el pliegue del disco 1.23.1 (V82)')
