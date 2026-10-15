# -*- coding: utf-8 -*-
"""delphi_designer: un subrango Low(T)..High(T) es de la base de T (1.19.1; Hermes,
15-oct-2026, informe 002938).

TModalResult = Low(Integer)..High(Integer) (System.UITypes). El generador de tablas
solo tomaba por entero un subrango cuyo limite bajo empezase por un numero (TColor,
TCursor): este quedaba sin base y set y lint dejaban pasar cualquier cosa. Medido
contra 1bdb4d7: `set ModalResult=mrOK` se escribia, lint decia CLEAN, y el cargador
real lo rechazaba (preview: ignored "Invalid property value" + DSGN-114, el form no
abre). El IDE escribe el numero.

  M1 set ModalResult=mrOK: negado (DSGN-093: un numero entero), nada escrito
  M2 set ModalResult=1: escrito, y el preview no lo ignora
  M3 lint de un form con "ModalResult = mrOK" escrito a mano: no CLEAN, lo nombra
  M4 control: Color=clRed (TColor, subrango con constantes registradas) sigue valiendo

Uso:  python tests/test_designer_modalresult_1191.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer_modalresult_1191')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)

s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='designer-modalresult', t=300)


def d(**kw):
    return s.call('delphi_designer', kw, t=300)


try:
    listas = mc.espera_tablas(lambda tool, args, t=120: s.call(tool, args, t=t))
    check('fixture: las tablas del disenador estan listas',
          all(not mc.tiene(r, 'DSGN-051') and not mc.fallo(r) for _, r in listas), str(listas)[:300])
    s.call('delphi_create', {'kind': 'project-vcl', 'name': 'Modal', 'dir': JAIL})
    DFM = os.path.join(JAIL, 'UMain.dfm')
    d(command='insert', path=DFM, classname='TButton', component='BtnOk')
    antes = mc.lee(DFM)
    r = d(command='set', path=DFM, component='BtnOk', prop='ModalResult', value='mrOK')
    check('M1 set ModalResult=mrOK: negado como entero (DSGN-093) y nada escrito',
          mc.rechazado(r) and mc.es(r, 'SR_DESIGNER_SET_TIPO_FMT') and mc.lee(DFM) == antes, r[:300])
    r = d(command='set', path=DFM, component='BtnOk', prop='ModalResult', value='1')
    p = d(command='preview', path=DFM, maxwidth=200)
    check('M2 set ModalResult=1: escrito, y el preview no lo ignora',
          not mc.fallo(r) and 'ModalResult = 1' in mc.lee(DFM) and 'ModalResult' not in p.split('"ignored"')[-1][:200]
          if '"ignored"' in p else not mc.fallo(r) and 'ModalResult = 1' in mc.lee(DFM), (r[:200], p[:300]))
    s.call('delphi_edit', {'path': DFM, 'old': 'ModalResult = 1', 'new': 'ModalResult = mrOK'})
    r = d(command='lint', path=DFM)
    check('M3 lint con "ModalResult = mrOK" escrito a mano: no CLEAN, y lo nombra',
          not mc.es(r, 'SN_DESIGNER_LINT_OK_FMT') and 'ModalResult' in r, r[:400])
    s.call('delphi_edit', {'path': DFM, 'old': 'ModalResult = mrOK', 'new': 'ModalResult = 1'})
    r = d(command='set', path=DFM, component='FormMain', prop='Color', value='clRed')
    check('M4 control: Color=clRed (TColor con sus constantes) sigue valiendo',
          not mc.fallo(r) and 'Color = clRed' in mc.lee(DFM), r[:300])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('designer ModalResult 1.19.1')
