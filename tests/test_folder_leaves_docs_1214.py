# -*- coding: utf-8 -*-
r"""Borrar una carpeta suelta el motor que tiene un documento abierto bajo ella (1.21.4).
Medido el 19-oct-2026 en el NAS: una unidad en x\Units gobernada por el .dproj de ARRIBA
(la carpeta que el motor retiene es la del proyecto, no la borrada) -> delphi_delete de
Units no soltaba el motor, su handle dejaba la carpeta "borrandose" en el recurso SMB y
el padre no se vaciaba hasta que el motor se paraba solo. En NTFS no queda fantasma,
pero el motor tampoco se soltaba (medido por proceso).

  F1  hover en la unidad de x\Units y en otro proyecto: un motor por proyecto
  F2  delphi_delete de x\Units: va a la papelera y el motor que tenia la unidad
      abierta se para (queda solo el del otro proyecto)
  F3  control: el motor del otro proyecto, sin documentos bajo la carpeta, sigue vivo

F2 es ROJA contra 1.21.3 (pasar su exe como argumento).

Uso:  python tests/test_folder_leaves_docs_1214.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('folder-leaves-docs')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='fld', t=300)

try:
    P = os.path.join(BASE, 'P')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Arriba', 'dir': P})
    check('fixture: proyecto Arriba', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    r = srv.call('delphi_create', {'kind': 'unit', 'name': 'USuelta', 'project': os.path.join(P, 'Arriba.dpr'),
                                   'dir': 'x\\Units'})
    check('fixture: unidad en x\\Units, gobernada por el .dproj de arriba', not mc.rechazado(r), r[:200])
    unidad = os.path.join(P, 'x', 'Units', 'USuelta.pas')
    Q = os.path.join(BASE, 'Q')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Otro', 'dir': Q})
    check('fixture: proyecto Otro (control)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])

    srv.call('delphi_hover', {'path': unidad, 'line': 0, 'character': 5}, t=240)
    srv.call('delphi_hover', {'path': os.path.join(Q, 'Otro.dpr'), 'line': 0, 'character': 8}, t=240)
    antes = mc.hijos_lsp(srv.p.pid)
    check('F1 los hover arrancan los motores: uno por proyecto', len(antes) == 2, antes)

    r = srv.call('delphi_delete', {'path': os.path.join(P, 'x', 'Units')})
    despues = mc.hijos_lsp(srv.p.pid)
    check('F2 delete de x\\Units: va a la papelera', 'FILE-021' in r, r[:200])
    check('F2 ...y el motor que tenia la unidad abierta se para (queda solo el de Otro)',
          len(despues) == 1, (antes, despues))
    check('F3 control: el motor de Otro sigue vivo', len(despues) == 1 and despues[0] in antes, (antes, despues))
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('folder leaves docs 1214')
