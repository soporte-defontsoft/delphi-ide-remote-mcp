# -*- coding: utf-8 -*-
"""delphi_definition kind=implementation (1.20, Hermes en la VM 13.2 y medido aqui en
13.1): la descripcion decia "DelphiLSP answers it like declaration - measured", y la
peticion textDocument/implementation contesta, sobre una LLAMADA, la declaracion del
metodo que la CONTIENE (ShowMessage dentro de TFormMain.Greet -> Greet): otra cosa que
el simbolo pedido. La implementacion de un simbolo es su cuerpo, lo que da definition:
desde la 1.20 kind=implementation es definition.

  D1 definition de una llamada a una rutina de otra unidad: su cuerpo (UComun)
  D2 kind=implementation: lo MISMO que D1, nunca el metodo que contiene la llamada
     (ROJO en 3cc31fc: UsoZ.pas, la cabecera de Llama)
  D3 kind=declaration: la de la interface de UComun
  D4 kind=declaration desde la CABECERA del cuerpo de Saluda: la de la interface (1.22.1; ROJO
     contra la 1.22.0: el cuerpo - definition ya es la declaracion y la cadena seguia al cuerpo)
  D5 lo mismo con un metodo, TFoo.Bar: su declaracion en la clase (ROJO igual)
  D6 control: kind=declaration desde la propia declaracion de la interface, ella misma

Uso:  python tests/test_definition_implementation_120.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('definition_implementation_120')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='def-impl', t=300)
call = srv.call
try:
    d = os.path.join(JAIL, 'p')
    call('delphi_create', {'kind': 'project-console', 'name': 'P', 'dir': d})
    dproj = os.path.join(d, 'P.dproj')
    comun = os.path.join(d, 'UComun.pas')
    uso = os.path.join(d, 'UsoZ.pas')
    # UComun: 0 unit, 1 interface, 2 procedure Saluda;, 3 implementation, 4 procedure Saluda;
    open(comun, 'w', newline='\r\n').write(
        'unit UComun;\ninterface\nprocedure Saluda;\nimplementation\nprocedure Saluda;\nbegin\nend;\nend.\n')
    # UsoZ: la llamada a Saluda en la linea 0-based 7, columna 2..7
    open(uso, 'w', newline='\r\n').write(
        'unit UsoZ;\ninterface\nprocedure Llama;\nimplementation\nuses UComun;\n'
        'procedure Llama;\nbegin\n  Saluda;\nend;\nend.\n')
    clase = os.path.join(d, 'UClaseZ.pas')
    # UClaseZ: 5 la declaracion de Bar en la clase, 8 la cabecera de su cuerpo (Bar en la col 14)
    open(clase, 'w', newline='\r\n').write(
        'unit UClaseZ;\ninterface\ntype\n  TFoo = class\n  public\n    function Bar(A: Integer): Integer;\n'
        '  end;\nimplementation\nfunction TFoo.Bar(A: Integer): Integer;\nbegin\n  Result := A + 1;\nend;\nend.\n')
    for u in (uso, comun, clase):
        call('delphi_config', {'command': 'add-unit', 'project': dproj, 'path': u})
    call('delphi_hover', {'path': uso, 'line': 7, 'character': 4}, 300)

    def destino(kind):
        args = {'path': uso, 'line': 7, 'character': 4}
        if kind:
            args['kind'] = kind
        j = mc.como_json(call('delphi_definition', args, 300))
        return os.path.basename(str(j.get('path', ''))), j.get('line0'), j

    f1, l1, j1 = destino('')
    check('D1 definition de la llamada: el cuerpo de Saluda en UComun (linea0 4)',
          f1 == 'UComun.pas' and l1 == 4, str(j1)[:300])
    f2, l2, j2 = destino('implementation')
    check('D2 kind=implementation = definition, no el metodo que contiene la llamada',
          (f2, l2) == (f1, l1) and f2 != 'UsoZ.pas', str(j2)[:300])
    f3, l3, j3 = destino('declaration')
    check('D3 kind=declaration: la de la interface de UComun (linea0 2)',
          f3 == 'UComun.pas' and l3 == 2, str(j3)[:300])
    for caso, path, linea, col, esperada in (
            ('D4 desde la cabecera del cuerpo de Saluda', comun, 4, 12, 2),
            ('D5 desde la cabecera del cuerpo de TFoo.Bar', clase, 8, 15, 5),
            ('D6 control: desde la declaracion de Saluda', comun, 2, 12, 2)):
        j = mc.como_json(call('delphi_definition', {'path': path, 'line': linea, 'character': col,
                                                    'kind': 'declaration'}, 300))
        check('%s: kind=declaration da la declaracion (linea0 %d)' % (caso, esperada),
              os.path.basename(str(j.get('path', ''))) == os.path.basename(path) and j.get('line0') == esperada,
              str(j)[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('definition kind=implementation es definition 120')
