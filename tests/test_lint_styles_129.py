# -*- coding: utf-8 -*-
"""1.29 (C3): delphi_designer lint styles=<.style o carpeta> - los StyleLookup de un form FMX contra los estilos que el
agente dice que ve, aunque los tome de un StyleBook que el lint no lee o sea un frame (el del form que lo aloja). Un
informe del 7-nov: un frame con 167 StyleLookup, lint CLEAN + DSGN-178 ("no juzgados") y delphi_styles lint lo apartaba
(formsWithAStyleBook): ninguna herramienta los validaba, y un nombre mal escrito cae al estilo de la plataforma sin
ningun error. El juez es el propio estilo: sus StyleName (EL lector de un .style, TStyleDoc) y el de la plataforma.

  K1 control: el lint de un frame sin styles: DSGN-178, sus tres lookups sin juzgar, como antes
  K2 styles=<carpeta>: DSGN-192 con el mal escrito, y ni el del .style ni el de la plataforma; sin DSGN-178.
     ROJO contra 166bea8b (no habia styles)
  K3 styles=<el .style>: lo mismo
  K4 con el nombre arreglado: CLEAN, sin DSGN-192 ni DSGN-178
  K5 un form con su TStyleBook: con styles= se juzga (DSGN-192 con el suyo mal escrito)
  K6 un .style que el parser del IDE leeria distinto en la carpeta: sus nombres no cuentan y DSGN-194 lo dice
  K7 styles= que no vale: una carpeta sin .style, un fichero que no es un .style y uno que no existe (DSGN-193 o no
     existe); fuera de la jaula, la puerta de leer
  K8 styles= con un .dfm: DSGN-193 (StyleLookup es de FMX); styles con tree: DSGN-047

Uso:  python tests/test_lint_styles_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('lint_styles_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True, con_render=True)
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
for d in (JAIL, FUERA):
    os.makedirs(d)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='lintstyles', t=600)


def escribe(ruta, texto):
    with open(ruta, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(texto.replace('\n', '\r\n'))
    return ruta


def lint(path, **kw):
    a = {'command': 'lint', 'path': path}
    a.update(kw)
    return srv.call('delphi_designer', a, 300)


def nombra(r, lookup):
    # la LINEA de un lookup juzgado: el nombre entre comillas a secas tambien lo lleva la sugerencia
    # ("Did you mean 'mibotonstyle'?", dirigido de Hermes de la 1.29)
    return ("StyleLookup = '%s'" % lookup) in r


try:
    app = os.path.join(JAIL, 'App')
    r = srv.call('delphi_create', {'kind': 'project-fmx', 'name': 'App', 'dir': app})
    check('fixture: el proyecto FMX (delphi_create)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    r = srv.call('delphi_create', {'kind': 'frame-fmx', 'name': 'UMarco', 'project': os.path.join(app, 'App.dproj')})
    check('fixture: el frame UMarco', 'UMarco' in r and 'error' not in mc.como_json(r), r[:300])
    marco = os.path.join(app, 'UMarco.fmx')
    for comp, lookup in (('BotonPropio', 'mibotonstyle'), ('BotonTypo', 'mibotontsyle'), ('BotonPlat', 'buttonstyle')):
        r = srv.call('delphi_designer', {'command': 'insert', 'path': marco, 'classname': 'TButton',
                                         'component': comp, 'props': 'StyleLookup=' + lookup})
        check('fixture: %s con %s' % (comp, lookup), ('"inserted":"%s"' % comp) in r.replace(' ', ''), r[:300])
    estilos = os.path.join(app, 'Styles')
    os.makedirs(estilos)
    uno = escribe(os.path.join(estilos, 'Uno.style'),
                  "object TStyleContainer\n  object TLayout\n    StyleName = 'mibotonstyle'\n  end\nend\n")

    r = lint(marco)
    check('K1 control: un frame sin styles, DSGN-178 con sus 3 lookups sin juzgar',
          mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_JUZGAR_FMT') and ' 3 StyleLookup' in r, r[:600])

    r = lint(marco, styles=estilos)
    check('K2 styles=<carpeta>: DSGN-192 con el mal escrito. ROJO contra 166bea8b',
          mc.es(r, 'SN_DESIGNER_LOOKUPS_FUERA_DE_STYLES_FMT') and nombra(r, 'mibotontsyle') and 'BotonTypo' in r, r[:700])
    check('K2 ...ni el del .style ni el de la plataforma, y sin DSGN-178',
          not nombra(r, 'mibotonstyle') and not nombra(r, 'buttonstyle') and
          not mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_JUZGAR_FMT') and ' 1 StyleLookup' in r, r[:700])
    # el nombre que SI define el estilo dado, junto al mal escrito: el agente no tiene que buscarlo (Hermes,
    # dirigido de la 1.29: tarjetaestilo, con tarjetastyle en su .style)
    check('K2b ...y la linea del mal escrito trae el mas parecido de los que SI hay (mibotonstyle). '
          'ROJO contra 28ddda3f',
          "Did you mean 'mibotonstyle'?" in next((l for l in r.splitlines() if nombra(l, 'mibotontsyle')), ''),
          r[:700])
    r = lint(marco, styles=uno)
    check('K3 styles=<el .style>: lo mismo',
          mc.es(r, 'SN_DESIGNER_LOOKUPS_FUERA_DE_STYLES_FMT') and nombra(r, 'mibotontsyle') and
          not nombra(r, 'mibotonstyle') and not mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_JUZGAR_FMT'), r[:700])

    r = srv.call('delphi_designer', {'command': 'set', 'path': marco, 'component': 'BotonTypo',
                                     'prop': 'StyleLookup', 'value': 'mibotonstyle'})
    check('fixture: el nombre arreglado (designer set)', 'error' not in mc.como_json(r), r[:300])
    r = lint(marco, styles=estilos)
    check('K4 con el nombre arreglado: CLEAN, sin DSGN-192 ni DSGN-178',
          mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT') and not mc.es(r, 'SN_DESIGNER_LOOKUPS_FUERA_DE_STYLES_FMT') and
          not mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_JUZGAR_FMT'), r[:500])

    # un form con su TStyleBook (sus estilos van en binario: el lint no los lee)
    forma = escribe(os.path.join(app, 'UConLibro.fmx'),
                    "object ConLibro: TForm\n  StyleBook = StyleBook1\n  ClientHeight = 200\n  ClientWidth = 300\n"
                    "  object StyleBook1: TStyleBook\n    Left = 40\n    Top = 40\n  end\n"
                    "  object B1: TButton\n    StyleLookup = 'tipoenelform'\n    TabOrder = 0\n  end\nend\n")
    escribe(os.path.join(app, 'UConLibro.pas'),
            "unit UConLibro;\n\ninterface\n\nuses\n  System.Classes, FMX.Types, FMX.Controls, FMX.Forms, "
            "FMX.StdCtrls;\n\ntype\n  TConLibro = class(TForm)\n    StyleBook1: TStyleBook;\n    B1: TButton;\n  end;\n\n"
            "var\n  ConLibro: TConLibro;\n\nimplementation\n\n{$R *.fmx}\n\nend.\n")
    r = lint(forma)
    check('K5 control: un form con su TStyleBook sin styles, no juzgado (DSGN-178)',
          mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_JUZGAR_FMT') and not nombra(r, 'tipoenelform'), r[:500])
    r = lint(forma, styles=estilos)
    check('K5 ...con styles=, juzgado: DSGN-192 con el suyo',
          mc.es(r, 'SN_DESIGNER_LOOKUPS_FUERA_DE_STYLES_FMT') and nombra(r, 'tipoenelform'), r[:600])

    # un .style que el parser del IDE leeria distinto (el '>' de una coleccion en su propia linea)
    raros = os.path.join(JAIL, 'Raros')
    os.makedirs(raros)
    escribe(os.path.join(raros, 'Bueno.style'),
            "object TStyleContainer\n  object TLayout\n    StyleName = 'mibotonstyle'\n  end\nend\n")
    escribe(os.path.join(raros, 'Raro.style'),
            "object TStyleContainer\n  object TLayout\n    StyleName = 'tipoenelform'\n    Items = <\n      item\n"
            "      end\n    >\n  end\nend\n")
    r = lint(forma, styles=raros)
    check('K6 un .style que el parser del IDE lee distinto: sus nombres no cuentan (tipoenelform sigue en DSGN-192)',
          mc.es(r, 'SN_DESIGNER_LOOKUPS_FUERA_DE_STYLES_FMT') and nombra(r, 'tipoenelform'), r[:700])
    check('K6 ...y DSGN-194 lo nombra', mc.es(r, 'SN_DESIGNER_STYLES_SIN_LEER_FMT') and 'Raro.style' in r, r[-400:])

    vacia = os.path.join(JAIL, 'Vacia')
    os.makedirs(vacia)
    r = lint(marco, styles=vacia)
    check('K7 una carpeta sin .style: DSGN-193', mc.abre(r, 'SR_DESIGNER_STYLES_NO_VALE_FMT'), r[:300])
    r = lint(marco, styles=marco)
    check('K7 un fichero que no es un .style (el .fmx): DSGN-193', mc.abre(r, 'SR_DESIGNER_STYLES_NO_VALE_FMT'), r[:300])
    r = lint(marco, styles=os.path.join(estilos, 'NoEsta.style'))
    check('K7 uno que no existe: no existe', mc.abre(r, 'SR_NO_EXISTE_FMT'), r[:300])
    escribe(os.path.join(FUERA, 'Fuera.style'),
            "object TStyleContainer\n  object TLayout\n    StyleName = 'mibotontsyle'\n  end\nend\n")
    r = lint(marco, styles=FUERA)
    check('K7 fuera de la jaula: la puerta de leer', mc.es(r, 'SR_JAIL_FMT'), r[:300])

    dfm = escribe(os.path.join(JAIL, 'UVcl.dfm'), "object FVcl: TForm\n  Caption = 'x'\nend\n")
    r = lint(dfm, styles=estilos)
    check('K8 styles= con un .dfm: DSGN-193 (StyleLookup es de FMX)',
          mc.abre(r, 'SR_DESIGNER_STYLES_NO_VALE_FMT') and 'FMX' in r, r[:300])
    r = srv.call('delphi_designer', {'command': 'tree', 'path': marco, 'styles': estilos})
    check('K8 ...y styles con tree: DSGN-047', mc.abre(r, 'SR_DESIGNER_NO_VA_CON_COMANDO_FMT'), r[:300])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('lint styles= (1.29, C3)')
