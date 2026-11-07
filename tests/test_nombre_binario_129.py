# -*- coding: utf-8 -*-
"""1.29 (B1 del revisor del paisaje): el NOMBRE del binario que deja un build, como lo deja dcc. El nombrador
(Lsp.Dproj.NombreDelBinario) solo sabia del programa: probaba <proyecto> con cada extension de la plataforma, y
una libreria o un paquete con sufijo salian SIN output (medido el 7-nov-2026 en produccion c166: libMideLib.so,
MidePaquete370.bpl y bplMidePaquete370.so). La clase la dice la cabecera del fuente, el prefijo, el sufijo y la
version sus directivas de nombre (AUTO = el sufijo del compilador de la instalacion), y las extensiones y los
prefijos de cada plataforma, la tabla de CodeGear.Common.Targets.

  N1 control: un programa Win64 da <proyecto>.exe
  N2 libreria Win64 (GenDll) da Lib.dll
  N3 libreria Linux64 da libLib.so. ROJO contra 166bea8b: sin output
  N4 paquete Win64 con LIBSUFFIX AUTO da Paq370.bpl (el sufijo del compilador). ROJO contra 166bea8b
  N5 paquete Linux64 da bplPaq370.so. ROJO contra 166bea8b
  N6 paquete Win64 con un LIBSUFFIX literal ('abc') da Paqabc.bpl
  (N3 y N5 necesitan un SDK de Linux64 por defecto en el IDE; sin el, NOTA)

Uso:  python tests/test_nombre_binario_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('nombre_binario_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='nombre-bin', t=900)


def salida(dproj, plat, sdk=''):
    args = {'project': dproj, 'platform': plat}
    if sdk:
        args['sdk'] = sdk
    r = srv.call('delphi_build', args, 900)
    j = mc.como_json(r) or {}
    return os.path.basename(j.get('output') or ''), j.get('success'), r


def reescribe(path, viejo, nuevo):
    t = open(path, encoding='utf-8-sig').read()
    assert viejo in t, (path, viejo)
    with open(path, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(t.replace(viejo, nuevo, 1))


try:
    SDK = mc.sdk_por_defecto(srv.call, 'Linux64')
    # N1: el control, un programa
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'Prog', 'dir': os.path.join(JAIL, 'Prog')})
    nombre, ok, r = salida(os.path.join(JAIL, 'Prog', 'Prog.dproj'), 'Win64')
    check('N1 control: un programa Win64 da Prog.exe', ok and nombre == 'Prog.exe', (nombre, r[:200]))

    # una libreria: la consola pasa a library y el .dproj declara GenDll, como el IDE
    LIB = os.path.join(JAIL, 'Lib')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'Lib', 'dir': LIB})
    DPR = os.path.join(LIB, 'Lib.dpr')
    with open(DPR, 'w', encoding='utf-8-sig', newline='') as f:
        f.write('library Lib;\r\n\r\n{$R *.res}\r\n\r\nfunction Suma(A, B: Integer): Integer; stdcall;\r\n'
                'begin\r\n  Result := A + B;\r\nend;\r\n\r\nexports\r\n  Suma;\r\n\r\nbegin\r\nend.\r\n')
    LDPROJ = os.path.join(LIB, 'Lib.dproj')
    srv.call('delphi_config', {'command': 'set-property', 'project': LDPROJ, 'name': 'GenDll', 'value': 'true'})
    nombre, ok, r = salida(LDPROJ, 'Win64')
    check('N2 libreria Win64 da Lib.dll', ok and nombre == 'Lib.dll', (nombre, r[:200]))

    # un paquete con el sufijo de la instalacion
    PAQ = os.path.join(JAIL, 'Paq')
    srv.call('delphi_create', {'kind': 'project-package', 'name': 'Paq', 'dir': PAQ})
    DPK = os.path.join(PAQ, 'Paq.dpk')
    reescribe(DPK, '{$IMPLICITBUILD ON}', '{$IMPLICITBUILD ON}\r\n{$LIBSUFFIX AUTO}')
    PDPROJ = os.path.join(PAQ, 'Paq.dproj')
    nombre, ok, r = salida(PDPROJ, 'Win64')
    hay_370 = os.path.isfile(os.path.join(PAQ, 'Win64', 'Debug', 'Paq370.bpl'))
    check('N4 paquete Win64 con LIBSUFFIX AUTO da Paq370.bpl, el que deja dcc. ROJO contra 166bea8b: sin output',
          ok and hay_370 and nombre == 'Paq370.bpl', (nombre, hay_370, r[:200]))

    if not SDK:
        print('NOTA N3 y N5 no se miden: el IDE de esta maquina no tiene SDK por defecto para Linux64')
    else:
        srv.call('delphi_config', {'command': 'add-platform', 'project': LDPROJ, 'platform': 'Linux64'})
        nombre, ok, r = salida(LDPROJ, 'Linux64', SDK)
        check('N3 libreria Linux64 da libLib.so. ROJO contra 166bea8b: sin output',
              ok and nombre == 'libLib.so', (nombre, r[:200]))
        srv.call('delphi_config', {'command': 'add-platform', 'project': PDPROJ, 'platform': 'Linux64'})
        nombre, ok, r = salida(PDPROJ, 'Linux64', SDK)
        check('N5 paquete Linux64 da bplPaq370.so. ROJO contra 166bea8b: sin output',
              ok and nombre == 'bplPaq370.so', (nombre, r[:200]))

    # N6: un sufijo literal, por EL lector de literales
    reescribe(DPK, '{$LIBSUFFIX AUTO}', "{$LIBSUFFIX 'abc'}")
    nombre, ok, r = salida(PDPROJ, 'Win64')
    check("N6 paquete Win64 con LIBSUFFIX 'abc' da Paqabc.bpl", ok and nombre == 'Paqabc.bpl'
          and os.path.isfile(os.path.join(PAQ, 'Win64', 'Debug', 'Paqabc.bpl')), (nombre, r[:200]))
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('el nombre del binario de una libreria o un paquete (1.29)')
