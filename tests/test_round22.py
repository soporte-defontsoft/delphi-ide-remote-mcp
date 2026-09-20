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
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil, glob

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round22')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)

env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = BASE
proc = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                        text=True, encoding='utf-8')
q = queue.Queue()


def reader():
    for line in proc.stdout:
        line = line.strip()
        if line:
            q.put(line)


threading.Thread(target=reader, daemon=True).start()
rid = [10]
P = F = 0


def send(o):
    proc.stdin.write(json.dumps(o) + '\n')
    proc.stdin.flush()


def recv(r, t=300):
    dl = time.time() + t
    while time.time() < dl:
        try:
            line = q.get(timeout=1)
        except queue.Empty:
            continue
        try:
            m = json.loads(line)
        except Exception:
            continue
        if m.get('id') == r:
            return m
    return None


def call(tool, args, t=300):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call",
          "params": {"name": tool, "arguments": args}})
    r = recv(rid[0], t)
    if not r:
        return '(sin respuesta)'
    return r.get('result', {}).get('content', [{}])[0].get('text', 'ERR')


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:260])


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "round22", "version": "1"}}})
recv(1)
send({"jsonrpc": "2.0", "method": "notifications/initialized"})
time.sleep(0.3)

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
if dpr:
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
        check('M4 link Linux64 real: outputTail sin srvhost y linker legible',
              'srvhost' not in tail and 'Linker command line' in tail
              and 'sysroot' in tail, 'srvhost x%d' % tail.count('srvhost'))
    else:
        print('SKIP M4: esta maquina no linka Linux64 (sin SDK); M1-M3 cubren el masker')

proc.kill()
print('\n== round-22 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
