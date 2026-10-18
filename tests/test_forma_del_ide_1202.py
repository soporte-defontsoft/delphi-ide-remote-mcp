# -*- coding: utf-8 -*-
"""La forma de las lineas de un form, por su juez (3b del censo de jueces de la
1.20.2). LineasDeForm lee un designer de texto por lineas, en la forma en que
lo escribe el IDE (ObjectBinaryToText); el parser del IDE lo lee por tokens.
Medido el 18-oct-2026 en produccion: un form con el '>' de una coleccion en su
propia linea carga en el IDE y lint decia CLEAN; set Left=20 escribia un
Left = 20 NUEVO encima de la coleccion sin tocar el Left = 10 de debajo, que
seguia mandando, y contestaba ok con "line": 0. Ahora quien lee o escribe por
lineas pregunta al parser (Lsp.DesignerBin.LineaQueElParserLeeDistinta), y lo
que no lee igual se niega (DSGN-160) o se avisa (DSGN-161).

  F1 delphi_edit escribe el '>' suelto: su aviso lo dice (DSGN-161; ROJO en
     produccion: nada)
  F2 set Left: negado y nada escrito (ROJO: un Left duplicado y ok)
  F3 tree, get, layout y check-binding: negados (ROJO: contestaban con otras
     lineas)
  F4 lint: DSGN-161, no CLEAN (ROJO: CLEAN)
  F5 preview: negado (ROJO: dibujaba sin juzgar los literales de esas lineas)
  F6 el remedio: to-binary y to-text lo dejan como el IDE, y set cambia el
     Left que habia (control)
  F7 un .style con dos propiedades en una linea: view negado y el lint de
     estilos lo dice (notInTheIdeShape; ROJO: lo leia); bien escrito, control
  F8 una propiedad dos veces en su objeto - la forma del IDE con
     DefineProperties (ImageIndex de una accion FMX, Left y Top de un form
     FMX: 14 forms de los Samples) -: ni avisada ni negada; set cambia las
     dos y dice como previous la que cuenta, la ultima (ROJO: cambiaba la
     primera y la segunda seguia mandando)
  F9 algo detras del end de la raiz (un end de mas, como en un frame de
     Hermes): el lint lo dice (DSGN-162; ROJO: CLEAN), y la raiz se sigue
     leyendo y editando como la lee el IDE

Uso:  python tests/test_forma_del_ide_1202.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('forma_del_ide_1202')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
APPDATA = os.path.join(BASE, 'appdata')
os.makedirs(APPDATA)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'LOCALAPPDATA': APPDATA}), nombre='forma', t=300)
call = srv.call

SUELTO = ('  object StatusBar1: TStatusBar\r\n'
          '    Panels = <\r\n'
          '      item\r\n'
          '        Width = 50\r\n'
          '      end\r\n'
          '      >\r\n'
          '    SimplePanel = False')


def lee(ruta):
    return open(ruta, 'rb').read()


try:
    PROY = os.path.join(JAIL, 'lin')
    DFM = os.path.join(PROY, 'UMain.dfm')
    r = call('delphi_create', {'kind': 'project-vcl', 'name': 'PLin', 'dir': PROY}, t=120)
    check('fixture: el proyecto VCL', not mc.fallo(r) and os.path.isfile(DFM), r[:200])
    mc.espera_info(call, {'command': 'info', 'classname': 'TStatusBar', 'framework': 'vcl', 'filter': 'Panels'},
                   cond=lambda r: '"Panels"' in r, tope=300)
    r = call('delphi_designer', {'command': 'insert', 'path': DFM, 'classname': 'TStatusBar'})
    check('fixture: un TStatusBar', not mc.fallo(r) and b'StatusBar1' in lee(DFM), r[:200])

    # ------------------------------------------------------------------ F1
    r = call('delphi_edit', {'path': DFM, 'old': '  object StatusBar1: TStatusBar', 'new': SUELTO})
    check('F1 delphi_edit escribe el > suelto (el IDE lo carga)', not mc.fallo(r) and b'      >\r\n' in lee(DFM),
          r[:200])
    check('F1 ...y su aviso dice que no es la forma del IDE (DSGN-161)', 'DSGN-161' in r, r[-400:])

    # ------------------------------------------------------------------ F2
    antes = lee(DFM)
    r = call('delphi_designer', {'command': 'set', 'path': DFM, 'component': 'StatusBar1',
                                 'prop': 'Left', 'value': '20'})
    check('F2 set Left: negado (DSGN-160), nada escrito', 'DSGN-160' in r and lee(DFM) == antes, r[:300])

    # ------------------------------------------------------------------ F3
    for cmd, extra in (('tree', {}), ('get', {'component': 'StatusBar1'}), ('layout', {}),
                       ('check-binding', {})):
        args = {'command': cmd, 'path': DFM}
        args.update(extra)
        r = call('delphi_designer', args)
        check('F3 %s: negado (DSGN-160), con la linea del >' % cmd, 'DSGN-160' in r and 'line 19' in r, r[:300])

    # ------------------------------------------------------------------ F4
    r = call('delphi_designer', {'command': 'lint', 'path': DFM})
    check('F4 lint: DSGN-161 con su linea, no CLEAN', 'DSGN-161' in r and 'Line 19' in r and
          not mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:300])

    # ------------------------------------------------------------------ F5
    r = call('delphi_designer', {'command': 'preview', 'path': DFM}, t=180)
    check('F5 preview: negado (DSGN-160)', 'DSGN-160' in r, r[:300])

    # ------------------------------------------------------------------ F6
    r = call('delphi_designer', {'command': 'to-binary', 'path': DFM}, t=120)
    check('F6 to-binary lo lee (el parser del IDE)', not mc.fallo(r), r[:250])
    r = call('delphi_designer', {'command': 'to-text', 'path': DFM}, t=120)
    texto = lee(DFM)
    check('F6 ...to-text lo deja como el IDE: end> pegado', not mc.fallo(r) and b'      end>\r\n' in texto and
          b'      >\r\n' not in texto, r[:250])
    r = call('delphi_designer', {'command': 'set', 'path': DFM, 'component': 'StatusBar1',
                                 'prop': 'Left', 'value': '20'})
    texto = lee(DFM)
    check('F6 ...y set cambia el Left que habia, uno solo', not mc.rechazado(r) and
          texto.count(b'    Left = 20\r\n') == 1 and b'    Left = 10\r\n' not in texto, r[:250])
    r = call('delphi_designer', {'command': 'lint', 'path': DFM})
    check('F6 ...y lint: CLEAN', mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:250])

    # ------------------------------------------------------------------ F8
    r = call('delphi_edit', {'path': DFM, 'old': '    Top = 10', 'new': '    Top = 10\r\n    Left = 30'})
    check('F8 delphi_edit escribe un segundo Left: forma del IDE, sin aviso de forma',
          not mc.fallo(r) and 'DSGN-161' not in r and 'DSGN-162' not in r, r[-400:])
    r = call('delphi_designer', {'command': 'set', 'path': DFM, 'component': 'StatusBar1',
                                 'prop': 'Left', 'value': '40'})
    texto = lee(DFM)
    check('F8 set Left con dos: cambia las DOS', not mc.rechazado(r) and
          texto.count(b'    Left = 40\r\n') == 2 and b'Left = 20' not in texto and b'Left = 30' not in texto,
          r[:250])
    check('F8 ...y su previous es el que contaba, el ultimo (30)', '"previous":"30"' in r.replace(' ', ''), r[:250])

    # ------------------------------------------------------------------ F9
    t = lee(DFM)
    open(DFM, 'wb').write(t + b'  end\r\n')
    n_detras = t.count(b'\n') + 1
    r = call('delphi_designer', {'command': 'lint', 'path': DFM})
    check('F9 un end de mas detras de la raiz: lint lo dice (DSGN-162) con su linea, no CLEAN',
          'DSGN-162' in r and ('Line %d' % n_detras) in r and not mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:300])
    r = call('delphi_designer', {'command': 'tree', 'path': DFM})
    check('F9 ...y tree lee la raiz como el IDE', not mc.fallo(r) and 'StatusBar1' in r, r[:250])
    r = call('delphi_designer', {'command': 'set', 'path': DFM, 'component': 'StatusBar1',
                                 'prop': 'Top', 'value': '12'})
    check('F9 ...y set la edita', not mc.rechazado(r) and b'    Top = 12\r\n' in lee(DFM), r[:250])

    # ------------------------------------------------------------------ F7
    ESTILOS = os.path.join(JAIL, 'estilos')
    os.makedirs(ESTILOS)
    STY = os.path.join(ESTILOS, 'e.style')
    MAL = ('object TStyleContainer\r\n'
           '  object TLayout\r\n'
           "    StyleName = 'uno'\r\n"
           '    Height = 10.000000000000000000 Width = 20.000000000000000000\r\n'
           '  end\r\n'
           'end\r\n')
    open(STY, 'w', encoding='utf-8', newline='').write(MAL)
    r = call('delphi_styles', {'command': 'view', 'path': STY})
    check('F7 view de un .style con dos propiedades en una linea: negado (DSGN-160)',
          'DSGN-160' in r and 'line 4' in r, r[:300])
    r = call('delphi_styles', {'command': 'lint', 'path': STY}, t=180)
    check('F7 ...y el lint de estilos lo dice (notInTheIdeShape), no clean',
          'notInTheIdeShape' in r and '"clean":false' in r.replace(' ', ''), r[:400])
    open(STY, 'w', encoding='utf-8', newline='').write(
        MAL.replace(' Width = ', '\r\n    Width = '))
    r = call('delphi_styles', {'command': 'view', 'path': STY})
    check('F7 control: bien escrito, view lo lee', not mc.fallo(r) and "uno" in r and 'DSGN-160' not in r, r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('la forma de las lineas por su juez 1202')
