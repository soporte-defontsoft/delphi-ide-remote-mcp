# -*- coding: utf-8 -*-
"""Un parecido de OTRO proyecto lo juzga el motor de SU proyecto (B1 de la 1.28).

Hermes (luna y Qwen, 4-nov-2026) renombraba FormMain con dos proyectos de nombres por defecto, el
segundo en una subcarpeta del primero: rename lo negaba con RENAME-017, porque el motor del
objetivo resolvia los FormMain del otro proyecto a su propia declaracion y "podian ser este, visto
desde su proyecto". EL juez de eso es el motor del proyecto del parecido (medido el 5-nov: dice lo
mismo). Y el caso de campo del 25-ago-2026: una llamada de OTRO proyecto que el motor del objetivo
resuelve a otra definicion (una UAyuda de su proyecto con el mismo Doble) y el de su proyecto, que
es lo que compila, al objetivo.

  P1 (Hermes) rename preview de Doble en Uno: aplicable, sin RENAME-017 y con RENAME-024 por los
     Doble de Dos, que no salen en lookalikes (ROJA contra la 1.27.1: RENAME-017)
  P2 references de ese Doble: los dos de Dos en rejected, cada uno con su project (Dos.dproj), y
     rejectedByTheirProject 2
  P3 rename apply: escribe el UCalc de Uno, no toca el de Dos, y los dos proyectos compilan
  C1 (campo) references de Doble en Uno: la llamada de Tres\\UUsa sale CONFIRMADA con su project
     (Tres.dproj) (ROJA: rechazada, resuelta a la UAyuda de Uno)
  C2 rename preview: la llamada de Tres en changes, y RENAME-017 SOLO por los dos Doble de la UAyuda
     de Uno, del MISMO proyecto (un solo juez: la barrera sigue), que son los lookalikes
  T1 (al reves, medido en vivo el 5-nov) Tres compila SU copia de UCalc: el motor de Uno da su
     llamada a Doble por nuestra y el de Tres, por la suya. references: la llamada NO sale
     confirmada; sale en rejected con su project (ROJA contra el primer arreglo: confirmada)
  T2 rename apply: el UCalc de Uno renombrado, la llamada de Tres intacta, y Tres compila (ROJA:
     la renombraba, y Tres no compilaria)

Uso:  python tests/test_rename_su_proyecto_128.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('rename_su_proyecto_128')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='rename-su-proyecto', t=300)
call = srv.call

# una unidad con Doble en la linea 4 (0-based), columna 9: la declaracion del interface
DOBLE = ('unit %s;\n\ninterface\n\nfunction Doble(X: Integer): Integer;\n\nimplementation\n\n'
         'function Doble(X: Integer): Integer;\nbegin\n  Result := %s;\nend;\n\nend.\n')
AYUDA_TRES = 'unit UAyuda;\n\ninterface\n\nconst\n  Base = 1;\n\nimplementation\n\nend.\n'
USA = ('unit UUsa;\n\ninterface\n\nfunction Cuatro: Integer;\n\nimplementation\n\nuses\n  UCalc, UAyuda;\n\n'
       'function Cuatro: Integer;\nbegin\n  Result := Doble(Base + Base);\nend;\n\nend.\n')


def proyecto(nombre, carpeta):
    call('delphi_create', {'kind': 'project-console', 'name': nombre, 'dir': carpeta})
    return os.path.join(carpeta, nombre + '.dproj')


def unidad(dproj, nombre, contenido):
    call('delphi_create', {'kind': 'unit', 'name': nombre, 'project': dproj, 'content': contenido})


def compila(dproj):
    return mc.como_json(call('delphi_build', {'project': dproj}, 600)).get('success') is True


def preview(path):
    """rename de Doble, repetido mientras el motor (frio) deje algo sin verificar."""
    j = {}
    for _ in range(4):
        j = mc.como_json(call('delphi_rename_symbol', {'path': path, 'line': 4, 'character': 10,
                                                       'newname': 'Duplica'}, 300))
        if not j.get('unverifiedCount'):
            break
    return j


def refs(path):
    r = {}
    for _ in range(4):
        r = mc.como_json(call('delphi_references', {'path': path, 'line': 4, 'character': 10}, 300))
        if not r.get('unverified'):
            break
    return r


def de(hits, fichero):
    """Los aciertos de ese fichero (carpeta\\nombre, en minusculas: las rutas vuelven enmascaradas)."""
    return [h for h in hits if (h.get('path') or '').lower().endswith('\\' + fichero)]


def suyo(h, dproj):
    return (h.get('project') or '').lower().endswith(dproj)


try:
    # --- el caso de Hermes: Dos en una subcarpeta de Uno, cada uno con su Doble
    h = os.path.join(JAIL, 'h')
    UNO = proyecto('Uno', h)
    DOS = proyecto('Dos', os.path.join(h, 'Dos'))
    unidad(UNO, 'UCalc', DOBLE % ('UCalc', 'X * 2'))
    unidad(DOS, 'UCalc', DOBLE % ('UCalc', 'X + X'))
    PAS = os.path.join(h, 'UCalc.pas')
    PAS_DOS = os.path.join(h, 'Dos', 'UCalc.pas')
    check('preparacion: Uno y Dos compilan', compila(UNO) and compila(DOS))

    j = preview(PAS)
    bl = ' '.join(j.get('blockers') or [])
    av = ' '.join(j.get('warnings') or [])
    check('P1 rename de Doble en Uno: aplicable, sin RENAME-017 y con RENAME-024 por los de Dos (fuera de '
          'lookalikes)', j.get('applicable') is True and not mc.es(bl, 'SR_RENAME_HOMONYMS_FMT') and
          mc.es(av, 'SN_RENAME_HOMONIMOS_DE_SU_PROYECTO_FMT') and not j.get('lookalikes'), str(j)[:900])

    r = refs(PAS)
    dos = de(mc.aciertos(r, 'rejected'), 'dos\\ucalc.pas')
    check('P2 references: los dos Doble de Dos en rejected, cada uno con su project, y '
          'rejectedByTheirProject 2', len(dos) == 2 and all(suyo(x, 'dos.dproj') for x in dos) and
          r.get('rejectedByTheirProject') == 2, str(r)[:900])

    j = mc.como_json(call('delphi_rename_symbol', {'path': PAS, 'line': 4, 'character': 10,
                                                   'newname': 'Duplica', 'mode': 'apply'}, 300))
    uno_txt = open(PAS, encoding='utf-8-sig').read()
    dos_txt = open(PAS_DOS, encoding='utf-8-sig').read()
    check('P3 apply: el UCalc de Uno renombrado, el de Dos intacto, y los dos compilan',
          uno_txt.count('Duplica') == 2 and 'Doble' not in uno_txt and dos_txt.count('Doble') == 2 and
          'Duplica' not in dos_txt and compila(UNO) and compila(DOS), str(j)[-600:])

    # --- el caso de campo: Tres (subcarpeta) compila el UCalc de Uno, y la UAyuda que ve su UUsa es la
    # suya, sin Doble; el motor de Uno le resuelve UAyuda a la de Uno, que si tiene uno
    c = os.path.join(JAIL, 'c')
    UNO_C = proyecto('Uno', c)
    TRES = proyecto('Tres', os.path.join(c, 'Tres'))
    unidad(UNO_C, 'UCalc', DOBLE % ('UCalc', 'X * 2'))
    unidad(UNO_C, 'UAyuda', DOBLE % ('UAyuda', 'X + X'))
    PAS_C = os.path.join(c, 'UCalc.pas')
    call('delphi_config', {'command': 'add-unit', 'project': TRES, 'path': PAS_C})
    unidad(TRES, 'UAyuda', AYUDA_TRES)
    unidad(TRES, 'UUsa', USA)
    check('preparacion: Uno y Tres compilan', compila(UNO_C) and compila(TRES))

    r = refs(PAS_C)
    usa = de(mc.aciertos(r, 'confirmed'), 'tres\\uusa.pas')
    check('C1 references: la llamada de Tres\\UUsa sale CONFIRMADA, con su project (Tres.dproj)',
          len(usa) == 1 and suyo(usa[0], 'tres.dproj') and not de(mc.aciertos(r, 'rejected'), 'tres\\uusa.pas'),
          str(r)[:900])

    j = preview(PAS_C)
    look = mc.aciertos(j, 'lookalikes')
    check('C2 rename: la llamada de Tres en changes, y RENAME-017 solo por los dos Doble de la UAyuda de Uno',
          len(de(mc.aciertos(j, 'changes'), 'tres\\uusa.pas')) == 1 and j.get('applicable') is False and
          mc.es(' '.join(j.get('blockers') or []), 'SR_RENAME_HOMONYMS_FMT') and len(look) == 2 and
          len(de(look, 'c\\uayuda.pas')) == 2, str(j)[:900])
    # --- al reves: Tres (subcarpeta) compila su PROPIA copia de UCalc; el motor de Uno le resuelve
    # UCalc a la de Uno
    t = os.path.join(JAIL, 't')
    UNO_T = proyecto('Uno', t)
    TRES_T = proyecto('Tres', os.path.join(t, 'Tres'))
    unidad(UNO_T, 'UCalc', DOBLE % ('UCalc', 'X * 2'))
    unidad(TRES_T, 'UCalc', DOBLE % ('UCalc', 'X * 3'))
    unidad(TRES_T, 'UAyuda', AYUDA_TRES)
    unidad(TRES_T, 'UUsa', USA)
    PAS_T = os.path.join(t, 'UCalc.pas')
    USA_T = os.path.join(t, 'Tres', 'UUsa.pas')
    check('preparacion: Uno y Tres (con su UCalc) compilan', compila(UNO_T) and compila(TRES_T))

    r = refs(PAS_T)
    rej = de(mc.aciertos(r, 'rejected'), 'tres\\uusa.pas')
    check('T1 references: la llamada de Tres, que compila su UCalc, NO sale confirmada: sale en rejected '
          'con su project', not de(mc.aciertos(r, 'confirmed'), 'tres\\uusa.pas') and len(rej) == 1 and
          suyo(rej[0], 'tres.dproj'), str(r)[:900])

    preview(PAS_T)  # los motores calientes antes de escribir (preview ya repite)
    j = mc.como_json(call('delphi_rename_symbol', {'path': PAS_T, 'line': 4, 'character': 10,
                                                   'newname': 'Duplica', 'mode': 'apply'}, 300))
    uno_txt = open(PAS_T, encoding='utf-8-sig').read()
    usa_txt = open(USA_T, encoding='utf-8-sig').read()
    check('T2 apply: el UCalc de Uno renombrado, la llamada de Tres intacta, y los dos compilan',
          uno_txt.count('Duplica') == 2 and 'Doble(Base + Base)' in usa_txt and 'Duplica' not in usa_txt and
          compila(UNO_T) and compila(TRES_T), str(j)[-600:])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('un parecido de otro proyecto lo juzga el motor de su proyecto 1.28 (B1)')
