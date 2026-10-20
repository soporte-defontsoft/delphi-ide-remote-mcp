# -*- coding: utf-8 -*-
"""delphi_completion con un trigger que el motor no anuncia (1.21.1): no
cambia nada y lo dice. Una letra (S, Z) se ignoraba en silencio y Hermes lo
leyo como un fallo dos veces. El juez es EL MOTOR: los triggerCharacters de
su respuesta a initialize (el agente de la 37.0 anuncia . ( < [, medido el
20-oct-2026), no una lista nuestra.

  T1 trigger "S": triggerNote (LSP-047) con los caracteres que anuncia el motor
  T2 ...y la respuesta es la de sin trigger (lo que la nota afirma, medido)
  T3 sin trigger, ni nota
  T4 trigger "(" (uno de los suyos): ni nota

T1 es ROJA contra 1.21.0 (pasar su exe como argumento); T2-T4, verdes con las dos.

Uso:  python tests/test_completion_trigger_1211.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('completion_trigger_1211')
JAIL = os.path.join(BASE, 'jail')
P = os.path.join(JAIL, 'comp')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='completion-trigger', t=600)

try:
    r = S.call('delphi_create', {'kind': 'project-console', 'name': 'Comp', 'dir': P})
    check('preparacion: consola Comp', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    DPR = os.path.join(P, 'Comp.dpr')
    LINEAS = ['program Comp;', '', '{$APPTYPE CONSOLE}', '', 'uses', '  System.SysUtils;', '',
              'begin', '  Wri', 'end.']
    open(DPR, 'w', encoding='utf-8', newline='\r\n').write('\n'.join(LINEAS) + '\n')
    POS = {'path': DPR, 'line': LINEAS.index('  Wri'), 'character': len('  Wri')}

    sin = mc.como_json(S.call('delphi_completion', POS, t=600)) or {}
    con_s = mc.como_json(S.call('delphi_completion', dict(POS, trigger='S'), t=600)) or {}
    con_par = mc.como_json(S.call('delphi_completion', dict(POS, trigger='('), t=600)) or {}
    nota = con_s.get('triggerNote', '')
    check('T1 trigger "S": triggerNote con lo que anuncia el motor',
          mc.es(nota, 'SN_COMPLETION_TRIGGER_NO_ES_FMT') and '"S"' in nota and '.' in nota, str(con_s)[:300])
    check('T2 ...y la respuesta es la de sin trigger',
          sin.get('total') and con_s.get('total') == sin.get('total') and
          [i.get('label') for i in con_s.get('items', [])] == [i.get('label') for i in sin.get('items', [])],
          (sin.get('total'), con_s.get('total')))
    check('T3 sin trigger, ni nota', sin.get('total') and 'triggerNote' not in sin, str(sin)[:300])
    check('T4 trigger "(" (uno de los suyos): ni nota', 'triggerNote' not in con_par, str(con_par)[:300])
finally:
    S.cierra()

mc.borra(BASE)
mc.fin('completion trigger 1.21.1')
