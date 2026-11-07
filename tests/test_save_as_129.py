# -*- coding: utf-8 -*-
"""1.29 (C1): delphi_config save-as = el "Save Project As" del IDE, MEDIDO el 7-nov-2026 con tres copias (David en el
IDE: ClBluetooth guardado como ClRenombrado, Arnes con su .res y su .deployproj, un .dpr suelto). COPIA, no
renombra: el .dpr nuevo es el viejo con su cabecera, el .dproj nuevo cambia MainSource, ProjectName,
SanitizedProjectName, <Source Name="MainSource"> y el binario de las ProjectOutput que llevan plataforma (LocalName
y RemoteName); las vacias, tal cual. No copia el .res (lo hace el build) ni el .deployproj, y no borra nada. Un
agente no tenia camino: MainSource es estructura (CFG-132) y delphi_textedit no escribe un .dproj (informe del
7-nov).

  S1 save-as del ejemplo ClBluetooth (Samples de RAD Studio) como ClRenombrado: lo escribe. ROJO contra 695a0aac
  S2 el .dpr nuevo es el viejo con program ClRenombrado; y nada mas
  S3 el .dproj nuevo: MainSource, SanitizedProjectName y <Source Name="MainSource">, con el nombre nuevo
  S4 ...las ProjectOutput con plataforma, con el binario nuevo (LocalName y RemoteName); ninguna con el viejo
  S5 el viejo no se toca (sus bytes), y ni .res ni .deployproj nuevos
  S6 el compilador lo acepta: delphi_build del nuevo (Win32 Debug) deja ClRenombrado.exe
  S7 nunca pisa: el mismo nombre otra vez -> CREATE-023 y nada cambia
  S8 un nombre que no es identificador -> la negativa de delphi_create; sin name -> CFG-150

Uso:  python tests/test_save_as_129.py [ruta-a-DelphiLspMcp.exe]
"""
import hashlib
import os
import re
import shutil
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('save_as_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='saveas', t=120)
# los Samples de la instalacion activa: cuelgan de BDSCOMMONDIR (su rsvars.bat, el que lee el servidor)
SAMPLE = os.path.join(mc.variable_de_rsvars(srv.call, 'BDSCOMMONDIR'), 'Samples', 'Object Pascal',
                      'Multi-Device Samples', 'Device Sensors and Services', 'Bluetooth', 'Classic Bluetooth Basic app')
if not os.path.isfile(os.path.join(SAMPLE, 'ClBluetooth.dproj')):
    srv.cierra()
    mc.borra(BASE)
    mc.fin('save-as (1.29, C1)', sin_checks='sin el ejemplo ClBluetooth de los Samples de RAD Studio')
P = os.path.join(JAIL, 'Cl')
shutil.copytree(SAMPLE, P)
VIEJO, VIEJO_DPR = os.path.join(P, 'ClBluetooth.dproj'), os.path.join(P, 'ClBluetooth.dpr')
NUEVO, NUEVO_DPR = os.path.join(P, 'ClRenombrado.dproj'), os.path.join(P, 'ClRenombrado.dpr')


def huella(f):
    return hashlib.sha256(open(f, 'rb').read()).hexdigest()


antes = {f: huella(os.path.join(P, f)) for f in os.listdir(P) if os.path.isfile(os.path.join(P, f))}
try:
    r = srv.call('delphi_config', {'command': 'save-as', 'project': VIEJO, 'name': 'ClRenombrado'})
    check('S1 save-as de ClBluetooth como ClRenombrado: lo escribe. ROJO contra 695a0aac',
          mc.abre(r, 'SN_CFG_SAVE_AS_FMT') and os.path.isfile(NUEVO) and os.path.isfile(NUEVO_DPR), r[:400])
    viejo_dpr, nuevo_dpr = mc.lee(VIEJO_DPR), mc.lee(NUEVO_DPR)
    check('S2 el .dpr nuevo es el viejo con program ClRenombrado; y nada mas',
          nuevo_dpr == viejo_dpr.replace('program ClBluetooth;', 'program ClRenombrado;', 1) and nuevo_dpr != viejo_dpr,
          nuevo_dpr[:200])
    x = mc.lee(NUEVO)
    check('S3 el .dproj nuevo: MainSource, SanitizedProjectName y Source MainSource con el nombre nuevo',
          '<MainSource>ClRenombrado.dpr</MainSource>' in x and
          '<SanitizedProjectName>ClRenombrado</SanitizedProjectName>' in x and
          '<Source Name="MainSource">ClRenombrado.dpr</Source>' in x and
          '<MainSource>MainSource</MainSource>' in x, x[:300])
    salidas = re.findall(r'<DeployFile LocalName="([^"]+)" Configuration="[^"]*" Class="ProjectOutput">\s*'
                         r'<Platform Name="[^"]+">\s*<RemoteName>([^<]+)</RemoteName>', x)
    check('S4 las ProjectOutput con plataforma llevan el binario nuevo (LocalName y RemoteName)',
          len(salidas) >= 2 and all('ClRenombrado' in a and 'ClRenombrado' in b for a, b in salidas) and
          not any('ClBluetooth' in a or 'ClBluetooth' in b for a, b in salidas), salidas)
    nuevos = sorted(f for f in os.listdir(P) if f not in antes)
    check('S5 el viejo no se toca, y ni .res ni .deployproj nuevos',
          all(huella(os.path.join(P, f)) == h for f, h in antes.items()) and
          nuevos == ['ClRenombrado.dpr', 'ClRenombrado.dproj'], nuevos)
    ok, err = mc.build_ok(srv.call, NUEVO, 'Win32', 'Debug')
    check('S6 el compilador lo acepta: el build del nuevo deja ClRenombrado.exe',
          ok and os.path.isfile(os.path.join(P, 'Win32', 'Debug', 'ClRenombrado.exe')), err)
    h_nuevo = huella(NUEVO)
    r = srv.call('delphi_config', {'command': 'save-as', 'project': VIEJO, 'name': 'ClRenombrado'})
    check('S7 nunca pisa: el mismo nombre otra vez, CREATE-023 y nada cambia',
          mc.abre(r, 'SR_CREATE_YA_EXISTE_PROYECTO_FMT') and huella(NUEVO) == h_nuevo, r[:300])
    r = srv.call('delphi_config', {'command': 'save-as', 'project': VIEJO, 'name': 'Cl Renombrado'})
    r2 = srv.call('delphi_config', {'command': 'save-as', 'project': VIEJO})
    check('S8 un nombre que no es identificador, la negativa de delphi_create; sin name, CFG-150',
          mc.abre(r, 'SR_CREATE_IDENTIFICADOR_NOMBRE_PROYECTO_FMT') and mc.abre(r2, 'SR_CFG_SAVE_AS_SIN_NOMBRE'),
          (r[:200], r2[:200]))
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('save-as (1.29, C1)')
