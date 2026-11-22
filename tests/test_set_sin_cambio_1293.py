# -*- coding: utf-8 -*-
"""delphi_designer set que no cambia ningun valor pedido no escribe el
fichero, y lo que reescribe la CARGA del form va aparte de lo que cambia el
setter (D28 de la 1.29.3).

Medido en campo el 18-nov-2026 (Hermes, en un proyecto FMX): set HitTest=False en un
TLabel y en un TLayout, que ya lo eran (DSGN-165), reescribio TabOrder 5->4 y
Size.Height 228->424, con DSGN-189 diciendo que lo hacia el componente al
poner la propiedad; el agente lo llamo "residuo cosmetico" y lo deshizo a mano
(restore + stash). Medido en test-mcp-server (MideD28): un set de Opacity, que
no toca el tamano, reescribe el mismo Size.Height viejo del Client: lo trae la
carga (el form realinea), no el setter.

  N1 set de una que no cambia nada (HitTest=False en un TLayout, el valor de su
     clase) en un form con el Size.Height de su Client viejo: el fichero, byte a
     byte, como estaba; la nota de nada escrito (DSGN-202) y el notStored de
     DSGN-165; sin alsoWritten ni loadWritten
  N2 ...y sin copia en la papelera (no se escribio)
  N3 set de varias que no cambia nada (HitTest=False y el Text que ya tiene, en
     un TLabel con TabOrder con huecos): el fichero como estaba, DSGN-202
  N4 set de una que cambia (Opacity=0.5 en el Client): se escribe, y el
     Size.Height que recalcula la carga va en loadWritten con DSGN-203, no en
     alsoWritten
  N5 control (I30): el StyledSettings que FMX quita al poner un FontColor va en
     alsoWritten con DSGN-189, no en loadWritten
  N6 control: set de varias con una que cambia y otra que no: se escribe, sin
     DSGN-202

Uso:  python tests/test_set_sin_cambio_1293.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('set_sin_cambio_1293')
JAIL = os.path.join(BASE, 'jail')
FMX = os.path.join(JAIL, 'fmx')
os.makedirs(FMX)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)

s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='set-sin-cambio-1293', t=300)


def d(**kw):
    return s.call('delphi_designer', kw, t=300)


def bytes_de(ruta):
    with open(ruta, 'rb') as f:
        return f.read()


def escribe(ruta, texto):
    with open(ruta, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(texto.replace('\n', '\r\n'))


def en_papelera(carpeta, nombre):
    """True si la papelera de carpeta (mc.PAPELERA) guarda una copia de nombre."""
    for _, _, ficheros in os.walk(os.path.join(carpeta, mc.PAPELERA)):
        if nombre in ficheros:
            return True
    return False


def lineas(j, campo):
    return [str(x) for x in (j.get(campo) or [])]


MAIN_PAS = '''unit UMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Layouts,
  FMX.StdCtrls, FMX.Edit, FMX.Controls.Presentation;

type
  TFormMain = class(TForm)
    lytCab: TLayout;
    lytBarra: TLayout;
    lytPie: TLayout;
    pnlEditor: TPanel;
    lblAntet: TLabel;
    edtBusca: TEdit;
    lblPista: TLabel;
    lytTrabajo: TLayout;
  private
  public
  end;

var
  FormMain: TFormMain;

implementation

{$R *.fmx}

end.
'''
# lo que dejaria un form editado fuera del disenador: el Client con la altura
# de antes (228; carga con 354) y los TabOrder del panel con huecos (2, 4, 5)
MAIN_FMX = '''object FormMain: TFormMain
  Left = 0
  Top = 0
  Caption = 'FormMain'
  ClientHeight = 480
  ClientWidth = 640
  FormFactor.Width = 320
  FormFactor.Height = 480
  FormFactor.Devices = [Desktop]
  DesignerMasterStyle = 0
  object lytCab: TLayout
    Align = Top
    Size.Width = 640.000000000000000000
    Size.Height = 42.000000000000000000
    Size.PlatformDefault = False
    TabOrder = 0
  end
  object lytBarra: TLayout
    Align = Top
    Position.Y = 42.000000000000000000
    Size.Width = 640.000000000000000000
    Size.Height = 42.000000000000000000
    Size.PlatformDefault = False
    TabOrder = 1
  end
  object lytPie: TLayout
    Align = Bottom
    Position.Y = 438.000000000000000000
    Size.Width = 640.000000000000000000
    Size.Height = 42.000000000000000000
    Size.PlatformDefault = False
    TabOrder = 2
  end
  object pnlEditor: TPanel
    Align = Left
    Position.Y = 84.000000000000000000
    Size.Width = 120.000000000000000000
    Size.Height = 354.000000000000000000
    Size.PlatformDefault = False
    TabOrder = 3
    object lblAntet: TLabel
      Position.X = 10.000000000000000000
      Position.Y = 10.000000000000000000
      Text = 'lblAntet'
      TabOrder = 2
    end
    object edtBusca: TEdit
      Touch.InteractiveGestures = [LongTap, DoubleTap]
      TabOrder = 4
      Position.X = 10.000000000000000000
      Position.Y = 10.000000000000000000
    end
    object lblPista: TLabel
      Position.X = 10.000000000000000000
      Position.Y = 10.000000000000000000
      Text = 'lblPista'
      TabOrder = 5
    end
  end
  object lytTrabajo: TLayout
    Align = Client
    Size.Width = 520.000000000000000000
    Size.Height = 228.000000000000000000
    Size.PlatformDefault = False
    TabOrder = 4
  end
end
'''

try:
    listas = mc.espera_tablas(lambda tool, args, t=120: s.call(tool, args, t=t))
    check('fixture: las tablas del disenador estan listas',
          all(mc.tabla_lista(r) for _, r in listas), str(listas)[:300])
    s.call('delphi_create', {'kind': 'project-fmx', 'name': 'D28', 'dir': FMX})
    F = os.path.join(FMX, 'UMain.fmx')
    escribe(os.path.join(FMX, 'UMain.pas'), MAIN_PAS)
    escribe(F, MAIN_FMX)
    antes = bytes_de(F)
    check('fixture: el form con el Client viejo y sin copia en la papelera',
          b'228.000000000000000000' in antes and not en_papelera(FMX, 'UMain.fmx'), mc.lee(F)[:200])

    r = d(command='set', path=F, component='lytTrabajo', prop='HitTest', value='False')
    j = mc.como_json(r) or {}
    check('N1 set de una que no cambia nada: el fichero como estaba, DSGN-202 y DSGN-165, sin also/load',
          not mc.fallo(r) and bytes_de(F) == antes and mc.es(str(j.get('note', '')), 'SN_DESIGNER_NADA_CAMBIA_FMT')
          and mc.es(str(j.get('notStored', '')), 'SN_DESIGNER_IDE_NO_GUARDA_FMT')
          and 'alsoWritten' not in j and 'loadWritten' not in j, r[:700])
    check('N2 ...y sin copia en la papelera (no se escribio)',
          not en_papelera(FMX, 'UMain.fmx') and not mc.es(r, 'SN_COPIAS_DE_LA_LLAMADA_FMT'), r[:300])

    # cada caso desde el fixture: un N1 que escribiera dejaria el 228 corregido y N3/N4
    # pasarian o fallarian por el caso de antes, no por el suyo
    escribe(F, MAIN_FMX)
    r = d(command='set', path=F, component='lblPista', props="HitTest=False;Text='lblPista'")
    j = mc.como_json(r) or {}
    check('N3 set de varias que no cambia nada: el fichero como estaba, DSGN-202',
          not mc.fallo(r) and bytes_de(F) == antes and mc.es(str(j.get('note', '')), 'SN_DESIGNER_NADA_CAMBIA_FMT')
          and 'alsoWritten' not in j and 'loadWritten' not in j, r[:700])

    escribe(F, MAIN_FMX)
    r = d(command='set', path=F, component='lytTrabajo', prop='Opacity', value='0.5')
    j = mc.como_json(r) or {}
    texto = mc.lee(F)
    check('N4 set que cambia: escrito, y el Size.Height de la carga en loadWritten con DSGN-203, no en alsoWritten',
          not mc.fallo(r) and 'Opacity = 0.5' in texto
          and any(x.startswith('Size.Height = ') for x in lineas(j, 'loadWritten'))
          and not any(x.startswith('Size.Height = ') for x in lineas(j, 'alsoWritten'))
          and mc.es(str(j.get('loadNote', '')), 'SN_DESIGNER_CARGA_TAMBIEN_ESCRIBE_FMT'), r[:700])

    r = d(command='set', path=F, component='lblPista', prop='TextSettings.FontColor', value='claRed')
    j = mc.como_json(r) or {}
    check('N5 control (I30): el StyledSettings del setter en alsoWritten con DSGN-189, no en loadWritten',
          not mc.fallo(r) and any(x.startswith('StyledSettings = ') for x in lineas(j, 'alsoWritten'))
          and not any(x.startswith('StyledSettings = ') for x in lineas(j, 'loadWritten'))
          and mc.es(str(j.get('alsoNote', '')), 'SN_DESIGNER_IDE_TAMBIEN_ESCRIBE_FMT'), r[:700])

    antes = bytes_de(F)
    r = d(command='set', path=F, component='edtBusca', props="HitTest=True;Text='hola'")
    j = mc.como_json(r) or {}
    check('N6 control: set de varias con una que cambia y otra que no: escrito, sin DSGN-202',
          not mc.fallo(r) and bytes_de(F) != antes and "Text = 'hola'" in mc.lee(F)
          and not mc.es(r, 'SN_DESIGNER_NADA_CAMBIA_FMT'), r[:700])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('designer set que no cambia nada no escribe; lo de la carga aparte 1.29.3 (D28)')
