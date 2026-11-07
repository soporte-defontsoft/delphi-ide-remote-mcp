# -*- coding: utf-8 -*-
"""1.29 (A2+A18): un frame puesto en linea en un form ANCESTRO. En la heredada, el IDE lo escribe inherited
(inherited Frame11: TFrame1 con inherited Edit1 dentro: TWriter, medido el 7-nov-2026), y el disenador solo
reconocia un frame por la palabra 'inline': Frame11.Edit1 daba DSGN-078 con su bloque ahi (A2), y sin bloque
get/set de Frame11 o de Frame11.Edit1 tambien (A18: HeredadoSegunElIde se salia ante un frame). Ahora cuales de
sus inherited son frames lo dice el lector del IDE (el form entero que escribe lleva inline) y lo pregunta UN
predicado (TStyleObj.EsFrameIncrustado).

  FormMain: inline Frame11 (su Edit1 sin tocar) y un Button1
  FormB hereda: inherited Frame11 > inherited Edit1 (Text = 'Hola')
  FormC hereda: sin ningun bloque

  H1 FormB get Frame11.Edit1: su bloque. ROJO contra 37e32724
  H2 FormB get Edit1 a secas: no es del form (lo de dentro de un frame va por su ruta), como en FormMain. ROJO
  H3 FormB set Frame11.Edit1 Text: en su bloque. ROJO
  H4 FormC get Frame11: llega del ancestro (DSGN-172). ROJO
  H5 FormC get Frame11.Edit1: llega de su frame (DSGN-172). ROJO
  H6 FormC set Frame11.Edit1 Text: escribe inherited Frame11 > inherited Edit1 con el Text (DSGN-171). ROJO
  H7 ...y el lector del IDE carga lo escrito (lint limpio)
  H8 control: en FormMain get y set de Frame11.Edit1, como antes
  H9 control: FormC get Button1, un heredado normal (DSGN-172), como antes

Uso:  python tests/test_frame_heredado_129.py [ruta-a-DelphiLspMcp.exe]
"""
import io
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('frame_heredado_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True, con_conversor=True)
JAIL = os.path.join(BASE, 'jail')
P = os.path.join(JAIL, 'PFH')
os.makedirs(P)

USES_VCL = ('  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,\n'
            '  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs')


def escribe(nombre, texto):
    # como los guarda el IDE: UTF-8 con BOM y CRLF
    io.open(os.path.join(P, nombre), 'w', encoding='utf-8-sig', newline='\r\n').write(texto)


def unidad(nombre, clase, ancestro, campos, usos=''):
    escribe(nombre + '.pas', 'unit %s;\n\ninterface\n\nuses\n%s%s;\n\ntype\n  %s = class(%s)\n%s  private\n  public\n'
            '  end;\n\nvar\n  %s: %s;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n'
            % (nombre, USES_VCL, usos, clase, ancestro, campos, clase[1:], clase))


escribe('UFrame1.pas', 'unit UFrame1;\n\ninterface\n\nuses\n%s,\n  Vcl.StdCtrls;\n\ntype\n  TFrame1 = class(TFrame)\n'
        '    Edit1: TEdit;\n  private\n  public\n  end;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n' % USES_VCL)
escribe('UFrame1.dfm', "object Frame1: TFrame1\n  Left = 0\n  Top = 0\n  Width = 320\n  Height = 240\n  TabOrder = 0\n"
        "  object Edit1: TEdit\n    Left = 10\n    Top = 10\n    Width = 121\n    Height = 23\n    TabOrder = 0\n"
        "    Text = 'Edit1'\n  end\nend\n")
unidad('UMain', 'TFormMain', 'TForm', '    Frame11: TFrame1;\n    Button1: TButton;\n', ', UFrame1, Vcl.StdCtrls')
escribe('UMain.dfm', "object FormMain: TFormMain\n  Left = 0\n  Top = 0\n  Caption = 'FormMain'\n  ClientHeight = 420\n"
        "  ClientWidth = 620\n  Color = clBtnFace\n  Font.Charset = DEFAULT_CHARSET\n  Font.Color = clWindowText\n"
        "  Font.Height = -12\n  Font.Name = 'Segoe UI'\n  Font.Style = []\n  TextHeight = 15\n"
        "  inline Frame11: TFrame1\n    Left = 10\n    Top = 10\n    TabOrder = 0\n  end\n"
        "  object Button1: TButton\n    Left = 10\n    Top = 300\n    Width = 75\n    Height = 25\n"
        "    Caption = 'Button1'\n    TabOrder = 1\n  end\nend\n")
unidad('UFormB', 'TFormB', 'TFormMain', '', ', UMain')
escribe('UFormB.dfm', "inherited FormB: TFormB\n  Caption = 'FormB'\n  inherited Frame11: TFrame1\n"
        "    inherited Edit1: TEdit\n      Text = 'Hola'\n    end\n  end\nend\n")
unidad('UFormC', 'TFormC', 'TFormMain', '', ', UMain')
escribe('UFormC.dfm', "inherited FormC: TFormC\n  Caption = 'FormC'\nend\n")
escribe('PFH.dpr', "program PFH;\n\nuses\n  Vcl.Forms,\n  UFrame1 in 'UFrame1.pas' {Frame1: TFrame},\n"
        "  UMain in 'UMain.pas' {FormMain},\n  UFormB in 'UFormB.pas' {FormB},\n  UFormC in 'UFormC.pas' {FormC};\n\n"
        "{$R *.res}\n\nbegin\n  Application.Initialize;\n  Application.CreateForm(TFormMain, FormMain);\n  Application.Run;\nend.\n")
MAIN, FB, FC = (os.path.join(P, n) for n in ('UMain.dfm', 'UFormB.dfm', 'UFormC.dfm'))

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='frameher', t=120)


def d(args):
    return srv.call('delphi_designer', args)


def lineas(f):
    return [l.strip() for l in mc.lee(f).splitlines()]


def dentro(f, *seguidas):
    """Las lineas dadas, en ese orden y seguidas, en el fichero f (sin sangria)."""
    L = lineas(f)
    for i in range(len(L) - len(seguidas) + 1):
        if L[i:i + len(seguidas)] == list(seguidas):
            return True
    return False


try:
    r = d({'command': 'get', 'path': FB, 'component': 'Frame11.Edit1'})
    check('H1 FormB get Frame11.Edit1: su bloque. ROJO contra 37e32724',
          not mc.fallo(r) and 'inherited Edit1: TEdit' in r and "Text = 'Hola'" in r, r[:400])
    r = d({'command': 'get', 'path': FB, 'component': 'Edit1'})
    check('H2 FormB get Edit1 a secas: no es del form, va por su ruta. ROJO',
          mc.abre(r, 'SR_DESIGNER_COMPONENTE_NO_ESTA_FMT') and 'Frame11.' in r, r[:400])
    r = d({'command': 'set', 'path': FB, 'component': 'Frame11.Edit1', 'prop': 'Text', 'value': 'Adios'})
    check('H3 FormB set Frame11.Edit1 Text: en su bloque. ROJO',
          not mc.fallo(r) and dentro(FB, 'inherited Frame11: TFrame1', 'inherited Edit1: TEdit', "Text = 'Adios'"),
          (r[:300], mc.lee(FB)))
    r = d({'command': 'get', 'path': FC, 'component': 'Frame11'})
    check('H4 FormC get Frame11: llega del ancestro (DSGN-172). ROJO',
          not mc.fallo(r) and mc.es(r, 'SN_DESIGNER_HEREDADO_SIN_BLOQUE_FMT') and 'TFrame1' in r, r[:400])
    r = d({'command': 'get', 'path': FC, 'component': 'Frame11.Edit1'})
    check('H5 FormC get Frame11.Edit1: llega de su frame (DSGN-172). ROJO',
          not mc.fallo(r) and mc.es(r, 'SN_DESIGNER_HEREDADO_SIN_BLOQUE_FMT') and 'TEdit' in r, r[:400])
    r = d({'command': 'set', 'path': FC, 'component': 'Frame11.Edit1', 'prop': 'Text', 'value': 'Desde C'})
    check('H6 FormC set Frame11.Edit1 Text: inherited Frame11 > inherited Edit1 (DSGN-171). ROJO',
          not mc.fallo(r) and mc.es(r, 'SN_DESIGNER_BLOQUES_HEREDADOS_FMT') and
          dentro(FC, 'inherited Frame11: TFrame1', 'inherited Edit1: TEdit', "Text = 'Desde C'"),
          (r[:300], mc.lee(FC)))
    r = d({'command': 'lint', 'path': FC})
    check('H7 ...y el lector del IDE carga lo escrito (lint limpio)', mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:400])
    r = d({'command': 'get', 'path': MAIN, 'component': 'Frame11.Edit1'})
    r2 = d({'command': 'set', 'path': MAIN, 'component': 'Frame11.Edit1', 'prop': 'Text', 'value': 'Desde main'})
    check('H8 control: en FormMain (inline) get y set de Frame11.Edit1, como antes',
          mc.es(r, 'SN_DESIGNER_HEREDADO_SIN_BLOQUE_FMT') and not mc.fallo(r2) and
          dentro(MAIN, 'inline Frame11: TFrame1', 'Left = 10', 'Top = 10', 'TabOrder = 0', 'inherited Edit1: TEdit',
                 "Text = 'Desde main'"), (r[:200], r2[:200], mc.lee(MAIN)))
    r = d({'command': 'get', 'path': FC, 'component': 'Button1'})
    check('H9 control: FormC get Button1, un heredado normal (DSGN-172), como antes',
          not mc.fallo(r) and mc.es(r, 'SN_DESIGNER_HEREDADO_SIN_BLOQUE_FMT') and 'TButton' in r, r[:400])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('frame puesto en un ancestro, en la heredada (1.29, A2+A18)')
