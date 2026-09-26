"""E2E battery for v0.76.0-beta - hermes' release audit, P0 + supplement.

Two dangers and one wall, all measured by hermes on the live runtime:

  - builds were NOT serialized: Indy serves each request on its own thread and
    two concurrent delphi_build/delphi_test calls entered MSBuild at once,
    colliding DCUs, outputs and .deployproj. Now a global queue: one msbuild
    at a time, and a queued call reports queuedMs + queuedNote.
  - delphi_search had maxresults but no offset: a truncated search was a wall,
    the next page was unreachable. Now offset + hasMore + nextOffset.
  (- TLspSession.Instance could double-create on two first concurrent LSP
    calls; fixed lock-free with CompareExchange - covered by code review, the
    race window is too narrow for a deterministic E2E check.)

  E1  search pagination: pages don't overlap, walk reaches total, tail page ok
  E2  two concurrent builds both succeed and one waited in queue (queuedMs)

Usage:  python tests/test_round15.py [path-to-DelphiLspMcp.exe]
"""
import json, threading, os, glob
import mcp_cliente as mc
from mcp_cliente import check


BASE = mc.carpeta('round15')
EXE = mc.copia_exe(BASE)

PORT = mc.puerto_libre()
env = mc.entorno({'DELPHI_MCP_ROOTS': BASE,
                  'DELPHI_MCP_BIND_IP': '127.0.0.1'})  # loopback: sin avisos del firewall
# v0.98: o workspace o nada - la bateria presenta su token
TOKEN = 'bateria-workspace'
with open(os.path.join(BASE, 'settings.ini'), 'w') as _f:
    _f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\n' % (TOKEN, BASE))
proc = mc.lanza_http(EXE, PORT, env)
# un cliente (seguro entre hilos) y una SESION por agente: cada llamada dice
# con cual habla (sid=). Hasta 420 s por llamada: compilan.
cli = mc.Http(PORT, TOKEN, t=420)


try:
    sid = cli.session('round15')

    # ---- E1: search pagination -------------------------------------------
    sub = os.path.join(BASE, 'srch')
    os.makedirs(sub)
    lines = []
    for i in range(10):
        lines.append('  NeedleXyz := %d;' % i)
        lines.append('  Other := 0;')
    open(os.path.join(sub, 'many.pas'), 'w').write(
        'unit many;\ninterface\nimplementation\nprocedure X;\nbegin\n' +
        '\n'.join(lines) + '\nend;\nend.\n')

    r1 = json.loads(cli.call('delphi_search',
                             {'root': sub, 'query': 'NeedleXyz', 'maxresults': 3}, sid=sid))
    check('E1 page 1: total=10 shown=3 hasMore nextOffset=3',
          r1.get('total') == 10 and r1.get('shown') == 3 and
          r1.get('hasMore') is True and r1.get('nextOffset') == 3, r1)
    r2 = json.loads(cli.call('delphi_search',
                             {'root': sub, 'query': 'NeedleXyz', 'maxresults': 3, 'offset': 3}, sid=sid))
    l1 = [h['line'] for h in r1['hits']]
    l2 = [h['line'] for h in r2['hits']]
    check('E1 page 2 continues, no overlap',
          r2.get('offset') == 3 and l2 and not (set(l1) & set(l2)) and
          min(l2) > max(l1), (l1, l2))
    seen, ofs = [], 0
    while True:
        rp = json.loads(cli.call('delphi_search',
                                 {'root': sub, 'query': 'NeedleXyz', 'maxresults': 4, 'offset': ofs}, sid=sid))
        seen += [h['line'] for h in rp['hits']]
        if not rp.get('hasMore'):
            break
        ofs = rp['nextOffset']
    check('E1 walking pages reaches every hit exactly once',
          len(seen) == 10 and len(set(seen)) == 10, seen)
    rt = json.loads(cli.call('delphi_search',
                             {'root': sub, 'query': 'NeedleXyz', 'offset': 99}, sid=sid))
    check('E1 offset past the end: shown 0, hasMore false',
          rt.get('shown') == 0 and rt.get('hasMore') is False, rt)

    # ---- E2: concurrent builds are serialized ----------------------------
    for name in ('BQa', 'BQb'):
        r = cli.call('delphi_create', {'kind': 'project-console', 'name': name, 'dir': BASE}, sid=sid)
        check('E2 scaffold %s' % name, 'CREADO' in r, r)
    dprojs = {n: glob.glob(os.path.join(BASE, '**', n + '.dproj'), recursive=True)[0]
              for n in ('BQa', 'BQb')}

    # Fatten both projects so each build takes SECONDS, not sub-second: warm
    # builds of the bare scaffold were so fast that OS scheduling skew under
    # load could finish one before the other's request landed - flaky. With
    # ~100k generated lines per project, overlap (and a queue wait well over
    # the 500ms reporting floor) is guaranteed by construction.
    for n in ('BQa', 'BQb'):
        dpr = dprojs[n][:-6] + '.dpr'
        folder = os.path.dirname(dpr)
        body = ['unit Gordo%s;' % n, 'interface', 'implementation']
        for i in range(2500):
            body += ['procedure P%d;' % i, 'var A: Integer;', 'begin',
                     '  A := %d;' % i, '  if A > 0 then A := A - 1;',
                     '  if A < 0 then A := 0;', 'end;']
        body.append('end.')
        open(os.path.join(folder, 'Gordo%s.pas' % n), 'w').write(
            '\n'.join(body) + '\n')
        s = open(dpr, encoding='utf-8-sig').read()
        s = s.replace('uses', 'uses\n  Gordo%s,' % n, 1)
        open(dpr, 'w', encoding='utf-8').write(s)

    results = {}
    # sessions OUTSIDE the threads and a barrier right before the call, so
    # both builds truly hit the server together (session setup used to skew
    # the start enough for the fast one to finish first - flaky on a busy box)
    sess = {'alice': cli.session('alice'), 'bob': cli.session('bob')}
    # sid=None volveria a la ULTIMA sesion del cliente: dos distintas de verdad
    assert sess['alice'] and sess['bob'] and sess['alice'] != sess['bob'], sess
    gate = threading.Barrier(2)

    def build(agent, proj):
        gate.wait()
        results[agent] = cli.call('delphi_build',
                                  {'project': proj, 'platform': 'Win64', 'config': 'Debug'},
                                  sid=sess[agent])

    t1 = threading.Thread(target=build, args=('alice', dprojs['BQa']))
    t2 = threading.Thread(target=build, args=('bob', dprojs['BQb']))
    t1.start()
    t2.start()
    t1.join(400)
    t2.join(400)

    ra = json.loads(results.get('alice', '{}'))
    rb = json.loads(results.get('bob', '{}'))
    check('E2 both concurrent builds succeed',
          ra.get('success') is True and rb.get('success') is True,
          (ra.get('firstError'), rb.get('firstError')))
    queued = [r for r in (ra, rb) if 'queuedMs' in r]
    check('E2 exactly one of them waited in the queue (queuedMs >= 500)',
          len(queued) == 1 and queued[0]['queuedMs'] >= 500,
          {'alice': ra.get('queuedMs'), 'bob': rb.get('queuedMs')})
    check('E2 the queued one explains itself (queuedNote)',
          bool(queued) and 'DE UNO EN UNO' in queued[0].get('queuedNote', ''),
          queued and queued[0].get('queuedNote'))
finally:
    proc.kill()

mc.fin('round-15 battery')
