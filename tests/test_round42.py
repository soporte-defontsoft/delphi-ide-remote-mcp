# -*- coding: utf-8 -*-
"""E2E battery: la respuesta del motor puede venir de OTRO workspace.

El indice del motor le sobrevive al servidor. Una unit SIN CONFIGURAR (sin
.delphilsp.json ni .dproj cerca) se resuelve contra otra unit del mismo
nombre que el motor indexo en una sesion anterior - de otro proceso, de otra
jaula, de otro usuario del servidor.

Esa ruta ajena se daba por buena y viajaba hasta el primer sitio que tocaba
la jaula, donde reventaba la llamada ENTERA con un RECHAZADO... que escupia
la ruta. Dos fallos en el mismo punto: una respuesta imposible (buscar los
usos de un simbolo que no es el tuyo) y una fuga (el que pregunta se entera
de que hay otro workspace y de como se llama su carpeta).

La bateria monta la contaminacion a proposito: jaula A indexa el nombre,
jaula B pregunta por el mismo nombre.

Usage:  python tests/test_round42.py [path-to-DelphiLspMcp.exe]
"""
import json
import os
import time
import uuid
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('round42')

# Unico por pasada: lo que se mide es la contaminacion que monta ESTA
# bateria entre sus dos jaulas, no la que dejaron las anteriores.
IDENT = 'Cruza' + uuid.uuid4().hex[:8]

UNIT = """unit Cru;

interface

type
  TCosa = class
    procedure %s;
  end;

implementation

procedure TCosa.%s;
begin
end;

procedure Usa;
var
  C: TCosa;
begin
  C := TCosa.Create;
  C.%s;
  C.Free;
end;

end.
""" % (IDENT, IDENT, IDENT)


def monta(nombre):
    """Una jaula con su servidor propio. Devuelve (exedir, jail, pas)."""
    exedir = os.path.join(BASE, nombre, 'srv')
    jail = os.path.join(BASE, nombre, 'jail')
    os.makedirs(os.path.join(jail, 'u'), exist_ok=True)
    mc.copia_exe(exedir)
    pas = os.path.join(jail, 'u', 'Cru.pas')
    open(pas, 'w', newline='\r\n').write(UNIT)
    return exedir, jail, pas


class Servidor:
    def __init__(self, exedir, jail, tok):
        self.tok = tok
        self.port = mc.puerto_libre()
        open(os.path.join(exedir, 'settings.ini'), 'w').write('\n'.join([
            '[Server]', 'BindIP=127.0.0.1', '',
            '[Workspace.%s]' % tok.upper(), 'Token=%s' % tok,
            'Roots=%s' % jail, '']))
        self.proc = mc.lanza_http(os.path.join(exedir, 'DelphiLspMcp.exe'), self.port,
                                  mc.entorno())
        # sin texto, el mensaje entero en JSON: es lo que ensena el detalle
        self.cli = mc.Http(self.port, tok, t=300, respaldo_json=True)
        self.cli.session(tok)

    def refs(self, pas, line, col):
        return self.cli.call('delphi_references',
                             {'path': pas, 'line': line, 'character': col})

    def para(self):
        try:
            self.proc.kill()
        except Exception:
            pass
        time.sleep(1)


L = UNIT.split('\n')
DECL = [i for i, x in enumerate(L) if x.strip() == 'procedure %s;' % IDENT][0]
COL = L[DECL].lower().index(IDENT.lower())

exeA, jailA, pasA = monta('A')
exeB, jailB, pasB = monta('B')
a = b = None
respuestas = {}
try:
    # Las DOS jaulas existen a la vez, con el mismo nombre de unit y el mismo
    # identificador: es la contaminacion, montada a proposito. Cual de las dos
    # elige el motor no se puede mandar, asi que no se mide ESO: se mide el
    # invariante, que vale siempre y es el que importa.
    a = Servidor(exeA, jailA, 'r42a')
    respuestas['A'] = a.refs(pasA, DECL, COL)
    a.para()
    b = Servidor(exeB, jailB, 'r42b')
    respuestas['B'] = b.refs(pasB, DECL, COL)
    b.para()

    ajena = {'A': jailB, 'B': jailA}
    for quien in ('A', 'B'):
        r = respuestas[quien]
        otra = ajena[quien]
        propia = {'A': jailA, 'B': jailB}[quien].lower()
        try:
            j = json.loads(r)
        except Exception:
            j = {}
        if not isinstance(j, dict):
            j = {}
        # Las DOS salidas legitimas, y solo ellas: contestar sobre SU simbolo
        # (el JSON de referencias), o el error que se entiende cuando el motor
        # resuelve la definicion fuera ("no busco sus usos"). Un timeout, un
        # error cualquiera o la negativa cruda de la jaula no son ninguna.
        contesta = j.get('identifier') == IDENT
        se_niega = (r.startswith('error:') and 'FUERA de este workspace' in r
                    and IDENT in r)
        print('  (jaula %s: el motor %s)' % (quien, 'contesta con referencias' if contesta else
              'resuelve fuera y se niega' if se_niega else 'NO da ninguna salida legitima'))

        # -------------------------------------------------------------- X1
        # EL INVARIANTE: pase lo que pase por dentro, en la respuesta no
        # puede salir una ruta de OTRO workspace. Este servidor sirve varios
        # [Workspace.X] con tokens distintos, asi que esto no es estetica.
        check('X1%s la respuesta de la jaula %s no nombra la otra jaula'
              % (quien.lower(), quien),
              (contesta or se_niega) and otra.lower() not in r.lower(),
              'se ha colado %s en: %s' % (otra, r[:240]))

        # -------------------------------------------------------------- X2
        # Y no puede morir con la negativa cruda de la jaula: eso es el
        # sintoma de haber dado por buena una ruta que no era de aqui.
        check('X2%s ...ni muere con un RECHAZADO de jaula' % quien.lower(),
              (contesta or se_niega) and 'FUERA de los workspaces permitidos' not in r,
              r[:240])

        # -------------------------------------------------------------- X3
        # SIEMPRE los mismos dos checks, sea cual sea la salida que elija el
        # motor (antes eran uno u otros dos segun la pasada). No se mide
        # CUANTAS confirma: estas units van sin configurar a proposito y el
        # motor resuelve lo que puede.
        defe = (j.get('definition') or {}).get('path', '')
        # X3: habla de lo SUYO - su fichero si contesta; su identificador y
        # el porque (SIN CONFIGURAR, mira con delphi_definition) si se niega
        check('X3%s la respuesta habla de su propio fichero'
              % quien.lower(),
              (contesta and propia in defe.lower().replace('srvc:', 'c:')) or
              (se_niega and 'SIN CONFIGURAR' in r and 'delphi_definition' in r),
              'identifier=%s definition=%s | %s' % (j.get('identifier'), defe, r[:200]))
        # X3-b: mira SOLO dentro de su jaula - o no mira en ningun sitio
        check('X3%s-b ...y solo mira dentro de su jaula'
              % quien.lower(),
              (contesta and bool(j.get('scope')) and
               all(propia in s.lower().replace('srvc:', 'c:')
                   for s in j.get('scope', []))) or
              (se_niega and 'no busco sus usos' in r),
              'scope=%s | %s' % (j.get('scope'), r[:200]))
finally:
    for s in (a, b):
        if s:
            s.para()

mc.fin('test_round42')
