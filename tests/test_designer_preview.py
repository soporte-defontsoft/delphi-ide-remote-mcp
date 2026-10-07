# -*- coding: utf-8 -*-
"""delphi_designer command=preview (1.17.0, RenderForm): un PNG de lo que
ensena el designer del IDE, dibujado por los renderizadores de src/Render
(DelphiFormRenderVcl/Fmx) que el servidor lanza a su lado.

Las cobayas son las del sandbox de RenderForm (hechas a mano para medir el
renderizador, 7-oct-2026), escritas aqui en la jaula de la bateria: una form
con no visuales, una heredada, frames inline VCL y FMX. Lo que se pinta se
comprueba POR PIXEL (mc.png_pixeles): el tamano de un PNG no dice si se pinto.
Los casos son los de su bateria DUnitX (RenderTests, 20/20 lanzando los exes
a mano) pasados por el servidor; las cobayas de Galatea no (estan fuera de
las raices a proposito), y el tiempo limite tampoco: el servidor no deja
pedir uno corto (lo dice una NOTA).

  P1  la form entera: raiz, componentes, nonVisual listado sin dibujar,
      fidelity, el PNG en out= con su tamano y el color del panel
  P2  component: el recorte (componentRect, el frame con su origen, el PNG
      del tamano del componente) y el componente que no existe (DSGN-066)
  P3  state: un estado de vista que se ve (el color del panel) y el que
      nombra un componente que no existe (RENDER-011, del ayudante tal cual)
  P4  una form heredada: el color que pone la hija, no el de la base
  P5  frames inline VCL: el fichero del frame y los inherited de cada uno
  P6  FMX: frames inline por pixel, fidelity canvas, el estilo de una
      plataforma del designer y la que no existe (RENDER-017)
  P7  nonvisual=true dibuja el icono donde lo guarda el dfm
  P8  una clase que ningun paquete registra: substituted y su nota
  P9  entrega: inline (imagen en la respuesta, temporal consumido) y out=
      que ya existe (lo de antes, sellado en la papelera)
  P10 rechazos antes de lanzar nada: una comilla que intentaba colar otro
      interruptor (y el fichero de fuera NO aparece), estilo de plataforma en
      VCL, estilo relativo, estilo y form fuera de la jaula, framework que no
      casa, out= con otra extension, parametro que no va con preview
  P11 sin los renderizadores junto al exe: DSGN-060
  P12 un estilo .vsf: la form VCL sale fuera de modo diseno con ese estilo

Uso:  python tests/test_designer_preview.py [ruta-a-DelphiLspMcp.exe]
"""
import glob, json, os, shutil
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer_preview')
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
OUT = os.path.join(JAIL, 'out')
for d in (JAIL, FUERA, OUT):
    os.makedirs(d, exist_ok=True)


def escribe(nombre, texto, carpeta=JAIL):
    ruta = os.path.join(carpeta, nombre)
    with open(ruta, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write(texto)
    return ruta


def J(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


FONT = """  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  PixelsPerInch = 96
  TextHeight = 15
"""

PRUEBA = escribe('Prueba.dfm', """object FormPrueba: TFormPrueba
  Left = 0
  Top = 0
  Caption = 'Prueba'
  ClientHeight = 200
  ClientWidth = 400
""" + FONT + """  object Label1: TLabel
    Left = 16
    Top = 16
    Width = 60
    Height = 15
    Caption = 'Nombre'
  end
  object Edit1: TEdit
    Left = 16
    Top = 36
    Width = 200
    Height = 23
    TabOrder = 0
    Text = 'Texto de prueba'
  end
  object Panel1: TPanel
    Left = 16
    Top = 140
    Width = 344
    Height = 41
    Caption = ''
    Color = clSkyBlue
    ParentBackground = False
    TabOrder = 1
  end
  object Timer1: TTimer
    Left = 300
    Top = 60
  end
  object ActionList1: TActionList
    Left = 340
    Top = 60
  end
end
""")

escribe('UBase.pas', """unit UBase;
interface
uses Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, System.Classes, Vcl.Controls;
type
  TFormBase = class(TForm)
    PanelCabecera: TPanel;
    BotonAceptar: TButton;
  end;
implementation
{$R *.dfm}
end.
""")
escribe('UBase.dfm', """object FormBase: TFormBase
  Left = 0
  Top = 0
  Caption = 'Base'
  ClientHeight = 240
  ClientWidth = 420
""" + FONT + """  object PanelCabecera: TPanel
    Left = 0
    Top = 0
    Width = 420
    Height = 41
    Align = alTop
    Caption = ''
    Color = clSkyBlue
    ParentBackground = False
    TabOrder = 0
  end
  object BotonAceptar: TButton
    Left = 320
    Top = 200
    Width = 90
    Height = 25
    Caption = 'Aceptar'
    TabOrder = 1
  end
end
""")
escribe('UHija.pas', """unit UHija;
interface
uses UBase, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, System.Classes, Vcl.Controls;
type
  TFormHija = class(TFormBase)
    EditHija: TEdit;
  end;
implementation
{$R *.dfm}
end.
""")
HIJA = escribe('UHija.dfm', """inherited FormHija: TFormHija
  Caption = 'Hija'
  ClientHeight = 300
  inherited PanelCabecera: TPanel
    Color = clMoneyGreen
  end
  object EditHija: TEdit
    Left = 16
    Top = 96
    Width = 200
    Height = 23
    TabOrder = 2
    Text = 'solo en la hija'
  end
end
""")

escribe('UFrameX.pas', """unit UFrameX;
interface
uses Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, System.Classes, Vcl.Controls;
type
  TFrameX = class(TFrame)
    EditFrame: TEdit;
    PanelFrame: TPanel;
  end;
implementation
{$R *.dfm}
end.
""")
escribe('UFrameX.dfm', """object FrameX: TFrameX
  Left = 0
  Top = 0
  Width = 300
  Height = 120
  TabOrder = 0
  object EditFrame: TEdit
    Left = 8
    Top = 32
    Width = 200
    Height = 23
    TabOrder = 0
    Text = 'texto del frame'
  end
  object PanelFrame: TPanel
    Left = 8
    Top = 64
    Width = 280
    Height = 41
    Caption = ''
    Color = clSkyBlue
    ParentBackground = False
    TabOrder = 1
  end
end
""")
escribe('UConFrame.pas', """unit UConFrame;
interface
uses UFrameX, Vcl.Forms, Vcl.StdCtrls, System.Classes, Vcl.Controls;
type
  TFormConFrame = class(TForm)
    FrameX1: TFrameX;
    FrameX2: TFrameX;
  end;
implementation
{$R *.dfm}
end.
""")
CONFRAME = escribe('UConFrame.dfm', """object FormConFrame: TFormConFrame
  Left = 0
  Top = 0
  Caption = 'Con frames'
  ClientHeight = 300
  ClientWidth = 340
""" + FONT + """  inline FrameX1: TFrameX
    Left = 16
    Top = 32
    Width = 300
    Height = 120
    TabOrder = 0
  end
  inline FrameX2: TFrameX
    Left = 16
    Top = 168
    Width = 300
    Height = 120
    TabOrder = 1
    inherited PanelFrame: TPanel
      Color = clYellow
    end
  end
end
""")

escribe('FrameF.pas', """unit FrameF;
interface
uses System.Classes, FMX.Forms, FMX.StdCtrls, FMX.Edit, FMX.Objects, FMX.Types, FMX.Controls;
type
  TFrameF = class(TFrame)
    EditF: TEdit;
    RectF: TRectangle;
  end;
implementation
{$R *.fmx}
end.
""")
escribe('FrameF.fmx', """object FrameF: TFrameF
  Size.Width = 300.000000000000000000
  Size.Height = 120.000000000000000000
  Size.PlatformDefault = False
  object EditF: TEdit
    Position.X = 8.000000000000000000
    Position.Y = 32.000000000000000000
    Size.Width = 200.000000000000000000
    Size.Height = 22.000000000000000000
    Size.PlatformDefault = False
    Text = 'texto del frame'
  end
  object RectF: TRectangle
    Position.X = 8.000000000000000000
    Position.Y = 64.000000000000000000
    Size.Width = 280.000000000000000000
    Size.Height = 40.000000000000000000
    Size.PlatformDefault = False
    Fill.Color = xFFC0E0FF
  end
end
""")
escribe('ConFrameF.pas', """unit ConFrameF;
interface
uses System.Classes, FMX.Forms, FMX.StdCtrls, FMX.Types, FMX.Controls, FrameF;
type
  TFormConFrameF = class(TForm)
    FrameF1: TFrameF;
    FrameF2: TFrameF;
  end;
implementation
{$R *.fmx}
end.
""")
CONFRAMEF = escribe('ConFrameF.fmx', """object FormConFrameF: TFormConFrameF
  Left = 0
  Top = 0
  Caption = 'Con frames FMX'
  ClientHeight = 300
  ClientWidth = 340
  FormFactor.Width = 320
  FormFactor.Height = 480
  FormFactor.Devices = [Desktop]
  DesignerMasterStyle = 0
  inline FrameF1: TFrameF
    Position.X = 16.000000000000000000
    Position.Y = 32.000000000000000000
  end
  inline FrameF2: TFrameF
    Position.X = 16.000000000000000000
    Position.Y = 168.000000000000000000
    inherited RectF: TRectangle
      Fill.Color = xFFFFFF80
    end
  end
end
""")

INVENTADA = escribe('Inventada.dfm', """object FormInventada: TFormInventada
  Left = 0
  Top = 0
  Caption = 'Inventada'
  ClientHeight = 120
  ClientWidth = 300
""" + FONT + """  object Raro: TClaseQueNoExisteEnNingunPaquete
    Left = 16
    Top = 16
    Width = 200
    Height = 60
  end
end
""")
FORM_FUERA = escribe('Fuera.dfm', open(PRUEBA, encoding='utf-8').read(), FUERA)

CIELO = (166, 202, 240)     # clSkyBlue = $F0CAA6
VERDE = (192, 220, 192)     # clMoneyGreen = $C0DCC0
AMARILLO = (255, 255, 0)    # clYellow
ROJO = (255, 0, 0)          # TColor 255


def cerca(p, q, tol=3):
    return p is not None and all(abs(a - b) <= tol for a, b in zip(p, q))


def pixel_de(png, x, y):
    try:
        _, _, px = mc.png_pixeles(png)
        return px(x, y)
    except Exception as e:
        return None


def png(nombre):
    return os.path.join(OUT, nombre)


EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='preview', t=180)
call = srv.call


def preview(**kw):
    a = {'command': 'preview'}
    a.update(kw)
    return call('delphi_designer', a, t=180)


try:
    # ------------------------------------------------------------------ P1
    r = preview(path=PRUEBA, out=png('p1.png'), inline='false')
    j = J(r)
    raiz = j.get('root') or {}
    check('P1 la form entera: su raiz, sus componentes y el framework',
          raiz.get('name') == 'FormPrueba' and raiz.get('kind') == 'form' and
          j.get('framework') == 'vcl' and j.get('components') == 5, r[:400])
    check('P1 una form estandar no carga ningun paquete del IDE (packages 0/0)',
          j.get('packages') == '0/0' and 'substituted' not in j and 'ignored' not in j, r[:400])
    nv = sorted((x.get('name'), x.get('class')) for x in j.get('nonVisual') or [])
    check('P1 nonVisual lista los no visuales SIN dibujarlos (por defecto)',
          nv == [('ActionList1', 'TActionList'), ('Timer1', 'TTimer')] and
          j.get('nonVisualDrawn') is False and mc.es(j.get('nonVisualNote', ''), 'SN_DESIGNER_NO_VISUALES_OCULTOS'),
          r[:500])
    check('P1 fidelity dice como se pinto (window en una sesion con escritorio, print en un servicio)',
          j.get('fidelity') in ('window', 'print') and
          (j.get('fidelity') != 'print' or mc.es(j.get('fidelityNote', ''), 'SN_DESIGNER_FIDELIDAD_PRINT')),
          j.get('fidelity'))
    ancho, alto, _ = mc.png_pixeles(png('p1.png')) if os.path.exists(png('p1.png')) else (0, 0, None)
    check('P1 el PNG cae en out= con el tamano del cliente de la form (400x200)',
          (ancho, alto) == (400, 200), (ancho, alto))
    check('P1 ...y lo PINTADO es la form: el panel con su color (por pixel)',
          cerca(pixel_de(png('p1.png'), 30, 150), CIELO), pixel_de(png('p1.png'), 30, 150))
    check('P1 el frame de una imagen sin recorte empieza en 0,0',
          j.get('frame') == '400x200@400x200+0+0', j.get('frame'))

    # ------------------------------------------------------------------ P2
    r = preview(path=PRUEBA, component='Panel1', out=png('p2.png'), inline='false')
    j = J(r)
    check('P2 component: componentRect en coordenadas de la form y el frame con su origen',
          j.get('componentRect') == '16,140,344,41' and j.get('frame') == '344x41@344x41+16+140' and
          j.get('croppedFrom') == '400x200', r[:500])
    a2 = mc.png_pixeles(png('p2.png'))[:2] if os.path.exists(png('p2.png')) else None
    check('P2 ...el PNG es el del componente, recortado por el servidor, y del color del panel',
          a2 == (344, 41) and cerca(pixel_de(png('p2.png'), 10, 10), CIELO), (a2, pixel_de(png('p2.png'), 10, 10)))
    r = preview(path=PRUEBA, component='NoHayTal')
    check('P2 un componente que no esta: DSGN-066, sin imagen',
          mc.abre(r, 'SR_DESIGNER_PREVIEW_SIN_COMPONENTE_FMT'), r[:300])

    # ------------------------------------------------------------------ P3
    r = preview(path=PRUEBA, state='Panel1.Color=255;Edit1.Text=cambiado', out=png('p3.png'), inline='false')
    check('P3 state: el estado de vista se ve en la imagen (el panel en rojo)',
          cerca(pixel_de(png('p3.png'), 30, 150), ROJO), (r[:200], pixel_de(png('p3.png'), 30, 150)))
    check('P3 ...y nunca se escribe en el fichero',
          'clSkyBlue' in open(PRUEBA, encoding='utf-8').read(), 'el .dfm cambio')
    r = preview(path=PRUEBA, state='NoHayTal.Caption=x')
    check('P3 un estado de un componente que no existe: el RENDER-011 del ayudante, tal cual',
          mc.abre(r, 'SR_RENDER_ESTADO_SIN_COMPONENTE_FMT') and mc.outcome(r) == 'NOT_FOUND', r[:300])
    r = preview(path=PRUEBA, state='Edit1.NoExisteTal=1')
    check('P3 ...y el de una propiedad que la clase no publica: RENDER-012',
          mc.abre(r, 'SR_RENDER_ESTADO_NO_PUBLICA_FMT') and 'NoExisteTal' in r, r[:300])

    # ------------------------------------------------------------------ P4
    r = preview(path=HIJA, out=png('p4.png'), inline='false')
    j = J(r)
    check('P4 una form heredada: la raiz es la hija y trae los componentes de la base',
          (j.get('root') or {}).get('name') == 'FormHija' and j.get('components') == 3 and
          'ignored' not in j, r[:400])
    check('P4 ...el panel con el color que pone la HIJA, no el de la base',
          cerca(pixel_de(png('p4.png'), 200, 20), VERDE), pixel_de(png('p4.png'), 200, 20))

    # ------------------------------------------------------------------ P5
    r = preview(path=CONFRAME, out=png('p5.png'), inline='false')
    j = J(r)
    check('P5 frames inline VCL: el del fichero del frame en el primero',
          cerca(pixel_de(png('p5.png'), 16 + 8 + 10, 32 + 64 + 10), CIELO),
          (r[:200], pixel_de(png('p5.png'), 34, 106)))
    check('P5 ...y el inherited del segundo aplicado encima, sin nada ignorado',
          cerca(pixel_de(png('p5.png'), 16 + 8 + 10, 168 + 64 + 10), AMARILLO) and 'ignored' not in j,
          (pixel_de(png('p5.png'), 34, 242), j.get('ignored')))
    r = preview(path=os.path.join(JAIL, 'UFrameX.dfm'), out=png('p5b.png'), inline='false')
    j = J(r)
    check('P5 un frame suelto: frame por su .pas, dibujado en una form de su tamano',
          (j.get('root') or {}).get('kind') == 'frame' and os.path.exists(png('p5b.png')) and
          mc.png_pixeles(png('p5b.png'))[:2] == (300, 120), r[:300])

    # ------------------------------------------------------------------ P6
    r = preview(path=CONFRAMEF, out=png('p6.png'), inline='false')
    j = J(r)
    check('P6 FMX: framework fmx, fidelity canvas',
          j.get('framework') == 'fmx' and str(j.get('fidelity', '')).startswith('canvas'), r[:300])
    check('P6 FMX inline por pixel: el rectangulo del frame en el primero...',
          cerca(pixel_de(png('p6.png'), 16 + 8 + 10, 32 + 64 + 10), (192, 224, 255)),
          pixel_de(png('p6.png'), 34, 106))
    check('P6 ...y el del inherited en el segundo',
          cerca(pixel_de(png('p6.png'), 16 + 8 + 10, 168 + 64 + 10), (255, 255, 128)),
          pixel_de(png('p6.png'), 34, 242))
    check('P6 ...sin nada ignorado', 'ignored' not in j, j.get('ignored'))
    r = preview(path=CONFRAMEF, component='FrameF2', out=png('p6c.png'), inline='false')
    check('P6 FMX component: el rect del frame metido, en coordenadas de la form',
          J(r).get('componentRect') == '16,168,300,120', r[:400])
    r = preview(path=os.path.join(JAIL, 'FrameF.fmx'), inline='false')
    check('P6 un frame FMX suelto: frame por su .pas',
          (J(r).get('root') or {}).get('kind') == 'frame', r[:300])
    r = preview(path=CONFRAMEF, style='android', out=png('p6a.png'), inline='false')
    check('P6 style con una plataforma del designer (android): STYLE lo dice',
          'ANDROIDSTYLE' in str(J(r).get('style', '')), r[:300])
    r = preview(path=CONFRAMEF, style='none', inline='false')
    check('P6 style none: el estilo por defecto de Windows, como el designer',
          str(J(r).get('style', '')).startswith('none'), r[:300])
    r = preview(path=CONFRAMEF, style='plataformainventada')
    check('P6 una plataforma que no existe: el RENDER-017 del ayudante con la lista',
          mc.abre(r, 'SR_RENDER_ESTILO_DESCONOCIDO_FMT') and 'android' in r, r[:300])

    # ------------------------------------------------------------------ P7
    preview(path=PRUEBA, out=png('p7off.png'), inline='false')
    r = preview(path=PRUEBA, nonvisual=True, out=png('p7on.png'), inline='false')
    off, on = pixel_de(png('p7off.png'), 300, 60), pixel_de(png('p7on.png'), 300, 60)
    check('P7 nonvisual=true dibuja el icono en el Left/Top que guarda el dfm (y sin el, fondo)',
          J(r).get('nonVisualDrawn') is True and on is not None and off is not None and on != off,
          (on, off))

    # ------------------------------------------------------------------ P8
    r = preview(path=INVENTADA, inline='false')
    j = J(r)
    check('P8 una clase que ningun paquete registra: substituted y su nota',
          j.get('substituted') == ['TClaseQueNoExisteEnNingunPaquete'] and
          mc.es(j.get('substitutedNote', ''), 'SN_DESIGNER_SUSTITUIDAS'), r[:500])
    check('P8 ...despues de buscarla en los paquetes del IDE (packages ya no es 0/0)',
          str(j.get('packages', '0/0')).split('/')[0] not in ('', '0'), j.get('packages'))

    # ------------------------------------------------------------------ P9
    # P8 dejo el suyo a proposito (inline=false sin out=: se consume al
    # descargarlo): lo que se mide es que ESTA llamada no deje ninguno
    capturas = os.path.join(JAIL, '__delphi-temp', '**', 'designer', '*.png')
    antes = set(glob.glob(capturas, recursive=True))
    r = preview(path=PRUEBA)
    j = J(r)
    sueltos = sorted(set(glob.glob(capturas, recursive=True)) - antes)
    check('P9 inline (por defecto): la imagen viaja en la respuesta y su temporal se consume',
          j.get('inlineImage') is True and j.get('consumed') is True and 'screenshot' not in j and
          mc.es(j.get('inlineNote', ''), 'SN_DESIGNER_INLINE_NOTE_FMT') and
          mc.es(j.get('frameNote', ''), 'SN_DESIGNER_FRAME_NOTE'), r[:600])
    check('P9 ...y no deja PNG en la carpeta de capturas del diseñador', not sueltos, sueltos)
    escribe('existente.png', 'contenido de antes', OUT)
    r = preview(path=PRUEBA, out=png('existente.png'), inline='false')
    sellada = glob.glob(os.path.join(JAIL, '**', '__delphi-patch', '**', 'existente.png*'), recursive=True)
    check('P9 out= sobre un fichero que ya estaba: lo de antes, sellado en la papelera',
          bool(sellada) and mc.png_pixeles(png('existente.png'))[:2] == (400, 200), (r[:200], sellada))

    # ------------------------------------------------------------------ P10
    victima = os.path.join(FUERA, 'colado.png')
    r = preview(path=PRUEBA, state='Edit1.Text=a" --out "' + victima)
    check('P10 una comilla en un valor (colaba otro --out): DSGN-065 y nada se lanza',
          mc.abre(r, 'SR_DESIGNER_VALOR_CON_COMILLAS_FMT') and not os.path.exists(victima),
          (r[:300], os.path.exists(victima)))
    r = preview(path=PRUEBA, style='android')
    check('P10 un estilo de plataforma en una form VCL: DSGN-072',
          mc.abre(r, 'SR_DESIGNER_STYLE_VCL_FMT'), r[:300])
    r = preview(path=PRUEBA, style='estilos\\Carbon.vsf')
    check('P10 un estilo por ruta relativa: DSGN-073 (no se resuelve contra nada)',
          mc.abre(r, 'SR_DESIGNER_STYLE_NOMBRE_FMT'), r[:300])
    escribe('Fuera.vsf', 'no es un estilo', FUERA)
    r = preview(path=PRUEBA, style=os.path.join(FUERA, 'Fuera.vsf'))
    check('P10 un estilo fuera de la jaula: la puerta de lectura', mc.es(r, 'SR_JAIL_FMT'), r[:300])
    r = preview(path=FORM_FUERA)
    check('P10 una form fuera de la jaula: la puerta de lectura', mc.es(r, 'SR_JAIL_FMT'), r[:300])
    r = preview(path=PRUEBA, framework='fmx')
    check('P10 framework que no casa con el fichero: DSGN-074',
          mc.abre(r, 'SR_DESIGNER_FW_NO_CASA_FMT'), r[:300])
    r = preview(path=PRUEBA, out=png('mal.jpg'))
    check('P10 out= con otra extension: la regla de toda captura',
          mc.abre(r, 'SR_CAPTURE_EXT_FMT') and not os.path.exists(png('mal.jpg')), r[:300])
    r = preview(path=PRUEBA, classname='TButton')
    check('P10 un parametro que no va con preview: DSGN-047',
          mc.abre(r, 'SR_DESIGNER_NO_VA_CON_COMANDO_FMT'), r[:300])
    r = call('delphi_designer', {'command': 'tree', 'path': PRUEBA, 'state': 'Edit1.Text=x'})
    check('P10 ...ni los de preview con otro comando', mc.abre(r, 'SR_DESIGNER_NO_VA_CON_COMANDO_FMT'), r[:300])

    # ------------------------------------------------------------------ P12
    # un .vsf del IDE (Redist\styles\vcl): se copia a la jaula, que es donde
    # la bateria sabe que se puede leer
    vsf = sorted(glob.glob(r'C:\Program Files (x86)\Embarcadero\Studio\*\Redist\styles\vcl\*.vsf'))
    if vsf:
        estilo = shutil.copy(vsf[0], os.path.join(JAIL, 'Estilo.vsf'))
        r = preview(path=PRUEBA, style=estilo, out=png('p12.png'), inline='false')
        check('P12 un .vsf: la form VCL fuera de modo diseno, y STYLE lo dice',
              'not in design mode' in str(J(r).get('style', '')) and os.path.exists(png('p12.png')), r[:400])
        check('P12 ...y el estilo se ve: el fondo ya no es el de la form sin estilo',
              not cerca(pixel_de(png('p12.png'), 380, 10), pixel_de(png('p1.png'), 380, 10), 0),
              (pixel_de(png('p12.png'), 380, 10), pixel_de(png('p1.png'), 380, 10)))
    else:
        print('NOTA P12: no hay ningun .vsf en Redist\\styles\\vcl de este RAD Studio: no se mide el estilo VCL')
finally:
    try:
        srv.mata()
    except Exception:
        pass

# ---------------------------------------------------------------------- P11
EXE2 = mc.copia_exe(os.path.join(BASE, 'srv_sin'), con_render=False)
srv2 = mc.Stdio(EXE2, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='preview_sin', t=120)
try:
    r = srv2.call('delphi_designer', {'command': 'preview', 'path': PRUEBA})
    check('P11 sin los renderizadores junto al exe: DSGN-060 con el nombre del que falta',
          mc.abre(r, 'SR_DESIGNER_SIN_RENDER_FMT') and 'DelphiFormRenderVcl.exe' in r, r[:300])
finally:
    try:
        srv2.mata()
    except Exception:
        pass

print('NOTA el tiempo limite (RENDER-007 / DSGN-062) no se mide aqui: el servidor no deja pedir uno corto; '
      'lo midio la bateria DUnitX del ayudante (rc 3)')
print('NOTA un hermano .dfm/.pas que sea un ENLACE de fichero (el ayudante no lo lee: FormRender.Comun.EsEnlace) '
      'no se mide: esta cuenta no puede crear symlinks (privilegio o modo desarrollador), como K16b')
mc.borra(BASE)
mc.fin('designer preview')
