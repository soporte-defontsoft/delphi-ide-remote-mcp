# -*- coding: utf-8 -*-
"""SYS-015 nombra TODOS los parametros desconocidos de una llamada, no solo el primero (D3 de la 1.29.3).

Medido en el state.db de Hermes (12-20 nov-2026, solo lectura, hq_sys015.py con los alias del fuente descontados):
171 SYS-015 y 39 de ellos llevaban
dos o mas desconocidos en la misma llamada (delphi_read con root, limit o maxlines; delphi_paserver output con jobid y
where...): el mensaje nombraba el primero, el agente lo corregia y el siguiente le costaba otro rechazo. Sugerir
el valido mas parecido se midio tambien y NO: casi nunca habia uno parecido, y el que habia despistaba
(name -> classname, project -> parent, maxlines -> fromline, to -> toy).

  U1 delphi_read con tres desconocidos (root, readtype, tailchars: los tres de Hermes, 14-15 nov): SYS-015 abre,
     nombra el primero como siempre y los otros dos en "(and also ...)", y lista los validos; nada leido. Ojo:
     from/to/startline/endline/offset NO son desconocidos en delphi_read, son alias de fromline/toline, y limit,
     tail y su alias maxlines son suyos desde el punto B de la 1.29.3 (test_capacidades_b_1293)
  U2 control: con UNO solo, el texto de siempre, sin "(and also"
  U3 delphi_search con dos desconocidos y los buenos: los dos, y ninguno de los buenos entre los desconocidos
  U4 el caso de campo: delphi_paserver output con jobid y where (18-nov): los dos de una vez
  U5 control: una llamada sin desconocidos no da SYS-015

Uso:  python tests/test_sys015_todos_1293.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('sys015_todos_1293')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
UNIT = os.path.join(JAIL, 'Uno.pas')
with open(UNIT, 'w', encoding='utf-8', newline='\r\n') as f:
    f.write('unit Uno;\n\ninterface\n\nimplementation\n\nend.\n')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='sys015-1293', t=120)
# el trozo fijo que abre la lista de los demas: ' (and also '
MAS = mc.trozos_de_formato('SF_SYS_UNKNOWN_TAMBIEN_FMT')[0]


def texto(r):
    # el error puede venir dentro de un JSON: las comillas, sin escapar
    return r.replace('\\"', '"')


try:
    r = texto(s.call('delphi_read', {'path': UNIT, 'root': JAIL, 'readtype': 'tail', 'tailchars': 1200}))
    check('U1 delphi_read con root, readtype y tailchars: SYS-015 con los tres de una vez, el primero como siempre y '
          'los demas en "(and also ...)" (ROJO sin D3: solo root)',
          mc.abre(r, 'SR_SYS_UNKNOWN_PARAM_FMT') and 'Unknown parameter "root"' in r and MAS in r
          and '"readtype"' in r and '"tailchars"' in r and 'fromline' in r and 'unit Uno' not in r, r[:400])
    r = texto(s.call('delphi_read', {'path': UNIT, 'root': JAIL, 'from': 1, 'to': 3}))
    check('U1b control: from y to son alias de fromline/toline, no desconocidos: solo root',
          mc.abre(r, 'SR_SYS_UNKNOWN_PARAM_FMT') and 'Unknown parameter "root"' in r and MAS not in r, r[:400])
    r = texto(s.call('delphi_read', {'path': UNIT, 'zzparam': 1}))
    check('U2 control: con uno solo, el texto de siempre, sin "(and also"',
          mc.abre(r, 'SR_SYS_UNKNOWN_PARAM_FMT') and 'Unknown parameter "zzparam". Valid parameters: ' in r
          and MAS not in r, r[:300])
    r = texto(s.call('delphi_search', {'root': JAIL, 'query': 'unit', 'ignorecase': True, 'casesensitive': False}))
    check('U3 delphi_search con dos desconocidos y los buenos: los dos, y root/query no estan entre ellos',
          mc.abre(r, 'SR_SYS_UNKNOWN_PARAM_FMT') and '"ignorecase"' in r and '"casesensitive"' in r
          and '"root"' not in r and '"query"' not in r, r[:400])
    r = texto(s.call('delphi_paserver', {'command': 'output', 'jobid': '20261119-000515475-91e46cab',
                                         'profile': 'Fedora', 'where': 'last'}))
    check('U4 el caso de campo: paserver output con jobid y where, los dos de una vez (Hermes, 18-nov)',
          mc.abre(r, 'SR_SYS_UNKNOWN_PARAM_FMT') and '"jobid"' in r and '"where"' in r, r[:400])
    r = texto(s.call('delphi_read', {'path': UNIT, 'fromline': 1, 'toline': 3}))
    check('U5 control: sin desconocidos no hay SYS-015 y lee', not mc.es(r, 'SR_SYS_UNKNOWN_PARAM_FMT')
          and 'unit Uno' in r, r[:300])
finally:
    s.mata()
mc.borra(BASE)
mc.fin('SYS-015 nombra todos los desconocidos 1.29.3 (D3)')
