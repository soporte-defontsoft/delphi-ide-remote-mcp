# -*- coding: utf-8 -*-
"""Battery 1.18.2, point 1: an edit does not rewrite the line endings of the
lines it does not touch.

Measured 2026-10-10 (pendientes 1.18.1, point 7): delphi_textedit on a file
'a CRLF, b LF, c CRLF, d CRLF' editing d left 'b CRLF' - it rewrote a line
it did not touch, while every editor promises the line endings are kept
(delphi_help conventions: "ENCODING AND LINE ENDINGS are kept as they are").
Each engine joined ALL the lines with the file's dominant ending: DoEdit
(delphi_edit), DoEditLine and ApplyBlockEdit (both tools), the changeset's
delete-line, the CreateForm line that delphi_create / remove-unit write in a
.dpr, and the vault (vault_patch, vault_append).

The rule, door by door: what lies outside the edit keeps its bytes, line
endings included; the edited line keeps the ending it had; the breaks INSIDE
a new text of several lines are the file's dominant one (text being written);
a file without a final line ending keeps none. And the controls: a no-op on a
mixed file is UNCHANGED and writes nothing, a pure CRLF file stays pure, and
EDIT-082 (foreign endings) does not fire for endings the edit did not bring.

Usage:  python tests/test_eol_mixto_1182.py [path-to-DelphiLspMcp.exe]
"""
import atexit
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('eol-mixto-1182')
atexit.register(mc.borra, BASE)
JAIL = os.path.join(BASE, 'jail')
VAULT = os.path.join(BASE, 'vault')
for _d in (JAIL, VAULT):
    os.makedirs(_d)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_VAULT_PATH': VAULT,
                                'DELPHI_MCP_VAULT_READONLY': '0'}), nombre='eol', t=300)
call = srv.call

# CRLF el dominante; "dos" acaba en LF
MIXTO = b'uno\r\ndos\ntres\r\ncuatro\r\ncinco\r\n'


def fichero(nombre, contenido, dentro=JAIL):
    p = os.path.join(dentro, nombre)
    with open(p, 'wb') as f:
        f.write(contenido)
    return p


def lee(p):
    with open(p, 'rb') as f:
        return f.read()


def corto(t):
    return ' '.join(str(t).split())[:240]


def sin_082(r):
    return '[EDIT-082]' not in str(r)


try:
    # ---- delphi_textedit: DoEditLine y ApplyBlockEdit ----
    p = fichero('t1.txt', MIXTO)
    r = call('delphi_textedit', {'path': p, 'old': 'cuatro', 'new': 'CUATRO'})
    check('T1 textedit: cambia una linea CRLF y la LF de "dos" sigue LF',
          lee(p) == b'uno\r\ndos\ntres\r\nCUATRO\r\ncinco\r\n', lee(p))

    p = fichero('t2.txt', MIXTO)
    call('delphi_textedit', {'path': p, 'old': 'dos', 'new': 'DOS'})
    check('T2 textedit: la linea LF cambiada conserva su LF',
          lee(p) == b'uno\r\nDOS\ntres\r\ncuatro\r\ncinco\r\n', lee(p))

    p = fichero('t3.txt', MIXTO)
    call('delphi_textedit', {'path': p, 'old': 'dos', 'new': 'd1\nd2'})
    check('T3 textedit: un new de dos lineas lleva dentro el dominante y al final el salto de la linea',
          lee(p) == b'uno\r\nd1\r\nd2\ntres\r\ncuatro\r\ncinco\r\n', lee(p))

    p = fichero('t4.txt', MIXTO)
    call('delphi_textedit', {'path': p, 'old': 'tres', 'delete': True})
    check('T4 textedit: borrar una linea deja las demas con su salto',
          lee(p) == b'uno\r\ndos\ncuatro\r\ncinco\r\n', lee(p))

    p = fichero('t5.txt', MIXTO)
    r = call('delphi_textedit', {'path': p, 'edits': [{'old': 'uno', 'new': 'UNO'},
                                                      {'old': 'tres\ncuatro', 'new': 'TC'}]})
    check('T5 textedit edits (una linea y un BLOQUE): lo de fuera con su salto',
          lee(p) == b'UNO\r\ndos\nTC\r\ncinco\r\n', '%s %s' % (lee(p), corto(r)))

    p = fichero('t6.txt', MIXTO)
    call('delphi_textedit', {'path': p, 'old': 'tres', 'toline': 4, 'new': 'X'})
    check('T6 textedit toline: el rango se va, la nueva lleva el salto con que acababa y "dos" sigue LF',
          lee(p) == b'uno\r\ndos\nX\r\ncinco\r\n', lee(p))

    p = fichero('t7.txt', b'a\r\nb\nc')
    call('delphi_textedit', {'path': p, 'old': 'c', 'new': 'C'})
    check('T7 textedit: sin salto final, la ultima cambiada sigue sin el y "b" sigue LF',
          lee(p) == b'a\r\nb\nC', lee(p))
    p = fichero('t7b.txt', b'a\nb\r\nc\r\nd')
    call('delphi_textedit', {'path': p, 'old': 'd', 'delete': True})
    check('T7b textedit: borrar la ultima de un fichero sin salto final lo deja sin el, y "a" sigue LF',
          lee(p) == b'a\nb\r\nc', lee(p))

    p = fichero('t8.txt', b'a\r\na\nb\r\n')
    call('delphi_textedit', {'path': p, 'old': 'a', 'atline': 1, 'delete': True})
    check('T8 textedit: de dos lineas iguales se va la PEDIDA con su salto',
          lee(p) == b'a\nb\r\n', lee(p))

    p = fichero('t9.txt', b'x\r\ny\r\n')
    r = call('delphi_textedit', {'path': p, 'old': 'y', 'new': 'y1\ny2'})
    check('T9 control: un fichero todo CRLF sigue todo CRLF',
          lee(p) == b'x\r\ny1\r\ny2\r\n', lee(p))

    p = fichero('t10.txt', MIXTO)
    r = call('delphi_textedit', {'path': p, 'old': 'cuatro', 'new': 'cuatro'})
    check('T10 control: old == new en un fichero mixto es UNCHANGED y no escribe',
          mc.es(r, 'SN_EDIT_SIN_CAMBIOS_FMT') and lee(p) == MIXTO, '%s %s' % (lee(p), corto(r)))

    p = fichero('t11.txt', MIXTO)
    r = call('delphi_textedit', {'path': p, 'old': 'dos', 'new': ''})
    check('T11 textedit: old sin new deja la linea EN BLANCO con su LF (no la borra)',
          lee(p) == b'uno\r\n\ntres\r\ncuatro\r\ncinco\r\n', '%s %s' % (lee(p), corto(r)))

    p = fichero('t12.txt', MIXTO)
    r = call('delphi_textedit', {'path': p, 'edits': [{'old': 'tres\ncuatro', 'new': ''}]})
    check('T12 textedit: un BLOQUE con new vacio se va entero (sin dejar una en blanco)',
          lee(p) == b'uno\r\ndos\ncinco\r\n', '%s %s' % (lee(p), corto(r)))

    # T13: un CR suelto que la edicion deja delante de una linea VACIA en LF
    # se leeria como UN CRLF y esa linea desapareceria (revisor propio de la
    # 1.18.2, medido): sale CRLF y la linea en blanco sigue
    p = fichero('t13.txt', b'a\rX\n\nb\n')
    call('delphi_textedit', {'path': p, 'old': 'X', 'delete': True})
    check('T13 textedit: un CR suelto no se funde con la linea en blanco de debajo',
          lee(p) == b'a\r\n\nb\n', lee(p))

    p = fichero('t14.txt', b'x\ny\n')
    call('delphi_textedit', {'path': p, 'old': 'y', 'new': 'y1\ny2'})
    check('T14 control: un fichero todo LF sigue todo LF', lee(p) == b'x\ny1\ny2\n', lee(p))

    p = fichero('t15.txt', b'x\ry\r')
    call('delphi_textedit', {'path': p, 'old': 'y', 'new': 'y1\ny2'})
    check('T15 control: un fichero todo CR sigue todo CR', lee(p) == b'x\ry1\ry2\r', lee(p))

    p = fichero('t16.txt', MIXTO)
    r = call('delphi_textedit', {'path': p, 'edits': [{'old': 'dos\ntres', 'new': 'dos\ntres'}]})
    check('T16 textedit: un BLOQUE con old == new no reescribe nada (la LF de "dos" sigue)',
          lee(p) == MIXTO, '%s %s' % (lee(p), corto(r)))

    p = fichero('t17.txt', MIXTO)
    call('delphi_textedit', {'path': p, 'old': 'dos', 'new': 'dos\nNUEVA'})
    check('T17 textedit: anadir detras de una linea le deja SU salto y la nueva lleva el dominante',
          lee(p) == b'uno\r\ndos\nNUEVA\r\ntres\r\ncuatro\r\ncinco\r\n', lee(p))

    p = fichero('t18.txt', MIXTO)
    call('delphi_textedit', {'path': p, 'old': 'uno', 'toline': 3, 'new': 'UNO\ndos\ntres'})
    check('T18 textedit: un rango cuyas ultimas lineas no cambian las deja con su salto',
          lee(p) == b'UNO\r\ndos\ntres\r\ncuatro\r\ncinco\r\n', lee(p))

    # ---- delphi_edit: DoEdit y ApplyBlockEdit en Pascal ----
    PAS = (b'unit UMix;\r\n\r\ninterface\n\r\nimplementation\r\n\r\n'
           b'// nota uno\r\n// nota dos\n// nota tres\r\n\r\nend.\r\n')

    p = fichero('UMix.pas', PAS)
    r = call('delphi_edit', {'path': p, 'old': '// nota tres', 'new': '// nota TRES'})
    check('E1 delphi_edit: cambia una linea y las dos LF siguen LF',
          lee(p) == PAS.replace(b'// nota tres', b'// nota TRES'), '%s %s' % (lee(p), corto(r)))

    p = fichero('UMix.pas', PAS)
    r = call('delphi_edit', {'path': p, 'old': '// nota dos', 'new': '// d1\n// d2'})
    check('E2 delphi_edit: un new de dos lineas en la linea LF: dentro CRLF, al final su LF',
          lee(p) == PAS.replace(b'// nota dos\n', b'// d1\r\n// d2\n'), '%s %s' % (lee(p), corto(r)))
    check('E2b ...sin EDIT-082', sin_082(r), corto(r))

    p = fichero('UMix.pas', PAS)
    call('delphi_edit', {'path': p, 'old': '// nota uno', 'toline': 9, 'delete': True})
    check('E3 delphi_edit: borrar un rango deja "interface" con su LF',
          lee(p) == b'unit UMix;\r\n\r\ninterface\n\r\nimplementation\r\n\r\n\r\nend.\r\n', lee(p))

    p = fichero('UMix.pas', PAS)
    r = call('delphi_edit', {'path': p, 'edits': [{'old': '// nota uno', 'new': '// UNO'},
                                                  {'old': '// nota dos\n// nota tres', 'new': '// DT'}]})
    check('E4 delphi_edit edits (una linea y un BLOQUE): lo de fuera con su salto',
          lee(p) == b'unit UMix;\r\n\r\ninterface\n\r\nimplementation\r\n\r\n// UNO\r\n// DT\r\n\r\nend.\r\n',
          '%s %s' % (lee(p), corto(r)))

    # old sin new: la linea queda EN BLANCO, con su salto. La respuesta lo
    # dice (EDIT-089), y ninguna bateria miraba los bytes: un ''.Split vacio
    # la BORRABA diciendo BLANKED (mutante del compositor, 11-oct-2026)
    p = fichero('UMix.pas', PAS)
    r = call('delphi_edit', {'path': p, 'old': '// nota dos', 'new': ''})
    check('E6 delphi_edit: old sin new deja la linea EN BLANCO con su LF (no la borra)',
          lee(p) == PAS.replace(b'// nota dos\n', b'\n'), '%s %s' % (lee(p), corto(r)))

    p = fichero('UMix.pas', PAS)
    r = call('delphi_edit', {'path': p, 'old': '// nota dos', 'new': '// nota dos'})
    check('E5 control: old == new en un .pas mixto es UNCHANGED y no escribe',
          mc.es(r, 'SN_EDIT_SIN_CAMBIOS_FMT') and lee(p) == PAS, '%s %s' % (lee(p), corto(r)))

    # ---- delphi_changeset delete-line ----
    p = fichero('c1.txt', MIXTO)
    r = call('delphi_changeset', {'command': 'begin'})
    cid = mc.id_changeset(r)
    call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'delete-line', 'path': p,
                              'atline': 4, 'old': 'cuatro'})
    call('delphi_changeset', {'command': 'preview', 'id': cid})
    r = call('delphi_changeset', {'command': 'commit', 'id': cid})
    check('C1 changeset delete-line: las demas lineas con su salto',
          lee(p) == b'uno\r\ndos\ntres\r\ncinco\r\n', '%s %s' % (lee(p), corto(r)))

    # ---- el .dpr: CreateForm al crear un form y al quitar la unit ----
    PROY = os.path.join(JAIL, 'PMix')
    r = call('delphi_create', {'kind': 'project-vcl', 'name': 'PMix', 'dir': PROY})
    DPR = os.path.join(PROY, 'PMix.dpr')
    if not os.path.exists(DPR):
        check('P0 fixture: el proyecto VCL', False, corto(r))
    else:
        d = lee(DPR)
        check('P0 fixture: el .dpr nace todo CRLF y con Application.Initialize',
              b'\n' not in d.replace(b'\r\n', b'') and b'Application.Initialize;\r\n' in d, d)
        with open(DPR, 'wb') as f:
            f.write(d.replace(b'Application.Initialize;\r\n', b'Application.Initialize;\n'))
        r = call('delphi_create', {'kind': 'form-vcl', 'name': 'UOtro',
                                   'project': os.path.join(PROY, 'PMix.dproj')})
        d = lee(DPR)
        check('P1 un form nuevo entra en el .dpr (su CreateForm)', b'CreateForm(TFormUOtro' in d,
              '%s %s' % (d, corto(r)))
        check('P1b ...y la linea LF de Application.Initialize sigue LF, sola',
              b'Application.Initialize;\n' in d and d.count(b'\n') - d.count(b'\r\n') == 1, d)
        # la linea del CreateForm lleva algo mas detras y acaba en LF: al quitar
        # la unit se va la sentencia sola, y lo que queda de la linea, con su LF
        d = d.replace(b'Application.CreateForm(TFormUOtro, FormUOtro);\r\n',
                      b'Application.CreateForm(TFormUOtro, FormUOtro); { resto }\n')
        with open(DPR, 'wb') as f:
            f.write(d)
        check('P3 fixture: el CreateForm con algo detras y en LF', b'{ resto }\n' in d, d)
        r = call('delphi_config', {'command': 'remove-unit', 'project': os.path.join(PROY, 'PMix.dproj'),
                                   'path': os.path.join(PROY, 'UOtro.pas')})
        d = lee(DPR)
        check('P2 remove-unit quita su CreateForm', b'UOtro' not in d, '%s %s' % (d, corto(r)))
        check('P2b ...y las dos lineas LF siguen LF: Initialize y lo que quedo del CreateForm',
              b'Application.Initialize;\n' in d and b'{ resto }\n' in d and
              d.count(b'\n') - d.count(b'\r\n') == 2, d)

    # ---- el vault: vault_patch y vault_append ----
    n = fichero('n.md', b'# Nota\r\nuno\ndos\r\n', VAULT)
    r = call('vault_patch', {'path': 'n.md', 'old_text': 'dos', 'new_text': 'DOS'})
    check('V1 vault_patch: la linea LF de otra linea sigue LF',
          lee(n) == b'# Nota\r\nuno\nDOS\r\n', '%s %s' % (lee(n), corto(r)))
    r = call('vault_append', {'path': 'n.md', 'content': 'tres'})
    check('V2 vault_append: lo anadido con el dominante, lo de antes con su salto',
          lee(n) == b'# Nota\r\nuno\nDOS\r\ntres\r\n', '%s %s' % (lee(n), corto(r)))
    # una nota VACIA (Obsidian las crea asi): daba SYS-009 (revisor propio)
    n = fichero('vacia.md', b'', VAULT)
    r = call('vault_append', {'path': 'vacia.md', 'content': 'hola'})
    check('V3 vault_append a una nota vacia escribe como antes',
          lee(n) == b'\r\nhola\r\n', '%s %s' % (lee(n), corto(r)))
    n = fichero('ancla.md', b'# Nota\r\nuno\ndos\r\n', VAULT)
    r = call('vault_append', {'path': 'ancla.md', 'content': 'tres', 'anchor': 'uno'})
    check('V4 vault_append con ancla: el ancla conserva su LF, lo anadido con el dominante',
          lee(n) == b'# Nota\r\nuno\ntres\r\n\r\ndos\r\n', '%s %s' % (lee(n), corto(r)))
finally:
    srv.cierra()

mc.fin('eol: an edit keeps the line endings of the lines it does not touch (1.18.2)')
