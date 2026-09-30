# -*- coding: utf-8 -*-
"""E2E battery for the LIFE of the LSP engines (1.8.0): the server's sweeper
stops the engines nobody uses and the ones that hang, by itself, and the next
request of the project starts another.

Until 1.8.0 an engine lived until its folder left or the server stopped: each
one at rest keeps 125 MB (measured 2026-09-30 on a 60-unit project), and one
that stopped reading kept the requests of its project waiting - 30 s each
while they fitted in its pipe, and with no bound once it was full.

  V1  [Server] EngineIdleMinutes (0.2 here: twelve seconds): an engine nobody
      uses for that long is stopped - the server has no engine left -, the
      log says why, and the next request starts another and answers
  V0  DELPHI_MCP_ENGINE_IDLE_MINUTES in the environment wins over the ini
      (which still says twelve seconds): with 0 the engine is still there,
      the same one, after eighteen
  V3  a request a HEALTHY engine never answers does not get it stopped. The
      completion whose trigger is a double quote went to the engine as broken
      JSON, and the engine answers NOTHING to what it cannot parse (measured):
      now it goes as JSON and is answered, by the same engine
  V2  a HUNG engine (suspended here: no message, no CPU, no I/O, no answer
      when asked) with a request waiting for its answer: whoever waited is
      told LSP-033 by the server ITSELF; the engine is gone, the log says why,
      and the request repeated starts another and answers
  V2b the same with a WRITE the engine is not reading - a request that opens
      a file too big for its pipe: the case that had no bound at all

Usage:  python tests/test_motor_vida.py [path-to-DelphiLspMcp.exe]
"""
import os, subprocess, threading, time
import mcp_cliente as mc
from mcp_cliente import check

TOPE = 90
BASE = mc.carpeta('motor-vida')
SRVDIR = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRVDIR)
TOKEN = 'test-token-vida'
LOG = os.path.join(SRVDIR, 'logs', 'actual.log')
NL = chr(10)


def lanza(entorno=None):
    puerto = mc.puerto_libre()
    with open(os.path.join(SRVDIR, 'settings.ini'), 'w') as f:
        f.write('[Server]' + NL + 'Port=%d' % puerto + NL + 'BindIP=127.0.0.1' + NL
                + 'EngineIdleMinutes=0.2' + NL * 2
                + '[Workspace.Op]' + NL + 'Token=%s' % TOKEN + NL + 'Roots=%s' % BASE + NL
                + 'DelphiVersion=37.0' + NL)
    proc = mc.lanza_http(EXE, None, mc.entorno(entorno), espera_en=puerto)
    return proc, puerto


def cliente(puerto, t=TOPE):
    c = mc.Http(puerto, TOKEN, t=t)
    c.session('vida')
    return c


def caliente(c, dpr, intentos=8):
    h = ''
    for _ in range(intentos):
        h = c.call('delphi_hover', {'path': dpr, 'line': 9, 'character': 4})
        if 'TApplication' in h:
            return True, h
        time.sleep(2)
    return False, h


def proyecto(c, nombre):
    d = os.path.join(BASE, nombre)
    c.call('delphi_create', {'kind': 'project-vcl', 'name': nombre, 'dir': d})
    return d, os.path.join(d, nombre + '.dpr')


def apuntado(que, minimo=1, segundos=8):
    # las lineas del log del servidor sobre sus motores que dicen eso. El
    # servidor apunta DESPUES de parar el motor, y el log se vuelca cada medio
    # segundo: se esperan, hasta ese tope, las que tiene que haber
    t0 = time.time()
    while True:
        try:
            r = [' '.join(l.split())[:200] for l in open(LOG, encoding='utf-8', errors='replace')
                 if 'lsp: ENGINE' in l and que in l]
        except Exception:
            r = []
        if len(r) >= minimo or time.time() - t0 > segundos:
            return r
        time.sleep(0.5)


def pide(puerto, res, tool, args):
    # una peticion en un hilo, con SU sesion, y lo que tardo
    t = time.time()
    try:
        res['v'] = cliente(puerto).call(tool, args)
    except Exception as e:
        res['v'] = 'EXCEPCION %s: %s' % (type(e).__name__, e)
    res['dt'] = time.time() - t


def se_va(proc, pids, segundos=20):
    # espera a que esos motores dejen de ser hijos del servidor; devuelve los que sigan
    t0 = time.time()
    quedan = set(pids)
    while quedan and time.time() - t0 < segundos:
        time.sleep(1)
        quedan = set(mc.hijos_lsp(proc.pid)) & set(pids)
    return sorted(quedan), time.time() - t0


def acaba(proc):
    try:
        motores = mc.hijos_lsp(proc.pid)
    except Exception:
        motores = []
    proc.kill()
    proc.wait()
    for pid in motores:
        subprocess.run(['taskkill', '/PID', str(pid), '/F'], capture_output=True)


# ---------------------------------------------------------------- V1
proc, puerto = lanza()
try:
    uno = cliente(puerto)
    d, dpr = proyecto(uno, 'Uno')
    ok, h = caliente(uno, dpr)
    antes = mc.hijos_lsp(proc.pid)
    check('V1 (preparacion) el proyecto tiene su motor caliente', ok and len(antes) >= 1,
          'motores %s | %s' % (antes, ' '.join(h.split())[:120]))
    quedan, dt = se_va(proc, antes, 40)
    check('V1 el motor que nadie usa en EngineIdleMinutes (aqui 12 s) lo para el servidor solo (%.0f s despues): '
          'no le queda ninguno' % dt, antes != [] and quedan == [] and mc.hijos_lsp(proc.pid) == [],
          'habia %s, quedan %s' % (antes, quedan))
    dicho = apuntado('not used for')
    check('V1 ...y el log del servidor dice por que lo paro', len(dicho) >= 1, dicho)
    t0 = time.time()
    ok, h = caliente(uno, dpr)
    dt = time.time() - t0
    ahora = mc.hijos_lsp(proc.pid)
    check('V1 ...y la peticion siguiente arranca OTRO motor y contesta (%.1f s hasta su primera respuesta)' % dt,
          ok and ahora != [] and not (set(ahora) & set(antes)),
          'antes %s, ahora %s | %s' % (antes, ahora, ' '.join(h.split())[:120]))
finally:
    acaba(proc)

# ------------------------------------------------- V0, V3, V2 y V2b
# El ini sigue diciendo 0.2: el entorno gana
proc, puerto = lanza({'DELPHI_MCP_ENGINE_IDLE_MINUTES': '0'})
try:
    uno = cliente(puerto)
    d, dpr = proyecto(uno, 'Dos')
    ok, h = caliente(uno, dpr)
    antes = mc.motores_en(proc.pid, d)
    time.sleep(18)      # el plazo del ini (12 s) y tres pasadas del barrendero
    sigue = mc.motores_en(proc.pid, d)
    check('V0 el entorno gana al ini (que dice 12 s): con DELPHI_MCP_ENGINE_IDLE_MINUTES=0 el motor sin uso '
          'SIGUE a los 18 s, el mismo', ok and len(antes) == 1 and sigue == antes,
          'antes %s, 18 s despues %s' % (antes, sigue))

    # V3 - una peticion que un motor sano no contestaba nunca
    t0 = time.time()
    r = uno.call('delphi_completion', {'path': dpr, 'line': 9, 'character': 4, 'trigger': '"'})
    dt = time.time() - t0
    check('V3 la completion cuyo trigger es una comilla SE CONTESTA (%.1f s), y el motor sigue siendo el mismo: '
          'iba al motor como JSON roto, y a eso no contesta nada' % dt,
          dt < 15 and not mc.fallo(r) and '"items"' in r and 'timed out' not in r
          and mc.motores_en(proc.pid, d) == antes, ' '.join(r.split())[:160])

    # V2 - el motor colgado, con una peticion que espera su respuesta
    parado = len(antes) == 1 and mc.suspende(antes[0])
    res = {}
    hilo = threading.Thread(target=pide, args=(puerto, res, 'delphi_hover', {'path': dpr, 'line': 9, 'character': 4}))
    hilo.start()
    hilo.join(TOPE)
    v, dt = res.get('v', '(sin respuesta en %d s)' % TOPE), res.get('dt', TOPE)
    check('V2 (preparacion) el motor del proyecto, suspendido: asi se ve uno colgado', parado, antes)
    check('V2 a la peticion en vuelo sobre un motor COLGADO el servidor le contesta LSP-033 por si mismo (%.0f s), '
          'no "timed out" a los 30 de su plazo' % dt, mc.es(v, 'SR_LSP_ENGINE_STOPPED'), ' '.join(v.split())[:160])
    # a quien esperaba se le contesta al RETIRAR el motor; acabar el proceso
    # (pedirle shutdown 1 s, esperarle 2 s, acabarlo) viene detras: se le espera
    colgado, dt = se_va(proc, antes)
    dicho = apuntado('no sign of life')
    check('V2 ...el log dice por que lo paro, y el proceso colgado ya no esta (%.0f s despues)' % dt,
          len(dicho) >= 1 and not colgado, 'sigue %s | %s' % (colgado, dicho))
    ok, h = caliente(uno, dpr)
    ahora = mc.motores_en(proc.pid, d)
    check('V2 ...y la peticion REPETIDA arranca otro motor y contesta',
          ok and ahora != [] and not (set(ahora) & set(antes)),
          'antes %s, ahora %s | %s' % (antes, ahora, ' '.join(h.split())[:120]))

    # V2b - el motor colgado, con una ESCRITURA que no lee: abrir un fichero que
    # no cabe en su tuberia. Esa peticion no tenia plazo ninguno
    d3, dpr3 = proyecto(uno, 'Tres')
    grande = os.path.join(d3, 'Grande.pas')
    with open(grande, 'w') as f:
        f.write('unit Grande;' + NL * 2 + 'interface' + NL * 2 + 'implementation' + NL * 2
                + ''.join('// relleno %06d para que no quepa en la tuberia' % i + NL for i in range(4000))
                + NL + 'end.' + NL)
    ok3, h = caliente(uno, dpr3)
    motor3 = mc.motores_en(proc.pid, d3)
    parado3 = len(motor3) == 1 and mc.suspende(motor3[0])
    n_antes = len(apuntado('no sign of life', 0))
    res = {}
    hilo = threading.Thread(target=pide, args=(puerto, res, 'delphi_hover', {'path': grande, 'line': 0, 'character': 5}))
    hilo.start()
    hilo.join(TOPE)
    v, dt = res.get('v', '(sin respuesta en %d s)' % TOPE), res.get('dt', TOPE)
    check('V2b (preparacion) otro proyecto caliente con su motor suspendido', ok3 and parado3, motor3)
    check('V2b a la peticion que se queda ESCRIBIENDOLE a un motor colgado (un fichero que no cabe en su tuberia) '
          'el servidor le contesta LSP-033 por si mismo (%.0f s): esa no tenia plazo' % dt,
          mc.es(v, 'SR_LSP_ENGINE_STOPPED'), ' '.join(v.split())[:160])
    colgado, dt = se_va(proc, motor3)
    check('V2b ...y el proceso colgado ya no esta, y el log lo dice otra vez',
          not colgado and len(apuntado('no sign of life', n_antes + 1)) > n_antes, 'sigue %s' % colgado)
finally:
    acaba(proc)

if mc.F == 0:
    mc.borra(BASE)
    mc.limpia_caches_lsp()
mc.fin('test_motor_vida')
