# -*- coding: utf-8 -*-
"""D9 de la 1.29.3 (opencode, 17-nov): delphi_styles lint daba clean:true con un estilo que FMX NO devuelve por su
nombre. FMX indexa TODOS los objetos con StyleName (FMX.Types, TStyleIndexer.Rebuild: los internos y los roles de la
paleta tambien, sin mayusculas) y el ULTIMO gana; el control con ese StyleLookup recibe el otro o sale vacio, sin
error. Tres casos reales ese dia (un TPath 'lupa' dentro de editbuscar contra el estilo lupa, 15 botones; el rol
carrilPestanas contra carrilpestanas; un 'separador' dentro de rotulopizarra, 13 controles). Ahora el conversor le
pregunta a FMX (FindStyleResource) por cada estilo de primer nivel y el lint lo dice: shadowedByInnerName.

  P1 un interno 'lupa' DENTRO de editbuscar, que va despues del estilo 'lupa': shadowedByInnerName lo dice (style
     lupa, returnedInstead editbuscar.lupa) y clean es false (ROJO: clean true y nada)
  P2 un rol de la paleta 'CarrilX' contra el estilo 'carrilx', sin mayusculas: tambien
  P3 control: los mismos con el interno y el rol renombrados: ni shadowedByInnerName ni su nota, y clean
  P4 control (el juez es FMX, no el nombre): un interno 'cosa' que va ANTES del estilo 'cosa' no lo pisa (gana el
     ultimo, el estilo) y no se dice

Uso:  python tests/test_estilos_pisados_1293.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('estilos_pisados_1293')
JAIL = os.path.join(BASE, 'jail')
# con_conversor: sin DelphiStyleConvert al lado el lint no le pregunta a FMX y P3/P4 pasaban SIN medir nada (medido
# al escribirla: la primera version no lo pedia). P1 en verde es la prueba de que el conversor corrio en este servidor
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True)


def capa(nombre, dentro=''):
    return ("  object TLayout\r\n    StyleName = '%s'\r\n    Size.Width = 20.000000000000000000\r\n"
            "    Size.Height = 20.000000000000000000\r\n    Size.PlatformDefault = False\r\n%s  end\r\n" % (nombre, dentro))


def interno(nombre):
    return ("    object TRectangle\r\n      StyleName = '%s'\r\n      Size.Width = 10.000000000000000000\r\n"
            "      Size.Height = 10.000000000000000000\r\n      Size.PlatformDefault = False\r\n    end\r\n" % nombre)


def paleta(rol):
    return ("  object TLayout\r\n    StyleName = 'Paleta'\r\n    Size.Width = 20.000000000000000000\r\n"
            "    Size.Height = 20.000000000000000000\r\n    Size.PlatformDefault = False\r\n"
            "    object TColorObject\r\n      StyleName = '%s'\r\n      Color = xFF112233\r\n    end\r\n  end\r\n" % rol)


def carpeta_con(nombre, bloques):
    d = os.path.join(JAIL, nombre)
    os.makedirs(d)
    with open(os.path.join(d, 'Prueba.style'), 'w', encoding='utf-8', newline='') as f:
        f.write('object TStyleContainer\r\n' + ''.join(bloques) + 'end\r\n')
    return d


def pisados(j):
    return {(p.get('style'), p.get('returnedInstead')) for p in (j.get('shadowedByInnerName') or [])}


MAL = carpeta_con('Mal', [capa('lupa'), capa('editbuscar', interno('lupa')), capa('carrilx'), paleta('CarrilX')])
BIEN = carpeta_con('Bien', [capa('lupa'), capa('editbuscar', interno('iconobuscar')), capa('carrilx'),
                            paleta('carrilSegmentado')])
ANTES = carpeta_con('Antes', [capa('host', interno('cosa')), capa('cosa')])
# revisor del paisaje de la 1.29.3: dos estilos de PRIMER nivel con el mismo nombre son un duplicado
# (duplicatedStyleNames); salian tambien como pisados "por un interno o un rol", que no hay
DOBLE = carpeta_con('Doble', [capa('boton'), capa('boton')])

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='estilos-pisados', t=300)
try:
    r = srv.call('delphi_styles', {'command': 'lint', 'path': MAL}, t=300)
    j = mc.como_json(r) or {}
    check('P1 un interno lupa dentro de editbuscar, despues del estilo lupa: shadowedByInnerName lo dice'
          ' (returnedInstead editbuscar.lupa) y clean es false (ROJO: clean true)',
          ('lupa', 'editbuscar.lupa') in pisados(j) and j.get('clean') is False
          and mc.abre(j.get('shadowedByInnerNameNote', ''), 'SN_STYLES_PISADOS_FMT'), r[:900])
    check('P2 ...y el rol de la paleta CarrilX pisa al estilo carrilx, sin mayusculas',
          ('carrilx', 'Paleta.CarrilX') in pisados(j), (sorted(pisados(j)), r[:600]))
    r = srv.call('delphi_styles', {'command': 'lint', 'path': BIEN}, t=300)
    j = mc.como_json(r) or {}
    check('P3 control: con el interno y el rol renombrados, ni shadowedByInnerName ni su nota, y clean',
          'shadowedByInnerName' not in j and 'shadowedByInnerNameNote' not in j and j.get('clean') is True, r[:900])
    r = srv.call('delphi_styles', {'command': 'lint', 'path': ANTES}, t=300)
    j = mc.como_json(r) or {}
    check('P4 control: un interno cosa que va ANTES del estilo cosa no lo pisa (gana el ultimo): no se dice',
          'styleNames' in j and 'shadowedByInnerName' not in j, r[:900])
    r = srv.call('delphi_styles', {'command': 'lint', 'path': DOBLE}, t=300)
    j = mc.como_json(r) or {}
    check('P5 dos boton de primer nivel: duplicatedStyleNames, y NO shadowedByInnerName (ROJO sin el arreglo: los '
          'dos, con "rename that inner object")', any(d.get('style') == 'boton' for d in
                                                        (j.get('duplicatedStyleNames') or []))
          and 'shadowedByInnerName' not in j, r[:900])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('estilos que FMX no devuelve por su nombre 1.29.3 (D9)')
