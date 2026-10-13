# -*- coding: utf-8 -*-
"""Un form de TEXTO en UTF-16 o UTF-32 lo abre el IDE y dcc no lo compila
(RLINK32, E2161, medido el 9-oct-2026): DSGN-121. Lo decian lint y los
escritores del disenador (insert/set/delete) y preview; delphi_edit, su tanda
(edits) y el changeset escriben el mismo form y lo callaban (1.18.2, punto 4,
B1; medido en produccion el 13-oct: delphi_edit sobre un .dfm UTF-16 escribia
sin la nota y designer set la daba). Ahora la nota tiene UN compositor
(Lsp.DesignerBin.NotaDeFormAncho) y la dice tambien el juicio del form de los
escritores genericos (Lsp.Patch.DesignerLint).

  W1 delphi_edit sobre un .dfm UTF-16 LE: escribe y dice DSGN-121
  W2 ...su tanda (edits): igual
  W3 delphi_changeset que edita el .dfm: igual
  W4 delphi_edit sobre un .dfm UTF-32 LE: igual
  W5 el control: delphi_edit sobre un .dfm UTF-8 con BOM no la dice
  W6 designer set la sigue diciendo (el compositor de antes, ahora el helper)

Y lo del revisor propio del punto 4 (13-oct):
  W7 una tanda que deja el parser quejandose (una cadena sin cerrar) dice la
     nota UNA vez: cada entrada la traia tras su *** (R5). Desde H6 (el juicio
     del form, una vez al final) el aviso del parser sale una vez tambien
  W8 un changeset que edita dos Unit1.dfm de dos carpetas da DOS notas, cada
     una en la linea de su ruta: se deduplicaba por el nombre (R6)
  W9 el gemelo de W7 en el changeset: dos pasos sobre un UTF-16, la nota UNA
     vez (R5, su lado del changeset; con H6, el juicio tambien)

Uso:  python tests/test_form_ancho_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('form_ancho_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

FORM = ("object FormW: TFormW\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'Ancho'\r\n"
        "  ClientHeight = 100\r\n  ClientWidth = 200\r\nend\r\n")
PAS = ("unit {u};\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms;\r\n\r\ntype\r\n  TFormW = class(TForm)\r\n"
       "  end;\r\n\r\nimplementation\r\n\r\n{{$R *.dfm}}\r\n\r\nend.\r\n")
COD = {'utf16': (b'\xff\xfe', 'utf-16-le'), 'utf32': (b'\xff\xfe\x00\x00', 'utf-32-le'),
       'utf8bom': (b'\xef\xbb\xbf', 'utf-8')}


def par(nombre, cod):
    bom, c = COD[cod]
    open(os.path.join(JAIL, nombre + '.pas'), 'wb').write(PAS.format(u=nombre).encode('ascii'))
    p = os.path.join(JAIL, nombre + '.dfm')
    open(p, 'wb').write(bom + FORM.encode(c))
    return p


def lee(p, cod):
    bom, c = COD[cod]
    return open(p, 'rb').read()[len(bom):].decode(c)


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='form-ancho', t=120)
try:
    p = par('UW1', 'utf16')
    r = srv.call('delphi_edit', {'path': p, 'old': "  Caption = 'Ancho'", 'new': "  Caption = 'Ancho1'"})
    check('W1 delphi_edit sobre un .dfm UTF-16: escribe y dice DSGN-121',
          not mc.rechazado(r) and "'Ancho1'" in lee(p, 'utf16') and mc.es(r, 'SN_DSGN_FORM_ANCHO_FMT'), r[:400])

    p = par('UW2', 'utf16')
    r = srv.call('delphi_edit', {'path': p, 'edits': [{'old': "  Caption = 'Ancho'", 'new': "  Caption = 'Ancho2'"},
                                                     {'old': '  Left = 0', 'new': '  Left = 4'}]})
    check('W2 la tanda (edits) sobre un .dfm UTF-16: escribe y dice DSGN-121, una vez',
          not mc.rechazado(r) and "'Ancho2'" in lee(p, 'utf16') and mc.es(r, 'SN_DSGN_FORM_ANCHO_FMT') and
          r.count('UW2.dfm is a text form') == 1, r[:400])

    p = par('UW3', 'utf16')
    cid = mc.id_changeset(srv.call('delphi_changeset', {'command': 'begin'}))
    srv.call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'edit', 'path': p,
                                  'old': "  Caption = 'Ancho'", 'new': "  Caption = 'Ancho3'"})
    srv.call('delphi_changeset', {'command': 'preview', 'id': cid})
    r = srv.call('delphi_changeset', {'command': 'commit', 'id': cid})
    check('W3 delphi_changeset que edita un .dfm UTF-16: escribe y dice DSGN-121, una vez',
          not mc.rechazado(r) and "'Ancho3'" in lee(p, 'utf16') and mc.es(r, 'SN_DSGN_FORM_ANCHO_FMT') and
          r.count('UW3.dfm is a text form') == 1, r[:400])

    p = par('UW4', 'utf32')
    r = srv.call('delphi_edit', {'path': p, 'old': "  Caption = 'Ancho'", 'new': "  Caption = 'Ancho4'"})
    check('W4 delphi_edit sobre un .dfm UTF-32: escribe y dice DSGN-121',
          not mc.rechazado(r) and "'Ancho4'" in lee(p, 'utf32') and mc.es(r, 'SN_DSGN_FORM_ANCHO_FMT'), r[:400])

    p = par('UW5', 'utf8bom')
    r = srv.call('delphi_edit', {'path': p, 'old': "  Caption = 'Ancho'", 'new': "  Caption = 'Ancho5'"})
    check('W5 el control: delphi_edit sobre un .dfm UTF-8 con BOM NO dice DSGN-121',
          not mc.rechazado(r) and "'Ancho5'" in lee(p, 'utf8bom') and not mc.es(r, 'SN_DSGN_FORM_ANCHO_FMT'), r[:400])

    p = par('UW6', 'utf16')
    r = srv.call('delphi_designer', {'path': p, 'command': 'set', 'component': 'FormW', 'prop': 'Caption',
                                     'value': "'Ancho6'"})
    check('W6 designer set sobre un .dfm UTF-16 la sigue diciendo (encodingNote)',
          not mc.rechazado(r) and mc.es(r, 'SN_DSGN_FORM_ANCHO_FMT'), r[:400])

    # W7 la tanda con avisos *** en cada entrada: la nota una vez
    p = par('UW7', 'utf16')
    r = srv.call('delphi_edit', {'path': p, 'edits': [{'old': "  Caption = 'Ancho'", 'new': "  Caption = 'Ancho7"},
                                                     {'old': '  Left = 0', 'new': '  Left = 4'},
                                                     {'old': '  Top = 0', 'new': '  Top = 4'}]})
    check('W7 una tanda de 3 entradas con avisos *** (el parser) sobre un .dfm UTF-16: la nota UNA vez',
          not mc.rechazado(r) and "'Ancho7" in lee(p, 'utf16') and r.count('***') >= 1 and
          r.count('UW7.dfm is a text form') == 1, (r.count('***'), r.count('UW7.dfm is a text form'), r[:600]))

    # W8 dos forms con el mismo nombre en dos carpetas, en un changeset: dos notas
    ps = []
    for sub in ('a', 'b'):
        d = os.path.join(JAIL, sub)
        os.makedirs(d)
        bom, c = COD['utf16']
        open(os.path.join(d, 'Unit1.pas'), 'wb').write(PAS.format(u='Unit1').encode('ascii'))
        ps.append(os.path.join(d, 'Unit1.dfm'))
        open(ps[-1], 'wb').write(bom + FORM.encode(c))
    cid = mc.id_changeset(srv.call('delphi_changeset', {'command': 'begin'}))
    for i, p in enumerate(ps):
        srv.call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'edit', 'path': p,
                                      'old': "  Caption = 'Ancho'", 'new': "  Caption = 'Ancho8%d'" % i})
    srv.call('delphi_changeset', {'command': 'preview', 'id': cid})
    r = srv.call('delphi_changeset', {'command': 'commit', 'id': cid})
    check('W8 un changeset con a\\Unit1.dfm y b\\Unit1.dfm (UTF-16): DOS notas, una por carpeta',
          not mc.rechazado(r) and r.count('Unit1.dfm is a text form') == 2 and
          all(any((sub + '\\Unit1.dfm: ') in L and 'is a text form' in L for L in r.split('\n'))
              for sub in ('a', 'b')), r[:800])

    # W9 el changeset con avisos *** en sus pasos: la nota una vez
    p = par('UW9', 'utf16')
    cid = mc.id_changeset(srv.call('delphi_changeset', {'command': 'begin'}))
    srv.call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'edit', 'path': p,
                                  'old': "  Caption = 'Ancho'", 'new': "  Caption = 'Ancho9"})
    srv.call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'edit', 'path': p,
                                  'old': '  Left = 0', 'new': '  Left = 9'})
    srv.call('delphi_changeset', {'command': 'preview', 'id': cid})
    r = srv.call('delphi_changeset', {'command': 'commit', 'id': cid})
    check('W9 un changeset de 2 pasos con avisos *** (el parser) sobre un .dfm UTF-16: la nota UNA vez',
          not mc.rechazado(r) and "'Ancho9" in lee(p, 'utf16') and r.count('***') >= 1 and
          r.count('UW9.dfm is a text form') == 1, (r.count('***'), r.count('UW9.dfm is a text form'), r[:800]))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('form ancho DSGN-121 1182')
