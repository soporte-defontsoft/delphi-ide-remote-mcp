# -*- coding: utf-8 -*-
"""1.29 (C4): delphi_designer insert items=[{classname, component, parent, props}, ...] - varios insert en UNA
escritura, todo o nada, cada uno como un insert suelto (sus jueces: el lector del IDE para lo puesto, el escritor
para sus propiedades, el juez del orden para su sitio entre los hermanos; su campo y sus units) sobre lo que deja el
anterior. Un informe del 7-nov: rehacer en FMX una pantalla de unos 150 controles a golpe de insert no era practicable
y el agente escribio el .fmx a mano y los campos del .pas a mano. El limite de una llamada es el plazo del cliente
(DSGN-185), que dice cuantos cupieron: medido el 7-nov, unos 2,5 s por control en produccion.

  I1 FMX: el lote deja el .fmx y el .pas IGUALES, byte a byte, que los mismos insert sueltos en un gemelo.
     ROJO contra 166bea8b (no habia items: 14 de 26 en rojo)
  I2 ...la respuesta: inserted con los tres, items en orden con su campo y DSGN-197; sin lint en un form limpio
  I2b el lint del lote es el del form escrito: un StyleLookup que ningun estilo define
  I3 VCL: lo mismo (el juez del orden escribe el TLabel delante del TButton), byte a byte
  I4 todo o nada: una entrada con una clase que no existe -> DSGN-196 nombra cual, y ni el .fmx ni el .pas cambian
  I5 el padre de una entrada es una de DESPUES: negada (aun no existe), nada escrito
  I6 dos entradas con el mismo nombre: la segunda negada, nada escrito
  I7 la forma: no es una lista, vacia, un campo que no existe (DSGN-195); items y classname a la vez (DSGN-198)
  I8 outsideParent dice los del lote que caen fuera de su padre (un layout para todos)
  (No se recorre aqui el plazo agotado - pide 50 s de jueces -: el fragmento de cuantos cupieron.)

Uso:  python tests/test_insert_items_129.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('insert_items_129')
# el conversor: sin el estilo por defecto el juez de los lookups calla (I2b), como en un servidor sin el
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True, con_render=True)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='items', t=600)


def proyecto(nombre, kind):
    d = os.path.join(JAIL, nombre)
    r = srv.call('delphi_create', {'kind': kind, 'name': 'App', 'dir': d})
    check('fixture: %s (%s)' % (nombre, kind), not mc.fallo(r), r[:200])
    return d


def bytes_de(d, ext):
    return open(os.path.join(d, 'UMain' + ext), 'rb').read()


def suelto(form, **kw):
    a = {'command': 'insert', 'path': form}
    a.update(kw)
    return srv.call('delphi_designer', a, 300)


def lote(form, items, **kw):
    a = {'command': 'insert', 'path': form, 'items': items}
    a.update(kw)
    return srv.call('delphi_designer', a, 300)


FMX_ITEMS = [{'classname': 'TLayout', 'component': 'Campo1', 'props': 'Align=Top;Height=40'},
             {'classname': 'TLabel', 'component': 'Etiqueta1', 'parent': 'Campo1', 'props': "Text='Nombre';Align=Left"},
             {'classname': 'TEdit', 'component': 'Edicion1', 'parent': 'Campo1', 'props': 'Align=Client'}]
VCL_ITEMS = [{'classname': 'TPanel', 'component': 'Panel1', 'props': 'Align=alTop;Height=41'},
             {'classname': 'TButton', 'component': 'Boton1', 'parent': 'Panel1', 'props': "Caption='OK'"},
             {'classname': 'TLabel', 'component': 'Etiqueta1', 'parent': 'Panel1', 'props': "Caption='Nombre'"}]

try:
    # ------------------------------------------------------------------ I1, I2
    A = proyecto('FmxSueltos', 'project-fmx')
    B = proyecto('FmxLote', 'project-fmx')
    for it in FMX_ITEMS:
        r = suelto(os.path.join(A, 'UMain.fmx'), **{k: v for k, v in it.items()})
        check('fixture: insert suelto de %s' % it['component'], not mc.fallo(r), r[:200])
    r = lote(os.path.join(B, 'UMain.fmx'), FMX_ITEMS)
    j = mc.como_json(r) or {}
    check('I1 FMX: el lote deja el .fmx igual que los sueltos, byte a byte. ROJO contra 166bea8b',
          not mc.fallo(r) and bytes_de(A, '.fmx') == bytes_de(B, '.fmx'), r[:400])
    check('I1 ...y el .pas (campos y units), igual', bytes_de(A, '.pas') == bytes_de(B, '.pas'),
          (bytes_de(A, '.pas')[-300:], bytes_de(B, '.pas')[-300:]))
    items = j.get('items') or []
    check('I2 la respuesta: inserted con los tres, items en orden con su campo y DSGN-197; sin lint en un form '
          'limpio, como el suelto',
          j.get('inserted') == ['Campo1', 'Etiqueta1', 'Edicion1'] and
          [x.get('inserted') for x in items] == ['Campo1', 'Etiqueta1', 'Edicion1'] and
          all(x.get('fieldAt') for x in items) and 'lint' not in j and
          mc.abre(j.get('note', ''), 'SN_DESIGNER_ITEMS_FMT'), r[:600])
    r = lote(os.path.join(B, 'UMain.fmx'), [{'classname': 'TButton', 'component': 'BotonSinEstilo', 'parent': 'Campo1',
                                             'props': 'StyleLookup=loteSinEstilo'}])
    lint_lote = json.dumps((mc.como_json(r) or {}).get('lint'))
    check('I2b el lint del lote, el del form escrito: un StyleLookup que ningun estilo define (como L11 del suelto)',
          not mc.fallo(r) and mc.es(lint_lote, 'SN_DESIGNER_LOOKUPS_SIN_ESTILO_FMT') and 'loteSinEstilo' in lint_lote,
          r[:600])

    # ------------------------------------------------------------------ I3
    C = proyecto('VclSueltos', 'project-vcl')
    D = proyecto('VclLote', 'project-vcl')
    for it in VCL_ITEMS:
        r = suelto(os.path.join(C, 'UMain.dfm'), **{k: v for k, v in it.items()})
        check('fixture: insert suelto VCL de %s' % it['component'], not mc.fallo(r), r[:200])
    r = lote(os.path.join(D, 'UMain.dfm'), VCL_ITEMS)
    texto = bytes_de(D, '.dfm').decode('utf-8-sig', errors='replace')
    check('I3 VCL: el lote deja el .dfm y el .pas iguales que los sueltos, byte a byte',
          not mc.fallo(r) and bytes_de(C, '.dfm') == bytes_de(D, '.dfm') and bytes_de(C, '.pas') == bytes_de(D, '.pas'),
          r[:400])
    check('I3 ...con el TLabel delante del TButton, como lo escribe el IDE',
          0 <= texto.find('Etiqueta1: TLabel') < texto.find('Boton1: TButton'), texto[:600])

    # ------------------------------------------------------------------ I4, I5, I6
    fmx_b = os.path.join(B, 'UMain.fmx')
    antes = (bytes_de(B, '.fmx'), bytes_de(B, '.pas'))
    r = lote(fmx_b, [{'classname': 'TButton', 'component': 'BotonBueno', 'parent': 'Campo1'},
                     {'classname': 'TNoExisteNunca', 'component': 'Malo'}])
    check('I4 todo o nada: la entrada 2 (clase que no existe) -> DSGN-196 nombra cual',
          mc.es(r, 'SR_DESIGNER_ITEMS_ENTRADA_FMT') and 'entry 2 of 2' in r and 'TNoExisteNunca' in r, r[:400])
    check('I4 ...y ni el .fmx ni el .pas cambian (tampoco la entrada 1)',
          (bytes_de(B, '.fmx'), bytes_de(B, '.pas')) == antes, r[:200])
    r = lote(fmx_b, [{'classname': 'TButton', 'component': 'Hijo', 'parent': 'PadreDespues'},
                     {'classname': 'TLayout', 'component': 'PadreDespues'}])
    check('I5 el padre es una entrada de DESPUES: la 1 negada, nada escrito',
          mc.es(r, 'SR_DESIGNER_ITEMS_ENTRADA_FMT') and 'entry 1 of 2' in r and
          (bytes_de(B, '.fmx'), bytes_de(B, '.pas')) == antes, r[:400])
    r = lote(fmx_b, [{'classname': 'TButton', 'component': 'Gemelo'}, {'classname': 'TButton', 'component': 'Gemelo'}])
    check('I6 dos con el mismo nombre: la 2 negada, nada escrito',
          mc.es(r, 'SR_DESIGNER_ITEMS_ENTRADA_FMT') and 'entry 2 of 2' in r and
          (bytes_de(B, '.fmx'), bytes_de(B, '.pas')) == antes, r[:400])

    # ------------------------------------------------------------------ I7
    r = lote(fmx_b, 'no es una lista')
    check('I7 items que no es una lista: DSGN-195', mc.abre(r, 'SR_DESIGNER_ITEMS_FORMA_FMT'), r[:300])
    r = lote(fmx_b, [])
    check('I7 una lista vacia: DSGN-195', mc.abre(r, 'SR_DESIGNER_ITEMS_FORMA_FMT'), r[:300])
    r = lote(fmx_b, [{'classname': 'TButton', 'nombre': 'X'}])
    check('I7 un campo que no existe: DSGN-195 lo nombra', mc.abre(r, 'SR_DESIGNER_ITEMS_FORMA_FMT') and 'nombre' in r,
          r[:300])
    r = lote(fmx_b, [{'classname': 'TButton'}], classname='TButton')
    check('I7 items y classname a la vez: DSGN-198', mc.abre(r, 'SR_DESIGNER_ITEMS_Y_SUELTO'), r[:300])
    check('I7 ...y nada escrito en todo esto', (bytes_de(B, '.fmx'), bytes_de(B, '.pas')) == antes)

    # ------------------------------------------------------------------ I8
    r = lote(os.path.join(D, 'UMain.dfm'), [{'classname': 'TButton', 'component': 'Dentro', 'parent': 'Panel1'},
                                             {'classname': 'TButton', 'component': 'Fuera', 'parent': 'Panel1',
                                              'props': 'Left=900'}])
    fuera = json.dumps((mc.como_json(r) or {}).get('outsideParent'))
    check('I8 outsideParent dice los del lote que caen fuera de su padre', 'Fuera' in fuera and 'Dentro' not in fuera,
          r[:500])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('insert items (1.29, C4)')
