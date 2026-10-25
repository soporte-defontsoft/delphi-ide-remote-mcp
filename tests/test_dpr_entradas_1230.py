# -*- coding: utf-8 -*-
r"""Las entradas del uses de un .dpr y sus CreateForm, por UN escritor y UN lector
(V17-6g de la 1.23).

Medido en produccion (r1222bj) el 25-oct-2026:
  - add-unit de una unit en una carpeta con apostrofo (David's units) escribia
    in 'David's units\UFicha.pas' sin doblar la comilla: el .dpr no compilaba
    (E2029 + E2052) y la tool decia ADDED;
  - remove-unit de esa entrada leia la ruta hasta la comilla ('David'): dejaba su
    DCCReference en el .dproj y el aviso nombraba "David";
  - con una comilla sin cerrar, el lector de la clausula no veia su ';', y
    reescribirla se llevo el begin y Application.Initialize diciendo REMOVED;
  - un CreateForm partido en dos lineas no se quitaba con su unit.

  D1 add-unit en "David's units": la comilla doblada, y el .dpr compila
  D2 remove-unit de esa: fuera del .dpr Y del .dproj, y el aviso nombra el fichero
  D3 una clausula con una comilla sin cerrar: USES-026, y el .dpr no cambia
  D4 un CreateForm partido en dos lineas se va con su unit, y el .dpr compila
  D5 control: el .dpr de un proyecto nuevo, el de siempre

Rojo contra r1222bj: D1-D4.

Uso:  python tests/test_dpr_entradas_1230.py [exe]
"""
import os, re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('dpr_entradas_1230')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='dpr-entradas', t=300)


def cfg(**kw):
    return s.call('delphi_config', kw, t=300)


def escribe(ruta, texto):
    with open(ruta, 'wb') as f:
        f.write(b'\xef\xbb\xbf' + texto.encode('utf-8'))


try:
    P = os.path.join(JAIL, 'p')
    s.call('delphi_create', {'kind': 'project-vcl', 'name': 'Prj', 'dir': P})
    DPR, DPROJ = os.path.join(P, 'Prj.dpr'), os.path.join(P, 'Prj.dproj')
    dpr = ORIGINAL = mc.lee(DPR)
    check('D5 control: el .dpr de un proyecto nuevo, el de siempre (su entrada y su CreateForm)',
          "UMain in 'UMain.pas' {FormMain};" in dpr and
          'Application.CreateForm(TFormMain, FormMain);' in dpr, dpr)

    # --- D1, D2 -----------------------------------------------------------------
    DIR = os.path.join(P, "David's units")
    s.call('delphi_create', {'kind': 'unit', 'name': 'UFicha', 'dir': DIR})
    r = cfg(command='add-unit', project=DPROJ, path=os.path.join(DIR, 'UFicha.pas'))
    dpr = mc.lee(DPR)
    ok, err = mc.build_ok(s.call, DPROJ)
    check("D1 add-unit en David's units: la ruta con la comilla doblada, y el .dpr compila",
          "UFicha in 'David''s units\\UFicha.pas'" in dpr and ok, (r[:200], dpr, err))
    r = cfg(command='remove-unit', project=DPROJ, path=os.path.join(DIR, 'UFicha.pas'))
    check('D2 remove-unit de esa: fuera del .dpr y del .dproj, y el aviso nombra el fichero',
          'UFicha' not in mc.lee(DPR) and 'UFicha' not in mc.lee(DPROJ) and 'UFicha.pas' in r, r[:300])

    # --- D3 ---------------------------------------------------------------------
    # desde el .dpr del proyecto nuevo: lo de antes puede haberlo dejado roto
    roto = ORIGINAL.replace("UMain in 'UMain.pas' {FormMain};",
                            "UMain in 'UMain.pas' {FormMain},\r\n  URota in 'Rota's.pas';")
    assert roto != ORIGINAL, ORIGINAL
    escribe(DPR, roto)
    r = cfg(command='remove-unit', project=DPROJ, path=os.path.join(P, 'UMain.pas'))
    check('D3 una clausula con una comilla sin cerrar: USES-026 y el .dpr no cambia (su begin sigue)',
          mc.rechazado(r) and mc.es(r, 'SR_USES_ENTRADA_ILEGIBLE_FMT') and mc.lee(DPR) == roto, r[:300])
    escribe(DPR, ORIGINAL)

    # --- D4 ---------------------------------------------------------------------
    s.call('delphi_create', {'kind': 'form-vcl', 'name': 'UFicha2', 'project': DPR})
    dpr = mc.lee(DPR)
    cf = [m for m in re.finditer(r'Application\.CreateForm\((T\w+), (\w+)\);', dpr) if m.group(1) != 'TFormMain']
    if len(cf) != 1:
        check('D4 fixture: el form nuevo trae su CreateForm', False, dpr)
    else:
        escribe(DPR, dpr.replace(cf[0].group(0), 'Application.CreateForm(%s,\r\n    %s);' % (cf[0].group(1),
                                                                                   cf[0].group(2))))
        r = cfg(command='remove-unit', project=DPROJ, path=os.path.join(P, 'UFicha2.pas'))
        dpr = mc.lee(DPR)
        ok, err = mc.build_ok(s.call, DPROJ)
        check('D4 un CreateForm partido en dos lineas se va con su unit, y el .dpr compila',
              cf[0].group(1) not in dpr and cf[0].group(2) not in dpr and 'Application.Run;' in dpr and ok,
              (r[:200], dpr, err))
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('entradas del .dpr 1.23')
