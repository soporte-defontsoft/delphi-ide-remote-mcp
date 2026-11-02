# -*- coding: utf-8 -*-
r"""Lo de la 1.26.

  D1 un Deploy que falla en una carpeta cuyo nombre lleva E0017 y el del vigia de un
     remote-run: deployLockedNote leia la consola entera y mandaba matar un trabajo que
     no existe. El E0017 de verdad lo clasifica msbuild y llega a errors[], con el nombre
     del vigia en LA MISMA linea (medido el 1-nov-2026 contra un PAServer con un programa
     vivo; el camino bueno se mide en vivo, una bateria no tiene PAServer).
  C1 preview de un form cuyo frame lleva otro que cierra el ciclo: RENDER-026 dice en que
     fichero esta el inline que se salto, que no es el pedido (Qwen, dirigido de la 1.25.1:
     no se sabia que bloque faltaba).

Uso:  python tests/test_capacidades_126.py [exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('capacidades_126')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True, con_render=True)
# un perfil falso con su host permitido: msbuild llega a intentar el Deploy y falla
APPD, HOST = mc.appdata_perfil(BASE, 'mcp-e2e-noprof', '127.0.0.1', 'Linux64')
D1 = os.path.join(JAIL, 'E0017-20261101-173717596-a1d40549.wait.exe')
DPROJ = os.path.join(D1, 'Bloqueo.dproj')
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'APPDATA': APPD, 'DELPHI_MCP_REMOTE_HOSTS': HOST,
                              'DELPHI_MCP_ALLOW_REMOTE_RUN': '1', 'DELPHI_MCP_REMOTE_RUN_PROJECTS': DPROJ}),
             nombre='capacidades-126', t=400)

# ---- D: lo que dice la consola no es lo que clasifica msbuild
s.call('delphi_create', {'kind': 'project-console', 'dir': D1, 'name': 'Bloqueo'})
s.call('delphi_config', {'command': 'add-platform', 'platform': 'Linux64', 'project': DPROJ})
t = s.call('delphi_build', {'project': DPROJ, 'platform': 'Linux64', 'config': 'Debug', 'target': 'Deploy',
                            'profile': 'mcp-e2e-noprof', 'verbosity': 'normal'}, t=400)
r = mc.como_json(t)
check('D1 fixture: el Deploy falla', r.get('success') is False, t[:600])
check('D1 un Deploy que falla en una carpeta que se llama como el vigia no manda matar a nadie',
      'deployLockedNote' not in r, r.get('deployLockedNote'))

# ---- C: que bloque se salto
def escribe(ruta, texto):
    with open(ruta, 'wb') as f:
        f.write(texto.encode('ascii').replace(b'\n', b'\r\n'))


C1 = os.path.join(JAIL, 'ciclo')
os.makedirs(C1)
for uni, clase, otro in (('UUno', 'TFrUno', 'TFrDos'), ('UDos', 'TFrDos', 'TFrUno')):
    usa = 'UDos' if uni == 'UUno' else 'UUno'
    escribe(os.path.join(C1, uni + '.pas'),
            'unit %s;\n\ninterface\n\nuses\n  Vcl.Forms, %s;\n\ntype\n  %s = class(TFrame)\n    Dentro: %s;\n  end;\n\n'
            'implementation\n\n{$R *.dfm}\n\nend.\n' % (uni, usa, clase, otro))
    escribe(os.path.join(C1, uni + '.dfm'),
            'object %s: %s\n  Left = 0\n  Top = 0\n  Width = 100\n  Height = 80\n  TabOrder = 0\n'
            '  inline Dentro: %s\n    Left = 0\n    Top = 0\n  end\nend\n' % (clase[1:], clase, otro))
r = s.call('delphi_designer', {'command': 'preview', 'path': os.path.join(C1, 'UUno.dfm'), 'maxwidth': 100}, t=400)
check('C1 RENDER-026 dice en que fichero esta el inline que se salto: UDos.dfm, no el pedido',
      mc.es(r, 'SR_RENDER_FRAME_CICLICO_FMT') and 'Its inline in UDos.dfm' in r, r[:500])

s.cierra()
mc.borra(BASE)
mc.fin('capacidades 1.26')
