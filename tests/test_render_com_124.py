# -*- coding: utf-8 -*-
"""V65 de la 1.24: el ayudante del render corre en un contenedor, y de 5181 clases
COM de 32 bits hay 4 cuya clave InprocServer32 un contenedor no lee, las de ADO
(Command, Parameter, Recordset, Error; Connection si). CoCreateInstance respondia
acceso denegado: TADOQuery no se creaba, salia en IGNORED= y el juez del orden no
juzgaba ese form (DSGN-143). Su biblioteca si se lee, asi que la caja de paquetes
le da esas clases en el manifiesto de su copia del ayudante. Que clases, lo dice el
contenedor; este juego solo vale aqui mientras Windows las deje asi, y C0 lo mira.

  C0    la premisa, medida: el ayudante en su contenedor ve esas clases sin leer
  C1-C2 VCL: un form con ADO carga entero y el juez lo reordena
  C3    FMX: lo mismo al cargar
  C4    el ayudante original no se toca: el manifiesto es de la copia de la caja

ROJO contra un build sin el arreglo: C1, C2 y C3.

Uso:  python tests/test_render_com_124.py [ruta-a-DelphiLspMcp.exe]
"""
import ctypes
import json
import os
import subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('render_com_124')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
AYUDANTES = [os.path.join(os.path.dirname(EXE), n) for n in ('DelphiFormRenderVcl.exe', 'DelphiFormRenderFmx.exe')]


def escribe(nombre, texto):
    ruta = os.path.join(JAIL, nombre)
    open(ruta, 'wb').write(texto.replace('\n', '\r\n').encode('ascii'))
    return ruta


def pas(unidad, clase, usos, campos):
    return ('unit %s;\n\ninterface\n\nuses\n  %s;\n\ntype\n  %s = class(TForm)\n%s  end;\n\n'
            'implementation\n\n{$R *.%s}\n\nend.\n' % (unidad, usos, clase, campos, 'fmx' if 'FMX' in usos else 'dfm'))


CAMPOS = ('    Boton: TButton;\n    Otro: TButton;\n    Conn: TADOConnection;\n    Query: TADOQuery;\n'
          '    Tabla: TADOTable;\n    Comando: TADOCommand;\n')
NOVISUALES = ('  object Conn: TADOConnection\n    Left = 400\n    Top = 16\n  end\n'
              '  object Query: TADOQuery\n    Connection = Conn\n    Parameters = <>\n    Left = 400\n    Top = 72\n  end\n'
              '  object Tabla: TADOTable\n    Connection = Conn\n    Left = 400\n    Top = 128\n  end\n'
              '  object Comando: TADOCommand\n    Connection = Conn\n    Parameters = <>\n    Left = 400\n    Top = 184\n  end\n')
escribe('UAdoVcl.pas', pas('UAdoVcl', 'TFormAdoVcl', 'System.Classes, Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, Data.DB, Data.Win.ADODB', CAMPOS))
VCL = escribe('UAdoVcl.dfm', "object FormAdoVcl: TFormAdoVcl\n  Left = 0\n  Top = 0\n  Caption = 'ADO'\n"
              '  ClientHeight = 300\n  ClientWidth = 500\n'
              "  object Boton: TButton\n    Left = 8\n    Top = 8\n    Width = 75\n    Height = 25\n    Caption = 'Boton'\n    TabOrder = 0\n  end\n"
              "  object Otro: TButton\n    Left = 90\n    Top = 8\n    Width = 75\n    Height = 25\n    Caption = 'Otro'\n    TabOrder = 1\n  end\n"
              + NOVISUALES + 'end\n')
escribe('UAdoFmx.pas', pas('UAdoFmx', 'TFormAdoFmx', 'System.Classes, FMX.Forms, FMX.StdCtrls, FMX.Types, FMX.Controls, Data.DB, Data.Win.ADODB', CAMPOS))
FMX = escribe('UAdoFmx.fmx', "object FormAdoFmx: TFormAdoFmx\n  Left = 0\n  Top = 0\n  Caption = 'ADO'\n"
              '  ClientHeight = 300\n  ClientWidth = 500\n'
              "  object Boton: TButton\n    Position.X = 8\n    Position.Y = 8\n    TabOrder = 0\n    Text = 'Boton'\n  end\n"
              "  object Otro: TButton\n    Position.X = 90\n    Position.Y = 8\n    TabOrder = 1\n    Text = 'Otro'\n  end\n"
              + NOVISUALES + 'end\n')


def orden():
    return [l.split()[1].rstrip(':') for l in open(VCL, encoding='ascii') if l.startswith('  object ')]


def tiene_manifiesto(ruta):
    k = ctypes.WinDLL('kernel32')
    k.LoadLibraryExW.restype = ctypes.c_void_p
    k.LoadLibraryExW.argtypes = [ctypes.c_wchar_p, ctypes.c_void_p, ctypes.c_uint32]
    k.FindResourceW.restype = ctypes.c_void_p
    k.FindResourceW.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    k.FreeLibrary.argtypes = [ctypes.c_void_p]
    m = k.LoadLibraryExW(ruta, None, 2)
    assert m, ruta
    try:
        return bool(k.FindResourceW(m, 1, 24))
    finally:
        k.FreeLibrary(m)


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='render-com', t=300)
try:
    def preview(path, nombre):
        r = srv.call('delphi_designer', {'command': 'preview', 'path': path, 'out': os.path.join(JAIL, nombre)}, t=240)
        try:
            return json.loads(r), r
        except ValueError:
            return {}, r

    j, r = preview(VCL, 'v.png')
    check('C1 VCL: el form con ADO carga entero, sin un componente saltado (TADOQuery, TADOTable, TADOCommand)',
          j.get('components') == 6 and not j.get('ignored') and os.path.exists(os.path.join(JAIL, 'v.png')), r[:500])
    r = srv.call('delphi_designer', {'command': 'set', 'path': VCL, 'component': 'Otro', 'before': 'Boton'}, t=240)
    check('C2 VCL: el juez del orden juzga ese form y escribe (era DSGN-143: el form no cargaba entero)',
          orden() == ['Otro', 'Boton', 'Conn', 'Query', 'Tabla', 'Comando'], (orden(), r[:500]))
    j, r = preview(FMX, 'f.png')
    check('C3 FMX: lo mismo al cargar', j.get('components') == 6 and not j.get('ignored') and
          os.path.exists(os.path.join(JAIL, 'f.png')), r[:500])
finally:
    srv.cierra()

check('C4 los ayudantes de la instalacion no llevan manifiesto: se lo pone la caja a su copia',
      not any(tiene_manifiesto(a) for a in AYUDANTES), AYUDANTES)

mc.borra(BASE)
mc.fin('un form con ADO carga y se juzga en el contenedor (V65)')
