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
     una lista: STYLE-056), sin convertir ni dejar .res
  L2 (guarda) un .rc de lista pura: compila, y su .res lleva el recurso BAT
  L3 (V54) lint de un .rc con #define: dice que no es una lista (STYLE-056)
  L4 (revisor V54) una lista con DOS recursos: el servidor juzga lo que COMPONE
     (RcLecturasDenegadas sobre RcCompuesto, no una relectura) y el .res lleva
     los dos; guarda de que esa puerta no rompe un build legitimo (el cierre del
     TOCTOU -juzgar lo compuesto- es una barrera redundante: su divergencia con
     la puerta del original es una CARRERA, sin roja determinista)
  L5 (revisor V54) un .rc que nombra un fichero con un caracter fuera de la
     pagina ANSI de la maquina (brcc32 lee el .rc en esa pagina): negativa con
     codigo (EDIT-078) en la respuesta ESTRUCTURADA del build (rcOk:false), como
     cualquier otra negativa suya. MEDIDO: ya era DENIED, nunca INTERNAL
     [ROJO contra el build sin el arreglo: la excepcion sube y sale el mensaje
     suelto, sin la respuesta estructurada del build (rcOk)]

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


def res_lleva(path, nombre):
    # el nombre de un recurso va en el directorio del .res en UTF-16LE,
    # mayusculas y TERMINADO EN NULO (asi BAT no casa dentro de BAT2):
    # BAT -> b'B\x00A\x00T\x00\x00\x00'. Su firma minima, no una gramatica del .res
    if not os.path.exists(path):
        return False
    with open(path, 'rb') as f:
        return (nombre.upper() + '\0').encode('utf-16-le') in f.read()


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='styles-rc-lista', t=120)
try:
    # L1: un .rc con #define que HOY compila (el preprocesador corre sobre texto
    # del agente) -> el arreglo lo niega antes de convertir y no deja .res ni .bin
    limpia()
    pon_rc('#define BATRES "Bat.bin.style"\nBAT RCDATA BATRES\n')
    r = srv.call('delphi_styles', {'path': STY, 'command': 'build'})
    check('L1 (V54) un .rc con #define: build lo niega (STYLE-056), sin convertir ni dejar .res',
          mc.abre(r, 'SR_STYLES_RC_NO_LISTA_FMT') and not os.path.exists(RES) and not os.path.exists(BIN), r[:400])

    # L2: una lista pura compila y deja su .res (el servidor compone ese mismo .rc)
    limpia()
    pon_rc('BAT RCDATA "Bat.bin.style"\n')
    r = srv.call('delphi_styles', {'path': STY, 'command': 'build'})
    j = mc.como_json(r)
    check('L2 (guarda) un .rc de lista pura compila, y el .res lleva el recurso BAT',
          j.get('ok') is True and j.get('rcOk') is True and res_lleva(RES, 'BAT'),
          r[:400])

    # L3: el lint lo dice igual (es, no abre: va entre las incidencias del lint)
    pon_rc('#define BATRES "Bat.bin.style"\nBAT RCDATA BATRES\n')
    r = srv.call('delphi_styles', {'path': STY, 'command': 'lint'})
    check('L3 (V54) lint de un .rc con #define: dice que no es una lista (STYLE-056)',
          mc.es(r, 'SR_STYLES_RC_NO_LISTA_FMT'), r[:400])

    # L4 (revisor V54): un .rc de lista pura, con una entrada MAS (dos recursos):
    # el servidor juzga lo que COMPONE (no una relectura del original), asi que
    # el .res lleva los dos. Es la guarda de que la puerta del texto compuesto
    # (RcLecturasDenegadas sobre RcCompuesto) no rompe un build legitimo.
    limpia()
    open(os.path.join(STY, 'Bat2.bin.style'), 'wb').write(b'BAT2\n')
    pon_rc('BAT RCDATA "Bat.bin.style"\nBAT2 RCDATA "Bat2.bin.style"\n')
    r = srv.call('delphi_styles', {'path': STY, 'command': 'build'})
    j = mc.como_json(r)
    check('L4 (revisor V54) lista con dos recursos: compila y el .res lleva BAT y BAT2',
          j.get('rcOk') is True and res_lleva(RES, 'BAT') and res_lleva(RES, 'BAT2'), r[:400])

    # L5 (revisor V54): un fichero con un caracter que la pagina ANSI de la
    # maquina no guarda (brcc32 lee el .rc en esa pagina). El .rc se escribe con
    # BOM para que el servidor lo lea en UTF-8 y el caracter llegue entero a la
    # composicion; al escribir el .rc compuesto en ANSI no cabe. MEDIDO: ya salia
    # DENIED (el marco usa el mensaje de ECaracterNoCabe), nunca INTERNAL; el
    # arreglo lo devuelve en la respuesta ESTRUCTURADA del build (rcOk:false, el
    # EDIT-078 en 'error') en vez de dejar subir la excepcion como mensaje suelto.
    limpia()
    open(RC, 'w', encoding='utf-8-sig').write('BAT RCDATA "資.style"\n')
    r = srv.call('delphi_styles', {'path': STY, 'command': 'build'})
    seguro = r[:400].encode('ascii', 'backslashreplace').decode('ascii')  # r lleva el caracter
    check('L5 (revisor V54) caracter fuera de la ANSI: negativa con codigo (EDIT-078) en la respuesta estructurada (rcOk:false)',
          mc.rechazado(r) and not mc.es(r, 'SR_FALLO_INTERNO_FMT')
          and mc.como_json(r).get('rcOk') is False and not os.path.exists(RES), seguro)
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('el .rc de delphi_styles es una lista blanca, V54 de la 1.23')
