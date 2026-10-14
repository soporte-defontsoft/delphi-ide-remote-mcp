# -*- coding: utf-8 -*-
"""H6 de Hermes (1.18.2, punto 9; informe 20261013-123547, medido el 13-oct con
las sondas sonda_tanda_dsgn021 y sonda_changeset_dsgn021): el juicio del FORM
(el parser del IDE, las propiedades, el enlace con su clase) salia del estado
INTERMEDIO de una tanda y de un changeset. Un bloque quitado y puesto mas abajo,
o un renombre .dfm + .pas por changeset (la forma que recomendamos), daban
DSGN-021 "Fix it before deploying" de un form que acababa limpio. Ahora el
juicio es del fichero entero, como el de la estructura: las entradas no lo
hacen y quien agrupa lo hace UNA vez sobre lo escrito; el changeset juzga cada
form que toco, por si mismo o por su unidad.

  J1 tanda que quita el bloque de Panel1 y lo pone tras Label1: sin DSGN-021
     (ROJO en produccion)
  J2 changeset que renombra Panel1 -> Panel2 en el .dfm y en el .pas: sin
     DSGN-021 (ROJO en produccion)
  J3 changeset que solo toca el .pas y le quita el campo a Panel1: DSGN-021
     (el enlace se rompe desde la unidad; ROJO en produccion: no se juzgaba)
  J4 control: una tanda que deja el form roto (quita el bloque y nada mas)
     sigue diciendo DSGN-021, UNA vez
  J5 control: un delphi_edit suelto sobre el .dfm sigue juzgandolo

Y el juicio de lo que una escritura ALCANZA (JuicioDeLoEscrito, punto 7 y lo
visto en vivo tras H6):
  J6 el changeset de J3 (solo el .pas) no dice EDIT-084 "edited" del .dfm, que
     no toco (ROJO en produccion tras H6, medido en vivo)
  J7 un delphi_edit SUELTO del .pas que quita el campo: DSGN-021 del form de la
     unidad (ROJO en produccion: no decia nada)
  J8 una tanda del .pas que quita el campo y lo vuelve a poner: sin DSGN-021 (el
     juicio, al final y una vez, tambien en un .pas). GUARDA: con la tanda sin
     aplazar (mutante) sigue verde, porque el aviso de cada entrada lleva la
     ruta del form delante y AvisosDelMotor solo recoge lo que empieza por ***
  J9 control: un delphi_edit del .pas que no toca el enlace: sin DSGN-021

Y solo lo que se ESCRIBIO (W2 del revisor de cierre, medido), sobre un form que
YA estaba roto (el .pas sin el campo de Panel1):
  J10 una tanda del .dfm sin ningun cambio: dice que no cambio nada y no juzga
      (ROJO en produccion: EDIT-114 y despues EDIT-084 'edited' y DSGN-021)
  J11 un changeset con un paso real en otro fichero y uno sin cambio en ese
      .pas: no juzga el form de una unidad que no se toco
  J12 el form en BINARIO (designer to-binary) y un delphi_edit del .pas que le
      quita el campo: DSGN-021 (W4 del revisor de cierre, medido; ROJO en
      produccion: el juicio leia el binario como texto y no decia nada)

Uso:  python tests/test_juicio_final_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('juicio_final_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

BLOQUE_P = '  object Panel1: TPanel\n    Left = 8\n    Top = 8\n  end'
BLOQUE_L = '  object Label1: TLabel\n    Left = 8\n    Top = 40\n  end'


def par(nombre):
    d = os.path.join(JAIL, nombre)
    os.makedirs(d)
    pas = os.path.join(d, 'Unit1.pas')
    dfm = os.path.join(d, 'Unit1.dfm')
    with open(pas, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write('unit Unit1;\n\ninterface\n\nuses\n  Vcl.Forms, Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls,'
                ' System.Classes;\n\ntype\n  TForm1 = class(TForm)\n    Panel1: TPanel;\n    Label1: TLabel;\n'
                '  end;\n\nvar\n  Form1: TForm1;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n')
    with open(dfm, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write('object Form1: TForm1\n  Left = 0\n  Top = 0\n  Caption = \'Form1\'\n' + BLOQUE_P + '\n' +
                BLOQUE_L + '\nend\n')
    return pas, dfm


def par_roto(nombre):
    """El par de par(), con el .pas SIN el campo de Panel1: el form ya roto."""
    pas, dfm = par(nombre)
    t = open(pas, encoding='utf-8').read().replace('    Panel1: TPanel;\n', '')
    with open(pas, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write(t)
    return pas, dfm


def dsgn021(r):
    return r.count(mc.catalogo()['SN_DESIGNER_BINDING_LINT_HEADER'][:40])


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='juicio-final', t=240)
try:
    pas, dfm = par('j1')
    r = srv.call('delphi_edit', {'path': dfm, 'edits': [
        {'old': BLOQUE_P, 'new': ''},
        {'old': BLOQUE_L, 'new': BLOQUE_L + '\n' + BLOQUE_P}]}, t=240)
    check('J1 tanda que mueve el bloque de Panel1: sin DSGN-021 (el form final esta limpio)',
          not mc.rechazado(r) and dsgn021(r) == 0, r[:500])

    pas, dfm = par('j2')
    cid = mc.id_changeset(srv.call('delphi_changeset', {'command': 'begin'}))
    srv.call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'edit', 'path': dfm,
                                  'old': '  object Panel1: TPanel', 'new': '  object Panel2: TPanel'})
    srv.call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'edit', 'path': pas,
                                  'old': '    Panel1: TPanel;', 'new': '    Panel2: TPanel;'})
    srv.call('delphi_changeset', {'command': 'preview', 'id': cid})
    r = srv.call('delphi_changeset', {'command': 'commit', 'id': cid}, t=240)
    check('J2 changeset que renombra Panel1 -> Panel2 en .dfm y .pas: sin DSGN-021',
          not mc.rechazado(r) and dsgn021(r) == 0, r[:600])

    pas, dfm = par('j3')
    cid = mc.id_changeset(srv.call('delphi_changeset', {'command': 'begin'}))
    srv.call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'edit', 'path': pas,
                                  'old': '    Panel1: TPanel;', 'new': '    // sin campo'})
    srv.call('delphi_changeset', {'command': 'preview', 'id': cid})
    r = srv.call('delphi_changeset', {'command': 'commit', 'id': cid}, t=240)
    check('J3 changeset que solo le quita el campo al .pas: DSGN-021 (el enlace roto desde la unidad)',
          not mc.rechazado(r) and dsgn021(r) == 1, r[:600])
    check('J6 ...y no dice EDIT-084 ("edited") del .dfm, que el lote no toco',
          not mc.rechazado(r) and 'EDIT-084' not in r, r[:600])

    pas, dfm = par('j7')
    r = srv.call('delphi_edit', {'path': pas, 'old': '    Panel1: TPanel;', 'new': '    // sin campo'}, t=240)
    check('J7 un delphi_edit SUELTO del .pas que quita el campo: DSGN-021 del form de su unidad',
          not mc.rechazado(r) and dsgn021(r) == 1 and 'Unit1.dfm' in r, r[:600])

    pas, dfm = par('j8')
    r = srv.call('delphi_edit', {'path': pas, 'edits': [
        {'old': '    Panel1: TPanel;', 'new': '    // sin campo'},
        {'old': '    Label1: TLabel;', 'new': '    Label1: TLabel;\n    Panel1: TPanel;'}]}, t=240)
    check('J8 una tanda del .pas que quita el campo y lo vuelve a poner: sin DSGN-021',
          not mc.rechazado(r) and dsgn021(r) == 0, r[:600])

    pas, dfm = par('j9')
    r = srv.call('delphi_edit', {'path': pas, 'old': "  Form1: TForm1;", 'new': "  Form1: TForm1; // la form"},
                 t=240)
    check('J9 control: un delphi_edit del .pas que no toca el enlace: sin DSGN-021',
          not mc.rechazado(r) and dsgn021(r) == 0, r[:600])

    pas, dfm = par_roto('j10')
    antes = open(dfm, 'rb').read()
    r = srv.call('delphi_edit', {'path': dfm, 'edits': [
        {'old': "  Caption = 'Form1'", 'new': "  Caption = 'Form1'"},
        {'old': '    Top = 40', 'new': '    Top = 40'}]}, t=240)
    check('J10 una tanda SIN cambios sobre un form ya roto: dice que no cambio nada y no lo juzga',
          'EDIT-114' in r and 'EDIT-084' not in r and dsgn021(r) == 0 and open(dfm, 'rb').read() == antes,
          r[:600])

    pas, dfm = par_roto('j11')
    nota = os.path.join(os.path.dirname(pas), 'notas.txt')
    open(nota, 'w').write('uno\n')
    cid = mc.id_changeset(srv.call('delphi_changeset', {'command': 'begin'}))
    srv.call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'edit', 'path': nota,
                                  'old': 'uno', 'new': 'dos'})
    srv.call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'edit', 'path': pas,
                                  'old': '    Label1: TLabel;', 'new': '    Label1: TLabel;'})
    srv.call('delphi_changeset', {'command': 'preview', 'id': cid})
    r = srv.call('delphi_changeset', {'command': 'commit', 'id': cid}, t=240)
    check('J11 un changeset con un paso sin cambio en el .pas: no juzga el form de esa unidad',
          not mc.rechazado(r) and dsgn021(r) == 0 and open(nota).read() == 'dos\n', r[:600])

    pas, dfm = par('j12')
    rb = srv.call('delphi_designer', {'command': 'to-binary', 'path': dfm}, t=240)
    r = srv.call('delphi_edit', {'path': pas, 'old': '    Panel1: TPanel;', 'new': '    // sin campo'}, t=240)
    check('J12 con el form en BINARIO, quitarle el campo en el .pas: DSGN-021 del form',
          not mc.rechazado(rb) and open(dfm, 'rb').read()[:1] == b'\xff' and not mc.rechazado(r) and
          dsgn021(r) == 1, (rb[:200], r[:600]))

    pas, dfm = par('j4')
    r = srv.call('delphi_edit', {'path': dfm, 'edits': [
        {'old': BLOQUE_P, 'new': ''},
        {'old': "  Caption = 'Form1'", 'new': "  Caption = 'Form1b'"}]}, t=240)
    check('J4 control: una tanda que deja el form roto dice DSGN-021, una vez',
          not mc.rechazado(r) and dsgn021(r) == 1, r[:500])

    pas, dfm = par('j5')
    r = srv.call('delphi_edit', {'path': dfm, 'old': '  object Panel1: TPanel', 'new': '  object Panel9: TPanel'},
                 t=240)
    check('J5 control: un delphi_edit suelto del .dfm lo sigue juzgando (DSGN-021)',
          not mc.rechazado(r) and dsgn021(r) == 1, r[:500])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('juicio del form al final de la tanda y del changeset 1182 (H6)')
