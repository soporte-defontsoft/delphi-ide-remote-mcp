# -*- coding: utf-8 -*-
"""DSGN-061 de la 1.20 (Hermes, 12-oct): lo que el LECTOR del IDE no carga de
un form llegaba mal por dos caminos. Un valor de una propiedad que la clase
guarda POR CODIGO (FontColor = -65536 en un TEdit FMX: la tabla no sabe su
tipo) entraba por delphi_edit sin aviso, el lint decia CLEAN y preview
contestaba DSGN-061 INTERNAL. Y un entero que no cabe en una publicada
(TextSettings.FontColor = $FF00A152) lo saltaba el Ignore del renderizador sin
consumirlo, y preview solo decia "Stream read error". Medido en produccion el
16-oct (1.19.3 + ffa2dd1). Ahora preview dice DSGN-153 con lo que dijo el
lector y su linea, y cuando la tabla calla se le pregunta al lector en el lint
(CLEAN solo si carga), tras delphi_edit y el changeset (EDIT-127) y en upload.

  L1 delphi_edit escribe FontColor = -65536: EDIT-127 con su linea y lo que
     dijo el lector (ROJO en produccion: ni una palabra)
  L2 lint de ese form: no CLEAN, el lector con su linea (ROJO: LINT CLEAN)
  L3 preview: DSGN-153, no DSGN-061, con 'Error reading Edit1.FontColor' y su
     linea (ROJO: DSGN-061 INTERNAL)
  L4 TextSettings.FontColor = $FF00A152: preview DSGN-153 con la CAUSA
     (Edit1.TextSettings.FontColor), no solo "Stream read error" (ROJO)
  L5 un changeset que escribe FontColor = -65536: EDIT-127 en sus avisos (ROJO)
  L6 upload de un form entero con FontColor = -65536: "designer" con EDIT-127
     (ROJO: ok y nada mas)
  L7 upload a trozos: el primero (a medias, sin sha256) no se juzga; el
     ultimo, con sha256, si
  L8 el control: un form sano con lineas que la clase guarda por codigo
     (DesignerMasterStyle, la raiz juzgada por su .pas): lint CLEAN y
     delphi_edit sin EDIT-127
  L9 una clase de terceros que no esta (el ayudante la sustituye): lo que el
     lector se salta de ELLA no es un aviso del lector (es la nota DSGN-039)

Uso:  python tests/test_lector_puertas_120.py [ruta-a-DelphiLspMcp.exe]
"""
import base64
import hashlib
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('lector_puertas_120')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)

FMX = ("object FormC: TFormC\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'C'\r\n  ClientHeight = 480\r\n"
       "  ClientWidth = 640\r\n  FormFactor.Width = 320\r\n  FormFactor.Height = 480\r\n"
       "  FormFactor.Devices = [Desktop]\r\n  DesignerMasterStyle = 0\r\n{otro}"
       "  object Edit1: TEdit\r\n    Position.X = 10.000000000000000000\r\n"
       "    Position.Y = 10.000000000000000000\r\n    TabOrder = 0\r\n{dentro}  end\r\nend\r\n")
TERCEROS = "  object X1: TComponenteQueNoExiste1201\r\n    Foo = 1\r\n  end\r\n"
PAS = ("unit {u};\r\n\r\ninterface\r\n\r\nuses\r\n  System.SysUtils, System.Types, System.UITypes, "
       "System.Classes, System.Variants,\r\n  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, "
       "FMX.Edit;\r\n\r\ntype\r\n  TFormC = class(TForm)\r\n    Edit1: TEdit;\r\n  end;\r\n\r\nvar\r\n"
       "  FormC: TFormC;\r\n\r\nimplementation\r\n\r\n{{$R *.fmx}}\r\n\r\nend.\r\n")


def texto(dentro='', otro=''):
    return FMX.replace('{otro}', otro).replace('{dentro}', dentro)


def form(nombre, dentro='', otro=''):
    p = os.path.join(JAIL, nombre + '.fmx')
    open(p, 'wb').write(b'\xef\xbb\xbf' + texto(dentro, otro).encode('utf-8'))
    open(os.path.join(JAIL, nombre + '.pas'), 'wb').write(PAS.replace('{u}', nombre).encode('utf-8'))
    return p


def linea_de(p, trozo):
    """La linea (1-based) del form en disco que contiene trozo."""
    for i, l in enumerate(open(p, 'rb').read().decode('utf-8-sig').split('\r\n')):
        if trozo in l:
            return i + 1
    return 0


MALO = '    FontColor = -65536'
LECTOR = 'Error reading Edit1.FontColor: Invalid property value'

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='lector-puertas', t=240)
try:
    # la auditoria de una edicion no espera a las tablas: tienen que estar
    for fw, r in mc.espera_tablas(srv.call):
        check('L0 la tabla %s esta lista' % fw, not mc.tiene(r, 'DSGN-051') and not mc.fallo(r), r[:200])

    p = form('UL1')
    r = srv.call('delphi_edit', {'path': p, 'old': '    TabOrder = 0', 'new': '    TabOrder = 0\r\n' + MALO}, t=240)
    n = linea_de(p, 'FontColor = -65536')
    check('L1 delphi_edit escribe FontColor = -65536: EDIT-127 con su linea (%d) y lo que dijo el lector' % n,
          not mc.rechazado(r) and mc.es(r, 'SN_EDIT_AVISO_LECTOR_FMT') and ('line %d:' % n) in r and LECTOR in r,
          r[-700:])

    r = srv.call('delphi_designer', {'path': p, 'command': 'lint'}, t=240)
    check('L2 lint de ese form: no CLEAN, el lector con su linea',
          not mc.tiene(r, 'DSGN-020') and mc.tiene(r, 'DSGN-038') and ('line %d:' % n) in r and LECTOR in r,
          r[:600])

    r = srv.call('delphi_designer', {'path': p, 'command': 'preview', 'maxwidth': 200}, t=240)
    check('L3 preview: DSGN-153 (el fichero), no DSGN-061 INTERNAL, con lo que dijo el lector y su linea',
          mc.abre(r, 'SR_DESIGNER_NO_CARGA_FMT') and not mc.tiene(r, 'DSGN-061') and LECTOR in r
          and ('line %d:' % n) in r, r[:600])

    p = form('UL4', dentro='    TextSettings.FontColor = $FF00A152\r\n')
    n = linea_de(p, 'TextSettings.FontColor')
    r = srv.call('delphi_designer', {'path': p, 'command': 'preview', 'maxwidth': 200}, t=240)
    check('L4 un entero que no cabe: preview DSGN-153 con la CAUSA y su linea (%d), no solo Stream read error' % n,
          mc.abre(r, 'SR_DESIGNER_NO_CARGA_FMT') and 'Error reading Edit1.TextSettings.FontColor' in r
          and ('line %d:' % n) in r, r[:600])

    p = form('UL5')
    r = srv.call('delphi_changeset', {'command': 'begin'})
    m = re.search(r'CHANGESET (\S+) opened', r)
    cid = m.group(1) if m else ''
    srv.call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'edit', 'path': p,
                                  'old': '    TabOrder = 0', 'new': '    TabOrder = 0\r\n' + MALO})
    srv.call('delphi_changeset', {'command': 'preview', 'id': cid}, t=240)
    r = srv.call('delphi_changeset', {'command': 'commit', 'id': cid}, t=240)
    check('L5 un changeset que escribe FontColor = -65536: EDIT-127 en sus avisos',
          bool(cid) and not mc.rechazado(r) and mc.es(r, 'SN_EDIT_AVISO_LECTOR_FMT') and LECTOR in r, r[-700:])

    malo = b'\xef\xbb\xbf' + texto(MALO + '\r\n').encode('utf-8')
    open(os.path.join(JAIL, 'UL6.pas'), 'wb').write(PAS.replace('{u}', 'UL6').encode('utf-8'))
    p = os.path.join(JAIL, 'UL6.fmx')
    r = srv.call('delphi_upload', {'path': p, 'offset': 0, 'chunkbase64': base64.b64encode(malo).decode()}, t=240)
    j = mc.como_json(r)
    check('L6 upload de un form entero con FontColor = -65536: "designer" con EDIT-127',
          not mc.fallo(r) and mc.es(' '.join(j.get('designer') or []), 'SN_EDIT_AVISO_LECTOR_FMT'), r[:600])

    open(os.path.join(JAIL, 'UL7.pas'), 'wb').write(PAS.replace('{u}', 'UL7').encode('utf-8'))
    p = os.path.join(JAIL, 'UL7.fmx')
    mitad = len(malo) // 2
    r1 = srv.call('delphi_upload', {'path': p, 'offset': 0,
                                    'chunkbase64': base64.b64encode(malo[:mitad]).decode()}, t=240)
    r2 = srv.call('delphi_upload', {'path': p, 'offset': mitad,
                                    'chunkbase64': base64.b64encode(malo[mitad:]).decode(),
                                    'sha256': hashlib.sha256(malo).hexdigest()}, t=240)
    j1, j2 = mc.como_json(r1), mc.como_json(r2)
    check('L7 a trozos: el primero (a medias, sin sha256) no se juzga; el ultimo, con sha256, si',
          not mc.fallo(r1) and 'designer' not in j1 and j2.get('verified') is True
          and mc.es(' '.join(j2.get('designer') or []), 'SN_EDIT_AVISO_LECTOR_FMT'), (r1[:300], r2[:500]))

    p = form('UL8')
    r = srv.call('delphi_designer', {'path': p, 'command': 'lint'}, t=240)
    e = srv.call('delphi_edit', {'path': p, 'old': '    TabOrder = 0', 'new': '    TabOrder = 1'}, t=240)
    check('L8 el control: un form sano con lineas guardadas por codigo: lint CLEAN y delphi_edit sin EDIT-127',
          mc.tiene(r, 'DSGN-020') and not mc.rechazado(e) and not mc.tiene(e, 'EDIT-127'), (r[:300], e[-400:]))

    p = form('UL9', otro=TERCEROS)
    e = srv.call('delphi_edit', {'path': p, 'old': '    TabOrder = 0', 'new': '    TabOrder = 1'}, t=240)
    check('L9 una clase de terceros sustituida: lo que el lector se salta de ella no es un aviso del lector',
          not mc.rechazado(e) and not mc.tiene(e, 'EDIT-127') and 'X1.Foo' not in e, e[-600:])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('el lector del IDE en todas las puertas 120 (DSGN-061)')
