# -*- coding: utf-8 -*-
"""EL lector del .rc (Lsp.Styles.LeeRc, 3c del censo de jueces de la 1.20.2).
Lo leian dos regex de linea: la del lint de estilos ('X RCDATA "f"') y la de la
segunda barrera de build (RcPathsDenied: dos palabras y un fichero). brcc32 lee
por TOKENS (medido el 18-oct-2026): banderas de memoria delante del fichero, el
fichero en otra linea, dos recursos en una. Ninguna de las dos lo veia.

  R1 lint: un recurso con DISCARDABLE delante de un fichero que falta, sale en
     rcMissingFiles (ROJO en produccion: no lo veia)
  R2 lint: uno en tres lineas y dos en una, los que faltan, salen; el que esta,
     no (control)
  R3 build: un recurso con banderas que nombra una ruta FUERA de las raices (que
     no existe: nada se lee) -> la segunda barrera lo niega, STYLE-023, antes de
     convertir (ROJO: pasaba al contenedor)
  R4 control: el .rc de siempre compila

Uso:  python tests/test_rc_lector_1202.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('rc_lector_1202')
JAIL = os.path.join(BASE, 'jail')
STY = os.path.join(JAIL, 'Styles')
os.makedirs(STY)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True)
APPDATA = os.path.join(BASE, 'appdata')
os.makedirs(APPDATA)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'LOCALAPPDATA': APPDATA}), nombre='rclector', t=300)
call = srv.call

STYLE = """object TStyleContainer
  object TLayout
    StyleName = 'uno'
  end
end
"""
RC = os.path.join(STY, 'Estilos.rc')
open(os.path.join(STY, 'Uno.style'), 'w', encoding='utf-8', newline='\r\n').write(STYLE)
open(os.path.join(STY, 'esta.bin'), 'wb').write(b'x')


def escribe_rc(texto):
    open(RC, 'w', encoding='utf-8', newline='\r\n').write(texto)


def faltan(r):
    return {(e.get('resource'), e.get('missing')) for e in mc.como_json(r).get('rcMissingFiles', [])}


try:
    # ------------------------------------------------------------------ R1
    escribe_rc('LOGO RCDATA DISCARDABLE "falta1.png"\n')
    r = call('delphi_styles', {'command': 'lint', 'path': STY}, t=180)
    check('R1 lint: LOGO RCDATA DISCARDABLE "falta1.png" sale en rcMissingFiles',
          ('LOGO', 'falta1.png') in faltan(r), r[:300])

    # ------------------------------------------------------------------ R2
    escribe_rc('FONDO\nRCDATA\n"falta2.png"\nA RCDATA falta3.bin B RCDATA "esta.bin"\n')
    r = call('delphi_styles', {'command': 'lint', 'path': STY}, t=180)
    f = faltan(r)
    check('R2 lint: uno en tres lineas y dos en una: los que faltan, si; el que esta, no',
          ('FONDO', 'falta2.png') in f and ('A', 'falta3.bin') in f and ('B', 'esta.bin') not in f, (f, r[:200]))

    # ------------------------------------------------------------------ R3
    FUERA = r'Z:\no\existe\fuera.bin'
    escribe_rc('X RCDATA PRELOAD DISCARDABLE "%s"\n' % FUERA)
    r = call('delphi_styles', {'command': 'build', 'path': STY}, t=300)
    check('R3 build: banderas delante de una ruta FUERA de las raices: STYLE-023, y ningun derivado nace',
          mc.abre(r, 'SR_STYLES_RC_OUTSIDE_FMT') and not os.path.exists(os.path.join(STY, 'Uno.bin.style')),
          r[:300])

    # ------------------------------------------------------------------ R4
    escribe_rc('UNO RCDATA "Uno.bin.style"\n')
    r = call('delphi_styles', {'command': 'build', 'path': STY}, t=300)
    check('R4 control: el .rc de siempre compila', mc.como_json(r).get('rcOk') is True, r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('el lector del .rc 1202')
