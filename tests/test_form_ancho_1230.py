# -*- coding: utf-8 -*-
"""Un form de TEXTO en UTF-16 o UTF-32 NO lo carga el IDE (A28 de la 1.23).

Medido con el juez el 24-oct-2026 (David, en el IDE): el editor deja GUARDAR
un .dfm en UTF-16 LE, UTF-16 BE o UTF-32, y al reabrirlo el disenador dice
"Error creating form in Unit2.dfm: Invalid stream format"; dcc lo niega
(E2161). La RTL lo dice por construccion (System.Classes): TestStreamFormat
toma un $FF inicial por binario y FE FF / 00 00 FE FF por desconocido, y
TParser niega todo BOM que no sea el de UTF-8. El servidor IMITABA al juez:
convertia el form (UTF-16 a UTF-8, UTF-32 a UTF-16) ANTES de preguntar al
parser, y asi lint daba CLEAN, preview lo dibujaba, los escritores escribian
y DSGN-121 decia "The IDE opens it". Ahora el parser recibe los bytes tal
cual y la respuesta dice la causa y la salida: command=to-text, que lo deja
como lo escribe el IDE (David, 24-oct: un form asi ya no se abre en el IDE).

  L  lint de un form ancho (los cuatro): no CLEAN, con la salida
  P  preview: negado, sin PNG, con la salida
  S  set en UTF-16 LE / I insert en UTF-16 BE / D delete en UTF-32 LE: negados
     y el .dfm y el .pas intactos
  B  to-binary de un form ancho: negado con la salida, intacto
  T  to-text de un form ancho: el texto que escribe el IDE (ASCII, el acento
     como #243), sin BOM ancho, con copia; lint CLEAN despues; la unit (en
     UTF-8 con BOM, como la guarda el IDE) byte a byte igual
  T2 (guarda) to-text de un form UTF-8 con BOM: "ya es texto"
  T3 to-text de un UTF-16 con medio caracter: DSGN-147 y el form intacto
  T4 to-text de un .fmx en UTF-16: tambien se convierte (DSGN-013 lo negaba:
     "a .fmx is always text", y la salida de DSGN-122 era un muro)
  E  delphi_edit de un form UTF-16 LE: escribe (es el editor de texto) y la
     nota dice la salida, no "The IDE opens it"
  A1 preview de una hija UTF-8 con el ANCESTRO en UTF-32: nombra UBase.dfm
     como el que el IDE no carga, no "no form file"
  A2 lo mismo con el ancestro en UTF-16 LE (produccion lo dibujaba con el)
  A3 insert en esa hija (ancestro UTF-32): la nota nombra UBase.dfm
  G  (guardas) UTF-8 con BOM y ANSI: lint CLEAN, preview dibuja, set escribe,
     to-binary convierte

Uso:  python tests/test_form_ancho_1230.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('form_ancho_1230')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)

SALIDA = 'command=to-text'
ANCHAS = (('utf16le', b'\xff\xfe', 'utf-16-le'), ('utf16be', b'\xfe\xff', 'utf-16-be'),
          ('utf32le', b'\xff\xfe\x00\x00', 'utf-32-le'), ('utf32be', b'\x00\x00\xfe\xff', 'utf-32-be'))
FORM = ("object FormA: TFormA\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'Configuración'\r\n"
        "  ClientHeight = 100\r\n  ClientWidth = 200\r\n"
        "  object Button1: TButton\r\n    Left = 8\r\n    Top = 8\r\n    Width = 75\r\n    Height = 25\r\n"
        "    Caption = 'Button1'\r\n    TabOrder = 0\r\n  end\r\nend\r\n")
USES = '  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls'


def unidad(d, nombre, clase, campos='    Button1: TButton;\r\n', ancestro='TForm', mas_uses=''):
    open(os.path.join(d, nombre + '.pas'), 'wb').write(
        ('unit %s;\r\n\r\ninterface\r\n\r\nuses\r\n%s%s;\r\n\r\ntype\r\n  %s = class(%s)\r\n%s  end;\r\n\r\n'
         'implementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n' % (nombre, USES, mas_uses, clase, ancestro, campos)).encode('ascii'))


def form(d, nombre, contenido):
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, nombre + '.dfm')
    open(p, 'wb').write(contenido)
    unidad(d, nombre, 'TFormA')
    return p


def ancho(d, nombre, bom, codec, texto=FORM):
    return form(d, nombre, bom + texto.encode(codec, 'surrogatepass'))


def bytes_de(p):
    return open(p, 'rb').read()


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='form-ancho-1230', t=600)


def dsg(**a):
    return srv.call('delphi_designer', a, t=300)


def pngs(d):
    return [f for f in os.listdir(d) if f.lower().endswith('.png')] if os.path.isdir(d) else []


try:
    for enc, bom, codec in ANCHAS:
        d = os.path.join(JAIL, enc)
        p = ancho(d, 'U' + enc, bom, codec)
        r = dsg(command='lint', path=p)
        check('L %s: lint no da CLEAN y dice la salida (%s)' % (enc, SALIDA),
              'DSGN-020' not in r and SALIDA in r, r[:400])
        out = os.path.join(d, 'png')
        os.makedirs(out)
        r = dsg(command='preview', path=p, out=out + '\\')
        check('P %s: preview negado, sin PNG, con la salida' % enc,
              mc.rechazado(r) and not pngs(out) and SALIDA in r, r[:400])
        antes = bytes_de(p)
        r = dsg(command='to-binary', path=p)
        check('B %s: to-binary negado con la salida, el form intacto' % enc,
              mc.rechazado(r) and SALIDA in r and bytes_de(p) == antes, r[:400])

    # S, I, D: los escritores del disenador no escriben un form que el IDE no carga
    for etiqueta, (enc, bom, codec), args in (
            ('S set', ANCHAS[0], {'command': 'set', 'component': 'Button1', 'prop': 'Left', 'value': '20'}),
            ('I insert', ANCHAS[1], {'command': 'insert', 'classname': 'TButton', 'component': 'Button2'}),
            ('D delete', ANCHAS[2], {'command': 'delete', 'component': 'Button1'})):
        d = os.path.join(JAIL, 'escribe_' + enc)
        p = ancho(d, 'UE' + enc, bom, codec)
        pas = p[:-4] + '.pas'
        antes, antes_pas = bytes_de(p), bytes_de(pas)
        r = dsg(path=p, **args)
        check('%s en %s: negado con la salida; el .dfm y el .pas intactos' % (etiqueta, enc),
              mc.rechazado(r) and SALIDA in r and bytes_de(p) == antes and bytes_de(pas) == antes_pas, r[:400])

    # T: to-text de un form ancho = el texto que escribe el IDE
    for enc, bom, codec in ANCHAS:
        d = os.path.join(JAIL, 'totext_' + enc)
        p = ancho(d, 'UT' + enc, bom, codec)
        pas = p[:-4] + '.pas'
        sin_bom = bytes_de(pas)  # leido ANTES: open('wb') lo vacia
        open(pas, 'wb').write(b'\xef\xbb\xbf' + sin_bom)  # la unit en UTF-8 con BOM, como la guarda el IDE
        antes_pas = bytes_de(pas)
        r = dsg(command='to-text', path=p)
        b = bytes_de(p)
        sin_bom_ancho = not (b.startswith(b'\xff\xfe') or b.startswith(b'\xfe\xff') or b.startswith(b'\x00\x00\xfe\xff'))
        texto = b.decode('utf-8-sig', 'replace')
        check('T %s: to-text lo deja como lo escribe el IDE (sin BOM ancho, el acento como #243, Button1 dentro)' % enc,
              not mc.rechazado(r) and sin_bom_ancho and "Caption = 'Configuraci'#243'n'" in texto and
              'object Button1: TButton' in texto and texto.count('\r\n') == texto.count('\n'), (r[:300], b[:80]))
        r2 = dsg(command='lint', path=p)
        check('T %s: ...y lint lo da por CLEAN despues' % enc, 'DSGN-020' in r2, r2[:300])
        check('T %s: ...y la unit (UTF-8 con BOM) no se toca: byte a byte igual' % enc, bytes_de(pas) == antes_pas, '')

    d = os.path.join(JAIL, 'totext_utf8')
    p = form(d, 'UT8', b'\xef\xbb\xbf' + FORM.encode('utf-8'))
    r = dsg(command='to-text', path=p)
    check('T2 (guarda) to-text de un form UTF-8 con BOM: ya es texto, nada cambia',
          mc.abre(r, 'SN_DESIGNER_ALREADY_FMT'), r[:300])

    d = os.path.join(JAIL, 'totext_suelto')
    p = ancho(d, 'UTS', b'\xff\xfe', 'utf-16-le', FORM.replace("'Button1'", "'Bot\ud800n'"))
    antes = bytes_de(p)
    r = dsg(command='to-text', path=p)
    check('T3 to-text de un UTF-16 con medio caracter: DSGN-147 y el form intacto',
          mc.rechazado(r) and mc.es(r, 'SR_DSGN_FORM_SUELTO_BINARIO_FMT') and bytes_de(p) == antes, r[:300])

    d = os.path.join(JAIL, 'totext_fmx')
    os.makedirs(d)
    FMX = os.path.join(d, 'UF.fmx')
    open(FMX, 'wb').write(b'\xff\xfe' + (
        "object FormF: TFormF\r\n  Left = 0\r\n  Top = 0\r\n  ClientHeight = 200\r\n  ClientWidth = 300\r\n"
        "  FormFactor.Width = 320\r\n  FormFactor.Height = 480\r\n  FormFactor.Devices = [Desktop]\r\n"
        "  DesignerMasterStyle = 0\r\n  object Button1: TButton\r\n    Position.X = 8.000000000000000000\r\n"
        "    Position.Y = 8.000000000000000000\r\n    TabOrder = 0\r\n    Text = 'Botón'\r\n  end\r\nend\r\n"
    ).encode('utf-16-le'))
    r = dsg(command='to-text', path=FMX)
    b = bytes_de(FMX)
    check('T4 to-text de un .fmx en UTF-16: se convierte al texto del IDE (sin BOM ancho, el acento como #243)',
          not mc.rechazado(r) and not b.startswith(b'\xff\xfe') and b"Text = 'Bot'#243'n'" in b and
          b'object Button1: TButton' in b, (r[:300], b[:60]))
    r = dsg(command='to-binary', path=FMX)
    check('T4 ...y to-binary de un .fmx sigue negado: FireMonkey no tiene binario (DSGN-013)',
          mc.abre(r, 'SR_DESIGNER_FMX_ALWAYS_TEXT'), r[:300])

    # E: delphi_edit es el editor de texto: escribe, y la nota dice la salida
    d = os.path.join(JAIL, 'edit')
    p = ancho(d, 'UED', b'\xff\xfe', 'utf-16-le')
    r = srv.call('delphi_edit', {'path': p, 'old': "    Caption = 'Button1'", 'new': "    Caption = 'Boton1'"})
    b = bytes_de(p)
    check('E delphi_edit en un form UTF-16 LE: escribe en UTF-16 LE y la nota dice la salida, no "The IDE opens it"',
          not mc.rechazado(r) and b.startswith(b'\xff\xfe') and "'Boton1'" in b[2:].decode('utf-16-le') and
          SALIDA in r and 'The IDE opens it' not in r, r[:500])

    # A: una hija en UTF-8 cuyo ANCESTRO esta en un form ancho
    BASE_DFM = ("object FormBase: TFormBase\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'Base'\r\n"
                "  ClientHeight = 200\r\n  ClientWidth = 300\r\n"
                "  object Panel1: TPanel\r\n    Left = 8\r\n    Top = 8\r\n    Width = 200\r\n    Height = 150\r\n"
                "    TabOrder = 0\r\n"
                "    object Button1: TButton\r\n      Left = 8\r\n      Top = 8\r\n      TabOrder = 0\r\n    end\r\n"
                "    object Button2: TButton\r\n      Left = 8\r\n      Top = 40\r\n      TabOrder = 1\r\n    end\r\n"
                "  end\r\nend\r\n")
    HIJA_DFM = ("inherited FormHija: TFormHija\r\n  Caption = 'Hija'\r\n  inherited Panel1: TPanel\r\n"
                "    inherited Button1: TButton\r\n    end\r\n  end\r\nend\r\n")

    def familia(d, bom, codec):
        os.makedirs(d)
        open(os.path.join(d, 'UBase.dfm'), 'wb').write(bom + BASE_DFM.encode(codec))
        unidad(d, 'UBase', 'TFormBase', '    Panel1: TPanel;\r\n    Button1: TButton;\r\n    Button2: TButton;\r\n')
        h = os.path.join(d, 'UHija.dfm')
        open(h, 'wb').write(HIJA_DFM.encode('ascii'))
        unidad(d, 'UHija', 'TFormHija', '', 'TFormBase', ', UBase')
        return h

    for etiqueta, (enc, bom, codec) in (('A1', ANCHAS[2]), ('A2', ANCHAS[0])):
        d = os.path.join(JAIL, 'familia_' + enc)
        h = familia(d, bom, codec)
        out = os.path.join(d, 'png')
        os.makedirs(out)
        r = dsg(command='preview', path=h, out=out + '\\')
        check('%s preview de una hija UTF-8 con el ancestro en %s: nombra UBase.dfm como el que el IDE no carga, '
              'con la salida' % (etiqueta, enc),
              'UBase.dfm' in r and SALIDA in r, r[:600])
    d = os.path.join(JAIL, 'familia_inserta')
    h = familia(d, ANCHAS[2][1], ANCHAS[2][2])
    r = dsg(command='insert', path=h, classname='TButton', component='Button9', parent='Panel1')
    check('A3 insert en una hija con el ancestro en UTF-32: la respuesta nombra UBase.dfm con la salida, '
          'no "no form file"',
          'UBase.dfm' in r and SALIDA in r and 'has no form file' not in r, r[:700])

    # G: guardas, lo que el IDE si carga sigue igual
    for etiqueta, contenido in (('UTF-8 con BOM', b'\xef\xbb\xbf' + FORM.encode('utf-8')),
                                ('ANSI', FORM.encode('cp1252'))):
        d = os.path.join(JAIL, 'guarda_' + etiqueta.split()[0].replace('-', ''))
        p = form(d, 'UG', contenido)
        r = dsg(command='lint', path=p)
        check('G %s: lint CLEAN' % etiqueta, 'DSGN-020' in r, r[:300])
        out = os.path.join(d, 'png')
        os.makedirs(out)
        r = dsg(command='preview', path=p, out=out + '\\')
        check('G %s: preview dibuja' % etiqueta, not mc.rechazado(r) and len(pngs(out)) == 1, r[:300])
        r = dsg(command='set', path=p, component='Button1', prop='Left', value='20')
        check('G %s: set escribe' % etiqueta, not mc.rechazado(r) and b'Left = 20' in bytes_de(p), r[:300])
        r = dsg(command='to-binary', path=p)
        check('G %s: to-binary convierte' % etiqueta, not mc.rechazado(r) and bytes_de(p)[:1] == b'\xff', r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('un form de texto ancho no lo carga el IDE: la causa y la salida, A28 de la 1.23')
