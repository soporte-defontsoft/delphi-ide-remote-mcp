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
  F1 el renderizador que sigue cargando los paquetes del IDE al vencer --packagestimeout
     contesta RENDER-027 con cuantos llevaba, no RENDER-007 "algo del form espera". La
     carga lenta, con un paquete en una direccion de TEST-NET: Windows tarda ~21 s en
     decir que no existe (medido el 2-nov-2026), y el vigia corta a los 2.
  F2 un ayudante que el SERVIDOR para mientras decia PHASE=packages: DSGN-187, no DSGN-062;
     y uno que ya dijo PHASE=form, DSGN-062. Con ayudantes de mentira, como
     test_protocolo_render_125: lo que se mide es lo que el servidor lee.

Uso:  python tests/test_capacidades_126.py [exe]
"""
import os, re, shutil, subprocess, threading, time
import mcp_cliente as mc
from mcp_cliente import check

# el protocolo, de su fuente: el numero, la clave de la fase y el codigo del vigia
INC = open(os.path.join(mc.REPO, 'src', 'Render', 'FormRenderProtocolo.inc'), encoding='ascii').read()
PROTOCOLO = re.search(r'FR_PROTOCOLO_VERSION = (\d+);', INC).group(1)
FASE = re.search(r"FR_PHASE = '([A-Z]+=)'", INC).group(1)
FASE_PAQUETES = re.search(r"FR_FASE_PAQUETES = '(\w+)'", INC).group(1)
FASE_FORM = re.search(r"FR_FASE_FORM = '(\w+)'", INC).group(1)
RC_TIEMPO = int(re.search(r'FR_RC_TIMEOUT = (\d+);', INC).group(1))

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

# ---- F: la fase de los paquetes
F1 = os.path.join(JAIL, 'fases')
os.makedirs(F1)
DFM = os.path.join(F1, 'UF.dfm')
escribe(DFM, "object UF: TUF\n  Left = 0\n  Top = 0\n  ClientHeight = 60\n  ClientWidth = 80\nend\n")
LISTA = os.path.join(F1, 'paquetes.lst')
with open(LISTA, 'w', encoding='utf-8-sig') as f:
    f.write('\\\\192.0.2.1\\nada\\Nada370.bpl\n')
t0 = time.time()
u = subprocess.run([os.path.join(os.path.dirname(EXE), 'DelphiFormRenderVcl.exe'), '--path', DFM,
                    '--out', os.path.join(F1, 'o.png'), '--packages', 'all', '--knownfile', LISTA,
                    '--root', 'form', '--fidelity', 'print', '--style', 'none',
                    '--timeout', '20000', '--packagestimeout', '2000'],
                   capture_output=True, timeout=120, cwd=F1)
dt = time.time() - t0
salida = u.stdout.decode('utf-8', 'replace')
check('F1 cargando los paquetes al vencer --packagestimeout: RENDER-027 con cuantos llevaba, a los 2 s y no a los '
      '20 del plazo entero, con su codigo de tiempo (%.1f s)' % dt,
      u.returncode == RC_TIEMPO and mc.es(salida, 'SR_RENDER_PAQUETES_CARGANDO_FMT') and '(0 of 1)' in salida
      and (FASE + FASE_PAQUETES) in salida.splitlines() and dt < 15,
      (u.returncode, salida[-500:]))

PRUEBA = os.path.join(JAIL, 'prueba')
os.makedirs(PRUEBA)
escribe(os.path.join(PRUEBA, 'UP.pas'), 'unit UP;\n\ninterface\n\nuses\n  Vcl.Forms;\n\ntype\n  TUP = class(TForm)\n  end;\n\n'
        'implementation\n\n{$R *.dfm}\n\nend.\n')
escribe(os.path.join(PRUEBA, 'UP.dfm'), "object UP: TUP\n  Left = 0\n  Top = 0\n  ClientHeight = 60\n  ClientWidth = 80\nend\n")


def se_queda(nombre, fases):
    """Un ayudante de mentira: su protocolo, esas fases, y se queda esperando a que lo paren."""
    d = os.path.join(JAIL, 'stubs', nombre)
    s.call('delphi_create', {'kind': 'project-console', 'name': nombre, 'dir': d})
    lineas = ['PROTOCOL=' + PROTOCOLO] + [FASE + x for x in fases]
    escribe(os.path.join(d, nombre + '.dpr'),
            'program %s;\n\n{$APPTYPE CONSOLE}\n\nuses\n  System.SysUtils;\n\nbegin\n%s  Flush(Output);\n  Sleep(600000);\nend.\n'
            % (nombre, ''.join("  Writeln('%s');\n" % x for x in lineas)))
    j = mc.como_json(s.call('delphi_build', {'project': os.path.join(d, nombre + '.dproj'), 'platform': 'Win64',
                                             'config': 'Release'}, t=120)) or {}
    check('F2 fixture: el ayudante de mentira %s compila' % nombre, j.get('success') is True, str(j)[:300])
    return os.path.join(d, 'Win64', 'Release', nombre + '.exe')


def preview_con(ayudante, nombre, res):
    d = os.path.join(BASE, 'srv-' + nombre)
    exe = mc.copia_exe(d, con_render=True)
    shutil.copy(ayudante, os.path.join(d, 'DelphiFormRenderVcl.exe'))
    otro = mc.Stdio(exe, mc.entorno({'DELPHI_MCP_ROOTS': PRUEBA}), nombre='fases-' + nombre, t=240)
    try:
        res[nombre] = otro.call('delphi_designer', {'command': 'preview', 'path': os.path.join(PRUEBA, 'UP.dfm'),
                                                    'maxwidth': 100}, t=200)
    finally:
        otro.cierra()


mentiras = {'Paquetes': se_queda('Paquetes', [FASE_PAQUETES]), 'Form': se_queda('Form', [FASE_PAQUETES, FASE_FORM])}
res = {}
hilos = [threading.Thread(target=preview_con, args=(a, n, res)) for n, a in mentiras.items()]
for h in hilos:
    h.start()
for h in hilos:
    h.join(400)
r = res.get('Paquetes', '(sin respuesta)')
check('F2 el servidor para a un ayudante que lo ultimo que dijo es que cargaba los paquetes: DSGN-187, no '
      '"algo del form espera"', mc.es(r, 'SR_DESIGNER_RENDER_PAQUETES_TIEMPO_FMT')
      and not mc.es(r, 'SR_DESIGNER_RENDER_TIEMPO_FMT'), r[:400])
r = res.get('Form', '(sin respuesta)')
check('F2 ...y uno que ya habia pasado al form: DSGN-062, lo de siempre (cuenta la ULTIMA fase)',
      mc.es(r, 'SR_DESIGNER_RENDER_TIEMPO_FMT') and not mc.es(r, 'SR_DESIGNER_RENDER_PAQUETES_TIEMPO_FMT'), r[:400])

s.cierra()
mc.borra(BASE)
mc.fin('capacidades 1.26')
