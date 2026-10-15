# -*- coding: utf-8 -*-
"""H9 de la 1.19.2 (Hermes sobre la 1.19.1, informe 111720; medido el 15-oct en
hermes1191\\lintmodal): una propiedad que el cargador rechaza en la RAIZ del form
salia en "ignored" de preview con el nombre de NUESTRA clase de dentro
("component": "TFormOculta", la del renderizador VCL) y sin "line", aunque la nota
DSGN-114 dice que line dice donde esta cada una. Un hijo salia bien (Button1, su
linea). La causa: el renderizador lee la raiz en modo diseno, donde TReader lee su
nombre y lo descarta (ReadRootComponent), y le ponia el nombre DESPUES de leer;
el error de una propiedad de un componente sin nombre lleva su ClassName.

  P1 VCL, raiz de un form con ModalResult = mrOK: "component" = el nombre de la
     raiz (FormMain), con su "line", y nada de TFormOculta (ROJO en produccion)
  P2 FMX, raiz de un form con una propiedad que no existe: lo mismo (ROJO)
  P3 VCL, raiz de un FRAME con una propiedad que no existe: el nombre del frame
     y su linea (ROJO)
  C1 control: un hijo (Button1) con una propiedad que no existe: su nombre y su
     linea, como ya salia

Uso:  python tests/test_preview_raiz_1192.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('preview_raiz_1192')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)

s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='preview-raiz', t=300)


def d(**kw):
    return s.call('delphi_designer', kw, t=300)


def raiz(fichero):
    """El nombre de la raiz, de la cabecera del fichero (object/inherited X: TX)."""
    m = re.search(r'^\s*(?:object|inherited|inline)\s+(\w+)\s*:', mc.lee(fichero), re.M)
    return m.group(1) if m else ''


def linea_de(fichero, texto):
    for n, l in enumerate(mc.lee(fichero).splitlines(), 1):
        if l.strip() == texto:
            return n
    return 0


def ignoradas(p):
    try:
        return json.loads(p).get('ignored', [])
    except ValueError:
        return []


def mete(fichero, ancla, nueva):
    """Una linea debajo de ancla (la primera), con delphi_edit como un agente."""
    s.call('delphi_edit', {'path': fichero, 'old': ancla, 'new': ancla + '\n' + nueva})


def la_de(ign, prop):
    return next((i for i in ign if i.get('property') == prop), {})


try:
    listas = mc.espera_tablas(lambda tool, args, t=120: s.call(tool, args, t=t))
    check('fixture: las tablas del disenador estan listas',
          all(not mc.tiene(r, 'DSGN-051') and not mc.fallo(r) for _, r in listas), str(listas)[:300])

    # P1 + C1: VCL
    vcl = os.path.join(JAIL, 'vcl')
    s.call('delphi_create', {'kind': 'project-vcl', 'name': 'RaizVcl', 'dir': vcl})
    DFM = os.path.join(vcl, 'UMain.dfm')
    d(command='insert', path=DFM, classname='TButton', component='Button1')
    mete(DFM, '  TextHeight = 15', '  ModalResult = mrOK')
    mete(DFM, '    TabOrder = 0', '    Frobnica = 1')
    p = d(command='preview', path=DFM, maxwidth=100)
    ign = ignoradas(p)
    uno = la_de(ign, 'ModalResult')
    check('P1 VCL: la raiz en ignored con SU nombre y su linea, sin TFormOculta',
          uno.get('component') == raiz(DFM) and uno.get('line') == linea_de(DFM, 'ModalResult = mrOK')
          and 'TFormOculta' not in p, (raiz(DFM), uno, p[:200]))
    hijo = la_de(ign, 'Frobnica')
    check('C1 control: un hijo con su nombre y su linea',
          hijo.get('component') == 'Button1' and hijo.get('line') == linea_de(DFM, 'Frobnica = 1'), hijo)

    # P2: FMX
    fmx = os.path.join(JAIL, 'fmx')
    s.call('delphi_create', {'kind': 'project-fmx', 'name': 'RaizFmx', 'dir': fmx})
    FMX = os.path.join(fmx, 'UMain.fmx')
    primera = next(l for l in mc.lee(FMX).splitlines()[1:] if '=' in l)
    mete(FMX, primera, '  Frobnica = 1')
    p = d(command='preview', path=FMX, maxwidth=100)
    uno = la_de(ignoradas(p), 'Frobnica')
    check('P2 FMX: la raiz en ignored con SU nombre y su linea',
          uno.get('component') == raiz(FMX) and uno.get('line') == linea_de(FMX, 'Frobnica = 1'),
          (raiz(FMX), uno, p[:300]))

    # P3: un frame VCL
    s.call('delphi_create', {'kind': 'frame-vcl', 'name': 'UMarco', 'project': os.path.join(vcl, 'RaizVcl.dproj')})
    MARCO = os.path.join(vcl, 'UMarco.dfm')
    primera = next(l for l in mc.lee(MARCO).splitlines()[1:] if '=' in l)
    mete(MARCO, primera, '  Frobnica = 1')
    p = d(command='preview', path=MARCO, maxwidth=100)
    uno = la_de(ignoradas(p), 'Frobnica')
    check('P3 frame VCL: la raiz en ignored con el nombre del frame y su linea',
          uno.get('component') == raiz(MARCO) and uno.get('line') == linea_de(MARCO, 'Frobnica = 1'),
          (raiz(MARCO), uno, p[:300]))
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('preview: la raiz en ignored 1.19.2 (H9)')
