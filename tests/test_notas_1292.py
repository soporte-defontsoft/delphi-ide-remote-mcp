# -*- coding: utf-8 -*-
"""1.29.2 (C6, C7, C8): tres textos que no llevaban al paso siguiente, medidos por Hermes (IQ3_S) en el control de la
1.29.2 (14-nov-2026, state.db) y aqui en produccion.

  N1 C7 un E2003 (TStringList sin System.Classes): undeclaredNote (BUILD-075) nombra el identificador y la busqueda de
        delphi_docs que da su unidad. ROJO contra el build anterior (ninguna nota nombraba delphi_docs)
  N2 C7 un error que NO es E2003 (E2010, con sus propias citas) y un build verde: sin undeclaredNote (va por el codigo)
  N3 C6 una unidad que no existe (F2613, sin candidatas): BUILD-042 dice que puede NO EXISTIR y como dar con la real.
        ROJO contra el build anterior (solo "no instalado o sin fuente")
  N4 C8 hover sobre la declaracion de un TIPO contesta (el hecho que desmiente la nota vieja), y un null lleva LSP-024
        diciendo lo mismo que la descripcion ("may return null"). ROJO contra el build anterior ("not on declarations")

Uso:  python tests/test_notas_1292.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('notas_1292')
EXE = mc.copia_exe(BASE)
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='notas1292', t=600)

# E2003 'TStringList': la unidad no usa System.Classes (el r07 del dataset)
NODECL = '''unit UNoDecl;

interface

implementation

procedure Usa;
var
  L: TStringList;
begin
  L := nil;
end;

end.
'''
# E2010 Incompatible types: 'Integer' and 'string' - un error con citas que no es E2003
OTRO = '''unit UOtro;

interface

implementation

procedure Usa;
var
  I: Integer;
begin
  I := 'texto';
end;

end.
'''
# una unidad que no existe en ninguna parte (F2613 sin candidatas)
NOEXISTE = '''unit UNoExiste;

interface

uses
  NoSuchUnitXyz1292;

implementation

end.
'''
# un tipo declarado: hover sobre su declaracion (linea0 5, `  TCosa = class`) y sobre la linea en blanco (linea0 1)
HOVER = '''unit UHover;

interface

type
  TCosa = class
  public
    procedure Hola;
  end;

implementation

procedure TCosa.Hola;
begin
end;

end.
'''


def escribe(carpeta, nombre, texto):
    os.makedirs(carpeta, exist_ok=True)
    ruta = os.path.join(carpeta, nombre)
    with open(ruta, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(texto.replace('\n', '\r\n'))
    return ruta


def proyecto(nombre, texto, unidad):
    d = os.path.join(BASE, nombre)
    r = S.call('delphi_create', {'kind': 'project-console', 'name': nombre, 'dir': d})
    check('preparacion: el proyecto %s' % nombre, not mc.fallo(r), r[:200])
    ruta = escribe(d, unidad, texto)
    dproj = os.path.join(d, nombre + '.dproj')
    r = S.call('delphi_config', {'command': 'add-unit', 'project': dproj, 'path': ruta})
    check('preparacion: %s en %s' % (unidad, nombre), not mc.fallo(r), r[:200])
    return dproj, ruta


def build(dproj):
    return mc.como_json(S.call('delphi_build', {'project': dproj}, 600)) or {}


def hover(path, line, character, tope=180):
    """El hover, repetido mientras el motor diga que aun indexa (LSP-025)."""
    t0, r = time.time(), ''
    while time.time() - t0 < tope:
        r = S.call('delphi_hover', {'path': path, 'line': line, 'character': character}, 120) or ''
        if not mc.es(r, 'SR_LSP_WARMING'):
            return r
        time.sleep(3)
    return r


try:
    # ------------------------------------------------------------------ N1
    j = build(proyecto('PNoDecl', NODECL, 'UNoDecl.pas')[0])
    nota = j.get('undeclaredNote', '')
    check('N1 un E2003 (TStringList): el build falla con el E2003 en errors',
          j.get('success') is False and any('E2003' in e and "'TStringList'" in e for e in j.get('errors') or []),
          j.get('errors'))
    check('N1 ...y undeclaredNote (BUILD-075) nombra TStringList y la busqueda de delphi_docs. ROJO contra el anterior',
          mc.abre(nota, 'SN_BUILD_UNDECLARED_FMT') and "'TStringList'" in nota and
          'delphi_docs command=search query=TStringList' in nota, nota)

    # ------------------------------------------------------------------ N2
    j = build(proyecto('POtro', OTRO, 'UOtro.pas')[0])
    check('N2 un E2010 (con sus propias citas): sin undeclaredNote - va por el codigo, no por la cita',
          j.get('success') is False and any('E2010' in e for e in j.get('errors') or []) and
          'undeclaredNote' not in j, (j.get('errors'), j.get('undeclaredNote')))

    # ------------------------------------------------------------------ N3
    j = build(proyecto('PNoExiste', NOEXISTE, 'UNoExiste.pas')[0])
    nota = j.get('missingUnitsNote', '')
    faltan = {m.get('unit'): m.get('sourceFolders') for m in j.get('missingUnits') or []}
    check('N3 una unidad que no existe: missingUnits la trae sin candidatas',
          faltan.get('NoSuchUnitXyz1292') == [], j.get('missingUnits'))
    check('N3 ...y BUILD-042 dice que puede no existir y que delphi_docs da la real. ROJO contra el anterior',
          mc.abre(nota, 'SN_BUILD_MISSING_UNITS_NOTE') and 'the unit may not exist' in nota and
          'delphi_docs command=search' in nota, nota)

    # ------------------------------------------------------------------ N4
    dproj, uhover = proyecto('PHover', HOVER, 'UHover.pas')
    j = build(dproj)
    check('N4 (preparacion) el proyecto del hover compila, y sin undeclaredNote',
          j.get('success') is True and 'undeclaredNote' not in j, str(j)[:300])
    r = hover(uhover, 5, 3)
    check('N4 hover sobre la DECLARACION de un tipo (TCosa = class) contesta: la nota vieja decia que no',
          not mc.sin_respuesta(r) and not mc.es(r, 'SR_LSP_WARMING') and 'TCosa' in r and
          not mc.es(r, 'SN_LSP_HINT_HOVER_USAGES'), r[:300])
    r = hover(uhover, 1, 0)
    check('N4 un null (linea en blanco) lleva LSP-024 diciendo lo mismo que la descripcion: "may return null". '
          'ROJO contra el anterior ("not on declarations")',
          mc.es(r, 'SN_LSP_HINT_HOVER_USAGES') and 'may return null' in r and 'not on declarations' not in r,
          r[-300:])
finally:
    S.cierra()
    mc.borra(BASE)
mc.fin('notas de build y hover (1.29.2, C6/C7/C8)')
