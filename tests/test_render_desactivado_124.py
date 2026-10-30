# -*- coding: utf-8 -*-
"""V124 de la 1.24: un paquete DESACTIVADO en el IDE (Install Packages sin marcar,
clave Disabled Packages) se cargaba igual en el preview, el lint y el juez de
escritura: el renderizador leia Known Packages sin mirar la otra lista. Medido
contra la 1.23.1 con el TChatBubble de MakerAi.UI.bpl, desactivado aqui y en
ningun otro paquete: se dibujaba. Ahora lo dice el servidor, que ya tenia ese
lector, y desde V65 el ayudante no mira el registro: carga la lista que le da.

El registro del IDE no se toca: lo desactivado aqui es de la maquina, asi que
  D1-D2 el renderizador DE VERDAD con --knownfile, y un paquete estandar del IDE
        (dclsmp370.bpl, TGauge) en vez del de esta maquina
  D3    ...y sin --bdsroot no busca el IDE en el registro: RENDER-008
  E1    el servidor entero: PACKAGES= cuenta lo que dice el registro, leido aqui
        solo para comparar (ROJO en produccion si la maquina tiene desactivados)

Uso:  python tests/test_render_desactivado_124.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import subprocess
import winreg
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('render_desactivado_124')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
RENDER = os.path.join(os.path.dirname(EXE), 'DelphiFormRenderVcl.exe')
BDS = '37.0'


def escribe(nombre, texto):
    ruta = os.path.join(JAIL, nombre)
    open(ruta, 'wb').write(texto.replace('\n', '\r\n').encode('ascii'))
    return ruta


escribe('UGauge.pas', 'unit UGauge;\n\ninterface\n\nuses\n  Vcl.Forms, Vcl.Samples.Gauges;\n\ntype\n'
        '  TFormGauge = class(TForm)\n    Gauge1: TGauge;\n  end;\n\nvar\n  FormGauge: TFormGauge;\n\n'
        'implementation\n\n{$R *.dfm}\n\nend.\n')
FORM = escribe('UGauge.dfm', 'object FormGauge: TFormGauge\n  Left = 0\n  Top = 0\n  Caption = \'G\'\n'
               '  ClientHeight = 200\n  ClientWidth = 300\n  object Gauge1: TGauge\n    Left = 8\n    Top = 8\n'
               '    Width = 100\n    Height = 100\n    Progress = 40\n  end\nend\n')


def ayudante(*extra):
    """Lanzado como lo lanza el servidor; las lineas CLAVE=valor de su salida."""
    p = subprocess.run([RENDER, '--path', FORM, '--out', os.path.join(BASE, 'o.png'), '--timeout', '120000',
                        '--bds', BDS, '--bdsroot', mc.raiz_del_ide(BDS)] + list(extra),
                       capture_output=True, timeout=240, cwd=JAIL)
    salida = {}
    for linea in p.stdout.decode('utf-8', 'replace').replace('\r', '').split('\n'):
        clave, igual, valor = linea.partition('=')
        if igual:
            salida.setdefault(clave, valor)
    return p.returncode, salida


def conocidos(paquetes):
    """El total de PACKAGES=<cargados>/<conocidos> (None si no vino)."""
    trozos = (paquetes or '').split('/')
    return int(trozos[1]) if len(trozos) == 2 and trozos[1].isdigit() else None


def con_lista(rutas):
    lista = os.path.join(JAIL, 'paquetes.lst')
    open(lista, 'w', encoding='utf-8-sig').write('\n'.join(rutas))
    return ayudante('--knownfile', lista)


BIN = os.path.join(mc.raiz_del_ide(BDS), 'bin')
ESTANDAR = [os.path.join(BIN, n) for n in ('dclstd370.bpl', 'dclsmp370.bpl')]
c0, s0 = con_lista(ESTANDAR)
check('D1 control: con dclsmp370.bpl en la lista, el TGauge se dibuja (no sale sustituido)',
      c0 == 0 and 'TGauge' not in s0.get('SUBSTITUTED', '') and conocidos(s0.get('PACKAGES')) == 2, (c0, s0))
c1, s1 = con_lista(ESTANDAR[:1])
check('D2 sin el en la lista, TGauge sale sustituido y hay un conocido menos',
      c1 == 0 and 'TGauge' in s1.get('SUBSTITUTED', '') and conocidos(s1.get('PACKAGES')) == 1, (c1, s1))
# el estilo de una plataforma es lo unico que le pide la carpeta del IDE: un recurso de sus bpl
FMX = escribe('UEstilo.fmx', 'object FormE: TFormE\n  Left = 0\n  Top = 0\n  Caption = \'E\'\n'
              '  ClientHeight = 100\n  ClientWidth = 100\nend\n')
p = subprocess.run([os.path.join(os.path.dirname(EXE), 'DelphiFormRenderFmx.exe'), '--path', FMX, '--out',
                    os.path.join(BASE, 'e.png'), '--timeout', '120000', '--bds', BDS, '--style', 'android'],
                   capture_output=True, timeout=240, cwd=JAIL)
salida = p.stdout.decode('utf-8', 'replace')
check('D3 sin --bdsroot no busca el IDE en el registro: RENDER-008', mc.es(salida, 'SR_RENDER_SIN_IDE_FMT'), salida[:300])


def lista(subclave):
    """Los .bpl de una clave del IDE, sin tocarla; KEY_READ."""
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, 'Software\\Embarcadero\\BDS\\%s\\%s' % (BDS, subclave)) as k:
            return [winreg.EnumValue(k, i)[0].replace('/', '\\').rsplit('\\', 1)[-1].lower()
                    for i in range(winreg.QueryInfoKey(k)[1])]
    except OSError:
        return []


quedan = [n for n in lista('Known Packages') if n not in set(lista('Disabled Packages'))]
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='render-desactivado', t=300)
try:
    r = srv.call('delphi_designer', {'command': 'preview', 'path': FORM, 'out': os.path.join(JAIL, 'o.png')}, t=240)
    try:
        j = json.loads(r)
    except ValueError:
        j = {}
    check('E1 por el servidor, PACKAGES= cuenta Known Packages menos Disabled Packages',
          conocidos(j.get('packages')) == len(quedan), (j.get('packages'), len(quedan), r[:300]))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('un paquete desactivado en el IDE no se carga (V124)')
