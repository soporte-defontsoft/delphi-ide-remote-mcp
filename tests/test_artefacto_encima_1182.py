# -*- coding: utf-8 -*-
"""M1 del revisor de cierre de la 1.18.2 (medido): el filtro de artefactos del
IDE (SkipIdeArtifacts: Debug, Release, Win32, Win64, dcu, __history...) se
juzgaba sobre la ruta ABSOLUTA, asi que una carpeta de ENCIMA con uno de esos
nombres hacia artefacto a todo lo de debajo. Ahora cada recorrido juzga lo que
hay debajo de su raiz (SkipBajoLaRaiz) y upload lo de debajo de la raiz del
workspace (RaizQueContiene).

La raiz del workspace cuelga aqui de una carpeta llamada Release:

  A1 adduses de una unidad que esta junto al .dpr: es del proyecto, USES-021
     (ROJO en produccion: USES-013, entraba como de biblioteca)
  A2 delphi_symbols de una carpeta: lista sus unidades (ROJO: ninguna)
  A3 delphi_upload de un fichero nuevo: se sube (ROJO: negado como artefacto)
  A4 ...y al sobrescribir uno que existe, con su copia antes (backup)
  A5 control: lo que esta en un Win32 DEBAJO de la raiz sigue siendo artefacto
     (upload negado)
  A6 delphi_references de una funcion de la unidad: encuentra su uso en el .dpr

Uso:  python tests/test_artefacto_encima_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import base64
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('artefacto_encima_1182')
JAIL = os.path.join(BASE, 'Release', 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
UNIDAD = ('unit UA;\n\ninterface\n\nfunction Doble(N: Integer): Integer;\n\nimplementation\n\n'
          'function Doble(N: Integer): Integer;\nbegin\n  Result := N * 2;\nend;\n\nend.\n')


def sube(srv, ruta, datos):
    return srv.call('delphi_upload', {'path': ruta, 'chunkbase64': base64.b64encode(datos).decode()}, t=120)


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='artefacto-encima', t=300)
try:
    pa = os.path.join(JAIL, 'PA')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'PA', 'dir': pa}, t=120)
    open(os.path.join(pa, 'UFoo.pas'), 'w').write('unit UFoo;\n\ninterface\n\nimplementation\n\nend.\n')
    r = srv.call('delphi_edit', {'path': os.path.join(pa, 'PA.dpr'), 'adduses': 'UFoo'}, t=120)
    check('A1 adduses de la unidad de al lado del .dpr, bajo una carpeta Release de encima: USES-021',
          'USES-021' in r, r[:300])
    # (M8 del revisor de cierre: el escritor de delphi_edit bajo ese antepasado)
    r = srv.call('delphi_edit', {'path': os.path.join(pa, 'UFoo.pas'), 'old': 'interface',
                                 'new': 'interface\n\nconst\n  Uno = 1;'}, t=120)
    check('A1b delphi_edit de esa unidad bajo la carpeta Release de encima: escribe (EDIT-087)',
          'EDIT-087' in r and 'Uno = 1' in open(os.path.join(pa, 'UFoo.pas')).read(), r[:300])

    ps = os.path.join(JAIL, 'PS')
    os.makedirs(ps)
    open(os.path.join(ps, 'UOne.pas'), 'w').write('unit UOne;\n\ninterface\n\nprocedure Uno;\n\n'
                                                   'implementation\n\nprocedure Uno;\nbegin\nend;\n\nend.\n')
    r = srv.call('delphi_symbols', {'path': ps}, t=120)
    check('A2 delphi_symbols de la carpeta lista su unidad', 'UOne' in r, r[:300])

    nuevo = os.path.join(ps, 'up.txt')
    r = sube(srv, nuevo, b'uno\n')
    check('A3 upload de un fichero nuevo: se sube', not mc.rechazado(r) and os.path.exists(nuevo), r[:300])
    r = sube(srv, nuevo, b'dos\n')
    check('A4 ...y al sobrescribirlo, con su copia antes',
          not mc.rechazado(r) and 'backup' in r.lower() and open(nuevo).read() == 'dos\n', r[:400])
    dentro = os.path.join(ps, 'Win32', 'x.txt')
    r = sube(srv, dentro, b'x\n')
    check('A5 control: un Win32 DEBAJO de la raiz sigue siendo artefacto (upload negado)',
          mc.rechazado(r) and not os.path.exists(dentro), r[:300])

    pr = os.path.join(JAIL, 'PR')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'PR', 'dir': pr}, t=120)
    srv.call('delphi_create', {'kind': 'unit', 'name': 'UA', 'project': os.path.join(pr, 'PR.dpr'),
                               'content': UNIDAD}, t=120)
    dpr = os.path.join(pr, 'PR.dpr')
    srv.call('delphi_edit', {'path': dpr, 'old': "    Writeln('PR running');",
                             'new': "    Writeln('PR running', Doble(21));"}, t=120)
    r = srv.call('delphi_references', {'path': os.path.join(pr, 'UA.pas'), 'line': 4, 'character': 10}, t=300)
    usos = [f for f in mc.como_json(r).get('confirmed', []) for f in f.get('files', [])]
    check('A6 references de Doble encuentra su uso en el .dpr',
          any(f.get('name', '').lower() == 'pr.dpr' for f in usos), r[:500])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('artefacto por encima de la raiz 1182 (M1)')
