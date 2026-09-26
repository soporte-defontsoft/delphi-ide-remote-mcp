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
import json, os, time, zipfile
import mcp_cliente as mc
from mcp_cliente import check

NUEVO = mc.exe_origen()
ZIP12 = os.path.join(mc.REPO, 'release-out', 'DelphiLspMcp-v1.0.12-beta-win64.zip')
# sin mc.carpeta(): la barre prepara(), que es quien monta el escenario
BASE = os.path.join(mc.RAIZ, 'round48')
PROY = os.path.join(BASE, 'jaula', 'proy')
SUB = os.path.join(PROY, 'sub')


class Srv:
    def __init__(self, exe, nombre, workspaces):
        self.dir = os.path.join(BASE, 'srv_' + nombre)
        mc.borra(self.dir)
        copia = mc.copia_exe(self.dir, exe)
        self.port = mc.puerto_libre()
        ini = ['[Server]', 'BindIP=127.0.0.1', '']
        for tok, roots in workspaces:
            ini += ['[Workspace.%s]' % tok.upper(), 'Token=%s' % tok, 'Roots=%s' % roots, '']
        open(os.path.join(self.dir, 'settings.ini'), 'w').write('\n'.join(ini))
        self.proc = mc.lanza_http(copia, self.port, mc.entorno())
        self.cli = {}; self.rid = 100
    def call(self, tok, tool, args):
        c = self.cli.get(tok)
        if c is None:
            c = self.cli[tok] = mc.Http(self.port, tok, t=300)
            c.session(tok)
        # un contador de ids POR SERVIDOR, como antes: un fallo devuelve el
        # mensaje entero (con su id), y en K1 dos fallos no salen iguales
        c.rid, self.rid = self.rid, self.rid + 1
        r = c.call_msg(tool, args)
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
    mc.borra(BASE); os.makedirs(os.path.join(BASE, 'jaula'))
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
          # Doble solo vive en Base.pas, FUERA de su jaula: la unica respuesta
          # buena es "sin resolver" (null), y sin nombrar Base.pas
          d.startswith('null') and 'base.pas' not in d.lower(), d[:240])
    check('K3 ...ni delphi_references le habla de una definicion de FUERA',
          'no resuelve "Doble"' in r and 'FUERA de este workspace' not in r, r[:240])
    # K3b: esa negativa es del LLAMANTE y viaja como tal. Hasta el 26-sep salia
    # como 'Error executing tool: RECHAZADO...' (se lanzaba como excepcion y el
    # despachador la vestia de fallo interno): lo destapo K3 al endurecerlo.
    check('K3b ...y esa negativa llega como RECHAZADO, no como fallo interno del servidor',
          r.startswith('RECHAZADO') and not r.startswith('Error executing tool'), r[:240])
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
    mc.borra(BASE)

mc.fin('test_round48')
