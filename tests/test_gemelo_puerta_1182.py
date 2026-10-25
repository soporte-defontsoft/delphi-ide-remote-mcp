# -*- coding: utf-8 -*-
"""El gemelo designer de una unit, por la puerta (1.18.2, punto 2c).

Hasta la 1.22 delphi_move y delphi_delete de una unit se llevaban su .dfm/.fmx
con ella, y la puerta juzgaba solo la UNIT: el gemelo se movia, se copiaba o iba
a la papelera sin preguntar nada (2c). Desde V19 (1.23) el par no viaja solo:
se nombra con un comodin (U.*), y CADA entrada que case pasa SU puerta. Comparten
carpeta, asi que la diferencia esta en lo que la puerta dice de ESE fichero:
aqui, una entrada de ReadOnlyPaths que lo nombra a el solo.

  G0  control: la puerta niega editar y mover el .dfm de solo lectura
  G1  mover U.* con su .dfm de solo lectura: se niega y todo queda (ni la unit
      movida, ni copia en la papelera, ni la carpeta de destino creada)
  G1c ...y la unit sola SI se mueve (el par no viaja solo): el .dfm se queda y
      la respuesta avisa del par partido (FILE-051)
  G2  borrar D.* con su .dfm de solo lectura: se niega, todo o nada
  G2c ...y la unit sola SI va a la papelera, con el aviso del par
  G3  control: COPIAR C.* si (leer lo de solo lectura es libre), y el original
      intacto
  G4  mover W.* adonde su .dfm caeria en solo lectura: se niega
  G5  COPIAR Z.* adonde su .dfm caeria en solo lectura: se niega
  (los destinos son carpetas que aun no existen: un move que no se hace no las
  crea)

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

Y restaurar desde la papelera (1.18.3; la bateria que faltaba): la unit y su
designer vuelven con delphi_move desde sus copias de __delphi-patch, y el sitio
de vuelta del designer es de solo lectura.

  R0  control: borrar R.* manda la unit y su .dfm a la papelera
  R1  restaurar los dos adonde el .dfm es de solo lectura: la unit vuelve, el
      .dfm NO se escribe alli (GUARD-012) y su copia sigue en la papelera para
      otro intento

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
SOLO = ';'.join([U_DFM, D_DFM, C_DFM, os.path.join(NUEVO4, 'W.dfm'), os.path.join(NUEVO5, 'Z.dfm'),
                 # y lo que llegaria con una carpeta (F1, F2)
                 os.path.join(NUEVOF, 'F', 'U.dfm'), os.path.join(NUEVOG, 'G', 'U.dfm'),
                 os.path.join(NUEVOK, 'K', 'U.dfm'), os.path.join(REAL6, 'A', 'U.dfm'),
                 # y el sitio de vuelta del designer de R (R1)
                 os.path.join(JAIL, 'vuelta', 'R.dfm')])
os.makedirs(os.path.join(JAIL, 'rest'))
R_PAS = escribe(os.path.join(JAIL, 'rest', 'R.pas'),
                PAS.format('R'))
R_DFM = escribe(os.path.join(JAIL, 'rest', 'R.dfm'), DFM.format('R'))
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
    # por la regla de SOLO LECTURA (GUARD-012), no por otra (revisor de baterias,
    # 18-oct-2026): si no, G3 deja de probar que leer lo de solo lectura es libre
    check('G0 control: el .dfm de solo lectura no se edita ni se mueve por si solo',
          mc.es(r, 'SR_READONLY_PATH_FMT') and mc.es(r2, 'SR_READONLY_PATH_FMT') and intacto(U_DFM),
          (r[:300], r2[:300]))

    r = srv.call('delphi_move', {'path': os.path.join(JAIL, 'U.*'), 'dest': NUEVO1})
    check('G1a mover U.* con su .dfm de solo lectura: lo niega la puerta de ESA entrada (GUARD-012)',
          mc.es(r, 'SR_READONLY_PATH_FMT') and 'U.dfm' in r, r[:400])
    check('G1b ...y todo queda: nada movido, nada en la papelera, ninguna carpeta creada',
          intacto(U_PAS, U_DFM) and not os.path.exists(NUEVO1) and not en_papelera('U.'),
          (os.path.exists(NUEVO1), en_papelera('U.')))

    r = srv.call('delphi_delete', {'path': os.path.join(JAIL, 'D.*')})
    check('G2a borrar D.* con su .dfm de solo lectura: lo niega su puerta, antes de tocar nada',
          mc.rechazado(r) and mc.es(r, 'SR_READONLY_PATH_FMT') and 'D.dfm' in r, r[:400])
    check('G2b ...y todo queda: ni la unit ni su .dfm en la papelera',
          intacto(D_PAS, D_DFM) and not en_papelera('D.dfm') and not en_papelera('D.pas'),
          (r[:400], en_papelera('D.')))

    # que C.dfm ES de solo lectura (si no, el control no mide nada)
    r = srv.call('delphi_edit', {'path': C_DFM, 'old': "  Caption = 'FormC'", 'new': "  Caption = 'Otro'"})
    check('G3a control: C.dfm es de solo lectura de verdad (no se edita)', mc.es(r, 'SR_READONLY_PATH_FMT'), r[:300])
    COPIA = os.path.join(JAIL, 'copia')
    r = srv.call('delphi_move', {'path': os.path.join(JAIL, 'C.*'), 'dest': COPIA, 'copy': True})
    check('G3 control: COPIAR C.* si, la unit y su .dfm (leer lo de solo lectura es libre), y el original intacto',
          not mc.fallo(r) and os.path.isfile(os.path.join(COPIA, 'C.pas')) and
          os.path.isfile(os.path.join(COPIA, 'C.dfm')) and intacto(C_PAS, C_DFM), r[:400])

    r = srv.call('delphi_move', {'path': os.path.join(JAIL, 'otra', 'W.*'), 'dest': NUEVO4})
    check('G4a mover W.* adonde su .dfm caeria en solo lectura: lo niega la puerta de ese destino',
          mc.es(r, 'SR_READONLY_PATH_FMT') and 'W.dfm' in r, r[:400])
    check('G4b ...y todo queda: nada movido, nada en la papelera, ninguna carpeta creada',
          intacto(W_PAS, W_DFM) and not os.path.exists(NUEVO4) and not en_papelera('W.'),
          (os.path.exists(NUEVO4), en_papelera('W.')))

    r = srv.call('delphi_move', {'path': os.path.join(JAIL, 'otra', 'Z.*'), 'dest': NUEVO5, 'copy': True})
    # (la decision de la copia lo dice antes que la puerta de escribir: MOVE-020)
    check('G5a COPIAR Z.* adonde su .dfm caeria en solo lectura: lo niega la decision de la copia (MOVE-020)',
          mc.abre(r, 'SR_MUDANZA_DESTINO_PROTEGIDO_FMT') and 'Z.dfm' in r, r[:400])
    check('G5b ...y no queda ni la copia ni su carpeta, y el original intacto',
          intacto(Z_PAS, Z_DFM) and not os.path.exists(NUEVO5), os.path.exists(NUEVO5))

    # la unit SOLA, nombrada por su nombre: el par no viaja solo (V19)
    r = srv.call('delphi_move', {'path': U_PAS, 'dest': os.path.join(NUEVO1, 'V.pas')})
    check('G1c la unit sola SI se mueve: su .dfm de solo lectura se queda, y FILE-051 avisa del par',
          mc.abre(r, 'SK_MOVE_MOVIDO_FMT') and os.path.isfile(os.path.join(NUEVO1, 'V.pas')) and
          intacto(U_DFM) and mc.es(r, 'SN_FILE_PAR_PARTIDO_FMT'), r[:500])
    r = srv.call('delphi_delete', {'path': D_PAS})
    check('G2c ...y borrar la unit sola SI la manda a la papelera: el .dfm se queda, con el aviso',
          mc.abre(r, 'SK_FILE_BORRADO_PAPELERA_FMT') and not os.path.exists(D_PAS) and intacto(D_DFM)
          and mc.es(r, 'SN_FILE_PAR_PARTIDO_FMT'), r[:500])

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
    # ------------------------------------------------------------- R (1.18.3)
    r = srv.call('delphi_delete', {'path': os.path.join(JAIL, 'rest', 'R.*')})
    cp_pas = [c for c in en_papelera('R.pas') if os.path.isfile(c)]
    cp_dfm = [c for c in en_papelera('R.dfm') if os.path.isfile(c)]
    check('R0 control: borrar R.* manda la unit y su .dfm a la papelera',
          not mc.fallo(r) and cp_pas and cp_dfm and not os.path.exists(R_PAS) and not os.path.exists(R_DFM),
          (r[:300], cp_pas, cp_dfm))
    VUELTA = os.path.join(JAIL, 'vuelta')
    r1 = srv.call('delphi_move', {'path': cp_pas[0], 'dest': os.path.join(VUELTA, 'R.pas')}) if cp_pas else ''
    r2 = srv.call('delphi_move', {'path': cp_dfm[0], 'dest': os.path.join(VUELTA, 'R.dfm')}) if cp_dfm else ''
    check('R1 restaurar la unit y su .dfm adonde el .dfm es de solo lectura: la unit vuelve, el .dfm no se '
          'escribe alli y su copia sigue en la papelera',
          mc.abre(r1, 'SK_MOVE_MOVIDO_FMT') and os.path.isfile(os.path.join(VUELTA, 'R.pas')) and
          not os.path.exists(os.path.join(VUELTA, 'R.dfm')) and cp_dfm and os.path.isfile(cp_dfm[0]) and
          mc.abre(r2, 'SR_READONLY_PATH_FMT'), (r1[:300], r2[:300]))
    check('el servidor sigue vivo', not mc.fallo(srv.call('delphi_list', {'root': JAIL})))
finally:
    srv.cierra()
mc.fin('gemelo por la puerta 1182')
