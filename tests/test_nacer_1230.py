# -*- coding: utf-8 -*-
"""Como NACE un fichero, una regla (A21 y A38 de la 1.23).

  N1 (A21) un .dproj creado por un changeset nace en UTF-8 con BOM, como lo
     escribe el IDE y como lo crea delphi_create (ROJO hasta la 1.23: sin BOM)
  N2 (A21, guarda) un .txt creado por un changeset y por delphi_textedit nace en
     UTF-8 sin BOM
  N3 (A38, guarda) eol=lf en el create de delphi_edit y de delphi_textedit: los
     bytes en LF y la respuesta dice LF; sin eol, CRLF; eol=cr se niega en los dos

Uso:  python tests/test_nacer_1230.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('test_nacer_1230')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
BOM = b'\xef\xbb\xbf'
DPROJ = ('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n'
         '    <PropertyGroup>\n        <ProjectGuid>{0A0B0C0D-0000-0000-0000-000000000001}</ProjectGuid>\n'
         '    </PropertyGroup>\n</Project>\n')

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='test-nacer', t=300)
try:
    r = srv.call('delphi_changeset', {'command': 'begin'})
    cid = mc.id_changeset(r)
    pd = os.path.join(JAIL, 'Nuevo.dproj')
    pt = os.path.join(JAIL, 'notas.txt')
    srv.call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'create', 'path': pd, 'content': DPROJ})
    srv.call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'create', 'path': pt, 'content': 'hola\n'})
    srv.call('delphi_changeset', {'command': 'preview', 'id': cid}, t=120)
    r = srv.call('delphi_changeset', {'command': 'commit', 'id': cid}, t=120)
    check('N1 un .dproj creado por un changeset nace con BOM, como lo escribe el IDE',
          os.path.exists(pd) and open(pd, 'rb').read().startswith(BOM),
          (r[:300], open(pd, 'rb').read()[:8] if os.path.exists(pd) else None))
    pt2 = os.path.join(JAIL, 'notas2.txt')
    srv.call('delphi_textedit', {'path': pt2, 'create': True, 'content': 'hola\n'})
    check('N2 (guarda) un .txt nace sin BOM, por changeset y por delphi_textedit',
          os.path.exists(pt) and not open(pt, 'rb').read().startswith(BOM) and
          os.path.exists(pt2) and not open(pt2, 'rb').read().startswith(BOM), r[:300])

    pu = os.path.join(JAIL, 'ULf.pas')
    r1 = srv.call('delphi_edit', {'path': pu, 'createunit': True, 'eol': 'lf'})
    pl = os.path.join(JAIL, 'lf.txt')
    r2 = srv.call('delphi_textedit', {'path': pl, 'create': True, 'content': 'a\r\nb\r\n', 'eol': 'lf'})
    pc = os.path.join(JAIL, 'crlf.txt')
    r3 = srv.call('delphi_textedit', {'path': pc, 'create': True, 'content': 'a\nb\n'})
    r4 = srv.call('delphi_textedit', {'path': os.path.join(JAIL, 'cr.txt'), 'create': True, 'content': 'a', 'eol': 'cr'})
    r5 = srv.call('delphi_edit', {'path': os.path.join(JAIL, 'UCr.pas'), 'createunit': True, 'eol': 'cr'})
    b1 = open(pu, 'rb').read() if os.path.exists(pu) else b''
    b2 = open(pl, 'rb').read() if os.path.exists(pl) else b''
    b3 = open(pc, 'rb').read() if os.path.exists(pc) else b''
    check('N3 (guarda) eol=lf en los dos create: LF y lo dicen; sin eol, CRLF; eol=cr, negado en los dos',
          b'\r\n' not in b1 and b'\n' in b1 and 'LF' in r1 and b2 == b'a\nb\n' and 'LF' in r2 and
          b3 == b'a\r\nb\r\n' and mc.rechazado(r4) and mc.rechazado(r5), (r1[:150], r2[:150], r4[:150], r5[:150]))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('como nace un fichero, A21 y A38 de la 1.23')
