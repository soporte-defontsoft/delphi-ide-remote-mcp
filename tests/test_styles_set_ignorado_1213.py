# -*- coding: utf-8 -*-
"""delphi_styles set sobre una propiedad que FMX YA ignoraba (1.21.3). El juez
de set (STYLE-050) es un diff de lo que FMX ignora antes y despues del cambio:
una propiedad que la clase no publica y que YA estaba en el objeto se reescribia
con CHANGED, y el valor nunca llegaba a la app ni al .bin.style (deep-test de
Hermes sobre la 1.21.2, 21-oct-2026: Fill.Color en un TButton puesto el dia
antes). Ahora lo ignorado que nombra la propiedad que ESTE set escribe se niega
aunque ya estuviera.

  S1 set Fill.Color sobre un TLayout que ya la tenia (FMX la ignora): STYLE-050,
     nada escrito (el fichero sigue con el valor viejo)
  S2 control: en ese mismo objeto, una propiedad que si publica (Visible): CHANGED
     (lo ignorado que ya estaba y no es de este set no estorba)
  S3 control: Fill.Color en un TRectangle (la publica) con el TLayout al lado:
     CHANGED
  S4 lint ve el Fill.Color del TLayout en ignoredByFmx (el juez es el mismo)

S1 es ROJA contra 1.21.2 (pasar su exe como argumento). Necesita
DelphiStyleConvert.exe junto al exe bajo prueba (con_conversor).

Uso:  python tests/test_styles_set_ignorado_1213.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('styles-set-ignorado-1213')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True)
STY = os.path.join(BASE, 'Styles')
os.makedirs(STY)
FICHERO = os.path.join(STY, 'Ignorado.style')
TEXTO = ("object TStyleContainer\r\n"
         "  object TLayout\r\n"
         "    StyleName = 'boton'\r\n"
         "    Visible = True\r\n"
         "    Fill.Color = xFF0000FF\r\n"
         "  end\r\n"
         "  object TRectangle\r\n"
         "    StyleName = 'caja'\r\n"
         "    Fill.Color = xFFFF0000\r\n"
         "  end\r\n"
         "end\r\n")
with open(FICHERO, 'w', encoding='utf-8', newline='') as f:
    f.write(TEXTO)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='sty-ign', t=120)


def leido():
    # newline='': los CRLF tal cual, para comparar byte a byte con lo escrito
    with open(FICHERO, encoding='utf-8', newline='') as f:
        return f.read()


try:
    r = srv.call('delphi_styles', {'command': 'set', 'path': FICHERO, 'style': 'boton',
                                   'prop': 'Fill.Color', 'value': 'xFF00FF00'})
    check('S1 set de una propiedad que FMX ya ignoraba (Fill.Color en TLayout): STYLE-050',
          mc.rechazado(r) and mc.es(r, 'SR_STYLES_FMX_LO_IGNORARIA_FMT') and 'Fill.Color' in r, r[:400])
    check('S1 ...y nada escrito: el fichero sigue con el valor viejo', leido() == TEXTO, leido()[:200])
    r = srv.call('delphi_styles', {'command': 'set', 'path': FICHERO, 'style': 'boton',
                                   'prop': 'Visible', 'value': 'False'})
    check('S2 control: en el mismo objeto, una propiedad que si publica (Visible) se escribe',
          mc.abre(r, 'SN_STYLES_PROP_SET_FMT') and 'Visible = False' in leido(), r[:300])
    r = srv.call('delphi_styles', {'command': 'set', 'path': FICHERO, 'style': 'caja',
                                   'prop': 'Fill.Color', 'value': 'xFF00FF00'})
    check('S3 control: Fill.Color en un TRectangle (la publica), con el TLayout ignorado al lado, se escribe',
          mc.abre(r, 'SN_STYLES_PROP_SET_FMT') and 'Fill.Color = xFF00FF00' in leido(), r[:300])
    r = srv.call('delphi_styles', {'command': 'lint', 'path': STY})
    d = mc.como_json(r)
    ign = [i for x in d.get('ignoredByFmx', []) for i in x.get('ignored', [])]
    check('S4 lint ve el Fill.Color del TLayout en ignoredByFmx (el mismo juez)',
          any('TLayout.Fill.Color' in i for i in ign), (ign or r[:300]))
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('styles set sobre lo que FMX ya ignoraba 1213')
