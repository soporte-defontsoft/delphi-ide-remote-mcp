# -*- coding: utf-8 -*-
"""La regex del AGENTE no tumba el servidor (Lsp.Regex.TExprDelAgente).

Medido el 6-oct-2026 (1.15.0): PCRE recursa en la pila de C y, sin tope
propio, su limite de recursion es el de pasos (diez millones): (?:a|b)*c sobre
una linea de 2.000 caracteres ya daba "Stack overflow" (SYS-006). El proceso
aguanta el primero y el SEGUNDO desbordamiento lo TUMBA (la pagina de guarda
de la pila ya se gasto): dos busquedas de una credencial de solo lectura
bastaban para tirar el servicio. Con match_limit_recursion propio, PCRE se
rinde y lo dice (SEARCH-005).

  P1  stdio, delphi_search: la linea larga CINCO veces en el MISMO proceso ->
      SEARCH-005 cada vez, y el servidor sigue contestando
  P2  stdio, vault_search (la misma puerta, el otro llamador): igual
  P3  HTTP (el modo del servicio, hilos de Indy): igual, en la misma sesion
  P4  control: el MISMO patron en una linea corta sigue encontrando (el tope no
      corta lo normal)

Mutante (medido con el binario de antes del tope): P1 y P2 rojos, el primer
desborde da SYS-006 y el proceso muere en la segunda busqueda; P3 rojo, desborda
las cinco veces sin morir (cada peticion de este cliente abre conexion, y con
ella hilo, nuevo: no gasta dos veces la misma pagina de guarda); P4 verde, es
el control.

Uso:  python tests/test_regex_pila.py [exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

LARGA = 'ab' * 50000          # 100.000 caracteres: muy por encima del desborde
PATRON = '(?:a|b)*c'          # un grupo con alternativa repetido: un nivel por caracter
VECES = 5

BASE = mc.carpeta('regexpila')
JAIL = os.path.join(BASE, 'jail')
VAULT = os.path.join(BASE, 'vault')
for d in (os.path.join(JAIL, 'larga'), os.path.join(JAIL, 'corta'), VAULT):
    os.makedirs(d, exist_ok=True)
with open(os.path.join(JAIL, 'larga', 'f.txt'), 'w') as f:
    f.write(LARGA + '\n')
with open(os.path.join(JAIL, 'corta', 'f.txt'), 'w') as f:
    f.write('ab' * 100 + 'c\n')
with open(os.path.join(VAULT, 'MEMORY.md'), 'w') as f:
    f.write('# indice\n')
with open(os.path.join(VAULT, 'nota.md'), 'w') as f:
    f.write('# nota\n\n' + LARGA + '\n')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def vivo(llama):
    try:
        return '"server"' in llama('delphi_workspace', {})
    except Exception:
        return False


def cinco(llama, tool, args):
    """VECES llamadas en el MISMO proceso: cuantas dijeron SEARCH-005 y si
    sigue vivo despues de cada una."""
    res = []
    for _ in range(VECES):
        try:
            r = llama(tool, args)
        except Exception as e:
            r = 'EXCEPCION %r' % e
        res.append((mc.es(r, 'SR_SEARCH_REGEX_CARA_FMT'), 'Stack overflow' in r, vivo(llama), r[:160]))
        if not res[-1][2]:
            break
    return res


def resumen(res):
    return ' | '.join('rinde=%s desborda=%s vivo=%s' % (a, b, c) for a, b, c, _ in res) + ' | ' + res[-1][3]


ENT = mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_VAULT_PATH': VAULT,
                  'DELPHI_MCP_VAULT_READONLY': '1'})


def con_servidor(fn):
    """Cada caso con SU servidor stdio: si uno lo tumba (el mutante), el
    siguiente mide lo suyo y no la caida del anterior."""
    srv = mc.Stdio(EXE, ENT, nombre='regexpila', t=300)
    try:
        return fn(srv.call)
    finally:
        try: srv.mata()
        except Exception: pass


res = con_servidor(lambda llama: cinco(llama, 'delphi_search', {
    'root': os.path.join(JAIL, 'larga'), 'query': PATRON, 'regex': True, 'pattern': '*.txt'}))
check('P1 stdio delphi_search: %d veces la linea larga, SEARCH-005 y vivo' % VECES,
      len(res) == VECES and all(a and not b and c for a, b, c, _ in res), resumen(res))

res = con_servidor(lambda llama: cinco(llama, 'vault_search', {'target': 'content', 'pattern': PATRON}))
check('P2 stdio vault_search: %d veces la nota larga, SEARCH-005 y vivo' % VECES,
      len(res) == VECES and all(a and not b and c for a, b, c, _ in res), resumen(res))


def corta(llama):
    try:
        return llama('delphi_search', {'root': os.path.join(JAIL, 'corta'), 'query': PATRON,
                                       'regex': True, 'pattern': '*.txt'})
    except Exception as e:
        return 'EXCEPCION %r' % e


r = con_servidor(corta)
check('P4 control: el mismo patron en una linea de 201 caracteres sigue encontrando',
      (mc.como_json(r) or {}).get('total') == 1, r[:200])

TOKEN = 'regexpila-token'
WORK = os.path.join(BASE, 'http')
os.makedirs(WORK)
EXE_H = mc.copia_exe(WORK)
with open(os.path.join(WORK, 'settings.ini'), 'w') as f:
    f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\n' % (TOKEN, JAIL))
PORT = mc.puerto_libre()
proc = mc.lanza_http(EXE_H, PORT, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'}))
try:
    cli = mc.Http(PORT, TOKEN, t=300)
    cli.session('regexpila')
    res = cinco(cli.call, 'delphi_search', {'root': os.path.join(JAIL, 'larga'), 'query': PATRON,
                                            'regex': True, 'pattern': '*.txt'})
    check('P3 HTTP (modo servicio): %d veces la linea larga en la misma sesion, SEARCH-005 y vivo' % VECES,
          len(res) == VECES and all(a and not b and c for a, b, c, _ in res) and proc.poll() is None,
          resumen(res))
finally:
    try: proc.kill()
    except Exception: pass

try:
    mc.fin('regex de pila battery')  # sys.exit: la carpeta se borra en el finally
finally:
    mc.borra(BASE)
