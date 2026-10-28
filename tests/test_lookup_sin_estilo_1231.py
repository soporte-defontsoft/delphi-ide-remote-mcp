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

V143: tras una edicion, la nota dice solo los StyleLookup que ELLA trae (iba la lista entera en
cada edicion: 91 lineas por cambiar una Opacity, medido el 28-oct). Rojas contra b2b7024:
  L7 designer set de otra propiedad del mismo componente: sin DSGN-175
  L8 delphi_edit de una linea sin StyleLookup: sin DSGN-175
  L9 ...la tanda (edits): sin DSGN-175
  L10 ...un changeset: sin DSGN-175; y uno que cambia el lookup: la nota lo dice (control)
  L11 insert de Boton2 con un lookup que no existe: la nota dice SOLO el suyo, como de esta edicion
  L12 control: el lint del form los sigue dando todos

V123: "este StyleLookup tiene estilo" eran dos bucles, y solo la nota sabia de un StyleBook.
UN lector (Lsp.Styles.LookupsDeForm). Rojas contra b2b7024:
  L13 StyleBook = DM.StyleBook1 en la raiz: sin DSGN-175 (decia "the form has no StyleBook")
  L14 una vista FMX (raiz inherited: el StyleBook de su maestro): sin DSGN-175
  L15 delphi_styles lint de un Sample con su StyleBook (Classic Bluetooth Basic app): sus lookups
      TabItem1Style1/TabItem2Style1 no salen como faltas; el form va en formsWithAStyleBook (STYLE-057)
  L16 control: un form del mismo proyecto SIN StyleBook sigue juzgado (su lookup, en la lista)

V151: un FRAME FMX toma sus estilos del StyleBook de la form que lo aloja (FMX.Controls: el control
los busca en Scene.StyleBook, y el padre le pasa su Scene al alojarlo); su .fmx no lo dice. La nota
decia de un frame "the form takes no StyleBook... FMX then draws the control with its class's own
style". Quien sabe que la raiz es un frame: su cadena de clases (Lsp.ProjectUnits.RaizDeDesigner,
la de preview). Rojas contra f6d99ec:
  L17 insert en un frame de un boton con un lookup que no define el estilo por defecto: sin
      DSGN-175; y su lint, tampoco
  L18 delphi_styles lint del proyecto: el frame va en formsWithAStyleBook y su lookup no es una
      falta (UMain, sin StyleBook, sigue juzgado: L16 lo mide en otro proyecto)

V153: la rama .pas de delphi_styles lint (StyleLookup := 'x' en codigo) juzgaba contra los estilos
que conoce aunque la form de esa unidad tome los suyos de un StyleBook que no lee, o sea un frame:
la misma respuesta decia de la form "its StyleLookup values are not judged here" y daba por faltas
los de su codigo (medido en vivo el 28-oct). El designer de una unidad: su {$R} (InspectUnit). Rojas
contra c7868bd:
  L19 el .pas de un frame con StyleLookup := 'pasdelmarco': no es una falta
  L20 el .pas de una form con su StyleBook (el Sample): no es una falta
  L21 (control) una unidad sin designer con un StyleLookup := que nada define: sigue siendo falta

Uso:  python tests/test_lookup_sin_estilo_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import shutil
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
    # ...y su unidad: un insert de un caso deja su campo, y el lint del siguiente lo decia
    with open(os.path.join(carpeta, 'UMain.pas'), 'rb') as f:
        PAS_ORIGINAL = f.read()

    def con(lookup, extra='', raiz=''):
        texto = ORIGINAL.replace("StyleLookup = 'buttonstyle'", "StyleLookup = '%s'" % lookup)
        if extra:
            i = texto.rindex('end')
            texto = texto[:i] + extra + texto[i:]
        if raiz:
            i = texto.index('\r\n') + 2
            texto = texto[:i] + raiz + texto[i:]
        with open(fmx, 'w', encoding='utf-8-sig', newline='') as f:
            f.write(texto)
        with open(os.path.join(carpeta, 'UMain.pas'), 'wb') as f:
            f.write(PAS_ORIGINAL)

    def linea_con(texto):
        with open(fmx, encoding='utf-8-sig', newline='') as f:
            return next(x for x in f.read().split('\r\n') if texto in x)

    def sin_nota(r):
        return 'error' not in mc.como_json(r) and not mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_ESTILO_FMT')

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

    # V143: lo que la edicion trae
    con('estiloquenoexiste')
    r = srv.call('delphi_designer', {'command': 'set', 'path': fmx, 'component': 'Boton1',
                                     'prop': 'Opacity', 'value': '0.5'})
    check('L7 designer set de otra propiedad (el lookup ya estaba): sin DSGN-175', sin_nota(r), r[:500])
    lin = linea_con('Opacity')
    r = srv.call('delphi_edit', {'path': fmx, 'old': lin.strip(), 'new': lin.replace('0.5', '0.6').strip()})
    check('L8 delphi_edit de una linea sin StyleLookup: sin DSGN-175', sin_nota(r), r[:500])
    lin = linea_con('Opacity')
    r = srv.call('delphi_edit', {'path': fmx, 'edits': [{'old': lin.strip(),
                                                         'new': lin.replace('0.6', '0.7').strip()}]})
    check('L9 la tanda (edits) de una linea sin StyleLookup: sin DSGN-175', sin_nota(r), r[:500])
    lin = linea_con('Opacity')
    i = mc.id_changeset(srv.call('delphi_changeset', {'command': 'begin'}))
    srv.call('delphi_changeset', {'command': 'stage', 'id': i, 'kind': 'edit', 'path': fmx,
                                  'old': lin.strip(), 'new': lin.replace('0.7', '0.8').strip()})
    srv.call('delphi_changeset', {'command': 'preview', 'id': i})
    r = srv.call('delphi_changeset', {'command': 'commit', 'id': i})
    check('L10 un changeset de una linea sin StyleLookup: sin DSGN-175',
          '0.8' in linea_con('Opacity') and sin_nota(r), r[:500])
    lin = linea_con('estiloquenoexiste')
    i = mc.id_changeset(srv.call('delphi_changeset', {'command': 'begin'}))
    srv.call('delphi_changeset', {'command': 'stage', 'id': i, 'kind': 'edit', 'path': fmx,
                                  'old': lin.strip(), 'new': "StyleLookup = 'cuarto'"})
    srv.call('delphi_changeset', {'command': 'preview', 'id': i})
    r = srv.call('delphi_changeset', {'command': 'commit', 'id': i})
    check('L10 ...y uno que cambia el lookup: la nota lo dice (control)', nota(r, 'cuarto'), r[:500])
    r = srv.call('delphi_designer', {'command': 'insert', 'path': fmx, 'classname': 'TButton',
                                     'component': 'Boton2', 'props': 'StyleLookup=nuevoquenoexiste'})
    DE_LA_EDICION = mc.catalogo()['SF_DESIGNER_LOOKUPS_DE_LA_EDICION'].strip()[:30]
    check('L11 insert de Boton2 con un lookup que no existe: la nota dice SOLO el suyo, como de esta edicion',
          mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_ESTILO_FMT') and "'nuevoquenoexiste'" in r and
          "'cuarto'" not in r and DE_LA_EDICION in r, r[:700])
    r = lint(fmx)
    check('L12 control: el lint del form los sigue dando todos', "'nuevoquenoexiste'" in r and
          nota(r, 'cuarto') and DE_LA_EDICION not in r, r[:700])

    # V123: un StyleBook que estas lineas no dejan leer
    con('estiloquenoexiste', raiz='  StyleBook = DM.StyleBook1\r\n')
    r = lint(fmx)
    check('L13 StyleBook = DM.StyleBook1 en la raiz: sin DSGN-175 (no es "the form has no StyleBook")',
          not mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_ESTILO_FMT'), r[:500])
    con('buttonstyle')
    pas = os.path.join(carpeta, 'UMain.pas')
    with open(pas, encoding='utf-8-sig', newline='') as f:
        t = f.read()
    assert '{$R *.fmx}' in t, t
    with open(pas, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(t.replace('{$R *.fmx}', '{$R *.fmx}\r\n{$R *.Windows.fmx MSWINDOWS}', 1))
    vista = os.path.join(carpeta, 'UMain.Windows.fmx')
    with open(vista, 'w', encoding='utf-8-sig', newline='') as f:
        f.write('inherited FormMain_Windows: TFormMain_Windows\r\n  inherited Boton1: TButton\r\n'
                "    StyleLookup = 'devistaquenoexiste'\r\n  end\r\nend\r\n")
    r = lint(vista)
    check('L14 una vista FMX (el StyleBook de su maestro): sin DSGN-175',
          not mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_ESTILO_FMT') and 'devistaquenoexiste' not in r, r[:500])

    # un Sample con su StyleBook, del BDSCOMMONDIR que pone el rsvars.bat del IDE (como el corpus)
    SAMPLE_BT = os.path.join(mc.variable_de_rsvars(srv.call, 'BDSCOMMONDIR'), 'Samples', 'Object Pascal',
                             'Multi-Device Samples', 'Device Sensors and Services', 'Bluetooth',
                             'Classic Bluetooth Basic app')
    check('L15 el Sample con StyleBook esta en esta maquina', os.path.isdir(SAMPLE_BT), SAMPLE_BT)
    bt = os.path.join(BASE, 'bt')
    shutil.copytree(SAMPLE_BT, bt)
    estilos = os.path.join(bt, 'Styles')
    os.makedirs(estilos)
    with open(os.path.join(estilos, 'Uno.style'), 'w', newline='') as f:
        f.write("object TStyleContainer\r\n  object TLayout\r\n    StyleName = 'mibotonstyle'\r\n  end\r\nend\r\n")
    with open(os.path.join(bt, 'Otro.fmx'), 'w', encoding='utf-8-sig', newline='') as f:
        f.write("object F2: TForm\r\n  object B: TButton\r\n    StyleLookup = 'faltaenotro'\r\n  end\r\nend\r\n")
    r = srv.call('delphi_styles', {'command': 'lint', 'path': estilos, 'project': bt}, 300)
    j = mc.como_json(r)
    faltas = json.dumps(j.get('lookupsWithoutStyle'))
    check('L15 el lint de un form con su StyleBook: TabItem1Style1 no es una falta',
          'TabItem1Style1' not in faltas and 'TabItem2Style1' not in faltas, faltas)
    check('L15 ...va en formsWithAStyleBook, con su nota STYLE-057',
          any(x.endswith('Unit1.fmx') for x in (j.get('formsWithAStyleBook') or [])) and
          mc.es(r, 'SN_STYLES_FORMS_CON_STYLEBOOK'), r[:800])
    check('L16 control: un form SIN StyleBook del mismo proyecto sigue juzgado', 'faltaenotro' in faltas, faltas)

    # V151: un frame toma el StyleBook de la form que lo aloja
    con('buttonstyle')
    r = srv.call('delphi_create', {'kind': 'frame-fmx', 'name': 'UMarco',
                                   'project': os.path.join(carpeta, 'App.dproj')})
    check('fixture: el frame UMarco creado', 'UMarco' in r and 'error' not in mc.como_json(r), r[:300])
    marco = os.path.join(carpeta, 'UMarco.fmx')
    r = srv.call('delphi_designer', {'command': 'insert', 'path': marco, 'classname': 'TButton',
                                     'component': 'BotonMarco', 'props': 'StyleLookup=delanfitrion'})
    check('L17 insert en un frame con un lookup del StyleBook de su anfitrion: escrito y sin DSGN-175',
          '"inserted":"BotonMarco"' in r.replace(' ', '') and
          not mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_ESTILO_FMT'), r[:700])
    r = lint(marco)
    check('L17 ...y el lint del frame, tampoco', not mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_ESTILO_FMT') and
          'delanfitrion' not in r, r[:500])
    estilos_app = os.path.join(carpeta, 'Styles')
    os.makedirs(estilos_app)
    with open(os.path.join(estilos_app, 'Uno.style'), 'w', newline='') as f:
        f.write("object TStyleContainer\r\n  object TLayout\r\n    StyleName = 'mibotonstyle'\r\n  end\r\nend\r\n")
    r = srv.call('delphi_styles', {'command': 'lint', 'path': estilos_app, 'project': carpeta}, 300)
    j = mc.como_json(r)
    faltas = json.dumps(j.get('lookupsWithoutStyle'))
    check('L18 delphi_styles lint: el lookup del frame no es una falta', 'delanfitrion' not in faltas, faltas)
    check('L18 ...y el frame va en formsWithAStyleBook, con STYLE-057',
          any(x.endswith('UMarco.fmx') for x in (j.get('formsWithAStyleBook') or [])) and
          mc.es(r, 'SN_STYLES_FORMS_CON_STYLEBOOK'), r[:800])

    # V153: el codigo de una unidad cuya form toma un StyleBook que no se lee
    def con_codigo(pas, lookup):
        with open(pas, encoding='utf-8-sig', newline='') as f:
            t = f.read()
        i = t.rindex('end.')
        t = t[:i] + ('procedure PonEstilo(C: TStyledControl);\r\nbegin\r\n  C.StyleLookup := \'%s\';\r\n'
                     'end;\r\n\r\n' % lookup) + t[i:]
        with open(pas, 'w', encoding='utf-8-sig', newline='') as f:
            f.write(t)

    con_codigo(os.path.join(carpeta, 'UMarco.pas'), 'pasdelmarco')
    plano = os.path.join(carpeta, 'UPlano.pas')
    with open(plano, 'w', encoding='utf-8-sig', newline='') as f:
        f.write('unit UPlano;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n')
    con_codigo(plano, 'pasplano')
    r = srv.call('delphi_styles', {'command': 'lint', 'path': estilos_app, 'project': carpeta}, 300)
    faltas = json.dumps(mc.como_json(r).get('lookupsWithoutStyle'))
    check('L19 el .pas de un frame: su StyleLookup := no es una falta', 'pasdelmarco' not in faltas, faltas)
    check('L21 (control) una unidad sin designer: su StyleLookup := sigue siendo falta', 'pasplano' in faltas, faltas)
    con_codigo(os.path.join(bt, 'Unit1.pas'), 'pasdelsample')
    r = srv.call('delphi_styles', {'command': 'lint', 'path': estilos, 'project': bt}, 300)
    faltas = json.dumps(mc.como_json(r).get('lookupsWithoutStyle'))
    check('L20 el .pas de una form con su StyleBook: no es una falta', 'pasdelsample' not in faltas, faltas)
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('lookup sin estilo 1.23.1 (V75, V123, V143, V151, V153)')
