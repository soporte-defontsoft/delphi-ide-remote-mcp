"""E2E battery - binary .dfm (VCL) read on the fly and converted on purpose.

A legacy form saved in binary left an agent blind (Hermes, 2026-09-24): the
designer refused it and delphi_search saw no text. Now Lsp.DesignerBin (the
RTL's own ObjectResourceToText / ObjectTextToResource, what the IDE runs on
"View as Text" and on save) reads a binary .dfm on the fly everywhere that
reads, and delphi_designer to-text / to-binary convert it on disk, backup
first. Editing a binary directly stays refused, pointing at to-text.

The binary fixture is made by the server itself (to-binary of a text form),
so the battery measures the RTL path both ways without convert.exe; the
second to-binary must reproduce the first byte for byte.

Usage:  python tests/test_designer_binary.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'designer-binary')
shutil.rmtree(BASE, ignore_errors=True); os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe'); shutil.copy(SRC, EXE)

env = dict(os.environ); env['DELPHI_MCP_ROOTS'] = BASE
proc = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
q = queue.Queue()
def reader():
    for line in proc.stdout:
        line = line.strip()
        if line: q.put(line)
threading.Thread(target=reader, daemon=True).start()
rid = [10]
def send(o): proc.stdin.write(json.dumps(o) + '\n'); proc.stdin.flush()
def recv(r, t=120):
    dl = time.time() + t
    while time.time() < dl:
        try: line = q.get(timeout=1)
        except queue.Empty: continue
        try: m = json.loads(line)
        except Exception: continue
        if m.get('id') == r: return m
    return None
def call(name, args):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call", "params": {"name": name, "arguments": args}})
    r = recv(rid[0])
    if r is None: return '(timeout)'
    if 'error' in r: return 'MCPERROR ' + json.dumps(r['error'])[:200]
    c = r['result'].get('content', [])
    return c[0].get('text', '') if c else '(no content)'
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "dgb", "version": "1"}}})
recv(1); send({"jsonrpc": "2.0", "method": "notifications/initialized"})

P = F = 0
def check(name, ok, detail=''):
    global P, F
    if ok: P += 1; print('PASS', name)
    else: F += 1; print('FAIL', name, '--', str(detail)[:300])
def J(t):
    try: return json.loads(t)
    except Exception: return {}

# ---- fixture: a small VCL form in TEXT, then the server makes the binary
DFM = os.path.join(BASE, 'Legacy.dfm')
TEXT = """object FormLegacy: TFormLegacy
  Left = 274
  Top = 75
  Caption = 'Legacy'
  ClientHeight = 200
  ClientWidth = 300
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  TextHeight = 13
  object Label1: TLabel
    Left = 16
    Top = 16
    Width = 40
    Height = 13
    Caption = 'Nombre'
  end
  object Edit1: TEdit
    Left = 16
    Top = 40
    Width = 200
    Height = 21
    TabOrder = 0
  end
  object Button1: TButton
    Left = 16
    Top = 80
    Width = 75
    Height = 25
    Caption = 'Aceptar'
    TabOrder = 1
  end
end
"""
open(DFM, 'w', encoding='utf-8', newline='\r\n').write(TEXT)

r = call('delphi_designer', {'command': 'to-binary', 'path': DFM})
check('to-binary convierte el texto', 'CONVERTIDO' in r and 'BINARIO' in r, r[:200])
b1 = open(DFM, 'rb').read()
check('en disco: envoltorio de recurso $FF con TPF0 dentro', b1[:1] == b'\xff' and b'TPF0' in b1[:64], b1[:24])
check('copia previa en __delphi-patch', os.path.isdir(os.path.join(BASE, '__delphi-patch')), '')
r = call('delphi_designer', {'command': 'to-binary', 'path': DFM})
check('to-binary dos veces: nada que hacer', 'ya es binario' in r, r[:120])

# ---- reading the binary on the fly, everywhere that reads
r = call('delphi_read', {'path': DFM, 'fromline': 1, 'toline': 3})
check('delphi_read lee el binario como texto', '1|object FormLegacy: TFormLegacy' in r, r[:300])
check('delphi_read lo dice: BINARIO en disco + to-text', 'BINARIO' in r and 'to-text' in r, r[:200])
r = call('delphi_designer', {'command': 'tree', 'path': DFM})
j = J(r)
names = [c.get('name') for c in j.get('root', {}).get('children', [])]
check('tree del binario: los 3 hijos', names == ['Label1', 'Edit1', 'Button1'], r[:300])
check('tree lleva binaryOnDiskNote', 'binaryOnDiskNote' in j, list(j.keys()))
r = call('delphi_designer', {'command': 'get', 'path': DFM, 'component': 'Button1'})
check('get del binario: el bloque del boton', "Caption = 'Aceptar'" in r, r[:300])
check('get lleva la nota (texto)', 'BINARIO' in r and 'to-text' in r, r[-200:])
r = call('delphi_designer', {'command': 'lint', 'path': DFM})
check('lint del binario contesta (no rechaza)', 'RECHAZADO' not in r, r[:200])
r = call('delphi_designer', {'command': 'layout', 'path': DFM})
j = J(r)
check('layout del binario: clientWidth 300', j.get('clientWidth') == 300, r[:200])
r = call('delphi_search', {'path': BASE, 'query': 'object Edit1'})
check('delphi_search encuentra texto dentro del binario', '"total":1' in r.replace(' ', '') and 'Legacy.dfm' in r, r[:300])
r = call('delphi_projects', {'root': BASE})  # no projects here: just must not choke on the binary
check('un binario no rompe a quien lista', 'MCPERROR' not in r, r[:120])

# ---- editing the binary directly stays refused, pointing at to-text
r = call('delphi_edit', {'path': DFM, 'old': '  Left = 274', 'new': '  Left = 275'})
check('delphi_edit sobre el binario: RECHAZADO con TPF0/BINARIO', 'RECHAZADO' in r and 'BINARIO' in r and 'TPF0' in r, r[:200])
check('...y apunta a to-text', 'to-text' in r, r[:200])
check('el fichero no se toco', open(DFM, 'rb').read() == b1, '')

# ---- to-text, edit as text, to-binary reproduces the bytes
r = call('delphi_designer', {'command': 'to-text', 'path': DFM})
check('to-text convierte a texto', 'CONVERTIDO' in r and 'TEXTO' in r, r[:200])
t = open(DFM, 'rb').read()
check('en disco: texto, empieza por object, CRLF', t.startswith(b'object FormLegacy') and b'\r\n' in t and b'\xff' not in t[:4], t[:40])
r = call('delphi_designer', {'command': 'to-text', 'path': DFM})
check('to-text dos veces: nada que hacer', 'ya es texto' in r, r[:120])
r = call('delphi_read', {'path': DFM, 'fromline': 1, 'toline': 2})
check('delphi_read del texto: sin nota de binario', 'BINARIO' not in r, r[:200])
r = call('delphi_edit', {'path': DFM, 'old': '  Left = 274', 'new': '  Left = 275'})
check('editable como cualquier .dfm tras to-text', r.startswith('ESCRITO') or r.startswith('OK'), r[:120])
r = call('delphi_edit', {'path': DFM, 'old': '  Left = 275', 'new': '  Left = 274'})
r = call('delphi_designer', {'command': 'to-binary', 'path': DFM})
b2 = open(DFM, 'rb').read()
check('viaje redondo: el binario se reproduce byte a byte', b2 == b1, '%d vs %d bytes' % (len(b2), len(b1)))

# ---- accents: to-text writes #NNN like the IDE; to-binary reads a raw one
# through ANSI (what the RTL parser and the IDE expect) and refuses what ANSI
# cannot hold. Measured 2026-09-24: feeding the parser UTF-8 turned an 'o'
# with an accent into #195#179.
for nombre, enc in (('utf8', 'utf-8'), ('utf8bom', 'utf-8-sig'), ('cp1252', 'cp1252')):
    RAW = os.path.join(BASE, 'Raw_%s.dfm' % nombre)
    open(RAW, 'wb').write(("object FormR: TFormR\r\n  Caption = 'Configuración'\r\n"
                           "  ClientHeight = 10\r\n  ClientWidth = 10\r\nend\r\n").encode(enc))
    r = call('delphi_designer', {'command': 'to-binary', 'path': RAW})
    check('acento en crudo (%s): to-binary acepta' % nombre, 'CONVERTIDO' in r, r[:160])
    r = call('delphi_designer', {'command': 'to-text', 'path': RAW})
    t = open(RAW, 'rb').read()
    check('acento en crudo (%s): vuelve como #243, ASCII puro' % nombre,
          b"'Configuraci'#243'n'" in t and all(x < 128 for x in t), t[:120])
FUERA = os.path.join(BASE, 'FueraAnsi.dfm')
open(FUERA, 'wb').write("object FormF: TFormF\r\n  Caption = 'ok ✔'\r\n  ClientHeight = 10\r\n  ClientWidth = 10\r\nend\r\n".encode('utf-8'))
r = call('delphi_designer', {'command': 'to-binary', 'path': FUERA})
check('caracter fuera de ANSI en crudo: to-binary RECHAZADO con #NNNN', 'RECHAZADO' in r and '#NNNN' in r, r[:200])
check('...y el fichero no se toco', open(FUERA, 'rb').read().startswith(b'object FormF'), '')

# ---- .fmx is always text; a damaged binary is refused with the reason
FMX = os.path.join(BASE, 'Vista.fmx')
open(FMX, 'w', encoding='utf-8', newline='\r\n').write("object Form1: TForm1\n  Caption = 'x'\nend\n")
r = call('delphi_designer', {'command': 'to-binary', 'path': FMX})
check('.fmx: to-binary rechazado (siempre texto)', 'RECHAZADO' in r and '.fmx' in r, r[:200])
r = call('delphi_designer', {'command': 'to-text', 'path': FMX})
check('.fmx: to-text rechazado (siempre texto)', 'RECHAZADO' in r and '.fmx' in r, r[:200])
BAD = os.path.join(BASE, 'Roto.dfm')
open(BAD, 'wb').write(b'\xff\x0a\x00TROTO\x00\x30\x10\x10\x00\x00\x00TPF0basura sin sentido')
r = call('delphi_designer', {'command': 'tree', 'path': BAD})
check('binario danado: RECHAZADO con motivo', 'RECHAZADO' in r and 'BINARIO' in r, r[:200])
r = call('delphi_read', {'path': BAD})
check('delphi_read de un binario danado: RECHAZADO', 'RECHAZADO' in r, r[:200])
r = call('delphi_designer', {'command': 'to-text', 'path': BAD})
check('to-text de un binario danado: RECHAZADO, fichero intacto', 'RECHAZADO' in r and open(BAD, 'rb').read().startswith(b'\xff\x0a\x00TROTO'), r[:200])

proc.kill()
print('\n== designer-binary battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
