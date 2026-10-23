# -*- coding: utf-8 -*-
r"""Lo que una tool prometia y no hacia (1.22.2; Opus 5.5 en Hermes sobre la 1.22.1, 22/23-oct-2026).

delphi_move dice "What it could not re-point is named" y callaba lo que el build lee por una propiedad del
documento ($(My-Path), que puede ser cualquier cosa y no se re-apunta) o escrito absoluto: tras mover la carpeta,
F2613 sin pista. Ahora MOVE-021 lo nombra, con el valor expandido como lo lee msbuild (el expansor de la puerta).

  M1 un proyecto con My-Path=lib y DCC_UnitSearchPath=$(My-Path): mover lib a lib2 nombra My-Path en MOVE-021
     (ROJO contra la 1.22.1: callaba)
  M1b ...y es lo que rompe: el build da F2613 hasta que set-property My-Path=lib2, y entonces compila
  M2 control: una ruta relativa ESCRITA (lib3) se re-apunta (MOVE-005) y no sale en MOVE-021
  M3 una ruta absoluta del DCC_IncludePath a lo movido: nombrada (ROJO igual)
  M4 control: mover una carpeta Data no nombra el DCC_Namespace (Data.Win no es una ruta que lea el build)
  M5 control: el proyecto entero renombrado en el mismo nivel: su $(Comun)=..\comun sigue llegando, nada que decir
  M6 ...y un nivel mas adentro: $(Comun)=..\comun ya no llega, nombrado (ROJO igual)

delphi_config set-property cambia un valor EN SU SITIO, y uno con $(X) podia quedar encima de la definicion de X:
msbuild lee el .dproj de arriba abajo y lo lee vacio (F2613), sin aviso. Ahora CFG-136 lo dice.
  P1 DCC_UnitSearchPath=lib, luego My-Path=lib (al final), luego DCC_UnitSearchPath=$(My-Path) en su sitio:
     CFG-136 dice que msbuild lee $(My-Path) vacio ahi (ROJO contra la 1.22.1: callaba)
  P1b ...y es verdad: el build da F2613
  P2 control: una propiedad NUEVA con $(My-Path) va al final, debajo de My-Path: sin nota
  P3 remove-property y set-property otra vez (lo que dice la nota): sin nota, y compila

Uso:  python tests/test_contratos_1222.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('contratos-1222')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='c1222', t=600)


def lee(p):
    return open(p, encoding='utf-8-sig', newline='').read()


def planta(dproj, tras, texto):
    """Mete texto en el .dproj detras de la primera linea que contiene tras (como lo dejaria un operador)."""
    dp = lee(dproj)
    i = dp.index(tras)
    j = dp.index('\n', i) + 1
    open(dproj, 'w', encoding='utf-8-sig', newline='').write(dp[:j] + texto + dp[j:])


def nombrado(r, *trozos):
    """La linea de MOVE-021 de la respuesta lleva todos los trozos."""
    for linea in (r or '').replace('\\n', '\n').split('\n'):
        if mc.es(linea, 'SN_REUBICA_NO_LLEGA_FMT'):
            return all(t in linea for t in trozos)
    return False


try:
    app = os.path.join(JAIL, 'app')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'App', 'dir': app})
    check('M0 fixture creada (delphi_create)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    dproj = os.path.join(app, 'App.dproj')
    for sub in ('lib', 'lib3', 'inc', 'Data'):
        os.makedirs(os.path.join(app, sub))
    open(os.path.join(app, 'lib', 'ULib.pas'), 'w', newline='\r\n').write(
        'unit ULib;\ninterface\nfunction Doble(X: Integer): Integer;\nimplementation\n'
        'function Doble(X: Integer): Integer;\nbegin\n  Result := X * 2;\nend;\nend.\n')
    open(os.path.join(app, 'inc', 'comun.inc'), 'w', newline='\r\n').write('// comun\n')
    open(os.path.join(app, 'Data', 'datos.txt'), 'w').write('datos')
    os.makedirs(os.path.join(JAIL, 'comun'))
    planta(dproj, '<DCC_DcuOutput>',
           '        <My-Path>lib</My-Path>\r\n'
           '        <Comun>..\\comun</Comun>\r\n'
           '        <DCC_UnitSearchPath>$(My-Path);lib3;$(Comun);$(DCC_UnitSearchPath)</DCC_UnitSearchPath>\r\n'
           '        <DCC_IncludePath>%s;$(DCC_IncludePath)</DCC_IncludePath>\r\n' % os.path.join(app, 'inc'))
    # el uses a mano: adduses de una unit de la carpeta del proyecto la manda a add-unit (USES-021), y aqui
    # tiene que encontrarse SOLO por el search path
    dpr = os.path.join(app, 'App.dpr')
    t = lee(dpr)
    open(dpr, 'w', encoding='utf-8-sig', newline='').write(t.replace('System.SysUtils;', 'System.SysUtils, ULib;', 1))
    check('M0 ...el .dpr usa ULib, que se encuentra por $(My-Path)', 'ULib;' in lee(dpr), lee(dpr)[:300])
    r = srv.call('delphi_build', {'project': dproj, 'platform': 'Win64'}, 300)
    check('M0 ...y compila antes de mover nada', mc.como_json(r).get('success') is True, r[:400])

    r = srv.call('delphi_move', {'path': os.path.join(app, 'lib'), 'dest': os.path.join(app, 'lib2')})
    check('M1 mover lib a lib2: MOVE-021 nombra el DCC_UnitSearchPath que llega por $(My-Path)',
          not mc.fallo(r) and nombrado(r, 'App.dproj', 'DCC_UnitSearchPath', '$(My-Path)', 'lib2'), r[:900])
    check('M1 ...y la propiedad sigue como estaba: no se reescribe', '<My-Path>lib</My-Path>' in lee(dproj),
          lee(dproj)[:300])
    r = srv.call('delphi_build', {'project': dproj, 'platform': 'Win64'}, 300)
    check('M1b ...es lo que rompe: el build da F2613 por ULib', 'F2613' in r and 'ULib' in r, r[:400])
    r = srv.call('delphi_config', {'project': dproj, 'command': 'set-property', 'name': 'My-Path',
                                   'value': 'lib2'})
    r = srv.call('delphi_build', {'project': dproj, 'platform': 'Win64'}, 300)
    check('M1b ...y con set-property My-Path=lib2 compila', mc.como_json(r).get('success') is True, r[:400])

    r = srv.call('delphi_move', {'path': os.path.join(app, 'lib3'), 'dest': os.path.join(app, 'lib4')})
    check('M2 control: lib3, escrita, se re-apunta (MOVE-005) y MOVE-021 no la nombra',
          mc.es(r, 'SN_REUBICA_FMT') and ';lib4;' in lee(dproj) and not mc.es(r, 'SN_REUBICA_NO_LLEGA_FMT'),
          r[:900])

    r = srv.call('delphi_move', {'path': os.path.join(app, 'inc'), 'dest': os.path.join(app, 'inc2')})
    check('M3 una ruta ABSOLUTA del DCC_IncludePath a lo movido: nombrada en MOVE-021',
          nombrado(r, 'App.dproj', 'DCC_IncludePath', 'inc2'), r[:900])

    r = srv.call('delphi_move', {'path': os.path.join(app, 'Data'), 'dest': os.path.join(app, 'Data2')})
    check('M4 control: mover Data no nombra el DCC_Namespace (no es una ruta que lea el build)',
          not mc.fallo(r) and not mc.es(r, 'SN_REUBICA_NO_LLEGA_FMT'), r[:900])

    app2 = os.path.join(JAIL, 'app2')
    r = srv.call('delphi_move', {'path': app, 'dest': app2})
    check('M5 control: el proyecto renombrado en el MISMO nivel: $(Comun)=..\\comun sigue llegando',
          not mc.fallo(r) and not nombrado(r, '$(Comun)'), r[:900])
    r = srv.call('delphi_move', {'path': app2, 'dest': os.path.join(JAIL, 'sub', 'app2')})
    check('M6 ...y un nivel mas adentro: $(Comun) ya no llega a comun, nombrado',
          nombrado(r, 'App.dproj', 'DCC_UnitSearchPath', '$(Comun)', 'comun'), r[:900])

    pdir = os.path.join(JAIL, 'prop')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Prop', 'dir': pdir})
    check('P0 fixture creada (delphi_create)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    pproj = os.path.join(pdir, 'Prop.dproj')
    os.makedirs(os.path.join(pdir, 'lib'))
    open(os.path.join(pdir, 'lib', 'ULib.pas'), 'w', newline='\r\n').write(
        'unit ULib;\ninterface\nfunction Doble(X: Integer): Integer;\nimplementation\n'
        'function Doble(X: Integer): Integer;\nbegin\n  Result := X * 2;\nend;\nend.\n')
    pdpr = os.path.join(pdir, 'Prop.dpr')
    t = lee(pdpr)
    open(pdpr, 'w', encoding='utf-8-sig', newline='').write(t.replace('System.SysUtils;', 'System.SysUtils, ULib;', 1))

    def pon(nombre, valor):
        return srv.call('delphi_config', {'project': pproj, 'command': 'set-property', 'name': nombre,
                                          'value': valor})

    r1, r2 = pon('DCC_UnitSearchPath', 'lib'), pon('My-Path', 'lib')
    check('P0 ...DCC_UnitSearchPath=lib y despues My-Path=lib', mc.es(r1, 'SN_CFG_PROPERTY_PUESTA_FMT') and
          mc.es(r2, 'SN_CFG_PROPERTY_PUESTA_FMT') and 'EMPTY' not in r1 + r2, (r1[:300], r2[:300]))
    dp = lee(pproj)
    check('P0 ...My-Path queda DEBAJO de DCC_UnitSearchPath', dp.index('<DCC_UnitSearchPath>') < dp.index('<My-Path>'),
          dp[:200])
    r = pon('DCC_UnitSearchPath', '$(My-Path)')
    check('P1 DCC_UnitSearchPath=$(My-Path) en su sitio, encima de My-Path: CFG-136 dice que se lee VACIO',
          mc.es(r, 'SN_CFG_PROPERTY_PUESTA_FMT') and 'reads $(My-Path) EMPTY here' in r, r[:600])
    r = srv.call('delphi_build', {'project': pproj, 'platform': 'Win64'}, 300)
    check('P1b ...y es verdad: el build da F2613 por ULib', 'F2613' in r and 'ULib' in r, r[:400])
    r = pon('Otra', '$(My-Path)\\x')
    check('P2 control: una propiedad NUEVA con $(My-Path) va al final, debajo: sin nota',
          mc.es(r, 'SN_CFG_PROPERTY_PUESTA_FMT') and 'EMPTY' not in r, r[:600])
    rq = srv.call('delphi_config', {'project': pproj, 'command': 'remove-property', 'name': 'DCC_UnitSearchPath'})
    r = pon('DCC_UnitSearchPath', '$(My-Path)')
    check('P3 remove-property y set-property otra vez: sin nota',
          mc.es(rq, 'SN_CFG_PROPERTY_QUITADA_FMT') and mc.es(r, 'SN_CFG_PROPERTY_PUESTA_FMT') and 'EMPTY' not in r,
          (rq[:300], r[:600]))
    r = srv.call('delphi_build', {'project': pproj, 'platform': 'Win64'}, 300)
    check('P3 ...y compila', mc.como_json(r).get('success') is True, r[:400])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('contratos 1222')
