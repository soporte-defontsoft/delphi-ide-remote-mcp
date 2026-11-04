# -*- coding: utf-8 -*-
"""V13: lo que dice el build lo clasifica su juez, no una subcadena.

errors[], warnings[] y hints[] salian de buscar ': error ', ' error E', ' warning W'... en cada linea de la consola
de msbuild: con normal, un aviso cuyo texto dice ': error' iba a errors[] con success=true; con verbose, una carpeta
'Mi error Ejemplo' mandaba alli todas las lineas que la nombran, y cada aviso salia dos veces. msbuild los separa el
solo en sus ficheros (/flp errorsonly, warningsonly), y el resumen de DUnitX es el ULTIMO de la salida, no el primero
que un test haya escrito.

Usage:  python tests/test_build_juez_125.py [path-to-DelphiLspMcp.exe]
"""
import json, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build-juez-125')
EXE = mc.copia_exe(BASE)
RAIZ = os.path.join(BASE, 'raiz')
os.makedirs(RAIZ)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': RAIZ, 'DELPHI_MCP_ALLOW_TESTS': '1'}), nombre='build-juez')
call = srv.call


def consola(nombre, carpeta, antes='', cuerpo=None, uses=''):
    d = os.path.join(RAIZ, carpeta)
    call('delphi_create', {'kind': 'project-console', 'name': nombre, 'dir': d})
    dpr = os.path.join(d, nombre + '.dpr')
    with open(dpr, encoding='utf-8-sig', newline='') as f:
        t = f.read()
    i = t.find('\nbegin')
    if cuerpo is not None:
        t = t[:i + 1] + antes + 'begin\r\n' + cuerpo + 'end.\r\n'
    else:
        t = t[:i + 1] + antes + t[i + 1:]
    if uses:
        t = t.replace('uses', 'uses\r\n  %s,' % uses, 1)
    with open(dpr, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(t)
    return os.path.join(d, nombre + '.dproj')


def compila(p, verbosidad=''):
    a = {'project': p, 'platform': 'Win64', 'config': 'Debug'}
    if verbosidad:
        a['verbosity'] = verbosidad
    return mc.como_json(call('delphi_build', a, t=180)) or {}


try:
    # el texto de un aviso no lo convierte en error
    MENSAJES = ("{$MESSAGE WARN 'nota: error de prueba'}\r\n{$MESSAGE HINT 'otra: fatal de prueba'}\r\n"
                "{$MESSAGE 'plana: error x'}\r\n")
    P = consola('PMsg', 'Msg', MENSAJES)
    for v in ('normal', 'verbose'):
        j = compila(P, v)
        check('%s: un aviso que dice ": error" no es un error' % v, j.get('success') is True and j.get('errors') == [], str(j)[:500])
        w = j.get('warnings') or []
        h = j.get('hints') or []
        check('%s: va a warnings[], una vez' % v, len(w) == 1 and 'W1054' in w[0] and 'nota: error de prueba' in w[0], str(j)[:500])
        check('%s: los hints a hints[], una vez' % v, len(h) == 2 and all('H1054' in x for x in h), str(j)[:500])
        check('%s: sin firstError' % v, 'firstError' not in j, str(j)[:300])
        check('%s: ni repetidos en la cola' % v, 'W1054' not in (j.get('outputTail') or '') and 'H1054' not in (j.get('outputTail') or ''), (j.get('outputTail') or '')[-400:])
    j = compila(P)
    check('quiet: errors[] vacio y sin las otras listas', j.get('errors') == [] and 'warnings' not in j and 'hints' not in j, str(j)[:300])
    check('quiet: nada de los avisos en la respuesta', 'W1054' not in json.dumps(j) and 'H1054' not in json.dumps(j), str(j)[:300])

    # el nombre de la carpeta tampoco
    A = "{$MESSAGE WARN 'aviso normal'}\r\n{$MESSAGE HINT 'pista normal'}\r\n"
    P = consola('PCarp', 'Mi error Ejemplo', A)
    for v in ('normal', 'verbose'):
        j = compila(P, v)
        check('carpeta con " error E", %s: ningun error' % v, j.get('success') is True and j.get('errors') == [], str(j)[:400])
        check('carpeta con " error E", %s: el aviso y el hint, solos' % v,
              len(j.get('warnings') or []) == 1 and len(j.get('hints') or []) == 1, str(j)[:400])
    P = consola('QCarp', 'Mi warning Wizard', A)
    j = compila(P, 'verbose')
    check('carpeta con " warning W", verbose: un aviso y un hint', len(j.get('warnings') or []) == 1 and len(j.get('hints') or []) == 1, str(j)[:400])

    # la casa del servidor no se ve
    check('verbose: la linea de msbuild no ensena donde deja sus logs', 'logfile' not in json.dumps(j).lower() and 'flp' not in json.dumps(j).lower(), json.dumps(j)[:400])
    casa = [os.path.join(r, d) for r, ds, _ in os.walk(BASE) for d in ds if d == 'build-logs']
    check('sus logs viven en la casa del servidor', len(casa) == 1, casa)
    check('...y no quedan', not any(fs for c in casa for _, _, fs in os.walk(c)), casa)

    # un error de verdad, sigue siendo error; una unidad que falta, tambien
    P = consola('PErr', 'Err', cuerpo='  NoExiste := 1;\r\n')
    j = compila(P, 'quiet')
    check('E2003 en errors[] y en firstError', j.get('success') is False and len(j.get('errors') or []) == 1 and 'E2003' in j['errors'][0] and 'E2003' in j.get('firstError', ''), str(j)[:400])
    check('la ruta del .dproj fuera de la linea', '.dproj' not in j['errors'][0], j['errors'][0])
    P = consola('PFat', 'Fat', uses='UnidadQueNoExiste')
    j = compila(P, 'quiet')
    check('F2613 en errors[] y en missingUnits', j.get('success') is False and any('F2613' in e for e in j.get('errors') or []) and any(m.get('unit') == 'UnidadQueNoExiste' for m in j.get('missingUnits') or []), str(j)[:500])

    # el codigo de un fallo es el del compilador: el nombre de la carpeta no reintenta el build
    P = consola('PBloq', 'F2039Demo', cuerpo='  NoExiste := 1;\r\n')
    j = compila(P, 'normal')
    check('un E2003 en una carpeta F2039Demo: sin reintentos ni nota de binario abierto',
          j.get('success') is False and any('E2003' in e for e in j.get('errors') or []) and
          'lockedRetries' not in j and 'lockedOutputNote' not in j, str(j)[:400])  # su E2003, no otro fallo (revisor de baterias de la 1.27)

    # lo que no es ASCII, tal cual lo dijo dcc
    P = consola('PAcc', 'Acc', "{$MESSAGE WARN 'año y acción'}\r\n")
    j = compila(P, 'normal')
    check('un aviso con acentos llega con sus acentos', any('año y acción' in w for w in j.get('warnings') or []), str(j)[:400])

    # DUnitX: su resumen es el ultimo, no el primero que escriba un test. Y no cierra la salida:
    # detras van sus bloques, con el Message de cada test (DUnitX.Loggers.Console)
    REC = "var\r\n  DUnitX: record Foo: Integer end;\r\n"


    def salida(nombre, lineas, codigo):
        cuerpo = "  DUnitX.Foo := 1;\r\n" + ''.join("  Writeln('%s');\r\n" % x for x in lineas) + "  System.ExitCode := %d;\r\n" % codigo
        return mc.como_json(call('delphi_test', {'project': consola(nombre, nombre, REC, cuerpo)}, t=240)) or {}


    RESUMEN = ['Tests Found   : 5', 'Tests Ignored : 0', 'Tests Passed  : %d', 'Tests Leaked  : 0', 'Tests Failed  : %d', 'Tests Errored : 0']
    j = salida('MsgRojo', [x % {2: 4, 4: 1}[i] if '%' in x else x for i, x in enumerate(RESUMEN)] +
               ['', 'Failing Tests', '', '  T.UnTest', '  Message: Expected Tests Failed : 0', ''], 0)
    check('DUnitX: el Message de un test rojo no es la cuenta, y una suite roja no sale verde',
          j.get('result') == 'fail' and j.get('failed') == 1 and j.get('passed') == 4, str(j)[:400])
    check('...y el fallo sale en failures, con su mensaje', any('T.UnTest' in x and 'Expected' in x for x in j.get('failures') or []), str(j)[:400])
    j = salida('RuidoBloque', ['Failing Tests', 'esto lo escribio un test'] + [x % {2: 5, 4: 0}[i] if '%' in x else x for i, x in enumerate(RESUMEN)], 0)
    check('DUnitX: un test que escribe "Failing Tests" antes del resumen no llena failures',
          j.get('result') == 'pass' and j.get('failures') == [], str(j)[:400])


    def suite(nombre, ruido, fallos, salida):
        cuerpo = ("  DUnitX.Foo := 1;\r\n  Writeln('Tests Found   : 5');\r\n  Writeln('Tests Passed  : 5');\r\n  Writeln('%s');\r\n"
                  "  Writeln('Tests Found   : 5');\r\n  Writeln('Tests Passed  : %d');\r\n  Writeln('Tests Failed  : %d');\r\n  Writeln('Tests Errored : 0');\r\n"
                  "  System.ExitCode := %d;\r\n") % (ruido, 5 - fallos, fallos, salida)
        return mc.como_json(call('delphi_test', {'project': consola(nombre, nombre, REC, cuerpo)}, t=240)) or {}


    j = suite('Ruido7Verde', 'Tests Failed : 7', 0, 0)
    check('DUnitX: verde aunque un test escriba "Tests Failed : 7"', j.get('result') == 'pass' and j.get('failed') == 0 and j.get('passed') == 5, str(j)[:400])
    j = suite('Ruido0Rojo', 'Tests Failed : 0', 1, 1)
    check('DUnitX: rojo con su cuenta aunque un test escriba "Tests Failed : 0"', j.get('result') == 'fail' and j.get('failed') == 1 and j.get('passed') == 4, str(j)[:400])
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('build judge 1.25 battery')
