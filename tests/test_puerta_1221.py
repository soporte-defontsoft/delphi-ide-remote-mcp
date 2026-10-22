# -*- coding: utf-8 -*-
r"""La puerta de lecturas del build juzga cada trozo como lo resuelve dcc/msbuild/Win32,
no por reglas de texto (1.22.1). Seis agujeros de la revision de Opus 5.5, MEDIDOS reales
el 22-oct-2026 contra la 1.22.0 (cada uno compilaba leyendo Ajena de FUERA de la jaula, o
negaba un valor legitimo), y uno de expansion:

  P1 (H1) un trozo con '=' antes de la barra (a=b\..\..\fuera) no se saltaba por "clave=valor":
     ahora se juzga la ruta (GetFullPath colapsa los .. como Win32) y se niega. VerInfo_Keys y
     DCC_UnitAlias (clave=valor de verdad) siguen pasando: PROPIEDADES_CLAVE_VALOR.
  P2 (H2) un ':' con barras detras (s\a:b\..\..\fuera) se tomaba por URL y se saltaba: ahora
     solo en una propiedad clave=valor; en una de ruta se juzga y se niega.
  P3 (H2b) la forma NT del prefijo de dispositivo (\??\C:\fuera) no la quitaba EsPrefijoDeDispositivo
     (solo \\?\ y \\.\): ahora si, y se juzga la ruta real.
  P4 (H3) %2E%2E (puntos escapados): msbuild desescapa y la puerta no; ahora desescapa antes de juzgar.
  P5 (H3b) %3B (punto y coma escapado): msbuild lo desescapa a ';' y parte la lista; ahora la puerta
     tambien (desescapa antes de TrozosDeLista).
  P6 (H4) $(ProjectDir): la puerta lo expandia con la carpeta del proyecto; msbuild lo lee VACIO en el
     cuerpo del .dproj (no es reservada) -> fuera de la jaula. Ahora la puerta no lo pone en su tabla.
  P7 (H9) $(My-Path) con guion: set-property acepta crear My-Path (EsNombreDeEtiqueta) y la puerta lo
     negaba con BUILD-051 (EsNombreDeMacro no admitia '-'). msbuild acepta el '-'; ahora la puerta
     tambien -> un $(My-Path) legitimo COMPILA.
  P8 (H12) $( A ) con espacios: la puerta recortaba el nombre y usaba el valor de A; msbuild NO recorta
     (" A " es otra propiedad, vacia). Ahora no se recorta -> no verificable, BUILD-051.
  P9 (://-unidad, regresion del propio 1.22.1) C://x contiene '://'; Contains('://') lo saltaba por URL
     y dcc lo abria como C:\x (fuera). Ahora EsEsquemaDeUrl exige 2+ letras de esquema (una unidad es 1).
     ROJA contra la 1.22.1 SIN arreglar, VERDE contra la 1.22.0 y el arreglo.

Fixture: un proyecto de consola cuyo .dpr usa Ajena, y Ajena SOLO en FUERA (fuera de la raiz) o, para
P7, en lib\ de dentro. Los grupos van ANTES del primer <Import>.
ROJA contra la 1.22.0 (python tests/test_puerta_1221.py <exe-1220>), VERDE con el build nuevo (sin arg).
"""
import os
import sys
from xml.sax.saxutils import escape
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('puerta-1221')
FUERA = mc.carpeta('puerta-1221-fuera')     # hermana de BASE, FUERA de la raiz
CARPETA = os.path.join(BASE, 'fixture')
LIB = os.path.join(CARPETA, 'lib')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
REL = os.path.relpath(FUERA, CARPETA)        # ..\..\puerta-1221-fuera
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='p1221', t=600)
AJENA = 'unit Ajena;\r\ninterface\r\nimplementation\r\nend.\r\n'


def build(proyecto):
    return srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64', 'config': 'Release'}, 600)


def compila(r):
    return mc.como_json(r).get('success') is True


def detalle(r):
    return mc.como_json(r).get('firstError') or ' '.join(str(r).split())[:260]


try:
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': CARPETA})
    check('fixture creada', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    proyecto = os.path.join(CARPETA, 'Fixture.dproj')
    open(os.path.join(FUERA, 'Ajena.pas'), 'w', encoding='utf-8').write(AJENA)
    os.makedirs(LIB)
    open(os.path.join(LIB, 'Ajena.pas'), 'w', encoding='utf-8').write(AJENA)
    dpr = os.path.join(CARPETA, 'Fixture.dpr')
    with open(dpr, encoding='utf-8-sig') as f:
        fuente = f.read()
    with open(dpr, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(fuente.replace('uses', 'uses\r\n  Ajena,', 1))
    with open(proyecto, encoding='utf-8-sig') as f:
        xml = f.read()
    assert '<Import Project=' in xml

    def con(payload):
        with open(proyecto, 'w', encoding='utf-8-sig', newline='') as f:
            f.write(xml.replace('<Import Project=', payload + '<Import Project=', 1))

    def usp(ruta):
        return '<PropertyGroup><DCC_UnitSearchPath>%s</DCC_UnitSearchPath></PropertyGroup>' % escape(ruta)

    # --- los que la puerta tiene que NEGAR (compilaban leyendo FUERA en la 1.22.0) ---
    def niega(nombre, payload):
        con(payload)
        r = build(proyecto)
        check(nombre, mc.rechazado(r) and not compila(r), detalle(r))

    niega('P1 (H1) search path con "=" antes de la barra: NEGADO (no se salta por clave=valor)',
          usp('k=v\\..\\' + REL))
    niega('P2 (H2) search path con ":" y barras detras: NEGADO (no se toma por URL)',
          usp('s\\a:b\\..\\..\\' + REL))
    niega('P3 (H2b) search path con prefijo NT \\??\\: NEGADO (se quita y se juzga la ruta real)',
          usp('\\??\\' + os.path.abspath(FUERA)))
    niega('P4 (H3) search path con %2E%2E (puntos escapados): NEGADO (se desescapa antes de juzgar)',
          usp(REL.replace('.', '%2E')))
    niega('P5 (H3b) search path con %3B (punto y coma escapado): NEGADO (se desescapa y se parte)',
          usp('dentro%3B' + REL))
    niega('P6 (H4) search path con $(ProjectDir): NEGADO (msbuild lo lee vacio, no la carpeta)',
          usp('$(ProjectDir)' + REL))
    niega('P8 (H12) search path con $( A ) (espacios, A=keep): NEGADO (no se recorta el nombre)',
          '<PropertyGroup><A>keep</A></PropertyGroup>' + usp('$( A )' + REL))

    # P9 (regresion del propio 1.22.1): C://x contiene '://'; la regla Contains('://') lo saltaba
    # como URL y dcc lo abria como C:\x, fuera de la jaula (medido 22-oct-2026). Ahora EsEsquemaDeUrl
    # exige 2+ letras de esquema (una unidad es 1). ROJA contra la 1.22.1 SIN arreglar, VERDE contra
    # el arreglo y contra la 1.22.0 (que juzgaba la ruta y la negaba).
    abs_fuera = os.path.abspath(FUERA)
    colcol = abs_fuera[0] + '://' + abs_fuera[3:]
    niega('P9 (://-unidad) search path C://<fuera> (doble barra): NEGADO (una unidad no es una URL)',
          usp(colcol))

    # --- el que la puerta tiene que DEJAR PASAR (lo negaba de mas en la 1.22.0) ---
    con('<PropertyGroup><My-Path>%s</My-Path></PropertyGroup>' % escape(LIB) + usp('$(My-Path)'))
    r = build(proyecto)
    check('P7 (H9) $(My-Path) con guion hacia lib\\ de dentro: COMPILA (msbuild acepta el "-")',
          compila(r), detalle(r))

    # --- controles: una ruta normal de dentro sigue compilando, y una de fuera sin truco se niega ---
    con(usp(LIB))
    r = build(proyecto)
    check('C1 control: un search path normal hacia lib\\ de dentro COMPILA', compila(r), detalle(r))
    con(usp(REL))
    r = build(proyecto)
    check('C2 control: un search path liso hacia FUERA se NIEGA (BUILD-050 de siempre)',
          mc.rechazado(r) and not compila(r), detalle(r))
finally:
    srv.cierra()
    mc.borra(BASE)
    mc.borra(FUERA)
mc.fin('puerta de lecturas del build 1.22.1 (H1-H4, H9, H12)')
