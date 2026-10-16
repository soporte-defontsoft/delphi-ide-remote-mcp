# -*- coding: utf-8 -*-
"""delphi_rename_symbol y una CADENA con el nombre en OTRA unidad (1.20, Hermes en la VM,
validacion previa del 16-oct). La descripcion promete que un acierto dentro de un literal
(FindComponent, RTTI o StyleLookup por nombre) deja applicable=false; pero el bloqueo solo
miraba las cadenas de los ficheros que el rename TOCA. Hermes renombro ProbeValueRenamed120
con 'ProbeValueRenamed120 Hola' en otra unidad: un aviso RENAME-007 y applicable=true - un
rename que deja un FindComponent apuntando a un nombre que ya no existe, y el compilador
calla. Ahora references cuenta aparte las menciones que caen en una CADENA, en todo el
alcance (stringMentionsCount, por la vista del lexico), y rename bloquea con esa cuenta.

  N1 una cadena con el nombre en otra unidad: applicable=false con RENAME-020
     (ROJO en 3cc31fc: applicable=true y solo el aviso)
  N2 references lo cuenta: stringMentionsCount=1 de mentionsCount=2 (cadena y comentario)
  N3 control: el nombre solo en un COMENTARIO de otra unidad no bloquea
  N4 control: una cadena en la unidad tocada sigue bloqueando

Uso:  python tests/test_rename_cadena_120.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('rename_cadena_120')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='rename-cadena', t=300)
call = srv.call


def escribe(ruta, texto):
    open(ruta, 'w', newline='\r\n').write(texto)


try:
    d = os.path.join(JAIL, 'p')
    call('delphi_create', {'kind': 'project-console', 'name': 'P', 'dir': d})
    dproj = os.path.join(d, 'P.dproj')
    comun = os.path.join(d, 'UComun.pas')
    uso = os.path.join(d, 'UsoZ.pas')
    otra = os.path.join(d, 'UOtra.pas')
    # UComun: 2 procedure Saluda; (interface)
    escribe(comun, 'unit UComun;\ninterface\nprocedure Saluda;\nprocedure Despide;\nimplementation\n'
                   'procedure Saluda;\nbegin\nend;\nprocedure Despide;\nbegin\nend;\nend.\n')
    escribe(uso, 'unit UsoZ;\ninterface\nprocedure Llama;\nimplementation\nuses UComun;\n'
                 'procedure Llama;\nbegin\n  Saluda;\n  Despide;\nend;\nend.\n')
    # otra unidad: Saluda en una CADENA y en un comentario; Despide solo en un comentario
    escribe(otra, "unit UOtra;\ninterface\nconst\n  NOMBRE = 'Saluda';\n"
                  "// Saluda y Despide se llaman por su nombre\nimplementation\nend.\n")
    for u in (uso, comun, otra):
        call('delphi_config', {'command': 'add-unit', 'project': dproj, 'path': u})
    call('delphi_hover', {'path': uso, 'line': 7, 'character': 4}, 300)

    j = mc.como_json(call('delphi_rename_symbol', {'path': comun, 'line': 2, 'character': 12,
                                                   'newname': 'Saludar'}, 300))
    blk = ' '.join(j.get('blockers') or [])
    check('N1 una cadena con el nombre en OTRA unidad: applicable=false con RENAME-020',
          j.get('applicable') is False and mc.tiene(blk, 'RENAME-020'), str(j)[:600])

    r = mc.como_json(call('delphi_references', {'path': comun, 'line': 2, 'character': 12}, 300))
    check('N2 references: stringMentionsCount=1 de mentionsCount=2 (la cadena y el comentario)',
          r.get('stringMentionsCount') == 1 and r.get('mentionsCount') == 2, str(r)[:600])

    j = mc.como_json(call('delphi_rename_symbol', {'path': comun, 'line': 3, 'character': 12,
                                                   'newname': 'Despedir'}, 300))
    check('N3 control: solo en un COMENTARIO de otra unidad: applicable=true con el aviso',
          j.get('applicable') is True and mc.tiene(' '.join(j.get('warnings') or []), 'RENAME-007'),
          str(j)[:600])

    escribe(otra, "unit UOtra;\ninterface\nimplementation\nend.\n")
    escribe(uso, 'unit UsoZ;\ninterface\nprocedure Llama;\nimplementation\nuses UComun;\n'
                 "procedure Llama;\nbegin\n  Saluda;\n  Despide;\n  Writeln('Saluda');\nend;\nend.\n")
    j = mc.como_json(call('delphi_rename_symbol', {'path': comun, 'line': 2, 'character': 12,
                                                   'newname': 'Saludar'}, 300))
    check('N4 control: una cadena en la unidad tocada sigue bloqueando',
          j.get('applicable') is False and mc.tiene(' '.join(j.get('blockers') or []), 'RENAME-020'),
          str(j)[:600])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('rename y una cadena con el nombre en otra unidad 120')
