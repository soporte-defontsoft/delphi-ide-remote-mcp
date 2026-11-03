# -*- coding: utf-8 -*-
r"""A9 de la 1.27: lo que el build LEE se juzga con UN juez, la jaula y la biblioteca del IDE.

Medido el 3-nov-2026 en produccion: la puerta del build juzgaba las rutas de los valores del .dproj
con los lugares del MOTOR, que incluyen los del IDE (su carpeta de datos del usuario, la de los .profile
y los .sdk; la de SDKs; los sysroots). Con DCC_UnitSearchPath=$(APPDATA)\Embarcadero\BDS\<ver> y un
{$I x.profile} con nombre suelto en el .dpr, la puerta aprobaba, dcc leia el fichero del AppData del IDE
(delphi_read lo niega) y sus errores devolvian su contenido. Ahora todo lo que el build lee porque lo
DICE el proyecto (valores, {$I}/{$R}, el in de un .dpr, enlaces del arbol) pregunta a uno: la jaula +
la biblioteca del IDE (Lsp.Patch.LUGARES_DEL_BUILD), este o no encendida la zona. Lo que el AGENTE
nombra en una llamada (add-searchpath, add-deployfile) lo sigue juzgando la jaula, suelo incluido.

Un %APPDATA% FALSO (mc.appdata_perfil) con un .profile SENUELO: nunca el real.

  F0 delphi_read del senuelo: negado (la premisa: el agente no lo lee)
  F1 search path $(APPDATA)\Embarcadero\BDS\<ver> + {$I palabras.profile} suelto: BUILD-050 y la
     palabra del senuelo en ninguna parte (ROJA: compilaba y dcc la citaba)
  F2 search path $(BDSPLATFORMSDKSDIR): BUILD-050 (ROJA: aceptado)
  F3 add-searchpath de la carpeta de datos del IDE (ruta entera): negado por la JAULA, GUARD-002 (guarda;
     con $(APPDATA) lo negaba CFG-148, la macro que add-searchpath no resuelve, y no media la jaula)
  F4 {$I '<appdata falso>\...\palabras.profile'} con la ruta entera: BUILD-028 (guarda)
  F5 search path $(BDS)\source\rtl\common: compila (guarda: la instalacion la sigue leyendo)
  Con la zona de biblioteca APAGADA (DELPHI_MCP_LIBRARY_ZONE=0):
  F6 add-searchpath $(BDS)\source\rtl\common: negado (lo nombra el agente: la jaula), y el mismo
     search path puesto con set-property compila (lo dice el proyecto: la biblioteca) (guarda)
  F7 {$I '<un .inc de la instalacion>'} bajo un {$IFDEF} que no se define: no es BUILD-028
     (ROJA: BUILD-028; el search path a esa carpeta si pasaba)
  F8 add-deployfile de ese .inc: negado y el .dproj intacto (guarda: lo nombra el agente)
  F9 el .rc de un RcCompile que nombra un fichero de la instalacion: compila (ROJA: BUILD-052; el lector
     del .rc juzgaba con la jaula del agente, y ese mismo fichero en un {$R} o un icono pasaba)

Uso:  python tests/test_build_lee_ide_127.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('build-lee-ide-127')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
APPDATA, _ = mc.appdata_perfil(BASE, nombre='senuelo')
PALABRA = 'senueloPalabraA9'
ENV = {'DELPHI_MCP_ROOTS': JAIL, 'APPDATA': APPDATA}
srv = mc.Stdio(EXE, mc.entorno(ENV), nombre='lee-ide-127', t=600)
srv2 = None
# la version la dice el servidor, no la bateria: con otra activa, la carpeta de datos del IDE seria otra y F1
# pasaria tambien sin el arreglo (revisor del paisaje de la 1.27)
VER = mc.instalacion_activa(srv.call).get('version', '')
check('fixture: la version activa del IDE, por delphi_installs', bool(VER), VER)
BDS_FALSO = os.path.join(APPDATA, 'Embarcadero', 'BDS', VER)
SENUELO = os.path.join(BDS_FALSO, 'palabras.profile')
os.makedirs(BDS_FALSO, exist_ok=True)
with open(SENUELO, 'w', encoding='utf-8') as f:
    f.write('%s := secretoPalabraA9;\n' % PALABRA)


def config(s, comando, **campos):
    args = {'project': DPROJ, 'command': comando}
    args.update(campos)
    return s.call('delphi_config', args)


def build(s):
    return s.call('delphi_build', {'project': DPROJ, 'platform': 'Win64', 'config': 'Release'}, 600)


def compila(r):
    return mc.como_json(r).get('success') is True


def pon(ruta, texto):
    with open(ruta, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(texto)


def lee(ruta):
    with open(ruta, encoding='utf-8-sig') as f:
        return f.read()


def con_include(directiva):
    """El .dpr original con una directiva tras el begin del programa."""
    i = DPR_ORIGINAL.index('\nbegin')
    j = DPR_ORIGINAL.index('\n', i + 1)
    return DPR_ORIGINAL[:j + 1] + '  ' + directiva + '\r\n' + DPR_ORIGINAL[j + 1:]


def search_path(s, valor):
    pon(DPROJ, ORIGINAL)
    pon(DPR, DPR_ORIGINAL)
    return config(s, 'set-property', name='DCC_UnitSearchPath', value=valor + ';$(DCC_UnitSearchPath)')


try:
    D = os.path.join(JAIL, 'cons')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Cons', 'dir': D})
    check('fixture creada (delphi_create)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    DPROJ = os.path.join(D, 'Cons.dproj')
    DPR = os.path.join(D, 'Cons.dpr')
    ORIGINAL = lee(DPROJ)
    DPR_ORIGINAL = lee(DPR)
    RAIZ_IDE = mc.raiz_ide(srv.call)
    check('fixture: la instalacion activa', os.path.isdir(RAIZ_IDE), RAIZ_IDE)

    r = srv.call('delphi_read', {'path': SENUELO})
    check('F0 delphi_read del senuelo del AppData falso: negado', mc.rechazado(r) and PALABRA not in r, r[:200])

    search_path(srv, '$(APPDATA)\\Embarcadero\\BDS\\' + VER)
    pon(DPR, con_include('{$I palabras.profile}'))
    rb = build(srv)
    check('F1 search path al AppData del IDE + {$I} suelto: BUILD-050 y el senuelo en ninguna parte',
          mc.es(rb, 'SR_BUILD_LECTURA_FUERA_FMT') and PALABRA.lower() not in rb.lower(), rb[:400])

    search_path(srv, '$(BDSPLATFORMSDKSDIR)')
    rb = build(srv)
    check('F2 search path $(BDSPLATFORMSDKSDIR): BUILD-050', mc.es(rb, 'SR_BUILD_LECTURA_FUERA_FMT'), rb[:300])

    pon(DPROJ, ORIGINAL)
    antes = lee(DPROJ)
    # la ruta entera, sin macro: con $(APPDATA) contestaba CFG-148 antes de llegar a la jaula (revisor del paisaje)
    r = config(srv, 'add-searchpath', platform='Win64', path=BDS_FALSO)
    check('F3 add-searchpath de la carpeta de datos del IDE: negado por la jaula (GUARD-002) y el .dproj intacto',
          mc.es(r, 'SR_JAIL_FMT') and lee(DPROJ) == antes, r[:300])

    pon(DPR, con_include("{$I '%s'}" % SENUELO))
    rb = build(srv)
    check('F4 {$I} con la ruta entera del senuelo: BUILD-028 y el senuelo en ninguna parte',
          mc.es(rb, 'SR_BUILD_INCLUDE_OUTSIDE_FMT') and PALABRA.lower() not in rb.lower(), rb[:300])

    search_path(srv, '$(BDS)\\source\\rtl\\common')
    rb = build(srv)
    check('F5 search path $(BDS)\\source\\rtl\\common: compila (la instalacion se sigue leyendo)',
          compila(rb), rb[:300])
    srv.cierra()

    srv2 = mc.Stdio(EXE, mc.entorno(dict(ENV, DELPHI_MCP_LIBRARY_ZONE='0')), nombre='lee-ide-127-sin-zona', t=600)
    pon(DPROJ, ORIGINAL)
    pon(DPR, DPR_ORIGINAL)
    r = config(srv2, 'add-searchpath', platform='Win64', path='$(BDS)\\source\\rtl\\common')
    intacto = lee(DPROJ) == ORIGINAL
    search_path(srv2, '$(BDS)\\source\\rtl\\common')
    rb = build(srv2)
    check('F6 sin zona de biblioteca: add-searchpath $(BDS)\\source\\rtl\\common negado, y por set-property compila',
          mc.rechazado(r) and intacto and compila(rb), (r[:300], rb[:300]))

    inc = ''
    for d, _, fs in os.walk(os.path.join(RAIZ_IDE, 'source', 'rtl')):
        inc = next((os.path.join(d, f) for f in sorted(fs) if f.lower().endswith('.inc')), '')
        if inc:
            break
    check('fixture: un .inc de la instalacion', os.path.isfile(inc), inc)
    pon(DPROJ, ORIGINAL)
    pon(DPR, con_include("{$IFDEF NUNCA_A9_127}{$I '%s'}{$ENDIF}" % inc))
    rb = build(srv2)
    check('F7 sin zona de biblioteca: {$I} de un .inc de la instalacion no es BUILD-028',
          not mc.es(rb, 'SR_BUILD_INCLUDE_OUTSIDE_FMT') and compila(rb), rb[:300])

    antes = lee(DPROJ)
    r = config(srv2, 'add-deployfile', platform='Win64', path=inc)
    check('F8 sin zona de biblioteca: add-deployfile de un fichero de la instalacion negado y el .dproj intacto',
          mc.rechazado(r) and lee(DPROJ) == antes, r[:300])

    pon(DPR, DPR_ORIGINAL)
    with open(os.path.join(D, 'Recursos.rc'), 'w', encoding='utf-8') as f:
        f.write('DATOS RCDATA "%s"\r\n' % inc.replace('\\', '/'))
    pon(DPROJ, ORIGINAL.replace('</Project>', '<ItemGroup><RcCompile Include="Recursos.rc"><Form>Recursos.res'
                                              '</Form></RcCompile></ItemGroup></Project>'))
    rb = build(srv2)
    check('F9 sin zona de biblioteca: el .rc de un RcCompile que nombra un fichero de la instalacion compila',
          not mc.es(rb, 'SR_BUILD_RC_FMT') and compila(rb), rb[:300])
finally:
    srv.cierra()
    if srv2:
        srv2.cierra()

mc.borra(BASE)
mc.fin('lo que el build lee: la jaula y la biblioteca, no el AppData del IDE 1.27 (A9)')
