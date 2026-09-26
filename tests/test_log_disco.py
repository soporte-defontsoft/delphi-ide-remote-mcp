r"""E2E battery for the server's log ON DISK (1.5.0): logs\ next to the exe, the
same in every host. Until 2026-09-26 only the tray's window wrote it, so the
Windows Service - production since 2026-09-20 - ran six days without one line
(logs\actual.log stopped on 2026-09-20 at 18:09). The disk now belongs to
Lsp.LogSink, which TMcpHost starts in every mode; this battery drives the two
terminal modes (the service and the tray build the very same TMcpHost).

  A  stdio: actual.log exists and grows WHILE the process lives (~0,5 s), a
     password never reaches it, and a clean exit leaves its "parado" line
  B  --http killed from outside: what it logged is already on disk
  C  rotation: a block every [Log] LinesPerFile lines is actual.log RENAMED,
     the newest [Log] MaxFiles blocks stay (by the namer's order: "-2" is
     newer than its first), and a .log the namer would not compose is never
     touched
  D  a junction planted at logs\ -> a victim OUTSIDE: nothing is written or
     pruned there, and the server keeps answering
  E  two processes with the same exe write the same actual.log at once: no
     line is lost and none is cut into another
  F  a base64 run (an inline capture travels inside the response) is not
     kept: a mark with its size stays, and the rest of the line is whole
  G  every line goes through the secrets masker, the RESPONSE too (the
     transports masked only the request)

Usage:  python tests/test_log_disco.py [path-to-DelphiLspMcp.exe]
"""
import subprocess, threading, time, os, shutil, re, base64
import mcp_cliente as mc
from mcp_cliente import check

RAIZ = mc.RAIZ
BASE = os.path.join(RAIZ, 'log_disco')
VICTIM = os.path.join(RAIZ, 'log_disco_victima')
LOGS = os.path.join(BASE, 'logs')
VIVO = os.path.join(LOGS, 'actual.log')
INI = os.path.join(BASE, 'settings.ini')
# lo que compone el nombrador del servidor: sin sufijo, o -2, -3... (nunca -1 ni -01)
BLOQUE = re.compile(r'^\d{8}-\d{6}(-([2-9]|[1-9]\d+))?\.log$')


def quita_enlace(p):
    # rmdir quita el ENLACE, nunca lo que hay detras
    if os.path.isjunction(p) or os.path.islink(p):
        os.rmdir(p)


def limpia():
    quita_enlace(LOGS)
    shutil.rmtree(BASE, ignore_errors=True)
    shutil.rmtree(VICTIM, ignore_errors=True)


limpia()
os.makedirs(BASE)
EXE = mc.copia_exe(BASE)
ENV = mc.entorno()
ENV['DELPHI_MCP_ROOTS'] = BASE

def lee(p):
    try:
        with open(p, encoding='utf-8', errors='replace') as f:
            return f.read()
    except OSError:
        return ''


def espera(cond, t=8.0):
    dl = time.time() + t
    while time.time() < dl:
        if cond():
            return True
        time.sleep(0.1)
    return cond()


def bloques(d=LOGS):
    return sorted(n for n in os.listdir(d) if BLOQUE.match(n)) if os.path.isdir(d) else []


print('== log en disco ==')

# ---- A: stdio, salida limpia
s = mc.Stdio(EXE, ENV, nombre='log-battery')
check('A actual.log aparece junto al exe con el proceso VIVO',
      espera(lambda: 'Log en disco:' in lee(VIVO)), os.listdir(BASE))
t = lee(VIVO)
check('A el arranque dice donde esta el log (la misma nota en los tres modos)',
      'Log en disco:' in t and 'actual.log en vivo' in t and '(stdio)' in t, t[-400:])
s.call('delphi_help', {"command": "tool", "name": "MARCA-VIVA-1"})
check('A una peticion llega a disco en ~medio segundo, sin salir el proceso',
      espera(lambda: 'MARCA-VIVA-1' in lee(VIVO), 3), lee(VIVO)[-300:])
s.call('delphi_help', {"command": "tool", "name": "delphi_read", "password": "SECRETO-LOG-123"})
check('A una contrasena NUNCA llega al log (el enmascarador de siempre)',
      espera(lambda: '"password"' in lee(VIVO), 3) and 'SECRETO-LOG-123' not in lee(VIVO),
      [l for l in lee(VIVO).splitlines() if 'password' in l][:1])
check('A antes de salir no hay linea de parada', ': parado' not in lee(VIVO))
# F: una tira base64 (600 simbolos, con la barra escapada como la manda JSON)
# y una palabra corta del mismo alfabeto que NO es una tira
blob = base64.b64encode(bytes(range(256)) * 2).decode()[:600]
corta = 'QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo0MTIz'
s.rid += 1
s.p.stdin.write('{"jsonrpc":"2.0","id":%d,"method":"tools/call","params":{"name":"delphi_help",'
                '"arguments":{"command":"tool","name":"MARCA-B64","data":"%s","corta":"%s"}}}\n'
                % (s.rid, blob.replace('/', '\\/'), corta))
s.p.stdin.flush(); s.recv(s.rid)
espera(lambda: 'MARCA-B64' in lee(VIVO), 3)
linea = next((l for l in lee(VIVO).splitlines() if 'MARCA-B64' in l), '')
check('F fixture: la tira lleva barras escapadas', '/' in blob and '\\/' in blob.replace('/', '\\/'))
check('F una tira base64 no llega al log: queda su marca con el tamano',
      '[base64: 600 caracteres]' in linea and blob[100:160] not in linea
      and blob.replace('/', '\\/')[100:160] not in linea, linea[:300])
check('F el resto de la linea queda entero (una palabra corta del alfabeto no es una tira)',
      '"corta":"%s"' % corta in linea and '"name":"MARCA-B64"' in linea, linea[:300])
# G: la RESPUESTA que registra el transporte ("Sent:") no pasaba por el
# enmascarador. Un lint de estilos contesta un objeto con un campo "token"
# (el de diseno que falta en un tema): sin escapar, en structuredContent.
EST = os.path.join(BASE, 'estilos'); os.makedirs(EST)
open(os.path.join(EST, 'Min.style'), 'w', encoding='utf-8', newline='\n').write(
    "object TStyleContainer\n  object TLayout\n    StyleName = 'uno'\n  end\nend\n")
open(os.path.join(EST, 'tokens.ini'), 'w', encoding='utf-8').write('[claro]\nMARCA-TOK=1\n[oscuro]\nOTRO=1\n')
s.call('delphi_styles', {"path": EST, "command": "lint"})
espera(lambda: 'tokensMissing' in lee(VIVO), 3)
linea = next((l for l in lee(VIVO).splitlines() if 'tokensMissing' in l and '"token"' in l), '')
check('G fixture: la respuesta del lint esta en el log con su campo "token"', linea != '', lee(VIVO)[-300:])
check('G la respuesta registrada pasa por el enmascarador: "token":"***", nunca el valor',
      '"token":"***"' in linea and '"token":"MARCA-TOK"' not in linea, linea[:400])
s.cierra()
check('A salida limpia: queda la linea "parado" (la cola de la sesion llega a disco)',
      ': parado' in lee(VIVO), lee(VIVO)[-300:])

# ---- B: --http matado desde fuera
shutil.rmtree(LOGS, ignore_errors=True)
PORT = mc.puerto_libre()
h = mc.lanza_http(EXE, PORT, ENV, stdin=subprocess.DEVNULL)
check('B --http: el arranque esta en disco con el proceso vivo',
      espera(lambda: ('HTTP :%d' % PORT) in lee(VIVO) and 'Ready.' in lee(VIVO)), lee(VIVO)[-300:])
h.kill(); h.wait(10)
t = lee(VIVO)
check('B matado desde fuera: lo registrado sigue ahi (no hace falta salir bien)',
      ('HTTP :%d' % PORT) in t and ': parado' not in t, t[-300:])

# ---- C: rotacion, poda y el nombrador
shutil.rmtree(LOGS, ignore_errors=True)
os.makedirs(LOGS)
open(INI, 'w', encoding='utf-8').write('[Log]\nLinesPerFile=100\nMaxFiles=3\n')
FALSOS = ['20200101-000000.log', '20200101-000001.log', '20200101-000001-2.log']
AJENOS = ['notas.log', '20200101-000002-01.log', 'x20200101-000000.log', '20200101-000003-1.log']
for n in FALSOS + AJENOS:
    open(os.path.join(LOGS, n), 'w', encoding='utf-8').write('viejo ' + n + '\n')
s = mc.Stdio(EXE, ENV, nombre='log-battery')
nuevos = []
for i in range(400):
    s.call('delphi_help', {"command": "tool", "name": "ROTA-%03d" % i})
    if i % 25 == 24:
        time.sleep(0.8)
        nuevos = [n for n in bloques() if not n.startswith('2020')]
        if nuevos:
            break
check('C un bloque cada LinesPerFile lineas, con el proceso vivo', len(nuevos) >= 1, bloques())
t_bloques = ''.join(lee(os.path.join(LOGS, n)) for n in nuevos)
check('C el bloque ES la cola en vivo renombrada: empieza en el arranque de esta ejecucion',
      'Log en disco:' in t_bloques and 'ROTA-000' in t_bloques, t_bloques[:200])
s.call('delphi_help', {"command": "tool", "name": "TRAS-CORTE"})
check('C tras el corte, lo nuevo va a un actual.log nuevo (nada se pierde en el corte)',
      espera(lambda: 'TRAS-CORTE' in lee(VIVO), 3) and 'ROTA-000' not in lee(VIVO), lee(VIVO)[:200])
todos = bloques()
check('C se guardan los MaxFiles (3) bloques mas nuevos', len(todos) == 3, todos)
check('C el mas viejo se poda', '20200101-000000.log' not in todos, todos)
quedan = [n for n in todos if n.startswith('2020')]
check('C orden del nombrador: el "-2" es MAS NUEVO que su primero (se queda antes que el)',
      (not quedan) or ('20200101-000001-2.log' in quedan and
                       (len(quedan) == 2 or '20200101-000001.log' not in quedan)), quedan)
check('C un .log que el nombrador no compone NUNCA se toca',
      all(os.path.exists(os.path.join(LOGS, n)) for n in AJENOS), sorted(os.listdir(LOGS)))
s.cierra()
os.remove(INI)

# ---- D: junction plantado en logs\ hacia una victima de FUERA
shutil.rmtree(LOGS, ignore_errors=True)
os.makedirs(VICTIM)
open(os.path.join(VICTIM, '20200101-000000.log'), 'w', encoding='utf-8').write('VICTIMA\n')
open(os.path.join(VICTIM, 'dato.txt'), 'w', encoding='utf-8').write('dato\n')
antes = sorted(os.listdir(VICTIM))
subprocess.run(['cmd', '/c', 'mklink', '/J', LOGS, VICTIM], capture_output=True)
check('D fixture: logs\\ es un junction a la victima', os.path.isjunction(LOGS))
open(INI, 'w', encoding='utf-8').write('[Log]\nLinesPerFile=100\nMaxFiles=1\n')
try:
    s = mc.Stdio(EXE, ENV, nombre='log-battery')
    vivas = sum(1 for i in range(150)
                if s.call_msg('delphi_help', {"command": "tool", "name": "J-%03d" % i}) is not None)
    time.sleep(1.5)
    s.cierra()
    check('D el servidor sigue contestando con el log bloqueado', vivas == 150, vivas)
    check('D la victima sale INTACTA: ni actual.log ni bloques nuevos, nada podado',
          sorted(os.listdir(VICTIM)) == antes and lee(os.path.join(VICTIM, '20200101-000000.log')) == 'VICTIMA\n',
          sorted(os.listdir(VICTIM)))
finally:
    quita_enlace(LOGS)
    if os.path.exists(INI): os.remove(INI)

# ---- E: dos procesos, el mismo actual.log
shutil.rmtree(LOGS, ignore_errors=True)
a, b = mc.Stdio(EXE, ENV, nombre='log-battery-a'), mc.Stdio(EXE, ENV, nombre='log-battery-b')
def rafaga(srv, tag):
    for i in range(40):
        srv.call('delphi_help', {"command": "tool", "name": "MARCA-%s-%02d" % (tag, i)})
ta = threading.Thread(target=rafaga, args=(a, 'P1')); tb = threading.Thread(target=rafaga, args=(b, 'P2'))
ta.start(); tb.start(); ta.join(); tb.join()
a.cierra(); b.cierra()
t = lee(VIVO) + ''.join(lee(os.path.join(LOGS, n)) for n in bloques())
faltan = [m for m in ['MARCA-%s-%02d' % (g, i) for g in ('P1', 'P2') for i in range(40)] if m not in t]
check('E dos escritores a la vez: no se pierde ninguna linea', not faltan, faltan[:5])
rotas = [l for l in t.splitlines() if 'MARCA-P' in l and not l.startswith('[')]
check('E ninguna linea cortada dentro de otra', not rotas, rotas[:2])
check('E las dos salidas limpias dejan su "parado"', t.count(': parado') >= 2, t.count(': parado'))

if mc.F == 0:
    limpia()
mc.fin('log-disco battery')
