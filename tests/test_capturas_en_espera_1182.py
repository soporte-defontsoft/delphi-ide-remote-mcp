# -*- coding: utf-8 -*-
"""2ab-R3 de la 1.18.2 (revisor del 2ab, medido): con inline=false por HTTP una
captura NUESTRA se quedaba en nuestra casa hasta que alguien la descargaba o
hasta la purga del arranque: una credencial (tambien de solo lectura) podia
llenar el disco del servidor capturando sin descargar nunca. Ahora, al dejar
una esperando su enlace, las de esa carpeta de mas de una hora y las que pasan
de las 50 mas nuevas se borran (PurgaCapturasEnEspera, por el borrado de las
capturas, ConsumeAgentCapture).

Se siembran en la casa del agente 3 capturas de hace dos horas y 55 recientes;
un preview inline=false por HTTP deja la suya esperando.

  Q1 las de hace dos horas se van (ROJO en produccion: siguen)
  Q2 quedan 50 en total, la nueva incluida (ROJO en produccion: 59)
  Q3 control: la nueva se descarga por su enlace (sigue esperando)

Y por WORKSPACE, no por agente (J5 del revisor de cierre, medido: el agente es
el nombre que elige el cliente, y uno que cambiaba de nombre dejaba una carpeta
sin purgar en cada sesion). Se siembran ademas en la casa de 'bob' (el mismo
workspace) 2 de hace dos horas y 10 recientes, mas viejas que las de ana:
  Q4 las de hace dos horas de bob se van (ROJO en produccion)
  Q5 el tope es del workspace: las 10 de bob, las mas viejas, se van y quedan
     50 entre los dos (ROJO en produccion: 60)

Uso:  python tests/test_capturas_en_espera_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import glob
import json
import os
import time
import urllib.request
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('capturas_espera_1182')
SRV = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRV, con_render=True)
RAIZ = os.path.join(BASE, 'op')
os.makedirs(RAIZ)
FORM = ("object FormPrueba: TFormPrueba\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'Prueba'\r\n"
        "  ClientHeight = 200\r\n  ClientWidth = 400\r\nend\r\n")
PRUEBA = os.path.join(RAIZ, 'Prueba.dfm')
open(PRUEBA, 'w', newline='').write(FORM)
TOKEN = 'espera1182-op-0123456789'
PUERTO = mc.puerto_libre()
with open(os.path.join(SRV, 'settings.ini'), 'w') as f:
    f.write('[Server]\nPort=%d\nBindIP=127.0.0.1\n\n[Workspace.Op]\nToken=%s\nRoots=%s\n' % (PUERTO, TOKEN, RAIZ))

def J(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


proc = mc.lanza_http(EXE, None, mc.entorno(), espera_en=PUERTO)
try:
    # la siembra DESPUES del arranque: la purga del arranque barre la casa (la
    # primera version sembraba antes y media esa purga, no la de la espera)
    CASA = os.path.join(mc.casa_de_capturas(SRV, 'ana', 'Op'), 'designer')
    os.makedirs(CASA, exist_ok=True)
    PNG = b'\x89PNG\r\n\x1a\n'
    hace_dos_horas = time.time() - 2 * 3600
    viejas = []
    for i in range(3):
        p = os.path.join(CASA, 'vieja%d.png' % i)
        open(p, 'wb').write(PNG)
        os.utime(p, (hace_dos_horas, hace_dos_horas))
        viejas.append(p)
    for i in range(55):
        p = os.path.join(CASA, 'reciente%02d.png' % i)
        open(p, 'wb').write(PNG)
        t = time.time() - 600 + i   # de hace diez minutos a ahora, en orden
        os.utime(p, (t, t))
    CASA_BOB = os.path.join(mc.casa_de_capturas(SRV, 'bob', 'Op'), 'designer')
    os.makedirs(CASA_BOB, exist_ok=True)
    viejas_bob = []
    for i in range(2):
        p = os.path.join(CASA_BOB, 'vieja%d.png' % i)
        open(p, 'wb').write(PNG)
        os.utime(p, (hace_dos_horas, hace_dos_horas))
        viejas_bob.append(p)
    for i in range(10):
        p = os.path.join(CASA_BOB, 'reciente%02d.png' % i)
        open(p, 'wb').write(PNG)
        t = time.time() - 1200 + i  # hace veinte minutos: mas viejas que las de ana
        os.utime(p, (t, t))


    op = mc.Http(PUERTO, TOKEN, t=180)
    op.session('ana')
    r = op.call('delphi_designer', {'command': 'preview', 'path': PRUEBA, 'inline': False}, t=180)
    j = J(r)
    quedan = glob.glob(os.path.join(CASA, '*.png'))
    check('Q1 las capturas en espera de hace dos horas se van',
          not any(os.path.exists(v) for v in viejas), [os.path.basename(v) for v in viejas if os.path.exists(v)])
    check('Q2 quedan 50 en total, la nueva incluida', len(quedan) == 50, len(quedan))
    check('Q4 las de hace dos horas en la carpeta de OTRO agente del workspace (bob) se van',
          not any(os.path.exists(v) for v in viejas_bob), [os.path.basename(v) for v in viejas_bob if os.path.exists(v)])
    de_bob = glob.glob(os.path.join(CASA_BOB, '*.png'))
    check('Q5 el tope es del workspace: las de bob, las mas viejas, se van; 50 entre los dos',
          de_bob == [] and len(quedan) + len(de_bob) == 50, (len(quedan), len(de_bob)))
    dl = j.get('download', '')
    req = urllib.request.Request('http://127.0.0.1:%d%s' % (PUERTO, dl))
    req.add_header('Authorization', 'Bearer ' + TOKEN)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            codigo, cuerpo = resp.status, resp.read()
    except urllib.error.HTTPError as e:
        codigo, cuerpo = e.code, b''
    check('Q3 control: la nueva sigue esperando y se baja por su enlace (200, un PNG)',
          bool(dl) and codigo == 200 and cuerpo[:8] == PNG, (r[:300], codigo))
    # (revisor de baterias, 18-oct-2026) la EDAD sola, lejos del tope: con 70 en
    # el workspace el tope de 50 se lleva primero las mas viejas, y Q1/Q4 seguian
    # verdes sin la regla de la edad. Ahora 3 viejas y 5 recientes, y nada mas
    for p in glob.glob(os.path.join(CASA, '*.png')) + glob.glob(os.path.join(CASA_BOB, '*.png')):
        os.remove(p)
    viejas2, recientes2 = [], []
    for i in range(3):
        p = os.path.join(CASA, 'vieja2_%d.png' % i)
        open(p, 'wb').write(PNG)
        os.utime(p, (hace_dos_horas, hace_dos_horas))
        viejas2.append(p)
    for i in range(5):
        p = os.path.join(CASA, 'reciente2_%d.png' % i)
        open(p, 'wb').write(PNG)
        recientes2.append(p)
    r2 = op.call('delphi_designer', {'command': 'preview', 'path': PRUEBA, 'inline': False}, t=180)
    check('Q6 la EDAD sola, lejos del tope: las de hace dos horas se van y las recientes se quedan',
          not mc.fallo(r2) and not any(os.path.exists(v) for v in viejas2)
          and all(os.path.exists(p) for p in recientes2),
          (r2[:200], [os.path.basename(v) for v in viejas2 if os.path.exists(v)],
           [os.path.basename(p) for p in recientes2 if not os.path.exists(p)]))
finally:
    try:
        proc.kill()
    except Exception:
        pass

mc.borra(BASE)
mc.fin('capturas en espera por enlace 1182 (2ab-R3)')
