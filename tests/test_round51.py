# -*- coding: utf-8 -*-
"""Round 51: quien lee un fichero como UTF-8 ESTRICTO muere con el primer CP1252.

Salio revisando un pendiente viejo ("delphi_styles lint escanea comentarios",
que ya estaba arreglado): el lint leia los .pas con TEncoding.UTF8 "porque los
lookups son ASCII" - pero el FICHERO no lo es. Un solo fuente en CP1252 con un
acento, que es lo normal en un proyecto Delphi con anos, tumbaba el lint entero
con "No mapping for the Unicode character". Es el gemelo del fallo CESU-8 del
decodificador de hijos (test_round47).

El paisaje: los otros lectores UTF-8 estrictos eran los del vault. Una nota
guardada en CP1252 por un editor viejo no se podia ni leer.

La regla: nadie decodifica a mano. El lector de la casa es
Lsp.Patch.DecodeSourceBytes / PatchLoadText (BOM, UTF-8 estricto, y CP1252 solo
cuando algun byte alto no forma secuencia valida).
"""
import os
import time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('round51')


EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
VAULT = os.path.join(BASE, 'vault')
for d in (EXEDIR, JAIL, FUERA, VAULT):
    os.makedirs(d)
EXE = mc.copia_exe(EXEDIR)

TOK = 'r51'
PORT = mc.puerto_libre()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R51]', 'Token=%s' % TOK, 'Roots=%s' % JAIL, 'VaultPath=%s' % VAULT,
    'VaultReadOnly=0', '']))
# espera a que ESCUCHE (antes un sleep fijo de 3 s)
proc = mc.lanza_http(EXE, PORT, mc.entorno())
# sin texto, el mensaje entero en JSON: es lo que ensena el detalle de un FAIL
cli = mc.Http(PORT, TOK, respaldo_json=True)
cli.session('r51')
call = cli.call


ACENTOS = 'Atención: el camión lleva señales'

try:
    # ------------------------------------------------------------------- L
    # Un proyecto FMX de los de verdad: fuentes viejos en CP1252 con acentos.
    proy = os.path.join(JAIL, 'App')
    os.makedirs(os.path.join(proy, 'Styles'))
    open(os.path.join(proy, 'Styles', 'App.style'), 'w', newline='\r\n').write(
        "object TStyleContainer\n  object TLayout\n"
        "    StyleName = 'cardstyle'\n  end\nend\n")
    open(os.path.join(proy, 'ULegado.pas'), 'wb').write((
        'unit ULegado;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\n'
        "// %s. StyleLookup := 'comentadostyle';\r\n"
        'procedure P(B: TObject);\r\nbegin\r\n'
        "  TButton(B).StyleLookup := 'noexistestyle';\r\n"
        "  TButton(B).StyleLookup := 'cardstyle';\r\n"
        'end;\r\n\r\nend.\r\n' % ACENTOS).encode('cp1252'))
    r = call('delphi_styles', {'command': 'lint',
                               'path': os.path.join(proy, 'Styles')})
    # no morir Y contestar: el informe del lint, que ha leido el estilo y el
    # .pas (antes bastaba con no ver el error: un timeout pasaba)
    lint = mc.como_json(r)
    check('L1 el lint de estilos no muere con un .pas en CP1252',
          'EEncodingError' not in r and 'No mapping' not in r and
          lint.get('styleFiles') == 1 and lint.get('lookupsUsed', 0) >= 1 and
          'lookupsWithoutStyle' in lint, r[:240])
    check('L2 ...ve el lookup que ningun estilo define',
          'noexistestyle' in r, r[:400])
    check('L3 ...y NO cuenta el que esta en un comentario',
          'comentadostyle' not in r, r[:400])

    # ------------------------------------------------------------------- V
    # Un vault con una nota que alguien guardo en CP1252 con un editor viejo.
    open(os.path.join(VAULT, 'MEMORY.md'), 'wb').write(
        b'# Indice\r\n- [[vieja]]\r\n')
    open(os.path.join(VAULT, 'vieja.md'), 'wb').write(
        ('# Nota vieja\r\n\r\n%s\r\n' % ACENTOS).encode('cp1252'))
    r = call('vault_read', {'path': 'vieja.md'})
    # no morir Y contestar: la nota, con su cabecera y su primera linea
    check('V1 vault_read de una nota en CP1252 no muere',
          'EEncodingError' not in r and 'No mapping' not in r and
          r.startswith('# vieja.md') and '1|# Nota vieja' in r, r[:240])
    check('V2 ...y los acentos llegan bien, no como U+FFFD',
          'camión' in r and '�' not in r, r[:240])
    r = call('vault_search', {'pattern': 'lleva', 'target': 'content'})
    check('V3 vault_search por contenido tampoco muere, y la encuentra',
          'No mapping' not in r and 'vieja' in r, r[:240])
    r = call('vault_read', {})
    check('V4 el arranque del vault (reglas + indice) sigue contestando',
          'No mapping' not in r and 'Indice' in r, r[:240])
finally:
    try:
        proc.kill()
    except Exception:
        pass
    time.sleep(0.5)
    mc.borra(BASE)

mc.fin('test_round51')
