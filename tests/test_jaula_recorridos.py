"""Lectura de arboles: cada tool ve solo lo legible, tambien tras un junction."""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('jaula-recorridos')
MINE = os.path.join(BASE, 'mio')
VICTIM = os.path.join(BASE, 'victima')
os.makedirs(MINE)
os.makedirs(VICTIM)
MARK = 'UJaulaVictima'
files = {
    MARK + '.pas': 'unit ' + MARK + ';\ninterface\nuses ULocal;\nimplementation\nprocedure Otra; begin Saludo; end;\nend.\n',
    'JaulaVictimaTests.dpr': 'program JaulaVictimaTests;\n{$APPTYPE CONSOLE}\nbegin end.\n',
    'JaulaVictima.dfm': 'object JaulaVictima: TForm\n  OnClick = Saludo\nend\n',
    'JaulaVictima.dproj': '<Project><ItemGroup><DCCReference Include="USuelta.pas" /></ItemGroup></Project>',
}
for n, t in files.items():
    open(os.path.join(VICTIM, n), 'w', encoding='utf-8').write(t)
before = {n: open(os.path.join(VICTIM, n), 'rb').read() for n in files}
LINK = os.path.join(MINE, 'enlace')
check('fixture junction a victima fuera de todas las raices', mc.junction(LINK, VICTIM))
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': MINE}), nombre='jaula-recorridos', t=180)
try:
    r = srv.call('delphi_create', {'kind': 'project-console', 'dir': MINE, 'name': 'JaulaLocal'})
    check('fixture proyecto local creado', not mc.fallo(r), r)
    LOCAL = os.path.join(MINE, 'ULocal.pas')
    open(LOCAL, 'w', encoding='utf-8-sig').write(
        'unit ULocal;\ninterface\nprocedure Saludo;\nimplementation\n'
        'procedure Saludo; begin end;\nend.\n')
    r = srv.call('delphi_config', {'command': 'add-unit',
        'project': os.path.join(MINE, 'JaulaLocal.dproj'), 'path': LOCAL})
    check('fixture unidad local registrada', not mc.fallo(r), r)
    for tool, args in (
        ('delphi_test', {'command': 'discover', 'path': MINE}),
        ('delphi_symbols', {'path': MINE}),
        ('delphi_references', {'path': LOCAL, 'line': 2, 'character': 11}),
        ('delphi_rename_symbol', {'path': LOCAL, 'line': 2, 'character': 11,
                                  'newname': 'SaludoNuevo', 'mode': 'preview'}),
    ):
        r = srv.call(tool, args)
        check(tool + ': responde sin nombres ni contenido de fuera',
              not mc.sin_respuesta(r) and not mc.fallo(r) and
              MARK not in r and 'JaulaVictima' not in r and 'MARCA_PRIVADA' not in r, r)
    SUELTA = os.path.join(MINE, 'suelta')
    os.makedirs(SUELTA)
    USUELTA = os.path.join(SUELTA, 'USuelta.pas')
    open(USUELTA, 'w').write('unit USuelta;\ninterface\nimplementation\nend.\n')
    ESPIA = os.path.join(SUELTA, 'enlace')
    check('fixture proyecto enlazado para unidad suelta', mc.junction(ESPIA, VICTIM))
    try:
        r = srv.call('delphi_symbols', {'path': USUELTA})
        check('unidad suelta no expone el nombre del proyecto de fuera', not mc.fallo(r) and
              not mc.sin_respuesta(r) and 'JaulaVictima' not in r, r)
    finally:
        os.rmdir(ESPIA)
    check('victima intacta tras las tools',
          sorted(os.listdir(VICTIM)) == sorted(files) and all(open(os.path.join(VICTIM, n), 'rb').read() == t
                                                   for n, t in before.items()))
finally:
    srv.cierra()
    os.rmdir(LINK)
mc.fin('jaula recorridos')
