# -*- coding: utf-8 -*-
"""Un heredado SIN bloque en la hija se toca como en el IDE (A16-G1, 1.23).

El IDE escribe en una form heredada SOLO lo que difiere del ancestro (medido en
el IDE el 24-oct-2026, con un Panel1 de la base que tiene Button1 y Button2:
tocando el Caption de la form, ni Button1 ni Button2 tienen bloque en la hija;
tocando Button1.Left escribe inherited Panel1 con inherited Button1 dentro y
solo su Left). Asi que un heredado que nadie ha tocado no esta en el fichero, y
get, set, delete e insert parent= de el decian DSGN-078 ("no hay ningun
Button1"): el agente no tenia camino. Ahora set e insert parent= escriben sus
bloques inherited (DSGN-171) donde el IDE los pone entre sus hermanos, get dice
lo que es y como lo carga el IDE (DSGN-172), y delete y el renombrado dan la
negativa de lo heredado (DSGN-084).

  H1  set Button1 Left=20: inherited Panel1 > inherited Button1 > Left = 20, y el lint del IDE lo carga
  H2  ...y despues set Button2: su bloque DETRAS del de Button1 (el orden del ancestro)
  H3  set Button2 primero y Button1 despues: el de Button1 DELANTE (el orden del IDE, no el ultimo)
  H4  donde lo pone el IDE entre los propios: DETRAS de un TLabel (la VCL escribe los graficos
      antes que las ventanas) y DELANTE de un TButton propio (lo heredado se crea antes)
  H5  insert TButton parent=Panel1: inherited Panel1 con el boton nuevo dentro
  H6  delete Button1 sin bloque: DSGN-084, nada escrito
  H7  renombrar Button1 sin bloque: DSGN-084, nada escrito
  H8  get Button1 sin bloque: DSGN-172 con sus lineas como lo carga el IDE
  H9  control: un nombre que no existe: DSGN-078 en get y en set
  H10 set parent=Panel1 de un Label9 propio: inherited Panel1 y el Label9 dentro

Lo mismo en un frame puesto en linea: el escritor se salta tambien un hijo suyo que no
difiere del frame (TWriter.WriteData), y DSGN-083 prometia poner aqui sus propiedades
por su ruta (Marco1.Dentro), que decia DSGN-078. Medido el 24-oct: el juez escribe
inline Marco1 con sus hijos dentro, y los encuentra por esa ruta.

  H11 set Marco1.Dentro Left=20: inline Marco1 > inherited PanelF > inherited Dentro > Left = 20
  H12 get Marco1.Fuera sin bloque: DSGN-172 del frame, con sus lineas
  H13 delete Marco1.Dentro sin bloque: DSGN-083, como con su bloque
  H14 insert parent=Marco1.PanelF sin bloque: DSGN-083

Y before=/after= con un heredado sin bloque de referencia (decia DSGN-078): el juez lo
ve donde lo crea el ancestro, y su bloque no se escribe (el IDE no escribe uno que no
difiere, y sin [n] no cambia nada al cargar: TReader.ReadComponent).

  H15 Button7 before=Panel1: DSGN-136 con el orden del IDE (lo heredado se crea antes)
  H16 Label9 before=Panel1: ya esta (los graficos antes), en la 1 de 2 del FICHERO
  H17 Button8 after=Panel1: delante de Button7, sin bloque de Panel1, index 1 de 2

Mutante: produccion antes de A16-G1 (r1222ao): H1-H8 y H10 rojos; antes de los
hermanos (r1222ap): H11-H17 rojos, menos los dos lint, que miran un fichero sin tocar.

Uso:  python tests/test_heredado_sin_bloque_1230.py [exe]
"""
import os, re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('heredado1230')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
USES = '  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls'
BASE_DFM = ("object FormBase: TFormBase\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'Base'\r\n"
            "  ClientHeight = 200\r\n  ClientWidth = 300\r\n"
            "  object Panel1: TPanel\r\n    Left = 8\r\n    Top = 8\r\n    Width = 200\r\n    Height = 150\r\n"
            "    TabOrder = 0\r\n"
            "    object Button1: TButton\r\n      Left = 8\r\n      Top = 8\r\n      TabOrder = 0\r\n    end\r\n"
            "    object Button2: TButton\r\n      Left = 8\r\n      Top = 40\r\n      TabOrder = 1\r\n    end\r\n"
            "  end\r\nend\r\n")
BASE_PAS = ("unit UBase;\r\n\r\ninterface\r\n\r\nuses\r\n" + USES + ";\r\n\r\n"
            "type\r\n  TFormBase = class(TForm)\r\n    Panel1: TPanel;\r\n    Button1: TButton;\r\n"
            "    Button2: TButton;\r\n  end;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n")
CON_LABEL = ("  object Label9: TLabel\r\n    Left = 240\r\n    Top = 8\r\n    Width = 34\r\n    Height = 15\r\n"
             "    Caption = 'Label9'\r\n  end\r\n")
CON_BOTON = ("  object Button7: TButton\r\n    Left = 220\r\n    Top = 40\r\n    Width = 75\r\n    Height = 25\r\n"
             "    Caption = 'Button7'\r\n    TabOrder = 1\r\n  end\r\n")
CON_BOTON8 = ("  object Button8: TButton\r\n    Left = 220\r\n    Top = 80\r\n    Width = 75\r\n    Height = 25\r\n"
              "    Caption = 'Button8'\r\n    TabOrder = 2\r\n  end\r\n")
MARCO_DFM = ("object Marco: TMarco\r\n  Left = 0\r\n  Top = 0\r\n  Width = 200\r\n  Height = 120\r\n  TabOrder = 0\r\n"
             "  object PanelF: TPanel\r\n    Left = 0\r\n    Top = 0\r\n    Width = 200\r\n    Height = 60\r\n"
             "    TabOrder = 0\r\n"
             "    object Dentro: TButton\r\n      Left = 8\r\n      Top = 8\r\n      TabOrder = 0\r\n    end\r\n  end\r\n"
             "  object Fuera: TButton\r\n    Left = 8\r\n    Top = 70\r\n    TabOrder = 1\r\n  end\r\nend\r\n")
MARCO_PAS = ("unit UMarco;\r\n\r\ninterface\r\n\r\nuses\r\n" + USES + ";\r\n\r\n"
             "type\r\n  TMarco = class(TFrame)\r\n    PanelF: TPanel;\r\n    Dentro: TButton;\r\n"
             "    Fuera: TButton;\r\n  end;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n")


def escribe(p, texto):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'wb').write(texto.encode('ascii'))
    return p


def caso(nombre, cuerpo='', con_label=False, con_boton=False, con_boton8=False):
    """Una carpeta con la base y una hija SIN bloques inherited (con su Label9,
    su Button7 o su Button8 propios si se piden): el form de la hija."""
    d = os.path.join(JAIL, nombre)
    escribe(os.path.join(d, 'UBase.dfm'), BASE_DFM)
    escribe(os.path.join(d, 'UBase.pas'), BASE_PAS)
    campos = (('    Label9: TLabel;\r\n' if con_label else '') + ('    Button7: TButton;\r\n' if con_boton else '')
              + ('    Button8: TButton;\r\n' if con_boton8 else ''))
    escribe(os.path.join(d, 'UHija.pas'),
            "unit UHija;\r\n\r\ninterface\r\n\r\nuses\r\n%s, UBase;\r\n\r\ntype\r\n  TFormHija = class(TFormBase)\r\n"
            "%s  end;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n" % (USES, campos))
    return escribe(os.path.join(d, 'UHija.dfm'),
                   "inherited FormHija: TFormHija\r\n  Caption = 'Hija'\r\n%s%s%s%send\r\n"
                   % (cuerpo, CON_LABEL if con_label else '', CON_BOTON if con_boton else '',
                      CON_BOTON8 if con_boton8 else ''))


def caso_marco(nombre):
    """Una form (no heredada) con el frame Marco1 en linea y SIN bloques de sus
    hijos, como la escribe el IDE si nadie los toca: el form."""
    d = os.path.join(JAIL, nombre)
    escribe(os.path.join(d, 'UMarco.dfm'), MARCO_DFM)
    escribe(os.path.join(d, 'UMarco.pas'), MARCO_PAS)
    escribe(os.path.join(d, 'UFormF.pas'),
            "unit UFormF;\r\n\r\ninterface\r\n\r\nuses\r\n%s, UMarco;\r\n\r\ntype\r\n  TFormF = class(TForm)\r\n"
            "    Label1: TLabel;\r\n    Marco1: TMarco;\r\n  end;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\n"
            "end.\r\n" % USES)
    return escribe(os.path.join(d, 'UFormF.dfm'),
                   "object FormF: TFormF\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'F'\r\n  ClientHeight = 300\r\n"
                   "  ClientWidth = 300\r\n  object Label1: TLabel\r\n    Left = 8\r\n    Top = 8\r\n    Width = 30\r\n"
                   "    Height = 15\r\n    Caption = 'L'\r\n  end\r\n  inline Marco1: TMarco\r\n    Left = 8\r\n"
                   "    Top = 40\r\n    Width = 200\r\n    Height = 120\r\n    TabOrder = 0\r\n  end\r\nend\r\n")


def lineas(p):
    return open(p, 'rb').read().decode('ascii').split('\r\n')


def sin_sangria(p):
    return [l.strip() for l in lineas(p) if l.strip()]


def dentro(ls, padre, hijo):
    """hijo es un bloque de primer nivel DENTRO del bloque padre (por sangria)."""
    try:
        i = next(k for k, l in enumerate(ls) if l.strip() == padre)
    except StopIteration:
        return False
    ind = len(ls[i]) - len(ls[i].lstrip())
    for l in ls[i + 1:]:
        if l.strip() == 'end' and len(l) - len(l.lstrip()) == ind:
            return False
        if l.strip() == hijo:
            return len(l) - len(l.lstrip()) == ind + 2
    return False


def antes(ls, a, b):
    sa = [l.strip() for l in ls]
    return a in sa and b in sa and sa.index(a) < sa.index(b)


antes_atomos = mc.atomos_rtl_nombres()
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='heredado1230', t=900)


def dsg(**a):
    return srv.call('delphi_designer', a, t=300)


try:
    # la tabla del disenador, generada antes de medir nada (DSGN-051)
    mc.espera_info(srv.call, {'command': 'info', 'classname': 'TButton'})

    # --- H1 ---------------------------------------------------------------------
    H = caso('h1')
    r = dsg(command='set', path=H, component='Button1', prop='Left', value='20')
    ls = lineas(H)
    check('H1 set Button1 Left=20 sin bloque: inherited Panel1 > inherited Button1 > Left = 20 (DSGN-171)',
          not mc.fallo(r) and mc.es(r, 'SN_DESIGNER_BLOQUES_HEREDADOS_FMT')
          and dentro(ls, 'inherited Panel1: TPanel', 'inherited Button1: TButton')
          and dentro(ls, 'inherited Button1: TButton', 'Left = 20')
          and sum(1 for l in ls if l.strip().startswith('inherited Button')) == 1, (r[:400], ls))
    r = dsg(command='lint', path=H)
    check('H1 ...y el lector del IDE lo carga (lint CLEAN)', mc.es(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:300])

    # --- H2 ---------------------------------------------------------------------
    r = dsg(command='set', path=H, component='Button2', prop='Top', value='60')
    ls = lineas(H)
    check('H2 ...y set Button2 despues: su bloque DETRAS del de Button1, en el mismo Panel1',
          not mc.fallo(r) and dentro(ls, 'inherited Panel1: TPanel', 'inherited Button2: TButton')
          and antes(ls, 'inherited Button1: TButton', 'inherited Button2: TButton')
          and sum(1 for l in ls if l.strip() == 'inherited Panel1: TPanel') == 1, (r[:300], ls))

    # --- H3 ---------------------------------------------------------------------
    H = caso('h3')
    dsg(command='set', path=H, component='Button2', prop='Top', value='60')
    r = dsg(command='set', path=H, component='Button1', prop='Left', value='20')
    ls = lineas(H)
    check('H3 set Button2 y luego Button1: el bloque de Button1 DELANTE del de Button2 (el orden del IDE)',
          not mc.fallo(r) and antes(ls, 'inherited Button1: TButton', 'inherited Button2: TButton'), (r[:300], ls))

    # --- H4 ---------------------------------------------------------------------
    H = caso('h4', con_label=True, con_boton=True)
    r = dsg(command='set', path=H, component='Panel1', prop='Width', value='220')
    ls = lineas(H)
    check('H4 entre los propios, donde lo pone el IDE: DETRAS de object Label9 (los graficos antes que las '
          'ventanas) y DELANTE de object Button7 (lo heredado se crea antes)',
          not mc.fallo(r) and antes(ls, 'object Label9: TLabel', 'inherited Panel1: TPanel')
          and antes(ls, 'inherited Panel1: TPanel', 'object Button7: TButton')
          and dentro(ls, 'inherited Panel1: TPanel', 'Width = 220'), (r[:300], ls))

    # --- H5 ---------------------------------------------------------------------
    H = caso('h5')
    r = dsg(command='insert', path=H, classname='TButton', component='Button9', parent='Panel1')
    ls = lineas(H)
    check('H5 insert TButton parent=Panel1 sin bloque: inherited Panel1 con el Button9 dentro (DSGN-171)',
          not mc.fallo(r) and mc.es(r, 'SN_DESIGNER_BLOQUES_HEREDADOS_FMT')
          and dentro(ls, 'inherited Panel1: TPanel', 'object Button9: TButton'), (r[:400], ls))

    # --- H6, H7, H8 -------------------------------------------------------------
    H = caso('h6')
    a = open(H, 'rb').read()
    r = dsg(command='delete', path=H, component='Button1')
    check('H6 delete Button1 sin bloque: DSGN-084 (se borra en el ancestro), nada escrito',
          mc.rechazado(r) and mc.es(r, 'SR_DESIGNER_HEREDADO_FMT') and open(H, 'rb').read() == a, r[:300])
    r = dsg(command='set', path=H, component='Button1', prop='Name', value='Boton')
    check('H7 renombrar Button1 sin bloque: DSGN-084, nada escrito',
          mc.rechazado(r) and mc.es(r, 'SR_DESIGNER_HEREDADO_FMT') and open(H, 'rb').read() == a, r[:300])
    r = dsg(command='get', path=H, component='Button1')
    check('H8 get Button1 sin bloque: DSGN-172, con sus lineas como lo carga el IDE (Top = 8 del ancestro)',
          not mc.fallo(r) and mc.es(r, 'SN_DESIGNER_HEREDADO_SIN_BLOQUE_FMT') and 'TButton' in r
          and re.search(r'Top = 8\b', r) is not None and open(H, 'rb').read() == a, r[:400])

    # --- H9 control ---------------------------------------------------------------
    r = dsg(command='get', path=H, component='NoExiste')
    r2 = dsg(command='set', path=H, component='NoExiste', prop='Left', value='1')
    check('H9 control: un nombre que no existe tampoco en el ancestro: DSGN-078 en get y en set',
          mc.es(r, 'SR_DESIGNER_COMPONENTE_NO_ESTA_FMT') and mc.es(r2, 'SR_DESIGNER_COMPONENTE_NO_ESTA_FMT')
          and open(H, 'rb').read() == a, (r[:200], r2[:200]))

    # --- H10 ----------------------------------------------------------------------
    H = caso('h10', con_label=True)
    r = dsg(command='set', path=H, component='Label9', parent='Panel1')
    ls = lineas(H)
    check('H10 set parent=Panel1 de un Label9 propio: inherited Panel1 y el Label9 dentro',
          not mc.fallo(r) and dentro(ls, 'inherited Panel1: TPanel', 'object Label9: TLabel'), (r[:400], ls))

    # --- H11-H14: los de un frame en linea, sin bloque ---------------------------
    M = caso_marco('h11')
    r = dsg(command='set', path=M, component='Marco1.Dentro', prop='Left', value='20')
    ls = lineas(M)
    check('H11 set Marco1.Dentro Left=20 sin bloque: inline Marco1 > inherited PanelF > inherited Dentro > '
          'Left = 20 (DSGN-171, que nombra el frame)',
          not mc.fallo(r) and mc.es(r, 'SN_DESIGNER_BLOQUES_HEREDADOS_FMT') and 'frame Marco1' in r
          and dentro(ls, 'inline Marco1: TMarco', 'inherited PanelF: TPanel')
          and dentro(ls, 'inherited PanelF: TPanel', 'inherited Dentro: TButton')
          and dentro(ls, 'inherited Dentro: TButton', 'Left = 20'), (r[:400], ls))
    r = dsg(command='lint', path=M)
    check('H11 ...y el lector del IDE lo carga (lint CLEAN)', mc.es(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:300])
    M = caso_marco('h12')
    a = open(M, 'rb').read()
    r = dsg(command='get', path=M, component='Marco1.Fuera')
    check('H12 get Marco1.Fuera sin bloque: DSGN-172 del frame, con sus lineas como lo carga el IDE (Top = 70)',
          not mc.fallo(r) and mc.es(r, 'SN_DESIGNER_HEREDADO_SIN_BLOQUE_FMT') and 'frame Marco1' in r
          and re.search(r'Top = 70\b', r) is not None and open(M, 'rb').read() == a, r[:400])
    r = dsg(command='delete', path=M, component='Marco1.Dentro')
    check('H13 delete Marco1.Dentro sin bloque: DSGN-083 (se borra en el frame), como con su bloque; nada escrito',
          mc.abre(r, 'SR_DESIGNER_DENTRO_DE_INLINE_FMT') and open(M, 'rb').read() == a, r[:300])
    r = dsg(command='insert', path=M, classname='TButton', component='Button9', parent='Marco1.PanelF')
    check('H14 insert parent=Marco1.PanelF sin bloque: DSGN-083, nada escrito',
          mc.abre(r, 'SR_DESIGNER_DENTRO_DE_INLINE_FMT') and open(M, 'rb').read() == a, r[:300])

    # --- H15-H17: before=/after= con un heredado sin bloque de referencia --------
    H = caso('h15', con_label=True, con_boton=True)
    a = open(H, 'rb').read()
    r = dsg(command='set', path=H, component='Button7', before='Panel1')
    check('H15 Button7 before=Panel1 (heredado sin bloque): DSGN-136 con el orden del IDE (lo heredado se crea '
          'antes), no DSGN-078; nada escrito',
          mc.abre(r, 'SR_DESIGNER_ORDEN_EL_IDE_FMT') and 'Label9, Panel1, Button7' in r
          and open(H, 'rb').read() == a, r[:400])
    r = dsg(command='set', path=H, component='Label9', before='Panel1')
    check('H16 Label9 before=Panel1: ya esta (los graficos antes que las ventanas), en la 1 de 2 del FICHERO '
          '(DSGN-141); nada escrito',
          mc.es(r, 'SN_DESIGNER_ORDEN_YA_ESTA_FMT') and 'position 1 of 2' in r and open(H, 'rb').read() == a,
          r[:300])
    H = caso('h17', con_boton=True, con_boton8=True)
    r = dsg(command='set', path=H, component='Button8', after='Panel1')
    ls = lineas(H)
    j = mc.como_json(r)
    check('H17 Button8 after=Panel1: delante de Button7 (el primero de los propios va justo detras de lo '
          'heredado), SIN bloque de Panel1 (el IDE no escribe uno que no difiere), index 1 de 2 y su linea',
          not mc.fallo(r) and antes(ls, 'object Button8: TButton', 'object Button7: TButton')
          and not any(l.strip().startswith('inherited Panel1') for l in ls)
          and j.get('index') == 1 and j.get('of') == 2 and 0 < j.get('line', 0) <= len(ls)
          and ls[j.get('line', 0) - 1].strip() == 'object Button8: TButton', (r[:400], ls))
    r = dsg(command='lint', path=H)
    check('H17 ...y el lector del IDE lo carga (lint CLEAN)', mc.es(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:300])
finally:
    srv.cierra()
    print('atomos RTL nuevos de procesos muertos:', mc.atomos_rtl_dejados(antes_atomos))
    try:
        mc.fin('bateria de lo heredado sin bloque (A16-G1)')
    finally:
        mc.borra(BASE)
