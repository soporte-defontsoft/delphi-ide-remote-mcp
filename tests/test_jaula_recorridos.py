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
# la unidad suelta de dentro (se crea abajo): la victima la LISTA por su ruta absoluta, para que el
# .dproj de fuera la sirviera de verdad si un recorredor cruzara el enlace; sin eso (solo un
# DCCReference, sin .dpr) no la servia ni cruzando y la ausencia de abajo no podia fallar (revisor
# del diff de la cola de la 1.27)
SUELTA = os.path.join(MINE, 'suelta')
USUELTA = os.path.join(SUELTA, 'USuelta.pas')
files = {
    MARK + '.pas': 'unit ' + MARK + ';\ninterface\nuses ULocal;\nimplementation\nprocedure Otra; begin Saludo; end;\nend.\n',
    'JaulaVictimaTests.dpr': 'program JaulaVictimaTests;\n{$APPTYPE CONSOLE}\nbegin end.\n',
    'JaulaVictima.dfm': 'object JaulaVictima: TForm\n  OnClick = Saludo\nend\n',
    'JaulaVictima.dproj': '<Project><ItemGroup><DCCReference Include="USuelta.pas" /></ItemGroup></Project>',
    'JaulaVictima.dpr': "program JaulaVictima;\nuses\n  USuelta in '%s';\nbegin end.\n" % USUELTA,
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
    # (revisor de baterias, 18-oct-2026) cada tool tiene que ver lo LOCAL: solo
    # ausencias, una respuesta vacia pasaba (discover no tenia nada que ver)
    open(os.path.join(MINE, 'LocalTests.dpr'), 'w', encoding='utf-8').write(
        'program LocalTests;\n{$APPTYPE CONSOLE}\nbegin end.\n')
    LO_LOCAL = {'delphi_test': 'LocalTests', 'delphi_symbols': 'Saludo',
                'delphi_references': 'ULocal.pas', 'delphi_rename_symbol': 'ULocal.pas'}
    for tool, args in (
        ('delphi_test', {'command': 'discover', 'path': MINE}),
        ('delphi_symbols', {'path': MINE}),
        ('delphi_references', {'path': LOCAL, 'line': 2, 'character': 11}),
        ('delphi_rename_symbol', {'path': LOCAL, 'line': 2, 'character': 11,
                                  'newname': 'SaludoNuevo', 'mode': 'preview'}),
    ):
        r = srv.call(tool, args)
        check(tool + ': responde sin nombres ni contenido de fuera, y con lo de dentro (%s)' % LO_LOCAL[tool],
              not mc.sin_respuesta(r) and not mc.fallo(r) and LO_LOCAL[tool] in r and
              MARK not in r and 'JaulaVictima' not in r and 'MARCA_PRIVADA' not in r, r)
    os.makedirs(SUELTA)
    open(USUELTA, 'w').write('unit USuelta;\ninterface\nimplementation\nend.\n')
    ESPIA = os.path.join(SUELTA, 'enlace')
    check('fixture proyecto enlazado para unidad suelta', mc.junction(ESPIA, VICTIM))
    # (revisor de baterias de la 1.27) el .dproj local de la raiz esta ENCIMA de suelta\ y la servia: la
    # respuesta era la misma con el de fuera tomado o no (symbols no nombra el proyecto), y la ausencia no
    # podia fallar. Apartado, lo que se mide es que el de fuera NO la sirve: LSP-021 (ningun .dproj la sirve)
    DPROJ_LOCAL = os.path.join(MINE, 'JaulaLocal.dproj')
    os.rename(DPROJ_LOCAL, DPROJ_LOCAL + '.aparte')
    try:
        try:
            r = srv.call('delphi_symbols', {'path': USUELTA})
            check('unidad suelta no expone el nombre del proyecto de fuera, ni la sirve (LSP-021)',
                  not mc.fallo(r) and not mc.sin_respuesta(r) and 'JaulaVictima' not in r and
                  mc.es(r, 'SN_LSP_NO_SETTINGS_WARNING'), r)
        finally:
            os.rmdir(ESPIA)
        # el control: un .dproj de DENTRO que la lista SI la sirve, y el aviso se va
        open(os.path.join(SUELTA, 'SueltaLocal.dproj'), 'w').write(
            '<Project><ItemGroup><DCCReference Include="USuelta.pas" /></ItemGroup></Project>')
        r = srv.call('delphi_symbols', {'path': USUELTA})
        check('control: con un .dproj de dentro que la lista, sin LSP-021',
              not mc.fallo(r) and not mc.sin_respuesta(r) and not mc.es(r, 'SN_LSP_NO_SETTINGS_WARNING'), r)
    finally:
        os.rename(DPROJ_LOCAL + '.aparte', DPROJ_LOCAL)
    check('victima intacta tras las tools',
          sorted(os.listdir(VICTIM)) == sorted(files) and all(open(os.path.join(VICTIM, n), 'rb').read() == t
                                                   for n, t in before.items()))
finally:
    srv.cierra()
    os.rmdir(LINK)
mc.borra(BASE)
check('BASE eliminada con su copia del exe', not os.path.exists(BASE), BASE)
mc.fin('jaula recorridos')
