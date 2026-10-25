# -*- coding: utf-8 -*-
"""Lo que el build lee por el IN de la fuente principal se juzga (V14 de la 1.23).

Un uses X in '...' de un .dpr (o un contains X in '...' de un .dpk) lo abre
dcc como un {$I}: con el permiso del servidor, y lo que entra vuelve a salir
(dentro del binario, citado en los errores). La puerta del build juzgaba los
{$I}/{$R} y todo lo que lee el .dproj, pero no esto: un uses X in '<fuera>'
COMPILABA (medido en vivo contra r1222bp, 25-oct-2026). Se juzga la ruta,
exista o no: si no, "existe / no existe" seria un bit de fuera.

  I1  uses UFuera in '<fuera, existe>' -> BUILD-061, sin compilar
  I2  ...una de fuera que NO existe -> la MISMA negativa (no hay oraculo)
  I3  ...relativa que sale por ..\\ -> BUILD-061
  I4  (control) uses UDentro in 'UDentro.pas' -> compila
  I5  un .dpk con contains UFuera in '<fuera>' -> BUILD-061
  I6  una unidad DENTRO de la jaula pero fuera de la carpeta del proyecto,
      alcanzada por su in, con un {$I} de fuera -> BUILD-028 (su directiva se
      juzga como las de la carpeta del proyecto)
  I7  una entrada que no se lee (una comilla abierta) -> USES-026, sin compilar
  I8  "X:y" de otra unidad -> BUILD-062
  I9  la salida: delphi_config remove-unit de la entrada de fuera la quita y
      el build compila
  I10 (guarda) una DCCReference de fuera en el .dproj, exista o no -> BUILD-050
  I11 una unidad de un search path de la jaula (fuera de la carpeta del
      proyecto) con un {$I} de fuera -> BUILD-028

Uso:  python tests/test_build_in_fuera_1230.py [ruta-a-DelphiLspMcp.exe]
"""
import os, glob
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build_in_fuera_1230')
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
os.makedirs(JAIL)
UNIDAD = os.path.splitdrive(JAIL)[0].upper()
OTRA_UNIDAD = 'Y:' if UNIDAD == 'Z:' else 'Z:'


def escribe(p, texto, nl='\r\n'):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'w', encoding='utf-8', newline=nl).write(texto)


def unidad(nombre, extra=''):
    return ('unit %s;\n\ninterface\n\nfunction Dame%s: Integer;\n\nimplementation\n\n%s'
            'function Dame%s: Integer;\nbegin\n  Result := 1;\nend;\n\nend.\n' % (nombre, nombre, extra, nombre))


escribe(os.path.join(FUERA, 'UFuera.pas'), unidad('UFuera'))
escribe(os.path.join(FUERA, 'secreto.inc'), '// de fuera\n')
OTRA = os.path.join(JAIL, 'otra')
escribe(os.path.join(OTRA, 'UOtra.pas'), unidad('UOtra', '{$I %s}\n\n' % os.path.join(FUERA, 'secreto.inc')))
LIB = os.path.join(JAIL, 'lib')
escribe(os.path.join(LIB, 'ULib.pas'), unidad('ULib', '{$I %s}\n\n' % os.path.join(FUERA, 'secreto.inc')))

EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'LOCALAPPDATA': os.path.join(BASE, 'appdata')}),
               nombre='build_in_fuera_1230', t=300)
try:
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'PIn', 'dir': os.path.join(JAIL, 'PIn')})
    dprs = glob.glob(os.path.join(JAIL, 'PIn', '**', 'PIn.dpr'), recursive=True)
    check('I0 (preparacion) el proyecto de consola nace', bool(dprs), r[:300])
    DPR = dprs[0]
    DPROJ = DPR[:-4] + '.dproj'
    PDIR = os.path.dirname(DPR)
    escribe(os.path.join(PDIR, 'UDentro.pas'), unidad('UDentro'))
    DPR_0 = open(DPR, encoding='utf-8-sig').read()
    DPROJ_0 = open(DPROJ, encoding='utf-8-sig').read()
    assert 'uses' in DPR_0 and '<ItemGroup>' in DPROJ_0

    def paso(dpr=lambda s: s, dproj=lambda s: s):
        """El proyecto como nacio con UN cambio, y su build: (el JSON, su texto)."""
        open(DPR, 'w', encoding='utf-8').write(dpr(DPR_0))
        open(DPROJ, 'w', encoding='utf-8').write(dproj(DPROJ_0))
        rb = srv.call('delphi_build', {'project': DPROJ, 'platform': 'Win64', 'config': 'Debug'}, t=300)
        return mc.como_json(rb), rb

    def con_uses(entrada):
        return lambda s: s.replace('uses', 'uses\n  %s,' % entrada, 1)

    def sin_compilar(j):
        return j.get('success') is not True

    fuera = os.path.join(FUERA, 'UFuera.pas')
    j1, r1 = paso(con_uses("UFuera in '%s'" % fuera))
    check('I1 uses UFuera in <fuera, existe>: BUILD-061 y no se compila',
          mc.abre(r1, 'SR_BUILD_IN_FUERA_FMT') and sin_compilar(j1), r1[:400])
    no_existe = os.path.join(FUERA, 'NoExiste.pas')
    j2, r2 = paso(con_uses("UNoExiste in '%s'" % no_existe))
    check('I2 ...una de fuera que NO existe: la misma negativa (no hay oraculo de existencia)',
          mc.abre(r2, 'SR_BUILD_IN_FUERA_FMT') and sin_compilar(j2) and
          # (la ruta llega enmascarada, srvc:\...: se compara con el nombre del fichero cambiado)
          r2.replace('NoExiste.pas', 'X.pas').replace('UNoExiste', 'X') ==
          r1.replace('UFuera.pas', 'X.pas').replace('UFuera', 'X'),
          (r1[:300], r2[:300]))
    rel = os.path.relpath(fuera, PDIR)
    j3, r3 = paso(con_uses("UFuera in '%s'" % rel))
    check('I3 ...relativa que sale por ..\\: BUILD-061', mc.abre(r3, 'SR_BUILD_IN_FUERA_FMT') and sin_compilar(j3),
          (rel, r3[:400]))
    j4, r4 = paso(con_uses("UDentro in 'UDentro.pas'"))
    check('I4 (control) uses UDentro in \'UDentro.pas\': compila', j4.get('success') is True, r4[:400])
    j6, r6 = paso(con_uses("UOtra in '%s'" % os.path.relpath(os.path.join(OTRA, 'UOtra.pas'), PDIR)))
    check('I6 una unidad de la jaula fuera de la carpeta del proyecto, por su in, con un {$I} de fuera: '
          'BUILD-028 (su directiva se juzga)', mc.abre(r6, 'SR_BUILD_INCLUDE_OUTSIDE_FMT') and sin_compilar(j6),
          r6[:400])
    j7, r7 = paso(con_uses("UMal in 'abierto.pas"))
    check('I7 una entrada con la comilla abierta: USES-026 y no se compila',
          mc.abre(r7, 'SR_USES_ENTRADA_ILEGIBLE_FMT') and sin_compilar(j7), r7[:400])
    j8, r8 = paso(con_uses("UOtraUnidad in '%sUOtraUnidad.pas'" % OTRA_UNIDAD))
    check('I8 "%sx" (la carpeta actual de otra unidad): BUILD-062' % OTRA_UNIDAD,
          mc.abre(r8, 'SR_BUILD_IN_NO_VERIFICABLE_FMT') and sin_compilar(j8), r8[:400])

    # I9: la salida que dice la negativa
    open(DPR, 'w', encoding='utf-8').write(con_uses("UFuera in '%s'" % fuera)(DPR_0))
    open(DPROJ, 'w', encoding='utf-8').write(DPROJ_0)
    rr = srv.call('delphi_config', {'command': 'remove-unit', 'project': DPROJ, 'path': fuera})
    rb = srv.call('delphi_build', {'project': DPROJ, 'platform': 'Win64', 'config': 'Debug'}, t=300)
    check('I9 la salida: remove-unit de la entrada de fuera la quita del .dpr y el build compila',
          'UFuera' not in open(DPR, encoding='utf-8-sig').read() and mc.como_json(rb).get('success') is True,
          (rr[:300], rb[:300]))

    # I10: la DCCReference de fuera, exista o no (guarda: la juzga LecturasDelBuildDenegadas)
    for ruta in (fuera, no_existe):
        j, rd = paso(dproj=lambda s, ruta=ruta: s.replace('<ItemGroup>', '<ItemGroup>\n        '
                                                          '<DCCReference Include="%s"/>' % ruta, 1))
        check('I10 una DCCReference de fuera (%s): BUILD-050' % ('existe' if ruta == fuera else 'no existe'),
              mc.abre(rd, 'SR_BUILD_LECTURA_FUERA_FMT') and sin_compilar(j), rd[:400])

    # I11: por un search path de la jaula, fuera de la carpeta del proyecto
    j11, r11 = paso(con_uses('ULib'), lambda s: s.replace('<ItemGroup>', '<PropertyGroup>\n        '
                    '<DCC_UnitSearchPath>%s;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>\n    </PropertyGroup>\n'
                    '    <ItemGroup>' % LIB, 1))
    check('I11 una unidad de un search path de la jaula con un {$I} de fuera: BUILD-028',
          mc.abre(r11, 'SR_BUILD_INCLUDE_OUTSIDE_FMT') and sin_compilar(j11), r11[:400])

    # I5: un paquete con contains de fuera
    r = srv.call('delphi_create', {'kind': 'project-package', 'name': 'PkIn', 'dir': os.path.join(JAIL, 'PkIn')})
    dpks = glob.glob(os.path.join(JAIL, 'PkIn', '**', 'PkIn.dpk'), recursive=True)
    check('I5 (preparacion) el paquete nace', bool(dpks), r[:300])
    if dpks:
        dpk = open(dpks[0], encoding='utf-8-sig').read()
        if 'contains' in dpk:
            dpk = dpk.replace('contains', "contains\n  UFuera in '%s'," % fuera, 1)
        else:
            dpk = dpk.replace('end.', "contains\n  UFuera in '%s';\n\nend." % fuera, 1)
        open(dpks[0], 'w', encoding='utf-8').write(dpk)
        rp = srv.call('delphi_build', {'project': dpks[0][:-4] + '.dproj', 'platform': 'Win64', 'config': 'Debug'},
                      t=300)
        check('I5 un .dpk con contains UFuera in <fuera>: BUILD-061',
              mc.abre(rp, 'SR_BUILD_IN_FUERA_FMT') and sin_compilar(mc.como_json(rp)), rp[:400])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('lo que lee el in de la fuente principal, V14 de la 1.23')
