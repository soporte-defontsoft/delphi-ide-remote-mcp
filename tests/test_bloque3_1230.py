# -*- coding: utf-8 -*-
"""Bloque 3 de la 1.23: reglas que vivian dos o tres veces, una sola.

  C1 (A16) get de un componente que no esta: la negativa de los comandos que
     escriben (DSGN-078), con los nombres del form (ROJO hasta la 1.23: DSGN-017)
  C2 (A23) delphi_create form-vcl formname=Begin: se niega y no se escribe nada
     (ROJO hasta la 1.23: escribia "Begin: TBegin", que no compila)
  C3 (A33) set-version en una consola con VerInfo_IncludeVerInfo=yes, que msbuild
     lee como verdad: no dice que la version no se incluye (ROJO hasta la 1.23)
  C4 (A37) set-output output=none vuelve a lo de RAD Studio, como default
     (ROJO hasta la 1.23: escribia una carpeta "none")
  C5 (A20, guarda) un preview con out=: 'screenshot' y 'screenshotBytes', que
     compone DeliverCapture para toda tool que captura

Uso:  python tests/test_bloque3_1230.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('test_bloque3_1230')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)  # C5: el preview, con sus renderizadores


def lee(ruta):
    return open(ruta, encoding='utf-8-sig').read()


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='test-bloque3', t=300)
try:
    vcl = os.path.join(JAIL, 'V')
    srv.call('delphi_create', {'kind': 'project-vcl', 'name': 'PV', 'dir': vcl}, t=120)
    dpr = os.path.join(vcl, 'PV.dpr')
    dfms = [f for f in os.listdir(vcl) if f.endswith('.dfm')]
    dfm = os.path.join(vcl, dfms[0]) if dfms else ''
    r = srv.call('delphi_designer', {'command': 'get', 'path': dfm, 'component': 'NoEsta'}, t=120)
    check('C1 get de un componente que no esta: DSGN-078, con los nombres del form',
          mc.rechazado(r) and mc.es(r, 'SR_DESIGNER_COMPONENTE_NO_ESTA_FMT') and 'NoEsta' in r, r[:300])

    r = srv.call('delphi_create', {'kind': 'form-vcl', 'name': 'UBegin', 'formname': 'Begin', 'project': dpr},
                 t=120)
    check('C2 form-vcl formname=Begin: se niega (CREATE-026) y no escribe la unit',
          mc.rechazado(r) and mc.es(r, 'SR_CREATE_IDENTIFICADOR_FORM_FMT') and
          not os.path.exists(os.path.join(vcl, 'UBegin.pas')), r[:300])

    con = os.path.join(JAIL, 'C')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'PC', 'dir': con}, t=120)
    dproj = os.path.join(con, 'PC.dproj')
    x = lee(dproj)
    m = re.search(r"<PropertyGroup Condition=\"'\$\(Base\)'!=''\">", x)
    x = x[:m.end()] + '\r\n        <VerInfo_IncludeVerInfo>yes</VerInfo_IncludeVerInfo>' + x[m.end():]
    with open(dproj, 'w', encoding='utf-8', newline='') as f:
        f.write(x)
    r = srv.call('delphi_config', {'command': 'set-version', 'project': dproj, 'version': '1.2.3.4'})
    check('C3 set-version con VerInfo_IncludeVerInfo=yes (verdad para msbuild): no dice que no se incluye',
          not mc.rechazado(r) and 'does not include the version' not in r, r[:400])

    srv.call('delphi_config', {'command': 'set-output', 'project': dproj, 'output': 'bin'})
    r = srv.call('delphi_config', {'command': 'set-output', 'project': dproj, 'output': 'none'})
    x = lee(dproj)
    check('C4 set-output output=none vuelve a lo de RAD Studio, sin una carpeta "none"',
          not mc.rechazado(r) and '(RAD Studio default)' in r and
          not any('none' in v.lower() for v in re.findall(r'<DCC_ExeOutput>([^<]*)', x)),
          (r[:300], re.findall(r'<DCC_ExeOutput>[^<]*', x)[:3]))

    out = os.path.join(JAIL, 'cap.png')
    r = srv.call('delphi_designer', {'command': 'preview', 'path': dfm, 'out': out, 'inline': False}, t=240)
    j = mc.como_json(r) if r.lstrip().startswith('{') else {}
    check('C5 (guarda) preview con out=: screenshot y screenshotBytes, de DeliverCapture',
          os.path.exists(out) and j.get('screenshotBytes') == os.path.getsize(out) and 'cap.png' in str(j.get('screenshot')),
          r[:400])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('bloque 3 de la 1.23: una regla donde habia dos')
