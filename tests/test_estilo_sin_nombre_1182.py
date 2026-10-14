# -*- coding: utf-8 -*-
"""Punto 9 de la 1.18.2 (Hermes): delphi_styles view y lint callaban ante un
estilo sin StyleName. FMX encuentra un estilo SOLO por su StyleName (el
StyleLookup de un control lo nombra), asi que uno sin el no se usa nunca: lint
se lo saltaba en silencio (if StyleName = '' then Continue) y view lo ensenaba
con style vacio. Medido antes de escribir: los 50 .style de texto de RAD
Studio 37.0 no tienen ninguno, asi que el aviso no salta en un estilo sano.

  S1 lint de un .style con un objeto sin StyleName: lo lista en
     withoutStyleName (fichero, clase, lineas) y clean=false (ROJO en
     produccion: clean=true y nada)
  S2 view: esa entrada lleva styleNote (ROJO en produccion)
  S3 el control: el mismo .style sin ese objeto sale clean y sin styleNote

Y lo que queda del informe de Hermes (213123: entradas 'inherited cardstyle:
TLayout' sin StyleName). MEDIDO en el fuente de FMX: el lector de estilos
(TStyleReader.SetName) tira el nombre del objeto y el indice (TStyleIndexer)
solo mira StyleName - nadie encuentra 'cardstyle':
  S4 get style=cardstyle: STYLE-047 dice que es el nombre de un objeto sin
     StyleName, con sus lineas (ROJO en produccion: STYLE-036 seco)
  S5 delete style=cardstyle: el mismo STYLE-047 (ROJO: tenia su propio "no
     hay", STYLE-027, gemelo del de get)
  S6 view de un contenedor vacio: STYLE-048, no "resuelve a uno de estos" con
     la lista vacia (ROJO en produccion)
  S7 control: get de un estilo que no existe sigue siendo STYLE-036

Uso:  python tests/test_estilo_sin_nombre_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('estilo_sin_nombre_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

CON = (b"object TStyleContainer\r\n  object TLayout\r\n    StyleName = 'cardstyle'\r\n    Hint = 'x'\r\n  end\r\n"
       b"  object TRectangle\r\n    Fill.Color = claRed\r\n  end\r\nend\r\n")
SIN = (b"object TStyleContainer\r\n  object TLayout\r\n    StyleName = 'cardstyle'\r\n    Hint = 'x'\r\n  end\r\n"
       b"end\r\n")


def estilo(nombre, contenido):
    d = os.path.join(JAIL, nombre)
    os.makedirs(d)
    p = os.path.join(d, 'E.style')
    open(p, 'wb').write(contenido)
    return p


def J(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='estilo-sin-nombre', t=120)
try:
    p = estilo('s1', CON)
    r = J(srv.call('delphi_styles', {'path': p, 'command': 'lint'}))
    sin = r.get('withoutStyleName') or []
    check('S1 lint lista el objeto sin StyleName (TRectangle, sus lineas) y clean=false',
          len(sin) == 1 and sin[0].get('class') == 'TRectangle' and sin[0].get('lines') == '6-8'
          and r.get('clean') is False, (sin, r.get('clean')))

    r = J(srv.call('delphi_styles', {'path': p, 'command': 'view'}))
    notas = [e for e in r.get('styles', []) if e.get('style') == '' and e.get('styleNote')]
    check('S2 view: la entrada sin StyleName lleva styleNote', len(notas) == 1, r.get('styles'))

    p = estilo('s3', SIN)
    r = J(srv.call('delphi_styles', {'path': p, 'command': 'lint'}))
    v = J(srv.call('delphi_styles', {'path': p, 'command': 'view'}))
    check('S3 control: sin ese objeto, clean y sin styleNote',
          r.get('clean') is True and not (r.get('withoutStyleName') or []) and
          not any(e.get('styleNote') for e in v.get('styles', [])), (r.get('clean'), v.get('styles')))

    p = estilo('s4', b"object TStyleContainer\r\n  inherited cardstyle: TLayout\r\n    Hint = 'x'\r\n  end\r\nend\r\n")
    r = srv.call('delphi_styles', {'path': p, 'command': 'get', 'style': 'cardstyle'})
    check('S4 get de un nombre que es el de un objeto sin StyleName: STYLE-047, con sus lineas',
          mc.rechazado(r) and 'STYLE-047' in r and '2-4' in r, r[:300])
    r = srv.call('delphi_styles', {'path': p, 'command': 'delete', 'style': 'cardstyle'})
    check('S5 delete del mismo: STYLE-047 (un solo "no hay")', mc.rechazado(r) and 'STYLE-047' in r, r[:300])
    p = estilo('s6', b"object TStyleContainer\r\nend\r\n")
    r = srv.call('delphi_styles', {'path': p, 'command': 'view'})
    check('S6 view de un contenedor vacio: STYLE-048', 'STYLE-048' in r and 'STYLE-010' not in r, r[:300])
    r = srv.call('delphi_styles', {'path': estilo('s7', SIN), 'command': 'get', 'style': 'nada'})
    check('S7 control: get de uno que no existe, STYLE-036', mc.rechazado(r) and 'STYLE-036' in r, r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('delphi_styles: estilo sin StyleName 1182 (punto 9)')
