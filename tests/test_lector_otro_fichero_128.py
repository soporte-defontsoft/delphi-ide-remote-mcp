# -*- coding: utf-8 -*-
"""C9 de la 1.28: lo que dice el lector del IDE se atribuye al componente del form
SOLO si lo dijo leyendo ESE form (TIgnorada.Fichero), no un frame en linea ni un
ancestro con un componente que se llama igual; y lo que una clase define POR CODIGO
sin escritor (su DefineProperties) no es "el valor que ya da la clase".

Medido en produccion (e331d4c, 5-nov-2026, sandbox C9Lectura):
  - un frame en linea cuyo propio .fmx tiene su Edit1 con FontColor = -65536 (el
    lector no lo carga): set del Edit1 del FORM, FontColor = claRed, escribia DOS
    lineas - TextSettings.FontColor = claRed, la del escritor, y ademas la suya
    FontColor = claRed, porque el salto del frame se tomaba por el del form
    (ConLasPropiedadesDelIde);
  - un ancestro con ese Edit1 roto: set del Edit1 de la HIJA, FontColor = claRed,
    se negaba con DSGN-149 "el lector no carga ESE valor", cuando el que no carga
    es el -65536 del ancestro (CargaLoPuesto); la politica es escribirlo con
    readerNote DSGN-159 (el form ya no cargaba);
  - set Label1.Font.Size = 20 en un TLabel FMX escribe TextSettings.Font.Size = 20
    y contestaba notStored DSGN-165 "es el valor que la clase ya da": FMX define
    Font.Size por codigo, solo para leer, y su lector lo pone en TextSettings.

  O1 frame roto: set del Edit1 del form escribe la linea del escritor y NO la suya
     (ROJO en produccion: las dos)
  O2 ancestro roto: set del Edit1 de la hija no se niega (ROJO en produccion: DSGN-149)
  O3 ...y la respuesta dice que no se juzgo (readerNote DSGN-159)
  O4 guarda: el valor malo en el PROPIO form se sigue negando (DSGN-149): el fichero
     que dice el lector del form propuesto es el form
  O5 Font.Size de un TLabel FMX: storedIn con TextSettings.Font.Size, no notStored
     (ROJO en produccion: DSGN-165)
  O6 FontColor de un TEdit FMX: storedIn con TextSettings.FontColor (ROJO en
     produccion: DSGN-165)
  O7 la nota de O5 dice que su clase solo la lee por codigo, no "stored False"
     (ROJO contra el primer arreglo, c9-lector: lo decia de Font.Size)

Uso:  python tests/test_lector_otro_fichero_128.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('lector_otro_fichero_128')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)

CABECERA = ("  Left = 0\r\n  Top = 0\r\n  Caption = 'F'\r\n  ClientHeight = 480\r\n  ClientWidth = 640\r\n"
            "  FormFactor.Width = 320\r\n  FormFactor.Height = 480\r\n  FormFactor.Devices = [Desktop]\r\n"
            "  DesignerMasterStyle = 0\r\n")
EDIT1 = ("  object Edit1: TEdit\r\n{malo}    Position.X = 10.000000000000000000\r\n"
         "    Position.Y = 10.000000000000000000\r\n    TabOrder = 0\r\n  end\r\n")
MALO = "    FontColor = -65536\r\n"
USES = ("uses\r\n  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,\r\n"
        "  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls, FMX.Edit{mas};\r\n")


def escribe(nombre, ext, texto):
    p = os.path.join(JAIL, nombre + ext)
    open(p, 'wb').write(b'\xef\xbb\xbf' + texto.encode('utf-8'))
    return p


def unidad(nombre, clase, ancestro, campos, mas_uses=''):
    escribe(nombre, '.pas', 'unit %s;\r\n\r\ninterface\r\n\r\n%s\r\ntype\r\n  %s = class(%s)\r\n%s  end;\r\n\r\n'
            'implementation\r\n\r\n{$R *.fmx}\r\n\r\nend.\r\n'
            % (nombre, USES.replace('{mas}', mas_uses), clase, ancestro, campos))


def bloque(p, nombre):
    """Las lineas del objeto Nombre en el form p (de su 'object/inherited' a su 'end')."""
    lineas = open(p, 'rb').read().decode('utf-8-sig').split('\r\n')
    for i, l in enumerate(lineas):
        if l.strip().split(':')[0].split(' ')[-1] == nombre and l.strip().startswith(('object ', 'inherited ')):
            sangria = len(l) - len(l.lstrip())
            for j in range(i + 1, len(lineas)):
                if lineas[j].strip() == 'end' and len(lineas[j]) - len(lineas[j].lstrip()) == sangria:
                    return [x.strip() for x in lineas[i + 1:j]]
    return []


# el frame en linea, con SU Edit1 roto
escribe('UMarcoM', '.fmx', "object FrameM: TFrameM\r\n  Size.Width = 320.000000000000000000\r\n"
        "  Size.Height = 240.000000000000000000\r\n  Size.PlatformDefault = False\r\n" +
        EDIT1.replace('{malo}', MALO) + "end\r\n")
unidad('UMarcoM', 'TFrameM', 'TFrame', '    Edit1: TEdit;\r\n')
PF = escribe('UFormF', '.fmx', "object FormF: TFormF\r\n" + CABECERA + EDIT1.replace('{malo}', '') +
             "  inline Marco1: TFrameM\r\n    Position.X = 10.000000000000000000\r\n"
             "    Position.Y = 60.000000000000000000\r\n    TabOrder = 1\r\n  end\r\nend\r\n")
unidad('UFormF', 'TFormF', 'TForm', '    Edit1: TEdit;\r\n    Marco1: TFrameM;\r\n', ', UMarcoM')

# el ancestro con su Edit1 roto, y la hija que lo hereda
escribe('UBaseB', '.fmx', "object FormB: TFormB\r\n" + CABECERA + EDIT1.replace('{malo}', MALO) + "end\r\n")
unidad('UBaseB', 'TFormB', 'TForm', '    Edit1: TEdit;\r\n')
PH = escribe('UHijaH', '.fmx', "inherited FormH: TFormH\r\n  Caption = 'H'\r\n  inherited Edit1: TEdit\r\n"
             "    Position.X = 20.000000000000000000\r\n  end\r\nend\r\n")
unidad('UHijaH', 'TFormH', 'TFormB', '', ', UBaseB')

# un form sano, con un TLabel
PG = escribe('UFormG', '.fmx', "object FormG: TFormG\r\n" + CABECERA + EDIT1.replace('{malo}', '') +
             "  object Label1: TLabel\r\n    Position.X = 10.000000000000000000\r\n"
             "    Position.Y = 60.000000000000000000\r\n    Text = 'Label1'\r\n    TabOrder = 1\r\n  end\r\nend\r\n")
unidad('UFormG', 'TFormG', 'TForm', '    Edit1: TEdit;\r\n    Label1: TLabel;\r\n')


def setp(p, comp, prop, valor):
    return srv.call('delphi_designer', {'path': p, 'command': 'set', 'component': comp, 'prop': prop,
                                        'value': valor}, t=240)


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='lector-otro-fichero', t=240)
try:
    r = setp(PF, 'Edit1', 'FontColor', 'claRed')
    b = bloque(PF, 'Edit1')
    check('O1 frame roto: set del Edit1 del form escribe TextSettings.FontColor y NO su FontColor = claRed',
          not mc.fallo(r) and 'TextSettings.FontColor = claRed' in b and 'FontColor = claRed' not in b,
          (r[:300], b))

    antes = open(PH, 'rb').read()
    r = setp(PH, 'Edit1', 'FontColor', 'claRed')
    check('O2 ancestro roto: set del Edit1 de la hija no se niega por el valor del ancestro (DSGN-149)',
          not mc.rechazado(r) and not mc.es(r, 'SR_DESIGNER_SET_NO_CARGA_FMT') and open(PH, 'rb').read() != antes,
          r[:400])
    nota = mc.como_json(r).get('readerNote') or ''
    check('O3 ...y la respuesta dice que Edit1.FontColor = claRed no se juzgo (readerNote DSGN-159)',
          mc.abre(nota, 'SN_DESIGNER_SET_SIN_JUZGAR_FMT') and 'Edit1.FontColor = claRed' in nota, r[:400])

    antes = open(PG, 'rb').read()
    r = setp(PG, 'Edit1', 'FontColor', '-65536')
    check('O4 guarda: el valor malo en el PROPIO form se sigue negando (DSGN-149) y el form queda igual',
          mc.abre(r, 'SR_DESIGNER_SET_NO_CARGA_FMT') and open(PG, 'rb').read() == antes, r[:300])

    r = setp(PG, 'Label1', 'Font.Size', '20')
    j = mc.como_json(r)
    check('O5 Font.Size de un TLabel FMX (por codigo): storedIn con TextSettings.Font.Size, no notStored',
          'TextSettings.Font.Size = 20' in (j.get('storedIn') or '') and not j.get('notStored') and
          any(x.startswith('TextSettings.Font.Size = 20') for x in bloque(PG, 'Label1')), r[:400])
    nota = j.get('storedNote') or ''
    check('O7 ...y su nota dice que la clase solo la LEE por codigo, no que la declare stored False (DSGN-167)',
          mc.abre(nota, 'SN_DESIGNER_IDE_GUARDA_EN_OTRAS_FMT') and
          mc.catalogo()['SF_DESIGNER_IDE_SOLO_SE_LEE'] in nota and
          mc.catalogo()['SF_DESIGNER_IDE_STORED_FALSE'] not in nota, nota)

    r = setp(PG, 'Edit1', 'FontColor', 'claBlue')
    j = mc.como_json(r)
    check('O6 FontColor de un TEdit FMX (por codigo): storedIn con TextSettings.FontColor, no notStored',
          'TextSettings.FontColor = claBlue' in (j.get('storedIn') or '') and not j.get('notStored') and
          'TextSettings.FontColor = claBlue' in bloque(PG, 'Edit1') and 'FontColor = claBlue' not in bloque(PG, 'Edit1'),
          r[:400])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('lo que dice el lector, del fichero que leia; lo definido por codigo, donde quedo (C9 de la 1.28)')
