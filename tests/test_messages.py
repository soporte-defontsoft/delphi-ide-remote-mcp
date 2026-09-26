r"""E2E battery for delphi_messages: the operator's mailbox (the way back of
delphi_report). Messages are .md files in messages\<agent>\ next to the server
exe - one box per agent, none "for everyone" (a notice for all goes into each
agent's folder, 2026-09-25). While the caller's own mail waits EVERY tool
answer ends with a MENSAJES PENDIENTES line; read delivers it and DELETES it,
like a capture: nothing is kept aside, nothing is purged later.

Usage:  python tests/test_messages.py [path-to-DelphiLspMcp.exe]
The exe is COPIED to a scratch folder so the mailbox is private to the run.
"""
import json, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('messages')
EXE = mc.copia_exe(BASE)
MSG = os.path.join(BASE, 'messages')
os.makedirs(os.path.join(MSG, 'dsh'))
open(os.path.join(MSG, 'dsh', '20260823-0100-deploy.md'), 'w', encoding='utf-8').write(
    '# Reconecta y sigue con el Deploy\n\nEl server se reinicio. Sigue con target=Deploy.\n')
# el buzon de ESTE cliente (clientInfo.name = messages-battery)
os.makedirs(os.path.join(MSG, 'messages-battery'))
open(os.path.join(MSG, 'messages-battery', '20260823-0102-propio.md'), 'w', encoding='utf-8').write(
    '# Correo propio\n\nPara quien pregunta.\n')
# un .md suelto en la raiz: antes era "para todos"; ya no es correo de nadie
open(os.path.join(MSG, '20260823-0059-aviso.md'), 'w', encoding='utf-8').write(
    '# Aviso general\n\nVentana de mantenimiento a las 02:00.\n')

env = mc.entorno({'DELPHI_MCP_ROOTS': BASE})
srv = mc.Stdio(EXE, env, nombre='messages-battery')
call = srv.call


print('== messages battery ==')
t = call('delphi_workspace', {})
# Desde 2026-09-25 no hay buzon "para todos" (un aviso general se deja en la
# carpeta de cada agente) y un mensaje leido se BORRA, como una captura. El
# aviso al final de cada respuesta es el del correo PROPIO (la identidad del
# handshake): quien lo ve puede leerlo y apagarlo. El de otros buzones no se
# nombra ni se cuenta ahi (v1.0.4-beta: seis mensajes ajenos dejaban la linea
# clavada ~40 llamadas); ese recuento vive en la ficha de delphi_workspace.
check('aviso del correo PROPIO al final de cualquier tool',
      'MENSAJES PENDIENTES: 1 en tu buzon (messages-battery)' in t, t[-200:])
check('el aviso NO nombra el buzon de otro agente', 'dsh' not in t, t[-200:])
check('un .md suelto en la raiz ya no es correo de nadie',
      'TODOS' not in t and 'Aviso general' not in t, t[-200:])
w = json.loads(call('delphi_workspace', {}))
check('la ficha del servidor cuenta el correo de los buzones, sin decir de quien',
      w.get('server', {}).get('mailboxes') == 2 and 'dsh' not in json.dumps(w),
      json.dumps(w.get('server', {}))[:200])
t = call('delphi_messages', {"command": "check", "agent": "dsh"})
check('check lista sin consumir, solo su buzon',
      'pendientes: 1' in t and 'Reconecta' in t and 'Aviso general' not in t, t)
check('check no borra', os.path.exists(os.path.join(MSG, 'dsh', '20260823-0100-deploy.md')))
t = call('delphi_messages', {"agent": "dsh"})
check('read entrega el suyo', 'MENSAJE 1/1' in t and 'Sigue con target=Deploy' in t
      and 'Aviso general' not in t and 'borrados' in t, t)
check('leido = BORRADO, y no queda copia en ningun sitio',
      not os.path.exists(os.path.join(MSG, 'dsh', '20260823-0100-deploy.md'))
      and not os.path.exists(os.path.join(MSG, '_entregados')), os.listdir(MSG))
t = call('delphi_messages', {"agent": "dsh"})
check('segunda lectura: nada', t.startswith('Sin mensajes para "dsh"'), t)
t = call('delphi_messages', {})
check('sin agent: la identidad del handshake lee SU buzon',
      'MENSAJE 1/1' in t and 'Correo propio' in t, t)
t = call('delphi_workspace', {})
check('leido: el aviso se apaga', 'MENSAJES PENDIENTES' not in t, t[-120:])
check('el .md de la raiz sigue ahi: ni se entrega ni se borra (es del operador)',
      os.path.exists(os.path.join(MSG, '20260823-0059-aviso.md')))
t = call('delphi_messages', {"command": "x"})
check('command invalido', t.startswith('error:'), t)
# the agent id is slugged like delphi_report: no path tricks
open(os.path.join(MSG, 'dsh', 'otro.md'), 'w', encoding='utf-8').write('# Otro\n\nhola\n')
t = call('delphi_messages', {"agent": "..\\dsh"})
check('agent se normaliza (sin ..)', 'MENSAJE 1/1' in t and 'hola' in t, t)
t = call('delphi_messages', {"command": "read", "agent": "dsh"})
check('tras leer, vacio', t.startswith('Sin mensajes'), t)

srv.cierra()
mc.fin('messages battery')
