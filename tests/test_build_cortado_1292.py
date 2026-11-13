# -*- coding: utf-8 -*-
"""1.29.2 (C3): delphi_build PERDIA un mensaje de dcc cuando su linea pasa de 128 caracteres. dcc corta el principio
(la ruta y el numero de linea) y la tarea de msbuild ya no reconoce la linea como error ni aviso: no llegaba a errors.log
ni a warnings.log, y el agente veia el F2063 del .dpr (o un MSB6006) sin la causa. Medido el 12 y el 13-nov-2026 (los
ejemplos rotos del dataset y una sonda en test-mcp-server\\C3); el arreglo lee el log de /flp3 (minimal), donde esos
mensajes quedan con la forma de dcc (Lsp.BuildRunner.MensajesSinClasificar).

  K1 un E2065 en una ruta honda: sale en errors, PRIMERO (firstError), y BUILD-074 lo dice. ROJO contra 1.29.1 (solo F2063)
  K2 un F2613 en una ruta honda: sale primero y missingUnits trae la unidad. ROJO contra 1.29.1 (solo MSB6006)
  K3 un aviso y una pista en una ruta honda (normal): en warnings y en hints, y la cola no los repite. ROJO contra 1.29.1
  K4 lo mismo en quiet: sin avisos y sin nota (no se piden)
  K5 la misma unidad rota en una ruta corta: como siempre (la forma de msbuild, con su linea) y sin nota

Uso:  python tests/test_build_cortado_1292.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build_cortado_1292')
EXE = mc.copia_exe(BASE)
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='cortado1292', t=600)

# el r02 del dataset: un metodo declarado y no implementado (E2065 en la linea 11)
COUNTERS = '''unit Counters;

interface

type
  TCounter = class
  private
    FValue: Integer;
  public
    procedure Increment;
    procedure Reset;
    property Value: Integer read FValue;
  end;

implementation

procedure TCounter.Increment;
begin
  Inc(FValue);
end;

end.
'''
# una unidad que no existe (F2613)
NAMEFIELD = '''unit NameField;

interface

uses
  FMX.Editors;

implementation

end.
'''
# un aviso (W1036) y una pista (H2164), y compila
NAMEHINT = '''unit NameHint;

interface

function Twice(const A: Integer): Integer;

implementation

function Twice(const A: Integer): Integer;
var
  Unused: Integer;
  Maybe: Integer;
begin
  if A > 100 then
    Maybe := 1;
  Result := A * 2 + Maybe;
end;

end.
'''


def escribe(carpeta, nombre, texto):
    os.makedirs(carpeta, exist_ok=True)
    ruta = os.path.join(carpeta, nombre)
    with open(ruta, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(texto.replace('\n', '\r\n'))
    return ruta


def proyecto(nombre, unidad):
    d = os.path.join(BASE, nombre)
    r = S.call('delphi_create', {'kind': 'project-console', 'name': nombre, 'dir': d})
    check('preparacion: el proyecto %s' % nombre, not mc.fallo(r), r[:200])
    dproj = os.path.join(d, nombre + '.dproj')
    r = S.call('delphi_config', {'command': 'add-unit', 'project': dproj, 'path': unidad})
    check('preparacion: %s en %s' % (os.path.basename(unidad), nombre), not mc.fallo(r), r[:200])
    return dproj


def build(dproj, verbosity='quiet'):
    return mc.como_json(S.call('delphi_build', {'project': dproj, 'verbosity': verbosity}, 600)) or {}


try:
    # la ruta honda pasa de 128 con "(11)" detras; la corta no llega (lo que dcc imprime es la ruta LARGA)
    HONDA = os.path.join(BASE, 'deep', 'a' * 32, 'b' * 32, 'c' * 32)
    CORTA = os.path.join(BASE, 'short')
    honda = escribe(HONDA, 'Counters.pas', COUNTERS)
    corta = escribe(CORTA, 'Counters.pas', COUNTERS)
    campo = escribe(HONDA, 'NameField.pas', NAMEFIELD)
    pista = escribe(HONDA, 'NameHint.pas', NAMEHINT)
    check('preparacion: la ruta honda pasa de 128 caracteres y la corta no',
          len(mc.larga(honda) + '(11)') > 140 and len(mc.larga(corta) + '(11)') < 120,
          (len(mc.larga(honda)), len(mc.larga(corta))))

    # ------------------------------------------------------------------ K1
    j = build(proyecto('PDeep', honda))
    e = j.get('errors') or []
    check('K1 un E2065 en una ruta honda: sale en errors, primero y como firstError, delante del F2063. '
          'ROJO contra 1.29.1',
          j.get('success') is False and e and 'E2065' in e[0] and "'TCounter.Reset'" in e[0] and
          j.get('firstError') == e[0] and any('F2063' in x for x in e[1:]), e)
    check('K1 ...y BUILD-074 lo dice (1 mensaje)',
          mc.abre(j.get('cutMessagesNote', ''), 'SN_BUILD_CUT_MESSAGES_FMT') and
          ' 1 of its messages' in j.get('cutMessagesNote', ''), j.get('cutMessagesNote'))

    # ------------------------------------------------------------------ K2
    j = build(proyecto('PField', campo))
    e = j.get('errors') or []
    check('K2 un F2613 en una ruta honda: sale primero, y missingUnits trae FMX.Editors. ROJO contra 1.29.1',
          j.get('success') is False and e and 'F2613' in e[0] and "'FMX.Editors'" in e[0] and
          'FMX.Editors' in [m.get('unit') for m in j.get('missingUnits') or []], (e, j.get('missingUnits')))

    # ------------------------------------------------------------------ K3, K4
    PH = proyecto('PHint', pista)
    j = build(PH, 'normal')
    w, h = j.get('warnings') or [], j.get('hints') or []
    check('K3 un aviso y una pista en una ruta honda (normal): W1036 en warnings, H2164 en hints. ROJO contra 1.29.1',
          j.get('success') is True and any('W1036' in x for x in w) and any('H2164' in x for x in h), (w, h))
    check('K3 ...la nota cuenta los dos, y la cola no los repite',
          ' 2 of its messages' in j.get('cutMessagesNote', '') and
          'W1036' not in j.get('outputTail', '') and 'H2164' not in j.get('outputTail', ''),
          (j.get('cutMessagesNote'), j.get('outputTail')))
    j = build(PH, 'quiet')
    check('K4 lo mismo en quiet: compila, sin warnings (no se piden) y sin nota',
          j.get('success') is True and 'warnings' not in j and 'cutMessagesNote' not in j, str(j)[:400])

    # ------------------------------------------------------------------ K5
    j = build(proyecto('PShort', corta))
    e = j.get('errors') or []
    check('K5 la misma unidad rota en una ruta corta: la forma de msbuild con su linea, y sin nota',
          e and '(11): error E2065:' in e[0] and 'cutMessagesNote' not in j, (e, j.get('cutMessagesNote')))
finally:
    S.cierra()
    mc.borra(BASE)
mc.fin('build: mensajes de dcc cortados (1.29.2, C3)')
