"""E2E battery for v0.12.0-beta:
- virtual drive units (srvX:) round trip, byte-fidelity exemptions, masking
  of jail rejections, 8.3-immune single rule, boundary false positives;
- delphi_edit: delete mode, blank-line message, insert rutina-global in .dpr
  (between uses and the main begin), insert metodo into the implicit
  published section of a form class;
- acentos= metric without the BOM;
- git commit/tag messages via -F (double quotes survive);
- Roots parsing: surrounding quotes tolerated, invalid roots fail CLOSED.

Usage:  python tests/test_v012.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, re, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'v012')
shutil.rmtree(BASE, ignore_errors=True)
INSIDE = os.path.join(BASE, 'permitido')
os.makedirs(INSIDE, exist_ok=True)

DRIVE = INSIDE[0].upper()            # the real drive of the jail
VJAIL = 'srv' + DRIVE.lower() + INSIDE[1:]   # its virtual form

SRC = ('unit Dentro;\r\n\r\ninterface\r\n\r\nprocedure Uno;\r\n\r\n'
       'implementation\r\n\r\nprocedure Uno;\r\nbegin\r\nend;\r\n\r\nend.\r\n')
open(os.path.join(INSIDE, 'Dentro.pas'), 'wb').write(SRC.encode('cp1252'))

# file whose CONTENT carries a real path + a boundary false-positive bait
BAIT = ('linea con ruta real ' + DRIVE + ':\\carpeta\\f.txt\r\n'
        'refspec HEA' + DRIVE + ':\\no-es-ruta\r\n')
open(os.path.join(INSIDE, 'contenido.txt'), 'wb').write(BAIT.encode('cp1252'))

DPR = ('program Mini;\r\n\r\n'
       "{$APPTYPE CONSOLE}\r\n\r\n"
       'uses\r\n  System.SysUtils;\r\n\r\n'
       'begin\r\n  Writeln(1);\r\nend.\r\n')
open(os.path.join(INSIDE, 'Mini.dpr'), 'wb').write(DPR.encode('cp1252'))

FORM = ('unit UF;\r\n\r\ninterface\r\n\r\nuses\r\n  System.Classes;\r\n\r\n'
        'type\r\n  TFormPrueba = class(TObject)\r\n'
        '    Nombre: string;\r\n'
        '  private\r\n    FDato: Integer;\r\n'
        '  end;\r\n\r\nimplementation\r\n\r\nend.\r\n')
open(os.path.join(INSIDE, 'UF.pas'), 'wb').write(FORM.encode('cp1252'))


def start(envroots, extra_env=None):
    env = dict(os.environ)
    env['DELPHI_MCP_ROOTS'] = envroots
    env.update(extra_env or {})
    p = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                         text=True, encoding='utf-8')
    qq = queue.Queue()

    def reader():
        for line in p.stdout:
            line = line.strip()
            if line:
                qq.put(line)
    threading.Thread(target=reader, daemon=True).start()
    return p, qq


proc, q = start(INSIDE)
rid = [10]


def send(o):
    proc.stdin.write(json.dumps(o) + '\n')
    proc.stdin.flush()


def recv(r, t=90):
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


def call(name, args, t=90):
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


def handshake():
    send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "v012-battery", "version": "1"}}})
    assert recv(1, 20), 'no initialize response'
    send({"jsonrpc": "2.0", "method": "notifications/initialized"})


handshake()

P = F = 0


def check(name, cond, detail=''):
    global P, F
    if cond:
        P += 1
        print('PASS -', name)
    else:
        F += 1
        print('FAIL -', name, '|', str(detail)[:200])


IN_PAS = os.path.join(INSIDE, 'Dentro.pas')
V_PAS = 'srv' + DRIVE.lower() + IN_PAS[1:]

# ---- virtual drive units: outbound masking -------------------------------
out = call('delphi_workspace', {})
ws = json.loads(out)
check('workspace: roots salen con unidad virtual',
      ws['roots'] and ws['roots'][0].lower().startswith('srv' + DRIVE.lower() + ':'), out)
check('workspace: la unidad real no viaja', (DRIVE + ':\\') not in out, out)
check('workspace: la nota explica las unidades virtuales', 'srv' in ws.get('note', ''), out)

out = call('delphi_read', {"path": os.path.join(INSIDE, 'nada.pas')})
check('read: rechazo "no existe" enmascarado (la exencion es solo para contenido)',
      'srv' + DRIVE.lower() + ':' in out and (DRIVE + ':\\') not in out, out)

OUTSIDE = os.path.join(BASE, 'prohibido')
os.makedirs(OUTSIDE, exist_ok=True)
out = call('delphi_edit', {"path": os.path.join(OUTSIDE, 'x.pas'),
                           "old": "a", "new": "b"})
check('rechazo enjaulado: roots del mensaje enmascarados',
      'FUERA de los workspaces' in out and 'srv' + DRIVE.lower() + ':' in out
      and (DRIVE + ':\\') not in out, out)

# ---- inbound expansion: whole cycle through the virtual unit --------------
out = call('delphi_read', {"path": V_PAS})
check('read por unidad virtual', 'unit Dentro' in out, out)

out = call('delphi_edit', {"path": V_PAS, "old": "unit Dentro;",
                           "new": "unit Dentro; // virtual"})
check('edit por unidad virtual', out.startswith('ESCRITO'), out)

# ---- byte fidelity: read/fetch content is NEVER masked --------------------
out = call('delphi_read', {"path": os.path.join(INSIDE, 'contenido.txt')})
check('read: contenido con ruta real intacto (sin enmascarar)',
      (DRIVE + ':\\carpeta\\f.txt') in out, out)
check('read: cebo de falso positivo intacto',
      ('HEA' + DRIVE + ':\\no-es-ruta') in out, out)

# search DOES mask its result lines, but must not touch the bait (letter
# before the drive letter = not a path start)
out = call('delphi_search', {"root": INSIDE, "query": "refspec"})
check('search: falso positivo NO enmascarado', 'HEAsrv' not in out, out)

# ---- delete / blank ------------------------------------------------------
out = call('delphi_edit', {"path": V_PAS, "old": "procedure Uno;",
                           "new": "", "atline": 5})
check('blanquear linea: mensaje claro', 'BLANQUEADA la linea 5' in out, out)

out = call('delphi_edit', {"path": V_PAS, "old": "  Nombre: string;", "delete": True})
check('delete: rechaza ancla inexistente en este fichero',
      'RECHAZADO' in out and 'no aparece' in out, out)

out = call('delphi_read', {"path": V_PAS})
lines_before = out.count('\n')
out = call('delphi_edit', {"path": V_PAS, "old": "unit Dentro; // virtual",
                           "delete": True})
check('delete: borra la linea entera', 'BORRADA la linea 1' in out, out)
out = call('delphi_read', {"path": V_PAS})
check('delete: la linea ya no existe', 'unit Dentro; // virtual' not in out
      and out.count('\n') == lines_before - 1, out)
# restore sanity: put the unit header back so the file stays a unit
call('delphi_edit', {"path": V_PAS, "old": "interface",
                     "new": "unit Dentro;\ninterface", "atline": 2})

out = call('delphi_edit', {"path": V_PAS, "old": "implementation",
                           "new": "algo", "delete": True})
check('delete: new junto a delete rechazado', 'RECHAZADO' in out and 'delete:true no lleva' in out, out)

# ---- B3: rutina-global inside a .dpr -------------------------------------
DPR_PATH = os.path.join(INSIDE, 'Mini.dpr')
out = call('delphi_edit', {"path": DPR_PATH, "insert": "rutina-global",
                           "code": "procedure Saluda;\nbegin\n  Writeln('hola');\nend;"})
check('dpr: insert rutina-global aceptado', 'INSERT rutina-global (.dpr)' in out, out)
raw = open(DPR_PATH, 'rb').read().decode('cp1252')
iuses = raw.find('System.SysUtils;')
iproc = raw.find('procedure Saluda;')
imain = raw.find('begin\r\n  Writeln(1);')
check('dpr: rutina entre uses y begin principal',
      -1 < iuses < iproc < imain, f'uses={iuses} proc={iproc} main={imain}')

out = call('delphi_edit', {"path": DPR_PATH, "insert": "metodo",
                           "inclass": "TX", "code": "procedure Nada;\nbegin\nend;"})
check('dpr: insert metodo rechazado con guia', 'no aplica a un .dpr' in out, out)

# ---- C1: metodo en la seccion published implicita -------------------------
UF = os.path.join(INSIDE, 'UF.pas')
out = call('delphi_edit', {"path": UF, "insert": "metodo", "inclass": "TFormPrueba",
                           "visibility": "published",
                           "code": "procedure BotonClick(Sender: TObject);\nbegin\n  FDato := 1;\nend;"})
check('published implicita: aceptado', 'INSERT metodo' in out and 'DOS mitades' in out, out)
raw = open(UF, 'rb').read().decode('cp1252')
icls = raw.find('TFormPrueba = class(TObject)')
idecl = raw.find('procedure BotonClick(Sender: TObject);')
ipriv = raw.find('private')
check('published implicita: declaracion tras la cabecera de la clase',
      -1 < icls < idecl < ipriv, f'cls={icls} decl={idecl} priv={ipriv}')
iimpl = raw.find('procedure TFormPrueba.BotonClick')
check('published implicita: implementacion cualificada presente', iimpl > ipriv, raw[-200:])

out = call('delphi_edit', {"path": UF, "insert": "metodo", "inclass": "TFormPrueba",
                           "visibility": "protected",
                           "code": "procedure Otra;\nbegin\nend;"})
check('visibility inexistente distinta de published: sigue rechazada',
      'RECHAZADO' in out and "no tiene seccion 'protected'" in out, out)

# ---- B2: acentos= sin contar el BOM ---------------------------------------
NU = os.path.join(INSIDE, 'Nueva.Unidad.pas')
out = call('delphi_edit', {"path": NU, "createunit": True})
check('createunit: informa el encoding del IDE', 'el configurado en el IDE' in out, out)
out = call('delphi_read', {"path": NU})
check('acentos=0 en unit nueva sin acentos (BOM fuera de la cuenta)',
      'acentos=0' in out, out)

# ---- B1: git commit con comillas ------------------------------------------
GITDIR = os.path.join(INSIDE, 'repo')
os.makedirs(GITDIR, exist_ok=True)
out = call('delphi_git', {"repo": GITDIR, "command": "init", "args": ""})
if 'exit=0' in out:
    call('delphi_git', {"repo": GITDIR, "command": "config", "args": "user.name", "message": "Test Bot"})
    call('delphi_git', {"repo": GITDIR, "command": "config", "args": "user.email", "message": "bot@test.local"})
    call('delphi_textedit', {"path": os.path.join(GITDIR, 'a.txt'), "create": True, "content": "hola\n"})
    call('delphi_git', {"repo": GITDIR, "command": "add", "args": "-A"})
    MSG = 'fix: "comillas dobles" y \'simples\' con acentos (ó)'
    out = call('delphi_git', {"repo": GITDIR, "command": "commit", "args": "", "message": MSG})
    check('commit con comillas: exit=0', 'exit=0' in out, out)
    out = call('delphi_git', {"repo": GITDIR, "command": "log", "args": "--format=%B -1"})
    check('commit con comillas: el mensaje sobrevive byte a byte',
          '"comillas dobles"' in out and '(ó)' in out, out)
else:
    check('git disponible para la prueba de commit', False, out)

# ---- R3-1: LSP URIs must not leak the real drive (file:///D%3A/...) --------
out = call('delphi_symbols', {"path": V_PAS})
check('LSP: la URI no filtra la unidad real (%3A)',
      (DRIVE + '%3A') not in out and (DRIVE + '%3a') not in out, out[:200])

# ---- C1-bis: published declaration AFTER the fields, never before ----------
FORM2 = os.path.join(INSIDE, 'UF2.pas')
open(FORM2, 'wb').write(FORM.replace('TFormPrueba', 'TFormDos').encode('cp1252'))
out = call('delphi_edit', {"path": FORM2, "insert": "metodo", "inclass": "TFormDos",
                           "visibility": "published",
                           "code": "procedure BotonClick(Sender: TObject);\nbegin\nend;"})
check('C1-bis: insert aceptado', 'INSERT metodo' in out, out[:150])
raw = open(FORM2, 'rb').read().decode('cp1252')
icampo = raw.find('Nombre: string;')
idecl = raw.find('procedure BotonClick(Sender: TObject);')
ipriv = raw.find('private')
check('C1-bis: declaracion DESPUES del campo y antes de private (no E2169)',
      -1 < icampo < idecl < ipriv, f'campo={icampo} decl={idecl} priv={ipriv}')

# ---- delphi_report: works at every level, one .md per report ---------------
import glob as _glob
RDIR = os.path.join(os.path.dirname(EXE), 'reports')
before = set(_glob.glob(os.path.join(RDIR, '*.md')))
out = call('delphi_report', {"message": "Al usar delphi_x paso Y, esperaba Z.",
                             "title": "Prueba de la bateria",
                             "kind": "bug", "from": "test_v012"})
check('report: aceptado y guardado', 'GRACIAS' in out and '.md' in out, out[:150])
after = set(_glob.glob(os.path.join(RDIR, '*.md')))
new_files = after - before
check('report: creo exactamente 1 fichero .md', len(new_files) == 1, new_files)
if new_files:
    txt = open(list(new_files)[0], encoding='utf-8-sig').read()
    check('report: lleva version, fecha y mensaje',
          'Server version' in txt and 'Date' in txt and 'esperaba Z' in txt, txt[:200])
out = call('delphi_report', {"message": ""})
check('report: mensaje vacio rechazado', 'RECHAZADO' in out, out[:120])

# ---- delphi_report: "agent" groups reports in a folder per emitter ---------
ADIR = os.path.join(RDIR, 'bateria-v012')
out = call('delphi_report', {"message": "reporte con carpeta de agente",
                             "title": "agente", "kind": "question",
                             "agent": "Bateria V012!"})
check('report agent: aceptado y cita la subcarpeta',
      'GRACIAS' in out and 'bateria-v012/' in out, out[:150])
afiles = _glob.glob(os.path.join(ADIR, '*.md'))
check('report agent: el .md cae en reports/<agente>/ (slug normalizado)',
      len(afiles) == 1, afiles)
if afiles:
    txt = open(afiles[0], encoding='utf-8-sig').read()
    check('report agent: la cabecera lleva Agent', '**Agent**: bateria-v012' in txt, txt[:250])
    os.remove(afiles[0])
try:
    os.rmdir(ADIR)
except OSError:
    pass
out = call('delphi_report', {"message": "sin agente sigue en la raiz",
                             "title": "raiz", "kind": "question"})
saved_name = out.split('como ')[-1].split(' (v')[0] if 'como ' in out else '?'
check('report sin agent: sigue en la raiz de reports',
      'GRACIAS' in out and '/' not in saved_name, out[:150])

# ---- git dangerous options refused at the GATE (both access levels) --------
PWN = os.path.join(INSIDE, 'PWNED.txt')
out = call('delphi_git', {"repo": INSIDE, "command": "diff", "args": "--output=" + PWN})
check('git: --output rechazado en el gate (aun con token RW)',
      'RECHAZADO' in out and 'git' in out, out[:150])
check('git: --output no escribio nada', not os.path.exists(PWN), PWN)
out = call('delphi_git', {"repo": INSIDE, "command": "log", "args": "--oneline -3"})
check('git: log normal sigue funcionando (sin falso positivo)',
      'RECHAZADO' not in out, out[:120])

# ---- R4-A: fetch virtualizes its path, base64 payload untouched -----------
import base64 as _b64
out = call('delphi_fetch', {"path": V_PAS, "offset": 0, "maxbytes": 64})
try:
    fd = json.loads(out)
except Exception:
    fd = {}
check('R4-A: fetch devuelve el path virtualizado',
      fd.get('path', '').lower().startswith('srv' + DRIVE.lower() + ':'), out[:150])
ok_b64 = False
try:
    _b64.b64decode(fd.get('chunkBase64', ''), validate=True)
    ok_b64 = True
except Exception:
    pass
check('R4-A: el base64 sigue siendo decodificable (mascara inocua)', ok_b64, out[:120])

# ---- R4-B: workspace announces the readable library zone ------------------
out = call('delphi_workspace', {})
ws2 = json.loads(out)
check('R4-B: workspace publica readableExtra',
      isinstance(ws2.get('readableExtra'), list) and len(ws2['readableExtra']) > 0, out[:200])
check('R4-B: readableExtra tambien virtualizado', (DRIVE + ':\\') not in out, out[:200])

# ---- R4-C: list canonicalizes, no '..' echoed back ------------------------
out = call('delphi_list', {"root": os.path.join(INSIDE, 'sub', '..'), "pattern": "*.pas"})
check('R4-C: la salida de list no arrastra ".."', '..' not in out, out[:150])

# ---- delphi_config: view + add-platform with the VCL/FMX rule -------------
import shutil as _sh
# Both fixtures are derived from the ONE real project (there is a single one
# since the hosts merged): the VCL copy verbatim, and a FrameworkType=None copy
# for the non-VCL case. Deriving them keeps the test honest about the real
# .dproj shape without needing a second project to exist just to be test data.
_real = open(os.path.join(REPO, 'src', 'DelphiLspMcp.dproj'), encoding='utf-8').read()
VCLP = os.path.join(INSIDE, 'VclProj.dproj')
open(VCLP, 'w', encoding='utf-8').write(_real)                       # VCL
CON = os.path.join(INSIDE, 'ConfProj.dproj')
open(CON, 'w', encoding='utf-8').write(
    _real.replace('<FrameworkType>VCL</FrameworkType>',
                  '<FrameworkType>None</FrameworkType>'))            # no framework

out = call('delphi_config', {"project": CON})
cfg = json.loads(out)
check('config: view lista configuraciones', 'Debug' in cfg.get('configurations', []), out[:150])
check('config: view lista plataformas con estado',
      any(p.get('name') == 'Win64' for p in cfg.get('platforms', [])), out[:150])

out = call('delphi_config', {"project": VCLP, "command": "add-platform", "platform": "Linux64"})
check('config: add-platform Linux64 en VCL RECHAZADO (regla VCL!=FMX)',
      'RECHAZADO' in out and 'VCL' in out, out[:150])
out = call('delphi_config', {"project": CON, "command": "add-platform", "platform": "Linux64"})
# shape, not data: the fixture is a copy of the live .dproj, so Linux64 may
# arrive undeclared (ANADIDA) or declared-but-disabled (HABILITADA) - both
# mean "the console project accepted the platform"
check('config: add-platform Linux64 en consola aceptado',
      ('ANADIDA' in out) or ('HABILITADA' in out), out[:150])

# R5-B: platform name is whitelisted - XML injection into the .dproj refused
inj = 'Win64"/><Import Project=' + chr(34) + 'evilshare' + chr(34) + '/><X y='
out = call('delphi_config', {"project": CON, "command": "add-platform", "platform": inj})
check('R5-B: inyeccion XML por el nombre de plataforma RECHAZADA',
      'RECHAZADO' in out and 'no es una plataforma' in out, out[:150])
check('R5-B: el payload no se escribio en el .dproj',
      'evilshare' not in open(CON, encoding='utf-8-sig').read(), 'injected!')
out = call('delphi_config', {"project": CON, "command": "add-platform", "platform": "NoExiste99"})
check('R5-B: plataforma inventada RECHAZADA', 'RECHAZADO' in out, out[:120])
# before removing: R6-A - view must report Linux64 as ENABLED (it was just added)
_plats = {p['name']: p.get('enabled') for p in json.loads(call('delphi_config', {"project": CON})).get('platforms', [])}
check('R6-A: view reporta enabled=True para una plataforma activa (Linux64)',
      _plats.get('Linux64') is True, _plats)
check('R6-A: view reporta enabled=True para Win64 (value=True en el .dproj)',
      _plats.get('Win64') is True, _plats)
# R5-C: remove-platform (with backup)
out = call('delphi_config', {"project": CON, "command": "remove-platform", "platform": "Linux64"})
check('R5-C: remove-platform deshabilita', 'DESHABILITADA' in out, out[:120])
out = call('delphi_config', {"project": CON})
_plats = {p['name']: p.get('enabled') for p in json.loads(out).get('platforms', [])}
check('R6-A: Linux64 queda DECLARADA pero enabled=False tras remove-platform',
      'Linux64' in _plats and _plats['Linux64'] is False, _plats)

# ---- delphi_config set-output: all binaries under one folder ---------------
out = call('delphi_config', {"project": CON, "command": "set-output", "output": "Compiled"})
check('set-output: fija la carpeta Compiled',
      'DCC_ExeOutput' in out and r'.\Compiled\$(Platform)\$(Config)' in out, out[:150])
_dproj = open(CON, encoding='utf-8-sig').read()
check('set-output: DCC_ExeOutput escrito en el .dproj',
      r'<DCC_ExeOutput>.\Compiled\$(Platform)\$(Config)</DCC_ExeOutput>' in _dproj, 'not written')
check('set-output: DCC_DcuOutput bajo Compiled\\Dcu',
      r'<DCC_DcuOutput>.\Compiled\Dcu\$(Platform)\$(Config)</DCC_DcuOutput>' in _dproj, 'not written')
# injection through the folder name is refused (no XML metacharacters reach the file)
out = call('delphi_config', {"project": CON, "command": "set-output",
                             "output": 'x</DCC_ExeOutput><Import Project=' + chr(34) + 'evilshare' + chr(34) + '/>'})
check('set-output: inyeccion por el nombre de carpeta RECHAZADA', out.startswith('RECHAZADO'), out[:120])
check('set-output: el payload no se escribio en el .dproj',
      'evilshare' not in open(CON, encoding='utf-8-sig').read(), 'injected!')
# absolute path refused
out = call('delphi_config', {"project": CON, "command": "set-output", "output": r"C:\Temp\out"})
check('set-output: ruta absoluta RECHAZADA', out.startswith('RECHAZADO'), out[:120])
# restore to the RAD Studio default layout
out = call('delphi_config', {"project": CON, "command": "set-output", "output": "default"})
check('set-output: restaurar default',
      r'<DCC_ExeOutput>.\$(Platform)\$(Config)</DCC_ExeOutput>' in open(CON, encoding='utf-8-sig').read(), out[:150])

# ---- delphi_config add-searchpath / remove-searchpath ----------------------
# Field 2026-08-21: a real FMX app built for Linux64 except ONE unit - the
# component's folder was in the IDE library path for Win/Android only. The
# .dproj had no DCC_UnitSearchPath and no Base_Linux64 groups at all.
_spdir = os.path.join(INSIDE, 'libs-extra')
os.makedirs(_spdir, exist_ok=True)
out = call('delphi_config', {"project": CON, "command": "add-searchpath",
                             "platform": "Linux64", "path": _spdir})
check('searchpath: anadido a Linux64', out.startswith('ANADIDO'), out[:160])
_x = open(CON, encoding='utf-8-sig').read()
check('searchpath: grupo DEFINER Base_Linux64 creado como el IDE',
      "('$(Platform)'=='Linux64' and '$(Base)'=='true') or '$(Base_Linux64)'!=''" in _x
      and '<Base_Linux64>true</Base_Linux64>' in _x, 'definer missing')
check('searchpath: DCC_UnitSearchPath (SINGULAR, el nombre real) en el grupo de valores',
      '<DCC_UnitSearchPath>' + _spdir + ';$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' in _x
      and 'DCC_UnitSearchPaths' not in _x, 'tag missing or misspelt')
out = call('delphi_config', {"project": CON, "command": "add-searchpath",
                             "platform": "Linux64", "path": _spdir})
check('searchpath: repetir = ya estaba, sin cambios', 'ya estaba' in out, out[:120])
_v = json.loads(call('delphi_config', {"project": CON}))
check('searchpath: view lo ensena por plataforma (ruta enmascarada srvX:)',
      any(e.lower().endswith('libs-extra') and e.lower().startswith('srv')
          for e in (_v.get('searchPaths') or {}).get('Linux64', [])), str(_v.get('searchPaths'))[:160])
out = call('delphi_config', {"project": CON, "command": "add-searchpath",
                             "platform": "Linux64", "path": os.path.join(INSIDE, 'no-existe-zz')})
check('searchpath: carpeta inexistente RECHAZADA', out.startswith('RECHAZADO') and 'no existe' in out, out[:140])
out = call('delphi_config', {"project": CON, "command": "add-searchpath",
                             "platform": "Linux64", "path": r'C:\Windows\System32'})
check('searchpath: fuera de la jaula RECHAZADO', out.startswith('RECHAZADO') and 'FUERA' in out, out[:140])
out = call('delphi_config', {"project": CON, "command": "add-searchpath",
                             "platform": "Linux64", "path": _spdir + '"><Import Project="evil"/>'})
check('searchpath: inyeccion XML por el path RECHAZADA', out.startswith('RECHAZADO'), out[:140])
check('searchpath: el payload no toco el .dproj', 'evil' not in open(CON, encoding='utf-8-sig').read(), 'injected!')
out = call('delphi_config', {"project": CON, "command": "add-searchpath",
                             "platform": "Commodore64", "path": _spdir})
check('searchpath: plataforma invalida RECHAZADA', out.startswith('RECHAZADO'), out[:120])
out = call('delphi_config', {"project": CON, "command": "remove-searchpath",
                             "platform": "Linux64", "path": _spdir})
check('searchpath: quitado', out.startswith('QUITADO'), out[:120])
check('searchpath: elemento eliminado del .dproj',
      'DCC_UnitSearchPath' not in open(CON, encoding='utf-8-sig').read(), 'still there')
out = call('delphi_config', {"project": CON, "command": "remove-searchpath",
                             "platform": "Linux64", "path": _spdir})
check('searchpath: quitar lo que no esta responde honesto', 'no esta' in out, out[:120])

# ---- delphi_config add-deployfile / remove-deployfile -----------------------
# Field 2026-08-22: a component's runtime library (OBR's libzbar.so on Linux)
# must travel with the binary - the IDE's Deployment Manager. CON has no
# .deployproj: the standard one must be generated first.
_dep = os.path.join(INSIDE, 'libs-extra', 'libfake.so')
with open(_dep, 'wb') as f:
    f.write(b'\x7fELF fake')
_deployproj = CON[:-6] + '.deployproj'
check('deployfile: CON no tiene manifiesto de despliegue al empezar', not os.path.exists(_deployproj), _deployproj)
out = call('delphi_config', {"project": CON, "command": "add-deployfile",
                             "platform": "Linux64", "path": _dep})
check('deployfile: anadido (manifiesto generado primero)', out.startswith('ANADIDO') and 'genero el estandar' in out, out[:200])
_x = open(_deployproj, encoding='utf-8-sig').read()
check('deployfile: entrada Debug y Release con la forma del IDE',
      _x.count('<DeployFile Include="' + _dep + '"') == 2 and '<DeployClass>File</DeployClass>' in _x
      and '<RemoteDir>ConfProj' + chr(92) + '</RemoteDir>' in _x and "'$(Config)'=='Release'" in _x, 'shape mismatch')
check('deployfile: el .dproj importa el manifiesto',
      '$(MSBuildProjectName).deployproj' in open(CON, encoding='utf-8-sig').read(), 'import line missing')
out = call('delphi_config', {"project": CON, "command": "add-deployfile",
                             "platform": "Linux64", "path": _dep})
check('deployfile: repetir = ya viaja, sin cambios', 'ya viaja' in out, out[:120])
_v = json.loads(call('delphi_config', {"project": CON}))
check('deployfile: view lo ensena por plataforma (una linea por fichero, junto al binario)',
      sum('libfake.so' in e for e in (_v.get('deployFiles') or {}).get('Linux64', [])) == 1
      and any('ConfProj ->' in e for e in (_v.get('deployFiles') or {}).get('Linux64', [])),
      str(_v.get('deployFiles'))[:160])
out = call('delphi_config', {"project": CON, "command": "add-deployfile",
                             "platform": "Android64", "path": _dep})
check('deployfile: .so en Android64 va a library/lib/arm64-v8a por defecto',
      'arm64-v8a' in out, out[:200])
out = call('delphi_config', {"project": CON, "command": "add-deployfile",
                             "platform": "Linux64", "path": os.path.join(INSIDE, 'libs-extra')})
check('deployfile: una carpeta RECHAZADA', out.startswith('RECHAZADO') and 'carpeta' in out, out[:120])
out = call('delphi_config', {"project": CON, "command": "add-deployfile",
                             "platform": "Linux64", "path": _dep + '.nope'})
check('deployfile: fichero inexistente RECHAZADO', out.startswith('RECHAZADO') and 'no existe' in out, out[:120])
out = call('delphi_config', {"project": CON, "command": "add-deployfile",
                             "platform": "Linux64", "path": r'C:\Windows\System32\kernel32.dll'})
check('deployfile: fuera de la jaula RECHAZADO', out.startswith('RECHAZADO') and 'FUERA' in out, out[:120])
out = call('delphi_config', {"project": CON, "command": "add-deployfile",
                             "platform": "Linux64", "path": _dep, "remotedir": '..' + chr(92) + '..' + chr(92) + 'etc' + chr(92)})
check('deployfile: remotedir con .. RECHAZADO', out.startswith('RECHAZADO') and 'remotedir' in out, out[:120])
out = call('delphi_config', {"project": CON, "command": "add-deployfile",
                             "platform": "", "path": _dep})
check('deployfile: sin plataforma RECHAZADO', out.startswith('RECHAZADO'), out[:120])
out = call('delphi_config', {"project": CON, "command": "remove-deployfile",
                             "platform": "Linux64", "path": _dep})
check('deployfile: quitado (2 entradas)', out.startswith('QUITADO') and '2 entradas' in out, out[:120])
_x = open(_deployproj, encoding='utf-8-sig').read()
check('deployfile: Linux64 limpio, Android64 intacto',
      ('libfake.so' in _x) and _x.count('<DeployFile Include="' + _dep + '"') == 2
      and "'$(Platform)'=='Android64'" in _x, 'unexpected manifest state')
out = call('delphi_config', {"project": CON, "command": "remove-deployfile",
                             "platform": "Linux64", "path": _dep})
check('deployfile: quitar lo que no esta responde honesto', 'no esta' in out, out[:120])

# ---- delphi_paserver: read subcommands ------------------------------------
out = call('delphi_paserver', {"command": "packages"})
pk = json.loads(out)
check('paserver: packages lista los instaladores',
      any('linux' in p.get('path', '').lower() for p in pk.get('packages', [])), out[:150])
out = call('delphi_paserver', {"command": "platforms"})
pf = json.loads(out)
check('paserver: platforms distingue local vs remoto',
      any(p['platform'] == 'Win64' and p['buildsLocally'] for p in pf.get('platforms', []))
      and any(not p['buildsLocally'] for p in pf.get('platforms', [])), out[:150])
out = call('delphi_paserver', {"command": "profiles"})
check('paserver: profiles responde', 'profiles' in out, out[:120])

# ---- delphi_move / delphi_delete with recoverable trash -------------------
mvsrc = os.path.join(INSIDE, 'Mover.pas')
open(mvsrc, 'wb').write(SRC.replace('Dentro', 'Mover').encode('cp1252'))
mvdst = os.path.join(INSIDE, 'movidos', 'Mover.pas')
out = call('delphi_move', {"path": mvsrc, "dest": mvdst})
check('move: aceptado y crea carpeta destino', 'MOVIDO' in out and os.path.exists(mvdst)
      and not os.path.exists(mvsrc), out[:120])
out = call('delphi_move', {"path": mvdst, "dest": os.path.join(OUTSIDE, 'x.pas')})
check('move: destino fuera de la jaula rechazado', 'FUERA de los workspaces' in out, out[:120])

out = call('delphi_delete', {"path": mvdst})
check('delete: mueve a papelera (no borrado duro)', 'BORRADO' in out and not os.path.exists(mvdst), out[:120])
import glob as _g2
trash = _g2.glob(os.path.join(INSIDE, '**', '__delphi-patch', '**', 'deleted', '*'), recursive=True)
check('delete: el fichero esta recuperable en la papelera', len(trash) > 0, trash)
# R5-A: restore from the trash via delphi_move (the path delete's message names)
if trash:
    rec = os.path.join(INSIDE, 'Recuperado.pas')
    out = call('delphi_move', {"path": trash[0], "dest": rec})
    check('R5-A: restaurar desde la papelera con delphi_move PERMITIDO',
          'MOVIDO' in out and os.path.exists(rec), out[:120])
    out = call('delphi_move', {"path": rec, "dest": os.path.join(INSIDE, '__delphi-patch', 'x.pas')})
    check('R5-A: meter ficheros DENTRO de la papelera a mano rechazado', 'RECHAZADO' in out, out[:120])
out = call('delphi_delete', {"path": os.path.join(OUTSIDE, 'Fuera.pas')})
check('delete: fuera de la jaula rechazado', 'FUERA de los workspaces' in out, out[:120])
out = call('delphi_delete', {"path": os.path.join(INSIDE, 'movidos', '__delphi-patch')})
check('delete: no se puede borrar la propia papelera', 'RECHAZADO' in out, out[:120])

# R6-B: the trash is hidden from delphi_list by default, but discoverable with
# includeTrash=true so a deleted file can be found and restored.
out = call('delphi_list', {"root": INSIDE, "pattern": "*.pas"})
check('R6-B: delphi_list normal NO muestra __delphi-patch',
      not any('__delphi-patch' in e.get('path', '') for e in json.loads(out).get('files', [])), out[:200])
out = call('delphi_list', {"root": INSIDE, "pattern": "*.pas", "includeTrash": True})
check('R6-B: delphi_list includeTrash=true SI muestra la papelera',
      any('__delphi-patch' in e.get('path', '') for e in json.loads(out).get('files', [])), out[:200])

# ---- an exception that escapes a tool is NOT content ----------------------
# delphi_read/vault_read/vault_search are exempt from drive masking so their
# payload keeps byte fidelity for anchors. But the dispatcher wraps any escaped
# exception as "Error executing tool: <msg>", and a Delphi I/O exception embeds
# the REAL absolute path - which the exemption used to let through unmasked
# (the exemption only cancelled on lower-case 'error').
import ctypes
LOCKED = os.path.join(INSIDE, 'Bloqueado.pas')
open(LOCKED, 'wb').write(SRC.replace('Dentro', 'Bloqueado').encode('cp1252'))
GENERIC_READ, OPEN_EXISTING = 0x80000000, 3
h = ctypes.windll.kernel32.CreateFileW(LOCKED, GENERIC_READ, 0, None,
                                       OPEN_EXISTING, 0, None)
check('fichero bloqueado para la prueba', h != -1, h)
if h != -1:
    try:
        out = call('delphi_read', {"path": LOCKED})
        # either it fails (the interesting case) or it read anyway; in BOTH
        # cases the real drive letter must not appear
        check('read de fichero bloqueado: la unidad real NO viaja',
              (DRIVE + ':\\') not in out, out[:200])
    finally:
        ctypes.windll.kernel32.CloseHandle(h)

# ...and the fence in the other direction: real CONTENT that merely starts
# with "Error" must stay verbatim (a case-insensitive test would mask it and
# silently break every anchored write built on that text).
ERRPAS = os.path.join(INSIDE, 'Error.txt')
open(ERRPAS, 'wb').write(('Error: algo fallo en ' + DRIVE + ':\\carpeta\\f.txt\r\n').encode('cp1252'))
out = call('delphi_read', {"path": ERRPAS})
check('read: contenido que empieza por "Error" sigue verbatim',
      (DRIVE + ':\\carpeta\\f.txt') in out and 'srv' + DRIVE.lower() not in out, out[:200])

# ---- argument types: a wrong value is an ERROR, never a silent default ----
# 'abc' used to become 0 (StrToIntDef) and any boolean but "true" became False:
# the agent believed it had filtered and had not.
out = call('delphi_read', {"path": IN_PAS, "fromline": "abc"})
check('tipos: fromline no numerico rechazado con el nombre del parametro',
      'fromline' in out.lower() and 'whole number' in out, out[:200])
out = call('delphi_list', {"root": INSIDE, "dirs": "quiza"})
check('tipos: booleano invalido rechazado',
      'true or false' in out, out[:200])
# ...but what parses cleanly is still accepted (clients that send text)
out = call('delphi_read', {"path": IN_PAS, "fromline": "2", "toline": "4"})
check('tipos: numero en texto ("2") sigue valiendo',
      'RECHAZADO' not in out and 'Error executing tool' not in out, out[:200])
out = call('delphi_list', {"root": INSIDE, "dirs": "TRUE"})
check('tipos: booleano en texto ("TRUE") sigue valiendo',
      '"dirs"' in out and 'Error executing tool' not in out, out[:150])
# JSON null means "not provided", never the string 'null' nor 0
out = call('delphi_read', {"path": IN_PAS, "fromline": None})
check('tipos: null se trata como ausente (no como 0 ni "null")',
      'unit Dentro' in out, out[:150])

# ---- delphi_report: the only write a read-only client may do, now bounded -
out = call('delphi_report', {"kind": "bug", "title": "cap", "message": "x" * (300 * 1024)})
check('report: un reporte gigante se rechaza',
      'RECHAZADO' in out and 'KB' in out, out[:200])
out = call('delphi_report', {"kind": "bug", "title": "cap-ok", "message": "prueba de la bateria"})
check('report: un reporte normal sigue pasando', out.startswith('GRACIAS'), out[:150])

# ---- unserved virtual units: no drive enumeration (field round 10) -------
# "srvz:" used to expand to the REAL "Z:\", so the rejection echoed a drive of
# the host - and the outbound mask covers SERVED letters only, so it came back
# raw. Probing srva: .. srvz: told the client which drives the machine has.
FREE = [c for c in 'zyxwvuts' if not os.path.exists(c + ':\\')]
check('prueba viable: quedan letras sin unidad real', len(FREE) >= 2, FREE)
GHOST = FREE[0] if FREE else None
if GHOST:
    GV = 'srv' + GHOST + ':\\secreto\\x.pas'
    REAL = re.compile(r'(?<!srv)' + GHOST + r':\\', re.I)  # the real form only
    for tool, args in (('delphi_read', {"path": GV}),
                       ('delphi_edit', {"path": GV, "old": "a", "new": "b"}),
                       # delphi_list with dirs=true was the exact vector of the
                       # field report - the parameter is 'root', not 'path'
                       ('delphi_list', {"root": GV, "dirs": True})):
        out = call(tool, args)
        check(tool + ': unidad no servida rechazada por nombre',
              'no es una unidad de este servidor' in out, out)
        check(tool + ': la letra real NO viaja de vuelta',
              REAL.search(out) is None, out)
    # rule 4: a rejection always names the legitimate way in
    out = call('delphi_read', {"path": GV})
    check('unidad no servida: el rechazo ofrece las unidades validas',
          'srv' + DRIVE.lower() + ':' in out, out)
    # and a SERVED unit keeps working (the fix must not close the door)
    out = call('delphi_read', {"path": V_PAS})
    check('unidad servida: sigue resolviendo (sin falso positivo)',
          'unit Dentro' in out, out)

# ---- shutdown main server --------------------------------------------------
proc.stdin.close()
proc.wait(timeout=15)

# ---- Roots con comillas / roots invalidos (servidores propios) -------------
def one_shot(envroots, tool, args, extra_env=None):
    global proc, q
    proc, q = start(envroots, extra_env)
    handshake()
    out = call(tool, args)
    proc.stdin.close()
    proc.wait(timeout=15)
    return out


QDIR = os.path.join(BASE, 'con espacios en nombre')
os.makedirs(QDIR, exist_ok=True)
open(os.path.join(QDIR, 'X.pas'), 'wb').write(SRC.replace('Dentro', 'X').encode('cp1252'))

out = one_shot('"' + QDIR + '"', 'delphi_read', {"path": os.path.join(QDIR, 'X.pas')})
check('roots entrecomillados + espacios: jaula funcional', 'unit X;' in out, out)

out = one_shot('C:\\<invalido>|malo', 'delphi_read', {"path": os.path.join(QDIR, 'X.pas')})
check('roots invalidos: fallo CERRADO (todo rechazado)',
      'ninguna de sus rutas es valida' in out, out)

# ---- the vault is a served root of its OWN ------------------------------
# subst gives a drive that is neither workspace root nor library zone, so the
# only thing that can make it served is the vault itself.
VDRV = FREE[1] if len(FREE) > 1 else None
if VDRV:
    VROOT = os.path.join(BASE, 'vault-en-otra-unidad')
    os.makedirs(VROOT, exist_ok=True)
    subst = subprocess.run('subst %s: "%s"' % (VDRV, VROOT), shell=True,
                           capture_output=True)
    if subst.returncode == 0:
        try:
            out = one_shot(INSIDE, 'delphi_read',
                           {"path": 'srv' + VDRV + ':\\nota.md'},
                           {'DELPHI_MCP_VAULT_PATH': VDRV + ':\\'})
            check('vault en otra unidad: su letra ES una unidad servida',
                  'no es una unidad de este servidor' not in out, out)
            check('vault en otra unidad: la letra real no viaja',
                  re.search(r'(?<!srv)' + VDRV + r':\\', out, re.I) is None, out)
        finally:
            subprocess.run('subst %s: /d' % VDRV, shell=True, capture_output=True)
    else:
        print('SKIP - subst no disponible, no se prueba el vault en otra unidad')

print()
print(f'RESULT: {P} passed, {F} failed')
sys.exit(1 if F else 0)
