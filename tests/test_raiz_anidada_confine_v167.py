# -*- coding: utf-8 -*-
"""V167 (1.23.1): confinement uses the MOST SPECIFIC root, not the first one
declared.

With nested roots (D:\\W and D:\\W\\agents) and AgentConfinement=1, the agent's
segment - and so whether a write is confined - was taken from the FIRST root
that contained the path, so it depended on the ORDER the roots were declared:
writing <W>\\agents\\alice\\x as alice was CREATED with the roots in one order
and GUARD-015 in the other. PathDenied and ConfinamientoPorLaRutaReal now pick
the longest matching root, like RaizQueContiene (the "which root contains this"
namer). The outcome is the same in both orders.

  N1 roots [W, W\\agents]: alice writes W\\agents\\alice\\x -> CREATED (her folder
     under the most specific root). RED against 06f59ce in THIS order (GUARD-015)
  N2 roots [W\\agents, W]: the same write -> CREATED (unchanged, already worked)
  N3 (both orders) alice writes W\\agents\\bob\\x -> GUARD-015 (bob's folder)

Usage:  python tests/test_raiz_anidada_confine_v167.py [path-to-DelphiLspMcp.exe]
"""
import os, sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
TOKEN = 'bateria-workspace'


def corre(orden, etiqueta):
    base = mc.carpeta(os.path.join('raiz_anidada_v167', etiqueta))
    W = os.path.join(base, 'W')
    AG = os.path.join(W, 'agents')
    for d in (os.path.join(W, 'alice'), os.path.join(AG, 'alice'), os.path.join(AG, 'bob')):
        os.makedirs(d)
    raices = ';'.join(W if r == 'W' else AG for r in orden)
    port = mc.puerto_libre()
    with open(os.path.join(base, 'settings.ini'), 'w') as f:
        f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\nAgentConfinement=1\n' % (TOKEN, raices))
    proc = mc.lanza_http(mc.copia_exe(base, src=exe_src), port,
                         mc.entorno({'DELPHI_MCP_ROOTS': raices, 'DELPHI_MCP_BIND_IP': '127.0.0.1'}))
    try:
        a = mc.Http(port, TOKEN)
        a.session('alice')
        prop = a.call('delphi_textedit', {'path': os.path.join(AG, 'alice', 'x.txt'), 'create': True, 'content': 'x'})
        ajeno = a.call('delphi_textedit', {'path': os.path.join(AG, 'bob', 'x.txt'), 'create': True, 'content': 'x'})
        return prop, ajeno
    finally:
        proc.kill()


# N1: W primero (el orden que fallaba en 06f59ce)
prop1, ajeno1 = corre(['W', 'W\\agents'], 'Wfirst')
check('N1 raices [W, W\\agents]: alice escribe en W\\agents\\alice (su carpeta bajo la raiz mas especifica) -> CREADO',
      mc.abre(prop1, 'SK_TEXT_CREADO_ENCODING_FINALES_FMT'), prop1[:200])
# N2: W\agents primero (ya funcionaba)
prop2, ajeno2 = corre(['W\\agents', 'W'], 'AGfirst')
check('N2 raices [W\\agents, W]: la misma escritura -> CREADO (mismo resultado, sin depender del orden)',
      mc.abre(prop2, 'SK_TEXT_CREADO_ENCODING_FINALES_FMT'), prop2[:200])
# N3: el confinamiento sigue negando la carpeta de otro agente, en los dos ordenes
check('N3 en los dos ordenes, escribir en W\\agents\\bob se niega (confinamiento)',
      mc.es(ajeno1, 'SR_AGENT_CONFINED_FMT') and mc.es(ajeno2, 'SR_AGENT_CONFINED_FMT'),
      (ajeno1[:120], ajeno2[:120]))

mc.fin('V167 raiz anidada confine battery')
