# -*- coding: utf-8 -*-
"""R1 de la 1.19.2 (medido el 15-oct al reproducir el H5-01 de Hermes):
references y rename_symbol daban por CONFIRMADOS, marcados via:"override",
simbolos que solo se llamaban igual. El parentesco entre clases se decidia por
el NOMBRE simple de la clase (sin su unidad) y una clase contaba como pariente
de si misma, asi que:

  - una clase TFoo declarada en DOS unidades sin relacion: todo lo de la otra
    unidad salia confirmado (y rename lo escribia: filesTouched 2);
  - una SOBRECARGA Sobre(string) salia como override de Sobre(Integer);
  - dos jerarquias homonimas (TBaseH/TDerH en dos unidades) se mezclaban.

Ahora el parentesco lo verifica EL MOTOR salto a salto (la definicion del
ancestro escrito en class(...)), una clase no es pariente de si misma, y el
TFoo de una cabecera cualificada 'procedure TFoo.Pinta;' - que el motor
resuelve al METODO - es la propia clase (un miembro suyo), no un pariente.

  R1 TFoo de UHomoA: nada de UHomoB confirmado            (ROJO en produccion)
  R2 ...y su cabecera 'procedure TFoo.Pinta;' confirmada SIN via (ROJO: via override)
  R3 Pinta de UHomoA: nada de UHomoB confirmado           (ROJO)
  R4 rename TFoo de UHomoA: aplicable y UN solo fichero   (ROJO: 2)
  O1 Sobre(Integer): ninguna confirmada via override      (ROJO)
  O2 ...la sobrecarga Sobre(string) y su llamada, rechazadas (ROJO)
  O3 control: Sobre(1) y su cabecera, confirmadas
  J1 control: la familia real (TDerH.Pinta y D.Pinta de UHier1), via override
  J2 nada de UHier2 (la jerarquia homonima, con las MISMAS lineas) confirmado (ROJO)
  J3 LSP-003 de rename dice que las lineas aqui son 0-based (ROJO: "delphi_read gives you line and column")

Uso:  python tests/test_referencias_familia_1192.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('referencias_familia_1192')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def homonima(nombre):
    return ('unit %s;\n\ninterface\n\ntype\n  TFoo = class\n    procedure Pinta;\n  end;\n\nimplementation\n\n'
            'procedure TFoo.Pinta;\nbegin\nend;\n\nprocedure Usa;\nvar\n  F: TFoo;\nbegin\n  F := TFoo.Create;\n'
            '  F.Pinta;\n  F.Free;\nend;\n\nend.\n' % nombre)


SOBRECARGA = ('unit UOver;\n\ninterface\n\ntype\n  TCosa = class\n    procedure Sobre(A: Integer); overload;\n'
              '    procedure Sobre(const S: string); overload;\n    procedure Pinta;\n  end;\n\nimplementation\n\n'
              'procedure TCosa.Sobre(A: Integer);\nbegin\nend;\n\nprocedure TCosa.Sobre(const S: string);\nbegin\nend;\n\n'
              'procedure TCosa.Pinta;\nbegin\n  Sobre(1);\n  Sobre(\'x\');\nend;\n\nend.\n')


def jerarquia(nombre):
    # las dos con las MISMAS lineas: un parentesco comparado solo por linea las mezcla
    return ('unit %s;\n\ninterface\n\ntype\n  TBaseH = class\n    procedure Pinta; virtual;\n'
            '    // la linea de debajo de la declaracion, con texto en su columna (J3)\n  end;\n\n'
            '  TDerH = class(TBaseH)\n    procedure Pinta; override;\n  end;\n\nprocedure Usa;\n\nimplementation\n\n'
            'procedure TBaseH.Pinta;\nbegin\nend;\n\nprocedure TDerH.Pinta;\nbegin\n  inherited;\nend;\n\n'
            'procedure Usa;\nvar\n  D: TDerH;\nbegin\n  D := TDerH.Create;\n  D.Pinta;\n  D.Free;\nend;\n\nend.\n' % nombre)


def J(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


def hits(t, campo, fichero=None):
    return [h for h in mc.aciertos(t, campo) if fichero is None or h.get('path', '').endswith(fichero)]


def textos(t, campo, fichero=None):
    return sorted(h['text'].strip() for h in hits(t, campo, fichero))


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='referencias-familia', t=300)
try:
    d = os.path.join(JAIL, 'P')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'P', 'dir': d}, t=120)
    dpr = os.path.join(d, 'P.dpr')
    for nombre, texto in (('UHomoA', homonima('UHomoA')), ('UHomoB', homonima('UHomoB')), ('UOver', SOBRECARGA),
                          ('UHier1', jerarquia('UHier1')), ('UHier2', jerarquia('UHier2'))):
        srv.call('delphi_create', {'kind': 'unit', 'name': nombre, 'project': dpr, 'content': texto}, t=120)

    # ---- las homonimas: TFoo y Pinta de UHomoA
    LA = homonima('UHomoA').split('\n')
    pas_a = os.path.join(d, 'UHomoA.pas')
    decl = LA.index('  TFoo = class')
    r = srv.call('delphi_references', {'path': pas_a, 'line': decl, 'character': 3}, t=240)
    check('R1 TFoo de UHomoA: nada de UHomoB entre las confirmadas',
          hits(r, 'confirmed') and not hits(r, 'confirmed', 'UHomoB.pas'),
          textos(r, 'confirmed', 'UHomoB.pas') or r[:300])
    cab = [h for h in hits(r, 'confirmed', 'UHomoA.pas') if h['text'].strip() == 'procedure TFoo.Pinta;']
    check('R2 ...y la cabecera procedure TFoo.Pinta; de UHomoA confirmada, SIN via (es la propia clase)',
          len(cab) == 1 and 'via' not in cab[0], cab or textos(r, 'confirmed', 'UHomoA.pas'))
    pinta = LA.index('    procedure Pinta;')
    r = srv.call('delphi_references', {'path': pas_a, 'line': pinta, 'character': LA[pinta].index('Pinta')}, t=240)
    check('R3 Pinta de UHomoA: nada de UHomoB entre las confirmadas',
          hits(r, 'confirmed') and not hits(r, 'confirmed', 'UHomoB.pas'),
          textos(r, 'confirmed', 'UHomoB.pas') or r[:300])
    r = srv.call('delphi_rename_symbol', {'path': pas_a, 'line': decl, 'character': 3, 'newname': 'TFoo2'}, t=240)
    j = J(r)
    # (en produccion: applicable=true y filesTouched=2, los TFoo de UHomoB entre los cambios. Ahora son
    # "parecidos" que resuelven a OTRA definicion, y rename se niega con RENAME-017 - la barrera del
    # 25-ago-2026, que se queda - en vez de escribir en la otra unidad)
    look = mc.aciertos(r, 'lookalikes')
    check('R4 rename TFoo de UHomoA (preview): no escribe en UHomoB - sus TFoo son parecidos (RENAME-017) y los '
          'cambios son de UN fichero',
          j.get('applicable') is False and any('RENAME-017' in b for b in j.get('blockers', []))
          and j.get('filesTouched') == 1 and look and all(h['path'].endswith('UHomoB.pas') for h in look),
          {'applicable': j.get('applicable'), 'filesTouched': j.get('filesTouched'), 'blockers': j.get('blockers'),
           'lookalikes': [h.get('text') for h in look]})

    # ---- la sobrecarga
    LO = SOBRECARGA.split('\n')
    pas_o = os.path.join(d, 'UOver.pas')
    ent = LO.index('    procedure Sobre(A: Integer); overload;')
    r = srv.call('delphi_references', {'path': pas_o, 'line': ent, 'character': LO[ent].index('Sobre')}, t=240)
    conf = hits(r, 'confirmed')
    check('O1 Sobre(Integer): ninguna confirmada via override (una sobrecarga no es un override)',
          conf and not any(h.get('via') for h in conf), [h['text'].strip() for h in conf if h.get('via')] or r[:300])
    rech = textos(r, 'rejected')
    check('O2 ...la sobrecarga Sobre(string): su cabecera y su llamada, rechazadas (no confirmadas)',
          "Sobre('x');" in rech and 'procedure TCosa.Sobre(const S: string);' in rech
          and "Sobre('x');" not in textos(r, 'confirmed'), rech)
    check('O3 control: Sobre(1) y la cabecera de Sobre(Integer), confirmadas',
          'Sobre(1);' in textos(r, 'confirmed') and 'procedure TCosa.Sobre(A: Integer);' in textos(r, 'confirmed'),
          textos(r, 'confirmed'))

    # ---- las dos jerarquias homonimas
    LH = jerarquia('UHier1').split('\n')
    pas_h = os.path.join(d, 'UHier1.pas')
    virt = LH.index('    procedure Pinta; virtual;')
    r = srv.call('delphi_references', {'path': pas_h, 'line': virt, 'character': LH[virt].index('Pinta')}, t=240)
    de1 = {h['text'].strip(): h for h in hits(r, 'confirmed', 'UHier1.pas')}
    check('J1 control: la familia real de UHier1 (TDerH.Pinta y D.Pinta), via override',
          de1.get('procedure TDerH.Pinta;', {}).get('via') == 'override'
          and de1.get('D.Pinta;', {}).get('via') == 'override' and 'via' not in de1.get('procedure TBaseH.Pinta;', {'via': 1}),
          sorted(de1))
    check('J2 nada de UHier2 (la jerarquia homonima, con las mismas lineas) entre las confirmadas',
          not hits(r, 'confirmed', 'UHier2.pas'), textos(r, 'confirmed', 'UHier2.pas'))

    # ---- el texto de LSP-003: la linea 1-based de delphi_read en el parametro 0-based (el H5-01 de Hermes)
    r = srv.call('delphi_rename_symbol', {'path': pas_h, 'line': virt + 1, 'character': LH[virt].index('Pinta'),
                                          'newname': 'Pinta2'}, t=240)
    check('J3 LSP-003 de rename dice que las lineas son 0-based aqui (N de un read es N-1), y no manda a delphi_read',
          'LSP-003' in r and 'N-1' in r and 'gives you line and column' not in r, r[:400])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('references y rename: el parentesco lo verifica el motor (R1 de la 1.19.2)')
