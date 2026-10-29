# -*- coding: utf-8 -*-
"""1.23.1 (V150, security) - what goes on the engine's option line from the
agent's .dproj is a list of NAMES, judged one by one (EsIdentificador). The
defines and the unit scopes were only stripped of what carried $( or \\, so a
DCC_Define "X -UD:/<folder outside the roots>" reached the engine as -DX and a
NEW -U: the engine indexed the units of a folder outside the jail. hover and
definition stop there (LSP-038, the second barrier), but signature help gave
the signature of a routine of a unit OUTSIDE and completion its name and
detail. Measured on 28-oct-2026 against the build of V119 (760f912), with a
unit of a sibling project outside the roots as the witness.

Here the witness is UFuera.pas in BASE\\fuera, outside the only root
(BASE\\jail):

  L0 control: with no injection, signature at SecretoDeFuera( does not show it
  L1 DCC_Define "X -U<fuera>": signature and completion do not show the routine
     of UFuera, and dccOptions carries no -U to it; DEBUG is still defined
  L2 DCC_Namespace "System;Y -U<fuera>": the same, and System is still a scope
  L3 FrameworkType "None -U<fuera>" (it becomes -DFRAMEWORK_<type>): the same
  L4 (V160c, security sibling): a <MainSource> that resolves OUTSIDE the roots
     pointed settings.project (and the engine's Held folder) at a project
     outside the jail; now it falls back to the sibling .dpr (DprDe), inside.

L1-L4 are RED against the build before (pass its exe as argument); L0 is green
with both.

Usage:  python tests/test_linea_del_motor_1231.py [path-to-DelphiLspMcp.exe]
"""
import json, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('linea1231')
EXE = mc.copia_exe(BASE)
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
APPDATA = os.path.join(BASE, 'appdata')
for d in (JAIL, FUERA, APPDATA):
    os.makedirs(d)
open(os.path.join(FUERA, 'UFuera.pas'), 'w', newline='\r\n').write(
    'unit UFuera;\ninterface\nfunction SecretoDeFuera(A: Integer): Integer;\n'
    'implementation\nfunction SecretoDeFuera(A: Integer): Integer;\nbegin\n  Result := A;\nend;\nend.\n')
# con barras normales: lo que llevaba '\' ya se quitaba
INYECCION = '-U' + FUERA.replace('\\', '/')
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'LOCALAPPDATA': APPDATA}), nombre='linea1231', t=600)

PROGRAMA = '\r\n'.join(['program %s;', '', '{$APPTYPE CONSOLE}', '', 'uses', '  System.SysUtils,', '  UFuera;', '',
                        'begin', '  Writeln(SecretoDeFuera(1));', 'end.', ''])
LINEA = PROGRAMA.split('\r\n').index('  Writeln(SecretoDeFuera(1));')
DENTRO = '  Writeln(SecretoDeFuera(1));'.index('(1)') + 1   # dentro de los parentesis de la llamada
PREFIJO = '  Writeln(SecretoDeFuera(1));'.index('Secreto') + len('Secreto')


def consola(nombre, prop=None, valor=None, framework=None):
    """Una consola en la jaula que usa UFuera, con una propiedad puesta: (.dpr)."""
    d = os.path.join(JAIL, nombre)
    r = S.call('delphi_create', {'kind': 'project-console', 'name': nombre, 'dir': d})
    check('preparacion: la consola %s' % nombre, not mc.fallo(r), r[:200])
    dproj, dpr = os.path.join(d, nombre + '.dproj'), os.path.join(d, nombre + '.dpr')
    if prop:
        r = S.call('delphi_config', {'command': 'set-property', 'project': dproj, 'name': prop,
                                     'value': valor + ';$(' + prop + ')'})
        check('preparacion: %s de %s' % (prop, nombre), not mc.fallo(r), r[:200])
    if framework:
        # a mano en el fixture: el FrameworkType que escribe el IDE, con lo plantado detras
        t = open(dproj, 'rb').read().decode('utf-8-sig')
        assert '<FrameworkType>None</FrameworkType>' in t, t[:400]
        t = t.replace('<FrameworkType>None</FrameworkType>', '<FrameworkType>%s</FrameworkType>' % framework, 1)
        open(dproj, 'wb').write(t.encode('utf-8'))
    open(dpr, 'wb').write((chr(0xfeff) + PROGRAMA % nombre).encode('utf-8'))
    return dpr


def lo_ensena(dpr):
    """(signature, completion): si alguna de las dos ensena la rutina de UFuera."""
    s = S.call('delphi_signature', {'path': dpr, 'line': LINEA, 'character': DENTRO}, 300)
    c = S.call('delphi_completion', {'path': dpr, 'line': LINEA, 'character': PREFIJO}, 300)
    return 'SecretoDeFuera' in s or 'UFuera' in s, 'SecretoDeFuera' in c, s[:200], c[:200]


def opciones(dpr):
    fab = mc.ajustes_fabricados(dpr, APPDATA)
    return json.load(open(fab, encoding='utf-8-sig'))['settings'].get('dccOptions', '') if fab else ''


# ---------------------------------------------------------------- L0
dpr0 = consola('Cero')
sig, comp, s, c = lo_ensena(dpr0)
check('L0 control: sin inyeccion, ni signature ni completion ensenan la unidad de fuera', not sig and not comp, (s, c))

# ---------------------------------------------------------------- L1-L3
for clave, dpr, comprueba in (
        ('L1 DCC_Define', consola('Def', 'DCC_Define', 'X ' + INYECCION), ' -DDEBUG'),
        ('L2 DCC_Namespace', consola('Nsp', 'DCC_Namespace', 'System;Y ' + INYECCION), 'System'),
        ('L3 FrameworkType', consola('Fwk', framework='None ' + INYECCION), ' -DDEBUG')):
    sig, comp, s, c = lo_ensena(dpr)
    check('%s con un -U a una carpeta de fuera: signature no ensena su rutina' % clave, not sig, s)
    check('%s ...ni completion' % clave, not comp, c)
    o = opciones(dpr)
    check('%s ...y la linea del motor no lleva ese -U (y conserva %s)' % (clave, comprueba.strip()),
          o != '' and INYECCION not in o and comprueba in o, o[:400])

# ---------------------------------------------------------------- L4 (V160c)
# <MainSource> -> settings.project: un MainSource que resuelve FUERA de las
# raices apuntaba el motor (y su Held, Lsp.Session) a un proyecto de fuera (el
# hermano de V150). Ahora, fuera de las raices vale lo que no tenerla: el .dpr
# de al lado (DprDe). Rojo contra el build anterior; verde con el fix.
import re
open(os.path.join(FUERA, 'Evil.dpr'), 'w', newline='\r\n').write('program Evil;\nbegin\nend.\n')
dmain = consola('Lanzadera')
dproj_main = dmain[:-4] + '.dproj'
_t = open(dproj_main, 'rb').read().decode('utf-8-sig')
_t2 = re.sub(r'<MainSource>.*?</MainSource>',
             lambda m: '<MainSource>..\\..\\fuera\\Evil.dpr</MainSource>', _t, count=1)
assert '<MainSource>..\\..\\fuera\\Evil.dpr</MainSource>' in _t2, _t[:300]
open(dproj_main, 'wb').write((chr(0xfeff) + _t2).encode('utf-8'))
S.call('delphi_completion', {'path': dmain, 'line': 1, 'character': 0}, 300)
_cfg = ''
_dir = mc.cache_servidor('configs', APPDATA)
for _f in (os.listdir(_dir) if os.path.isdir(_dir) else []):
    if _f.startswith('Lanzadera-') and _f.endswith('.delphilsp.json'):
        _cfg = json.load(open(os.path.join(_dir, _f), encoding='utf-8-sig'))['settings']['project']
check('L4 (V160c) un MainSource que resuelve fuera de las raices cae al .dpr de al lado, no al de fuera',
      _cfg != '' and '/jail/' in _cfg and 'Lanzadera.dpr' in _cfg and 'Evil' not in _cfg and '/fuera/' not in _cfg, _cfg)

S.cierra()
mc.borra(BASE)
mc.fin('linea-del-motor-1231 battery')
