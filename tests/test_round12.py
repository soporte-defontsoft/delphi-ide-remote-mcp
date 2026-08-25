"""E2E battery for v0.69.0-beta - round 8 of adversarial agent probing.

Three agents attacked the live server at once. What they found, and what this
battery pins down so it cannot come back:

  sec8 (security)
    S1  purging a trash FOLDER took every agent's copies inside it, no
        question asked. The check looked for "<folder>.by", which never
        exists, read that as "nobody's", and deleted the tree. Real damage:
        another agent's whole backup folder, gone.
    S2  the ".by" owner marker was writable: edit it to your own name and the
        copy is yours to purge.
    S3  another agent's recoverable copy was writable at all - you did not
        even need the purge to destroy what the trash exists to preserve.
        delphi_edit refused the trash; delphi_textedit had never heard of it.
    S4  editing inside the trash made a trash-of-the-trash, recursively.

  docs8 (documentation vs reality)
    D1  delphi_upload was the one writer with no designer rule: it replaced a
        LIVE text .dfm of a compiling project with a TPF0 stream, after which
        no tool here could read the file it had just written.
    D2  delphi_test called a red suite "ha terminado bien": exit code 1 with a
        format it could not count came back as no-tests, because the zero-test
        branch overwrote the verdict the exit code had already given.

  forms8 (VCL forms)
    F1  check-binding accepted a handler declared private/public. That is the
        exact runtime failure it promises to catch: the form loader only sees
        PUBLISHED methods.
    F2  "unit" never went through the jail - a file oracle over the whole
        machine, and it parsed whatever it found.
    F3  a second class in the same unit vouched for components that did not
        exist in the form's own class.
    F4  "A, B: TButton;" and "X: Vcl.StdCtrls.TButton;" made the whole
        declaration unreadable, so every name on it was reported missing.
    F5  inline frames: the frame's own children were reported as missing from
        the form.
    F6  a form inheriting from another UNIT reported every inherited member as
        missing. Now it says what it cannot see instead of lying.
    F7  duplicate component names (EComponentError at load) went unnoticed.
    F8  an empty "OnClick =" is an invalid .dfm; the build dies in RLINK32
        without naming the line, and check-binding said it was fine.
    F9  a .pas passed as "path" produced a report full of invented orphans.

Usage:  python tests/test_round12.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil, glob

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round12')
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


def recv(r, t=120):
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


def call(name, args):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call",
          "params": {"name": name, "arguments": args}})
    r = recv(rid[0])
    if not r:
        return '(sin respuesta)'
    if 'result' in r:
        return r['result']['content'][0]['text']
    return 'ERROR ' + json.dumps(r.get('error'), ensure_ascii=False)[:200]


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:320])


def W(rel, text):
    p = os.path.join(BASE, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'w', encoding='utf-8', newline='').write(text)
    return p


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "round12", "version": "1"}}})
recv(1)
send({"jsonrpc": "2.0", "method": "notifications/initialized"})
time.sleep(0.5)

# --------------------------------------------------------------- trash safety
victim = W('victima.txt', 'de otro agente\r\n')
call('delphi_delete', {'path': victim})


def trash_copies(stem):
    return [x for x in glob.glob(os.path.join(
        BASE, '__delphi-patch', '*', 'deleted', stem + '-*'))
        if not x.endswith('.by')]


copy = trash_copies('victima.txt')[0]
open(copy + '.by', 'w').write('otroagente')          # simulate another owner
datefolder = os.path.dirname(os.path.dirname(copy))  # ...\__delphi-patch\<date>

# S1 - the one that destroyed real work
r = call('delphi_delete', {'path': datefolder, 'purge': True})
check('S1 purgar una CARPETA con copias ajenas: RECHAZADO',
      'RECHAZADO' in r and 'otroagente' in r and os.path.exists(copy), r[:220])
r = call('delphi_delete', {'path': os.path.dirname(copy), 'purge': True})
check('S1 tampoco por la subcarpeta "deleted"',
      'RECHAZADO' in r and os.path.exists(copy), r[:200])

# S2 - the owner marker is not a text file you can rewrite
r = call('delphi_textedit', {'path': copy + '.by', 'old': 'otroagente',
                             'new': 'round12'})
check('S2 el marcador .by no se edita',
      'RECHAZADO' in r and open(copy + '.by').read().strip() == 'otroagente',
      r[:200])
r = call('delphi_delete', {'path': copy + '.by', 'purge': True})
check('S2 el marcador .by no se purga suelto',
      'RECHAZADO' in r and os.path.exists(copy + '.by'), r[:200])

# S3/S4 - the trash is not a scratchpad
before = open(copy, encoding='utf-8').read()
r = call('delphi_textedit', {'path': copy, 'old': 'de otro agente',
                             'new': 'pisado'})
check('S3 no se escribe dentro de la papelera',
      'RECHAZADO' in r and open(copy, encoding='utf-8').read() == before,
      r[:200])
check('S4 y por tanto no hay papelera dentro de la papelera',
      not os.path.exists(os.path.join(os.path.dirname(copy), '__delphi-patch')))
r = call('delphi_textedit', {'path': os.path.join(BASE, '__history', 'x.txt'),
                             'create': True, 'content': 'x'})
check('S3 __history tampoco es escribible', 'RECHAZADO' in r, r[:160])

# you can still purge what is yours
mine = W('mio.txt', 'mio\r\n')
call('delphi_delete', {'path': mine})
mycopy = trash_copies('mio.txt')[0]
r = call('delphi_delete', {'path': mycopy, 'purge': True})
check('S1 lo tuyo se sigue purgando',
      'PURGADO' in r and not os.path.exists(mycopy), r[:160])

# ------------------------------------------------------------------- upload
DFM_OK = ("object Form1: TForm1\r\n  Caption = 'x'\r\n"
          "  object Btn: TButton\r\n    Caption = 'b'\r\n  end\r\nend\r\n")
live = W('proj/UMain.dfm', DFM_OK)
import base64
tpf0 = base64.b64encode(b'TPF0\x06TForm1\x05Form1\x00\x00').decode()
r = call('delphi_upload', {'path': live, 'chunkbase64': tpf0, 'offset': 0})
check('D1 upload NO pisa un .dfm de texto con un binario TPF0',
      'RECHAZADO' in r and open(live, encoding='utf-8',
                               newline='').read() == DFM_OK,
      r[:220])
resw = base64.b64encode(b'\xff\x0a\x00FORM1\x00TPF0').decode()
r = call('delphi_upload', {'path': os.path.join(BASE, 'proj', 'Nuevo.dfm'),
                           'chunkbase64': resw, 'offset': 0})
check('D1 tampoco crea uno nuevo envuelto en recurso ($FF)',
      'RECHAZADO' in r and not os.path.exists(
          os.path.join(BASE, 'proj', 'Nuevo.dfm')), r[:200])
r = call('delphi_upload', {'path': live + '.by', 'chunkbase64': tpf0})
check('S2 upload tampoco escribe marcadores .by', 'RECHAZADO' in r, r[:160])

# ------------------------------------------------------------- check-binding
PAS_HEAD = ("unit UMain;\r\n\r\ninterface\r\n\r\nuses Vcl.Forms, Vcl.StdCtrls;"
            "\r\n\r\ntype\r\n")


def binding(dfm, pas, unit=None, name='UMain'):
    d = W('bind/%s.dfm' % name, dfm)
    W('bind/%s.pas' % name, pas)
    args = {'command': 'check-binding', 'path': d}
    if unit:
        args['unit'] = unit
    return call('delphi_designer', args)


def J(r):
    try:
        return json.loads(r)
    except Exception:
        return {}


# F1 - the worst false negative: handler not published
dfm = ("object FormMain: TFormMain\r\n  object BtnDel: TButton\r\n"
       "    OnClick = BtnDelClick\r\n  end\r\nend\r\n")
pas = PAS_HEAD + ("  TFormMain = class(TForm)\r\n    BtnDel: TButton;\r\n"
                  "  private\r\n    procedure BtnDelClick(Sender: TObject);\r\n"
                  "  end;\r\n\r\nimplementation\r\n\r\nend.\r\n")
o = J(binding(dfm, pas))
check('F1 manejador declarado en private: NO cuadra',
      o.get('ok') is False and len(o.get('eventsWithMethodNotPublished', [])) == 1,
      o)
# ...and published is still fine
pas_ok = PAS_HEAD + ("  TFormMain = class(TForm)\r\n    BtnDel: TButton;\r\n"
                     "    procedure BtnDelClick(Sender: TObject);\r\n"
                     "  end;\r\n\r\nimplementation\r\n\r\nend.\r\n")
o = J(binding(dfm, pas_ok))
check('F1 y publicado sigue dando ok', o.get('ok') is True, o)

# F2 - the jail
r = binding(dfm, pas_ok, unit='C:\\Windows\\win.ini')
check('F2 "unit" pasa por la carcel',
      'RECHAZADO' in r and 'FUERA' in r.upper(), r[:200])
r = binding(dfm, pas_ok, unit='C:\\Windows\\no-existe-esto-jamas.pas')
check('F2 y no delata si un fichero de fuera existe o no',
      'RECHAZADO' in r and 'FUERA' in r.upper(), r[:200])
r = binding(dfm, pas_ok, unit=os.path.join(BASE, 'victima.txt'))
check('F2 "unit" tiene que ser un .pas', 'RECHAZADO' in r, r[:180])

# F3 - a second class must not vouch for anything
dfm3 = ("object FormMain: TFormMain\r\n  object BtnFantasma: TButton\r\n"
        "    OnClick = OtroClick\r\n  end\r\nend\r\n")
pas3 = PAS_HEAD + ("  TFormMain = class(TForm)\r\n  end;\r\n\r\n"
                   "  TOtro = class(TForm)\r\n    BtnFantasma: TButton;\r\n"
                   "    procedure OtroClick(Sender: TObject);\r\n  end;\r\n"
                   "\r\nimplementation\r\n\r\nend.\r\n")
o = J(binding(dfm3, pas3))
check('F3 otra clase de la misma unit no avala nada',
      o.get('ok') is False and len(o.get('componentsWithoutField', [])) == 1
      and len(o.get('eventsWithoutMethod', [])) == 1, o)

# F4 - multiple declaration and qualified type
dfm4 = ("object FormMain: TFormMain\r\n  object BtnA: TButton\r\n  end\r\n"
        "  object BtnB: TButton\r\n  end\r\n  object BtnQ: TButton\r\n  end\r\n"
        "end\r\n")
pas4 = PAS_HEAD + ("  TFormMain = class(TForm)\r\n    BtnA, BtnB: TButton;\r\n"
                   "    BtnQ: Vcl.StdCtrls.TButton;\r\n  end;\r\n\r\n"
                   "implementation\r\n\r\nend.\r\n")
o = J(binding(dfm4, pas4))
check('F4 "A, B: TButton;" y tipo cualificado se entienden',
      o.get('ok') is True, o)

# F5 - inline frames belong to the frame
dfm5 = ("object FormMain: TFormMain\r\n  inline Barra: TBarra\r\n"
        "    inherited BtnFrame: TButton\r\n    end\r\n  end\r\nend\r\n")
pas5 = PAS_HEAD + ("  TFormMain = class(TForm)\r\n    Barra: TBarra;\r\n"
                   "  end;\r\n\r\nimplementation\r\n\r\nend.\r\n")
o = J(binding(dfm5, pas5))
check('F5 los hijos de un frame inline no son del form',
      o.get('ok') is True, o)

# F6 - inheritance leaving the unit: honesty, not invention
dfm6 = ("inherited Child: TChild\r\n  inherited PanelTop: TPanel\r\n  end\r\n"
        "end\r\n")
pas6 = ("unit UChild;\r\n\r\ninterface\r\n\r\nuses UMain;\r\n\r\ntype\r\n"
        "  TChild = class(TFormMain)\r\n  end;\r\n\r\n"
        "implementation\r\n\r\nend.\r\n")
o = J(binding(dfm6, pas6, name='UChild'))
check('F6 herencia de otra unit: lo dice, no inventa que falta',
      o.get('componentsWithoutField') == [] and 'partialNote' in o, o)

# F7 - duplicate names
dfm7 = ("object FormMain: TFormMain\r\n  object Btn: TButton\r\n  end\r\n"
        "  object Btn: TButton\r\n  end\r\nend\r\n")
pas7 = PAS_HEAD + ("  TFormMain = class(TForm)\r\n    Btn: TButton;\r\n"
                   "  end;\r\n\r\nimplementation\r\n\r\nend.\r\n")
o = J(binding(dfm7, pas7))
check('F7 nombre de componente repetido (EComponentError)',
      o.get('ok') is False and len(o.get('duplicateNames', [])) == 1, o)

# F8 - an event with no value is an invalid .dfm
dfm8 = ("object FormMain: TFormMain\r\n  object Btn: TButton\r\n"
        "    OnClick = \r\n  end\r\nend\r\n")
o = J(binding(dfm8, pas7))
check('F8 "OnClick =" vacio: .dfm invalido, avisado',
      o.get('ok') is False and len(o.get('eventsWithNoHandler', [])) == 1, o)

# F9 - a .pas is not a form
r = call('delphi_designer', {'command': 'check-binding',
                             'path': os.path.join(BASE, 'bind', 'UMain.pas')})
check('F9 un .pas como "path" se rechaza', 'RECHAZADO' in r, r[:180])

# root class not declared in the unit
dfm10 = "object X: TNoExiste\r\n  object Btn: TButton\r\n  end\r\nend\r\n"
o = J(binding(dfm10, pas7))
check('la clase raiz del .dfm tiene que existir en la unit',
      o.get('ok') is False and 'TNoExiste' in json.dumps(o), o)

# and the tool is discoverable at all
r = call('delphi_designer', {'command': 'volar', 'path': 'x'})
check('el error de comando nombra check-binding', 'check-binding' in r, r[:200])

proc.kill()
print('\n== round-12 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
