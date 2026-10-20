# -*- coding: utf-8 -*-
"""delphi_edit INSERT con VARIAS rutinas en code (1.21.1, EDIT-129). Hermes, en la
validacion de la 1.21.1, mando un insert=metodo con dos procedimientos: la
herramienta declaro y cualifico el primero y escribio el segundo TAL CUAL - una
rutina global sin declarar que no compila (E2003) -, diciendo "the tool did BOTH
halves". Con insert=rutina-global y visible=true pasaba lo mismo: solo el primero
iba al interface. Medido en produccion el 20-oct-2026. Las rutinas las cuenta EL
lector de la casa (Lsp.PascalDecl): una anidada va dentro de la suya.

  I1 insert=metodo con dos rutinas: EDIT-129 con sus dos nombres, y nada escrito
  I2 insert=rutina-global visible=true con dos: EDIT-129, nada escrito
  I3 control: una rutina con una LOCAL anidada se inserta (es una)
  I4 control: un metodo solo, como siempre (las dos mitades)

I1 e I2 son ROJAS contra 1.21.0 (pasar su exe como argumento).

Uso:  python tests/test_insert_una_rutina_1211.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('insert_una_rutina_1211')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
U = os.path.join(JAIL, 'UDos.pas')
ORIGINAL = ('unit UDos;\r\n\r\ninterface\r\n\r\ntype\r\n  TCuenta = class\r\n  private\r\n'
            '    FCounter: Integer;\r\n  public\r\n  end;\r\n\r\nimplementation\r\n\r\nend.\r\n')
open(U, 'w', encoding='utf-8', newline='').write(ORIGINAL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='insert-una-rutina', t=120)
DOS_METODOS = ('procedure CountUp;\nbegin\n  FCounter := FCounter + 1;\nend;\n\n'
               'procedure ResetCount;\nbegin\n  FCounter := 0;\nend;')
DOS_GLOBALES = 'function Uno: Integer;\nbegin\n  Result := 1;\nend;\n\nfunction Dos: Integer;\nbegin\n  Result := 2;\nend;'


def texto():
    return open(U, encoding='utf-8-sig').read()


try:
    r = S.call('delphi_edit', {'path': U, 'insert': 'metodo', 'inclass': 'TCuenta', 'visibility': 'public',
                               'code': DOS_METODOS})
    check('I1 insert=metodo con dos rutinas: EDIT-129 con sus nombres',
          mc.es(r, 'SR_EDIT_INSERT_UNA_RUTINA_FMT') and 'CountUp' in r and 'ResetCount' in r, r[:300])
    check('I1b ...y nada escrito', open(U, 'rb').read() == ORIGINAL.encode('utf-8'), texto()[:300])

    r = S.call('delphi_edit', {'path': U, 'insert': 'rutina-global', 'visible': True, 'code': DOS_GLOBALES})
    check('I2 rutina-global visible=true con dos: EDIT-129', mc.es(r, 'SR_EDIT_INSERT_UNA_RUTINA_FMT'), r[:300])
    check('I2b ...y nada escrito', open(U, 'rb').read() == ORIGINAL.encode('utf-8'))

    r = S.call('delphi_edit', {'path': U, 'insert': 'rutina-global', 'code':
                               'function Suma3: Integer;\n\n  function Uno: Integer;\n  begin\n    Result := 1;\n  end;\n\n'
                               'begin\n  Result := Uno + 2;\nend;'})
    check('I3 una rutina con una local anidada se inserta (es UNA)',
          not mc.rechazado(r) and 'function Suma3' in texto() and 'function Uno' in texto(), r[:300])

    r = S.call('delphi_edit', {'path': U, 'insert': 'metodo', 'inclass': 'TCuenta', 'visibility': 'public',
                               'code': 'procedure CountUp;\nbegin\n  FCounter := FCounter + 1;\nend;'})
    check('I4 un metodo solo, como siempre: declaracion e implementacion',
          not mc.rechazado(r) and 'procedure CountUp;' in texto() and 'procedure TCuenta.CountUp;' in texto(), r[:300])
finally:
    S.cierra()

mc.borra(BASE)
mc.fin('insert una rutina 1.21.1')
