# -*- coding: utf-8 -*-
"""1.29 (EH8 del revisor del paisaje): la expresion del agente se buscaba con PCRE_NO_UTF8_CHECK, que pide
un texto UTF-16 valido. Un fuente UTF-16 trae sus sustitutos sueltos tal cual (delphi_read los cuenta como
corrupcion, U+FFFD) y PCRE juntaba dos sueltos como si fueran una pareja: '[^a]X' no encontraba una linea y en
otra daba una posicion de mas (medido el 7-nov-2026 contra 958be0fe). Ahora cada suelto se busca como
U+FFFD, uno por uno, y las posiciones son las del texto.

  X1 '[^a]X': las tres lineas, cada una en su posicion (un suelto, dos seguidos, un emoji entero)
  X2 control: la busqueda literal da las mismas posiciones de la X
  X3 '.' se come UN suelto: 'o.X' casa en la linea del suelto
  X4 el servidor sigue vivo

Uso:  python tests/test_regex_sueltos_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('regex_sueltos_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
LINEAS = ['uno\ud800X fin', 'dos \ud800\ud800XY', 'tres ' + '\U0001F600' + 'X', 'cuatro\ud800']
with open(os.path.join(JAIL, 'u16.pas'), 'wb') as f:
    f.write(b'\xff\xfe' + '\r\n'.join(LINEAS).encode('utf-16-le', 'surrogatepass'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='rx129', t=60)


def busca(q, rx):
    r = srv.call('delphi_search', {'root': JAIL, 'query': q, 'regex': rx, 'pattern': '*.pas'})
    j = mc.como_json(r)
    return [(h.get('line'), h.get('character0')) for d in j.get('folders', []) for fi in d.get('files', [])
            for h in fi.get('hits', [])], r


try:
    hits, r = busca('[^a]X', True)
    check('X1 [^a]X: las tres lineas en su posicion (un suelto, dos seguidos, un emoji). ROJO contra 958be0fe: '
          'falta la primera y la segunda sale una antes', hits == [(1, 3), (2, 5), (3, 5)], (hits, r[:200]))
    literal, r = busca('X', False)
    regex, r2 = busca('X', True)
    check('X2 control: la X literal y por regex en las mismas posiciones', literal == regex == [(1, 4), (2, 6), (3, 7)],
          (literal, regex))
    hits, r = busca('o.X', True)
    check('X3 "." se come UN sustituto suelto', hits == [(1, 2)], (hits, r[:200]))
    check('X4 el servidor sigue vivo', not mc.fallo(srv.call('delphi_list', {'root': JAIL})))
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('regex con sustitutos sueltos (1.29)')
