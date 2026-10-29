# -*- coding: utf-8 -*-
"""Revisor del paisaje del 29-oct, lote 2 (V199, V200, V202, V209, V210, V212 de la 1.23.1).

  Y1 delphi_messages read con un mensaje que no se deja leer (bloqueado) entre dos: los otros dos se
     entregan y se borran, el bloqueado se dice (MSGS-007) y se queda (V200; ROJA contra d1dbe99: la
     respuesta era un error y el primero ya estaba borrado sin entregar)
  Y2 insert=rutina-global visible=true en una unit con "Implementation" (mayuscula): la declaracion
     entra en el interface y el cuerpo se queda (V202; ROJA: la segunda escritura caia y se deshacia)
  Y3 lo mismo con "implementation // nota" (V202; ROJA)
  Y4 delphi_projects con un .dproj en __history: la nota PROJ-004 dice tambien del vault (V209; ROJA)
  Y5 delphi_references: la definicion trae character0, el de su declaracion (V210; ROJA)
  Y6 delphi_diagnostics, delphi_symbols, delphi_references y delphi_rename_symbol aceptan un .inc y un
     .dpk como fuente (lo que ahora dicen sus "path": el juez es SOURCE_EXTS; V212; control)
  Y7 con el token de SOLO LECTURA, delphi_help command=tool name=delphi_edit dice que no es para esta
     sesion (HELP-010) en vez de describirla; delphi_read si se describe (V199; ROJA)

Uso:  python tests/test_paisaje_p2_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import ctypes
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('paisaje_p2_1231')
EXE = mc.copia_exe(BASE, src=exe_src)
MSG = mc.buzon(os.path.join(BASE, 'messages'))
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)

BUZ = os.path.join(MSG, 'p2-battery')
os.makedirs(BUZ)
for n, t in (('1-a.md', 'contenido A'), ('2-b.md', 'contenido B'), ('3-c.md', 'contenido C')):
    open(os.path.join(BUZ, n), 'w', encoding='utf-8').write('# %s\n\n%s\n' % (n, t))

k32 = ctypes.WinDLL('kernel32', use_last_error=True)
k32.CreateFileW.restype = ctypes.c_void_p
k32.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p,
                            ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
k32.CloseHandle.argtypes = [ctypes.c_void_p]

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='p2-battery', t=300)
call = srv.call
try:
    # Y1: el 2 abierto sin compartir (GENERIC_READ, share 0): nadie mas lo lee
    h = k32.CreateFileW(os.path.join(BUZ, '2-b.md'), 0x80000000, 0, None, 3, 0x80, None)
    try:
        r = call('delphi_messages', {'command': 'read'})
    finally:
        k32.CloseHandle(h)
    check('Y1 read con uno bloqueado: entrega A y C, dice el B (MSGS-007) y lo deja',
          'contenido A' in r and 'contenido C' in r and mc.es(r, 'SN_MESSAGES_ILEGIBLE_FMT')
          and not os.path.exists(os.path.join(BUZ, '1-a.md')) and os.path.exists(os.path.join(BUZ, '2-b.md')),
          (r[:400], os.listdir(BUZ)))

    for etiqueta, linea in (('Y2', 'Implementation'), ('Y3', 'implementation // nota')):
        pas = os.path.join(JAIL, 'U%s.pas' % etiqueta)
        open(pas, 'w', newline='').write('unit U%s;\r\n\r\ninterface\r\n\r\n%s\r\n\r\nend.\r\n' % (etiqueta, linea))
        r = call('delphi_edit', {'path': pas, 'insert': 'rutina-global', 'visible': True,
                                 'code': 'procedure Nueva;\nbegin\nend;'})
        x = open(pas, encoding='utf-8-sig').read()
        check('%s insert visible con "%s": la declaracion en el interface y el cuerpo' % (etiqueta, linea),
              x.count('procedure Nueva;') == 2 and x.index('procedure Nueva;') < x.index(linea), (r[:300], x))

    hist = os.path.join(JAIL, 'pr', '__history')
    os.makedirs(hist)
    open(os.path.join(hist, 'Viejo.dproj'), 'w').write('<Project/>\n')
    r = call('delphi_projects', {'root': os.path.join(JAIL, 'pr')})
    check('Y4 projects: PROJ-004 nombra tambien el vault y como leerlo',
          mc.es(r, 'SN_PROJECTS_HIDDEN_FMT') and 'vault' in r, r[:400])

    # dentro de un proyecto: el motor no resuelve una unidad suelta
    prj = os.path.join(JAIL, 'prj')
    call('delphi_create', {'kind': 'project-console', 'name': 'Pr', 'dir': prj})
    call('delphi_create', {'kind': 'unit', 'name': 'URef', 'project': os.path.join(prj, 'Pr.dpr'),
                           'content': 'unit URef;\r\n\r\ninterface\r\n\r\nconst\r\n  Tope = 3;\r\n\r\n'
                                      'implementation\r\n\r\nprocedure Usa;\r\nvar\r\n  N: Integer;\r\nbegin\r\n'
                                      '  N := Tope;\r\nend;\r\n\r\nend.\r\n'})
    ref = os.path.join(prj, 'URef.pas')
    call('delphi_hover', {'path': ref, 'line': 13, 'character': 8}, 300)
    j = mc.como_json(call('delphi_references', {'path': ref, 'line': 13, 'character': 8}, 300))
    d = j.get('definition') or {}
    check('Y5 references: la definicion trae character0 (Tope en la columna 2 de la linea 5)',
          d.get('line0') == 5 and d.get('character0') == 2, d)

    inc = os.path.join(JAIL, 'Def.inc')
    open(inc, 'w', newline='').write('{$DEFINE X}\r\n')
    dpk = os.path.join(JAIL, 'Pk.dpk')
    open(dpk, 'w', newline='').write('package Pk;\r\n\r\nrequires\r\n  rtl;\r\n\r\nend.\r\n')
    for f in (inc, dpk):
        nombre = os.path.basename(f)
        for tool, args in (('delphi_diagnostics', {'path': f}), ('delphi_symbols', {'path': f}),
                           ('delphi_references', {'path': f, 'line': 0, 'character': 1}),
                           ('delphi_rename_symbol', {'path': f, 'line': 0, 'character': 1, 'newname': 'Otro'})):
            r = call(tool, args, 300)
            check('Y6 %s acepta %s como fuente (no LSP-NOT_SOURCE)' % (tool, nombre),
                  not mc.es(r, 'SR_LSP_NOT_SOURCE_FMT'), r[:200])
finally:
    srv.cierra()

# Y7, por HTTP: la credencial de solo lectura
SRV2 = os.path.join(BASE, 'srv2')
EXE2 = mc.copia_exe(SRV2, src=exe_src)
PUERTO = mc.puerto_libre()
RW, RO = 'p2-rw-0123456789abcdef', 'p2-ro-0123456789abcdef'
open(os.path.join(SRV2, 'settings.ini'), 'w').write(
    '[Server]\nPort=%d\nBindIP=127.0.0.1\n\n[Workspace.P2]\nToken=%s\nReadOnlyToken=%s\nRoots=%s\n' % (PUERTO, RW, RO, JAIL))
proc = mc.lanza_http(EXE2, None, mc.entorno(), espera_en=PUERTO)
try:
    cli = mc.Http(PUERTO, RO)
    cli.session('lector')
    r = cli.call('delphi_help', {'command': 'tool', 'name': 'delphi_edit'})
    check('Y7 solo lectura: help de delphi_edit dice que no es para esta sesion (HELP-010), sin describirla',
          mc.es(r, 'SR_HELP_TOOL_NO_DISPONIBLE_FMT') and '"parameters"' not in r, r[:300])
    r = cli.call('delphi_help', {'command': 'tool', 'name': 'delphi_read'})
    check('Y7 control: delphi_read se describe entera', '"parameters"' in r, r[:200])
finally:
    proc.kill()

mc.borra(BASE)
mc.fin('revisor del paisaje, lote 2 1231 (V199, V200, V202, V209, V210, V212)')
