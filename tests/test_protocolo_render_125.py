# -*- coding: utf-8 -*-
"""V25: un renderizador de otra version se dice, no se malinterpreta.

Los ayudantes viajan con el servidor, pero nada lo comprobaba: uno viejo con un servidor nuevo contestaba a un
argumento que no conocia con un error cualquiera, o leia IGNORED= con otras partes y lo saltado pasaba a "no
confirmado" en silencio (revisor de la 1.20.2; el 30-oct-2026 uno olvidado en la carpeta del compilado solo se delato
por un aviso del log). Lo primero que escribe el ayudante es su protocolo, y el servidor lo compara.
Con ayudantes de mentira, compilados aqui: el servidor no sabe de quien es lo que lanza.

Usage:  python tests/test_protocolo_render_125.py [path-to-DelphiLspMcp.exe]
"""
import os, shutil
import mcp_cliente as mc
from mcp_cliente import check

OTRA = 'SR_DESIGNER_RENDER_OTRA_VERSION_FMT'
BASE = mc.carpeta('protocolo-render-125')
RAIZ = os.path.join(BASE, 'raiz')
os.makedirs(RAIZ)
PAS = ('unit UF;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms, Vcl.StdCtrls, System.Classes, Vcl.Controls;\r\n\r\ntype\r\n'
       '  TUF = class(TForm)\r\n    Label1: TLabel;\r\n  end;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n')
DFM = ("object UF: TUF\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'F'\r\n  ClientHeight = 100\r\n  ClientWidth = 200\r\n"
       "  object Label1: TLabel\r\n    Left = 8\r\n    Top = 8\r\n    Width = 50\r\n    Height = 13\r\n    Caption = 'Uno'\r\n  end\r\nend\r\n")
with open(os.path.join(RAIZ, 'UF.pas'), 'w', newline='') as f:
    f.write(PAS)
FORM = os.path.join(RAIZ, 'UF.dfm')
with open(FORM, 'w', newline='') as f:
    f.write(DFM)
PNG = os.path.join(RAIZ, 'x.png')

srv = mc.Stdio(mc.copia_exe(os.path.join(BASE, 'compila')), mc.entorno({'DELPHI_MCP_ROOTS': RAIZ}), nombre='compila-stubs', t=240)


def ayudante(nombre, lineas, salida):
    """Un exe que escribe lineas y sale con ese codigo, como lo haria un ayudante."""
    d = os.path.join(RAIZ, 'stubs', nombre)
    srv.call('delphi_create', {'kind': 'project-console', 'name': nombre, 'dir': d})
    dpr = os.path.join(d, nombre + '.dpr')
    cuerpo = ''.join("  Writeln('%s');\r\n" % x for x in lineas)
    with open(dpr, 'w', newline='') as f:
        f.write('program %s;\r\n\r\n{$APPTYPE CONSOLE}\r\n\r\nbegin\r\n%s  Halt(%d);\r\nend.\r\n' % (nombre, cuerpo, salida))
    j = mc.como_json(srv.call('delphi_build', {'project': os.path.join(d, nombre + '.dproj'), 'platform': 'Win64', 'config': 'Release'}, t=120)) or {}
    check('el ayudante de mentira %s compila' % nombre, j.get('success') is True, str(j)[:300])
    return os.path.join(d, 'Win64', 'Release', nombre + '.exe')


def con_ayudante(exe_ayudante, nombre):
    """Un servidor nuevo con ese ayudante en el sitio del de VCL. Devuelve lo que dicen preview y set."""
    d = os.path.join(BASE, 'srv-' + nombre)
    exe = mc.copia_exe(d, con_render=True)
    shutil.copy(exe_ayudante, os.path.join(d, 'DelphiFormRenderVcl.exe'))
    s = mc.Stdio(exe, mc.entorno({'DELPHI_MCP_ROOTS': RAIZ}), nombre='proto-' + nombre, t=240)
    try:
        return (s.call('delphi_designer', {'command': 'preview', 'path': FORM, 'out': PNG, 'inline': False}),
                s.call('delphi_designer', {'command': 'set', 'path': FORM, 'component': 'Label1', 'prop': 'Caption', 'value': nombre}))
    finally:
        s.cierra()


try:
    CASOS = [
        ('Viejo', ['ROOT=UF:TUF:form', 'SIZE=10x10'], 0, 'sin protocolo y como si hubiera ido bien'),
        ('OtroNum', ['PROTOCOL=999', 'ROOT=UF:TUF:form', 'SIZE=10x10'], 0, 'con otro numero'),
        ('ArgNuevo', ['ERROR=Unknown argument: --boxes'], 2, 'el caso del 30-oct: un argumento que no conoce'),
    ]
    for nombre, lineas, salida, que in CASOS:
        pv, st = con_ayudante(ayudante(nombre, lineas, salida), nombre)
        check('%s (%s): preview dice que es de otra version' % (nombre, que), mc.es(pv, OTRA), pv[:300])
        check('%s: el mensaje no ensena donde esta la casa' % nombre, 'srv-' not in pv and 'delphi-mcp-tests' not in pv, pv[:300])
        check('%s: set sigue escribiendo, y sin caerse' % nombre, not mc.fallo(st), st[:300])

    # lo que no es otra version sigue diciendo lo suyo
    pv, _ = con_ayudante(ayudante('Muere', [], 7), 'Muere')
    check('un ayudante que muere sin decir nada no es "otra version"', not mc.es(pv, OTRA) and mc.fallo(pv), pv[:300])
    pv, _ = con_ayudante(ayudante('Runtime', ['Runtime error 217 at 00000000'], 217), 'Runtime')
    check('uno que revienta con su codigo tampoco', not mc.es(pv, OTRA) and mc.fallo(pv), pv[:300])

    # el de verdad
    d = os.path.join(BASE, 'srv-real')
    s = mc.Stdio(mc.copia_exe(d, con_render=True), mc.entorno({'DELPHI_MCP_ROOTS': RAIZ}), nombre='proto-real', t=240)
    try:
        t = s.call('delphi_designer', {'command': 'preview', 'path': FORM, 'out': PNG, 'inline': False})
        check('el ayudante del build habla el protocolo del servidor: se dibuja', not mc.fallo(t) and os.path.exists(PNG), t[:300])
        t = s.call('delphi_designer', {'command': 'to-binary', 'path': FORM})
        check('...y el conversor del mismo ayudante, tambien', not mc.fallo(t), t[:300])
    finally:
        s.cierra()
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('renderer protocol 1.25 battery')
