# -*- coding: utf-8 -*-
"""delphi_designer insert / set / delete (1.17.0, Lsp.DesignerEdit): editar
un form y su unidad como el IDE, solo lo basico (David, 4 y 7-oct-2026). El
criterio de lo basico es que el componente SE VEA: cada paso se comprueba con
el proyecto recien creado COMPILANDO, check-binding y lint limpios, y preview
de ORACULO (donde lo dibuja el renderizador, y por pixel). Lo que se mide
sobre textos (el analizador de impacto, los planes) esta en LspTests.DesignerEdit.

  V1  insert en VCL: el bloque minimo (10,10, Caption, TabOrder), el campo
      published, Vcl.StdCtrls en el uses; build, binding, lint, y preview lo
      pinta en 10,10 con el tamano de su constructor y su texto
  V2  insert de un contenedor y de un control dentro (parent=)
  V3  set de una propiedad que se ve: el panel amarillo, por pixel
  V4  set juzgado ANTES de escribir: propiedad que no existe (y la parecida),
      enumerado que no existe, entero que no lo es, cadena sin comillas (las
      pone, con su acento como el IDE), evento, componente que no esta,
      referencia que no esta, parent con prop, value que falta
  V4b el valor por lo que acepta su tipo, leido del fuente (base B, constantes
      I): una cadena en un TColor, una constante mal escrita (con la parecida),
      un decimal en un TCursor; crHandPoint si
  V5  set parent=: mueve el bloque, TabOrder el siguiente, avisa si cae fuera
      del padre (layout), preview lo pinta en su sitio nuevo; ciclo, padre que
      no es contenedor, clase no visual, clase que no existe
  V6  delete: NIEGA con un manejador con cuerpo (y no escribe nada); con el
      manejador vacio, lo quita con el campo; un contenedor con su hijo y la
      referencia de otro componente a el
  V7  set Name: el form, su Caption que era su nombre, el campo; nombre ocupado
      y nombre que no vale
  V7b insert con nombre (component=): las reglas del renombrado (ocupado sin
      mirar mayusculas, la clase del form, reservada; con comillas vale) y su
      Caption nace con ese nombre; build, binding, lint y preview
  V8  todo o nada: la unidad de solo lectura y el form vuelve a como estaba
  V9  el DataSource de un TDBGrid: un componente de otra clase se niega con los
      que caben (DSGN-107); DataSource1 si; compila
  V10 un frame: su tamano y un control en su .dfm; metido en el form (inline)
      su tamano lo juzga TFrame (su clase es del proyecto); compila
  V10b delete: el campo con un comentario que sigue debajo niega (DSGN-108) y
      la declaracion de su manejador asi se queda (handlersKept); compila
  V10c set Name: su texto en trozos al crecer y leido entero al volver, y la
      referencia de debajo contada en el form que queda (Delta); compila
  V10d una ruta por una referencia (PopupMenu.AutoPopup con PopupMenu =
      PopupMenu1): set la niega (DSGN-119) y el lint la avisa; un
      subcomponente (EditLabel.Caption) entra; compila
  F1  insert en FMX: Position con 18 decimales, Text solo en las clases cuyo
      SetName lo pone, leido del fuente por el generador (TButton y TLabel si;
      TRectangle no; TEditButton no: el suyo lo vacia - el caso medido en 13.1),
      FMX.StdCtrls; un TLabel con nombre, su Text con el; build, binding, lint
      y preview
  F2  set de un color FMX que se ve, por pixel (una cadena no; xFF00FF00 si);
      una Single escrita como el IDE (0.7 -> 0.699999988079071000);
      set parent= en FMX; delete
  R1-R16 la revision de la 1.17.0 (escrituras que rompian el form diciendo OK):
      la cadena larga del IDE reescrita entera, #39, un Hint de 5000 en trozos;
      una llave en una cadena; Items = <> en un item y check-binding despues;
      literales como el IDE; valores que el cargador no lee; nil quita;
      TStrings (DSGN-109); csAcceptsControls (TPageControl/TButton no,
      TGroupBox si); los nombres de un frame en linea no son del form; un data
      module no recibe controles; la base de otra unidad de la carpeta; FMX
      Align = Client no es una referencia; TAlphaColor abierta (DSGN-110); el
      mapa de delphi_help; insert sin salida: no visual a mano, uses en ramas;
      una referencia de tipo interfaz (TFDBatchMove.Reader) renombrada y borrada
  X1  rechazos sin tabla: .dfm binario, sin unidad, frame inline, heredado, el
      form mismo; parametros; fuera de la jaula; credencial de solo lectura

Uso:  python tests/test_designer_edit.py [ruta-a-DelphiLspMcp.exe]
"""
import atexit, glob, json, os, re, shutil
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer_edit')
# se borra AUNQUE la bateria caiga a medias: sin esto una excepcion dejaba el
# arbol en %TEMP% (revision de la 1.17.0)
atexit.register(mc.borra, BASE)
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
OUT = os.path.join(JAIL, 'out')
for d in (JAIL, FUERA, OUT):
    os.makedirs(d, exist_ok=True)

AMARILLO = (255, 255, 0)    # clYellow
ROJO = (255, 0, 0)          # claRed


def J(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


def escribe(ruta, texto):
    """El texto TAL CUAL (sus CRLF ya van en el: con newline='\\r\\n' un CRLF
    leido con mc.lee salia CR CR LF) y con el BOM si el fichero lo tenia."""
    bom = bytes_de(ruta).startswith(b'\xef\xbb\xbf')
    with open(ruta, 'w', encoding='utf-8-sig' if bom else 'utf-8', newline='') as f:
        f.write(texto)
    return ruta


def bytes_de(ruta):
    return open(ruta, 'rb').read() if os.path.exists(ruta) else b''


def cerca(p, q, tol=3):
    return p is not None and all(abs(a - b) <= tol for a, b in zip(p, q))


def pixel_de(png, x, y):
    try:
        return mc.png_pixeles(png)[2](x, y)
    except Exception:
        return None


def oscuros(png):
    """Cuantos pixeles oscuros tiene una captura: el texto pintado."""
    try:
        ancho, alto, px = mc.png_pixeles(png)
    except Exception:
        return -1
    return sum(1 for y in range(alto) for x in range(ancho) if sum(px(x, y)) < 300)


EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
ENV = mc.entorno({'DELPHI_MCP_ROOTS': JAIL})
srv = mc.Stdio(EXE, ENV, nombre='designer-edit', t=300)
call = srv.call


def dsg(**kw):
    return call('delphi_designer', kw, t=300)


N_PNG = [0]


def rect_de(path, comp):
    """(componentRect, png) de preview recortado a comp: donde lo DIBUJA el
    renderizador, el oraculo."""
    N_PNG[0] += 1
    png = os.path.join(OUT, 'p%d.png' % N_PNG[0])
    r = dsg(command='preview', path=path, component=comp, out=png, inline='false')
    return J(r).get('componentRect'), png


def compila_y_cuadra(etiqueta, dproj, form):
    ok, err = mc.build_ok(call, dproj)
    check(etiqueta + ' ...y el proyecto COMPILA', ok, err)
    r = dsg(command='check-binding', path=form)
    check(etiqueta + ' ...check-binding limpio', J(r).get('clean') is True, r[:400])
    r = dsg(command='lint', path=form)
    check(etiqueta + ' ...lint limpio', mc.es(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:400])


try:
    for fw, r in mc.espera_tablas(call):
        check('T0 la tabla del disenador %s esta lista' % fw,
              not mc.tiene(r, 'DSGN-051') and not mc.fallo(r), r[:200])

    # =================================================================== VCL
    VDIR = os.path.join(JAIL, 'EdVcl')
    r = call('delphi_create', {'kind': 'project-vcl', 'dir': VDIR, 'name': 'EdVcl'})
    check('V0 un proyecto VCL recien creado', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    VPROJ = os.path.join(VDIR, 'EdVcl.dproj')
    VDFM = (glob.glob(os.path.join(VDIR, '*.dfm')) or [''])[0]
    VPAS = VDFM[:-4] + '.pas'
    CLASE = (re.search(r'^object \w+: (\w+)', mc.lee(VDFM)) or re.search('()', '')).group(1)

    # ------------------------------------------------------------------ V1
    r = dsg(command='insert', path=VDFM, classname='TButton')
    j = J(r)
    check('V1 insert: Button1 en el form, con su bloque numerado, su campo y su unidad',
          j.get('inserted') == 'Button1' and j.get('class') == 'TButton' and
          j.get('parent') == (re.search(r'^object (\w+)', mc.lee(VDFM)) or re.search('()', '')).group(1) and
          j.get('usesAdded') == 'Vcl.StdCtrls' and j.get('field') == 'Button1: TButton' and
          any('object Button1: TButton' in b for b in j.get('block', [])) and
          mc.es(j.get('note', ''), 'SN_DESIGNER_INSERT_NOTE'), r[:700])
    dfm, pas = mc.lee(VDFM), mc.lee(VPAS)
    check('V1 ...lo minimo del IDE: 10,10, su nombre de Caption, TabOrder 0; ningun tamano',
          re.search(r"\r\n  object Button1: TButton\r\n    Left = 10\r\n    Top = 10\r\n"
                    r"    Caption = 'Button1'\r\n    TabOrder = 0\r\n  end\r\nend", dfm) is not None, dfm[-300:])
    check('V1 ...el campo en la seccion published de la clase y Vcl.StdCtrls en el uses del interface',
          re.search(r'= class\(TForm\)\r\n    Button1: TButton;', pas) is not None and
          'Vcl.StdCtrls' in pas.split('implementation')[0], pas[:700])
    compila_y_cuadra('V1', VPROJ, VDFM)
    rect, png = rect_de(VDFM, 'Button1')
    check('V1 ...y preview lo DIBUJA donde dice: 10,10 con el tamano de su constructor (75x25)',
          rect == '10,10,75,25', rect)
    check('V1 ...con su texto pintado (pixeles oscuros dentro del boton)', oscuros(png) > 5, oscuros(png))

    # ------------------------------------------------------------------ V2
    r = dsg(command='insert', path=VDFM, classname='TPanel')
    check('V2 insert de un contenedor: Panel1 con su Caption y el TabOrder siguiente (1)',
          J(r).get('inserted') == 'Panel1' and
          re.search(r"object Panel1: TPanel\r\n    Left = 10\r\n    Top = 10\r\n    Caption = 'Panel1'\r\n"
                    r"    TabOrder = 1\r\n", mc.lee(VDFM)) is not None, r[:300])
    r = dsg(command='insert', path=VDFM, classname='TEdit', parent='Panel1')
    j = J(r)
    check('V2 insert dentro de un padre: Edit1, Text con su nombre, TabOrder 0 dentro de Panel1',
          j.get('inserted') == 'Edit1' and j.get('parent') == 'Panel1' and
          re.search(r"    object Edit1: TEdit\r\n      Left = 10\r\n      Top = 10\r\n      Text = 'Edit1'\r\n"
                    r"      TabOrder = 0\r\n    end\r\n  end", mc.lee(VDFM)) is not None, r[:400])
    check('V2 ...sin aviso de fuera del padre (cabe)', 'outsideParent' not in j, r[:400])

    # ------------------------------------------------------------------ V3
    r = dsg(command='set', path=VDFM, component='Panel1', prop='Color', value='clYellow')
    check('V3 set: Panel1.Color = clYellow, con su linea', J(r).get('set') == 'Panel1.Color' and
          J(r).get('line', 0) > 0 and '    Color = clYellow' in mc.lee(VDFM), r[:300])
    r = dsg(command='set', path=VDFM, component='Panel1', prop='ParentBackground', value='False')
    check('V3 set de un Boolean', '    ParentBackground = False' in mc.lee(VDFM), r[:300])
    rect, png = rect_de(VDFM, 'Panel1')
    check('V3 ...y preview lo pinta: el panel (185x41 de su constructor) amarillo donde no esta el edit',
          rect == '10,10,185,41' and cerca(pixel_de(png, 170, 36), AMARILLO), (rect, pixel_de(png, 170, 36)))

    # ------------------------------------------------------------------ V4
    antes = bytes_de(VDFM)
    r = dsg(command='set', path=VDFM, component='Button1', prop='Captoin', value="'x'")
    check('V4 una propiedad que la clase no publica: DSGN-087 con la parecida, nada escrito',
          mc.abre(r, 'SR_DESIGNER_SET_INVALIDO_FMT') and 'Did you mean Caption?' in r and bytes_de(VDFM) == antes,
          r[:400])
    r = dsg(command='set', path=VDFM, component='Panel1', prop='Align', value='alNada')
    check('V4 un valor de enumerado que no existe: DSGN-087 con los legales',
          mc.abre(r, 'SR_DESIGNER_SET_INVALIDO_FMT') and 'alClient' in r and bytes_de(VDFM) == antes, r[:400])
    r = dsg(command='set', path=VDFM, component='Button1', prop='Left', value='abc')
    check('V4 un entero que no lo es: DSGN-093', mc.abre(r, 'SR_DESIGNER_SET_TIPO_FMT') and
          bytes_de(VDFM) == antes, r[:300])
    r = dsg(command='set', path=VDFM, component='Button1', prop='OnClick', value='Algo')
    check('V4 un evento: DSGN-088 (set no ata eventos)', mc.abre(r, 'SR_DESIGNER_SET_EVENTO_FMT'), r[:300])
    r = dsg(command='set', path=VDFM, component='NoHay', prop='Caption', value='x')
    check('V4 un componente que no esta: DSGN-078 con los que si y "insert"',
          mc.abre(r, 'SR_DESIGNER_COMPONENTE_NO_ESTA_FMT') and 'Button1' in r and 'insert' in r, r[:300])
    r = dsg(command='set', path=VDFM, component='Button1', prop='PopupMenu', value='PopupNo')
    check('V4 una referencia a un componente que no esta: DSGN-098',
          mc.abre(r, 'SR_DESIGNER_REFERENCIA_NO_ESTA_FMT'), r[:300])
    r = dsg(command='set', path=VDFM, component='Button1', prop='Caption', value='x', parent='Panel1')
    check('V4 parent con prop: DSGN-094', mc.abre(r, 'SR_DESIGNER_SET_PARENT_SOLO'), r[:300])
    r = dsg(command='set', path=VDFM, component='Button1', prop='Caption')
    check('V4 sin value: DSGN-090', mc.abre(r, 'SR_DESIGNER_SET_SIN_VALOR'), r[:300])
    check('V4 ...y nada de eso escribio', bytes_de(VDFM) == antes, '')
    r = dsg(command='set', path=VDFM, component='Button1', prop='Caption', value='Aceptar')
    check('V4 una cadena sin comillas: set se las pone (quoted) y escribe el valor anterior',
          J(r).get('quoted') is True and J(r).get('previous') == "'Button1'" and
          "    Caption = 'Aceptar'" in mc.lee(VDFM), r[:300])
    r = dsg(command='set', path=VDFM, component='Button1', prop='Caption', value='Acción')
    check('V4 ...con un acento, como lo escribe el IDE (#243)',
          "    Caption = 'Acci'#243'n'" in mc.lee(VDFM), r[:300])

    # ------------------------------------------------------------------ V4b
    # el valor, por lo que el cargador (TReader) acepta para su tipo, leido
    # del fuente por el generador (David, 7-oct-2026: comprobar tipos de
    # verdad, sin listas): la base del tipo (hecho B) y las constantes de un
    # entero (hecho I). Los tres casos medidos en vivo esa manana se escribian
    antes = bytes_de(VDFM)
    r = dsg(command='set', path=VDFM, component='Panel1', prop='Color', value="'hola'")
    check('V4b una cadena en un TColor: DSGN-093', mc.abre(r, 'SR_DESIGNER_SET_TIPO_FMT'), r[:300])
    r = dsg(command='set', path=VDFM, component='Panel1', prop='Color', value='clYelow')
    check('V4b una constante mal escrita: DSGN-093 con las del mapa del fuente y la parecida',
          mc.abre(r, 'SR_DESIGNER_SET_TIPO_FMT') and 'Did you mean clYellow?' in r and 'clBlack' in r, r[:400])
    r = dsg(command='set', path=VDFM, component='Button1', prop='Cursor', value='3.5')
    check('V4b un decimal en un TCursor: DSGN-093', mc.abre(r, 'SR_DESIGNER_SET_TIPO_FMT'), r[:300])
    check('V4b ...y nada de eso escribio', bytes_de(VDFM) == antes, '')
    r = dsg(command='set', path=VDFM, component='Button1', prop='Cursor', value='crHandPoint')
    check('V4b una constante de TCursor que si esta (la VCL la delega en System.UIConsts)',
          '    Cursor = crHandPoint' in mc.lee(VDFM), r[:300])

    # ------------------------------------------------------------------ V5
    r = dsg(command='set', path=VDFM, component='Button1', prop='Left', value='300')
    check('V5 set de un entero', '    Left = 300' in mc.lee(VDFM), r[:300])
    # el tamano del panel, escrito: el de su constructor no esta en el .dfm, y
    # layout no juzga "fuera" de un padre cuyo tamano no sabe
    dsg(command='set', path=VDFM, component='Panel1', prop='Width', value='185')
    dsg(command='set', path=VDFM, component='Panel1', prop='Height', value='41')
    r = dsg(command='set', path=VDFM, component='Button1', parent='Panel1')
    j = J(r)
    check('V5 set parent=: Button1 a Panel1, el TabOrder siguiente alli (1)',
          j.get('moved') == 'Button1' and j.get('to') == 'Panel1' and j.get('tabOrder') == 1, r[:500])
    check('V5 ...y como no cabe (Left 300 en un panel de 185) la respuesta lo dice',
          any(x.startswith('Button1:') for x in j.get('outsideParent', [])), r[:600])
    check('V5 ...el bloque entero, con su sangria nueva, ultimo hijo de Panel1',
          re.search(r"      TabOrder = 0\r\n    end\r\n    object Button1: TButton\r\n(      [^\r\n]*\r\n)*      Left = 300\r\n",
                    mc.lee(VDFM)) is not None, mc.lee(VDFM)[-500:])
    dsg(command='set', path=VDFM, component='Button1', prop='Left', value='60')
    rect, png = rect_de(VDFM, 'Button1')
    check('V5 ...y preview lo pinta en su sitio nuevo: el panel (10,10) mas su Left/Top (60,10)',
          rect == '70,20,75,25', rect)
    r = dsg(command='set', path=VDFM, component='Panel1', parent='Edit1')
    check('V5 un padre que esta dentro de el: DSGN-097', mc.abre(r, 'SR_DESIGNER_PADRE_CICLO_FMT'), r[:300])
    r = dsg(command='insert', path=VDFM, classname='TLabel')
    check('V5 insert de un TLabel: Caption, sin TabOrder (no lo publica)',
          J(r).get('inserted') == 'Label1' and
          re.search(r"object Label1: TLabel\r\n    Left = 10\r\n    Top = 10\r\n    Caption = 'Label1'\r\n  end",
                    mc.lee(VDFM)) is not None, r[:300])
    r = dsg(command='insert', path=VDFM, classname='TButton', parent='Label1')
    check('V5 un padre que no es contenedor en VCL: DSGN-080', mc.abre(r, 'SR_DESIGNER_PADRE_VCL_FMT'), r[:300])
    r = dsg(command='insert', path=VDFM, classname='TTimer')
    check('V5 una clase no visual: DSGN-079', mc.abre(r, 'SR_DESIGNER_INSERT_NO_VISUAL_FMT'), r[:300])
    r = dsg(command='insert', path=VDFM, classname='TNoExisteJamas')
    check('V5 una clase que no esta en la tabla: DSGN-015', mc.abre(r, 'SR_DESIGNER_CLASS_FMT'), r[:300])
    compila_y_cuadra('V5', VPROJ, VDFM)

    # ------------------------------------------------------------------ V6
    r = call('delphi_edit', {'path': VPAS, 'insert': 'metodo', 'inclass': CLASE, 'visibility': 'published',
                             'code': "procedure Button1Click(Sender: TObject);\nbegin\n  Caption := 'x';\nend;"})
    escribe(VDFM, re.sub(r'(\r\n(\s+)object Button1: TButton\r\n)', r'\1\2  OnClick = Button1Click\r\n',
                         mc.lee(VDFM)))
    check('V6 preparado: Button1 con un OnClick que tiene cuerpo (y compila)',
          'OnClick = Button1Click' in mc.lee(VDFM) and mc.build_ok(call, VPROJ)[0], r[:200])
    antes_dfm, antes_pas = bytes_de(VDFM), bytes_de(VPAS)
    r = dsg(command='delete', path=VDFM, component='Button1')
    check('V6 delete con un manejador CON cuerpo: DSGN-086, con el metodo y su linea',
          mc.abre(r, 'SR_DESIGNER_DELETE_BLOQUEADO_FMT') and re.search(r'Button1Click \(\w+\.pas:\d+, Button1\.OnClick\)', r)
          is not None, r[:500])
    check('V6 ...y NO escribio nada, ni el form ni la unidad',
          bytes_de(VDFM) == antes_dfm and bytes_de(VPAS) == antes_pas, '')
    escribe(VPAS, mc.lee(VPAS).replace("  Caption := 'x';\r\n", ''))
    r = dsg(command='delete', path=VDFM, component='Button1')
    j = J(r)
    check('V6 con el manejador vacio: borrado, con su campo y su manejador',
          j.get('deleted') == 'Button1' and any('Button1Click' in x for x in j.get('handlersRemoved', [])) and
          any(x.startswith('Button1 (') for x in j.get('fieldsRemoved', [])) and
          mc.es(j.get('note', ''), 'SN_DESIGNER_DELETE_NOTE'), r[:600])
    dfm, pas = mc.lee(VDFM), mc.lee(VPAS)
    check('V6 ...ni rastro en el form ni en la unidad', 'Button1' not in dfm and 'Button1' not in pas, pas[-400:])
    compila_y_cuadra('V6', VPROJ, VDFM)
    r = dsg(command='set', path=VDFM, component='Label1', prop='FocusControl', value='Label1')
    check('V6 una referencia de otra clase (FocusControl es un TWinControl, Label1 un TLabel): DSGN-107 '
          'con los que caben', mc.abre(r, 'SR_DESIGNER_REFERENCIA_TIPO_FMT') and 'Edit1' in r and 'Panel1' in r,
          r[:400])
    r = dsg(command='set', path=VDFM, component='Label1', prop='FocusControl', value='Edit1')
    check('V6 set de una referencia a un componente que si esta', '    FocusControl = Edit1' in mc.lee(VDFM), r[:300])
    r = dsg(command='delete', path=VDFM, component='Panel1')
    j = J(r)
    check('V6 delete de un contenedor: con su hijo, y la referencia de Label1 a el fuera',
          j.get('deleted') == 'Panel1' and j.get('alsoDeleted') == ['Edit1'] and
          any('FocusControl = Edit1' in x for x in j.get('referencesRemoved', [])), r[:600])
    dfm = mc.lee(VDFM)
    check('V6 ...Label1 sigue, sin su FocusControl', 'object Label1: TLabel' in dfm and 'FocusControl' not in dfm and
          'Panel1' not in dfm and 'Edit1' not in dfm, dfm[-400:])
    compila_y_cuadra('V6b', VPROJ, VDFM)

    # ------------------------------------------------------------------ V7
    r = dsg(command='insert', path=VDFM, classname='TButton')
    check('V7 insert vuelve a dar Button1 (el nombre esta libre otra vez)', J(r).get('inserted') == 'Button1', r[:200])
    r = dsg(command='set', path=VDFM, component='Button1', prop='Name', value='BtnOk')
    j = J(r)
    check('V7 set Name: renombrado en el form y en su campo',
          j.get('renamed') == 'Button1' and j.get('to') == 'BtnOk' and 'fieldAt' in j and
          mc.es(j.get('note', ''), 'SN_DESIGNER_RENAME_NOTE'), r[:500])
    dfm, pas = mc.lee(VDFM), mc.lee(VPAS)
    check('V7 ...su Caption, que era su nombre, sigue al nombre (como el IDE)',
          'object BtnOk: TButton' in dfm and "Caption = 'BtnOk'" in dfm and 'BtnOk: TButton;' in pas and
          'Button1' not in dfm + pas, dfm[-300:])
    compila_y_cuadra('V7', VPROJ, VDFM)
    rect, _ = rect_de(VDFM, 'BtnOk')
    check('V7 ...y preview lo encuentra con su nombre nuevo', rect == '10,10,75,25', rect)
    r = dsg(command='set', path=VDFM, component='BtnOk', prop='Name', value='Label1')
    check('V7 un nombre ocupado: DSGN-096', mc.abre(r, 'SR_DESIGNER_NOMBRE_OCUPADO_FMT'), r[:300])
    r = dsg(command='set', path=VDFM, component='BtnOk', prop='Name', value='1abc')
    check('V7 un nombre que no vale: DSGN-095', mc.abre(r, 'SR_DESIGNER_NOMBRE_INVALIDO_FMT'), r[:300])
    # el Name como literal del form (como lo escribe el IDE): su texto, igual
    # que en delphi_styles; quitaba las comillas a mano y 'Btn'#83'i' quedaba
    # en Btn'#83'i, negado (P5 de la segunda revision de la 1.17.0)
    r = dsg(command='set', path=VDFM, component='BtnOk', prop='Name', value="'Btn'#83'i'")
    j = J(r)
    literal_ok = j.get('to') == 'BtnSi' and 'object BtnSi: TButton' in mc.lee(VDFM)
    r2 = dsg(command='set', path=VDFM, component='BtnSi', prop='Name', value='BtnOk')
    check('V7 set Name con un literal del form: su texto (BtnSi), y de vuelta',
          literal_ok and J(r2).get('to') == 'BtnOk', r[:300] + ' | ' + r2[:200])

    # ------------------------------------------------------------------ V7b
    # insert con nombre: las reglas del renombrado (un solo juez), y su texto
    # nace con ese nombre, como en el IDE al teclearlo
    r = dsg(command='insert', path=VDFM, classname='TButton', component='BtnAceptar')
    j = J(r)
    check('V7b insert component=: BtnAceptar, con su campo de ese nombre',
          j.get('inserted') == 'BtnAceptar' and j.get('field') == 'BtnAceptar: TButton', r[:400])
    dfm, pas = mc.lee(VDFM), mc.lee(VPAS)
    check('V7b ...y su Caption nace con su nombre (el texto sigue al nombre)',
          re.search(r"object BtnAceptar: TButton\r\n    Left = 10\r\n    Top = 10\r\n    Caption = 'BtnAceptar'\r\n",
                    dfm) is not None and 'BtnAceptar: TButton;' in pas, dfm[-300:])
    antes_dfm, antes_pas = bytes_de(VDFM), bytes_de(VPAS)
    r = dsg(command='insert', path=VDFM, classname='TButton', component='btnaceptar')
    check('V7b un nombre ocupado, sin mirar mayusculas: DSGN-096', mc.abre(r, 'SR_DESIGNER_NOMBRE_OCUPADO_FMT'),
          r[:300])
    r = dsg(command='insert', path=VDFM, classname='TButton', component=CLASE)
    check('V7b el nombre de la clase del form: DSGN-096', mc.abre(r, 'SR_DESIGNER_NOMBRE_OCUPADO_FMT'), r[:300])
    r = dsg(command='insert', path=VDFM, classname='TButton', component='begin')
    check('V7b una palabra reservada: DSGN-095', mc.abre(r, 'SR_DESIGNER_NOMBRE_INVALIDO_FMT'), r[:300])
    check('V7b ...y nada de eso escribio', bytes_de(VDFM) == antes_dfm and bytes_de(VPAS) == antes_pas, '')
    r = dsg(command='insert', path=VDFM, classname='TButton', component="'BtnCancelar'")
    check('V7b con comillas tambien (como en set Name)', J(r).get('inserted') == 'BtnCancelar' and
          "Caption = 'BtnCancelar'" in mc.lee(VDFM), r[:300])
    compila_y_cuadra('V7b', VPROJ, VDFM)
    rect, _ = rect_de(VDFM, 'BtnAceptar')
    check('V7b ...y preview lo encuentra con su nombre', rect == '10,10,75,25', rect)
    # sin component=, el nombre del IDE: la clase sin su T y el primer numero
    # libre (David, 7-oct-2026: Label1 existe, luego Label2)
    r = dsg(command='insert', path=VDFM, classname='TLabel')
    check('V7b sin component=, como el IDE: Label1 existe, sale Label2 con su Caption',
          J(r).get('inserted') == 'Label2' and "Caption = 'Label2'" in mc.lee(VDFM), r[:300])

    # ------------------------------------------------------------------ V8
    antes_dfm = bytes_de(VDFM)
    with mc.solo_lectura(VPAS):
        r = dsg(command='insert', path=VDFM, classname='TCheckBox')
    check('V8 la unidad no se deja escribir: el insert falla...', mc.fallo(r) or mc.rechazado(r), r[:300])
    check('V8 ...y el form vuelve a como estaba (todo o nada)', bytes_de(VDFM) == antes_dfm,
          mc.lee(VDFM)[-300:])

    # ------------------------------------------------------------------ V9
    # el ejemplo de David: el DataSource de un TDBGrid solo apunta a un
    # TDataSource (o a una hija); otra clase se niega y la respuesta dice cuales
    # caben. El TDataSource no es visual (insert no lo pone): a mano, como el IDE
    r = dsg(command='insert', path=VDFM, classname='TDBGrid', component='Rejilla')
    check('V9 insert de un TDBGrid (Vcl.DBGrids en el uses)', J(r).get('inserted') == 'Rejilla' and
          J(r).get('usesAdded') == 'Vcl.DBGrids', r[:300])
    escribe(VDFM, re.sub(r'\r\nend\r\n$', '\r\n  object DataSource1: TDataSource\r\n    Left = 300\r\n'
                         '    Top = 10\r\n  end\r\nend\r\n', mc.lee(VDFM)))
    escribe(VPAS, mc.lee(VPAS).replace('    Rejilla: TDBGrid;\r\n',
                                       '    Rejilla: TDBGrid;\r\n    DataSource1: TDataSource;\r\n'))
    r = call('delphi_edit', {'path': VPAS, 'adduses': 'Data.DB', 'section': 'interface'})
    check('V9 preparado: DataSource1 en el form y en la clase, Data.DB en el uses',
          'object DataSource1: TDataSource' in mc.lee(VDFM) and 'DataSource1: TDataSource;' in mc.lee(VPAS) and
          'Data.DB' in mc.lee(VPAS), r[:200])
    antes = bytes_de(VDFM)
    r = dsg(command='set', path=VDFM, component='Rejilla', prop='DataSource', value='BtnOk')
    check('V9 DataSource = un TButton: DSGN-107 con los que caben (DataSource1), nada escrito',
          mc.abre(r, 'SR_DESIGNER_REFERENCIA_TIPO_FMT') and 'DataSource1' in r and bytes_de(VDFM) == antes, r[:400])
    r = dsg(command='set', path=VDFM, component='Rejilla', prop='DataSource', value='DataSource1')
    check('V9 DataSource = DataSource1: escrito', '    DataSource = DataSource1' in mc.lee(VDFM), r[:300])
    compila_y_cuadra('V9', VPROJ, VDFM)

    # ------------------------------------------------------------------ V10
    # un frame: en su .dfm (su tamano, un control dentro) y metido en el form
    # (inline, como lo deja el IDE): su tamano alli lo juzga TFrame, porque
    # su clase es del proyecto y no de la tabla (David, 7-oct-2026: el
    # tamano de un form o un frame en diseno; medido: se negaba con DSGN-082)
    call('delphi_create', {'kind': 'frame-vcl', 'name': 'UMarco', 'formname': 'Marco',
                           'project': os.path.join(VDIR, 'EdVcl.dpr')})
    MDFM = os.path.join(VDIR, 'UMarco.dfm')
    r = dsg(command='set', path=MDFM, component='Marco', prop='Height', value='40')
    check('V10 el tamano de un frame en su propio .dfm', '  Height = 40' in mc.lee(MDFM), r[:300])
    r = dsg(command='insert', path=MDFM, classname='TLabel', component='LblAviso')
    check('V10 ...y un control dentro', J(r).get('inserted') == 'LblAviso' and J(r).get('parent') == 'Marco', r[:300])
    escribe(VDFM, re.sub(r'\r\nend\r\n$', '\r\n  inline Marco1: TMarco\r\n    Left = 10\r\n    Top = 200\r\n'
                         '    Width = 320\r\n    Height = 40\r\n    TabOrder = 9\r\n  end\r\nend\r\n', mc.lee(VDFM)))
    escribe(VPAS, mc.lee(VPAS).replace('    DataSource1: TDataSource;\r\n',
                                       '    DataSource1: TDataSource;\r\n    Marco1: TMarco;\r\n'))
    call('delphi_edit', {'path': VPAS, 'adduses': 'UMarco', 'section': 'interface'})
    r = dsg(command='set', path=VDFM, component='Marco1', prop='Width', value='300')
    check('V10 el ancho del frame metido en el form: lo juzga TFrame y se escribe',
          J(r).get('set') == 'Marco1.Width' and '    Width = 300' in mc.lee(VDFM), r[:300])
    r = dsg(command='set', path=VDFM, component='Marco1', prop='Width', value='ancho')
    check('V10 ...y un valor que no es un entero se niega igual', mc.abre(r, 'SR_DESIGNER_SET_TIPO_FMT'), r[:300])
    compila_y_cuadra('V10', VPROJ, VDFM)

    # ------------------------------------------------------------------ V10b
    # 7.1 de la 1.18.0 (sin prueba desde la segunda revision de la 1.17.0):
    # quitar las lineas de un campo o de la declaracion de un manejador no
    # deja medio comentario detras (LineasLimpias). Uno con su comentario de
    # bloque que sigue en la linea de debajo: el campo niega el borrado; el
    # manejador se queda, con su comentario, y el resto se borra
    dsg(command='insert', path=VDFM, classname='TButton', component='BtnSucio')
    dsg(command='insert', path=VDFM, classname='TButton', component='BtnSucio2')
    call('delphi_edit', {'path': VPAS, 'insert': 'metodo', 'inclass': CLASE, 'visibility': 'published',
                         'code': 'procedure BtnSucio2Click(Sender: TObject);\nbegin\nend;'})
    escribe(VDFM, re.sub(r'(\r\n(\s+)object BtnSucio2: TButton\r\n)', r'\1\2  OnClick = BtnSucio2Click\r\n',
                         mc.lee(VDFM)))
    escribe(VPAS, mc.lee(VPAS).replace('    BtnSucio: TButton;\r\n', '    BtnSucio: TButton; (* nota\r\n      que sigue *)\r\n')
            .replace('    procedure BtnSucio2Click(Sender: TObject);\r\n',
                     '    procedure BtnSucio2Click(Sender: TObject); { nota\r\n      que sigue }\r\n'))
    check('V10b preparado: los dos comentarios que siguen debajo, y compila',
          '(* nota' in mc.lee(VPAS) and '{ nota' in mc.lee(VPAS) and mc.build_ok(call, VPROJ)[0], mc.lee(VPAS)[-600:])
    antes_dfm, antes_pas = bytes_de(VDFM), bytes_de(VPAS)
    r = dsg(command='delete', path=VDFM, component='BtnSucio')
    check('V10b el campo con un comentario que sigue en la linea de debajo: DSGN-108, nada escrito',
          mc.abre(r, 'SR_DESIGNER_CAMPO_LINEA_SUCIA_FMT') and bytes_de(VDFM) == antes_dfm and
          bytes_de(VPAS) == antes_pas, r[:400])
    r = dsg(command='delete', path=VDFM, component='BtnSucio2')
    j = J(r)
    pas = mc.lee(VPAS)
    check('V10b la declaracion de su manejador con un comentario que sigue debajo: el componente y su campo '
          'se van, el manejador se queda con su comentario (handlersKept)',
          j.get('deleted') == 'BtnSucio2' and any(x.get('method') == 'BtnSucio2Click' for x in j.get('handlersKept', []))
          and not any('BtnSucio2Click' in x for x in j.get('handlersRemoved', [])) and
          'procedure BtnSucio2Click(Sender: TObject); { nota\r\n      que sigue }' in pas and 'BtnSucio2:' not in pas,
          r[:600])
    escribe(VPAS, mc.lee(VPAS).replace('    BtnSucio: TButton; (* nota\r\n      que sigue *)\r\n',
                                       '    BtnSucio: TButton;\r\n'))
    compila_y_cuadra('V10b', VPROJ, VDFM)

    # ------------------------------------------------------------------ V10c
    # 7.1: el texto que es su nombre sigue al nombre tambien en VARIAS lineas
    # (leido entero), y las referencias de debajo se cuentan en el form que
    # QUEDA cuando el texto cambia de largo (el Delta de PlanDeRenombre)
    # (primero el que CRECE desde una linea: asi el Delta se ve aunque fallara
    # la lectura entera, que mide la vuelta)
    dsg(command='insert', path=VDFM, classname='TButton', component='BtnLargo')
    escribe(VDFM, re.sub(r'\r\nend\r\n$', "\r\n  object LblLargo: TLabel\r\n    Left = 10\r\n    Top = 260\r\n"
                         "    Caption = 'x'\r\n    FocusControl = BtnLargo\r\n  end\r\nend\r\n", mc.lee(VDFM)))
    escribe(VPAS, mc.lee(VPAS).replace('    BtnLargo: TButton;\r\n', '    BtnLargo: TButton;\r\n    LblLargo: TLabel;\r\n'))

    def linea_de_ref(r, valor):
        refs = J(r).get('referencesRenamed', [])
        m = re.match(r'.*:(\d+)$', refs[0]) if len(refs) == 1 else None
        lineas = mc.lee(VDFM).split('\r\n')
        return m is not None and lineas[int(m.group(1)) - 1].strip() == 'FocusControl = ' + valor, (refs, valor)

    LARGO = 'Btn' + 'X' * 67
    r = dsg(command='set', path=VDFM, component='BtnLargo', prop='Name', value=LARGO)
    dfm = mc.lee(VDFM)
    ok, det = linea_de_ref(r, LARGO)
    check('V10c un nombre de 70: su texto en trozos (dos lineas mas) y referencesRenamed senala la linea de '
          'FocusControl en el form que QUEDA',
          ok and ("    Caption = \r\n      '" + 'Btn' + 'X' * 61 + "' +\r\n") in dfm, (det, dfm[-400:]))
    r = dsg(command='set', path=VDFM, component=LARGO, prop='Name', value='BtnCorto')
    dfm = mc.lee(VDFM)
    check('V10c ...y de vuelta: su texto en VARIAS lineas se lee entero, sigue al nombre y queda en una',
          J(r).get('to') == 'BtnCorto' and "    Caption = 'BtnCorto'\r\n" in dfm and 'XXXX' not in dfm, dfm[-500:])
    ok, det = linea_de_ref(r, 'BtnCorto')
    check('V10c ...y la referencia de debajo, contada con dos lineas menos', ok, det)
    compila_y_cuadra('V10c', VPROJ, VDFM)

    # ------------------------------------------------------------------ V10d
    # 3.3 de la 1.18.0 (medido): una ruta por una REFERENCIA (PopupMenu =
    # PopupMenu1 y prop=PopupMenu.AutoPopup) se escribia en el boton, el lint
    # decia CLEAN y el form no cargaba: el cargador lee la ruta antes de
    # resolver la referencia. Un subcomponente (EditLabel) si entra
    escribe(VDFM, re.sub(r'\r\nend\r\n$', '\r\n  object PopupMenu1: TPopupMenu\r\n    Left = 300\r\n'
                         '    Top = 60\r\n  end\r\nend\r\n', mc.lee(VDFM)))
    escribe(VPAS, mc.lee(VPAS).replace('    LblLargo: TLabel;\r\n', '    LblLargo: TLabel;\r\n    PopupMenu1: TPopupMenu;\r\n'))
    call('delphi_edit', {'path': VPAS, 'adduses': 'Vcl.Menus', 'section': 'interface'})
    r = dsg(command='set', path=VDFM, component='BtnCorto', prop='PopupMenu', value='PopupMenu1')
    check('V10d preparado: BtnCorto.PopupMenu = PopupMenu1', '    PopupMenu = PopupMenu1' in mc.lee(VDFM), r[:300])
    antes = bytes_de(VDFM)
    r = dsg(command='set', path=VDFM, component='BtnCorto', prop='PopupMenu.AutoPopup', value='False')
    check('V10d set PopupMenu.AutoPopup con PopupMenu = PopupMenu1: DSGN-119, que dice donde ponerlo, nada escrito',
          mc.abre(r, 'SR_DESIGNER_SET_POR_REFERENCIA_FMT') and 'component=PopupMenu1 prop=AutoPopup' in r and
          bytes_de(VDFM) == antes, r[:400])
    r = dsg(command='set', path=VDFM, component='PopupMenu1', prop='AutoPopup', value='False')
    check('V10d ...y en PopupMenu1 entra', '    AutoPopup = False' in mc.lee(VDFM), r[:300])
    escribe(VDFM, mc.lee(VDFM).replace('    PopupMenu = PopupMenu1\r\n',
                                       '    PopupMenu.AutoPopup = False\r\n    PopupMenu = PopupMenu1\r\n'))
    r = dsg(command='lint', path=VDFM)
    check('V10d el lint la avisa (la linea a mano, antes de la referencia, como la dejaba set)',
          not mc.es(r, 'SN_DESIGNER_LINT_OK_FMT') and 'PopupMenu.AutoPopup = False' in r and
          'holds a reference to another component' in r, r[:500])
    escribe(VDFM, mc.lee(VDFM).replace('    PopupMenu.AutoPopup = False\r\n', ''))
    r = dsg(command='insert', path=VDFM, classname='TLabeledEdit', component='Etiquetado')
    r = dsg(command='set', path=VDFM, component='Etiquetado', prop='EditLabel.Caption', value='Nombre')
    check('V10d un subcomponente (EditLabel de un TLabeledEdit) no es una referencia: su Caption entra',
          "    EditLabel.Caption = 'Nombre'" in mc.lee(VDFM), r[:300])
    compila_y_cuadra('V10d', VPROJ, VDFM)

    # ------------------------------------------------------------------ V11
    # 3.8 de la 1.18.0 (Hermes, medido): usesInCode daba las lineas de la
    # unidad de ANTES del borrado, y el borrado quita su campo por encima del
    # uso: el agente iba a otra linea. Ahora, las de la unidad que QUEDA. (Lo
    # ultimo del proyecto VCL: despues de esto ya no compila, el uso queda.)
    dsg(command='insert', path=VDFM, classname='TButton', component='BtnUso')
    call('delphi_edit', {'path': VPAS, 'insert': 'metodo', 'inclass': CLASE, 'visibility': 'public',
                         'code': "procedure UsaBoton;\nbegin\n  BtnUso.Caption := 'x';\nend;"})
    r = dsg(command='delete', path=VDFM, component='BtnUso')
    usos = J(r).get('usesInCode', [])
    lineas_pas = mc.lee(VPAS).splitlines()
    m = re.match(r'.*?:(\d+): ', usos[0]) if usos else None
    n = int(m.group(1)) if m else 0
    check('V11 delete: usesInCode senala la linea del uso en la unidad que QUEDA',
          0 < n <= len(lineas_pas) and 'BtnUso.Caption' in lineas_pas[n - 1],
          (usos, lineas_pas[n - 1] if 0 < n <= len(lineas_pas) else '-'))

    # =================================================================== FMX
    FDIR = os.path.join(JAIL, 'EdFmx')
    r = call('delphi_create', {'kind': 'project-fmx', 'dir': FDIR, 'name': 'EdFmx'})
    check('F0 un proyecto FMX recien creado', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    FPROJ = os.path.join(FDIR, 'EdFmx.dproj')
    FFMX = (glob.glob(os.path.join(FDIR, '*.fmx')) or [''])[0]
    FPAS = FFMX[:-4] + '.pas'

    # ------------------------------------------------------------------ F1
    r = dsg(command='insert', path=FFMX, classname='TButton')
    j = J(r)
    check('F1 insert en FMX: Button1, FMX.StdCtrls en el uses', j.get('inserted') == 'Button1' and
          j.get('usesAdded') == 'FMX.StdCtrls', r[:500])
    fmx = mc.lee(FFMX)
    check('F1 ...Position con los 18 decimales del IDE, TabOrder y su Text (un TPresentedTextControl)',
          re.search(r"\r\n  object Button1: TButton\r\n    Position\.X = 10\.000000000000000000\r\n"
                    r"    Position\.Y = 10\.000000000000000000\r\n    TabOrder = \d+\r\n    Text = 'Button1'\r\n  end",
                    fmx) is not None, fmx[-400:])
    r = dsg(command='insert', path=FFMX, classname='TRectangle')
    check('F1 un TRectangle no lleva Text (su SetName no lo pone)', J(r).get('inserted') == 'Rectangle1' and
          re.search(r"object Rectangle1: TRectangle\r\n(    (?!Text)[^\r\n]*\r\n)*  end", mc.lee(FFMX)) is not None,
          mc.lee(FFMX)[-300:])
    # el caso medido en el fuente de 13.1 (David, 7-oct-2026): lo dice el
    # SetName de cada clase, que el generador lee (hecho T); TEditButton hereda
    # de un TPresentedTextControl y su SetName lo VACIA
    r = dsg(command='insert', path=FFMX, classname='TEditButton')
    check('F1 un TEditButton no lleva Text: su SetName lo vacia (leido del fuente por el generador)',
          J(r).get('inserted') == 'EditButton1' and
          re.search(r"object EditButton1: TEditButton\r\n(    (?!Text)[^\r\n]*\r\n)*  end", mc.lee(FFMX)) is not None,
          mc.lee(FFMX)[-300:])
    r = dsg(command='insert', path=FFMX, classname='TLayout')
    r = dsg(command='insert', path=FFMX, classname='TLabel', parent='Layout1')
    check('F1 un TLabel dentro de un TLayout, con su Text', J(r).get('parent') == 'Layout1' and
          "      Text = 'Label1'" in mc.lee(FFMX), r[:300])
    r = dsg(command='insert', path=FFMX, classname='TLabel', component='LblTitulo')
    check('F1 insert component= en FMX: LblTitulo, su Text nace con su nombre',
          J(r).get('inserted') == 'LblTitulo' and
          re.search(r"object LblTitulo: TLabel\r\n(    [^\r\n]*\r\n)*    Text = 'LblTitulo'\r\n  end", mc.lee(FFMX))
          is not None, mc.lee(FFMX)[-300:])
    compila_y_cuadra('F1', FPROJ, FFMX)
    rect, png = rect_de(FFMX, 'Button1')
    check('F1 ...y preview lo dibuja en 10,10 con su texto',
          (rect or '').startswith('10,10,') and oscuros(png) > 5, (rect, oscuros(png)))
    # 3.7 de la 1.18.0 (Hermes, medido): en FMX Left/Top los guarda TComponent
    # (el sitio del ICONO de un no visual): set los escribia, contestaba bien y
    # el control no se movia. Ahora se niega nombrando Position.X/Y, y el lint
    # avisa de una linea Left/Top en un control
    antes = mc.lee(FFMX)
    r = dsg(command='set', path=FFMX, component='Button1', prop='Left', value='50')
    check('F1b set Left en un control FMX: DSGN-118 nombra Position.X, sin escribir',
          mc.abre(r, 'SR_DESIGNER_FMX_LEFT_TOP_FMT') and 'Position.X' in r and mc.lee(FFMX) == antes, r[:300])
    escribe(FFMX, antes.replace("  object Button1: TButton\r\n", "  object Button1: TButton\r\n    Top = 7\r\n", 1))
    r = dsg(command='lint', path=FFMX)
    check('F1b lint: una linea Top en un control FMX avisa, con Position.Y',
          'Top does not place an FMX control' in r and 'Position.Y' in r, r[:400])
    # 3.1 de la 1.18.0: lint con el juez de tipos de set - una cadena en una
    # Single decia CLEAN, y el form no carga
    escribe(FFMX, antes.replace("  object Button1: TButton\r\n", "  object Button1: TButton\r\n    Opacity = 'hola'\r\n", 1))
    r = dsg(command='lint', path=FFMX)
    check('F1c lint: una cadena en una Single (Opacity) avisa con lo que toma',
          "Opacity is" in r and "not 'hola'" in r and 'will not load' in r, r[:400])
    escribe(FFMX, antes)

    # ------------------------------------------------------------------ F2
    r = dsg(command='set', path=FFMX, component='Rectangle1', prop='Fill.Color', value="'rojo'")
    check('F2 una cadena en un TAlphaColor: DSGN-093', mc.abre(r, 'SR_DESIGNER_SET_TIPO_FMT'), r[:300])
    # 3.9 de la 1.18.0 (Hermes, medido): el DSGN-093 de un valor que no es un
    # nombre solo daba los nombres; ahora, lo que su lector tambien toma
    # (xAARRGGBB y las formas cl)
    check('F2 ...y ensena lo que el lector de TAlphaColor tambien toma: xFF00FF00',
          'xFF00FF00' in r, r[:400])
    r = dsg(command='set', path=FFMX, component='Rectangle1', prop='Fill.Color', value='xFF00FF00')
    check('F2 xAARRGGBB en un TAlphaColor: su IdentTo lo acepta (no es una busqueda en el mapa: cualquiera)',
          '    Fill.Color = xFF00FF00' in mc.lee(FFMX), r[:300])
    r = dsg(command='set', path=FFMX, component='Rectangle1', prop='Fill.Color', value='claRed')
    check('F2 set de una subpropiedad FMX (Fill.Color)', '    Fill.Color = claRed' in mc.lee(FFMX), r[:300])
    rect, png = rect_de(FFMX, 'Rectangle1')
    check('F2 ...y preview lo pinta rojo', (rect or '').startswith('10,10,') and cerca(pixel_de(png, 25, 25), ROJO),
          (rect, pixel_de(png, 25, 25)))
    # un numero de coma flotante, escrito como el IDE (FloatToStrF ffFixed 16
    # 18 del valor que guarda la propiedad): nadie lo reescribe despues
    r = dsg(command='set', path=FFMX, component='Rectangle1', prop='Opacity', value='0.7')
    check('F2 una Single como la escribe el IDE: redondeada a Single, 18 decimales',
          '    Opacity = 0.699999988079071000' in mc.lee(FFMX), r[:300])
    r = dsg(command='set', path=FFMX, component='Rectangle1', prop='Opacity', value='1E39')
    check('F2 ...una que no cabe en una Single (1E39): no se escribe', mc.abre(r, 'SR_DESIGNER_SET_TIPO_FMT') and
          'a number its type holds' in r and 'Opacity = 0.699999988079071000' in mc.lee(FFMX), r[:300])
    r = dsg(command='set', path=FFMX, component='Rectangle1', prop='Size.Width', value='51')
    check('F2 ...y un entero en una Single, con sus 18 decimales',
          '    Size.Width = 51.000000000000000000' in mc.lee(FFMX), r[:300])
    r = dsg(command='set', path=FFMX, component='Rectangle1', prop='Size.Height', value='$20')
    check('F2 ...y un entero hexadecimal ($20) en una Single: 32 con sus 18 decimales',
          re.search(r"object Rectangle1: TRectangle\r\n(    [^\r\n]*\r\n)*?    Size\.Height = 32\.000000000000000000\r\n",
                    mc.lee(FFMX)) is not None, r[:300])
    r = dsg(command='set', path=FFMX, component='Button1', parent='Layout1')
    check('F2 set parent= en FMX: a un TLayout', J(r).get('moved') == 'Button1' and J(r).get('to') == 'Layout1' and
          'outsideParent' not in J(r), r[:300])
    r = dsg(command='delete', path=FFMX, component='Rectangle1')
    check('F2 delete en FMX', J(r).get('deleted') == 'Rectangle1' and 'Rectangle1' not in mc.lee(FFMX) and
          'Rectangle1' not in mc.lee(FPAS), r[:400])
    compila_y_cuadra('F2', FPROJ, FFMX)

    # =================================================================== R
    # La revision de la 1.17.0: lo que trajeron cinco revisores y la suite no
    # veia, escrituras que rompian el form diciendo OK (medido en vivo en
    # DisenoVivo\SondaRev). Un proyecto propio: cada caso, contra el servidor
    RDIR = os.path.join(JAIL, 'EdRev')
    r = call('delphi_create', {'kind': 'project-vcl', 'dir': RDIR, 'name': 'EdRev'})
    check('R0 un proyecto VCL para la revision', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    RPROJ = os.path.join(RDIR, 'EdRev.dproj')
    RDPR = os.path.join(RDIR, 'EdRev.dpr')
    RDFM = (glob.glob(os.path.join(RDIR, '*.dfm')) or [''])[0]
    RPAS = RDFM[:-4] + '.pas'
    RFORM = (re.search(r'^object (\w+)', mc.lee(RDFM)) or re.search('()', '')).group(1)

    def hijos_de(path):
        t = J(dsg(command='tree', path=path)).get('root', {})
        return t.get('name'), [c.get('name') for c in t.get('children', [])]

    # ------------------------------------------------------------------ R1
    dsg(command='insert', path=RDFM, classname='TLabel')
    # la cadena larga como la escribe el IDE: empieza en la linea de DEBAJO
    escribe(RDFM, mc.lee(RDFM).replace("    Caption = 'Label1'\r\n",
                                       "    Caption = \r\n      '" + 'a' * 64 + "' +\r\n      '" + 'b' * 10 + "'\r\n"))
    r = dsg(command='set', path=RDFM, component='Label1', prop='Caption', value='Corto')
    dfm = mc.lee(RDFM)
    check('R1 set sobre la cadena larga del IDE (empieza debajo): la reescribe ENTERA, sin trozos sueltos',
          "    Caption = 'Corto'\r\n  end" in dfm and 'aaaa' not in dfm and 'bbbb' not in dfm, (r[:200], dfm[-300:]))
    r = dsg(command='set', path=RDFM, component='Label1', prop='Caption', value="Conway's Life")
    check("R1 una comilla como la escribe el IDE: 'Conway'#39's Life'",
          "    Caption = 'Conway'#39's Life'" in mc.lee(RDFM), r[:300])
    r = dsg(command='set', path=RDFM, component='Label1', prop='Hint', value='x' * 5000)
    dfm = mc.lee(RDFM)
    check('R1 un Hint de 5000: trozos de 64 en las lineas de debajo, ninguna linea larga (4095 = "Line too long")',
          max(len(x) for x in dfm.split('\r\n')) < 100 and
          "    Hint = \r\n      '" + 'x' * 64 + "' +\r\n" in dfm, (r[:200], max(len(x) for x in dfm.split('\r\n'))))
    compila_y_cuadra('R1', RPROJ, RDFM)

    # ------------------------------------------------------------------ R2
    dsg(command='set', path=RDFM, component='Label1', prop='Caption', value='Total = {0}')
    r = dsg(command='insert', path=RDFM, classname='TButton')
    raiz, hijos = hijos_de(RDFM)
    check('R2 una llave en una cadena (Total = {0}) no abre un bloque binario: el insert cae en el form',
          J(r).get('inserted') == 'Button1' and J(r).get('parent') == RFORM and raiz == RFORM and
          {'Label1', 'Button1'} <= set(hijos), (r[:300], raiz, hijos))
    compila_y_cuadra('R2', RPROJ, RDFM)

    # ------------------------------------------------------------------ R3
    escribe(RDFM, re.sub(r'\r\nend\r\n$', "\r\n  object Cats: TCategoryButtons\r\n    Left = 10\r\n    Top = 60\r\n"
                         "    Width = 150\r\n    Height = 100\r\n    Categories = <\r\n      item\r\n"
                         "        Caption = 'Uno'\r\n        Items = <>\r\n      end>\r\n    TabOrder = 5\r\n  end\r\n"
                         "  object Lbl2: TLabel\r\n    Left = 10\r\n    Top = 170\r\n    Caption = 'Lbl2'\r\n  end\r\n"
                         "end\r\n", mc.lee(RDFM)))
    escribe(RPAS, mc.lee(RPAS).replace('    Button1: TButton;\r\n', '    Button1: TButton;\r\n    Cats: TCategoryButtons;\r\n'))
    call('delphi_edit', {'path': RPAS, 'adduses': 'Vcl.CategoryButtons', 'section': 'interface'})
    raiz, hijos = hijos_de(RDFM)
    check('R3 un Items = <> dentro de un item no descoloca el arbol: la raiz es el form, Cats y Lbl2 sus hijos',
          raiz == RFORM and {'Cats', 'Lbl2'} <= set(hijos), (raiz, hijos))
    r = dsg(command='check-binding', path=RDFM)
    check('R3 ...y check-binding ve el Lbl2 de DESPUES de la coleccion, sin su campo',
          J(r).get('clean') is False and 'Lbl2' in r, r[:400])
    escribe(RPAS, mc.lee(RPAS).replace('    Cats: TCategoryButtons;\r\n', '    Cats: TCategoryButtons;\r\n    Lbl2: TLabel;\r\n'))
    compila_y_cuadra('R3', RPROJ, RDFM)

    # ------------------------------------------------------------------ R4
    dsg(command='set', path=RDFM, component='Label1', prop='Caption', value="'Acción'")
    dsg(command='set', path=RDFM, component='Lbl2', prop='Caption', value="It's")
    r = dsg(command='set', path=RDFM, component='Label1', prop='Hint', value='#hashtag')
    dfm = mc.lee(RDFM)
    check("R4 los literales como el IDE: un acento entre comillas es #243, It's es #39, #hashtag es texto",
          "    Caption = 'Acci'#243'n'" in dfm and "    Caption = 'It'#39's'" in dfm and
          "    Hint = '#hashtag'" in dfm and 'ó' not in dfm, (r[:200], dfm[-500:]))

    # ------------------------------------------------------------------ R5
    antes = bytes_de(RDFM)
    casos = [('Button1', 'Align', '2'), ('Button1', 'Align', "'alClient'"), ('Button1', 'Anchors', '3'),
             ('Button1', 'Anchors', '[akLeft,]'), ('Label1', 'Font.Style', "'fsBold'"),
             ('Label1', 'Color', '$FFFF0000')]
    rs = [dsg(command='set', path=RDFM, component=c, prop=p, value=v) for c, p, v in casos]
    check('R5 lo que el cargador no lee se niega (Align=2, un enumerado entre comillas, Anchors=3, '
          '[akLeft,], fsBold suelto, un TColor de mas de 32 bits) y no se escribe nada',
          all(J(x).get('set') is None and any(mc.abre(x, k) for k in (
              'SR_DESIGNER_SET_TIPO_FMT', 'SR_DESIGNER_SET_INVALIDO_FMT', 'SR_DESIGNER_SET_GRAMATICA_FMT'))
              for x in rs) and bytes_de(RDFM) == antes, [x[:120] for x in rs])
    # un numero que no cabe en su tipo: 1E400 en un TDate (Double), que el
    # servidor no llega a leer, se escribia tal cual (segunda revision)
    dsg(command='insert', path=RDFM, classname='TDateTimePicker')
    antes = bytes_de(RDFM)
    r = dsg(command='set', path=RDFM, component='DateTimePicker1', prop='Date', value='1E400')
    check('R5 ...1E400 en un TDate (un Double): no cabe, nada escrito',
          mc.abre(r, 'SR_DESIGNER_SET_TIPO_FMT') and 'a number its type holds' in r and bytes_de(RDFM) == antes,
          r[:300])
    r = dsg(command='set', path=RDFM, component='Label1', prop='Font', value='x')
    check('R5 ...Font, un objeto que el componente guarda, no toma valor: sus subpropiedades, nada escrito',
          J(r).get('set') is None and 'no value of its own' in r and bytes_de(RDFM) == antes, r[:300])

    # ------------------------------------------------------------------ R6
    dsg(command='insert', path=RDFM, classname='TEdit')
    dsg(command='set', path=RDFM, component='Label1', prop='FocusControl', value='Edit1')
    check('R6 (de partida) Label1.FocusControl = Edit1 escrito', '    FocusControl = Edit1' in mc.lee(RDFM))
    r = dsg(command='set', path=RDFM, component='Label1', prop='FocusControl', value='nil')
    check('R6 nil en una referencia la quita (lo que escribe el IDE): ni la linea ni un DSGN-098',
          J(r).get('removed') is True and 'FocusControl' not in mc.lee(RDFM), r[:300])
    antes = bytes_de(RDFM)
    r = dsg(command='set', path=RDFM, component='Label1', prop='FocusControl', value='nil')
    check('R6 ...otra vez nil, sin linea que quitar: DSGN-112 (nada cambiado), no un removed',
          mc.abre(r, 'SN_DESIGNER_NADA_QUE_QUITAR_FMT') and bytes_de(RDFM) == antes, r[:300])

    # ------------------------------------------------------------------ R7
    dsg(command='insert', path=RDFM, classname='TMemo')
    r = dsg(command='set', path=RDFM, component='Memo1', prop='Lines', value="'hola'")
    check('R7 una TStrings (Memo1.Lines) se escribe con delphi_edit: DSGN-109, no "un componente"',
          mc.abre(r, 'SR_DESIGNER_SET_LISTA_FMT'), r[:300])

    # ------------------------------------------------------------------ R8
    dsg(command='insert', path=RDFM, classname='TPageControl')
    dsg(command='insert', path=RDFM, classname='TGroupBox')
    r1 = dsg(command='insert', path=RDFM, classname='TButton', parent='PageControl1')
    r2 = dsg(command='insert', path=RDFM, classname='TButton', parent='Button1')
    r3 = dsg(command='insert', path=RDFM, classname='TCheckBox', parent='GroupBox1')
    check('R8 csAcceptsControls del constructor: un TPageControl y un TButton no son padre (DSGN-080), '
          'un TGroupBox si',
          mc.abre(r1, 'SR_DESIGNER_PADRE_VCL_FMT') and mc.abre(r2, 'SR_DESIGNER_PADRE_VCL_FMT') and
          J(r3).get('parent') == 'GroupBox1', (r1[:200], r2[:200], r3[:200]))
    compila_y_cuadra('R8', RPROJ, RDFM)

    # ------------------------------------------------------------------ R9
    # un frame en linea con su LblAviso, y el form con un LblAviso propio: los
    # nombres del frame no son del form (el fixup de TReader resuelve en el form)
    call('delphi_create', {'kind': 'frame-vcl', 'name': 'UMarcoRev', 'formname': 'MarcoRev', 'project': RDPR})
    MRDFM = os.path.join(RDIR, 'UMarcoRev.dfm')
    dsg(command='insert', path=MRDFM, classname='TLabel', component='LblAviso')
    escribe(RDFM, re.sub(r'\r\nend\r\n$', "\r\n  inline MarcoRev1: TMarcoRev\r\n    Left = 300\r\n    Top = 10\r\n"
                         "    Width = 150\r\n    Height = 40\r\n    TabOrder = 9\r\n    inherited LblAviso: TLabel\r\n"
                         "      Caption = 'Del frame'\r\n    end\r\n  end\r\nend\r\n", mc.lee(RDFM)))
    escribe(RPAS, mc.lee(RPAS).replace('    Lbl2: TLabel;\r\n', '    Lbl2: TLabel;\r\n    MarcoRev1: TMarcoRev;\r\n'))
    call('delphi_edit', {'path': RPAS, 'adduses': 'UMarcoRev', 'section': 'interface'})
    r = dsg(command='insert', path=RDFM, classname='TLabel', component='LblAviso')
    check('R9 un LblAviso del FORM aunque el frame en linea tenga el suyo', J(r).get('inserted') == 'LblAviso', r[:300])
    r = dsg(command='set', path=RDFM, component='LblAviso', prop='Caption', value='Del form')
    dfm = mc.lee(RDFM)
    check('R9 ...set va al del form, y el del frame se queda',
          "    Caption = 'Del form'" in dfm and "      Caption = 'Del frame'" in dfm, (r[:200], dfm[-600:]))
    r = dsg(command='delete', path=RDFM, component='LblAviso')
    dfm = mc.lee(RDFM)
    check('R9 ...delete borra el del form, y la redefinicion dentro del frame sigue',
          J(r).get('deleted') == 'LblAviso' and 'Del form' not in dfm and 'inherited LblAviso: TLabel' in dfm,
          (r[:300], dfm[-400:]))
    compila_y_cuadra('R9', RPROJ, RDFM)

    # ------------------------------------------------------------------ R10
    call('delphi_create', {'kind': 'datamodule', 'name': 'UDatosRev', 'project': RDPR})
    r = dsg(command='insert', path=os.path.join(RDIR, 'UDatosRev.dfm'), classname='TButton')
    check('R10 un control en un data module: DSGN-080 (entraba)', mc.abre(r, 'SR_DESIGNER_PADRE_VCL_FMT'), r[:300])

    # ------------------------------------------------------------------ R11
    call('delphi_create', {'kind': 'form-vcl', 'name': 'UBaseRev', 'formname': 'FormBaseRev', 'project': RDPR})
    HRDFM = escribe(os.path.join(RDIR, 'UHijaRev.dfm'),
                    "inherited FormHijaRev: TFormHijaRev\r\n  Caption = 'FormHijaRev'\r\nend\r\n")
    escribe(os.path.join(RDIR, 'UHijaRev.pas'),
            "unit UHijaRev;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms, UBaseRev;\r\n\r\ntype\r\n"
            "  TFormHijaRev = class(TFormBaseRev)\r\n  end;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n")
    r = dsg(command='set', path=HRDFM, component='FormHijaRev', prop='Caption', value='Hija')
    check('R11 la raiz de una form que hereda de una base de OTRA unidad de la carpeta: set entra (era DSGN-082)',
          J(r).get('set') == 'FormHijaRev.Caption' and "  Caption = 'Hija'" in mc.lee(HRDFM), r[:300])
    # 3.2 de la 1.18.0: un componente de la BASE que la hija no cambia no esta
    # en el .dfm de la hija ni en su clase, y el nombre se daba por libre: el
    # form saltaba EComponentError al crearse
    dsg(command='insert', path=os.path.join(RDIR, 'UBaseRev.dfm'), classname='TButton')
    r = dsg(command='insert', path=HRDFM, classname='TButton')
    check('R11b insert en un form heredado: no toma el nombre de un componente de su base (Button1)',
          J(r).get('inserted') == 'Button2', r[:300])
    r = dsg(command='set', path=HRDFM, component='Button2', prop='Name', value='Button1')
    check('R11b ...ni se renombra a el: DSGN-096 dice que lo hereda de TFormBaseRev',
          mc.abre(r, 'SR_DESIGNER_NOMBRE_OCUPADO_FMT') and 'TFormBaseRev' in r, r[:300])

    # ------------------------------------------------------------------ R12
    dsg(command='insert', path=FFMX, classname='TLayout', component='Client')
    dsg(command='insert', path=FFMX, classname='TRectangle', component='Fondo')
    r = dsg(command='set', path=FFMX, component='Fondo', prop='Align', value='Client')
    check('R12 FMX: Align = Client (un enumerado sin prefijo) con un componente llamado Client',
          '    Align = Client' in mc.lee(FFMX), r[:300])
    # el renombrado pasa por el mismo juez: Client -> Cliente no toca el Align
    r = dsg(command='set', path=FFMX, component='Client', prop='Name', value='Cliente')
    fmx = mc.lee(FFMX)
    check('R12 ...renombrar Client tampoco lo toca: el bloque cambia y el Align de Fondo sigue en Client',
          J(r).get('renamed') == 'Client' and 'object Cliente: TLayout' in fmx and '    Align = Client' in fmx and
          'Align = Cliente' not in fmx, (r[:300], fmx[-400:]))
    r = dsg(command='delete', path=FFMX, component='Cliente')
    check('R12 ...borrar Cliente no se lleva el Align de Fondo: no es una referencia (lo dice la tabla)',
          J(r).get('deleted') == 'Cliente' and '    Align = Client' in mc.lee(FFMX) and
          not J(r).get('referencesRemoved'), r[:400])

    # ------------------------------------------------------------------ R13
    # TAlphaColor: una lista ABIERTA, con lo que su IdentTo lee de verdad,
    # sacado de su fuente (generacion 12): las tres formas que cargan entran
    # sin aviso, y lo demas se niega - 'Rojo' se escribia callado y el form no
    # abria (segunda revision de la 1.17.0). claRde y no claRedd: la parecida
    # no puede estar ya en el valor (un check que no podia fallar)
    for v in ('claRed', 'clRed', 'xFF00FF00'):
        r = dsg(command='set', path=FFMX, component='Fondo', prop='Fill.Color', value=v)
        check('R13 TAlphaColor %s: lo carga IdentToAlphaColor, se escribe sin aviso' % v,
              J(r).get('set') == 'Fondo.Fill.Color' and 'warning' not in J(r) and
              ('    Fill.Color = %s' % v) in mc.lee(FFMX), r[:300])
    antes = bytes_de(FFMX)
    r = dsg(command='set', path=FFMX, component='Fondo', prop='Fill.Color', value='Rojo')
    check('R13 ...Rojo no lo carga: se niega (y dice que formas toma), nada escrito',
          mc.abre(r, 'SR_DESIGNER_SET_TIPO_FMT') and 'keeps the form from opening' in r and
          'xFF00FF00' in r and bytes_de(FFMX) == antes, r[:400])
    r = dsg(command='set', path=FFMX, component='Fondo', prop='Fill.Color', value='claRde')
    check('R13 ...claRde tampoco: se niega con la parecida (Did you mean claRed?)',
          mc.abre(r, 'SR_DESIGNER_SET_TIPO_FMT') and 'Did you mean claRed?' in r and bytes_de(FFMX) == antes,
          r[:400])
    compila_y_cuadra('R13', FPROJ, FFMX)

    # ------------------------------------------------------------------ R14
    r = call('delphi_help', {'command': 'tasks'})
    check('R14 el mapa de delphi_help nombra preview e insert / set / delete',
          'delphi_designer preview' in r and 'delphi_designer insert / set' in r, r[:200])

    # ------------------------------------------------------------------ R15
    # las salidas cuando insert no puede: a mano, y dicho como
    # con TImageList: el ejemplo del mensaje es un TTimer fijo, y un check que
    # buscaba 'object Timer1' no podia fallar (segunda revision de la 1.17.0)
    antes = bytes_de(RDFM)
    r = dsg(command='insert', path=RDFM, classname='TImageList')
    check('R15 un no visual: DSGN-079 nombra su clase y dice como ponerlo a mano (bloque, campo, uses con '
          'section=interface, check-binding), nada escrito',
          mc.abre(r, 'SR_DESIGNER_INSERT_NO_VISUAL_FMT') and r.startswith('[DSGN-079') and
          'TImageList is not a visual control' in r and 'section=interface' in r and 'check-binding' in r and
          bytes_de(RDFM) == antes, r[:500])
    call('delphi_create', {'kind': 'form-vcl', 'name': 'URamas', 'formname': 'FormRamas', 'project': RDPR})
    RAMDFM, RAMPAS = os.path.join(RDIR, 'URamas.dfm'), os.path.join(RDIR, 'URamas.pas')
    pas = mc.lee(RAMPAS)
    m = re.search(r'uses\r\n(.*?);\r\n', pas, re.S)
    lista = m.group(1) if m else ''
    escribe(RAMPAS, pas[:m.start()] + 'uses\r\n{$IFDEF MSWINDOWS}\r\n' + lista + ';\r\n{$ELSE}\r\n' + lista +
            ';\r\n{$ENDIF}\r\n' + pas[m.end():] if m else pas)
    antes_dfm, antes_pas = bytes_de(RAMDFM), bytes_de(RAMPAS)
    r = dsg(command='insert', path=RAMDFM, classname='TButton')
    check('R15 un uses partido en ramas sin la unidad: USES-001 y que hacer (anadirla a mano y repetir), nada escrito',
          mc.abre(r, 'SR_USES_EN_RAMAS_FMT') and 'Vcl.StdCtrls' in r and 'repeat the insert' in r and
          bytes_de(RAMDFM) == antes_dfm and bytes_de(RAMPAS) == antes_pas, r[:500])
    escribe(RAMPAS, mc.lee(RAMPAS).replace(lista + ';', lista + ', Vcl.StdCtrls;'))
    r = dsg(command='insert', path=RAMDFM, classname='TButton')
    check('R15 ...con la unidad en las ramas, el insert entra y no la vuelve a poner',
          J(r).get('inserted') == 'Button1' and not J(r).get('usesAdded') and
          mc.lee(RAMPAS).count('Vcl.StdCtrls') == 2, r[:400])
    compila_y_cuadra('R15', RPROJ, RAMDFM)

    # ------------------------------------------------------------------ R16
    # una propiedad de tipo INTERFAZ (TFDBatchMove.Reader: IFDBatchMoveReader)
    # tambien es una referencia: el renombrado la sigue y el delete la quita
    # (revision de la 1.17.0: el juez solo miraba las clases)
    escribe(RDFM, re.sub(r'\r\nend\r\n$', '\r\n  object FDBatchMove1: TFDBatchMove\r\n    Reader = FDBatchMoveTextReader1\r\n'
                         '    Left = 400\r\n    Top = 200\r\n  end\r\n  object FDBatchMoveTextReader1: TFDBatchMoveTextReader\r\n'
                         '    Left = 440\r\n    Top = 200\r\n  end\r\nend\r\n', mc.lee(RDFM)))
    escribe(RPAS, mc.lee(RPAS).replace('    Lbl2: TLabel;\r\n', '    Lbl2: TLabel;\r\n    FDBatchMove1: TFDBatchMove;\r\n'
                                       '    FDBatchMoveTextReader1: TFDBatchMoveTextReader;\r\n'))
    call('delphi_edit', {'path': RPAS, 'adduses': 'FireDAC.Comp.BatchMove;FireDAC.Comp.BatchMove.Text',
                         'section': 'interface'})
    compila_y_cuadra('R16 (de partida)', RPROJ, RDFM)
    r = dsg(command='set', path=RDFM, component='FDBatchMoveTextReader1', prop='Name', value='LectorTxt')
    dfm = mc.lee(RDFM)
    check('R16 renombrar el lector reescribe la referencia de tipo interfaz: Reader = LectorTxt',
          J(r).get('renamed') == 'FDBatchMoveTextReader1' and '    Reader = LectorTxt' in dfm and
          'FDBatchMoveTextReader1' not in dfm + mc.lee(RPAS), (r[:300], dfm[-400:]))
    compila_y_cuadra('R16', RPROJ, RDFM)
    r = dsg(command='delete', path=RDFM, component='LectorTxt')
    dfm = mc.lee(RDFM)
    check('R16 ...y borrarlo quita la linea Reader del que lo usaba (con el campo)',
          J(r).get('deleted') == 'LectorTxt' and
          any('Reader = LectorTxt' in x for x in J(r).get('referencesRemoved', [])) and
          'Reader =' not in dfm and 'object FDBatchMove1: TFDBatchMove' in dfm and 'LectorTxt' not in mc.lee(RPAS),
          (r[:400], dfm[-300:]))
    compila_y_cuadra('R16b', RPROJ, RDFM)

    # ------------------------------------------------------------------ R17
    # un nombre con acento: solo con el form en UTF-8 con BOM (TParser lee en
    # ANSI un form sin el, y en ANSI no hay letra alta en un nombre) y la unidad
    # con BOM o en CP1252 (dcc lee en ANSI un fuente sin BOM). Sin el, el
    # proyecto dejaba de compilar (RLINK32) diciendo OK, y la codificacion de
    # un fichero no se cambia de paso: DSGN-111 (segunda revision de la 1.17.0)
    BOM = b'\xef\xbb\xbf'
    call('delphi_create', {'kind': 'form-vcl', 'name': 'UAcento', 'formname': 'FormAcento', 'project': RDPR})
    ACDFM, ACPAS = os.path.join(RDIR, 'UAcento.dfm'), os.path.join(RDIR, 'UAcento.pas')
    check('R17 (de partida) el form y la unidad recien creados llevan BOM (el IDE de esta maquina, en UTF-8)',
          bytes_de(ACDFM).startswith(BOM) and bytes_de(ACPAS).startswith(BOM), bytes_de(ACDFM)[:3])
    sin_bom = bytes_de(ACDFM)[3:]  # leido ANTES: open('wb') lo vacia
    open(ACDFM, 'wb').write(sin_bom)  # como lo guarda el IDE con todo ASCII
    antes_dfm, antes_pas = bytes_de(ACDFM), bytes_de(ACPAS)
    r = dsg(command='insert', path=ACDFM, classname='TLabel', component='LblDirección')
    check('R17 un nombre con acento en un form sin BOM: DSGN-111 nombrando el form, y nada escrito',
          mc.abre(r, 'SR_DESIGNER_NOMBRE_SIN_BOM_FMT') and 'UAcento.dfm' in r and
          bytes_de(ACDFM) == antes_dfm and bytes_de(ACPAS) == antes_pas, r[:300])
    open(ACDFM, 'wb').write(BOM + antes_dfm)
    open(ACPAS, 'wb').write(antes_pas[3:])
    r = dsg(command='insert', path=ACDFM, classname='TButton')
    check('R17 ...un nombre ASCII entra igual con la unidad sin BOM', J(r).get('inserted') == 'Button1', r[:300])
    # una unidad SOLO ASCII no tiene codificacion que respetar: el nombre la
    # elige, como el IDE al guardar -CP1252 si cabe, que dcc lee- (4.1 de la
    # 1.18.0). DSGN-111 la negaba por la preferencia del IDE (revisor propio
    # de la 4.1, 9-oct-2026: una segunda copia de la regla del escritor)
    r = dsg(command='set', path=ACDFM, component='Button1', prop='Name', value='BtnAcción')
    pas = bytes_de(ACPAS)
    check('R17 ...el renombrado a uno con acento con la unidad SOLO ASCII y sin BOM entra: la unidad pasa a '
          'CP1252 sin BOM, como la guarda el IDE (DSGN-111 lo negaba)',
          J(r).get('renamed') == 'Button1' and not pas.startswith(BOM) and 'BtnAcción'.encode('cp1252') in pas,
          (r[:300], pas[:60]))
    compila_y_cuadra('R17a', RPROJ, ACDFM)
    # una unidad que YA tiene su codificacion en UTF-8 SIN BOM (acentos ya
    # escritos asi, que dcc lee en ANSI): un nombre con acento no entra sin
    # cambiarla
    open(ACPAS, 'wb').write(pas.decode('cp1252').encode('utf-8'))
    antes_dfm, antes_pas = bytes_de(ACDFM), bytes_de(ACPAS)
    r = dsg(command='insert', path=ACDFM, classname='TLabel', component='LblDirección')
    check('R17 ...con la unidad en UTF-8 sin BOM y ya con acentos: DSGN-111 nombrando la unidad, nada escrito',
          mc.abre(r, 'SR_DESIGNER_NOMBRE_SIN_BOM_FMT') and 'UAcento.pas' in r and
          bytes_de(ACDFM) == antes_dfm and bytes_de(ACPAS) == antes_pas, r[:300])
    open(ACPAS, 'wb').write(BOM + antes_pas)
    r = dsg(command='insert', path=ACDFM, classname='TLabel', component='LblDirección')
    check('R17 ...con los dos con BOM, entra (y los dos siguen con BOM)', J(r).get('inserted') == 'LblDirección' and
          bytes_de(ACDFM).startswith(BOM) and bytes_de(ACPAS).startswith(BOM), r[:300])
    compila_y_cuadra('R17', RPROJ, ACDFM)
    rect, _ = rect_de(ACDFM, 'LblDirección')
    check('R17 ...y preview lo encuentra por su nombre con acento', bool(rect) and rect.startswith('10,10,'), rect)

    # =================================================================== X1
    r = call('delphi_create', {'kind': 'form-vcl', 'name': 'UOtra', 'project': os.path.join(VDIR, 'EdVcl.dpr')})
    OTRA = os.path.join(VDIR, 'UOtra.dfm')
    dsg(command='to-binary', path=OTRA)
    r = dsg(command='insert', path=OTRA, classname='TButton')
    check('X1 un .dfm binario: DSGN-075 (a texto primero)', mc.abre(r, 'SR_DESIGNER_EDIT_BINARIO_FMT'), r[:300])
    SUELTO = escribe(os.path.join(JAIL, 'Suelto.dfm'), "object Suelto: TSuelto\r\nend\r\n")
    r = dsg(command='insert', path=SUELTO, classname='TButton')
    check('X1 un form sin su unidad: DSGN-076', mc.abre(r, 'SR_DESIGNER_EDIT_SIN_UNIDAD_FMT'), r[:300])
    HDFM = escribe(os.path.join(JAIL, 'UHija.dfm'),
                   "inherited FormHija: TFormHija\r\n  inherited Boton: TButton\r\n  end\r\n"
                   "  inline Marco1: TMarco\r\n    inherited Dentro: TButton\r\n    end\r\n    object Nuevo: TButton\r\n"
                   "    end\r\n  end\r\nend\r\n")
    escribe(os.path.join(JAIL, 'UHija.pas'),
            "unit UHija;\r\ninterface\r\nuses UBase, UMarco;\r\ntype\r\n  TFormHija = class(TFormBase)\r\n"
            "    Marco1: TMarco;\r\n  end;\r\nimplementation\r\n{$R *.dfm}\r\nend.\r\n")
    r = dsg(command='delete', path=HDFM, component='Boton')
    check('X1 un componente heredado: DSGN-084', mc.abre(r, 'SR_DESIGNER_HEREDADO_FMT'), r[:300])
    r = dsg(command='delete', path=HDFM, component='Nuevo')
    check('X1 un componente de un frame en linea: DSGN-083', mc.abre(r, 'SR_DESIGNER_DENTRO_DE_INLINE_FMT'), r[:300])
    r = dsg(command='delete', path=HDFM, component='FormHija')
    check('X1 el form mismo: DSGN-085', mc.abre(r, 'SR_DESIGNER_RAIZ_FMT'), r[:300])
    r = dsg(command='insert', path=VDFM)
    check('X1 insert sin classname: DSGN-003', mc.abre(r, 'SR_DESIGNER_NEED_CLASS'), r[:300])
    r = dsg(command='delete', path=VDFM)
    check('X1 delete sin component: DSGN-006', mc.abre(r, 'SR_DESIGNER_NEED_COMPONENT'), r[:300])
    r = dsg(command='insert', path=VDFM, classname='TButton', value='x')
    check('X1 un parametro que no va con el comando: DSGN-047', mc.abre(r, 'SR_DESIGNER_NO_VA_CON_COMANDO_FMT'),
          r[:300])
    FDFM = escribe(os.path.join(FUERA, 'Fuera.dfm'), "object Fuera: TFuera\r\nend\r\n")
    escribe(os.path.join(FUERA, 'Fuera.pas'),
            "unit Fuera;\r\ninterface\r\ntype\r\n  TFuera = class(TForm)\r\n  end;\r\nimplementation\r\nend.\r\n")
    antes = bytes_de(FDFM)
    r = dsg(command='insert', path=FDFM, classname='TButton')
    check('X1 un form fuera de la jaula: rechazado, y no se toca', mc.rechazado(r) and bytes_de(FDFM) == antes, r[:300])
finally:
    try:
        srv.mata()
    except Exception:
        pass

# --------------------------------------------- X1: credencial de solo lectura
ro = mc.Stdio(EXE, ENV, nombre='designer-edit-ro', args=('--readonly',), t=300)
try:
    antes = bytes_de(VDFM)
    r = ro.call('delphi_designer', {'command': 'insert', 'path': VDFM, 'classname': 'TButton'}, t=120)
    r2 = ro.call('delphi_designer', {'command': 'delete', 'path': VDFM, 'component': 'Label1'}, t=120)
    r3 = ro.call('delphi_designer', {'command': 'set', 'path': VDFM, 'component': 'Label1', 'prop': 'Caption',
                                     'value': 'x'}, t=120)
    # con SU codigo (READ-002), no un rechazado cualquiera: otro motivo de
    # rechazo tambien pasaba (revision de la 1.17.0)
    check('X1 en solo lectura insert, set y delete se niegan con READ-002, y el form no cambia',
          all(mc.rechazado(x) and mc.es(x, 'SR_READ_ONLY_FMT') for x in (r, r2, r3)) and bytes_de(VDFM) == antes,
          (r[:200], r2[:200], r3[:200]))
    r = ro.call('delphi_designer', {'command': 'tree', 'path': VDFM}, t=120)
    check('X1 ...y leerlo si', not mc.fallo(r) and 'Label1' in r, r[:200])
finally:
    try:
        ro.mata()
    except Exception:
        pass

mc.borra(BASE)
mc.fin('designer edit')
