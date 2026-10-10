# -*- coding: utf-8 -*-
"""Un sustituto SUELTO que YA esta en el disco (1.18.1, revisor de version).

La 1.18.1 niega en todo escritor medio caracter del texto NUEVO (EncodeText
estricto). Pero el juez de la ida y vuelta (BytesVuelvenIgual) y la
escritura del fichero entero codificaban tambien lo que ya estaba: un UTF-16
con un D800 suelto en una linea que nadie toca dejo de editarse por ningun
escritor (EDIT-038), y delphi_move lo movia sin poder reescribir su cabecera
(MOVE-016), cuando la 1.18.0 lo editaba conservando sus bytes. Solo en
UTF-16: el lector de los demas nunca da un suelto (lee U+FFFD).

  S1  delphi_read de un UTF-16 con un suelto: sin READ-007; delphi_edit de
      OTRA linea: se escribe y el fichero queda byte a byte igual salvo esa
      linea
  S2  ...y lo mismo con delphi_textedit, adduses y una tanda (edits)
  S3  el changeset aplica un edit en ese fichero
  S4  delphi_move de la unit: la cabecera se reescribe y el suelto se queda
  S5  designer set en un .dfm UTF-16 con un suelto en el Caption; y lo que
      pregunta al juez del orden (set before=, insert): su copia temporal
      se codificaba estricta y daba EDIT-078 "nothing written" (revisor
      propio de la 1.18.1)
  S6  el texto NUEVO sigue negandose: un segundo suelto igual, y uno
      distinto, EDIT-078 sin escribir nada
  S7  control: un UTF-8 con BOM y una secuencia CESU (se lee U+FFFD) sigue
      siendo EDIT-038, sin escribir

Uso:  python tests/test_sueltos_disco_1181.py [exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('sueltos1181')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='sueltos1181', t=400)
D800 = '\ud800'


def u16(texto):
    """UTF-16 LE con BOM y CRLF; un sustituto suelto del texto va tal cual."""
    return b'\xff\xfe' + texto.replace('\n', '\r\n').encode('utf-16-le', 'surrogatepass')


def de16(b):
    return b[2:].decode('utf-16-le', 'surrogatepass').replace('\r\n', '\n')


def escribe(ruta, b):
    with open(ruta, 'wb') as f:
        f.write(b)


def lee(ruta):
    with open(ruta, 'rb') as f:
        return f.read()


UNIT = 'unit U16;\n\ninterface\n\n// suelto: ' + D800 + ' aqui\nconst A = 1;\n\nimplementation\n\nend.\n'

try:
    # ---- S1 ----
    U = os.path.join(JAIL, 'U16.pas')
    escribe(U, u16(UNIT))
    r = srv.call('delphi_read', {'path': U})
    check('S1 delphi_read de un UTF-16 con un suelto: sin READ-007 (sus bytes vuelven iguales)',
          not mc.fallo(r) and not mc.es(r, 'SN_READ_BYTES_NO_VUELVEN_FMT'), r[:300])
    r = srv.call('delphi_edit', {'path': U, 'old': 'const A = 1;', 'new': 'const A = 2;'})
    check('S1 delphi_edit de OTRA linea: se escribe, y el fichero es el mismo salvo esa linea (el suelto, en sus bytes)',
          not mc.fallo(r) and lee(U) == u16(UNIT.replace('A = 1', 'A = 2')), r[:300])

    # ---- S2 ----
    T = os.path.join(JAIL, 'notas.txt')
    TXT = 'uno ' + D800 + '\ndos\n'
    escribe(T, u16(TXT))
    r = srv.call('delphi_textedit', {'path': T, 'old': 'dos', 'new': 'tres'})
    check('S2 delphi_textedit de otra linea: se escribe y el suelto se queda',
          not mc.fallo(r) and lee(T) == u16(TXT.replace('dos', 'tres')), r[:300])
    r = srv.call('delphi_edit', {'path': U, 'adduses': 'System.SysUtils', 'section': 'interface'})
    t = de16(lee(U))
    check('S2 ...adduses en esa unit, y el suelto se queda',
          not mc.fallo(r) and 'System.SysUtils' in t and '// suelto: ' + D800 + ' aqui' in t, r[:300])
    r = srv.call('delphi_edit', {'path': U, 'edits': [{'old': 'const A = 2;', 'new': 'const A = 3;'}]})
    t = de16(lee(U))
    check('S2 ...y una tanda (edits)',
          not mc.fallo(r) and 'A = 3' in t and '// suelto: ' + D800 + ' aqui' in t, r[:300])

    # ---- S3 ----
    cid = mc.id_changeset(srv.call('delphi_changeset', {'command': 'begin'}))
    srv.call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'edit', 'path': U,
                                  'old': 'const A = 3;', 'new': 'const A = 4;'})
    p = srv.call('delphi_changeset', {'command': 'preview', 'id': cid})
    c = srv.call('delphi_changeset', {'command': 'commit', 'id': cid})
    t = de16(lee(U))
    check('S3 el changeset aplica un edit en ese fichero, y el suelto se queda',
          mc.abre(c, 'SN_CHANGESET_COMMITTED_FMT') and 'A = 4' in t and D800 in t,
          '%s | %s' % (p[:200], c[:200]))

    # ---- S4 ----
    DOS = os.path.join(JAIL, 'Dos16.pas')
    r = srv.call('delphi_move', {'path': U, 'dest': DOS})
    t = de16(lee(DOS)) if os.path.exists(DOS) else ''
    check('S4 delphi_move de la unit: la cabecera dice unit Dos16 y el suelto se queda (daba MOVE-016)',
          not mc.fallo(r) and t.startswith('unit Dos16;') and D800 in t, r[:300])

    # ---- S5 ----
    F = os.path.join(JAIL, 'F16.dfm')
    FORM = ("object Form1: TForm1\n  Left = 0\n  Top = 0\n  Caption = 'ab" + D800 + "cd'\n"
            "  ClientHeight = 200\n  ClientWidth = 300\n"
            "  object Label0: TLabel\n    Left = 8\n    Top = 8\n    Caption = 'cero'\n  end\n"
            "  object Label1: TLabel\n    Left = 8\n    Top = 30\n    Caption = 'uno'\n  end\nend\n")
    escribe(F, u16(FORM))
    with open(os.path.join(JAIL, 'F16.pas'), 'w', encoding='utf-8', newline='\r\n') as f:
        f.write('unit F16;\n\ninterface\n\nuses\n  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, System.Classes;\n\n'
                'type\n  TForm1 = class(TForm)\n    Label0: TLabel;\n    Label1: TLabel;\n  end;\n\n'
                'var\n  Form1: TForm1;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n')
    r = srv.call('delphi_designer', {'command': 'set', 'path': F, 'component': 'Form1',
                                     'prop': 'Left', 'value': '10'}, t=400)
    t = de16(lee(F))
    check('S5 designer set en un .dfm UTF-16 con un suelto en el Caption: se escribe y el suelto se queda',
          not mc.fallo(r) and 'Left = 10' in t and "Caption = 'ab" + D800 + "cd'" in t, r[:400])
    r = srv.call('delphi_designer', {'command': 'set', 'path': F, 'component': 'Label1', 'before': 'Label0'}, t=400)
    t = de16(lee(F))
    check('S5 ...set before= (pregunta al juez del orden): se reordena, sin EDIT-078, y el suelto se queda',
          not mc.fallo(r) and not mc.es(r, 'SR_EDIT_CARACTERES_NO_CABEN_FMT')
          and t.find('object Label1') < t.find('object Label0') and D800 in t, r[:400])
    r = srv.call('delphi_designer', {'command': 'insert', 'path': F, 'classname': 'TButton'}, t=400)
    t = de16(lee(F))
    # ...y que el juez CONTESTO: sin DSGN-145 ("el juez no contesto, va el ultimo"),
    # que pasaba tambien sin los renderizadores (segunda ronda de la 1.18.1)
    check('S5 ...insert: se escribe, el juez del orden contesta (sin DSGN-145 ni EDIT-078) y el suelto se queda',
          not mc.fallo(r) and not mc.es(r, 'SR_EDIT_CARACTERES_NO_CABEN_FMT') and not mc.es(r, 'SN_DESIGNER_ULTIMO_SIN_JUEZ_FMT')
          and 'TButton' in t and D800 in t, r[:400])

    # ---- S6 ----
    antes = lee(DOS)
    r1 = srv.call('delphi_edit', {'path': DOS, 'old': 'const A = 4;', 'new': 'const A = 5; // ' + D800})
    r2 = srv.call('delphi_edit', {'path': DOS, 'old': 'const A = 4;', 'new': 'const A = 5; // \udc00'})
    check('S6 el texto NUEVO sigue negandose: otro suelto igual y uno distinto, EDIT-078 sin escribir',
          mc.abre(r1, 'SR_EDIT_CARACTERES_NO_CABEN_FMT') and mc.abre(r2, 'SR_EDIT_CARACTERES_NO_CABEN_FMT')
          and lee(DOS) == antes, '%s | %s' % (r1[:200], r2[:200]))

    # ---- S7 ----
    C8 = os.path.join(JAIL, 'Cesu.pas')
    CESU = b'\xef\xbb\xbfunit Cesu;\r\n\r\ninterface\r\n\r\n// \xed\xa0\x80\r\nconst A = 1;\r\n\r\nimplementation\r\n\r\nend.\r\n'
    escribe(C8, CESU)
    r = srv.call('delphi_edit', {'path': C8, 'old': 'const A = 1;', 'new': 'const A = 2;'})
    check('S7 control: un UTF-8 con BOM y una secuencia CESU sigue siendo EDIT-038, sin escribir',
          mc.abre(r, 'SR_EDIT_BYTES_NO_VUELVEN_FMT') and lee(C8) == CESU, r[:300])
finally:
    srv.mata()

try:
    mc.fin('sueltos en disco 1181 battery')  # sys.exit: la carpeta se borra en el finally
finally:
    mc.borra(BASE)
