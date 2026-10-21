# -*- coding: utf-8 -*-
r"""FILE-011 dice lo que queda cuando una purga no termina (1.21.4). En el NAS (19-oct-2026)
"not empty" no decia que dentro quedaba una entrada que Windows listaba pero no dejaba
abrir (un borrado pendiente, retenido por el handle de un motor). Aqui, en NTFS: un
fichero de la copia abierto por otro proceso no se deja borrar (sharing violation) y la
purga lo nombra.

  Q1  delete de una carpeta con un fichero: a la papelera, con su copia nombrada
  Q2  purge de la copia con el fichero ABIERTO por esta bateria: FILE-011 y
      "Left inside: f.txt"
  Q3  cerrado el fichero, purge: OK y la copia desaparece

Q2 es ROJA contra 1.21.3 (sin "Left inside").

Uso:  python tests/test_purge_queda_1214.py [ruta-a-DelphiLspMcp.exe]
"""
import os, re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('purge-queda')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='pq')

try:
    carpeta = os.path.join(BASE, 'datos')
    os.makedirs(carpeta)
    with open(os.path.join(carpeta, 'f.txt'), 'w') as f:
        f.write('x\n')
    r = srv.call('delphi_delete', {'path': carpeta})
    m = re.search(r'copy: (\S+)', r)
    check('Q1 delete de la carpeta: a la papelera, con su copia nombrada', 'FILE-021' in r and bool(m), r[:300])
    copia = mc.real(m.group(1)) if m else ''
    abierto = open(os.path.join(copia, 'f.txt'), 'r')
    try:
        r = srv.call('delphi_delete', {'path': copia, 'purge': True})
        check('Q2 purge con f.txt abierto por otro proceso: FILE-011 y "Left inside: f.txt"',
              mc.rechazado(r) and mc.es(r, 'SR_FILE_PURGE_FAILED_FMT') and 'Left inside' in r and 'f.txt' in r, r[:400])
    finally:
        abierto.close()
    r = srv.call('delphi_delete', {'path': copia, 'purge': True})
    check('Q3 cerrado el fichero, la purga termina y la copia desaparece',
          not mc.rechazado(r) and not os.path.exists(copia), r[:200])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('purge queda 1214')
