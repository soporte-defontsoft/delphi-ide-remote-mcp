# -*- coding: utf-8 -*-
r"""Un color de menos de 8 cifras en un .fmx (V154 de la 1.23.1).

delphi_edit escribia Fill.Color = xFF7DFC6 sin decir nada y delphi_designer lint decia CLEAN
(medido en vivo el 28-oct): FMX lo carga x0FF7DFC6, alfa 0F, casi transparente. El mismo fallo
que V152 en los .style, que llego de un tema real. designer set/insert ya escriben como el IDE
(storedAs). Cuantas cifras: gramatica propia (Lsp.Styles.EsColorSinAlfa); como lo carga FMX: el
escritor del IDE (Lsp.FormRender.ComoLoEscribeElIde, el ayudante, fuera del cerrojo). Rojas
contra 417ee2c:

  C1 lint de un form con Fill.Color = xFF7DFC6: no CLEAN, DSGN-176 nombra Rect1.Fill.Color, su
     linea y lo que guarda el IDE (x0FF7DFC6)
  C2 delphi_edit que escribe ese color: su respuesta lleva DSGN-176
  C3 delphi_edit de otra linea (el color ya estaba): sin DSGN-176 (solo lo que la edicion trae,
     como DSGN-175 desde V143)
  C4 un changeset que escribe xF7DFC6: su respuesta lleva DSGN-176 (x00F7DFC6)
  C5 (control) un color de 8 cifras escrito con delphi_edit: sin DSGN-176, y el lint CLEAN

Uso:  python tests/test_color_sin_alfa_form_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('color-sin-alfa-form')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='csa', t=600)
NOTA = 'SN_DESIGNER_COLORES_SIN_ALFA_FMT'


def lint(fmx):
    return srv.call('delphi_designer', {'command': 'lint', 'path': fmx}, 300)


def limpio(r):
    return mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT')


try:
    carpeta = os.path.join(BASE, 'App')
    r = srv.call('delphi_create', {'kind': 'project-fmx', 'name': 'App', 'dir': carpeta})
    check('fixture creada (delphi_create)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    fmx = os.path.join(carpeta, 'UMain.fmx')
    r = srv.call('delphi_designer', {'command': 'insert', 'path': fmx, 'classname': 'TRectangle',
                                     'component': 'Rect1'}, 300)
    check('fixture: Rect1 insertado', '"inserted":"Rect1"' in r.replace(' ', ''), r[:300])
    with open(fmx, encoding='utf-8-sig', newline='') as f:
        ORIGINAL = f.read()
    ANCLA = '    Size.PlatformDefault = False\r\n  end\r\n'
    assert ORIGINAL.count(ANCLA) == 1, ORIGINAL

    def escribe(texto):
        with open(fmx, 'w', encoding='utf-8-sig', newline='') as f:
            f.write(texto)

    def con_color(valor):
        return ORIGINAL.replace(ANCLA, '    Size.PlatformDefault = False\r\n    Fill.Color = %s\r\n  end\r\n' % valor)

    def linea_de(texto, trozo):
        return texto.split('\r\n').index(trozo) + 1

    escribe(con_color('xFF7DFC6'))
    r = lint(fmx)
    linea = linea_de(con_color('xFF7DFC6'), '    Fill.Color = xFF7DFC6')
    check('C1 lint: no CLEAN y DSGN-176 nombra Rect1.Fill.Color, su linea y lo que guarda el IDE',
          not limpio(r) and mc.es(r, NOTA) and 'Rect1.Fill.Color = xFF7DFC6 (line %d)' % linea in r and
          'x0FF7DFC6' in r, r[:900])

    escribe(ORIGINAL)
    r = srv.call('delphi_edit', {'path': fmx, 'old': '    Size.PlatformDefault = False\n  end',
                                 'new': '    Size.PlatformDefault = False\n    Fill.Color = xFF7DFC6\n  end'}, 300)
    check('C2 delphi_edit que escribe un color de 7 cifras: su respuesta lleva DSGN-176',
          'Fill.Color = xFF7DFC6' in open(fmx, encoding='utf-8-sig').read() and mc.es(r, NOTA) and
          'x0FF7DFC6' in r, r[-900:])

    r = srv.call('delphi_edit', {'path': fmx, 'old': '    Position.X = 10.000000000000000000',
                                 'new': '    Position.X = 20.000000000000000000'}, 300)
    check('C3 delphi_edit de otra linea (el color ya estaba): sin DSGN-176',
          'error' not in mc.como_json(r) and not mc.es(r, NOTA), r[-700:])

    escribe(con_color('xFFF7DFC6'))
    i = mc.id_changeset(srv.call('delphi_changeset', {'command': 'begin'}))
    srv.call('delphi_changeset', {'command': 'stage', 'id': i, 'kind': 'edit', 'path': fmx,
                                  'old': '    Fill.Color = xFFF7DFC6', 'new': '    Fill.Color = xF7DFC6'})
    srv.call('delphi_changeset', {'command': 'preview', 'id': i}, 300)
    r = srv.call('delphi_changeset', {'command': 'commit', 'id': i}, 300)
    check('C4 un changeset que escribe xF7DFC6: su respuesta lleva DSGN-176 (x00F7DFC6)',
          mc.es(r, NOTA) and 'x00F7DFC6' in r, r[-900:])

    escribe(ORIGINAL)
    r = srv.call('delphi_edit', {'path': fmx, 'old': '    Size.PlatformDefault = False\n  end',
                                 'new': '    Size.PlatformDefault = False\n    Fill.Color = xFFF7DFC6\n  end'}, 300)
    check('C5 (control) un color de 8 cifras: sin DSGN-176', not mc.es(r, NOTA), r[-700:])
    r = lint(fmx)
    check('C5 ...y el lint CLEAN', limpio(r), r[:600])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('color sin alfa en un form 1.23.1 (V154)')
