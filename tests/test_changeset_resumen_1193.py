# -*- coding: utf-8 -*-
"""El resumen del preview de un changeset con operaciones sin resolver (CHSET-024)
culpaba siempre al ANCLA: "anchor NOT FOUND or AMBIGUOUS ... stage it again
correctly (with atline ...)". Hermes (informe 1938b sobre la 1.19.2, 15-oct): un
delete de un .pas se niega en el preview - a proposito: borrar y volver a crear el
mismo fichero en el lote es un plan valido, y al apilar no se ve lo que viene
despues - y su entrada nombra delphi_delete, pero el resumen le recetaba anclas y
atline. Lo mismo con los de delete-line (una linea que no existe, que no es la
nombrada). Ahora el resumen dice que cada entrada da su causa, y las nombra.

  K1 delete de un .pas: la entrada nombra delphi_delete y el resumen remite a la causa
     de cada entrada, sin culpar al ancla (ROJO en produccion)
  K2 delete-line con atline fuera del fichero: lo mismo (ROJO)
  C1 control: un edit con un ancla que no esta sigue sin resolver y el resumen sigue
     diciendo como apilarla bien (unstage, atline)

Uso:  python tests/test_changeset_resumen_1193.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('changeset_resumen_1193')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
UNIDAD = os.path.join(JAIL, 'UBorra1193.pas')
TEXTO = os.path.join(JAIL, 'notas.txt')
open(UNIDAD, 'wb').write(b'unit UBorra1193;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n')
open(TEXTO, 'wb').write(b'uno\r\ndos\r\n')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='changeset-resumen', t=120)

NUEVO = 'each one says why'
# (revisor de baterias, 18-oct-2026) el resumen de CHSET-024 es hoy un texto
# FIJO: lo que mide cada caso es la causa en el "anchor" de SU entrada (medido
# el 18-oct: "line 9 does not exist (notas.txt has 2)", "NOT FOUND"). El texto
# viejo ya no esta en el catalogo: su "not in" pasaba siempre


def ancla(r):
    ops = (mc.como_json(r) or {}).get('operations') or []
    return ops[0].get('anchor', '') if ops else ''


def cs(**kw):
    return s.call('delphi_changeset', kw, t=120)


def abre():
    r = cs(command='begin')
    return mc.como_json(r).get('id') or r.split('CHANGESET ')[1].split(' ')[0]


try:
    cid = abre()
    cs(command='stage', id=cid, kind='delete', path=UNIDAD)
    r = cs(command='preview', id=cid)
    check('K1 delete de un .pas: la entrada nombra delphi_delete y el resumen remite a la causa de cada entrada',
          mc.es(r, 'SN_CHANGESET_PREVIEW_BAD') and 'delphi_delete' in ancla(r) and NUEVO in r, r[:900])
    cs(command='rollback', id=cid)

    cid = abre()
    cs(command='stage', id=cid, kind='delete-line', path=TEXTO, atline=9)
    r = cs(command='preview', id=cid)
    check('K2 delete-line con atline fuera del fichero: el resumen remite a la causa, sin culpar al ancla',
          mc.es(r, 'SN_CHANGESET_PREVIEW_BAD') and NUEVO in r and 'line 9 does not exist' in ancla(r)
          and 'NOT FOUND' not in ancla(r), r[:900])
    cs(command='rollback', id=cid)

    cid = abre()
    cs(command='stage', id=cid, kind='edit', path=TEXTO, old='no esta', new='x')
    r = cs(command='preview', id=cid)
    check('C1 control: un ancla que no esta sigue sin resolver, y el resumen dice como apilarla bien',
          mc.es(r, 'SN_CHANGESET_PREVIEW_BAD') and 'unstage' in r and 'atline' in r and ancla(r) == 'NOT FOUND', r[:900])
    cs(command='rollback', id=cid)
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('changeset: el resumen del preview remite a la causa de cada entrada 1.19.3 (Hermes 1938b)')
