# -*- coding: utf-8 -*-
"""El RESULTADO de un rechazo lo declara su etiqueta (catalogo de mensajes,
27-sep-2026), y un rechazo es un error para el cliente: isError y un code
en structuredContent. Hasta ese dia, lo que no empezaba por RECHAZADO ni por
error: salia con ok:true aunque la tool no hubiera hecho nada - "Falta
path" en delphi_config y delphi_styles, una plataforma que no existe en
delphi_components. David: "Arreglarlos".

  E1  delphi_styles sin path                      -> INVALID_PARAM (STYLE-030)
  E2  delphi_styles get sin style                 -> INVALID_PARAM (STYLE-031)
  E3  delphi_config add-unit sin path             -> INVALID_PARAM (CFG-098)
  E4  delphi_config add-searchpath sin path       -> INVALID_PARAM (CFG-095)
  E5  delphi_components con plataforma inventada  -> INVALID_PARAM (COMP-008)
  E6  y un exito sigue siendo exito (delphi_styles view de un .style bueno)
  E7  un puerto ocupado dice CUAL y que hacer (issue #5: Indy solo decia
      "Could not bind socket." y el operador de la bandeja no sabia mas)
  E8  delphi_read devuelve el fichero TAL CUAL aunque traiga etiquetas con
      resultado: una linea con [CFG-001 DENIED] hacia que la lectura se
      tomara por una negativa y se enmascarara el contenido ('%s:' salia
      '%srv0:', medido 27-sep leyendo Lsp.Texts)

Usage:  python tests/test_resultados.py [path-to-DelphiLspMcp.exe]
"""
import json
import os
import subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('resultados')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(EXEDIR)

ESTILO = os.path.join(JAIL, 'Claro.style')
open(ESTILO, 'w').write('object TStyleContainer\n'
                        '  object TLayout\n'
                        '    StyleName = \'boton\'\n'
                        '  end\n'
                        'end\n')
ECO = os.path.join(JAIL, 'eco.txt')
open(ECO, 'w').write('uno [CFG-001 DENIED]\n'
                     "  '%s (%s) lineas %d-%d de %s:'#10 +\n"
                     'Roots=D:\\Projects\\Galatea\n')
DPROJ = os.path.join(JAIL, 'App.dproj')
open(DPROJ, 'w').write('<?xml version="1.0" encoding="utf-8"?>\n'
                       '<Project><PropertyGroup><MainSource>App.dpr</MainSource>'
                       '</PropertyGroup></Project>\n')

TOK = 'res'
PORT = mc.puerto_libre()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.Res]',
    'Token=%s' % TOK,
    'Roots=%s' % JAIL,
    '',
]))

proc = mc.lanza_http(EXE, PORT, mc.entorno())
cli = mc.Http(PORT, TOK, t=180, respaldo_json=True)
cli.session('resultados')


def rechazo(nombre, tool, args, code, msg_id):
    r = cli.call_msg(tool, args)
    res = (r or {}).get('result', {})
    sc = res.get('structuredContent', {})
    t = mc.texto(r, True)
    check(nombre, res.get('isError') is True and sc.get('ok') is False and sc.get('code') == code
          and mc.tiene(t, msg_id), '%s | %s' % (json.dumps(sc)[:160], t[:160]))


try:
    rechazo('E1 delphi_styles sin path es un error INVALID_PARAM',
            'delphi_styles', {'command': 'view'}, 'INVALID_PARAM', 'STYLE-030')
    rechazo('E2 delphi_styles get sin style es un error INVALID_PARAM',
            'delphi_styles', {'command': 'get', 'path': ESTILO}, 'INVALID_PARAM', 'STYLE-031')
    rechazo('E3 delphi_config add-unit sin path es un error INVALID_PARAM',
            'delphi_config', {'command': 'add-unit', 'project': DPROJ}, 'INVALID_PARAM', 'CFG-098')
    rechazo('E4 delphi_config add-searchpath sin path es un error INVALID_PARAM',
            'delphi_config', {'command': 'add-searchpath', 'project': DPROJ}, 'INVALID_PARAM', 'CFG-095')
    rechazo('E5 delphi_components con una plataforma inventada es un error INVALID_PARAM',
            'delphi_components', {'platform': 'Amiga500'}, 'INVALID_PARAM', 'COMP-008')

    r = cli.call_msg('delphi_styles', {'command': 'view', 'path': ESTILO})
    res = (r or {}).get('result', {})
    check('E6 y un exito sigue siendo exito', not res.get('isError') and
          res.get('structuredContent', {}).get('ok') is not False, mc.texto(r, True)[:200])

    t = mc.texto(cli.call_msg('delphi_read', {'path': ECO}), True)
    check('E8 delphi_read devuelve el contenido tal cual aunque cite etiquetas con resultado',
          "de %s:'#10" in t and 'Roots=D:\\Projects\\Galatea' in t and 'srv0' not in t, t[-300:])

    # un segundo servidor al MISMO puerto que el que ya escucha
    b = subprocess.run([EXE, '--http', str(PORT)], cwd=EXEDIR, capture_output=True, timeout=60,
                       env=mc.entorno())
    err = b.stderr.decode('utf-8', 'replace')
    check('E7 un puerto ocupado dice cual, por que y que hacer (issue #5)',
          b.returncode != 0 and ('port %d' % PORT) in err and 'already in use' in err and
          'Port=' in err, err[-400:])
finally:
    try:
        proc.kill()
    except Exception:
        pass

mc.fin('test_resultados')
