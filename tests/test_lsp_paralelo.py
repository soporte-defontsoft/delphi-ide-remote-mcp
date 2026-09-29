"""E2E battery (1.7.7): two engines that start TOGETHER do not take each
other's pipes.

Every child the server launches with redirected output inherits handles
(CreateProcess, bInheritHandles=True), and the pipe ends made for a child are
inheritable from CreatePipe until the parent closes its copy. Two launches
that overlapped, and the second child kept the write end of the first one's
output. Nobody noticed while an engine was only ever stopped when the server
stopped. Since 1.7.7 the server stops the engines of a folder before it takes
the folder away, in a request thread that holds the global write lock: the
stopped engine's reader never saw the end of its pipe, the stop did not
return, and the delete hung - and with it every writer of the server.

Measured 2026-09-29 against the first build of the fix: the delete hung in the
fourth round of this same scenario, twice out of two runs, and came back the
moment the OTHER engine was killed from outside. It needs the server over HTTP
(one thread per request): over stdio the calls come one at a time.

  P1  N rounds: two cold projects, hover and diagnostics of both in PARALLEL
      (four engines starting together), then the first project's folder is
      deleted: the delete answers in seconds and the folder is gone
      ...and none of the parallel calls COLLIDES (a guard, not a
      measure: with two first requests per project the collision below is
      rare, and this check passed with the fix taken out)
  P5  SIX first requests at once on the SAME cold project: none collides.
      They all found no fabricated settings and all wrote the same file;
      the ones that lost answered SYS-027, "Cannot create file" (measured
      in the 1.7.6 binary). Now there is one fabrication at a time. A
      GUARD too: over HTTP the requests do not arrive together enough, and
      this check passed with the fabrication of 1.7.6 put back. The measure
      is the unit test LspTests.Motor.TFabricaTests (eight threads leaving
      at once, forty rounds: red in the second round without the fix)
  P2  after the rounds the server still answers, to a read and to a write
  P4  releasing and taking away are ONE thing: the folder is deleted while
      another agent's FIRST hover is still building its engine - the delete
      waits for that engine, no engine of that round stays, and the hover
      gets its answer or is told why not. The delete leaves at several
      moments of the build, and at least ONE of them has to catch the engine
      half built (the hover is then told LSP-032 or LSP-033): a round where
      the hover won, or came late, is D3 again and measures nothing of this
      (then the battery says so in a NOTE: it is a matter of timing, not
      of the server)
  P6  a diagnostics in flight when git stops its engine is told LSP-033,
      and REPEATED - what LSP-033 says to do - it answers. What the session
      knew of the dead client's documents stayed for the next client of the
      same project: the text of the lint in flight was "the one being
      linted", nothing was sent to the new engine, and the answer was "in
      progress" after 40 s, every time (measured with the cleanup skipped).
      Now what is known of a client's documents is the client's own and goes
      with it (TSessionClient): there is nothing left to clean
  P7  an engine that STOPS READING keeps the requests of its own project,
      and nobody else's: with one engine suspended and two requests of its
      project waiting for it, the other project answers as ever, and the
      folder of the first one is deleted - the ones that waited are told
      LSP-033. The session had one lock for everything, held while an engine
      was written to (fourth review of 1.7.7: it was read, and a probe
      measured it)
  P3  with the server gone, none of its engines stays alive: an engine that
      holds another one's pipe keeps it from seeing that the server left

Usage:  python tests/test_lsp_paralelo.py [path-to-DelphiLspMcp.exe]
"""
import os, subprocess, threading, time
import mcp_cliente as mc
from mcp_cliente import check

RONDAS = 8
# segundos: un borrado sano tarda menos de uno; colgado, no vuelve. Por encima
# de lo que el servidor puede tardar SIN estar colgado: parar los motores (16,
# todos a la vez), esperar a los que se construyen (6) y lo suyo
TOPE = 30
BASE = mc.carpeta('lsp-paralelo')
SRVDIR = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRVDIR)
PORT = mc.puerto_libre()
TOKEN = 'test-token-paralelo'
with open(os.path.join(SRVDIR, 'settings.ini'), 'w') as f:
    f.write('[Server]' + chr(10) + 'Port=%d' % PORT + chr(10) + 'BindIP=127.0.0.1' + chr(10) * 2
            + '[Workspace.Op]' + chr(10) + 'Token=%s' % TOKEN + chr(10)
            + 'Roots=%s' % BASE + chr(10) + 'DelphiVersion=37.0' + chr(10))
proc = mc.lanza_http(EXE, None, mc.entorno(), espera_en=PORT)


def cliente(t=200):
    c = mc.Http(PORT, TOKEN, t=t)
    c.session('paralelo')
    return c


def caliente(h):
    return 'TApplication' in h


def choca(v):
    # SOLO el choque al fabricar la configuracion, o una peticion que no
    # vuelve: la negativa prevista de un motor frio (LSP-025, "warming up,
    # repeat") no es de estos checks, y los ponia rojos
    return v.startswith('EXCEPCION') or mc.es(v, 'SR_FICHERO_OCUPADO_FMT') or 'Cannot create file' in v


def tira(res, clave, tool, args):
    # cada hilo con SU sesion: son agentes distintos
    try:
        res[clave] = cliente().call(tool, args)
    except Exception as e:
        res[clave] = 'EXCEPCION %s: %s' % (type(e).__name__, e)


# Cada paso, una funcion, y el hilo de la bateria al final: con el servidor
# COLGADO en P1 los pasos siguientes le llamaban igual, la bateria reventaba
# con una traza y no llegaba ni a P2 ni a P3 (medido contra la primera version
# del arreglo; tercera revision de la 1.7.7)
def p1(uno, colgados):
    peor, frios, negadas = 0.0, 0, []
    for ronda in range(1, RONDAS + 1):
        a = os.path.join(BASE, 'A%d' % ronda)
        b = os.path.join(BASE, 'B%d' % ronda)
        uno.call('delphi_create', {'kind': 'project-vcl', 'name': 'A%d' % ronda, 'dir': a})
        uno.call('delphi_create', {'kind': 'project-vcl', 'name': 'B%d' % ronda, 'dir': b})
        res = {}
        hilos = [threading.Thread(target=tira, args=(res,) + a_) for a_ in (
            ('hA', 'delphi_hover', {'path': os.path.join(a, 'A%d.dpr' % ronda), 'line': 9, 'character': 4}),
            ('hB', 'delphi_hover', {'path': os.path.join(b, 'B%d.dpr' % ronda), 'line': 9, 'character': 4}),
            ('dA', 'delphi_diagnostics', {'path': os.path.join(a, 'UMain.pas')}),
            ('dB', 'delphi_diagnostics', {'path': os.path.join(b, 'UMain.pas')}))]
        for h in hilos:
            h.start()
        for h in hilos:
            h.join()
        # sin NINGUN motor que retenga A la ronda no mide nada. Por lo que
        # RETIENE (el directorio de trabajo de los motores), no por lo que
        # contestaron las peticiones: un arranque en frio con cuatro motores a
        # la vez puede dejar un hover sin respuesta con su motor ya dentro
        if not mc.motores_en(proc.pid, a):
            frios += 1
        negadas += ['ronda %d %s: %s' % (ronda, k, ' '.join(v.split())[:110])
                    for k, v in sorted(res.items()) if choca(v)]
        t0 = time.time()
        try:
            r = cliente(t=TOPE).call('delphi_delete', {'path': a})
        except Exception as e:
            r = 'EXCEPCION %s: %s' % (type(e).__name__, e)
        dt = time.time() - t0
        peor = max(peor, dt)
        if not (mc.abre(r, 'SK_FILE_BORRADO_PAPELERA_FMT') and not os.path.exists(a)):
            colgados.append('ronda %d (%.1f s): %s' % (ronda, dt, ' '.join(r.split())[:120]))
            break          # un servidor colgado no da mas rondas: lo dice P2
    check('P1 %d rondas de cuatro motores arrancando A LA VEZ: el borrado de la carpeta vuelve siempre '
          '(peor: %.1f s)' % (RONDAS, peor), not colgados and peor < TOPE, colgados)
    check('P1 ...y en todas habia un motor que RETENIA la carpeta que se borro (si no, no mide)',
          frios == 0, 'rondas sin motor en A: %d' % frios)
    check('P1 ...y ninguna de las %d peticiones en paralelo choco al fabricar la configuracion '
          '(SYS-027)' % (4 * RONDAS), not negadas, negadas[:4])


def p5(uno, colgados):
    # P5 - seis PRIMERAS peticiones a la vez sobre el mismo proyecto frio
    chocan = []
    for i in range(1, 5):
        f = os.path.join(BASE, 'F%d' % i)
        uno.call('delphi_create', {'kind': 'project-vcl', 'name': 'F%d' % i, 'dir': f})
        dpr, pas = os.path.join(f, 'F%d.dpr' % i), os.path.join(f, 'UMain.pas')
        res = {}
        hilos = [threading.Thread(target=tira, args=(res,) + a_) for a_ in (
            ('hover', 'delphi_hover', {'path': dpr, 'line': 9, 'character': 4}),
            ('definition', 'delphi_definition', {'path': dpr, 'line': 9, 'character': 4}),
            ('completion', 'delphi_completion', {'path': dpr, 'line': 9, 'character': 14}),
            ('signature', 'delphi_signature', {'path': dpr, 'line': 11, 'character': 25}),
            ('symbols', 'delphi_symbols', {'path': pas}),
            ('diagnostics', 'delphi_diagnostics', {'path': pas}))]
        for h in hilos:
            h.start()
        for h in hilos:
            h.join()
        chocan += ['F%d %s: %s' % (i, k, ' '.join(v.split())[:110])
                   for k, v in sorted(res.items()) if choca(v)]
    check('P5 seis PRIMERAS peticiones a la vez sobre el mismo proyecto frio, cuatro veces: ninguna '
          'choca', not chocan, chocan[:4])


def p4(uno, colgados):
    # P4 - el primer hover de otro agente, con el motor A MEDIO construir
    sueltos, dichos = [], []
    for i in range(1, 7):
        x = os.path.join(BASE, 'X%d' % i)
        uno.call('delphi_create', {'kind': 'project-vcl', 'name': 'X%d' % i, 'dir': x})
        n0 = mc.hijos_lsp(proc.pid)
        res = {}
        h = threading.Thread(target=tira, args=(res, 'h', 'delphi_hover', {
            'path': os.path.join(x, 'X%d.dpr' % i), 'line': 9, 'character': 4}))
        h.start()
        time.sleep(0.3 * i)            # el motor tarda 2-3 s en estar: se le pilla a medias
        try:
            r = cliente(t=TOPE).call('delphi_delete', {'path': x})
        except Exception as e:
            r = 'EXCEPCION %s: %s' % (type(e).__name__, e)
        h.join()
        time.sleep(0.5)
        # los motores NUEVOS de la ronda (por su pid: que otro se vaya entre
        # las dos cuentas no tapa uno que se quede)
        nuevos = sorted(set(mc.hijos_lsp(proc.pid)) - set(n0))
        dicho = res.get('h', '')
        a_medias = mc.es(dicho, 'SR_LSP_FOLDER_LEAVING_FMT') or mc.es(dicho, 'SR_LSP_ENGINE_STOPPED')
        sabe = a_medias or caliente(dicho) or mc.es(dicho, 'SR_LSP_NO_FILE_FMT')
        dichos.append('LSP-032/033' if a_medias else 'contesto' if caliente(dicho) else
                      'no esta' if mc.es(dicho, 'SR_LSP_NO_FILE_FMT') else 'OTRA COSA')
        if not (mc.abre(r, 'SK_FILE_BORRADO_PAPELERA_FMT') and not os.path.exists(x)
                and not nuevos and sabe):
            sueltos.append('X%d: motores nuevos %s | delete: %s | hover: %s' % (
                i, nuevos, ' '.join(r.split())[:90], ' '.join(dicho.split())[:110]))
    # que una ronda pille al motor A MEDIAS es cosa de tiempos, no del
    # servidor: con ninguna, la bateria dice que no midio (NOTA), y no pasa
    # en verde por lo que mide D3
    if 'LSP-032/033' in dichos:
        check('P4 borrar la carpeta con el motor de OTRO agente a medio construir (%d de 6 rondas lo '
              'pillaron a medias): se borra, no queda ningun motor de la ronda y el hover sabe a que '
              'atenerse' % dichos.count('LSP-032/033'), not sueltos, sueltos)
    else:
        print('NOTA: P4 no se mide: ninguna de las seis rondas pillo al motor a medio construir (%s)'
              % ', '.join(dichos))
        if sueltos:
            check('P4 (sin motor a medias) la carpeta se borra y no queda ningun motor de la ronda',
                  False, sueltos)


def p6(uno, colgados):
    # P6 - un diagnostics EN VUELO cuando git para su motor; y repetido
    rp = os.path.join(BASE, 'repo6')
    p6 = os.path.join(rp, 'Seis')
    pas6 = os.path.join(p6, 'UMain.pas')
    uno.call('delphi_create', {'kind': 'project-vcl', 'name': 'Seis', 'dir': p6})
    for a_ in ({'command': 'init'}, {'command': 'config', 'args': 'user.name', 'message': 'p6'},
               {'command': 'config', 'args': 'user.email', 'message': 'p6@example.com'},
               {'command': 'add', 'args': '.'}, {'command': 'commit', 'message': 'base'}):
        uno.call('delphi_git', dict(repo=rp, **a_))
    ramas = uno.call('delphi_git', {'repo': rp, 'command': 'branch'})
    esta = ([l.split()[1] for l in ramas.splitlines() if l.startswith('*')] + [''])[0]
    uno.call('delphi_git', {'repo': rp, 'command': 'switch', 'args': 'gemela', 'create': True})
    d1 = uno.call('delphi_diagnostics', {'path': pas6})
    cazado = repetido = ''
    dt = 0.0
    for intento, retraso in enumerate([0.05, 0.15, 0.3, 0.02, 0.5, 0.1], 1):
        with open(pas6, 'a') as f:
            f.write(chr(10) + '// cambio %d' % intento + chr(10))
        res = {}
        h = threading.Thread(target=tira, args=(res, 'd', 'delphi_diagnostics', {'path': pas6}))
        otro = cliente()
        h.start()
        time.sleep(retraso)
        otro.call('delphi_git', {'repo': rp, 'command': 'switch',
                                 'args': 'gemela' if intento % 2 == 0 else esta})
        h.join()
        if mc.es(res.get('d', ''), 'SR_LSP_ENGINE_STOPPED'):
            cazado = res['d']
            t0 = time.time()
            repetido = cliente(t=60).call('delphi_diagnostics', {'path': pas6})
            dt = time.time() - t0
            break
    if cazado:
        check('P6 un diagnostics en vuelo cuando git para su motor recibe LSP-033, y REPETIDO contesta '
              '(%.1f s; se quedaba en "in progress" a los 40)' % dt,
              '"errors"' in d1 and '"errors"' in repetido and dt < 20, ' '.join(repetido.split())[:160])
    else:
        print('NOTA: P6 no se mide: en seis intentos ningun diagnostics estaba en vuelo cuando git paro su motor')


def suspende(pid):
    # el motor sigue vivo y deja de leer su tuberia (andamio, no lo que se mide)
    import ctypes
    h = ctypes.windll.kernel32.OpenProcess(0x0800, False, pid)   # PROCESS_SUSPEND_RESUME
    rc = ctypes.windll.ntdll.NtSuspendProcess(h)
    ctypes.windll.kernel32.CloseHandle(h)
    return rc == 0


def p7(uno, colgados):
    # P7 - un motor que DEJA DE LEER retiene lo de su proyecto, y a nadie mas
    s, o = os.path.join(BASE, 'Sordo'), os.path.join(BASE, 'Oye')
    for n, d in (('Sordo', s), ('Oye', o)):
        uno.call('delphi_create', {'kind': 'project-vcl', 'name': n, 'dir': d})
    grande = os.path.join(s, 'Grande.pas')      # no cabe en la tuberia del motor
    with open(grande, 'w') as f:
        f.write('unit Grande;' + chr(10) * 2 + 'interface' + chr(10) * 2 + 'implementation' + chr(10) * 2
                + ''.join('// relleno %06d para que no quepa en la tuberia' % i + chr(10)
                          for i in range(4000)) + chr(10) + 'end.' + chr(10))
    dprs, dpro = os.path.join(s, 'Sordo.dpr'), os.path.join(o, 'Oye.dpr')
    hs = ho = ''
    for _ in range(6):
        hs = uno.call('delphi_hover', {'path': dprs, 'line': 9, 'character': 4})
        ho = uno.call('delphi_hover', {'path': dpro, 'line': 9, 'character': 4})
        if caliente(hs) and caliente(ho):
            break
        time.sleep(2)
    sordos = mc.motores_en(proc.pid, s)
    parados = [p for p in sordos if suspende(p)]
    res = {}
    hilos = [threading.Thread(target=tira, args=(res,) + a_) for a_ in (
        ('symbols', 'delphi_symbols', {'path': grande}),
        ('hover', 'delphi_hover', {'path': dprs, 'line': 9, 'character': 4}))]
    for h in hilos:
        h.start()
        time.sleep(1)
    time.sleep(2)
    esperan = [k for k in ('symbols', 'hover') if k not in res]
    t0 = time.time()
    try:
        otro = cliente(t=TOPE).call('delphi_hover', {'path': dpro, 'line': 9, 'character': 4})
    except Exception as e:
        otro = 'EXCEPCION %s: %s' % (type(e).__name__, e)
    dt_otro = time.time() - t0
    t0 = time.time()
    try:
        r = cliente(t=TOPE).call('delphi_delete', {'path': s})
    except Exception as e:
        r = 'EXCEPCION %s: %s' % (type(e).__name__, e)
    dt = time.time() - t0
    for h in hilos:
        h.join(TOPE)
    # un motor suspendido no sale solo: si el borrado no se lo llevo, aqui.
    # Solo los que SIGUEN siendo de este servidor, mirados ahora: el pid de
    # uno que ya se fue puede ser ya el de otro proceso
    try:
        siguen = sorted(set(sordos) & set(mc.hijos_lsp(proc.pid)))
    except Exception:
        siguen = []
    for pid in siguen:
        subprocess.run(['taskkill', '/PID', str(pid), '/F'], capture_output=True)
    dicho = ' '.join(str(sorted(res.items())).split())[:240]
    check('P7 (preparacion) dos proyectos calientes, el motor de uno deja de leer y dos peticiones de ese '
          'proyecto se quedan esperandole',
          caliente(hs) and caliente(ho) and len(sordos) == 1 and parados == sordos and len(esperan) == 2,
          'motores %s, parados %s, esperando %s | %s' % (sordos, parados, esperan, dicho))
    check('P7 con un motor que no lee, el OTRO proyecto contesta como siempre (%.1f s)' % dt_otro,
          caliente(otro) and dt_otro < 5, ' '.join(otro.split())[:160])
    check('P7 ...y la carpeta del proyecto de ese motor se borra (%.1f s), y las que esperaban se enteran '
          '(LSP-033)' % dt,
          mc.abre(r, 'SK_FILE_BORRADO_PAPELERA_FMT') and not os.path.exists(s) and dt < TOPE
          and all(mc.es(res.get(k, ''), 'SR_LSP_ENGINE_STOPPED') for k in ('symbols', 'hover')),
          '%s | %s' % (' '.join(r.split())[:100], dicho))


def p2():
    try:
        w = cliente(t=TOPE).call('delphi_workspace', {})
        p = os.path.join(BASE, 'vivo.txt')
        e = cliente(t=TOPE).call('delphi_textedit', {'path': p, 'create': True, 'content': 'vivo'})
    except Exception as ex:
        w = e = 'EXCEPCION %s: %s' % (type(ex).__name__, ex)
    check('P2 tras las rondas el servidor sigue contestando: a una lectura y a una escritura',
          '"roots"' in w and not mc.fallo(e) and os.path.exists(os.path.join(BASE, 'vivo.txt')),
          '%s | %s' % (w[:80], e[:120]))


motores = []
try:
    colgados = []
    try:
        uno = cliente()
    except Exception as ex:
        uno = None
        colgados.append('el servidor no abre sesion: %s' % ex)
    for paso in (p1, p5, p4, p6, p7):
        nombre = paso.__name__.upper()
        if colgados:
            print('NOTA: %s no se mide: el servidor no contesta (%s)' % (nombre, colgados[0][:80]))
            continue
        try:
            paso(uno, colgados)
        except Exception as ex:
            colgados.append('%s: %s: %s' % (nombre, type(ex).__name__, ex))
            check('%s acaba (el servidor contesta a todo lo que se le pide)' % nombre, False, colgados[-1])
    p2()
    try:
        motores = mc.hijos_lsp(proc.pid)
    except Exception as ex:
        check('P3 (preparacion) se puede preguntar por los motores', False, str(ex))
finally:
    proc.kill()
    proc.wait()

# P3 - sin servidor, cada motor ve cerrarse SU tuberia y se va
quedan = motores
t0 = time.time()
while quedan and time.time() - t0 < 15:
    time.sleep(0.5)
    quedan = mc.hijos_lsp(proc.pid)
check('P3 sin el servidor no queda vivo ninguno de sus motores (habia %d)' % len(motores),
      len(motores) > 0 and not quedan, 'quedan %s' % quedan)
# los que queden son de ESTE servidor (por su padre) y retienen su carpeta:
# la bateria no los deja en la maquina, tampoco cuando sale roja
for pid in quedan:
    subprocess.run(['taskkill', '/PID', str(pid), '/F'], capture_output=True)

if mc.F == 0:
    mc.borra(BASE)
    mc.limpia_caches_lsp()
mc.fin('test_lsp_paralelo')
