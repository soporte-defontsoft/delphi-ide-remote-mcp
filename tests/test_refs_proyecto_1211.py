# -*- coding: utf-8 -*-
"""delphi_references y delphi_rename_symbol nombran el PROYECTO cuyos ajustes
uso el motor (1.21.1). Decian el alcance (scope) y no de quien era: con dos
copias del mismo proyecto en el workspace - lo normal - el agente no sabia
con cual se habian buscado los usos. diagnostics ya lo decia (H7 de la
1.19.1); los tres lo leen ahora por UN sitio (ProyectoDeLosAjustes).

  P1 references en el original: project = su .dproj
  P2 references en una COPIA al lado: project = el .dproj de la copia
  P3 rename_symbol preview en la copia: el mismo project
  P4 diagnostics en la copia sigue diciendo el de la copia (control: verde
     tambien contra 1.21.0)

P1-P3 son ROJAS contra 1.21.0 (pasar su exe como argumento).

Uso:  python tests/test_refs_proyecto_1211.py [ruta-a-DelphiLspMcp.exe]
"""
import os, shutil
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('refs_proyecto_1211')
JAIL = os.path.join(BASE, 'jail')
A = os.path.join(JAIL, 'lib_1_0')
B = os.path.join(JAIL, 'lib_2_0')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='refs-proyecto', t=600)


def proyecto(r):
    """El project de una respuesta, en su forma real y larga ('' si no lo trae)."""
    p = (mc.como_json(r) or {}).get('project', '')
    return os.path.normcase(mc.larga(mc.real(p))) if p else ''


def es(p, dproj):
    return p == os.path.normcase(mc.larga(dproj))


try:
    r = S.call('delphi_create', {'kind': 'project-console', 'name': 'Lib', 'dir': A})
    check('preparacion: consola Lib', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    UCALC = os.path.join(A, 'UCalc.pas')
    open(UCALC, 'w', encoding='utf-8', newline='\r\n').write(
        'unit UCalc;\n\ninterface\n\ntype\n  TCalc = class\n  public\n'
        '    function Doble(A: Integer): Integer;\n  end;\n\n'
        'implementation\n\nfunction TCalc.Doble(A: Integer): Integer;\nbegin\n'
        '    Result := A * 2;\nend;\n\nend.\n')
    r = S.call('delphi_config', {'project': os.path.join(A, 'Lib.dproj'), 'command': 'add-unit', 'path': UCALC})
    check('preparacion: UCalc en el proyecto', not mc.fallo(r), r[:200])
    shutil.copytree(A, B)
    UCALC_B = os.path.join(B, 'UCalc.pas')
    # dentro de Doble, en su declaracion (0-based: linea 7; la palabra empieza en la 13)
    POS = {'line': 7, 'character': 14}

    r = S.call('delphi_references', dict(POS, path=UCALC), t=600)
    check('P1 references en el original nombra su proyecto',
          es(proyecto(r), os.path.join(A, 'Lib.dproj')), (proyecto(r), r[:300]))
    r = S.call('delphi_references', dict(POS, path=UCALC_B), t=600)
    check('P2 references en la copia nombra el proyecto de la copia',
          es(proyecto(r), os.path.join(B, 'Lib.dproj')), (proyecto(r), r[:300]))
    r = S.call('delphi_rename_symbol', dict(POS, path=UCALC_B, newname='Triple'), t=600)
    check('P3 rename preview en la copia: el mismo proyecto',
          es(proyecto(r), os.path.join(B, 'Lib.dproj')), (proyecto(r), r[:300]))
    check('P3b ...y es un preview: la copia no cambia',
          'Doble' in open(UCALC_B, encoding='utf-8-sig').read())
    r = S.call('delphi_diagnostics', {'path': UCALC_B}, t=600)
    check('P4 diagnostics en la copia sigue diciendo el de la copia (control)',
          es(proyecto(r), os.path.join(B, 'Lib.dproj')), (proyecto(r), r[:300]))
finally:
    S.cierra()

mc.borra(BASE)
mc.fin('refs proyecto 1.21.1')
