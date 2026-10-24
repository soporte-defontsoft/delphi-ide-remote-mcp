# -*- coding: utf-8 -*-
"""Un fuente es un paquete por su cabecera, como lo compila dcc (A30 de la 1.23).

Medido el 24-oct-2026 con dcc64: un .dpr que empieza por 'package' da un .bpl y
un .dpk que empieza por 'program' da un .exe. Tres sitios lo decidian por la
extension .dpk (add-requires, el CreateForm de add-unit y la nota de form en un
proyecto de consola); ahora preguntan Lsp.Pascal.EsFuenteDePaquete.

  K1 add-requires en un paquete escrito en un .dpr: anade el requires (ROJO
     hasta la 1.23: "no es un paquete")
  K2 add-requires en un programa escrito en un .dpk: se niega (ROJO hasta la
     1.23: se aceptaba por la extension)
  K3 (guarda) add-requires en un paquete de los de siempre (.dpk) sigue
     funcionando, y en un programa .dpr se sigue negando

Uso:  python tests/test_paquete_1230.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('test_paquete_1230')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def cruza(carpeta, nombre, de, a):
    """El fuente principal de carpeta/nombre pasa de la extension de a la a,
    con su contenido y el MainSource del .dproj."""
    viejo = os.path.join(carpeta, nombre + de)
    texto = open(viejo, 'rb').read()
    open(os.path.join(carpeta, nombre + a), 'wb').write(texto)
    os.remove(viejo)
    dproj = os.path.join(carpeta, nombre + '.dproj')
    x = open(dproj, 'rb').read().replace((nombre + de).encode(), (nombre + a).encode())
    open(dproj, 'wb').write(x)
    return os.path.join(carpeta, nombre + a)


def no_es_paquete(r):
    return mc.rechazado(r) and mc.es(r, 'SR_REQUIRES_NOT_PACKAGE_FMT')


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='test-paquete', t=300)
try:
    for k, n in (('project-package', 'PaqDpr'), ('project-console', 'ProgDpk'),
                 ('project-package', 'PaqDpk'), ('project-console', 'ProgDpr')):
        r = srv.call('delphi_create', {'kind': k, 'name': n, 'dir': os.path.join(JAIL, n)}, t=120)
        assert mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:300]
    paq_dpr = cruza(os.path.join(JAIL, 'PaqDpr'), 'PaqDpr', '.dpk', '.dpr')
    prog_dpk = cruza(os.path.join(JAIL, 'ProgDpk'), 'ProgDpk', '.dpr', '.dpk')

    r1 = srv.call('delphi_config', {'command': 'add-requires', 'project': paq_dpr, 'requires': 'vcl'})
    check('K1 add-requires en un paquete escrito en un .dpr: anade el requires',
          not mc.rechazado(r1) and 'vcl' in open(paq_dpr, encoding='utf-8-sig').read(), r1[:300])
    antes = open(prog_dpk, 'rb').read()
    r2 = srv.call('delphi_config', {'command': 'add-requires', 'project': prog_dpk, 'requires': 'vcl'})
    check('K2 add-requires en un programa escrito en un .dpk: se niega, sin tocarlo',
          no_es_paquete(r2) and open(prog_dpk, 'rb').read() == antes, r2[:300])
    dpk = os.path.join(JAIL, 'PaqDpk', 'PaqDpk.dpk')
    r3 = srv.call('delphi_config', {'command': 'add-requires', 'project': dpk, 'requires': 'vcl'})
    r4 = srv.call('delphi_config', {'command': 'add-requires',
                                     'project': os.path.join(JAIL, 'ProgDpr', 'ProgDpr.dpr'), 'requires': 'vcl'})
    check('K3 (guarda) un .dpk de siempre lo admite y un programa .dpr se niega',
          not mc.rechazado(r3) and 'vcl' in open(dpk, encoding='utf-8-sig').read() and no_es_paquete(r4),
          (r3[:200], r4[:200]))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('un fuente es un paquete por su cabecera, A30 de la 1.23')
