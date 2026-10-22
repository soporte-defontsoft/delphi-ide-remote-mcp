# -*- coding: utf-8 -*-
r"""La columna de las tools por posicion en una linea con acentos (1.22.1). DelphiLSP cuenta la columna en
BYTES UTF-8 de la linea, a la ida y a la vuelta (medido el 22-oct-2026 con el motor solo: una enye +1, un euro
+2, un emoji +2 sobre UTF-16, en hover, definition, symbols y diagnostics, con el fichero abierto o leido del
disco, ANSI o UTF-8; no declara positionEncoding con ninguna oferta). El agente, delphi_read y delphi_search
cuentan en UTF-16: con un acento delante, cada tool por posicion apuntaba al simbolo de al lado (test completo de
la 1.22.0 en Hermes). Ahora el cliente del motor (Lsp.Client) convierte cada columna que le manda y cada una que le
llega, con la linea que el motor tiene de ese documento.

Fixture: un proyecto de consola con UAnsi (ANSI: n~ y euro delante de una llamada y delante de la cabecera de un
cuerpo), UUtf8 (UTF-8 con BOM: un emoji y un euro), UMalAnsi y UMalU8 (un identificador sin declarar detras de
acentos) y, en el .dpr, una funcion cuya cabecera lleva un comentario con n~ y euro delante. Cada caso de ida tiene
su control en una linea sin acentos, que pasa tambien con la version anterior.

  A0/A1 hover en la columna UTF-16 de Doble y Triple (ANSI) y de Cuadruple y Quintuple (emoji): ese simbolo
  D0/D1 definition de Doble desde su llamada: la cabecera de su cuerpo (el motor da character 0 en una unidad)
  D2    definition de Septuple desde una linea SIN acentos: su cabecera del .dpr, con character0 en UTF-16 (la
        vuelta sola: el motor da los bytes)
  D3    definition de Septuple desde una linea CON acentos: lo mismo (la ida y la vuelta)
  S0/S1 signature dentro de Triple(...): la firma de Triple, no la de Doble
  C0/C1 completion con el cursor en Trip|le: Triple entre los primeros. GUARDA, no roja: la 1.22.0 ya lo
        daba (el servidor filtra por el prefijo que lee el en su texto); vigila que la conversion no lo rompa
  G0/G1 diagnostics: el rango del error empieza en su columna UTF-16 (ANSI, y UTF-8 con emoji)
  R0/R1/R2 references de Doble: la llamada sin acentos, la llamada con acentos y la cabecera del cuerpo con
        acentos salen CONFIRMADAS (con la 1.22.0 las dos con acentos quedaban sin verificar)
  N1    rename de Doble a Duplo (apply): las cuatro apariciones, ninguna Doble, y el fichero sigue en ANSI

Uso:  python tests/test_columna_acentos_1221.py [ruta-a-DelphiLspMcp.exe]
"""
import os, time
import mcp_cliente as mc
from mcp_cliente import check

ENYE, EURO, CARA = 'ñ', '€', '\U0001F600'
BASE = mc.carpeta('columna-acentos')
CARPETA = os.path.join(BASE, 'p')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='ca', t=600)

L_ANSI = "  S := 'se" + ENYE + "or" + EURO + "'; N := Doble(Triple(1));"
L_ANSI_PLANA = "  S := 'senor'; N := Doble(Triple(2));"
CAB_ANSI = '{ ' + ENYE + EURO + ' } function Doble(A: Integer): Integer;'
CAB_INT = 'function Doble(A: Integer): Integer;'
UANSI = ('unit UAnsi;\r\n\r\ninterface\r\n\r\n' + CAB_INT + '\r\nfunction Triple(A: Integer): Integer;\r\n'
         'procedure UsaAnsi;\r\n\r\nimplementation\r\n\r\n' + CAB_ANSI + '\r\nbegin\r\n  Result := A * 2;\r\nend;\r\n\r\n'
         'function Triple(A: Integer): Integer;\r\nbegin\r\n  Result := A * 3;\r\nend;\r\n\r\nprocedure UsaAnsi;\r\nvar\r\n'
         '  S: string;\r\n  N: Integer;\r\nbegin\r\n' + L_ANSI + '\r\n' + L_ANSI_PLANA + '\r\n  Writeln(S, N);\r\nend;\r\n\r\nend.\r\n')
L_U8 = "  S := 'cara" + CARA + EURO + "'; N := Cuadruple(Quintuple(1));"
L_U8_PLANA = "  S := 'cara'; N := Cuadruple(Quintuple(2));"
UUTF8 = ('unit UUtf8;\r\n\r\ninterface\r\n\r\nfunction Cuadruple(A: Integer): Integer;\r\nfunction Quintuple(A: Integer): Integer;\r\n'
         'procedure UsaUtf8;\r\n\r\nimplementation\r\n\r\nfunction Cuadruple(A: Integer): Integer;\r\nbegin\r\n  Result := A * 4;\r\n'
         'end;\r\n\r\nfunction Quintuple(A: Integer): Integer;\r\nbegin\r\n  Result := A * 5;\r\nend;\r\n\r\nprocedure UsaUtf8;\r\n'
         'var\r\n  S: string;\r\n  N: Integer;\r\nbegin\r\n' + L_U8 + '\r\n' + L_U8_PLANA + '\r\n  Writeln(S, N);\r\nend;\r\n\r\nend.\r\n')
L_MAL_ANSI = "  S := '" + ENYE + EURO + "' + S; N := N + Nada;"
L_MAL_U8 = "  S := '" + CARA + EURO + ENYE + "' + S; N := N + Nada;"
L_MAL_PLANA = "  S := 'x' + S; N := N + Nadie;"
CAB_DPR = '{ ' + ENYE + EURO + ' } function Septuple(A: Integer): Integer;'
L_DPR = "    Writeln('" + ENYE + EURO + "', Septuple(1));"
L_DPR_PLANA = "    Writeln('x', Septuple(2));"


def umal(nombre, linea):
    return ('unit %s;\r\n\r\ninterface\r\n\r\nprocedure Mal;\r\n\r\nimplementation\r\n\r\nprocedure Mal;\r\nvar\r\n  S: string;\r\n'
            '  N: Integer;\r\nbegin\r\n  S := \'\';\r\n  N := 0;\r\n%s\r\n%s\r\nend;\r\n\r\nend.\r\n') % (nombre, linea, L_MAL_PLANA)


def u16(linea, ident):
    """La columna UTF-16 (la del agente, delphi_read y delphi_search) de ident en linea."""
    return len(linea[:linea.index(ident)].encode('utf-16-le')) // 2


def num(texto, linea):
    """La linea 0-based de una linea exacta del texto."""
    return texto.split('\r\n').index(linea)


def diagnostics(path, tope=240):
    """delphi_diagnostics hasta que trae el resultado (un lint lento contesta que sigue en curso)."""
    t0, r = time.time(), ''
    while time.time() - t0 < tope:
        r = srv.call('delphi_diagnostics', {'path': path}, 120)
        if '"diagnostics"' in r:
            return r
        time.sleep(2)
    return r


def ubicacion(r):
    """La primera ubicacion de una respuesta de delphi_definition (objeto suelto, result o lista)."""
    j = mc.como_json(r)
    v = j.get('result', j)
    if isinstance(v, list):
        v = v[0] if v else {}
    return v if isinstance(v, dict) else {}


try:
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Acentos', 'dir': CARPETA})
    check('fixture creada (delphi_create)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    ficheros = {'UAnsi': (UANSI, 'cp1252'), 'UUtf8': (UUTF8, 'utf-8-sig'),
                'UMalAnsi': (umal('UMalAnsi', L_MAL_ANSI), 'cp1252'), 'UMalU8': (umal('UMalU8', L_MAL_U8), 'utf-8-sig')}
    for n, (t, cod) in ficheros.items():
        open(os.path.join(CARPETA, n + '.pas'), 'wb').write(t.encode(cod))
    dpr = os.path.join(CARPETA, 'Acentos.dpr')
    with open(dpr, encoding='utf-8-sig', newline='') as f:
        fuente = f.read()
    corriendo = "    Writeln('Acentos running');"
    assert 'uses' in fuente and '\r\nbegin\r\n' in fuente and corriendo in fuente, fuente[:400]
    fuente = fuente.replace('uses', 'uses\r\n' + ''.join("  %s in '%s.pas',\r\n" % (n, n) for n in ficheros), 1)
    fuente = fuente.replace('\r\nbegin\r\n', '\r\n' + CAB_DPR + '\r\nbegin\r\n  Result := A * 7;\r\nend;\r\n\r\nbegin\r\n', 1)
    fuente = fuente.replace(corriendo, corriendo + '\r\n' + L_DPR + '\r\n' + L_DPR_PLANA, 1)
    with open(dpr, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(fuente)
    pa = os.path.join(CARPETA, 'UAnsi.pas')
    pu = os.path.join(CARPETA, 'UUtf8.pas')

    # A: hover
    for caso, path, txt, linea, ident in (
            ('A0 control ANSI', pa, UANSI, L_ANSI_PLANA, 'Triple'), ('A1 ANSI n~ euro', pa, UANSI, L_ANSI, 'Doble'),
            ('A1 ANSI n~ euro', pa, UANSI, L_ANSI, 'Triple'), ('A0 control UTF-8', pu, UUTF8, L_U8_PLANA, 'Quintuple'),
            ('A1 UTF-8 emoji euro', pu, UUTF8, L_U8, 'Cuadruple'), ('A1 UTF-8 emoji euro', pu, UUTF8, L_U8, 'Quintuple')):
        r = srv.call('delphi_hover', {'path': path, 'line': num(txt, linea), 'character': u16(linea, ident) + 1}, 240)
        otros = [x for x in ('Doble', 'Triple', 'Cuadruple', 'Quintuple') if x != ident and x in r]
        check('%s: hover en la columna de %s dice %s' % (caso, ident, ident), ident in r and not otros, r[:300])

    # D: definition
    for caso, linea in (('D0 control', L_ANSI_PLANA), ('D1 n~ euro', L_ANSI)):
        r = srv.call('delphi_definition', {'path': pa, 'line': num(UANSI, linea), 'character': u16(linea, 'Doble') + 1}, 240)
        check('%s: definition de Doble va a la cabecera de su cuerpo (line0 %d)' % (caso, num(UANSI, CAB_ANSI)),
              ubicacion(r).get('line0') == num(UANSI, CAB_ANSI), r[:300])
    for caso, linea in (('D2 llamada sin acentos', L_DPR_PLANA), ('D3 llamada con n~ euro', L_DPR)):
        r = srv.call('delphi_definition', {'path': dpr, 'line': num(fuente, linea), 'character': u16(linea, 'Septuple') + 1}, 240)
        u = ubicacion(r)
        check('%s: definition de Septuple va a su cabecera del .dpr (line0 %d) con character0 en UTF-16 (%d)'
              % (caso, num(fuente, CAB_DPR), u16(CAB_DPR, 'function')),
              u.get('line0') == num(fuente, CAB_DPR) and u.get('character0') == u16(CAB_DPR, 'function'), r[:300])

    # S: signature dentro de Triple(...)
    for caso, linea in (('S0 control', L_ANSI_PLANA), ('S1 n~ euro', L_ANSI)):
        r = srv.call('delphi_signature', {'path': pa, 'line': num(UANSI, linea), 'character': u16(linea, 'Triple(') + 7}, 240)
        check('%s: signature dentro de Triple(...) es la de Triple' % caso, 'Triple' in r and 'Doble' not in r, r[:300])

    # C: completion con el cursor tras 'Trip'
    for caso, linea in (('C0 control', L_ANSI_PLANA), ('C1 n~ euro', L_ANSI)):
        r = srv.call('delphi_completion', {'path': pa, 'line': num(UANSI, linea), 'character': u16(linea, 'Triple') + 4}, 240)
        items = [x.get('label', '') for x in mc.como_json(r).get('items', []) if isinstance(x, dict)]
        check('%s: completion en Trip|le ofrece Triple entre los primeros' % caso, 'Triple' in items[:5], (items[:8], r[:200]))

    # G: diagnostics
    for caso, n, linea in (('G0 control ANSI', 'UMalAnsi', L_MAL_PLANA), ('G1 ANSI n~ euro', 'UMalAnsi', L_MAL_ANSI),
                           ('G0 control UTF-8', 'UMalU8', L_MAL_PLANA), ('G1 UTF-8 emoji euro n~', 'UMalU8', L_MAL_U8)):
        ident = 'Nadie' if linea == L_MAL_PLANA else 'Nada'
        r = diagnostics(os.path.join(CARPETA, n + '.pas'))
        ds = [d for d in mc.como_json(r).get('diagnostics', []) if "'%s'" % ident in d.get('message', '')]
        ini = ds[0].get('range', {}).get('start', {}) if ds else {}
        check('%s: el error de %s empieza en su columna UTF-16 (%d)' % (caso, ident, u16(linea, ident)),
              ini.get('line') == num(ficheros[n][0], linea) and ini.get('character') == u16(linea, ident), ds[:1] or r[:300])

    # R: references de Doble, confirmadas
    r = srv.call('delphi_references', {'path': pa, 'line': num(UANSI, CAB_INT), 'character': u16(CAB_INT, 'Doble') + 1}, 600)
    confirmadas = {h.get('line0') for h in mc.aciertos(r, 'confirmed')}
    for caso, linea in (('R0 control: la llamada sin acentos', L_ANSI_PLANA), ('R1 la llamada con n~ euro', L_ANSI),
                        ('R2 la cabecera del cuerpo con n~ euro', CAB_ANSI)):
        check('%s sale confirmada' % caso, num(UANSI, linea) in confirmadas, r[:400])

    # N: rename de Doble a Duplo
    r = srv.call('delphi_rename_symbol', {'path': pa, 'line': num(UANSI, CAB_INT), 'character': u16(CAB_INT, 'Doble') + 1,
                                          'newname': 'Duplo', 'mode': 'apply'}, 600)
    b = open(pa, 'rb').read()
    esperado = UANSI.replace('Doble', 'Duplo').encode('cp1252')
    check('N1 rename apply: las cuatro Doble son Duplo, la linea con acentos bien escrita y el fichero sigue en ANSI',
          b == esperado, r[:400])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('columna con acentos (1.22.1)')
