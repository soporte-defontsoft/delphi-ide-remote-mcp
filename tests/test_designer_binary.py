"""E2E battery - binary .dfm (VCL) read on the fly and converted on purpose.

A legacy form saved in binary left an agent blind (Hermes, 2026-09-24): the
designer refused it and delphi_search saw no text. Now Lsp.DesignerBin (the
RTL's own ObjectResourceToText / ObjectTextToResource, what the IDE runs on
"View as Text" and on save) reads a binary .dfm on the fly everywhere that
reads, and delphi_designer to-text / to-binary convert it on disk, backup
first. Editing a binary directly stays refused, pointing at to-text.

The binary fixture is made by the server itself (to-binary of a text form),
so the battery measures the RTL path both ways without convert.exe; the
second to-binary must reproduce the first byte for byte.

Usage:  python tests/test_designer_binary.py [path-to-DelphiLspMcp.exe]
"""
import json, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer-binary')
EXE = mc.copia_exe(BASE)

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='dgb')
call = srv.call

def J(t):
    try: return json.loads(t)
    except Exception: return {}

# ---- fixture: a small VCL form in TEXT, then the server makes the binary
DFM = os.path.join(BASE, 'Legacy.dfm')
TEXT = """object FormLegacy: TFormLegacy
  Left = 274
  Top = 75
  Caption = 'Legacy'
  ClientHeight = 200
  ClientWidth = 300
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  TextHeight = 13
  object Label1: TLabel
    Left = 16
    Top = 16
    Width = 40
    Height = 13
    Caption = 'Nombre'
  end
  object Edit1: TEdit
    Left = 16
    Top = 40
    Width = 200
    Height = 21
    TabOrder = 0
  end
  object Button1: TButton
    Left = 16
    Top = 80
    Width = 75
    Height = 25
    Caption = 'Aceptar'
    TabOrder = 1
  end
end
"""
open(DFM, 'w', encoding='utf-8', newline='\r\n').write(TEXT)

r = call('delphi_designer', {'command': 'to-binary', 'path': DFM})
check('to-binary convierte el texto', mc.abre(r, 'SN_DESIGNER_TOBINARY_FMT'), r[:200])
b1 = open(DFM, 'rb').read()
# la cabecera de recurso entera, FF 0A 00 (DesignerShapeOf): solo $FF tambien
# es el BOM de un texto UTF-16 LE (la regla vieja; segunda revision de la 1.17.0)
check('en disco: envoltorio de recurso FF 0A 00 con TPF0 dentro', b1[:3] == b'\xff\x0a\x00' and b'TPF0' in b1[:64], b1[:24])
check('copia previa en __delphi-patch', os.path.isdir(os.path.join(BASE, mc.PAPELERA)), '')
r = call('delphi_designer', {'command': 'to-binary', 'path': DFM})
check('to-binary dos veces: nada que hacer', mc.abre(r, 'SN_DESIGNER_ALREADY_FMT'), r[:120])

# ---- reading the binary on the fly, everywhere that reads
r = call('delphi_read', {'path': DFM, 'fromline': 1, 'toline': 3})
check('delphi_read lee el binario como texto', '1|object FormLegacy: TFormLegacy' in r, r[:300])
check('delphi_read lo dice: BINARIO en disco + to-text', mc.es(r, 'SN_READ_BINARY_DESIGNER') and 'to-text' in r, r[:200])
r = call('delphi_designer', {'command': 'tree', 'path': DFM})
j = J(r)
names = [c.get('name') for c in j.get('root', {}).get('children', [])]
check('tree del binario: los 3 hijos', names == ['Label1', 'Edit1', 'Button1'], r[:300])
check('tree lleva binaryOnDiskNote', 'binaryOnDiskNote' in j, list(j.keys()))
r = call('delphi_designer', {'command': 'get', 'path': DFM, 'component': 'Button1'})
check('get del binario: el bloque del boton', "Caption = 'Aceptar'" in r, r[:300])
check('get lleva la nota (texto)', mc.es(r, 'SN_DESIGNER_BINARY_VIEW') and 'to-text' in r, r[-200:])
r = call('delphi_designer', {'command': 'lint', 'path': DFM})
check('lint del binario contesta (no rechaza)', mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT') and 'Legacy.dfm' in r, r[:200])
r = call('delphi_designer', {'command': 'layout', 'path': DFM})
j = J(r)
check('layout del binario: clientWidth 300', j.get('clientWidth') == 300, r[:200])
r = call('delphi_search', {'path': BASE, 'query': 'object Edit1'})
check('delphi_search encuentra texto dentro del binario', '"total":1' in r.replace(' ', '') and 'Legacy.dfm' in r, r[:300])
r = call('delphi_projects', {'root': BASE})  # no projects here: just must not choke on the binary
check('un binario no rompe a quien lista', J(r).get('total') == 0 and J(r).get('projects') == [], r[:120])

# ---- editing the binary directly stays refused, pointing at to-text
r = call('delphi_edit', {'path': DFM, 'old': '  Left = 274', 'new': '  Left = 275'})
check('delphi_edit sobre el binario: RECHAZADO con TPF0/BINARIO', mc.rechazado(r) and mc.es(r, 'SR_EDIT_BINARIO_FIRMA_TPF0_ENVOLTORIO_FMT') and 'TPF0' in r, r[:200])
check('...y apunta a to-text', 'to-text' in r, r[:200])
check('el fichero no se toco', open(DFM, 'rb').read() == b1, '')

# ---- to-text, edit as text, to-binary reproduces the bytes
r = call('delphi_designer', {'command': 'to-text', 'path': DFM})
check('to-text convierte a texto', mc.abre(r, 'SN_DESIGNER_TOTEXT_FMT'), r[:200])
t = open(DFM, 'rb').read()
check('en disco: texto, empieza por object, CRLF', t.startswith(b'object FormLegacy') and b'\r\n' in t and t[:3] != b'\xff\x0a\x00', t[:40])
r = call('delphi_designer', {'command': 'to-text', 'path': DFM})
check('to-text dos veces: nada que hacer', mc.abre(r, 'SN_DESIGNER_ALREADY_FMT'), r[:120])
r = call('delphi_read', {'path': DFM, 'fromline': 1, 'toline': 2})
check('delphi_read del texto: sin nota de binario', not mc.es(r, 'SN_READ_BINARY_DESIGNER') and '1|object FormLegacy: TFormLegacy' in r, r[:200])
r = call('delphi_edit', {'path': DFM, 'old': '  Left = 274', 'new': '  Left = 275'})
check('editable como cualquier .dfm tras to-text', mc.abre(r, 'SK_EDIT_ESCRITO_EN_FMT'), r[:120])
r = call('delphi_edit', {'path': DFM, 'old': '  Left = 275', 'new': '  Left = 274'})
r = call('delphi_designer', {'command': 'to-binary', 'path': DFM})
b2 = open(DFM, 'rb').read()
check('viaje redondo: el binario se reproduce byte a byte', b2 == b1, '%d vs %d bytes' % (len(b2), len(b1)))

# ---- accents: to-text writes #NNN like the IDE; to-binary reads a raw one
# through ANSI (what the RTL parser and the IDE expect) and refuses what ANSI
# cannot hold. Measured 2026-09-24: feeding the parser UTF-8 turned an 'o'
# with an accent into #195#179.
# 4.1 de la 1.18.0 (David, 9-oct-2026): un form de texto SIN BOM es ANSI,
# lo sea o no como UTF-8 - asi lo leen dcc (medido en los bytes del exe:
# 'Configuracion' acentuado en UTF-8 sin BOM se ejecuta como ...Ã³n), el
# parser de forms del IDE y el renderizador; el IDE lo llama 'Text Form' y
# escribe sus acentos en CP1252 crudo (medido por David: 0xF2). El servidor
# lo leia como UTF-8 y su to-binary daba otra cadena que la que compila dcc.
ESPERADO = {'utf8': b"'Configuraci'#195#179'n'", 'utf8bom': b"'Configuraci'#243'n'",
            'cp1252': b"'Configuraci'#243'n'"}
for nombre, enc in (('utf8', 'utf-8'), ('utf8bom', 'utf-8-sig'), ('cp1252', 'cp1252')):
    RAW = os.path.join(BASE, 'Raw_%s.dfm' % nombre)
    open(RAW, 'wb').write(("object FormR: TFormR\r\n  Caption = 'Configuración'\r\n"
                           "  ClientHeight = 10\r\n  ClientWidth = 10\r\nend\r\n").encode(enc))
    r = call('delphi_designer', {'command': 'to-binary', 'path': RAW})
    check('acento en crudo (%s): to-binary acepta' % nombre, mc.abre(r, 'SN_DESIGNER_TOBINARY_FMT'), r[:160])
    r = call('delphi_designer', {'command': 'to-text', 'path': RAW})
    t = open(RAW, 'rb').read()
    check('acento en crudo (%s): vuelve como %s (lo que compila dcc), ASCII puro' % (nombre, ESPERADO[nombre].decode()),
          ESPERADO[nombre] in t and all(x < 128 for x in t), t[:120])
# ...y se LEE como lo lee dcc, y un acento nuevo se escribe como el IDE
SINBOM = os.path.join(BASE, 'SinBom.dfm')
open(SINBOM, 'wb').write("object FormS: TFormS\r\n  Caption = 'Configuración'\r\n  Hint = 'nada'\r\nend\r\n".encode('utf-8'))
r = call('delphi_read', {'path': SINBOM})
check('un .dfm de texto UTF-8 SIN BOM se lee en ANSI, como dcc: encoding=cp1252 y ...Ã³n',
      'encoding=cp1252' in r and "Configuraci\u00c3\u00b3n" in r, r[:300])
ASCIIDFM = os.path.join(BASE, 'SoloAscii.dfm')
open(ASCIIDFM, 'wb').write(b"object FormA: TFormA\r\n  Caption = 'nada'\r\nend\r\n")
r = call('delphi_edit', {'path': ASCIIDFM, 'old': "  Caption = 'nada'", 'new': "  Caption = 'Acción'"})
check('un acento nuevo en un .dfm ASCII sin BOM va en CP1252 crudo, sin BOM, como lo guarda el IDE',
      open(ASCIIDFM, 'rb').read() == b"object FormA: TFormA\r\n  Caption = 'Acci\xf3n'\r\nend\r\n",
      (r[:200], open(ASCIIDFM, 'rb').read()))
# lo que YA esta se escribe con sus mismos bytes, tambien los que en ANSI
# caen en los cinco huecos de CP1252 (81 8D 8F 90 9D): la A acentuada en
# UTF-8 es C3 81, la I C3 8D, la comilla de cierre E2 80 9D. Se leian y no se
# podian escribir: editar OTRA linea se negaba (EDIT-078 por un U+0081 que
# nadie habia tecleado; revisor propio, 9-oct-2026)
HUECOS = os.path.join(BASE, 'Huecos.dfm')
HUECOS_B = ("object FormH: TFormH\r\n  Caption = 'Árbol Índice ”fin'\r\n"
            "  Hint = 'nada'\r\nend\r\n").encode('utf-8')
open(HUECOS, 'wb').write(HUECOS_B)
r = call('delphi_edit', {'path': HUECOS, 'old': "  Hint = 'nada'", 'new': "  Hint = 'otra'"})
check('un .dfm UTF-8 sin BOM con una A acentuada (C3 81): editar OTRA linea escribe, y lo demas byte a byte',
      open(HUECOS, 'rb').read() == HUECOS_B.replace(b"'nada'", b"'otra'"), (r[:200], open(HUECOS, 'rb').read()[:80]))
# ...y el mismo hueco en un form CP1252 de siempre (un 81 crudo): este no
# depende de leer los forms en ANSI, y es el que cae sin el arreglo del codec
# (el de arriba, con la regla vieja, se leia como UTF-8 y no pasaba por el)
HUECO_ANSI = os.path.join(BASE, 'HuecoAnsi.dfm')
HUECO_ANSI_B = b"object FormG: TFormG\r\n  Caption = 'Gesti\xf3n \x81'\r\n  Hint = 'nada'\r\nend\r\n"
open(HUECO_ANSI, 'wb').write(HUECO_ANSI_B)
r = call('delphi_edit', {'path': HUECO_ANSI, 'old': "  Hint = 'nada'", 'new': "  Hint = 'otra'"})
check('un .dfm CP1252 con un byte 81 (de los que la pagina no define): editar OTRA linea escribe, byte a byte',
      open(HUECO_ANSI, 'rb').read() == HUECO_ANSI_B.replace(b"'nada'", b"'otra'"), (r[:200], open(HUECO_ANSI, 'rb').read()[:80]))
# (CON BOM: sin el, un form es ANSI - 4.1 de la 1.18.0 - y esos mismos bytes
# son 'ok âœ”', que si cabe y es lo que compila dcc)
FUERA = os.path.join(BASE, 'FueraAnsi.dfm')
FUERA_B = "object FormF: TFormF\r\n  Caption = 'ok ✔'\r\n  ClientHeight = 10\r\n  ClientWidth = 10\r\nend\r\n".encode('utf-8-sig')
open(FUERA, 'wb').write(FUERA_B)
r = call('delphi_designer', {'command': 'to-binary', 'path': FUERA})
check('caracter fuera de ANSI en crudo: to-binary RECHAZADO con #NNNN', mc.rechazado(r) and '#NNNN' in r, r[:200])
check('...y el fichero no se toco', open(FUERA, 'rb').read() == FUERA_B, '')
# un NOMBRE no ASCII (4.1 de la 1.18.0, medido): el parser de la RTL no lo
# lee (salia su EParserError 'Identifier expected on line 3') y dcc si, en
# UTF-8: se dice cual, en que linea y que hacer, y no se escribe
NOASCII = os.path.join(BASE, 'NombreNoAscii.dfm')
NOASCII_B = ("object FormN: TFormN\r\n  ClientHeight = 10\r\n  object Bot\u00f3n\u00d1: TButton\r\n    Left = 8\r\n"
             "  end\r\nend\r\n").encode('utf-8-sig')
open(NOASCII, 'wb').write(NOASCII_B)
r = call('delphi_designer', {'command': 'to-binary', 'path': NOASCII})
check('un nombre de componente no ASCII: to-binary DSGN-120 con el nombre y su linea, sin escribir',
      mc.abre(r, 'SR_DSGN_NOMBRE_NO_ASCII_BINARIO_FMT') and 'Bot\u00f3n\u00d1 (line 3)' in r and
      open(NOASCII, 'rb').read() == NOASCII_B, r[:300])

# ---- the IDE can save a TEXT form in UTF-16 (editor encoding menu): it
# starts with FF FE, and "starts with $FF" used to mean binary. The real
# binary starts with the resource header FF 0A 00.
U16 = os.path.join(BASE, 'Utf16.dfm')
open(U16, 'wb').write("object FormU: TFormU\r\n  Caption = 'u'\r\n  ClientHeight = 10\r\n  ClientWidth = 10\r\nend\r\n".encode('utf-16'))
check('fixture UTF-16 LE empieza por FF FE', open(U16, 'rb').read()[:2] == b'\xff\xfe', '')
r = call('delphi_designer', {'command': 'to-text', 'path': U16})
check('texto UTF-16 NO se toma por binario (to-text: ya es texto)', mc.abre(r, 'SN_DESIGNER_ALREADY_FMT'), r[:160])
check('...y el fichero no se toco', open(U16, 'rb').read()[:2] == b'\xff\xfe', '')

# ---- and a UTF-16 text form is READ, EDITED and WRITTEN BACK as UTF-16 by ONE
# detector (Lsp.Patch.DetectEnc). Until 24-sep two detectors lived side by
# side: search read UTF-16 through its own BOM branch, delphi_read did not
# (and its NUL-byte gate took UTF-16 for a binary). LE with an accent, BE too.
open(U16, 'wb').write("object FormU: TFormU\r\n  Caption = 'acento: c\u00f3digo'\r\n  ClientHeight = 10\r\n  ClientWidth = 10\r\nend\r\n".encode('utf-16'))
r = call('delphi_read', {'path': U16})
check('delphi_read lee el UTF-16 LE y lo dice', 'encoding=utf16-le' in r and "Caption = 'acento: c\u00f3digo'" in r, r[:200])
check('...con sus CRLF y sus 2 bytes altos (medido sobre el cuerpo UTF-8; 1.13.0: limpio, "audit=clean")', 'eol=CRLF' in r and 'audit=clean accents=2' in r, r[:200])
r = call('delphi_search', {'root': U16, 'query': 'c\u00f3digo'})
check('delphi_search lo encuentra con el acento', '"total":1' in r and '"line":2' in r, r[:200])
r = call('delphi_edit', {'path': U16, 'old': '  ClientHeight = 10', 'new': '  ClientHeight = 11'})
check('delphi_edit edita el UTF-16 LE', mc.abre(r, 'SK_EDIT_ESCRITO_EN_FMT') and 'encoding=utf16-le' in r, r[:200])
b = open(U16, 'rb').read()
check('...y en disco sigue UTF-16 LE con BOM, CRLF, acento y el cambio', b[:2] == b'\xff\xfe' and b[2:].decode('utf-16-le') == "object FormU: TFormU\r\n  Caption = 'acento: c\u00f3digo'\r\n  ClientHeight = 11\r\n  ClientWidth = 10\r\nend\r\n", b[:60].hex())
r = call('delphi_designer', {'command': 'lint', 'path': U16})
check('delphi_designer lint sobre el UTF-16: limpio', mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:200])
U16BE = os.path.join(BASE, 'notas_be.txt')
open(U16BE, 'wb').write(b'\xfe\xff' + 'uno\r\ndos: canci\u00f3n\r\ntres\r\n'.encode('utf-16-be'))
r = call('delphi_textedit', {'path': U16BE, 'old': 'tres', 'new': 'tres (editada)'})
check('delphi_textedit edita un UTF-16 BE (antes: "parece BINARIO")', 'encoding=utf16-be' in r and not mc.fallo(r), r[:200])
b = open(U16BE, 'rb').read()
check('...y en disco sigue UTF-16 BE con BOM y el acento', b[:2] == b'\xfe\xff' and b[2:].decode('utf-16-be') == 'uno\r\ndos: canci\u00f3n\r\ntres (editada)\r\n', b[:40].hex())
EXE_BIN = os.path.join(BASE, 'no_texto.bin')
open(EXE_BIN, 'wb').write(b'MZ\x90\x00\x03\x00\x00\x00' * 64)
r = call('delphi_read', {'path': EXE_BIN})
check('un binario de verdad sigue RECHAZADO por NUL (regla unica, 64 KB)', mc.rechazado(r) and mc.es(r, 'SR_EDIT_FICHERO_BINARIO_NUL_FMT'), r[:200])
r = call('delphi_textedit', {'path': EXE_BIN, 'old': 'MZ', 'new': 'ZZ'})
check('...tambien en delphi_textedit, la misma regla', mc.rechazado(r) and mc.es(r, 'SR_TEXT_PARECE_BINARIO_FMT'), r[:200])

# ---- .fmx is always text; a damaged binary is refused with the reason
FMX = os.path.join(BASE, 'Vista.fmx')
open(FMX, 'w', encoding='utf-8', newline='\r\n').write("object Form1: TForm1\n  Caption = 'x'\nend\n")
r = call('delphi_designer', {'command': 'to-binary', 'path': FMX})
check('.fmx: to-binary rechazado (siempre texto)', mc.rechazado(r) and mc.es(r, 'SR_DESIGNER_FMX_ALWAYS_TEXT') and '.fmx' in r, r[:200])
r = call('delphi_designer', {'command': 'to-text', 'path': FMX})
check('.fmx: to-text rechazado (siempre texto)', mc.rechazado(r) and mc.es(r, 'SR_DESIGNER_FMX_ALWAYS_TEXT') and '.fmx' in r, r[:200])
BAD = os.path.join(BASE, 'Roto.dfm')
open(BAD, 'wb').write(b'\xff\x0a\x00TROTO\x00\x30\x10\x10\x00\x00\x00TPF0basura sin sentido')
r = call('delphi_designer', {'command': 'tree', 'path': BAD})
check('binario danado: RECHAZADO con motivo', mc.abre(r, 'SR_DSGN_BINARIO_DANADO_FMT') and 'Stream read error' in r, r[:200])
r = call('delphi_read', {'path': BAD})
check('delphi_read de un binario danado: RECHAZADO', mc.rechazado(r), r[:200])
r = call('delphi_designer', {'command': 'to-text', 'path': BAD})
check('to-text de un binario danado: RECHAZADO, fichero intacto', mc.rechazado(r) and open(BAD, 'rb').read().startswith(b'\xff\x0a\x00TROTO'), r[:200])

# ---- T7 (segunda revision de la 1.17.0): binarios escritos por el IDE, no por
# nuestro escritor. Todos los de arriba los escribe to-binary, asi que si
# nuestra cabecera de recurso se desviara de la del IDE nada lo veria. Dos de
# la instalacion: un form con su recurso (FF 0A 00, banderas 0x1030) y uno
# heredado (el prefijo de un inherited). to-text y to-binary tienen que
# devolver los MISMOS bytes. Es una GUARDA (la 1.17.0 ya los devuelve iguales,
# medido el 9-oct): vigila que nuestro escritor no se aparte del IDE.
import glob, shutil
for rel in (r'DUnit\Contrib\XPGen\xpmain.dfm', r'DUnit\examples\embeddable\EmbeddableGUITestRunner.dfm'):
    orig = sorted(glob.glob(os.path.join(r'C:\Program Files (x86)\Embarcadero\Studio', '*', 'source', rel)))
    if not orig:
        print('NOTA: %s no esta en esta instalacion; T7 saltado para el' % rel)
        continue
    copia = os.path.join(BASE, 'ide-' + os.path.basename(rel))
    shutil.copy(orig[-1], copia)
    ide = open(copia, 'rb').read()
    r1 = call('delphi_designer', {'command': 'to-text', 'path': copia})
    r2 = call('delphi_designer', {'command': 'to-binary', 'path': copia})
    check('T7 %s del IDE: to-text y to-binary devuelven sus mismos bytes' % os.path.basename(rel),
          mc.abre(r1, 'SN_DESIGNER_TOTEXT_FMT') and mc.abre(r2, 'SN_DESIGNER_TOBINARY_FMT') and
          open(copia, 'rb').read() == ide, (r1[:120], r2[:120]))

# la regla de ida y vuelta de los escritores tambien en to-binary (revisor
# propio de la 4.1, 9-oct-2026): un form ROTO -un BOM de UTF-8 con el cuerpo
# en CP1252- se convertiria, con el lector tolerante, con U+FFFD donde estan
# sus acentos (la 1.17 reventaba: SYS-006). Se niega (EDIT-038) sin tocar un byte
ROTO = os.path.join(BASE, 'FRoto.dfm')
_ROTO = b"\xef\xbb\xbfobject FRoto: TForm\r\n  Caption = 'gesti\xf3n'\r\nend\r\n"
open(ROTO, 'wb').write(_ROTO)
r = call('delphi_designer', {'command': 'to-binary', 'path': ROTO})
check('to-binary de un form roto (BOM de UTF-8 y cuerpo CP1252): EDIT-038 y no toca un byte',
      mc.es(r, 'SR_EDIT_BYTES_NO_VUELVEN_FMT') and open(ROTO, 'rb').read() == _ROTO, r[:300])

# un BINARIO con un NOMBRE no ASCII (TPF0 a mano: to-binary no los escribe,
# DSGN-120): ObjectBinaryToText pone delante el BOM de UTF-8, y el conversor lo
# dejaba en el texto - tree no leia la raiz y to-text se negaba con EDIT-122
# (revisor propio de la 4.1, medido). to-text lo escribe en UTF-8 CON BOM, como
# el IDE
NOMB = os.path.join(BASE, 'FNombre.dfm')
open(NOMB, 'wb').write(b'TPF0' + b'\x05TForm' + b'\x06Bot\xc3\xb3n' + b'\x00\x00')
r = call('delphi_designer', {'command': 'tree', 'path': NOMB})
check('tree de un binario con un nombre no ASCII: lee su raiz (TForm)',
      'TForm' in r and '"class":""' not in r.replace(' ', ''), r[:300])
r = call('delphi_designer', {'command': 'to-text', 'path': NOMB})
_b = open(NOMB, 'rb').read()
check('to-text de un binario con un nombre no ASCII: UTF-8 CON BOM, como el IDE (era EDIT-122)',
      mc.abre(r, 'SN_DESIGNER_TOTEXT_FMT') and _b.startswith(b'\xef\xbb\xbfobject Bot\xc3\xb3n: TForm'),
      (r[:200], _b[:40]))

srv.mata()
mc.fin('designer-binary battery')
