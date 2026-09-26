# -*- coding: utf-8 -*-
"""E2E battery: el virtual y su override son EL MISMO metodo.

La v1.0.4 arreglo el primer gemelo: una rutina Pascal tiene DOS lineas de
definicion (declaracion e implementacion) y preguntar desde una tiraba las
referencias de la otra. Queda el SEGUNDO, un nivel mas arriba: un metodo
virtual y el que lo sobrescribe.

Una llamada por una variable de la clase HIJA resuelve siempre a la hija. Asi
que preguntando por el virtual de la BASE, la tool contestaba:

    confirmed: solo sus dos lineas de declaracion  -> "no lo llama nadie"
    rejected : el override y LAS DOS LLAMADAS REALES, como homonimos

Un agente lee eso, concluye que el virtual es codigo muerto y borra la base de
la jerarquia. Es el mismo desenlace del bug de la v1.0.4.

  V1  preguntando por el VIRTUAL de la base, las llamadas reales se confirman
  V2  ...marcadas con via:"override", no camufladas como usos directos
  V3  ...y con una nota que avisa de lo que implica al renombrar
  V4  preguntando por el OVERRIDE se sigue contestando bien (no se ha roto
      el sentido que ya funcionaba)
  V5  dos clases SIN parentesco con un metodo del mismo nombre siguen siendo
      homonimos: la union exige herencia, no solo el nombre
  V6  la jerarquia de tres alturas tambien (nieta -> hija -> base)

Usage:  python tests/test_round38.py [path-to-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check


BASE = mc.carpeta('round38')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(EXEDIR)
os.makedirs(JAIL)
EXE = mc.copia_exe(EXEDIR)

# TBase.Pinta virtual -> THija override -> TNieta override.
# TAjena.Pinta NO tiene nada que ver: mismo nombre, otra familia.
UNIT = '''unit Ov;

interface

type
  TBase = class
  public
    procedure Pinta; virtual;
  end;

  THija = class(TBase)
  public
    procedure Pinta; override;
  end;

  TNieta = class(THija)
  public
    procedure Pinta; override;
  end;

  TAjena = class
  public
    procedure Pinta;
  end;

procedure Usa;

implementation

procedure TBase.Pinta;
begin
end;

procedure THija.Pinta;
begin
  inherited;
end;

procedure TNieta.Pinta;
begin
  inherited;
end;

procedure TAjena.Pinta;
begin
end;

procedure Usa;
var
  H: THija;
  N: TNieta;
  A: TAjena;
begin
  H := THija.Create;
  H.Pinta;
  H.Pinta;
  N := TNieta.Create;
  N.Pinta;
  A := TAjena.Create;
  A.Pinta;
  H.Free;
  N.Free;
  A.Free;
end;

end.
'''

# La unit va con su PROYECTO al lado. Sin el va SIN CONFIGURAR y el motor
# resuelve la declaracion y poco mas, que no es lo que mide esta bateria.
# Hasta el 2026-09-21 colaba igual, pero por accidente: la busqueda de
# configuracion subia ocho niveles sin mirar la jaula y adoptaba un
# "fuera-de-la-jaula.dproj" de 10 bytes que otra bateria habia dejado en
# %TEMP%. Al cerrar esa subida (PuedoSubirA) esta bateria se quedo sin el
# apoyo prestado y se vio lo que de verdad necesitaba.
DPR = """program P38;

uses
  Ov in 'Ov.pas';

begin
end.
"""

DPROJ = """<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <MainSource>P38.dpr</MainSource>
    <Platform>Win32</Platform>
    <DCC_UnitSearchPath>.</DCC_UnitSearchPath>
  </PropertyGroup>
</Project>
"""

os.makedirs(os.path.join(JAIL, 'u'))
PAS = os.path.join(JAIL, 'u', 'Ov.pas')
open(PAS, 'w', newline='\r\n').write(UNIT)
open(os.path.join(JAIL, 'u', 'P38.dpr'), 'w', newline='\r\n').write(DPR)
open(os.path.join(JAIL, 'u', 'P38.dproj'), 'w', newline='\r\n').write(DPROJ)
L = UNIT.split('\n')


def linea0(texto, desde=0):
    """0-based line of the first line whose stripped text equals texto."""
    for i in range(desde, len(L)):
        if L[i].strip() == texto:
            return i
    raise AssertionError('no encuentro ' + texto)


TOK = 'r38'
PORT = mc.puerto_libre()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R38]', 'Token=%s' % TOK, 'Roots=%s' % JAIL, '',
]))

proc = mc.lanza_http(EXE, PORT, mc.entorno())
cli = mc.Http(PORT, TOK, t=300)  # el plazo de esta bateria
cli.session('r38')


def refs(line0):
    col = L[line0].lower().index('pinta') + 1
    r = cli.call_msg('delphi_references',
                     {'path': PAS, 'line': line0, 'character': col})
    try:
        return json.loads(r['result']['content'][0]['text'])
    except Exception:
        return {'error': json.dumps(r)[:300]}


def tiene(j, lista, texto):
    """Algun ancla de j[lista] ('confirmed' / 'rejected') contiene texto."""
    return any(texto in c.get('anchor', '') for c in j.get(lista, []))


def llamadas(j):
    """Las LLAMADAS confirmadas (H.Pinta / N.Pinta), no las declaraciones."""
    return [c for c in j.get('confirmed', []) if '.Pinta;' in c.get('text', '')
            and not c.get('text', '').strip().startswith('procedure')]


try:
    base = linea0('procedure Pinta; virtual;')
    hija = linea0('procedure Pinta; override;')
    nieta = linea0('procedure Pinta; override;', hija + 1)
    ajena = linea0('procedure Pinta;')

    # ------------------------------------------------------------------ V1
    j = refs(base)
    ll = llamadas(j)
    check('V1 el virtual de la base ve las llamadas reales',
          len(ll) >= 3, 'confirmed=%s' % json.dumps(j.get('confirmed'))[:260])
    check('V1b ...y NO dice que no lo llama nadie',
          len(j.get('confirmed', [])) > 2, json.dumps(j)[:260])

    # ------------------------------------------------------------------ V2
    check('V2 las de la familia van marcadas via:"override"',
          all(c.get('via') == 'override' for c in ll) and ll,
          json.dumps(ll)[:260])

    # ------------------------------------------------------------------ V3
    check('V3 la respuesta avisa de lo que implica al renombrar',
          'RENOMBRAR' in j.get('familyNote', ''), str(j.get('familyNote'))[:200])

    # ------------------------------------------------------------------ V5
    # Los negativos exigen que la respuesta EXISTA: la llamada ajena tiene que
    # estar clasificada como homonimo (rejected), no solo ausente de confirmed
    # - un refs() fallido ({'error': ...}) no tiene ni una cosa ni la otra.
    check('V5 la clase SIN parentesco sigue siendo homonimo',
          tiene(j, 'rejected', 'A.Pinta') and not tiene(j, 'confirmed', 'A.Pinta'),
          json.dumps({k: j.get(k) for k in ('confirmed', 'rejected', 'error')})[:260])

    # ------------------------------------------------------------------ V6
    check('V6 la jerarquia de tres alturas tambien cuenta',
          any('N.Pinta' in c.get('anchor', '') for c in j.get('confirmed', [])),
          json.dumps(j.get('confirmed'))[:260])

    # ------------------------------------------------------------------ V4
    j2 = refs(hija)
    check('V4 preguntando por el override se sigue contestando bien',
          len(llamadas(j2)) >= 2, json.dumps(j2.get('confirmed'))[:260])
    check('V4b ...y la clase ajena tampoco entra ahi',
          tiene(j2, 'rejected', 'A.Pinta') and not tiene(j2, 'confirmed', 'A.Pinta'),
          json.dumps({k: j2.get(k) for k in ('confirmed', 'rejected', 'error')})[:260])

    # y desde la clase ajena, solo lo suyo
    j3 = refs(ajena)
    # ...y la pregunta SI resolvio su propia familia: su llamada confirmada y
    # las de la otra familia clasificadas como homonimos
    check('V5b desde la clase ajena no entra nada de la otra familia',
          tiene(j3, 'confirmed', 'A.Pinta') and
          tiene(j3, 'rejected', 'H.Pinta') and tiene(j3, 'rejected', 'N.Pinta') and
          not (tiene(j3, 'confirmed', 'H.Pinta') or tiene(j3, 'confirmed', 'N.Pinta')),
          json.dumps({k: j3.get(k) for k in ('confirmed', 'rejected', 'error')})[:260])
finally:
    try:
        proc.kill()
    except Exception:
        pass

mc.fin('test_round38')
