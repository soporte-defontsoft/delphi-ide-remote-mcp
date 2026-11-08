# -*- coding: utf-8 -*-
"""El requires de un paquete tambien en su .dproj, como lo escribe el IDE (B7 de la 1.29).

Medido el 8-nov-2026 en los 17 paquetes de los Samples de la 37.0: cada .dproj de
paquete lleva una <DCCReference Include="<paquete>.dcp"/> por cada requires de su
.dpk, la primera justo tras </DelphiCompile> y todas delante de las units. El
servidor no las escribia: add-requires tocaba solo el .dpk y project-package hacia
nacer el .dproj sin la de rtl, que su .dpk si pide.

  Q1 project-package: el .dproj nace con la de rtl.dcp, tras </DelphiCompile>
     (ROJO hasta la 1.29)
  Q2 add-requires vcl;dbrtl en un paquete con una unit: las dos en el .dproj, tras
     rtl.dcp y DELANTE de la unit, en la forma del IDE, y la respuesta dice lo que
     recibio el .dproj (CFG-154, visto en vivo el 8-nov) (ROJO hasta la 1.29)
  Q3 un paquete que ya pide vcl en su .dpk y no lo tiene en el .dproj: add-requires
     vcl se lo pone y lo dice (CFG-153; ROJO hasta la 1.29: CFG-052 y nada)
  Q4 (guarda) otra vez lo mismo: CFG-052 y el .dpk y el .dproj byte a byte
  Q5 un .dproj en LF sigue en LF (el salto de su fichero, como add-unit)
  Q6 TODO O NADA: con el .dproj de solo lectura el .dpk tampoco cambia (ROJO
     hasta la 1.29: el .dpk se escribia y el .dproj no se miraba)
  Q7 (guarda) el paquete con sus requires en el .dproj COMPILA
  Q8 un paquete sin .dproj: CFG-053 y la nota CFG-048 nombra el .dpk, que es lo que
     se escribio (ROJO hasta la 1.29: decia ".dpr"), y no nace un .dproj
  Q9 el otro llamador de CFG-048: add-unit en ese paquete sin .dproj tambien nombra
     el .dpk (rigor 7: cada camino del texto cambiado)

Uso:  python tests/test_requires_dproj_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os, re, stat
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('test_requires_dproj_129')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def lee(p):
    return open(p, 'rb').read().decode('utf-8-sig')


def refs(dproj):
    """Los Include de sus DCCReference, en orden de documento."""
    return re.findall(r'<DCCReference\s+Include="([^"]*)"', lee(dproj))


def tras_compile(dproj, include):
    """La DCCReference de include es lo primero tras </DelphiCompile>."""
    t = lee(dproj)
    i = t.find('</DelphiCompile>')
    return i >= 0 and re.match(r'</DelphiCompile>\r?\n\s*<DCCReference Include="%s"/>' % re.escape(include), t[i:]) is not None


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='test-requires-dproj', t=300)
try:
    for n in ('PaqQ1', 'PaqQ3', 'PaqQ5', 'PaqQ6', 'PaqQ8'):
        r = srv.call('delphi_create', {'kind': 'project-package', 'name': n, 'dir': os.path.join(JAIL, n)}, t=120)
        assert mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:300]
    d1 = os.path.join(JAIL, 'PaqQ1', 'PaqQ1.dproj')
    check('Q1 project-package: el .dproj nace con la de rtl.dcp, tras </DelphiCompile>',
          refs(d1) == ['rtl.dcp'] and tras_compile(d1, 'rtl.dcp'), refs(d1))

    r = srv.call('delphi_create', {'kind': 'unit', 'name': 'UQ1', 'project': os.path.join(JAIL, 'PaqQ1', 'PaqQ1.dpk')})
    assert not mc.rechazado(r), r[:300]
    r = srv.call('delphi_config', {'command': 'add-requires', 'project': d1, 'requires': 'vcl;dbrtl'})
    t = lee(d1)
    check('Q2 add-requires vcl;dbrtl: en el .dproj tras rtl.dcp y delante de la unit, en la forma del IDE',
          mc.abre(r, 'SN_REQUIRES_ADDED_FMT') and refs(d1) == ['rtl.dcp', 'vcl.dcp', 'dbrtl.dcp', 'UQ1.pas']
          and mc.es(r, 'SN_REQUIRES_DPROJ_TAMBIEN_FMT') and 'vcl.dcp, dbrtl.dcp' in r
          and '\r\n        <DCCReference Include="vcl.dcp"/>\r\n' in t, (r[:200], refs(d1)))

    # Q3: el .dpk ya pide vcl (escrito a mano, como lo deja otra herramienta) y el .dproj no
    k3 = os.path.join(JAIL, 'PaqQ3', 'PaqQ3.dpk')
    d3 = os.path.join(JAIL, 'PaqQ3', 'PaqQ3.dproj')
    # leido ANTES de abrirlo para escribir: open(..., 'wb') lo trunca, y en la misma
    # expresion lee() leia un fichero vacio
    t3 = lee(k3).replace('  rtl;', '  rtl,\r\n  vcl;')
    open(k3, 'wb').write(t3.encode('utf-8'))
    r = srv.call('delphi_config', {'command': 'add-requires', 'project': d3, 'requires': 'vcl'})
    check('Q3 ya en el requires y no en el .dproj: add-requires se lo pone y lo dice (CFG-153)',
          mc.abre(r, 'SN_REQUIRES_EN_DPROJ_FMT') and refs(d3) == ['rtl.dcp', 'vcl.dcp'], (r[:200], refs(d3)))
    a_k, a_d = open(k3, 'rb').read(), open(d3, 'rb').read()
    r = srv.call('delphi_config', {'command': 'add-requires', 'project': d3, 'requires': 'vcl;rtl'})
    check('Q4 (guarda) otra vez: CFG-052 y el .dpk y el .dproj byte a byte',
          mc.abre(r, 'SN_REQUIRES_PRESENT_FMT') and open(k3, 'rb').read() == a_k and open(d3, 'rb').read() == a_d,
          r[:200])

    d5 = os.path.join(JAIL, 'PaqQ5', 'PaqQ5.dproj')
    b5 = open(d5, 'rb').read().replace(b'\r\n', b'\n')
    open(d5, 'wb').write(b5)
    r = srv.call('delphi_config', {'command': 'add-requires', 'project': d5, 'requires': 'vcl'})
    b5 = open(d5, 'rb').read()
    check('Q5 un .dproj en LF sigue en LF',
          mc.abre(r, 'SN_REQUIRES_ADDED_FMT') and b'\r' not in b5 and b'Include="vcl.dcp"' in b5, r[:200])

    k6 = os.path.join(JAIL, 'PaqQ6', 'PaqQ6.dpk')
    d6 = os.path.join(JAIL, 'PaqQ6', 'PaqQ6.dproj')
    a_k = open(k6, 'rb').read()
    os.chmod(d6, stat.S_IREAD)
    try:
        r = srv.call('delphi_config', {'command': 'add-requires', 'project': d6, 'requires': 'vcl'})
    finally:
        os.chmod(d6, stat.S_IREAD | stat.S_IWRITE)
    check('Q6 TODO O NADA: con el .dproj de solo lectura el .dpk tampoco cambia',
          mc.rechazado(r) and open(k6, 'rb').read() == a_k and 'vcl.dcp' not in lee(d6), r[:300])

    r = srv.call('delphi_build', {'project': d1, 'platform': 'Win64', 'config': 'Debug', 'target': 'Build'}, t=600)
    check('Q7 (guarda) el paquete con sus requires en el .dproj COMPILA', '"success":true' in r.replace(' ', ''), r[:300])

    k8 = os.path.join(JAIL, 'PaqQ8', 'PaqQ8.dpk')
    d8 = os.path.join(JAIL, 'PaqQ8', 'PaqQ8.dproj')
    os.remove(d8)
    r = srv.call('delphi_config', {'command': 'add-requires', 'project': k8, 'requires': 'vcl'})
    nota = [l for l in r.splitlines() if mc.id_de('SN_UNIT_NO_DPROJ_FMT') in l]
    check('Q8 sin .dproj: CFG-053, la nota CFG-048 nombra el .dpk y no nace un .dproj',
          mc.abre(r, 'SN_REQUIRES_ADDED_FMT') and mc.es(r, 'SN_UNIT_NO_DPROJ_FMT') and len(nota) == 1
          and 'PaqQ8.dpk' in nota[0] and '.dpr ' not in nota[0] and 'vcl' in lee(k8) and not os.path.exists(d8),
          r[:300])

    u9 = os.path.join(JAIL, 'PaqQ8', 'UQ9.pas')
    with open(u9, 'wb') as f:
        f.write(b'unit UQ9;\r\ninterface\r\nimplementation\r\nend.\r\n')
    r = srv.call('delphi_config', {'command': 'add-unit', 'project': k8, 'path': u9})
    nota = [l for l in r.replace('. [', '.\n[').splitlines() if mc.id_de('SN_UNIT_NO_DPROJ_FMT') in l]
    check('Q9 add-unit en el paquete sin .dproj: la nota CFG-048 tambien nombra el .dpk',
          not mc.rechazado(r) and len(nota) == 1 and 'PaqQ8.dpk' in nota[0] and 'UQ9' in lee(k8)
          and not os.path.exists(d8), r[:400])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('el requires de un paquete tambien en su .dproj, B7 de la 1.29')
