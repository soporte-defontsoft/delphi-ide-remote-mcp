# -*- coding: utf-8 -*-
"""Un ajuste de si/no se lee con UNA gramatica (V110 de la 1.23.1).

El ReadBool de la RTL (System.IniFiles: ReadInteger + StrToIntDef) leia 'true'
y 'false' escritos con letras como el DEFECTO: [CORS] Enabled=false dejaba CORS
encendido. Las variables de entorno se leian con '= 1' o '<> 0':
DELPHI_MCP_LIBRARY_ZONE=false dejaba la zona de biblioteca encendida. Ahora UNA
gramatica (Lsp.Settings.LeeSiNo): 1/0, true/false, yes/no, on/off; lo demas, el
valor CERRADO y una nota al arrancar (David: "cerrado y nunca callado").

  S1  [CORS] Enabled=false: la respuesta no lleva cabeceras CORS (ROJO contra la
      build anterior: las llevaba)
  S2  (control) [CORS] Enabled=true: las lleva
  S3  [CORS] Enabled=quizas: el lado cerrado y el log de arranque lo dice. El de
      CORS es ENCENDIDO: apagado no valida el Origin (V161 de la 1.23.1; aqui
      decia apagado, y V161 cambio el lector sin esta bateria)
  S4  DELPHI_MCP_LIBRARY_ZONE=false: delphi_workspace sin la zona de biblioteca
      (ROJO: la daba)
  S5  (control) sin la variable, la zona esta (su defecto)

Usage:  python tests/test_si_no_1231.py [path-to-DelphiLspMcp.exe]
"""
import os, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('si_no_1231')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
TOKEN = 'bateria-si-no'
CAT = mc.catalogo()
INIT = {"jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {"protocolVersion": mc.PROTOCOLO, "capabilities": {},
                   "clientInfo": {"name": "si-no", "version": "1"}}}


def con_cors(valor, n):
    """Un servidor HTTP con [CORS] Enabled=<valor>: (la cabecera CORS de su
    respuesta a una peticion con Origin, su log de arranque)."""
    d = os.path.join(BASE, 'cors-%d' % n)
    exe = mc.copia_exe(d)
    with open(os.path.join(d, 'settings.ini'), 'w') as f:
        f.write('[CORS]\nEnabled=%s\n\n[Workspace.Bateria]\nToken=%s\nRoots=%s\n' % (valor, TOKEN, JAIL))
    puerto = mc.puerto_libre()
    ruta = os.path.join(d, 'salida.log')
    salida = open(ruta, 'wb')
    try:
        proc = mc.lanza_http(exe, puerto, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'}),
                             stdout=salida, stderr=subprocess.STDOUT)
        try:
            # un origen PERMITIDO por los de fabrica (localhost): uno que no lo
            # esta recibe 403 sin cabeceras CORS, y S1 pasaba por ESO contra la
            # build anterior (medido con una sonda)
            st, h, raw = mc.post('http://127.0.0.1:%d/mcp' % puerto, INIT, TOKEN,
                                 cabeceras={'Origin': 'http://localhost'})
            cab = h.get('Access-Control-Allow-Origin') if h else None
        finally:
            proc.kill()
    finally:
        salida.close()
    return cab, open(ruta, 'rb').read().decode('utf-8', 'replace')


def zona(extra):
    """Si delphi_workspace de un stdio con ese entorno ensena la zona de biblioteca."""
    srv = mc.Stdio(mc.copia_exe(os.path.join(BASE, 'zona-%d' % len(extra))),
                   mc.entorno(dict({'DELPHI_MCP_ROOTS': JAIL}, **extra)), nombre='si-no')
    try:
        ws = mc.como_json(srv.call('delphi_workspace', {}))
    finally:
        srv.cierra()
    return bool(ws.get('readableExtra')), ws


cab, log = con_cors('false', 1)
check('S1 [CORS] Enabled=false: sin cabeceras CORS', cab is None, cab)
cab, log = con_cors('true', 2)
check('S2 (control) [CORS] Enabled=true: con ellas', cab == 'http://localhost', cab)
cab, log = con_cors('quizas', 3)
nota = CAT['SL_GUARD_SINO_ILEGIBLE_FMT'] % ('[CORS] Enabled', 'quizas', '1')
check('S3 [CORS] Enabled=quizas: el lado cerrado (CORS encendido, valida el Origin) y el log de arranque lo dice',
      cab == 'http://localhost' and nota in log, (cab, log[-600:]))
hay, ws = zona({'DELPHI_MCP_LIBRARY_ZONE': 'false'})
check('S4 DELPHI_MCP_LIBRARY_ZONE=false: delphi_workspace sin la zona de biblioteca', not hay,
      str(ws)[:300])
hay, ws = zona({})
check('S5 (control) sin la variable, la zona esta (su defecto)', hay, str(ws)[:300])

mc.fin('si/no 1.23.1 (V110)')
