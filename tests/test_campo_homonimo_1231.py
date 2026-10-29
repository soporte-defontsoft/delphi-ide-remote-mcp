# -*- coding: utf-8 -*-
"""La DECLARACION de un campo y un homonimo de la unidad (V181 de la 1.23.1, Hermes en la VM,
test completo del 29-oct).

Sobre la declaracion de un campo (Blocked: Integer dentro de un record), DelphiLSP contesta a
veces una var o una const de la unidad del MISMO nombre, o nada: medido a pelo el 29-oct, con
los ajustes del servidor (record Blocked -> la const Blocked; campo Tope de una clase y de un
record -> la var global Tope; un campo sin homonimo -> nada). references valida cada candidato
con esa respuesta, asi que references de la const CONFIRMABA la declaracion del campo y
rename_symbol la renombraba: dejaba R.Blocked sin campo y el proyecto sin compilar. Un campo no
tiene declaracion adelantada ni gemelo: su declaracion es su definicion. Quien dice que una
posicion declara un campo es el motor mismo, su documentSymbol (Lsp.References.DefinicionCorregida).

  H1 references de la const Blocked: la declaracion del campo Blocked NO sale confirmada, sale
     rechazada (ROJA contra b48699c: confirmada)
  H2 delphi_definition sobre la declaracion del campo Blocked: el campo (ROJA: la const)
  H3 references de la var global Tope: ninguna de las dos declaraciones de campo Tope (ROJA)
  H4 references desde la declaracion del campo Tope de la clase: ella y su uso C.Tope, no la var
     (ROJA: la var y sus usos)
  H5 delphi_definition sobre un campo SIN homonimo (Solo): el campo (el motor no contestaba nada)
  H8 delphi_definition kind=declaration sobre las declaraciones de campo (Blocked, Tope, Solo): el
     campo mismo (ROJA aun con la correccion de references: esta rama encadenaba declaration desde
     lo que contestaba el motor, la const, la var o nada)
  H6 (control) references de la clase TAdelantada: su declaracion ADELANTADA sale confirmada (es
     el mismo simbolo: la correccion no la toca)
  H7 rename_symbol apply de la const Clave de una unidad cuyo record tiene un campo Clave SIN usos
     (el caso de Hermes): el campo NO se renombra - rename lo niega con el campo entre los homonimos
     (RENAME-017) o lo aplica dejandolo - y el proyecto compila (ROJA contra b48699c: applicable,
     y el campo renombrado en silencio: compila igual, nadie lo ve)

Uso:  python tests/test_campo_homonimo_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('campo_homonimo_1231')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='campo-homonimo', t=300)
call = srv.call

UNIDAD = ('unit UHomonimos;\r\n\r\ninterface\r\n\r\ntype\r\n'
          '  TSinHomonimo = record\r\n    Solo: Integer;\r\n  end;\r\n'        # 5-7: Solo en 6
          '  PBlocked = record\r\n    Blocked: Integer;\r\n  end;\r\n'         # 8-10: Blocked en 9
          '  TClaseCampo = class\r\n    Tope: Integer;\r\n  end;\r\n'          # 11-13: Tope en 12
          '  TRecPropio = record\r\n    Tope: Integer;\r\n  end;\r\n'          # 14-16: Tope en 15
          '  TAdelantada = class;\r\n  TAdelantada = class\r\n  end;\r\n\r\n'   # 17 y 18
          'const\r\n  Blocked = 0;\r\n\r\n'                                     # 22
          'var\r\n  Tope: Integer;\r\n\r\n'                                     # 25
          'implementation\r\n\r\nprocedure Usa;\r\nvar\r\n  R: PBlocked;\r\n  C: TClaseCampo;\r\n'
          '  P: TRecPropio;\r\n  A: TAdelantada;\r\n  S: TSinHomonimo;\r\nbegin\r\n'
          '  R.Blocked := Blocked;\r\n'                                          # 37
          '  Tope := C.Tope + P.Tope + S.Solo;\r\n'                              # 38
          '  A := nil;\r\nend;\r\n\r\nend.\r\n')
# el caso de Hermes: un campo sin usos y una const de la unidad con su nombre
UNIDAD_SOLO = ('unit UCampoSolo;\r\n\r\ninterface\r\n\r\ntype\r\n  PSolo = record\r\n'
               '    Clave: Integer;\r\n  end;\r\n\r\n'                         # el campo en 6
               'const\r\n  Clave = 1;\r\n\r\nimplementation\r\n\r\nend.\r\n')  # la const en 10


def lineas(r, campo):
    """Las line0 de los aciertos de un campo (confirmed, unverified, rejected) de references."""
    out = []
    for d in r.get(campo) or []:
        for f in d.get('files') or []:
            out += [h.get('line0') for h in f.get('hits') or []]
    return sorted(out)


def refs(linea, col):
    """references, repetida mientras el motor (frio) deje algo sin verificar."""
    r = {}
    for _ in range(4):
        r = mc.como_json(call('delphi_references', {'path': PAS, 'line': linea, 'character': col}, 300))
        if not r.get('unverified'):
            break
    return r


try:
    d = os.path.join(JAIL, 'p')
    call('delphi_create', {'kind': 'project-console', 'name': 'P', 'dir': d})
    DPROJ = os.path.join(d, 'P.dproj')
    PAS = os.path.join(d, 'UHomonimos.pas')
    SOLO = os.path.join(d, 'UCampoSolo.pas')
    open(PAS, 'w', newline='').write(UNIDAD)
    open(SOLO, 'w', newline='').write(UNIDAD_SOLO)
    for u in (PAS, SOLO):
        call('delphi_config', {'command': 'add-unit', 'project': DPROJ, 'path': u})
    check('preparacion: el proyecto compila', mc.como_json(call('delphi_build', {'project': DPROJ}, 600))
          .get('success') is True)
    call('delphi_hover', {'path': PAS, 'line': 37, 'character': 4}, 300)

    r = refs(22, 2)
    check('H1 references de la const Blocked: la declaracion del campo (9) no sale confirmada, sale '
          'rechazada', 9 not in lineas(r, 'confirmed') and 9 in lineas(r, 'rejected') and
          22 in lineas(r, 'confirmed'), str(r)[:700])

    j = mc.como_json(call('delphi_definition', {'path': PAS, 'line': 9, 'character': 4}, 300))
    check('H2 delphi_definition sobre la declaracion del campo Blocked: el campo (9)', j.get('line0') == 9,
          str(j)[:400])

    r = refs(25, 2)
    check('H3 references de la var global Tope: ninguna declaracion de campo Tope (12, 15)',
          not ({12, 15} & set(lineas(r, 'confirmed'))) and 25 in lineas(r, 'confirmed'), str(r)[:700])

    r = refs(12, 4)
    conf = lineas(r, 'confirmed')
    check('H4 references desde el campo Tope de la clase: el (12) y su uso C.Tope (38), no la var (25)',
          12 in conf and 38 in conf and 25 not in conf and 15 not in conf, str(r)[:700])

    j = mc.como_json(call('delphi_definition', {'path': PAS, 'line': 6, 'character': 4}, 300))
    check('H5 delphi_definition sobre un campo sin homonimo (Solo): el campo (6)', j.get('line0') == 6,
          str(j)[:400])

    malas = []
    for linea in (9, 12, 6):
        j = mc.como_json(call('delphi_definition', {'path': PAS, 'line': linea, 'character': 4,
                                                    'kind': 'declaration'}, 300))
        if j.get('line0') != linea:
            malas.append((linea, j.get('line0')))
    check('H8 delphi_definition kind=declaration sobre los campos Blocked (9), Tope (12) y Solo (6): el '
          'campo mismo', not malas, malas)

    r = refs(18, 2)
    check('H6 (control) references de TAdelantada: la declaracion adelantada (17) sale confirmada',
          {17, 18} <= set(lineas(r, 'confirmed')), str(r)[:700])

    for _ in range(3):  # el motor frio deja sin verificar, y rename lo niega por eso
        j = mc.como_json(call('delphi_rename_symbol', {'path': SOLO, 'line': 10, 'character': 2,
                                                       'newname': 'Llave'}, 300))
        if not j.get('unverifiedCount'):
            break
    j = mc.como_json(call('delphi_rename_symbol', {'path': SOLO, 'line': 10, 'character': 2,
                                                   'newname': 'Llave', 'mode': 'apply'}, 300))
    texto = open(SOLO, encoding='utf-8-sig').read().splitlines()
    b = mc.como_json(call('delphi_build', {'project': DPROJ}, 600))
    negado = j.get('applicable') is False and mc.tiene(' '.join(j.get('blockers') or []), 'RENAME-017')
    aplicado = j.get('applicable') is True and texto[10].strip() == 'Llave = 1;'
    check('H7 rename apply de la const Clave con un campo Clave sin usos: el campo NO se renombra (negado '
          'con RENAME-017 o aplicado sin el) y el proyecto compila',
          texto[6].strip() == 'Clave: Integer;' and (negado or aplicado) and b.get('success') is True,
          (str(j)[-900:], texto[6], texto[10], str(b)[:300]))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('la declaracion de un campo y un homonimo de la unidad 1231 (V181)')
