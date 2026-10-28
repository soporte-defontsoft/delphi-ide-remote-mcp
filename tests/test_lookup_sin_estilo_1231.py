# -*- coding: utf-8 -*-
r"""Un StyleLookup que ningun estilo define (V75 de la 1.23.1): designer set lo escribia, el lint
del disenador decia CLEAN y preview lo dibujaba con el estilo de su clase (medido el 28-oct). El
juez ya existia en delphi_styles lint: el estilo por defecto de la plataforma
(PlatformDefaultStyleNames). Ahora lo pregunta tambien el disenador, como NOTA (DSGN-175): FMX
no revienta, dibuja el estilo de la clase, y un estilo que el proyecto cargue en ejecucion solo
lo ve delphi_styles lint con su carpeta.

  L1 lint de un form con StyleLookup = 'estiloquenoexiste': NO dice CLEAN y la nota DSGN-175
     nombra el componente y el lookup (ROJA contra 464c4cc: CLEAN)
  L2 control: StyleLookup = 'buttonstyle' (del estilo por defecto): CLEAN
  L3 control: StyleLookup = '' (el estilo de su clase): CLEAN
  L4 designer set StyleLookup=otroquenoexiste: la respuesta lleva DSGN-175 (roja)
  L5 delphi_edit que escribe un StyleLookup que no existe: sus avisos llevan DSGN-175 (roja)
  L6 con un TStyleBook en el form (sus estilos van en binario y no se leen): sin DSGN-175

Uso:  python tests/test_lookup_sin_estilo_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('lookup-sin-estilo')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True, con_render=True)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='ls', t=600)


def lint(fmx):
    return srv.call('delphi_designer', {'command': 'lint', 'path': fmx}, 300)


def limpio(r):
    return mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT')


def nota(r, lookup):
    return mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_ESTILO_FMT') and ("'%s'" % lookup) in r and 'Boton1' in r


try:
    carpeta = os.path.join(BASE, 'App')
    r = srv.call('delphi_create', {'kind': 'project-fmx', 'name': 'App', 'dir': carpeta})
    check('fixture creada (delphi_create)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    fmx = os.path.join(carpeta, 'UMain.fmx')
    r = srv.call('delphi_designer', {'command': 'insert', 'path': fmx, 'classname': 'TButton',
                                     'component': 'Boton1', 'props': 'StyleLookup=buttonstyle'})
    check('fixture: Boton1 insertado con buttonstyle', '"inserted":"Boton1"' in r.replace(' ', ''), r[:300])
    with open(fmx, encoding='utf-8-sig', newline='') as f:
        ORIGINAL = f.read()
    assert "StyleLookup = 'buttonstyle'" in ORIGINAL, ORIGINAL

    def con(lookup, extra=''):
        texto = ORIGINAL.replace("StyleLookup = 'buttonstyle'", "StyleLookup = '%s'" % lookup)
        if extra:
            i = texto.rindex('end')
            texto = texto[:i] + extra + texto[i:]
        with open(fmx, 'w', encoding='utf-8-sig', newline='') as f:
            f.write(texto)

    con('estiloquenoexiste')
    r = lint(fmx)
    check('L1 un lookup que no existe: el lint NO dice CLEAN', not limpio(r), r[:300])
    check('L1 ...y la nota DSGN-175 nombra Boton1 y el lookup', nota(r, 'estiloquenoexiste'), r[:500])

    con('buttonstyle')
    r = lint(fmx)
    check('L2 control: buttonstyle (del estilo por defecto): CLEAN', limpio(r), r[:300])

    con('')
    r = lint(fmx)
    check('L3 control: StyleLookup vacio (el estilo de su clase): CLEAN', limpio(r), r[:300])

    con('buttonstyle')
    r = srv.call('delphi_designer', {'command': 'set', 'path': fmx, 'component': 'Boton1',
                                     'prop': 'StyleLookup', 'value': 'otroquenoexiste'})
    check('L4 designer set de un lookup que no existe: lo escribe y lleva DSGN-175',
          'error' not in mc.como_json(r) and nota(r, 'otroquenoexiste'), r[:500])

    con('buttonstyle')
    r = srv.call('delphi_edit', {'path': fmx, 'old': "    StyleLookup = 'buttonstyle'",
                                 'new': "    StyleLookup = 'tercero'"})
    check('L5 delphi_edit que escribe un lookup que no existe: sus avisos llevan DSGN-175',
          nota(r, 'tercero'), r[:500])

    con('estiloquenoexiste', '  object StyleBook1: TStyleBook\r\n    Left = 40\r\n    Top = 40\r\n  end\r\n')
    r = lint(fmx)
    check('L6 con un TStyleBook en el form: no se juzga (sin DSGN-175)',
          not mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_ESTILO_FMT'), r[:500])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('lookup sin estilo 1.23.1 (V75)')
