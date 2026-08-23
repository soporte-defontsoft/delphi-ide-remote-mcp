"""E2E battery for v0.43.0-beta - delphi_styles (FMX styles by StyleName):
view / get / set / clone / lint / build over a copy of a REAL style pipeline
(a text .style with 200+ styles, a Tokens.ini, an .rc), plus the refusals
and the new `pattern` of delphi_search.

Needs DelphiStyleConvert.exe next to the server exe (built from
src/DelphiStyleConvert.dproj) for build and for the platform default names.

Usage:  python tests/test_styles.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, re, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'styles-battery')
shutil.rmtree(BASE, ignore_errors=True)
STY = os.path.join(BASE, 'Styles')
PRJ = os.path.join(BASE, 'codigofuente')
os.makedirs(STY); os.makedirs(PRJ)

# --- a small but realistic style file (the shapes seen in a real export) ---
STYLE = """object TStyleContainer
  object TStyleDescription
    StyleName = 'Description'
    Title = 'Battery'
    Version = '1.0'
  end
  object TLayout
    StyleName = 'formheader'
    Size.Width = 200.000000000000000000
    Size.Height = 44.000000000000000000
    Visible = False
    object TRectangle
      StyleName = 'background'
      Align = Contents
      Fill.Color = xFFF6ECDB
      Stroke.Kind = None
      object TRectangle
        Align = Bottom
        Fill.Color = xFFD0BA8E
        Size.Height = 1.000000000000000000
      end
    end
    object TText
      StyleName = 'text'
      Align = Client
      TextSettings.Font.Size = 14.000000000000000000
      Text = 'cabecera'
    end
  end
  object TLayout
    StyleName = 'cardstyle'
    Size.Width = 100.000000000000000000
    object TRectangle
      StyleName = 'background'
      Fill.Gradient.Points = <
        item
          Color = xFFFFFFFF
          Offset = 0.000000000000000000
        end
        item
          Color = xFFEEEEEE
          Offset = 1.000000000000000000
        end>
      Fill.Color = xFFFFFFFF
    end
    object TPath
      StyleName = 'icon'
      Data.Path = {
        0100000000000000000000000000000000000000}
      Fill.Color = xFF000000
    end
  end
  object TLayout
    StyleName = 'duplicado'
    Visible = False
  end
  object TLayout
    StyleName = 'duplicado'
    Visible = True
  end
end
"""
open(os.path.join(STY, 'Battery.style'), 'w', encoding='utf-8', newline='\n').write(STYLE)
open(os.path.join(STY, 'Battery.Tokens.ini'), 'w', encoding='utf-8').write(
    "[clasico]\nbg=xFF000000\naccent=xFF111111\n\n[oscuro]\nbg=xFF222222\n")
open(os.path.join(STY, 'Battery.Estilos.rc'), 'w', encoding='utf-8').write(
    'BATTERY RCDATA "Battery.bin.style"\nOTRO RCDATA "NoExiste.bin.style"\n')
open(os.path.join(PRJ, 'UMain.fmx'), 'w', encoding='utf-8').write(
    "object FormMain: TFormMain\n  object Panel1: TPanel\n    StyleLookup = 'cardstyle'\n  end\n"
    "  object Button1: TButton\n    StyleLookup = 'buttonstyle'\n  end\n"
    "  object Label1: TLabel\n    StyleLookup = 'labelinventado'\n  end\nend\n")
open(os.path.join(PRJ, 'UMain.pas'), 'w', encoding='utf-8').write(
    "unit UMain;\ninterface\nimplementation\n// NOTA: no usar Lbl.StyleLookup := 'comentado1' aqui\n{ ni StyleLookup := 'comentado2' }\n(* StyleLookup := 'comentado3' *)\nprocedure X;\nbegin\n  Btn.StyleLookup := 'formheader';\n  Lbl.StyleLookup := 'otroinventado'; // StyleLookup := 'comentado4'\nend;\nend.\n")
# a binary style (signature only) to test the refusal
open(os.path.join(STY, 'Battery.bin.style'), 'wb').write(b'FMX_STYLE\x00\x01\x02' + b'\x00' * 40)


def spawn(extra_env=None):
    env = dict(os.environ)
    env['DELPHI_MCP_ROOTS'] = BASE
    env.update(extra_env or {})
    p = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
    q = queue.Queue()

    def reader():
        for line in p.stdout:
            line = line.strip()
            if line:
                q.put(line)
    threading.Thread(target=reader, daemon=True).start()
    return p, q


proc, q = spawn()
rid = [10]


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


def call(name, args, t=120):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call",
          "params": {"name": name, "arguments": args}})
    r = recv(rid[0], t)
    if r is None:
        return '(timeout)'
    if 'error' in r:
        return 'MCPERROR ' + json.dumps(r['error'])[:200]
    c = r['result'].get('content', [])
    return c[0].get('text', '') if c else '(no content)'


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "styles-battery", "version": "1"}}})
recv(1)
send({"jsonrpc": "2.0", "method": "notifications/initialized"})

P = F = 0


def check(name, cond, detail=''):
    global P, F
    if cond:
        P += 1
        print('  PASS', name)
    else:
        F += 1
        print('  FAIL', name, '|', str(detail)[:400])


def rd(p):
    return open(p, 'rb').read().decode('utf-8-sig')


S = os.path.join(STY, 'Battery.style')
print('== styles battery ==')

# ---- view ----
out = call('delphi_styles', {"path": S})
d = json.loads(out)
names = [x['style'] for x in d['styles']]
check('view: 5 estilos de primer nivel', d['count'] == 5 and names[1:3] == ['formheader', 'cardstyle'], names)
check('view: partes contadas (formheader=2)', [x for x in d['styles'] if x['style'] == 'formheader'][0]['parts'] == 2, d['styles'])
check('view: lineas del estilo', [x for x in d['styles'] if x['style'] == 'formheader'][0]['lines'] == '7-29', d['styles'])
check('view: colecciones <item> y binarios {...} no rompen el parseo', [x for x in d['styles'] if x['style'] == 'cardstyle'][0]['parts'] == 2, d['styles'])
out = call('delphi_styles', {"path": S, "command": "view", "filter": "card"})
check('view: filter', json.loads(out)['count'] == 1, out[:200])

# ---- get ----
out = call('delphi_styles', {"path": S, "command": "get", "style": "formheader"})
check('get: bloque entero', out.startswith('formheader (TLayout) lineas 7-29') and "Text = 'cabecera'" in out, out[:200])
out = call('delphi_styles', {"path": S, "command": "get", "style": "formheader", "child": "background"})
check('get: parte por child', 'background (TRectangle)' in out and 'Fill.Color = xFFF6ECDB' in out and 'cabecera' not in out, out[:300])
out = call('delphi_styles', {"path": S, "command": "get", "style": "noexiste"})
check('get: estilo inexistente rechazado con pista', 'RECHAZADO' in out and 'command=view' in out, out)

# ---- set ----
out = call('delphi_styles', {"path": S, "command": "set", "style": "formheader", "child": "background", "prop": "Fill.Color", "value": "xFF112233"})
check('set: CAMBIADA', out.startswith('CAMBIADA'), out[:200])
txt = rd(S)
check('set: valor en disco con la indentacion original', '      Fill.Color = xFF112233' in txt and 'xFFF6ECDB' not in txt, txt)
out = call('delphi_styles', {"path": S, "command": "set", "style": "formheader", "prop": "Opacity", "value": "0.500000000000000000"})
check('set: ANADIDA tras StyleName', out.startswith('ANADIDA'), out[:200])
txt = rd(S)
i = txt.index("StyleName = 'formheader'"); j = txt.index('Opacity = 0.5')
check('set: la nueva propiedad va justo tras el StyleName', 0 < j - i < 40, txt[i:j + 40])
out = call('delphi_styles', {"path": S, "command": "set", "style": "formheader", "child": "background/text", "prop": "X", "value": "1"})
check('set: child inexistente rechazado', 'RECHAZADO' in out and 'no tiene una parte' in out, out)
out = call('delphi_styles', {"path": S, "command": "set", "style": "formheader", "prop": "Opacity", "delete": True})
check('set delete: QUITADA', out.startswith('QUITADA') and 'Opacity' not in rd(S), out[:200])
out = call('delphi_styles', {"path": S, "command": "set", "style": "formheader", "prop": "Fill Color", "value": "x"})
check('set: prop con espacios rechazada', 'RECHAZADO' in out, out)
out = call('delphi_styles', {"path": S, "command": "set", "style": "formheader", "prop": "Visible"})
check('set: sin value pide value (y menciona delete)', 'Falta "value"' in out and 'delete=true' in out, out)
check('set: copia previa en __delphi-patch', os.path.isdir(os.path.join(STY, '__delphi-patch')))

# ---- clone ----
out = call('delphi_styles', {"path": S, "command": "clone", "style": "cardstyle", "name": "cardstyle_alt"})
check('clone: CLONADO', out.startswith('CLONADO'), out[:200])
d = json.loads(call('delphi_styles', {"path": S}))
names = [x['style'] for x in d['styles']]
check('clone: el nuevo va justo detras del origen', names.index('cardstyle_alt') == names.index('cardstyle') + 1, names)
check('clone: partes copiadas', [x for x in d['styles'] if x['style'] == 'cardstyle_alt'][0]['parts'] == 2, d['styles'])
check('clone: el origen intacto', rd(S).count("StyleName = 'cardstyle'") == 1 and rd(S).count("StyleName = 'cardstyle_alt'") == 1, '')
out = call('delphi_styles', {"path": S, "command": "clone", "style": "cardstyle", "name": "cardstyle_alt"})
check('clone: nombre ocupado rechazado', 'RECHAZADO' in out and 'ya existe' in out, out)
out = call('delphi_styles', {"path": S, "command": "clone", "style": "cardstyle", "name": "mal nombre"})
check('clone: nombre invalido rechazado', 'RECHAZADO' in out, out)

# ---- lint ----
out = call('delphi_styles', {"path": STY, "command": "lint", "project": PRJ})
d = json.loads(out)
check('lint: parsea', d.get('styleFiles') == 1 and d['styleNames'] >= 5, out[:300])
check('lint: StyleName duplicado detectado', len(d['duplicatedStyleNames']) == 1 and d['duplicatedStyleNames'][0]['style'] == 'duplicado', d['duplicatedStyleNames'])
missing = sorted(x['lookup'] for x in d['lookupsWithoutStyle'])
check('lint: lookups sin estilo (fmx y pas), no los del proyecto', missing == ['labelinventado', 'otroinventado'], missing)
check('lint: los StyleLookup en COMENTARIOS del .pas no cuentan (//, llaves, paren-star, fin de linea)', not any(m.startswith('comentado') for m in missing), missing)
check('lint: buttonstyle es estandar (estilo por defecto de la plataforma)', d['lookupsStandard'] == 1, d)
check('lint: token ausente en un tema', len(d['tokensMissing']) == 1 and d['tokensMissing'][0]['theme'] == 'oscuro' and d['tokensMissing'][0]['token'] == 'accent', d['tokensMissing'])
check('lint: .rc con fichero ausente', len(d['rcMissingFiles']) == 1 and d['rcMissingFiles'][0]['missing'] == 'NoExiste.bin.style', d['rcMissingFiles'])
check('lint: ok=false', d['ok'] is False, d['ok'])
check('lint: rutas enmascaradas', 'srv' in d['stylesDir'] and ':' in d['stylesDir'], d['stylesDir'])

# ---- build ----
os.remove(os.path.join(STY, 'Battery.bin.style'))
open(os.path.join(STY, 'Battery.Estilos.rc'), 'w', encoding='utf-8').write('BATTERY RCDATA "Battery.bin.style"\n')
out = call('delphi_styles', {"path": STY, "command": "build"})
d = json.loads(out)
check('build: conversion OK', d['converted'][0]['ok'] is True and d['converted'][0]['bytes'] > 100, out[:300])
check('build: .bin.style creado con firma FMX', open(os.path.join(STY, 'Battery.bin.style'), 'rb').read(9) == b'FMX_STYLE', '')
check('build: .rc -> .res', d.get('rcOk') is True and os.path.exists(os.path.join(STY, 'Battery.Estilos.res')), out[:300])
check('build: ok', d['ok'] is True, d)
# the binary must not be editable
out = call('delphi_styles', {"path": os.path.join(STY, 'Battery.bin.style'), "command": "view"})
check('binario rechazado para editar/ver', 'RECHAZADO' in out and 'BINARIO' in out, out)
# lint again: clean except the duplicate
out = call('delphi_styles', {"path": STY, "command": "lint", "project": PRJ})
d = json.loads(out)
check('lint tras build: rc limpio', d['rcMissingFiles'] == [], d['rcMissingFiles'])

# ---- refusals ----
out = call('delphi_styles', {"path": STY, "command": "get", "style": "x"})
check('get sobre carpeta rechazado', 'RECHAZADO' in out and 'UN fichero' in out, out)
out = call('delphi_styles', {"command": "view"})
check('sin path: pide path + reconectar', 'Falta "path"' in out and 'reconecta' in out, out)
out = call('delphi_styles', {"path": r'C:\Windows\win.ini', "command": "view"})
check('fuera de la jaula rechazado', 'RECHAZADO' in out or 'error' in out.lower(), out[:200])

# ---- delphi_search pattern ----
out = call('delphi_search', {"root": STY, "query": "StyleName = 'cardstyle'", "pattern": "*.style", "maxresults": 5})
d = json.loads(out)
check('search pattern=*.style: encuentra', d['total'] >= 1 and d['filesScanned'] >= 1, out[:200])
out = call('delphi_search', {"root": STY, "query": "cardstyle", "maxresults": 5})
check('search sin pattern: sigue sin barrer .style', json.loads(out)['filesScanned'] == 0, out[:200])
out = call('delphi_search', {"root": STY, "query": "x", "pattern": "*.style;*.ini"})
check('search pattern compuesto rechazado', 'RECHAZADO' in out, out[:200])

# ---- delete ----
out = call('delphi_styles', {"path": S, "command": "delete", "style": "cardstyle_alt"})
check('delete: BORRADO con lineas y contador', out.startswith('BORRADO') and 'quedan' in out, out[:200])
d = json.loads(call('delphi_styles', {"path": S}))
names = [x['style'] for x in d['styles']]
check('delete: el estilo ya no esta y el origen sigue', 'cardstyle_alt' not in names and 'cardstyle' in names, names)
check('delete: el resto del fichero intacto (formheader 7-29)', [x for x in d['styles'] if x['style'] == 'formheader'][0]['lines'] == '7-29', d['styles'])
out = call('delphi_styles', {"path": S, "command": "delete", "style": "noexiste"})
check('delete: estilo inexistente rechazado', 'RECHAZADO' in out, out)
out = call('delphi_styles', {"path": S, "command": "delete"})
check('delete: sin style pide style', 'style' in out.lower() and not out.startswith('BORRADO'), out)

proc.stdin.close(); time.sleep(1); proc.kill()

# (read-only mode is exercised over HTTP in test_http_auth.py)

print()
print('== styles battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
