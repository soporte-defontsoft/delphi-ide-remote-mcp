# -*- coding: utf-8 -*-
"""E2E battery: delphi_symbols deja de dar firmas FALSAS.

El "name" que devuelve DelphiLSP en documentSymbol NO es un nombre: es una
firma RENDERIZADA, y pierde cosas. Medido con esta misma sonda:

    fuente:    function Alta(const A: string; B: Integer = 0): Boolean;
    DelphiLSP: Alta(const A: string; B: Integer): Boolean
    fuente:    FBuffer: array [0 .. 7] of Byte;
    DelphiLSP: FBuffer: Byte

Un parametro opcional pasaba por obligatorio y un array desaparecia. Lo peor
que puede hacer una tool de lectura es contestar algo falso con seguridad: el
agente respeta esa firma y escribe una llamada que no compila.

El renderizador bueno YA EXISTIA en el mismo fichero -el digest de carpeta lee
el fuente como texto y acierta-; el camino de UN fichero lo ignoraba.

  S1  la firma del summary lleva el valor por defecto
  S2  ...y el rango del array, y el "= (...)" de una constante tipada
  S3  el digest de carpeta sigue acertando (no se ha roto al compartirlo)
  S4  una rutina GLOBAL ya no se anuncia como "method" (kind 6 del LSP)
  S5  filter busca por NOMBRE: devuelve name limpio y decl real
  S6  filter NO casa por tipo ("string" daba 9 falsos por la firma)
  S7  un .dpr no sale como secciones VACIAS (su arbol es plano)
  S8  mode=full tambien lleva la declaracion real
  S9  una linea que es solo comentario no se pega dentro de la firma
  S10 el rechazo del ancla multilinea dice por donde SI se puede

Usage:  python tests/test_round36.py [path-to-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('round36')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(EXEDIR)
os.makedirs(JAIL)
EXE = mc.copia_exe(EXEDIR)

# La sonda: cada constructo que el LSP renderiza mal, uno por linea.
SONDA = '''unit Sonda;

interface

const
  TOPE = 7;
  NOMBRES: array [0 .. 2] of string = ('a', 'b', 'c');

type
  TCosa = class
  private
    FBuffer: array [0 .. 7] of Byte;
  public
    function Alta(const A: string; B: Integer = 0): Boolean;
    property Larga: string
      { una nota justo en medio de la declaracion }
      read FNombre;
  end;

function Global(const A, B: string; C: Integer = 5): string;

implementation

function Global(const A, B: string; C: Integer = 5): string;
begin
  Result := A + B;
end;

function TCosa.Alta(const A: string; B: Integer = 0): Boolean;
begin
  Result := A <> '';
end;

end.
'''

# Un .dpr: DelphiLSP devuelve su arbol PLANO, sin secciones.
DPR = '''program Sonda2;

uses
  System.SysUtils;

function Uno(A: Integer = 3): Integer;
begin
  Result := A;
end;

begin
  WriteLn(Uno);
end.
'''

os.makedirs(os.path.join(JAIL, 'u'))
PAS = os.path.join(JAIL, 'u', 'Sonda.pas')
open(PAS, 'w', newline='\r\n').write(SONDA)
DPRP = os.path.join(JAIL, 'u', 'Sonda2.dpr')
open(DPRP, 'w', newline='\r\n').write(DPR)

TOK = 'r36'
PORT = mc.puerto_libre()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R36]', 'Token=%s' % TOK, 'Roots=%s' % JAIL, '',
]))

# espera a que ESCUCHE (antes un sleep fijo de 3 s)
proc = mc.lanza_http(EXE, PORT, mc.entorno())
# sin texto, el mensaje entero en JSON: es lo que ensena el detalle de un FAIL
cli = mc.Http(PORT, TOK, t=180, respaldo_json=True)
cli.session('r36')
call = cli.call


def sinaviso(s):
    return s.split(' [warning')[0]


try:
    res = sinaviso(call('delphi_symbols', {'path': PAS, 'mode': 'summary'}))
    todas = ' || '.join(
        x for sec in json.loads(res).get('sections', [])
        for x in sec['symbols']) + ' || ' + ' || '.join(
        json.loads(res).get('symbols', []))

    # ------------------------------------------------------------------ S1
    check('S1 la firma del summary conserva el valor por defecto',
          'B: Integer = 0' in todas, todas[:220])
    check('S1b ...y tambien en la rutina global',
          'C: Integer = 5' in todas, todas[:220])

    # ------------------------------------------------------------------ S2
    check('S2 la constante tipada conserva el rango y el valor',
          "array [0 .. 2] of string = ('a', 'b', 'c')" in todas, todas[:220])

    # ------------------------------------------------------------------ S4
    check('S4 una rutina global no se anuncia como "method"',
          'function Global' in todas and 'method Global' not in todas,
          todas[:220])

    # ------------------------------------------------------------------ S9
    check('S9 una linea que es solo comentario no se pega a la firma',
          'una nota justo en medio' not in todas, todas[:260])

    # ------------------------------------------------------------------ S3
    dig = json.loads(sinaviso(call('delphi_symbols',
                                   {'path': os.path.join(JAIL, 'u')})))
    decls = [d['decl'] for u in dig['units'] for d in u['declares']]
    check('S3 el digest de carpeta sigue acertando tras compartir el lector',
          any('B: Integer = 0' in d for d in decls) and
          any('array [0 .. 7] of Byte' in d for d in decls), str(decls)[:240])

    # El pegado de comentarios SOLO se veia aqui: el digest une lineas para
    # leer una declaracion entera, y una nota en medio entraba dentro de la
    # firma. El summary no lo sufria porque no leia el fuente... que era
    # justamente el otro bug.
    check('S9b el digest tampoco pega el comentario dentro de la property',
          any('property Larga' in d for d in decls) and
          not any('una nota justo en medio' in d for d in decls),
          str(decls)[:300])

    # ------------------------------------------------------------------ S5
    fi = json.loads(sinaviso(call('delphi_symbols',
                                  {'path': PAS, 'filter': 'alta'})))
    m0 = fi['matches'][0]
    check('S5 filter devuelve el NOMBRE limpio, no la firma',
          m0['name'] in ('Alta', 'TCosa.Alta'), json.dumps(m0)[:200])
    check('S5b ...y la declaracion REAL aparte',
          'B: Integer = 0' in m0.get('decl', ''), json.dumps(m0)[:200])

    # ------------------------------------------------------------------ S6
    fs = json.loads(sinaviso(call('delphi_symbols',
                                  {'path': PAS, 'filter': 'string'})))
    check('S6 filter no casa por TIPO (buscaba dentro de la firma)',
          fs['total'] == 0, json.dumps(fs)[:200])
    check('S6b ...y el cero se explica, no se deja a secas',
          'NOMBRE' in fs.get('note', ''), json.dumps(fs)[:200])

    # ------------------------------------------------------------------ S8
    fu = sinaviso(call('delphi_symbols', {'path': PAS, 'mode': 'full'}))
    check('S8 mode=full tambien lleva la declaracion real',
          '"decl"' in fu and 'B: Integer = 0' in fu, fu[:200])

    # ------------------------------------------------------------------ S7
    dp = json.loads(sinaviso(call('delphi_symbols',
                                  {'path': DPRP, 'mode': 'summary'})))
    vacias = [s['section'] for s in dp.get('sections', []) if not s['symbols']]
    # un resumen DE VERDAD (con sus simbolos) y sin secciones vacias: una
    # respuesta vacia o el JSON de respaldo no traen 'sections' y pasaban
    check('S7 un .dpr no sale como secciones VACIAS',
          dp.get('mode') == 'summary' and bool(dp.get('symbols')) and not vacias,
          'vacias: %s | %s' % (vacias, json.dumps(dp)[:160]))
    check('S7b ...sus rutinas salen como simbolos de primer nivel',
          any('Uno' in x for x in dp.get('symbols', [])),
          json.dumps(dp)[:240])

    # ----------------------------------------------------------------- S10
    r = call('delphi_textedit', {'path': os.path.join(JAIL, 'u', 'x.md'),
                                 'create': True, 'content': 'a\nb\nc\n'})
    r = call('delphi_textedit', {'path': os.path.join(JAIL, 'u', 'x.md'),
                                 'old': 'a\nb', 'new': 'z'})
    check('S10 el rechazo del ancla multilinea manda a edits y a toline',
          'edits' in r and 'toline' in r and 'una llamada por linea' not in r,
          r[:240])
    r2 = call('delphi_edit', {'path': PAS, 'old': 'begin\nend;', 'new': 'x'})
    check('S10b ...y el gemelo Pascal dice lo MISMO',
          'edits' in r2 and 'toline' in r2, r2[:240])
finally:
    try:
        proc.kill()
    except Exception:
        pass

mc.fin('test_round36')
