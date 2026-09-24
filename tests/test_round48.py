# -*- coding: utf-8 -*-
"""Round 48: la tercera medida que la 1.0.13 dejo a deber - la clave de la
cache de ajustes entre workspaces SOLAPADOS.

Un servidor, dos tokens: "ancho" (Roots = el proyecto) y "estrecho" (Roots =
una subcarpeta suya). El .dproj vive ENCIMA de la jaula del estrecho, asi que
para el esa unit va sin configurar. Con la clave vieja (solo el directorio) el
primero que resolvia la carpeta fijaba SU respuesta para todos: tras una
llamada del ancho, delphi_definition le devolvia al estrecho una ruta de
FUERA de su jaula (medido contra el exe de la 1.0.12 el 2026-09-21).

EL INVARIANTE: lo que contesta un token no depende de quien llamo antes.
Se mide dos veces en servidores recien nacidos - el estrecho solo, y el
estrecho tras el ancho - y las dos respuestas tienen que ser identicas.

Si esta release-out/DelphiLspMcp-v1.0.12-beta-win64.zip se pasa ademas el
CONTROL: ese exe TIENE que fallar el invariante. Una bateria que no ve el
fallo en el binario que lo tiene no esta midiendo nada.
"""
import json, os, shutil, socket, subprocess, sys, tempfile, time, urllib.request, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
NUEVO = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Server', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
ZIP12 = os.path.join(REPO, 'release-out', 'DelphiLspMcp-v1.0.12-beta-win64.zip')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round48')
PROY = os.path.join(BASE, 'jaula', 'proy')
SUB = os.path.join(PROY, 'sub')

P = F = 0


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:300])

def borra(d):
    if os.path.isdir(d):
        shutil.rmtree(d, ignore_errors=True)

class Srv:
    def __init__(self, exe, nombre, workspaces):
        self.dir = os.path.join(BASE, 'srv_' + nombre)
        borra(self.dir); os.makedirs(self.dir)
        shutil.copy(exe, os.path.join(self.dir, 'DelphiLspMcp.exe'))
        sk = socket.socket(); sk.bind(('127.0.0.1', 0)); self.port = sk.getsockname()[1]; sk.close()
        ini = ['[Server]', 'BindIP=127.0.0.1', '']
        for tok, roots in workspaces:
            ini += ['[Workspace.%s]' % tok.upper(), 'Token=%s' % tok, 'Roots=%s' % roots, '']
        open(os.path.join(self.dir, 'settings.ini'), 'w').write('\n'.join(ini))
        self.proc = subprocess.Popen([os.path.join(self.dir, 'DelphiLspMcp.exe'), '--http', str(self.port)],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(3)
        self.sids = {}; self.rid = 100
    def rpc(self, tok, body):
        h = {'Content-Type': 'application/json', 'Accept': 'application/json, text/event-stream',
             'Authorization': 'Bearer ' + tok}
        if self.sids.get(tok): h['Mcp-Session-Id'] = self.sids[tok]
        r = urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:%d/mcp' % self.port,
            data=json.dumps(body).encode(), headers=h, method='POST'), timeout=300)
        raw = r.read().decode('utf-8', 'replace')
        sid = r.headers.get('Mcp-Session-Id')
        if sid: self.sids[tok] = sid
        for l in raw.splitlines():
            if l.startswith('data:'):
                m = json.loads(l[5:].strip())
                if 'result' in m or 'error' in m: return m
        try: return json.loads(raw)
        except Exception: return None
    def call(self, tok, tool, args):
        if tok not in self.sids:
            self.rpc(tok, {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {
                'protocolVersion': '2025-06-18', 'capabilities': {}, 'clientInfo': {'name': tok, 'version': '1'}}})
            self.rpc(tok, {'jsonrpc': '2.0', 'method': 'notifications/initialized'})
        self.rid += 1
        r = self.rpc(tok, {'jsonrpc': '2.0', 'id': self.rid, 'method': 'tools/call',
                           'params': {'name': tool, 'arguments': args}})
        try: return r['result']['content'][0]['text']
        except Exception: return json.dumps(r)[:600]
    def para(self):
        try: self.proc.kill()
        except Exception: pass
        time.sleep(1.5)

BASEPAS = """unit Base;

interface

function Doble(X: Integer): Integer;

implementation

function Doble(X: Integer): Integer;
begin
  Result := X * 2;
end;

end.
"""
HOJA = """unit Hoja;

interface

function Cuatro: Integer;

implementation

uses
  Base;

function Cuatro: Integer;
begin
  Result := Doble(2);
end;

end.
"""
LH = HOJA.split('\n')
LIN = [i for i, x in enumerate(LH) if 'Doble(2)' in x][0]
COL = LH[LIN].index('Doble') + 1

def prepara():
    borra(BASE); os.makedirs(os.path.join(BASE, 'jaula'))
    s = Srv(NUEVO, 'setup', [('setup', os.path.join(BASE, 'jaula'))])
    try:
        c1 = (s.call('setup', 'delphi_create', {'kind': 'project-console', 'name': 'P', 'dir': PROY})[:160])
        dpr = os.path.join(PROY, 'P.dpr')
        c2 = (s.call('setup', 'delphi_create', {'kind': 'unit', 'name': 'Base', 'project': dpr, 'content': BASEPAS.replace('\n', '\r\n')})[:160])
        c3 = (s.call('setup', 'delphi_create', {'kind': 'unit', 'name': 'Hoja', 'project': dpr, 'dir': 'sub', 'content': HOJA.replace('\n', '\r\n')})[:160])
        check('M0 el escenario se monta por el propio MCP (proyecto + unit + unit en subcarpeta)',
              c1.startswith('CREADO') and c2.startswith('CREADA') and c3.startswith('CREADA'), c1 + c2 + c3)
    finally:
        s.para()

def mide(exe, etiqueta):
    hoja = os.path.join(SUB, 'Hoja.pas')
    ws = [('ancho', PROY), ('estrecho', SUB)]
    out = {}
    for orden in ('solo', 'tras-ancho'):
        s = Srv(exe, etiqueta + '_' + orden, ws)
        try:
            if orden == 'tras-ancho':
                s.call('ancho', 'delphi_references', {'path': hoja, 'line': LIN, 'character': COL})
            d = s.call('estrecho', 'delphi_definition', {'path': hoja, 'line': LIN, 'character': COL})
            r = s.call('estrecho', 'delphi_references', {'path': hoja, 'line': LIN, 'character': COL})
            out[orden] = (d, r)
        finally:
            s.para()
    igual = out['solo'] == out['tras-ancho']
    return igual, out

try:
    prepara()
    igual, out = mide(NUEVO, 'actual')
    d, r = out['tras-ancho']
    check('K1 lo que contesta el estrecho NO depende de que el ancho llamase antes',
          igual, 'solo=%s | tras-ancho=%s' % (out['solo'][0][:120], d[:120]))
    check('K2 ...y su delphi_definition no nombra nada de fuera de su jaula',
          'base.pas' not in d.lower(), d[:240])
    check('K3 ...ni delphi_references le habla de una definicion de FUERA',
          'FUERA de este workspace' not in r, r[:240])
    if os.path.exists(ZIP12):
        z = os.path.join(BASE, 'v12')
        os.makedirs(z)
        with zipfile.ZipFile(ZIP12) as f:
            n = [x for x in f.namelist() if x.lower().endswith('delphilspmcp.exe')][0]
            f.extract(n, z)
        igual12, out12 = mide(os.path.join(z, n), 'v1012')
        check('K0 CONTROL: el exe de la 1.0.12 SI falla el invariante (la bateria ve el fallo)',
              not igual12 and 'base.pas' in out12['tras-ancho'][0].lower(),
              out12['tras-ancho'][0][:240])
    else:
        print('NOTA: sin release-out/...v1.0.12...zip no se pasa el control.')
finally:
    borra(BASE)

print('== test_round48: %d OK | %d fallos ==' % (P, F))
sys.exit(1 if F else 0)
