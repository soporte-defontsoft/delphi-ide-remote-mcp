# -*- coding: utf-8 -*-
"""Se compila como en el IDE: la plataforma por defecto del proyecto, y solo
una que el proyecto declara activa (David, 6-oct-2026: "si un agente compila
un proyecto del operador, este debe poder entrar despues al IDE y compilar
igual sin reconfigurar").

Medido antes: delphi_build compilaba Linux64 (sdk=) de un FMX que no declara
Linux64, sin los ajustes de esa plataforma y sin que el IDE la mostrara (el
GuiProbe de Hermes "perdio" asi una plataforma que nunca tuvo); sin platform=
compilaba Win32 a fuego aunque el proyecto tuviera Win64 por defecto (los que
crea delphi_create), y delphi_test Win64 a fuego.

  Q1  sin platform=: la plataforma POR DEFECTO del proyecto (Win64 en uno de
      delphi_create), no Win32
  Q2  una plataforma que no declara (Linux64): BUILD-046 y no se compila nada
  Q3  control: tras add-platform, la misma llamada compila
  Q4  tras remove-platform (desactivada, como en el IDE): BUILD-046 otra vez
  Q5  delphi_test run sin platform=: la del proyecto (uno con Win32 por
      defecto: Win32, no el Win64 de antes)
  Q6  un .dproj sin bloque <Platforms> (anterior a las plataformas): solo su
      plataforma por defecto; Win64 -> BUILD-046

Uso:  python tests/test_plataforma_declarada.py [exe]
"""
import os, re, json
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('platdecl')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL, exist_ok=True)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_ALLOW_TESTS': '1'}),
               nombre='platdecl', t=900)


def J(t):
    return mc.como_json(t) or {}


def pon_defecto(dproj, plat):
    """El selector <Platform Condition="'$(Platform)'==''">X</Platform>, como lo
    deja el IDE al cambiar la plataforma activa."""
    t = open(dproj, encoding='utf-8-sig').read()
    t2 = re.sub(r"(<Platform Condition=\"'\$\(Platform\)'==''\">)\w+(</Platform>)", r'\g<1>%s\g<2>' % plat, t,
                count=1)
    assert t2 != t, 'sin selector en ' + dproj
    open(dproj, 'w', encoding='utf-8').write(t2)


try:
    srv.call('delphi_create', {'kind': 'project-fmx', 'name': 'PD', 'dir': os.path.join(JAIL, 'PD')})
    D = os.path.join(JAIL, 'PD', 'PD.dproj')

    out = srv.call('delphi_build', {'project': D}, 900)
    j = J(out)
    check('Q1 sin platform=: la por defecto del proyecto (Win64), no Win32, y sin la nota BUILD-036',
          j.get('success') is True and j.get('platform') == 'Win64'
          and '\\Win64\\' in str(j.get('output')) and 'BUILD-036' not in out, out[:300])

    out = srv.call('delphi_build', {'project': D, 'platform': 'Linux64', 'sdk': 'zorin18'}, 900)
    check('Q2 Linux64 sin declarar: BUILD-046 y no se compila nada',
          mc.es(out, 'SR_BUILD_PLATAFORMA_NO_DECLARADA_FMT')
          and not os.path.isdir(os.path.join(JAIL, 'PD', 'Linux64')), out[:300])

    r = srv.call('delphi_config', {'command': 'add-platform', 'platform': 'Linux64', 'sdk': 'zorin18',
                                   'project': D})
    out = srv.call('delphi_build', {'project': D, 'platform': 'Linux64'}, 900)
    j = J(out)
    check('Q3 control: declarada con add-platform, compila', j.get('success') is True,
          r[:120] + ' | ' + out[:300])

    srv.call('delphi_config', {'command': 'remove-platform', 'platform': 'Linux64', 'project': D})
    out = srv.call('delphi_build', {'project': D, 'platform': 'Linux64'}, 900)
    check('Q4 desactivada con remove-platform: BUILD-046',
          mc.es(out, 'SR_BUILD_PLATAFORMA_NO_DECLARADA_FMT'), out[:300])

    srv.call('delphi_create', {'kind': 'project-test', 'name': 'PT', 'dir': os.path.join(JAIL, 'PT')})
    T = os.path.join(JAIL, 'PT', 'PT.dproj')
    pon_defecto(T, 'Win32')
    out = srv.call('delphi_test', {'command': 'run', 'project': T}, 900)
    j = J(out)
    check('Q5 delphi_test sin platform=: la del proyecto (Win32), no el Win64 de antes',
          j.get('platform') == 'Win32', out[:300])

    srv.call('delphi_create', {'kind': 'project-console', 'name': 'PV', 'dir': os.path.join(JAIL, 'PV')})
    V = os.path.join(JAIL, 'PV', 'PV.dproj')
    t = open(V, encoding='utf-8-sig').read()
    t = re.sub(r'\s*<Platforms>.*?</Platforms>', '', t, count=1, flags=re.S)
    assert '<Platforms>' not in t
    open(V, 'w', encoding='utf-8').write(t)
    defecto = re.search(r"<Platform Condition=\"'\$\(Platform\)'==''\">(\w+)</Platform>", t).group(1)
    otra = 'Win32' if defecto == 'Win64' else 'Win64'
    out = srv.call('delphi_build', {'project': V, 'platform': otra}, 900)
    check('Q6 .dproj sin <Platforms>: solo su plataforma por defecto, otra -> BUILD-046',
          mc.es(out, 'SR_BUILD_PLATAFORMA_NO_DECLARADA_FMT'), out[:300])
finally:
    try: srv.mata()
    except Exception: pass

try:
    mc.fin('plataforma declarada battery')  # sys.exit: la carpeta se borra en el finally
finally:
    mc.borra(BASE)
