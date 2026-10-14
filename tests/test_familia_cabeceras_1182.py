# -*- coding: utf-8 -*-
"""Punto 6 de la 1.18.2 (rondas de la 1.18.1: "via override en cabeceras de
metodos, familyNote enganoso"; MEDIDO en produccion el 14-oct): references de
TBase.Q marca con via:"override" las CABECERAS de TDer.Q - su declaracion
'procedure Q; override;' y su implementacion 'procedure TDer.Q;' - igual que
la llamada D.Q, y LSP-012 dice de todas que son llamadas ("counted as its uses
on purpose: a call through a variable of the child class..."). Ahora las
cabeceras de un pariente llevan header:true, y la nota distingue.

  F1 la declaracion y la implementacion de TDer.Q: via override y header:true
     (ROJO en produccion)
  F2 la llamada D.Q: via override SIN header
  F3 control: lo de TBase (sus cabeceras y B.Q) sigue confirmado sin via

Y "un metodo &Begin y una clase generica, verificar contra el motor" (MEDIDO
en produccion el 14-oct): el generico va bien; con &Begin cada 'begin' del
proyecto - la PALABRA reservada - salia candidato sin verificar, y la llamada
C.&Begin queda sin verificar porque el MOTOR no la resuelve (null; la cabecera
si): eso es honrado y se queda.
  G1 references de &Begin: ninguna linea 'begin' entre lo encontrado (ROJO en
     produccion: 7)
  G2 sus dos cabeceras, confirmadas
  G3 control: el metodo de la clase generica, 4 confirmadas

Y un metodo DE CLASE (M2 del revisor de cierre, medido): el lector de cabeceras
(ColumnaDelNombreDeRutina) no admitia 'class' delante, y las cabeceras de
TDer.Q salian como llamadas:
  H1 references de TBase.Q (class procedure): las cabeceras de TDer.Q con
     header:true (ROJO en produccion)
  H2 la llamada TDer.Q: via override sin header

Uso:  python tests/test_familia_cabeceras_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('familia_cabeceras_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
UNIDAD = ('unit UFamilia;\n\ninterface\n\ntype\n  TBase = class\n  public\n    procedure Q; virtual;\n  end;\n\n'
          '  TDer = class(TBase)\n  public\n    procedure Q; override;\n  end;\n\nprocedure Usa;\n\n'
          'implementation\n\nprocedure TBase.Q;\nbegin\nend;\n\nprocedure TDer.Q;\nbegin\n  inherited;\nend;\n\n'
          'procedure Usa;\nvar\n  B: TBase;\n  D: TDer;\nbegin\n  B := TBase.Create;\n  D := TDer.Create;\n'
          '  B.Q;\n  D.Q;\n  B.Free;\n  D.Free;\nend;\n\nend.\n')


ESCAPADOS = ('unit UEscapados;\n\ninterface\n\ntype\n  TCosa = class\n  public\n    procedure &Begin;\n  end;\n\n'
             '  TLista<T> = class\n  public\n    procedure Agrega(const A: T);\n  end;\n\nprocedure Usa;\n\n'
             'implementation\n\nprocedure TCosa.&Begin;\nbegin\nend;\n\nprocedure TLista<T>.Agrega(const A: T);\n'
             'begin\nend;\n\nprocedure Usa;\nvar\n  C: TCosa;\n  L: TLista<Integer>;\nbegin\n  C := TCosa.Create;\n'
             '  C.&Begin;\n  L := TLista<Integer>.Create;\n  L.Agrega(1);\n  L.Agrega(2);\n  C.Free;\n  L.Free;\n'
             'end;\n\nend.\n')


CLASE = ('unit UClase;\n\ninterface\n\ntype\n  TBaseC = class\n  public\n    class procedure Q; virtual;\n  end;\n\n'
         '  TDerC = class(TBaseC)\n  public\n    class procedure Q; override;\n  end;\n\nprocedure UsaC;\n\n'
         'implementation\n\nclass procedure TBaseC.Q;\nbegin\nend;\n\nclass procedure TDerC.Q;\nbegin\n  inherited;\nend;\n\n'
         'procedure UsaC;\nbegin\n  TBaseC.Q;\n  TDerC.Q;\nend;\n\nend.\n')
LC = CLASE.split('\n')


def hits(r):
    try:
        j = json.loads(r)
    except Exception:
        return {}
    out = {}
    for d in j.get('confirmed', []):
        for f in d.get('files', []):
            for h in f.get('hits', []):
                out[h['line0']] = h
    return out


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='familia-cabeceras', t=300)
try:
    d = os.path.join(JAIL, 'P')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'P', 'dir': d}, t=120)
    srv.call('delphi_create', {'kind': 'unit', 'name': 'UFamilia', 'project': os.path.join(d, 'P.dpr'),
                               'content': UNIDAD}, t=120)
    pas = os.path.join(d, 'UFamilia.pas')
    r = srv.call('delphi_references', {'path': pas, 'line': 7, 'character': 14}, t=240)
    h = hits(r)
    check('F1 las cabeceras de TDer.Q (declaracion e implementacion): via override y header:true',
          all(h.get(n, {}).get('via') == 'override' and h.get(n, {}).get('header') is True for n in (12, 23)),
          r[:600])
    check('F2 la llamada D.Q: via override sin header',
          h.get(36, {}).get('via') == 'override' and 'header' not in h.get(36, {}), h.get(36))
    check('F3 control: las de TBase y B.Q, confirmadas sin via',
          all(n in h and 'via' not in h[n] for n in (7, 19, 35)), sorted(h))

    srv.call('delphi_create', {'kind': 'unit', 'name': 'UEscapados', 'project': os.path.join(d, 'P.dpr'),
                               'content': ESCAPADOS}, t=120)
    pas = os.path.join(d, 'UEscapados.pas')
    r = srv.call('delphi_references', {'path': pas, 'line': 7, 'character': 15}, t=240)
    textos = []
    try:
        j = json.loads(r)
        for grupo in ('confirmed', 'unverified'):
            for dd in j.get(grupo, []):
                for f in dd.get('files', []):
                    textos += [x['text'].strip() for x in f.get('hits', [])]
    except Exception:
        pass
    check('G1 references de &Begin: ninguna linea begin (la palabra) entre lo encontrado',
          textos and not any(t.lower() == 'begin' for t in textos), textos)
    h = hits(r)
    check('G2 las dos cabeceras de &Begin, confirmadas', 7 in h and 19 in h, sorted(h))
    r = srv.call('delphi_references', {'path': pas, 'line': 12, 'character': 15}, t=240)
    check('G3 control: el metodo de la clase generica, 4 confirmadas', len(hits(r)) == 4, sorted(hits(r)))

    srv.call('delphi_create', {'kind': 'unit', 'name': 'UClase', 'project': os.path.join(d, 'P.dpr'),
                               'content': CLASE}, t=120)
    pas = os.path.join(d, 'UClase.pas')
    decl = LC.index('    class procedure Q; virtual;')
    r = srv.call('delphi_references', {'path': pas, 'line': decl, 'character': LC[decl].index('Q')}, t=240)
    h = hits(r)
    cabeceras = [LC.index('    class procedure Q; override;'), LC.index('class procedure TDerC.Q;')]
    check('H1 las cabeceras de un metodo de CLASE del hijo: via override y header:true',
          all(h.get(n, {}).get('via') == 'override' and h.get(n, {}).get('header') is True for n in cabeceras),
          r[:700])
    llamada = LC.index('  TDerC.Q;')
    check('H2 la llamada TDerC.Q: via override sin header',
          h.get(llamada, {}).get('via') == 'override' and 'header' not in h.get(llamada, {}), h.get(llamada))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('references: las cabeceras de la familia 1182 (punto 6)')
