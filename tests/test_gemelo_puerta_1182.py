# -*- coding: utf-8 -*-
"""El gemelo designer de una unit, por la puerta (1.18.2, punto 2c).

delphi_move y delphi_delete de una unit se llevan su .dfm/.fmx con ella. La
puerta juzgaba la UNIT (PathDenied, WriteTargetDenied, EntradaDenegada) y el
gemelo se movia, se copiaba o iba a la papelera sin preguntar nada: un
TFile.Move crudo a un nombre derivado (CLAUDE.md: "un primitivo crudo corre
solo sobre la ruta que la puerta acaba de aprobar"). Comparten carpeta, asi
que la diferencia esta en lo que la puerta dice de ESE fichero: aqui, una
entrada de ReadOnlyPaths que lo nombra a el solo.

  G0  control: la puerta niega editar y mover el .dfm de solo lectura
  G1  mover la unit no se lleva su .dfm de solo lectura: se niega (FILE-043)
      y todo queda como estaba
  G2  borrar la unit no manda a la papelera su .dfm de solo lectura; y sin
      la pregunta de antes, la hace el escritor (MoveToTrash) y todo queda
  G3  control: COPIAR la unit si (leer lo de solo lectura es libre), con su
      .dfm, y el original intacto
  G4  mover una unit a un sitio donde su .dfm caeria en solo lectura: se niega
  G5  COPIAR una unit a un sitio donde su .dfm caeria en solo lectura: se niega
  ("todo queda": ni el original movido, ni copia en la papelera, ni la
  carpeta de destino creada: los destinos son carpetas que aun no existen)

Y su segundo emisor, una CARPETA entera (2r, revisor del 2c): lo que lleva
dentro llega al destino sin que nadie pregunte por ello, y la puerta solo
miraba si el ORIGEN contenia un lugar protegido.

  F1  mover una carpeta adonde algo de dentro caeria en solo lectura: se
      niega (MOVE-020) y nada se mueve
  F2  COPIAR una carpeta igual: se niega y no queda nada
  F2b ...y se niega ANTES de copiar nada (CopiaDenegada): con un fichero del
      origen cogido por otro proceso, el rechazo es MOVE-020 y no el fallo
      de la copia. Sin esa pregunta lo para igual el mudador al final (la
      red: F2 sigue verde), pero despues de copiarlo todo a la bajada
  F3  control: a un destino sin nada protegido dentro, si
  F4  el destino por un junction (J6 -> real6) y la entrada por su ruta real:
      se compara por donde ESTA el destino (RutaDelEnlace), no por su texto

Uso:  python tests/test_gemelo_puerta_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import atexit, glob, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('gemelo_puerta_1182')
atexit.register(mc.borra, BASE)
JAIL = os.path.join(BASE, 'jail')
for d in ('', 'copia', 'otra'):
    os.makedirs(os.path.join(JAIL, d), exist_ok=True)

PAS = """unit {0};

interface

uses
  Vcl.Forms;

type
  TForm{0} = class(TForm)
  end;

var
  Form{0}: TForm{0};

implementation

{{$R *.dfm}}

end.
"""
DFM = """object Form{0}: TForm{0}
  Left = 0
  Top = 0
  Caption = 'Form{0}'
  ClientHeight = 100
  ClientWidth = 200
end
"""


def escribe(ruta, texto):
    with open(ruta, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write(texto)
    return ruta


def bytes_de(ruta):
    with open(ruta, 'rb') as f:
        return f.read()


U_PAS = escribe(os.path.join(JAIL, 'U.pas'), PAS.format('U'))
U_DFM = escribe(os.path.join(JAIL, 'U.dfm'), DFM.format('U'))
# una unit por comprobacion: un fallo de una no tapa a la siguiente
D_PAS = escribe(os.path.join(JAIL, 'D.pas'), PAS.format('D'))
D_DFM = escribe(os.path.join(JAIL, 'D.dfm'), DFM.format('D'))
C_PAS = escribe(os.path.join(JAIL, 'C.pas'), PAS.format('C'))
C_DFM = escribe(os.path.join(JAIL, 'C.dfm'), DFM.format('C'))
W_PAS = escribe(os.path.join(JAIL, 'otra', 'W.pas'), PAS.format('W'))
W_DFM = escribe(os.path.join(JAIL, 'otra', 'W.dfm'), DFM.format('W'))
Z_PAS = escribe(os.path.join(JAIL, 'otra', 'Z.pas'), PAS.format('Z'))
Z_DFM = escribe(os.path.join(JAIL, 'otra', 'Z.dfm'), DFM.format('Z'))
ANTES = {p: bytes_de(p) for p in (U_PAS, U_DFM, D_PAS, D_DFM, C_PAS, C_DFM, W_PAS, W_DFM, Z_PAS, Z_DFM)}
# destinos en carpetas que NO existen: un move que no se hace no las crea
NUEVO1, NUEVO4, NUEVO5 = (os.path.join(JAIL, n) for n in ('nuevo1', 'nuevo4', 'nuevo5'))
NUEVOF, NUEVOG, NUEVOK = (os.path.join(JAIL, n) for n in ('nuevoF', 'nuevoG', 'nuevoK'))
REAL6, J6 = os.path.join(JAIL, 'real6'), os.path.join(JAIL, 'J6')
os.makedirs(REAL6)
assert mc.junction(J6, REAL6), 'no se pudo crear el junction J6'
# solo lectura: los .dfm de U, D y C, y los .dfm que tendria W en nuevo4\ y nuevo5\
SOLO = ';'.join([U_DFM, D_DFM, C_DFM, os.path.join(NUEVO4, 'X.dfm'), os.path.join(NUEVO5, 'Y.dfm'),
                 # y lo que llegaria con una carpeta (F1, F2)
                 os.path.join(NUEVOF, 'F', 'U.dfm'), os.path.join(NUEVOG, 'G', 'U.dfm'),
                 os.path.join(NUEVOK, 'K', 'U.dfm'), os.path.join(REAL6, 'A', 'U.dfm')])
SRC = os.path.join(JAIL, 'src')
for _n in ('F', 'G', 'H', 'K', 'M'):
    os.makedirs(os.path.join(SRC, _n))
    escribe(os.path.join(SRC, _n, 'nota.txt'), 'hola ' + _n)
    escribe(os.path.join(SRC, _n, 'U.dfm'), DFM.format('U'))

EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_READONLY_PATHS': SOLO}),
               nombre='ana', t=120)


def intacto(*rutas):
    return all(os.path.isfile(p) and bytes_de(p) == ANTES[p] for p in rutas)


def en_papelera(nombre):
    return glob.glob(os.path.join(JAIL, '**', mc.PAPELERA, '**', nombre + '*'), recursive=True)


try:
    r = srv.call('delphi_edit', {'path': U_DFM, 'old': "  Caption = 'FormU'", 'new': "  Caption = 'Otro'"})
    r2 = srv.call('delphi_move', {'path': U_DFM, 'dest': os.path.join(NUEVO1, 'U.dfm')})
    check('G0 control: el .dfm de solo lectura no se edita ni se mueve por si solo',
          mc.rechazado(r) and mc.rechazado(r2) and intacto(U_DFM), (r[:300], r2[:300]))

    # (el %s de FILE-043, no la ruta que cita la negativa de dentro)
    r = srv.call('delphi_move', {'path': U_PAS, 'dest': os.path.join(NUEVO1, 'V.pas')})
    check('G1a mover la unit con su .dfm de solo lectura: FILE-043, que nombra el designer',
          mc.abre(r, 'SR_GEMELO_DENEGADO_FMT') and 'designer U.dfm goes along' in r, r[:400])
    check('G1b ...y todo queda: nada movido, nada en la papelera, ninguna carpeta creada',
          intacto(U_PAS, U_DFM) and not os.path.exists(NUEVO1) and not en_papelera('U.'),
          (os.path.exists(NUEVO1), en_papelera('U.')))

    r = srv.call('delphi_delete', {'path': D_PAS})
    check('G2a borrar la unit con su .dfm de solo lectura: FILE-043, antes de tocar nada',
          mc.abre(r, 'SR_GEMELO_DENEGADO_FMT') and 'designer D.dfm goes along' in r, r[:400])
    # (sin la pregunta de antes, la hace el escritor - MoveToTrash - y esto sigue en pie)
    check('G2b ...y todo queda: ni la unit ni su .dfm en la papelera',
          mc.rechazado(r) and intacto(D_PAS, D_DFM) and not en_papelera('D.dfm') and not en_papelera('D.pas'),
          (r[:400], en_papelera('D.')))

    # que C.dfm ES de solo lectura (si no, el control no mide nada)
    r = srv.call('delphi_edit', {'path': C_DFM, 'old': "  Caption = 'FormC'", 'new': "  Caption = 'Otro'"})
    check('G3a control: C.dfm es de solo lectura de verdad (no se edita)', mc.rechazado(r), r[:300])
    COPIA = os.path.join(JAIL, 'copia', 'C2.pas')
    r = srv.call('delphi_move', {'path': C_PAS, 'dest': COPIA, 'copy': True})
    check('G3 control: COPIAR la unit si, con su .dfm (leer lo de solo lectura es libre), y el original intacto',
          not mc.fallo(r) and os.path.isfile(COPIA) and os.path.isfile(os.path.join(JAIL, 'copia', 'C2.dfm')) and
          intacto(C_PAS, C_DFM), r[:400])

    r = srv.call('delphi_move', {'path': W_PAS, 'dest': os.path.join(NUEVO4, 'X.pas')})
    check('G4a mover una unit adonde su .dfm caeria en solo lectura: FILE-043, con la ruta negada',
          mc.abre(r, 'SR_GEMELO_DENEGADO_FMT') and 'designer W.dfm goes along' in r and 'X.dfm' in r, r[:400])
    check('G4b ...y todo queda: nada movido, nada en la papelera, ninguna carpeta creada',
          intacto(W_PAS, W_DFM) and not os.path.exists(NUEVO4) and not en_papelera('W.'),
          (os.path.exists(NUEVO4), en_papelera('W.')))

    r = srv.call('delphi_move', {'path': Z_PAS, 'dest': os.path.join(NUEVO5, 'Y.pas'), 'copy': True})
    check('G5a COPIAR una unit adonde su .dfm caeria en solo lectura: FILE-043, con la ruta negada',
          mc.abre(r, 'SR_GEMELO_DENEGADO_FMT') and 'designer Z.dfm goes along' in r and 'Y.dfm' in r, r[:400])
    check('G5b ...y no queda ni la copia ni su carpeta, y el original intacto',
          intacto(Z_PAS, Z_DFM) and not os.path.exists(NUEVO5), os.path.exists(NUEVO5))

    # ------------------------------------------------------------- F (2r)
    # (el estado primero: contra la 1.18.1 la clave nueva no esta en el catalogo)
    r = srv.call('delphi_move', {'path': os.path.join(SRC, 'F'), 'dest': os.path.join(NUEVOF, 'F')})
    check('F1 mover una CARPETA adonde algo de dentro caeria en solo lectura: se niega y nada se mueve',
          os.path.isfile(os.path.join(SRC, 'F', 'U.dfm')) and not os.path.exists(NUEVOF) and
          not en_papelera('F-') and mc.abre(r, 'SR_MUDANZA_DESTINO_PROTEGIDO_FMT'), r[:400])
    r = srv.call('delphi_move', {'path': os.path.join(SRC, 'G'), 'dest': os.path.join(NUEVOG, 'G'), 'copy': True})
    check('F2 COPIAR una carpeta adonde algo de dentro caeria en solo lectura: se niega y no queda nada',
          os.path.isfile(os.path.join(SRC, 'G', 'U.dfm')) and not os.path.exists(NUEVOG) and
          mc.abre(r, 'SR_MUDANZA_DESTINO_PROTEGIDO_FMT'), r[:400])
    with mc.bloqueado(os.path.join(SRC, 'K', 'nota.txt')):
        r = srv.call('delphi_move', {'path': os.path.join(SRC, 'K'), 'dest': os.path.join(NUEVOK, 'K'), 'copy': True})
    check('F2b ...y ANTES de copiar nada: con un fichero del origen cogido, MOVE-020 y no el fallo de la copia',
          mc.abre(r, 'SR_MUDANZA_DESTINO_PROTEGIDO_FMT') and not os.path.exists(NUEVOK) and
          os.path.isfile(os.path.join(SRC, 'K', 'U.dfm')), r[:400])
    r = srv.call('delphi_move', {'path': os.path.join(SRC, 'H'), 'dest': os.path.join(JAIL, 'libre', 'H')})
    check('F3 control: a un destino sin nada protegido dentro, la carpeta se mueve con lo suyo',
          not mc.fallo(r) and os.path.isfile(os.path.join(JAIL, 'libre', 'H', 'U.dfm')) and
          not os.path.exists(os.path.join(SRC, 'H')), r[:400])
    r = srv.call('delphi_move', {'path': os.path.join(SRC, 'M'), 'dest': os.path.join(J6, 'A')})
    check('F4 el destino por un junction, la entrada por su ruta real: se niega y nada se mueve',
          os.path.isfile(os.path.join(SRC, 'M', 'U.dfm')) and not os.path.exists(os.path.join(REAL6, 'A')) and
          mc.abre(r, 'SR_MUDANZA_DESTINO_PROTEGIDO_FMT'), r[:400])
    check('el servidor sigue vivo', not mc.fallo(srv.call('delphi_list', {'root': JAIL})))
finally:
    srv.cierra()
mc.fin('gemelo por la puerta 1182')
