# -*- coding: utf-8 -*-
"""1.29 (C2): delphi_designer preview scale= - el form como lo ensena una aplicacion en un monitor a esa escala de
Windows, sin depender de la escala de la maquina del servidor (los renderizadores son ajenos al DPI). Lo que hace
cada marco es SU juez (medido el 7-nov-2026 en la sonda MideEscala129): la VCL, ScaleForPPI (lo que hace un form al
pasar a un monitor de otro DPI; nada si dice Scaled = False), ANTES de mostrarlo, como una aplicacion que escala sus
forms (David: "el orden importa"); FMX, la escala forzada de la ventana y el bitmap a esa escala.
componentRect y frame quedan en unidades del fichero: el renderizador dice cuantos pixeles por unidad (SCALE=).
Eso arregla tambien un form guardado a 120 PPI y pintado con un .vsf, que la VCL lleva a 96 al cargarlo y cuya
respuesta decia "1 pixel = 1 unidad" (medido en produccion: OKBtn 300,8,75,25 en vez de 375,10,94,31).

  E1 VCL a 96, scale=150: la imagen entera a 600x300 (400x200 x 1,5). ROJO contra 166bea8b (no habia scale)
  E2 ...scale=125: 500x250; sin scale, 400x200, como siempre
  E3 scale=150 component=Anclado (anclado abajo a la derecha): componentRect en unidades del fichero
     (300,150,75,25) y el frame a 1,5 pixeles por unidad (el anclaje no lo mueve; medido aparte que escalar
     antes o despues de mostrar da lo mismo aqui: este check no vigila ese orden)
  E4 scale=150 nonvisual=true component=Timer1: el icono de un no visual, en unidades del fichero (200,100,28,40)
  E5 un form guardado a 120 PPI: sin estilo, como siempre, en sus unidades (OKBtn 375,10,94,31)
  E6 ...con un .vsf: componentRect y frame en SUS unidades, no 300,8,75,25. ROJO contra 166bea8b
  E7 ...scale=150: OKBtn a 1,2 pixeles por unidad (144/120), componentRect en sus unidades
  E8 Scaled = False y scale=150: a su tamano (400x200), como lo ensenaria la aplicacion, y RENDER-031 lo dice
  E9 un frame VCL de raiz, scale=150: componentRect en unidades del fichero y la imagen a 1,5
  E10 FMX scale=150: 600x300 y componentRect 16,16,80,22; scale=200: 800x400; el icono de un no visual, en
      unidades del fichero
  E11 la respuesta: scale y scaleNote (DSGN-191), con lo de los dibujos nativos solo en la VCL
  E12 scale fuera de 100..500: DSGN-190 sin lanzar nada (uno negativo lo niega antes el esquema, SYS-016); scale
      con layout: DSGN-047
  E13 (A16 de cierre-final-1-29-1, la B de David) insert en un .dfm a 120 PPI: el tamano y los margenes de su
      constructor escalados al del FICHERO, como los deja el disenador al soltarlo (SetParent -> ScaleForPPI) y
      como guardo el IDE los de ese form (94x31, Margins 4), en 10,10. ROJO contra 2c790b84 (75x25, sin Margins).
      E13b control: a 96, 75x25 y sin Margins, como siempre. E13c control: set de otra propiedad en un control
      que ya estaba no lo vuelve a escalar. E13d: lo que el agente da en el insert (props Width=200) esta en
      unidades del fichero y gana tal cual - escalado, salia 250 (revision propia del diff, 11-nov) -; lo demas,
      escalado

Uso:  python tests/test_preview_escala_129.py [ruta-a-DelphiLspMcp.exe]
"""
import glob
import json
import os
import re
import shutil
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('preview_escala_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)


def escribe(nombre, texto):
    ruta = os.path.join(JAIL, nombre)
    with open(ruta, 'w', encoding='ascii', newline='\r\n') as f:
        f.write(texto)
    return ruta


def pas(unidad, clase, padre, campos, usos):
    escribe(unidad + '.pas', 'unit %s;\n\ninterface\n\nuses\n  %s;\n\ntype\n  %s = class(%s)\n%s  end;\n\n'
                             'var\n  X: %s;\n\nimplementation\n\n{$R *.%s}\n\nend.\n'
            % (unidad, usos, clase, padre, ''.join('    %s;\n' % c for c in campos), clase,
               'fmx' if 'FMX' in usos else 'dfm'))


USOS_VCL = 'System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls'
# un form a 96 como lo escribe el IDE de hoy (ClientWidth/ClientHeight), con un anclado abajo a la derecha y un no visual
FORM96 = """object FormE: TFormE
  Left = 0
  Top = 0
  Caption = 'FormE'
  ClientHeight = 200
  ClientWidth = 400
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
%s  TextHeight = 15
  object Boton: TButton
    Left = 16
    Top = 16
    Width = 75
    Height = 25
    Caption = 'OK'
    TabOrder = 0
  end
  object Anclado: TButton
    Left = 300
    Top = 150
    Width = 75
    Height = 25
    Anchors = [akRight, akBottom]
    Caption = 'Anclado'
    TabOrder = 1
  end
  object Marca: TCheckBox
    Left = 16
    Top = 60
    Width = 120
    Height = 17
    Caption = 'Marca'
    TabOrder = 2
  end
  object Timer1: TTimer
    Left = 200
    Top = 100
  end
end
"""
F96 = escribe('UFormE.dfm', FORM96 % '')
pas('UFormE', 'TFormE', 'TForm', ['Boton: TButton', 'Anclado: TButton', 'Marca: TCheckBox', 'Timer1: TTimer'], USOS_VCL)
FNOESC = escribe('UNoEsc.dfm', (FORM96 % '  Scaled = False\n').replace('FormE: TFormE', 'NoEsc: TNoEsc'))
pas('UNoEsc', 'TNoEsc', 'TForm', ['Boton: TButton', 'Anclado: TButton', 'Marca: TCheckBox', 'Timer1: TTimer'], USOS_VCL)
# un form guardado a 120 PPI, con la forma de uno real escrito por el IDE (Width/Height, PixelsPerInch, TextHeight)
F120 = escribe('UDlg120.dfm', """object Dlg120: TDlg120
  Left = 216
  Top = 443
  Width = 503
  Height = 210
  Caption = 'Enter Password'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = 14
  Font.Name = 'MS Sans Serif'
  Font.Pitch = fpVariable
  Font.Style = []
  Position = poScreenCenter
  PixelsPerInch = 120
  TextHeight = 13
  object Label1: TLabel
    Left = 30
    Top = 20
    Width = 49
    Height = 13
    Caption = '&Password:'
  end
  object OKBtn: TButton
    Left = 375
    Top = 10
    Width = 94
    Height = 31
    Caption = 'OK'
    Default = True
    TabOrder = 0
  end
  object Edit1: TEdit
    Left = 30
    Top = 40
    Width = 321
    Height = 21
    TabOrder = 1
    Text = 'Edit1'
  end
end
""")
pas('UDlg120', 'TDlg120', 'TForm', ['Label1: TLabel', 'OKBtn: TButton', 'Edit1: TEdit'], USOS_VCL)
FMARCO = escribe('UMarcoE.dfm', """object MarcoE: TMarcoE
  Left = 0
  Top = 0
  Width = 400
  Height = 200
  TabOrder = 0
  object Boton: TButton
    Left = 200
    Top = 100
    Width = 75
    Height = 25
    Caption = 'OK'
    TabOrder = 0
  end
end
""")
pas('UMarcoE', 'TMarcoE', 'TFrame', ['Boton: TButton'], USOS_VCL)
FFMX = escribe('UFmxE.fmx', """object FmxE: TFmxE
  Left = 0
  Top = 0
  Caption = 'FmxE'
  ClientHeight = 200
  ClientWidth = 400
  FormFactor.Width = 320
  FormFactor.Height = 480
  FormFactor.Devices = [Desktop]
  DesignerMasterStyle = 0
  object Boton: TButton
    Position.X = 16.000000000000000000
    Position.Y = 16.000000000000000000
    Size.Width = 80.000000000000000000
    Size.Height = 22.000000000000000000
    Size.PlatformDefault = False
    TabOrder = 0
    Text = 'OK'
  end
  object Timer1: TTimer
    Left = 200
    Top = 100
  end
end
""")
pas('UFmxE', 'TFmxE', 'TForm', ['Boton: TButton', 'Timer1: TTimer'],
    'System.Classes, FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls')

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='escala', t=180)
call = srv.call


def preview(**kw):
    a = {'command': 'preview'}
    a.update(kw)
    return call('delphi_designer', a, t=180)


def J(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


def marco(r):
    """(imgW, imgH, srcW, srcH, ox, oy) del frame de la respuesta, o None"""
    m = re.match(r'^(\d+)x(\d+)@(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$', str(J(r).get('frame', '')))
    return tuple(int(g) for g in m.groups()) if m else None


def razon(f):
    """pixeles de la imagen por unidad del fichero, en ancho y en alto"""
    return (f[0] / f[2], f[1] / f[3]) if f and f[2] and f[3] else (0, 0)


def cerca(a, b, tol=0.03):
    return abs(a - b) <= tol


try:
    # ------------------------------------------------------------------ E1, E2
    r = preview(path=F96, scale=150)
    f = marco(r)
    check('E1 VCL a 96, scale=150: la imagen entera a 600x300. ROJO contra 166bea8b',
          f is not None and f[:4] == (600, 300, 400, 200), r[:400])
    r = preview(path=F96, scale=125)
    f = marco(r)
    check('E2 scale=125: 500x250', f is not None and f[:4] == (500, 250, 400, 200), r[:300])
    r = preview(path=F96)
    f = marco(r)
    check('E2 sin scale: 400x200, como siempre, y ni scale ni scaleNote',
          f is not None and f[:4] == (400, 200, 400, 200) and 'scale' not in J(r) and 'scaleNote' not in J(r),
          r[:300])
    # ------------------------------------------------------------------ E3
    r = preview(path=F96, scale=150, component='Anclado')
    f = marco(r)
    check('E3 scale=150 component=Anclado: componentRect en unidades del fichero (300,150,75,25)',
          J(r).get('componentRect') == '300,150,75,25', r[:400])
    check('E3 ...y el frame: 1,5 pixeles por unidad desde 300,150 (el anclaje no lo mueve)',
          f is not None and f[4:] == (300, 150) and all(cerca(x, 1.5) for x in razon(f)), f)
    # ------------------------------------------------------------------ E4
    r = preview(path=F96, scale=150, nonvisual=True, component='Timer1')
    f = marco(r)
    check('E4 scale=150 nonvisual=true component=Timer1: el icono en unidades del fichero (200,100,28,40)',
          J(r).get('componentRect') == '200,100,28,40' and f is not None and all(cerca(x, 1.5) for x in razon(f)),
          (J(r).get('componentRect'), f, r[:300]))
    # ------------------------------------------------------------------ E5, E6, E7
    r = preview(path=F120, component='OKBtn')
    f = marco(r)
    check('E5 guardado a 120, sin estilo: en sus unidades (375,10,94,31), 1 pixel por unidad',
          J(r).get('componentRect') == '375,10,94,31' and f is not None and razon(f) == (1, 1), r[:400])
    vsf = sorted(glob.glob(os.path.join(mc.raiz_ide(call), 'Redist', 'styles', 'vcl', '*.vsf')))
    if vsf:
        estilo = shutil.copy(vsf[0], os.path.join(JAIL, 'Estilo.vsf'))
        r = preview(path=F120, component='OKBtn', style=estilo)
        f = marco(r)
        check('E6 ...con un .vsf (la VCL lo lleva a 96): componentRect en SUS unidades. ROJO contra 166bea8b',
              J(r).get('componentRect') == '375,10,94,31', r[:400])
        check('E6 ...y el frame lo convierte: 0,8 pixeles por unidad (96/120) desde 375,10',
              f is not None and f[4:] == (375, 10) and all(cerca(x, 0.8) for x in razon(f)), f)
    else:
        print('NOTA E6: no hay ningun .vsf en Redist\\styles\\vcl de este RAD Studio: no se mide')
    r = preview(path=F120, component='OKBtn', scale=150)
    f = marco(r)
    check('E7 guardado a 120, scale=150: OKBtn a 1,2 pixeles por unidad (144/120), componentRect en sus unidades',
          J(r).get('componentRect') == '375,10,94,31' and f is not None and all(cerca(x, 1.2) for x in razon(f)),
          (J(r).get('componentRect'), f, r[:300]))
    # ------------------------------------------------------------------ E8
    r = preview(path=FNOESC, scale=150)
    f = marco(r)
    check('E8 Scaled = False, scale=150: a su tamano (400x200), como la aplicacion',
          f is not None and f[:4] == (400, 200, 400, 200), r[:400])
    check('E8 ...y RENDER-031 lo dice', mc.es(r, 'SN_RENDER_SIN_ESCALAR_FMT'), J(r).get('warnings'))
    # ------------------------------------------------------------------ E9
    r = preview(path=FMARCO, scale=150, component='Boton')
    f = marco(r)
    check('E9 un frame de raiz, scale=150: componentRect en unidades del fichero (200,100,75,25), la imagen a 1,5',
          J(r).get('root', {}).get('kind') == 'frame' and J(r).get('componentRect') == '200,100,75,25' and
          f is not None and all(cerca(x, 1.5) for x in razon(f)), (J(r).get('componentRect'), f, r[:300]))
    # ------------------------------------------------------------------ E10
    r = preview(path=FFMX, scale=150, component='Boton')
    f = marco(r)
    check('E10 FMX scale=150 component=Boton: componentRect 16,16,80,22 y la imagen a 1,5',
          J(r).get('componentRect') == '16,16,80,22' and f is not None and all(cerca(x, 1.5) for x in razon(f)),
          (J(r).get('componentRect'), f, r[:300]))
    r = preview(path=FFMX, scale=200)
    f = marco(r)
    check('E10 FMX scale=200: 800x400', f is not None and f[:4] == (800, 400, 400, 200), r[:300])
    r = preview(path=FFMX, scale=150, nonvisual=True, component='Timer1')
    f = marco(r)
    check('E10 FMX scale=150 nonvisual=true component=Timer1: el icono en unidades del fichero (200,100,28,42)',
          J(r).get('componentRect') == '200,100,28,42' and f is not None and all(cerca(x, 1.5) for x in razon(f)),
          (J(r).get('componentRect'), f, r[:300]))
    # ------------------------------------------------------------------ E11
    nota_fmx = str(J(r).get('scaleNote', ''))
    r = preview(path=F96, scale=150)
    nota_vcl = str(J(r).get('scaleNote', ''))
    check('E11 scale y scaleNote (DSGN-191) en la respuesta',
          J(r).get('scale') == 150 and mc.abre(nota_vcl, 'SN_DESIGNER_ESCALA_FMT') and
          mc.abre(nota_fmx, 'SN_DESIGNER_ESCALA_FMT'), (J(r).get('scale'), nota_vcl[:120]))
    check('E11 ...lo de los dibujos nativos, solo en la VCL',
          'native parts' in nota_vcl and 'native parts' not in nota_fmx, (nota_vcl[-200:], nota_fmx[-120:]))
    # ------------------------------------------------------------------ E12
    malos = [(v, preview(path=F96, scale=v)) for v in (99, 501)]
    check('E12 scale fuera de 100..500: DSGN-190',
          all(mc.abre(t, 'SR_DESIGNER_ESCALA_FUERA_FMT') for _, t in malos), [(v, t[:120]) for v, t in malos])
    r = preview(path=F96, scale=-150)
    check('E12 ...y uno negativo ni llega: lo niega el esquema (un entero, minimo 0)',
          mc.abre(r, 'SR_SYS_PARAM_VALUE_FMT') and 'scale' in r, r[:200])
    r = call('delphi_designer', {'command': 'layout', 'path': F96, 'scale': 150})
    check('E12 ...y scale con layout: DSGN-047', mc.abre(r, 'SR_DESIGNER_NO_VA_CON_COMANDO_FMT'), r[:300])
    # ------------------------------------------------------------------ E13 (al final: escribe en los forms)
    def bloque(ruta, nombre):
        t = open(ruta, encoding='ascii').read()
        m = re.search(r'\n  object %s: \w+\r?\n(.*?)\n  end' % nombre, t, re.S)
        return dict(re.findall(r'^\s+([\w.]+) = (.*?)\r?$', m.group(1), re.M)) if m else {}
    r = call('delphi_designer', {'command': 'insert', 'path': F120, 'classname': 'TButton'}, t=180)
    b = bloque(F120, 'Button1')
    check('E13 insert en un .dfm a 120 PPI: 94x31 y Margins 4 (los del constructor, escalados como al soltarlo), '
          'en 10,10. ROJO contra 2c790b84',
          b.get('Width') == '94' and b.get('Height') == '31' and b.get('Left') == '10' and b.get('Top') == '10'
          and all(b.get('Margins.' + l) == '4' for l in ('Left', 'Top', 'Right', 'Bottom')), (b, r[:300]))
    r = call('delphi_designer', {'command': 'insert', 'path': F96, 'classname': 'TButton'}, t=180)
    b = bloque(F96, 'Button1')
    check('E13b control: a 96, 75x25 y sin Margins, como siempre',
          b.get('Width') == '75' and b.get('Height') == '25' and not any(k.startswith('Margins') for k in b),
          (b, r[:300]))
    r = call('delphi_designer', {'command': 'set', 'path': F120, 'component': 'OKBtn', 'prop': 'Caption',
                                 'value': "'Vale'"}, t=180)
    b = bloque(F120, 'OKBtn')
    check('E13c control: set de otra propiedad en uno que ya estaba no lo vuelve a escalar (94x31, sin Margins)',
          b.get('Caption') == "'Vale'" and b.get('Width') == '94' and b.get('Height') == '31'
          and not any(k.startswith('Margins') for k in b), (b, r[:300]))
    r = call('delphi_designer', {'command': 'insert', 'path': F120, 'classname': 'TButton', 'props': 'Width=200'}, t=180)
    b = bloque(F120, 'Button2')
    check('E13d insert con props Width=200 a 120 PPI: el Width del agente tal cual (200, no 250); alto y margenes '
          'escalados (31, 4)',
          b.get('Width') == '200' and b.get('Height') == '31' and b.get('Margins.Left') == '4', (b, r[:300]))
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('preview a otra escala (1.29, C2)')
