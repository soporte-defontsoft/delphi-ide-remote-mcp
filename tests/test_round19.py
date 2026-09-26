"""E2E battery for v0.82.0-beta - hermes' P1.6: LSP lifecycle.

The session's global lock used to be held ACROSS the slow parts: spawning
DelphiLSP + initialize + the settings-load sleep (seconds) and the 500ms
indexing head starts. One agent warming one project stalled every other
agent's LSP call server-wide. Now the slow path runs unlocked (double-checked
client creation), the head-start sleeps happen outside the lock, the
settings/dproj resolution is cached by the stamp of the file that decided it,
and each client's notification queue is bounded (200, oldest first).

  L1  warming two DIFFERENT projects concurrently is parallel, not serial
      (wall for both together well under two sequential warms)
  L2  the settings cache does not go stale: touching the .dproj (add a search
      path) re-fabricates and the LSP keeps answering on the next call
  L3  the warm client answers symbols correctly after all of it

Usage:  python tests/test_round19.py [path-to-DelphiLspMcp.exe]
"""
import threading, time, os, glob
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('round19')
EXE = mc.copia_exe(BASE)

PORT = mc.puerto_libre()
env = mc.entorno({'DELPHI_MCP_ROOTS': BASE,
                  'DELPHI_MCP_BIND_IP': '127.0.0.1'})  # loopback: sin avisos del firewall
# v0.98: o workspace o nada - la bateria presenta su token
TOKEN = 'bateria-workspace'
with open(os.path.join(BASE, 'settings.ini'), 'w') as _f:
    _f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\n' % (TOKEN, BASE))
proc = mc.lanza_http(EXE, PORT, env)


def session(name):
    # un cliente por agente: cada uno con SU sesion (los warms van en hilos)
    cli = mc.Http(PORT, TOKEN, t=180)
    cli.session(name)
    return cli


try:
    cli = session('round19')

    # Four disposable projects, each in ITS OWN folder: the settings are
    # resolved per folder, so each one gets its own DelphiLSP client. Until
    # 2026-09-26 the three lived in the same folder and SHARED one client:
    # B and C came back warm in 0.25 s and L1c compared one cold warm with
    # two warm ones - it passed whether the warms ran in parallel or not.
    NOMBRES = ('WarmA', 'WarmB', 'WarmC', 'WarmD')
    for n in NOMBRES:
        r = cli.call('delphi_create', {'kind': 'project-console', 'name': n,
                                       'dir': os.path.join(BASE, n)})
        check('scaffold %s' % n, 'CREADO' in r, r)
    dpr = {n: glob.glob(os.path.join(BASE, '**', n + '.dpr'), recursive=True)[0]
           for n in NOMBRES}

    # L1a: the first warm of the process (it also pays the machine's cold
    # caches, so it is NOT the yardstick)
    ra = cli.call('delphi_symbols', {'path': dpr['WarmA']})
    check('L1a un warm solo responde simbolos',
          ra.lstrip().startswith('[') and 'selectionRange' in ra, ra[:150])
    # the yardstick: ONE cold warm of another project, measured alone
    t0 = time.time()
    cli.call('delphi_symbols', {'path': dpr['WarmD']})
    t_single = time.time() - t0

    # L1b: two DIFFERENT projects (both cold) warmed concurrently
    walls = {}

    def warm(agent, path):
        s = session(agent)
        t = time.time()
        walls[agent] = (s.call('delphi_symbols', {'path': path}), time.time() - t)

    t0 = time.time()
    th1 = threading.Thread(target=warm, args=('alice', dpr['WarmB']))
    th2 = threading.Thread(target=warm, args=('bob', dpr['WarmC']))
    th1.start()
    th2.start()
    th1.join(120)
    th2.join(120)
    t_both = time.time() - t0
    check('L1b ambos warms responden',
          all(w[0].lstrip().startswith('[') and 'selectionRange' in w[0]
              for w in walls.values()),
          (walls['alice'][0][:80], walls['bob'][0][:80]))
    # what makes L1c a measure: the two concurrent warms were COLD (each as
    # long as the yardstick, give or take), not answered by a warm client
    frios = [w[1] for w in walls.values()]
    check('L1d los dos warms a la vez son FRIOS (cada uno >= 0.5 x el suelto)',
          len(frios) == 2 and min(frios) >= 0.5 * t_single,
          (frios, t_single))
    # serial would be ~2x a single warm; parallel stays well under that
    check('L1c calentar dos proyectos a la vez NO se serializa '
          '(wall %.1fs < 1.6 x %.1fs)' % (t_both, t_single),
          t_both < 1.6 * t_single, (t_both, t_single))

    # L2: touch the .dproj (delphi_config add-searchpath) -> stamp changes ->
    # settings re-fabricated; the next LSP call must keep answering
    sub = os.path.join(os.path.dirname(dpr['WarmA']), 'extra')
    os.makedirs(sub)
    r = cli.call('delphi_config', {'project': dpr['WarmA'][:-4] + '.dproj',
                                   'command': 'add-searchpath', 'path': sub})
    check('L2 add-searchpath toca el .dproj',
          'ANADIDO' in r or 'ya estaba' in r, r[:160])
    r = cli.call('delphi_symbols', {'path': dpr['WarmA']})
    check('L2 tras cambiar el .dproj, symbols sigue respondiendo (cache invalidada)',
          r.lstrip().startswith('[') and 'selectionRange' in r, r[:150])

    # L3: hover on the program name still works on the warm client
    r = cli.call('delphi_symbols', {'path': dpr['WarmB']})
    check('L3 el cliente caliente reutilizado responde',
          r.lstrip().startswith('[') and 'selectionRange' in r, r[:120])
finally:
    proc.kill()

mc.fin('round-19 battery')
