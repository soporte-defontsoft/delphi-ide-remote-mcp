# -*- coding: utf-8 -*-
"""1.29 (A21): sin el estilo por defecto de la plataforma - el juez de un StyleLookup de un form FMX que no toma
StyleBook, que da el conversor (DelphiStyleConvert.exe junto al servidor) -, el lint del disenador callaba y decia
CLEAN (DSGN-020) de un form con un StyleLookup que nadie habia juzgado (medido al hacer C4, 7-nov: el mismo insert da
DSGN-175 con el conversor). Ahora lo dice: DSGN-199, cuantos y por que. Y delphi_styles lint decia siempre
"converter missing" (STYLE-017), tambien cuando el conversor fallaba: dice el motivo de verdad.

  (Contra 166bea8b: 3 de 7 en rojo, L1, L2 -que dice CLEAN- y L5; los controles pasan.)
  L1 sin conversor: insert con StyleLookup -> la nota de la escritura lleva DSGN-199 con el motivo.
     ROJO contra 166bea8b (callaba)
  L2 ...y lint: no CLEAN, DSGN-199 con 1 lookup. ROJO contra 166bea8b (CLEAN)
  L3 control: un form FMX sin StyleLookup da CLEAN sin conversor
  L4 control: con el conversor, el mismo form da DSGN-175 (el juez existe y lo juzga)
  L5 delphi_styles lint sin conversor: STYLE-017 con el motivo (no esta desplegado). ROJO contra 166bea8b
  (El conversor que falla o se pasa de plazo da otro motivo, con su codigo: no se provoca aqui.)

Uso:  python tests/test_lookups_sin_juez_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('lookups_sin_juez_129')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)


def servidor(nombre, conversor):
    # los renderizadores siempre: sin el lector del IDE el lint no dice CLEAN de nada (DSGN-154)
    exe = mc.copia_exe(os.path.join(BASE, nombre), con_conversor=conversor, con_render=True)
    return mc.Stdio(exe, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre=nombre, t=600)


def proyecto(srv, nombre):
    d = os.path.join(JAIL, nombre)
    r = srv.call('delphi_create', {'kind': 'project-fmx', 'name': 'App', 'dir': d})
    check('fixture: %s' % nombre, not mc.fallo(r), r[:200])
    return os.path.join(d, 'UMain.fmx')


def dice(t, nombre):
    """Un texto sin etiqueta (SF_) por su formato."""
    return re.search(mc.patron_de_formato(nombre), t or '', re.S) is not None


sin = servidor('sin', False)
try:
    form = proyecto(sin, 'ConLookup')
    r = sin.call('delphi_designer', {'command': 'insert', 'path': form, 'classname': 'TButton',
                                     'component': 'Boton1', 'props': 'StyleLookup=sinJuezAqui'}, 300)
    check('L1 sin conversor: la nota de la escritura dice DSGN-199 con el motivo. ROJO contra 166bea8b',
          not mc.fallo(r) and mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_DEFECTO_FMT') and
          dice(r, 'SF_ESTILO_DEFECTO_SIN_CONVERSOR'), r[:800])
    r = sin.call('delphi_designer', {'command': 'lint', 'path': form}, 300)
    m = re.search(mc.patron_de_formato('SN_DESIGNER_LOOKUPS_SIN_DEFECTO_FMT'), r, re.S)
    check('L2 ...y lint: no CLEAN, DSGN-199 con 1 lookup de UMain.fmx. ROJO contra 166bea8b',
          not mc.es(r, 'SN_DESIGNER_LINT_OK_FMT') and m is not None and m.group(1) == '1' and
          m.group(2) == 'UMain.fmx', r[:800])
    limpio = proyecto(sin, 'SinLookup')
    r = sin.call('delphi_designer', {'command': 'lint', 'path': limpio}, 300)
    check('L3 control: un form FMX sin StyleLookup, CLEAN sin conversor',
          mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT') and not mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_DEFECTO_FMT'), r[:600])
    estilos = os.path.join(JAIL, 'Estilos')
    os.makedirs(estilos)
    with open(os.path.join(estilos, 'Propio.style'), 'w', encoding='utf-8', newline='\r\n') as f:
        f.write('object TStyleContainer\n  object TLayout\n    StyleName = \'propio\'\n  end\nend\n')
    r = sin.call('delphi_styles', {'command': 'lint', 'path': estilos}, 300)
    check('L5 delphi_styles lint sin conversor: STYLE-017 con el motivo. ROJO contra 166bea8b',
          not mc.fallo(r) and mc.es(r, 'SN_STYLES_NO_DEFAULTS_FMT') and dice(r, 'SF_ESTILO_DEFECTO_SIN_CONVERSOR'),
          r[:800])
finally:
    sin.cierra()

con = servidor('con', True)
try:
    r = con.call('delphi_designer', {'command': 'lint', 'path': form}, 300)
    check('L4 control: con el conversor, el mismo form da DSGN-175 (hay juez y lo juzga)',
          mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_ESTILO_FMT') and 'sinJuezAqui' in r and
          not mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_DEFECTO_FMT'), r[:800])
finally:
    con.cierra()
    mc.borra(BASE)

mc.fin('lookups sin juez 1.29 (A21)')
