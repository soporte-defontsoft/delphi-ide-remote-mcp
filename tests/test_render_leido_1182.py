# -*- coding: utf-8 -*-
"""B5 rev6 de la 1.18.2 ("DSGN-144 solo compara el .dfm: un .pas o ancestro que
cambie mientras juzga"): el juez del orden corre SIN el cerrojo y carga el form
con sus ancestros y frames de la carpeta; antes de escribir lo juzgado, el
servidor solo volvia a mirar el form y su unidad. Un ancestro que otro escritor
cambiara mientras tanto dejaba escribir un orden juzgado con el ancestro viejo.
Ahora el renderizador dice que leyo (READ=<sha256>|<ruta>, FormRenderProtocolo.inc)
y el servidor lo vuelve a mirar con el cerrojo (CambioEnLoLeido).

La carrera no se puede provocar desde fuera de forma fiable (el ayudante lee el
ancestro y acaba en milisegundos): la comparacion la miden las unitarias
(LspTests.FormRender: el lector de READ=, CambioEnLoLeido con el fichero igual,
cambiado y borrado). Aqui, el renderizador DE VERDAD, lanzado como lo lanza el
juez (--writeback on, con la propuesta entre sus hermanos: lo copia todo a la
carpeta de la llamada), y el servidor entero de control:

  L1 READ= del ancestro (UBase.dfm) con el sha256 de sus bytes (ROJO en
     produccion: no habia READ=)
  L2 ...y del frame del ancestro (UMarco.dfm) y del .pas que decide la cadena
     (UHija.pas), con sus sha256
  L3 la propuesta (lo PEDIDO) no se anota: el form de verdad lo compara el
     servidor por sus bytes
  L4 control: el juez contesto (WRITTEN=) sin form a medias (sin PARTIAL=)
  E1 control por el servidor: ordenar en esa form heredada se escribe (lo leido
     sigue igual: ningun DSGN-144 de mas)

Uso:  python tests/test_render_leido_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import hashlib
import json
import os
import shutil
import subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('render_leido_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)  # el juez es el renderizador
RENDER = os.path.join(os.path.dirname(EXE), 'DelphiFormRenderVcl.exe')


def escribe(nombre, texto):
    ruta = os.path.join(JAIL, nombre)
    open(ruta, 'wb').write(texto.replace('\n', '\r\n').encode('ascii'))
    return ruta


def sha(ruta):
    return hashlib.sha256(open(ruta, 'rb').read()).hexdigest().lower()


escribe('UMarco.pas', 'unit UMarco;\n\ninterface\n\nuses\n  Vcl.Forms, Vcl.StdCtrls;\n\ntype\n'
        '  TMarco = class(TFrame)\n    Button1: TButton;\n  end;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n')
MARCO = escribe('UMarco.dfm', 'object Marco: TMarco\n  Left = 0\n  Top = 0\n  Width = 200\n  Height = 60\n'
                '  TabOrder = 0\n  object Button1: TButton\n    Left = 4\n    Top = 4\n    Width = 75\n'
                '    Height = 25\n    Caption = \'B\'\n    TabOrder = 0\n  end\nend\n')
escribe('UBase.pas', 'unit UBase;\n\ninterface\n\nuses\n  Vcl.Forms, Vcl.StdCtrls, UMarco;\n\ntype\n'
        '  TFormBase = class(TForm)\n    Label1: TLabel;\n    Marco1: TMarco;\n  end;\n\n'
        'implementation\n\n{$R *.dfm}\n\nend.\n')
ANCESTRO = escribe('UBase.dfm', 'object FormBase: TFormBase\n  Left = 0\n  Top = 0\n  Caption = \'Base\'\n'
                   '  ClientHeight = 200\n  ClientWidth = 300\n  object Label1: TLabel\n    Left = 8\n'
                   '    Top = 8\n    Width = 24\n    Height = 15\n    Caption = \'Base\'\n  end\n'
                   '  inline Marco1: TMarco\n    Left = 8\n    Top = 40\n    Width = 200\n    Height = 60\n'
                   '    TabOrder = 0\n  end\nend\n')
HIJA_PAS = escribe('UHija.pas', 'unit UHija;\n\ninterface\n\nuses\n  Vcl.Forms, Vcl.StdCtrls, UBase;\n\ntype\n'
                   '  TFormHija = class(TFormBase)\n    Button2: TButton;\n    Button3: TButton;\n  end;\n\n'
                   'var\n  FormHija: TFormHija;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n')
HIJA = escribe('UHija.dfm', 'inherited FormHija: TFormHija\n  Caption = \'Hija\'\n  object Button2: TButton\n'
               '    Left = 8\n    Top = 120\n    Width = 75\n    Height = 25\n    Caption = \'Dos\'\n'
               '    TabOrder = 1\n  end\n  object Button3: TButton\n    Left = 100\n    Top = 120\n'
               '    Width = 75\n    Height = 25\n    Caption = \'Tres\'\n    TabOrder = 2\n  end\nend\n')

# el renderizador, como lo lanza ComoLoEscribeElIde (Lsp.FormRender.ComponeOrdenDeRender)
p = subprocess.run([RENDER, '--path', HIJA, '--writeback', 'on',
                    '--timeout', '60000', '--bds', '37.0', '--bdsroot', mc.raiz_del_ide()],
                   capture_output=True, timeout=120, cwd=JAIL)
salida = p.stdout.decode('utf-8', 'replace').replace('\r', '').split('\n')
leidos = {}
for linea in salida:
    if linea.startswith('READ='):
        huella, _, ruta = linea[len('READ='):].partition('|')
        leidos[os.path.normcase(ruta)] = huella.lower()


def leido(ruta):
    return leidos.get(os.path.normcase(ruta))


check('L1 READ= del ancestro UBase.dfm con el sha256 de sus bytes', leido(ANCESTRO) == sha(ANCESTRO),
      (leidos, p.returncode))
check('L2 ...y del frame del ancestro (UMarco.dfm) y del .pas que decide la cadena (UHija.pas)',
      leido(MARCO) == sha(MARCO) and leido(HIJA_PAS) == sha(HIJA_PAS), leidos)
check('L3 la propuesta (lo pedido) no se anota', leido(HIJA) is None, leidos)
check('L4 control: el juez contesto (WRITTEN=) sin form a medias (sin PARTIAL=)',
      p.returncode == 0 and any(x.startswith('WRITTEN=') for x in salida) and
      not any(x.startswith('PARTIAL=') for x in salida), (p.returncode, salida[:20]))

# U1: sin argumentos, la linea de uso con el nombre del programa en cada forma
# (salia "%s --path ..." y "(No argument for format ...)": el texto tiene dos %s y
# TextoDeUso pasaba uno; medido el 20-oct-2026). Rojo contra la 1.21.0. Tres
# formas desde V71 (1.23.1): pintar, el juez que escribe y el conversor
u = subprocess.run([RENDER], capture_output=True, timeout=60, cwd=JAIL)
uso = u.stderr.decode('utf-8', 'replace')
check('U1 sin argumentos: la linea de uso nombra el programa en sus tres formas, sin %s ni "No argument"',
      u.returncode == 2 and uso.count('DelphiFormRenderVcl.exe --path') == 3 and '%s' not in uso
      and 'No argument' not in uso, (u.returncode, uso[:300]))

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='render-leido', t=300)
try:
    r = srv.call('delphi_designer', {'command': 'set', 'path': HIJA, 'component': 'Button3',
                                     'before': 'Button2'}, t=240)
    try:
        j = json.loads(r)
    except ValueError:
        j = {}
    texto = open(HIJA, encoding='ascii').read()
    check('E1 control por el servidor: Button3 delante de Button2 en la heredada se escribe (sin DSGN-144)',
          j.get('ordered') == 'Button3' and texto.index('object Button3') < texto.index('object Button2'),
          r[:400])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('lo que leyo el juez del orden 1182 (B5)')
