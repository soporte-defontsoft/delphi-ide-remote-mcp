# -*- coding: utf-8 -*-
"""delphi_styles build: el .rc del agente es una LISTA blanca (V54 de la 1.23).

brcc32 tiene preprocesador (#define, ##) y compone rutas que el lector del .rc
(LeeRc, STYLE-052) no sigue: solo las para el contenedor, que SI deja leer lo
que el SO concede a todos los paquetes de aplicacion (C:/Windows...). Para que al
preprocesador no le llegue texto del agente, el .rc de delphi_styles pasa a ser
SOLO una lista NOMBRE TIPO [banderas] "fichero"; cualquier otra cosa (#define,
#include, RCINCLUDE, bloques, LANGUAGE...) se niega, y el servidor ESCRIBE el .rc
que compila brcc32 (RcCompuesto, inversa de LeeRc). Un .rc que hoy es una lista
sigue compilando y el .res lleva el mismo recurso.

  L1 (V54) un .rc con #define (compila hoy): delphi_styles build lo NIEGA (no es
     una lista), sin convertir ni dejar .res   [ROJO contra el build sin el arreglo]
  L2 (guarda) un .rc de lista pura: compila, con su .res
  L3 (V54) lint de un .rc con #define: dice que no es una lista

Uso:  python tests/test_styles_rc_lista_1230.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('styles_rc_lista_1230')
JAIL = os.path.join(BASE, 'jail')
STY = os.path.join(JAIL, 'Styles')
os.makedirs(STY)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True)
RC = os.path.join(STY, 'Bat.Estilos.rc')
RES = os.path.join(STY, 'Bat.Estilos.res')
BIN = os.path.join(STY, 'Bat.bin.style')

STYLE = """object TStyleContainer
  object TStyleDescription
    StyleName = 'Description'
    Title = 'Lista'
    Version = '1.0'
  end
  object TLayout
    StyleName = 'cardstyle'
    object TRectangle
      StyleName = 'background'
      Fill.Color = xFFFFFFFF
    end
  end
end
"""
open(os.path.join(STY, 'Bat.style'), 'w', encoding='utf-8', newline='\n').write(STYLE)


def pon_rc(texto):
    open(RC, 'w', encoding='utf-8').write(texto)


def limpia():
    for p in (RES, BIN):
        if os.path.exists(p):
            os.remove(p)


def lista(r):
    return 'plain list' in r.lower()


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='styles-rc-lista', t=120)
try:
    # L1: un .rc con #define que HOY compila (el preprocesador corre sobre texto
    # del agente) -> el arreglo lo niega antes de convertir y no deja .res ni .bin
    limpia()
    pon_rc('#define BATRES "Bat.bin.style"\nBAT RCDATA BATRES\n')
    r = build = srv.call('delphi_styles', {'path': STY, 'command': 'build'})
    check('L1 (V54) un .rc con #define: build lo niega (no es una lista), sin convertir ni dejar .res',
          lista(r) and not os.path.exists(RES) and not os.path.exists(BIN), r[:400])

    # L2: una lista pura compila y deja su .res (el servidor compone ese mismo .rc)
    limpia()
    pon_rc('BAT RCDATA "Bat.bin.style"\n')
    r = srv.call('delphi_styles', {'path': STY, 'command': 'build'})
    j = mc.como_json(r)
    check('L2 (guarda) un .rc de lista pura compila, con su .res',
          j.get('ok') is True and j.get('rcOk') is True and os.path.exists(RES),
          r[:400])

    # L3: el lint lo dice igual
    pon_rc('#define BATRES "Bat.bin.style"\nBAT RCDATA BATRES\n')
    r = srv.call('delphi_styles', {'path': STY, 'command': 'lint'})
    check('L3 (V54) lint de un .rc con #define: dice que no es una lista', lista(r), r[:400])
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('el .rc de delphi_styles es una lista blanca, V54 de la 1.23')
