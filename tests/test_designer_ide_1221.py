# -*- coding: utf-8 -*-
"""delphi_designer insert y set escriben las propiedades como las guarda el
escritor del IDE (1.22.1; David: "el juez da tambien el orden").

Medido el 22-oct-2026 con el renderizador en --writeback (el TWriter del IDE):
insert en VCL no escribia Width/Height (el IDE guarda el tamano del
constructor), set ponia la propiedad nueva ARRIBA del bloque (el IDE la escribe
en el orden de su RTTI), un Size.Width en FMX salia sin el Size.Height y el
Size.PlatformDefault = False que anade el IDE, un Font.Style sin las Font.* ni
el ParentFont = False, y un valor que ya da la clase se escribia (el IDE no lo
guarda).

  I1 insert VCL TButton: Width y Height en el bloque, en el orden del IDE
  I2 ...y layout no lo da por sin tamano (sizeNotWritten)
  S1 set Hint de un boton con OnClick: Hint en su sitio (tras Height, antes de
     Caption) y el OnClick se queda, tras TabOrder
  S2 set Visible=True (el valor de la clase): DSGN-165 en notStored, sin linea
  S3 set Font.Style de un TMemo: las Font.* y ParentFont = False, como el IDE
  S4 FMX set Size.Width: Size.Height y Size.PlatformDefault = False
  S5 set Left de un TStatusBar (Align = alBottom): se escribe el que guarda el
     IDE, el que da su alineacion, y la respuesta lo dice (storedAs, DSGN-166;
     decia el valor dado mientras el fichero llevaria otro)
  G1 guarda: una referencia a un componente de otro modulo (FocusControl =
     Otro.Edit1) no se pierde al poner otra propiedad del mismo componente
  G2 guarda: set en la raiz (Color del form) como siempre, sin ideNote
  G3 guarda: insert FMX = lo que guarda el IDE (sin Size), sin ideNote
  S6 FMX set Width (stored False en su clase: su valor va en Size): ni notStored ni
     linea 0 - storedIn con el Size.Width que escribe el IDE, DSGN-167, y su linea
     (completo de Opus de la 1.22.1: decia DSGN-165, "el valor de la clase", con
     Size.Width = 120 escrito)

Uso:  python tests/test_designer_ide_1221.py [ruta-a-DelphiLspMcp.exe]
"""
import glob
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer_ide_1221')
JAIL = os.path.join(BASE, 'jail')
VCL = os.path.join(JAIL, 'vcl')
FMX = os.path.join(JAIL, 'fmx')
for c in (VCL, FMX):
    os.makedirs(c)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)

s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='designer-ide-1221', t=300)


def d(**kw):
    return s.call('delphi_designer', kw, t=300)


def props(fichero, nombre):
    """Las propiedades del nivel propio del bloque de nombre, en el orden del fichero."""
    dentro, sangria, res = False, None, []
    for l in mc.lee(fichero).splitlines():
        t = l.strip()
        if not dentro:
            if t.startswith('object ' + nombre + ':'):
                dentro, sangria = True, len(l) - len(l.lstrip()) + 2
            continue
        if t.startswith(('object ', 'inherited ', 'inline ')) or t == 'end':
            break
        if len(l) - len(l.lstrip()) == sangria and ' = ' in t:
            res.append(t.split(' = ')[0])
    return res


try:
    listas = mc.espera_tablas(lambda tool, args, t=120: s.call(tool, args, t=t))
    check('fixture: las tablas del disenador estan listas',
          all(mc.tabla_lista(r) for _, r in listas), str(listas)[:300])
    s.call('delphi_create', {'kind': 'project-vcl', 'name': 'Ide', 'dir': VCL})
    DFM = os.path.join(VCL, 'UMain.dfm')
    PAS = os.path.join(VCL, 'UMain.pas')

    r = d(command='insert', path=DFM, classname='TButton', component='BtnUno')
    p = props(DFM, 'BtnUno')
    check('I1 insert VCL TButton: Width y Height del constructor, en el orden del IDE',
          not mc.fallo(r) and p == ['Left', 'Top', 'Width', 'Height', 'Caption', 'TabOrder']
          and 'Width = 75' in mc.lee(DFM) and 'Height = 25' in mc.lee(DFM)
          and 'ideNote' not in (mc.como_json(r) or {}), (p, r[:400]))
    r = d(command='layout', path=DFM)
    check('I2 ...y layout no lo da por sin tamano', 'BtnUno' not in str((mc.como_json(r) or {}).get('sizeNotWritten')),
          r[:400])

    s.call('delphi_edit', {'path': DFM, 'old': 'TabOrder = 0', 'new': '    TabOrder = 0\n    OnClick = BtnUnoClick'})
    s.call('delphi_edit', {'path': PAS, 'insert': 'metodo', 'inclass': 'TFormMain', 'visibility': 'published',
                           'code': 'procedure BtnUnoClick(Sender: TObject);\nbegin\nend;'})
    check('fixture: el OnClick esta en el form y su metodo en la unidad',
          'OnClick = BtnUnoClick' in mc.lee(DFM) and 'BtnUnoClick' in mc.lee(PAS), mc.lee(DFM)[-300:])
    r = d(command='set', path=DFM, component='BtnUno', prop='Hint', value="'Ayuda'")
    p = props(DFM, 'BtnUno')
    check('S1 set Hint de un boton con OnClick: Hint en su sitio y el OnClick se queda, tras TabOrder',
          not mc.fallo(r) and p == ['Left', 'Top', 'Width', 'Height', 'Hint', 'Caption', 'TabOrder', 'OnClick']
          and 'OnClick = BtnUnoClick' in mc.lee(DFM), (p, r[:400]))

    r = d(command='set', path=DFM, component='BtnUno', prop='Visible', value='True')
    p = props(DFM, 'BtnUno')
    check('S2 set Visible=True, el valor de la clase: DSGN-165 en notStored y sin linea',
          not mc.fallo(r) and 'Visible' not in p
          and mc.es(str((mc.como_json(r) or {}).get('notStored')), 'SN_DESIGNER_IDE_NO_GUARDA_FMT'), (p, r[:400]))

    d(command='insert', path=DFM, classname='TMemo', component='MemoUno')
    r = d(command='set', path=DFM, component='MemoUno', prop='Font.Style', value='[fsBold]')
    p = props(DFM, 'MemoUno')
    check('S3 set Font.Style de un TMemo: las Font.* y ParentFont = False, como el IDE',
          not mc.fallo(r) and {'Font.Charset', 'Font.Color', 'Font.Height', 'Font.Name', 'Font.Style',
                               'ParentFont'} <= set(p)
          and p.index('Font.Style') < p.index('ParentFont'), (p, r[:400]))

    d(command='insert', path=DFM, classname='TLabel', component='LblUno')
    s.call('delphi_edit', {'path': DFM, 'old': "Caption = 'LblUno'",
                           'new': "    Caption = 'LblUno'\n    FocusControl = Otro.Edit1"})
    check('fixture: la etiqueta con una referencia a otro modulo', 'FocusControl = Otro.Edit1' in mc.lee(DFM),
          mc.lee(DFM)[-400:])
    r = d(command='set', path=DFM, component='LblUno', prop='Hint', value="'Pista'")
    check('G1 guarda: la referencia a otro modulo no se pierde al poner otra propiedad',
          not mc.fallo(r) and 'FocusControl = Otro.Edit1' in mc.lee(DFM) and 'FocusControl' not in
          str((mc.como_json(r) or {}).get('notStored')), (props(DFM, 'LblUno'), r[:400]))

    d(command='insert', path=DFM, classname='TStatusBar', component='SbUno')
    r = d(command='set', path=DFM, component='SbUno', prop='Left', value='20')
    j = mc.como_json(r) or {}
    check('S5 set Left de un TStatusBar alineado: el del IDE (0) escrito, y storedAs con DSGN-166',
          not mc.fallo(r) and j.get('storedAs') == '0' and mc.es(j.get('storedNote', ''), 'SN_DESIGNER_IDE_GUARDA_OTRO_FMT')
          and '    Left = 20\r\n' not in mc.lee(DFM), (props(DFM, 'SbUno'), r[:400]))
    # (el 20 lo guarda el IDE como ExplicitLeft, lo de antes de alinear: su
    # DefineProperties, detras de las publicadas)
    check('S5 ...y el 20 queda como ExplicitLeft, detras de las publicadas, como el IDE',
          '    ExplicitLeft = 20\r\n' in mc.lee(DFM) and props(DFM, 'SbUno')[-1] == 'ExplicitLeft', props(DFM, 'SbUno'))

    r = d(command='set', path=DFM, component='FormMain', prop='Color', value='clRed')
    check('G2 guarda: set en la raiz como siempre, sin ideNote',
          not mc.fallo(r) and 'Color = clRed' in mc.lee(DFM) and 'ideNote' not in (mc.como_json(r) or {}), r[:300])

    s.call('delphi_create', {'kind': 'project-fmx', 'name': 'Fm', 'dir': FMX})
    FMXF = (glob.glob(os.path.join(FMX, '*.fmx')) or [''])[0]
    r = d(command='insert', path=FMXF, classname='TButton', component='BtnF')
    p = props(FMXF, 'BtnF')
    check('G3 guarda: insert FMX como lo guarda el IDE, sin Size y sin ideNote',
          not mc.fallo(r) and p and not any(x.startswith('Size.') for x in p)
          and 'ideNote' not in (mc.como_json(r) or {}), (p, r[:400]))
    r = d(command='set', path=FMXF, component='BtnF', prop='Size.Width', value='100')
    p = props(FMXF, 'BtnF')
    check('S4 FMX set Size.Width: Size.Height y Size.PlatformDefault = False, como el IDE',
          not mc.fallo(r) and {'Size.Width', 'Size.Height', 'Size.PlatformDefault'} <= set(p)
          and 'Size.PlatformDefault = False' in mc.lee(FMXF), (p, r[:400]))
    r = d(command='set', path=FMXF, component='BtnF', prop='Width', value='120')
    j = mc.como_json(r) or {}
    check('S6 FMX set Width (stored False): ni notStored ni linea 0, storedIn con Size.Width = 120 y DSGN-167',
          not mc.fallo(r) and 'notStored' not in j and 'Size.Width = 120' in str(j.get('storedIn'))
          and mc.tiene(r, 'DSGN-167') and (j.get('line') or 0) > 0, r[:500])
    check('S6 ...y el fichero lleva el Size.Width que guarda el IDE',
          'Size.Width = 120.000000000000000000' in mc.lee(FMXF), mc.lee(FMXF)[-400:])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('designer como lo guarda el IDE 1.22.1')
