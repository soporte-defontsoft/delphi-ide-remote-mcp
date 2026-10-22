# -*- coding: utf-8 -*-
r"""Parametros que se ignoraban en silencio (test completo de Opus de la 1.22.0, 1.22.1): las tools de varios
modos dicen el que no va con lo pedido (Lsp.Guard.ParametroQueNoVa) y estas dos no.

  L1 delphi_list dirs=true con pattern: LIST-015, nada listado (ROJO contra la 1.22.0: listaba y callaba)
  L2 control: dirs=true sin pattern lista las carpetas
  S1 delphi_symbols de una CARPETA con mode=full: LSP-050 (ROJO: el digest, callando)
  S2 ...con filter: LSP-050 (ROJO igual)
  S3 control: la carpeta sola da el digest; un FICHERO con mode=full, su arbol

Y lo que dicen (dirigido de Opus de la 1.22.1 en Hermes, 22-oct-2026: el mensaje decia otra cosa que la tool):
  L3 LIST-015 dice con que modo SI va como se pide (dirs=false), no el valor suelto (ROJO: "goes with: false")
  C1 remove-searchpath de lib en Win64 cuando Win32 tiene lib y Win64 lib2 y libs: CFG-022 nombra el grupo que
     SI la tiene y SOLO ese (ROJO: listaba todos los grupos, el propio Win64 incluido)
  U1 a trozos, el sha256 del ULTIMO TROZO (no del fichero) en el segundo: UPLOAD-011 dice que es el del trozo
     (ROJO: decia que el fichero difiere del origen, y estaba bien)
  U2 el fichero entero con un sha256 que no es: UPLOAD-015 dice cual mando el agente y cual da lo subido
     (ROJO: "received/expected", que se lee al reves)

Uso:  python tests/test_contratos_1221.py [ruta-a-DelphiLspMcp.exe]
"""
import base64, hashlib, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('contratos-1221')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='c1221', t=300)
try:
    d = os.path.join(BASE, 'u')
    os.makedirs(os.path.join(d, 'sub'))
    unit = os.path.join(d, 'UUno.pas')
    open(unit, 'w', newline='\r\n').write('unit UUno;\ninterface\nfunction Uno: Integer;\nimplementation\n'
                                          'function Uno: Integer;\nbegin\n  Result := 1;\nend;\nend.\n')
    r = srv.call('delphi_list', {'root': d, 'dirs': True, 'pattern': '*.pas'})
    check('L1 list dirs=true con pattern: LIST-015 y nada listado',
          mc.abre(r, 'SR_LIST_NO_VA_CON_MODO_FMT') and '"pattern"' in r and '"folders"' not in r, r[:300])
    r = srv.call('delphi_list', {'root': d, 'dirs': True})
    check('L2 control: dirs=true sin pattern lista las carpetas', 'sub' in r and not mc.fallo(r), r[:300])
    for caso, extra in (('S1 ...con mode=full', {'mode': 'full'}), ('S2 ...con filter', {'filter': 'Uno'})):
        args = {'path': d}
        args.update(extra)
        r = srv.call('delphi_symbols', args, 240)
        check('%s: symbols de una carpeta dice LSP-050' % caso,
              mc.abre(r, 'SR_SYMBOLS_NO_VA_CON_CARPETA_FMT') and '"%s"' % list(extra)[0] in r, r[:300])
    r = srv.call('delphi_symbols', {'path': d}, 240)
    check('S3 control: la carpeta sola da el digest', '"units"' in r and 'UUno' in r, r[:300])
    r = srv.call('delphi_symbols', {'path': unit, 'mode': 'full'}, 240)
    check('S3 control: un fichero con mode=full da su arbol', 'Uno' in r and not mc.fallo(r), r[:300])

    r = srv.call('delphi_list', {'root': d, 'dirs': True, 'pattern': '*.pas'})
    check('L3 LIST-015 dice con que modo SI va: dirs=false (no "goes with: false")',
          'goes with: dirs=false.' in r and 'goes with: false' not in r, r[:400])

    carpeta = os.path.join(BASE, 'fixture')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
    check('C0 fixture creada (delphi_create)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    proyecto = os.path.join(carpeta, 'Fixture.dproj')
    for sub in ('lib', 'lib2', 'libs'):
        os.makedirs(os.path.join(carpeta, sub))
    r1 = srv.call('delphi_config', {'project': proyecto, 'command': 'add-searchpath', 'platform': 'Win32',
                                    'path': 'lib'})
    r2 = srv.call('delphi_config', {'project': proyecto, 'command': 'add-searchpath', 'platform': 'Win64',
                                    'paths': ['lib2', 'libs']})
    check('C0 ...lib en Win32; lib2 y libs en Win64', not mc.fallo(r1) and not mc.fallo(r2), (r1[:200], r2[:200]))
    r = srv.call('delphi_config', {'project': proyecto, 'command': 'remove-searchpath', 'platform': 'Win64',
                                   'path': 'lib'})
    check('C1 remove-searchpath de lib en Win64: CFG-022 y el grupo que SI la tiene (Win32)',
          mc.es(r, 'SN_CONFIG_PATH_ABSENT_FMT') and "'$(Base_Win32)'!=''" in r, r[:500])
    check('C1 ...y SOLO ese: ni el de Win64 (lib2, libs), que acaba de decir que no la tiene',
          "'$(Base_Win64)'!=''" not in r and 'lib2' not in r, r[:500])

    sube = os.path.join(BASE, 'subidas')
    os.makedirs(sube)
    trozo1, trozo2 = b'hola', b' mundo'
    r = srv.call('delphi_upload', {'path': os.path.join(sube, 'a.txt'), 'offset': 0,
                                   'chunkbase64': base64.b64encode(trozo1).decode()})
    check('U1 primer trozo sin sha256', not mc.fallo(r), r[:200])
    r = srv.call('delphi_upload', {'path': os.path.join(sube, 'a.txt'), 'offset': len(trozo1),
                                   'chunkbase64': base64.b64encode(trozo2).decode(),
                                   'sha256': hashlib.sha256(trozo2).hexdigest()})
    check('U1 el segundo con el sha256 de SU trozo: UPLOAD-011 y que esa suma es la del trozo (chunkSha256)',
          mc.es(r, 'SR_UPLOAD_SHA_MISMATCH_FMT') and 'is the sum of THIS chunk alone' in r, r[:600])
    bueno = hashlib.sha256(b'otra cosa').hexdigest()
    r = srv.call('delphi_upload', {'path': os.path.join(sube, 'b.txt'), 'offset': 0,
                                   'chunkbase64': base64.b64encode(trozo1).decode(), 'sha256': bueno})
    check('U2 entero con un sha256 que no es: UPLOAD-015 dice el que mando el agente como suyo',
          mc.es(r, 'SR_UPLOAD_SHA_ENTERO_MISMATCH_FMT') and ('your sha256 says %s' % bueno) in r
          and hashlib.sha256(trozo1).hexdigest() in r, r[:500])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('contratos 1221')
