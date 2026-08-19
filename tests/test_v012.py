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
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Win64', 'Debug', 'DelphiLspMcp.exe')

BASE = os.path.join(tempfile.gettempdir(), 'delphi-v012-tests')
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


def start(envroots):
    env = dict(os.environ)
    env['DELPHI_MCP_ROOTS'] = envroots
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
CON = os.path.join(INSIDE, 'ConfProj.dproj')
_sh.copy(os.path.join(REPO, 'src', 'DelphiLspMcp.dproj'), CON)   # console (FrameworkType None)
VCLP = os.path.join(INSIDE, 'VclProj.dproj')
_sh.copy(os.path.join(REPO, 'src', 'DelphiLspMcpTray.dproj'), VCLP)  # VCL

out = call('delphi_config', {"project": CON})
cfg = json.loads(out)
check('config: view lista configuraciones', 'Debug' in cfg.get('configurations', []), out[:150])
check('config: view lista plataformas con estado',
      any(p.get('name') == 'Win64' for p in cfg.get('platforms', [])), out[:150])

out = call('delphi_config', {"project": VCLP, "command": "add-platform", "platform": "Linux64"})
check('config: add-platform Linux64 en VCL RECHAZADO (regla VCL!=FMX)',
      'RECHAZADO' in out and 'VCL' in out, out[:150])
out = call('delphi_config', {"project": CON, "command": "add-platform", "platform": "Linux64"})
check('config: add-platform Linux64 en consola aceptado', 'ANADIDA' in out, out[:150])

# R5-B: platform name is whitelisted - XML injection into the .dproj refused
inj = 'Win64"/><Import Project=' + chr(34) + 'evilshare' + chr(34) + '/><X y='
out = call('delphi_config', {"project": CON, "command": "add-platform", "platform": inj})
check('R5-B: inyeccion XML por el nombre de plataforma RECHAZADA',
      'RECHAZADO' in out and 'no es una plataforma' in out, out[:150])
check('R5-B: el payload no se escribio en el .dproj',
      'evilshare' not in open(CON, encoding='utf-8-sig').read(), 'injected!')
out = call('delphi_config', {"project": CON, "command": "add-platform", "platform": "NoExiste99"})
check('R5-B: plataforma inventada RECHAZADA', 'RECHAZADO' in out, out[:120])
# R5-C: remove-platform (with backup)
out = call('delphi_config', {"project": CON, "command": "remove-platform", "platform": "Linux64"})
check('R5-C: remove-platform deshabilita', 'DESHABILITADA' in out, out[:120])
out = call('delphi_config', {"project": CON})
check('config: Linux64 ahora habilitada',
      any(p.get('name') == 'Linux64' and p.get('enabled') for p in json.loads(out).get('platforms', [])), out[:150])

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

# ---- shutdown main server --------------------------------------------------
proc.stdin.close()
proc.wait(timeout=15)

# ---- Roots con comillas / roots invalidos (servidores propios) -------------
def one_shot(envroots, tool, args):
    global proc, q
    proc, q = start(envroots)
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

print()
print(f'RESULT: {P} passed, {F} failed')
sys.exit(1 if F else 0)
