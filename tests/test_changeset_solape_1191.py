# -*- coding: utf-8 -*-
"""delphi_changeset: el preview ve lo que el commit va a rechazar por SOLAPE
(1.19.1; Hermes, 15-oct-2026, informe 083258).

Cada ancla se resuelve contra el fichero de ANTES del lote, y la descripcion de la
tool lo dice: "an edit cannot anchor on a line an earlier edit of it writes". El
preview no lo comprobaba: edit de la linea 17 + delete-line de la linea 17 daba
CHSET-023 limpio con unresolved 0, y el commit caia en CHSET-026 (rollback
completo). Medido contra 1bdb4d7.

  S1 la secuencia de Hermes (edit 17, create, delete-line 17): el preview la da
     por no resuelta, nombra la linea y la operacion 1, y no hay commit posible
  S2 dos edits que anclan en la misma linea: el segundo, no resuelto
  S3 control: edit de la linea 17 y delete-line de OTRA linea en blanco: limpio,
     y el commit aplica las dos

Uso:  python tests/test_changeset_solape_1191.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('changeset_solape_1191')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
U = os.path.join(JAIL, 'UProbe.pas')
NUEVO = os.path.join(JAIL, 'UNueva.pas')
LARGA = '  Result2 := 123456789012345678; // longline'
FUENTE = ['unit UProbe;', '', 'interface', '', 'function Probe: Integer;', '', 'implementation', '',
          'function Probe: Integer;', 'var', '  Result2: Int64;', 'begin', '  Result := 0;',
          '  Result2 := 0;', '  if Result2 > 0 then', '    Exit;', LARGA,
          '  Result := Integer(Result2 and $FF);', 'end;', '', 'end.', '']


def escribe():
    open(U, 'w', newline='\r\n').write('\n'.join(FUENTE))
    if os.path.exists(NUEVO):
        os.remove(NUEVO)


s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='changeset-solape', t=180)


def cs(**kw):
    return s.call('delphi_changeset', kw)


def abre():
    return mc.id_changeset(cs(command='begin'))


try:
    escribe()
    i = abre()
    cs(command='stage', id=i, kind='edit', path=U, old=LARGA, new='  Result2 := 0; // was long')
    cs(command='stage', id=i, kind='create', path=NUEVO, content='unit UNueva;\ninterface\nimplementation\nend.\n')
    cs(command='stage', id=i, kind='delete-line', path=U, atline=17, old=LARGA)
    r = cs(command='preview', id=i)
    p = mc.como_json(r)
    op3 = (p.get('operations') or [{}, {}, {}])[2]
    check('S1 la secuencia de Hermes: el preview no la da por limpia, nombra la linea 17 y la operacion 1',
          p.get('unresolved') == 1 and 'line 17 is the one operation 1' in str(op3.get('anchor', '')), r[:500])
    r = cs(command='commit', id=i)
    check('...y no hay commit: nada cambio en disco',
          mc.rechazado(r) and open(U, newline='').read() == '\r\n'.join(FUENTE) and not os.path.exists(NUEVO), r[:300])
    cs(command='rollback', id=i)

    escribe()
    i = abre()
    cs(command='stage', id=i, kind='edit', path=U, old='  Result := 0;', new='  Result := 1;')
    cs(command='stage', id=i, kind='edit', path=U, old='  Result := 0;', new='  Result := 2;')
    r = cs(command='preview', id=i)
    p = mc.como_json(r)
    op2 = (p.get('operations') or [{}, {}])[1]
    check('S2 dos edits que anclan en la misma linea: el segundo, no resuelto (operacion 1)',
          p.get('unresolved') == 1 and 'operation 1' in str(op2.get('anchor', '')), r[:500])
    cs(command='rollback', id=i)

    escribe()
    i = abre()
    cs(command='stage', id=i, kind='edit', path=U, old=LARGA, new='  Result2 := 0; // was long')
    cs(command='stage', id=i, kind='delete-line', path=U, atline=20)
    r = cs(command='preview', id=i)
    p = mc.como_json(r)
    check('S3 control: edit de la 17 y delete-line de la 20 (en blanco): limpio', p.get('unresolved') == 0, r[:400])
    r = cs(command='commit', id=i)
    texto = open(U, newline='').read()
    check('...y el commit aplica las dos',
          not mc.fallo(r) and '// was long' in texto and 'end;\r\nend.' in texto, r[:300])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('changeset solape 1.19.1')
