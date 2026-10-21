# -*- coding: utf-8 -*-
"""delphi_upload sobre un fichero de proyecto dice que el build lo juzga (1.21.3).
upload es el canal que escribe un .dproj crudo, a proposito (edit y textedit lo
niegan con EDIT-128), y quien lo juzga es delphi_build, haya llegado como haya
llegado. Hasta la 1.21.2 no decia nada (deep-test de Hermes: "upload lo
bordea"); ahora la respuesta lleva projectNote (UPLOAD-014) para la familia del
proyecto: .dproj, .groupproj, .dpr, .dpk. Un .txt no la lleva.

  U1 upload de un .dproj (sus mismos bytes): projectNote con UPLOAD-014
  U2 upload de un .dpk nuevo: projectNote
  U3 upload de un .dpr (el del proyecto, sus mismos bytes): projectNote
  U4 control: un .txt no lleva projectNote
  U5 y el .dproj resubido sigue compilando (los bytes eran los suyos)

U1-U3 son ROJAS contra 1.21.2 (pasar su exe como argumento).

Uso:  python tests/test_upload_nota_proyecto_1213.py [ruta-a-DelphiLspMcp.exe]
"""
import base64, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('upload-nota-proyecto-1213')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='up-nota', t=600)


def sube(path, datos):
    return srv.call('delphi_upload', {'path': path, 'offset': 0,
                                      'chunkbase64': base64.b64encode(datos).decode()})


def nota(r):
    return mc.es(mc.como_json(r).get('projectNote', ''), 'SN_UPLOAD_FICHERO_DE_PROYECTO')


try:
    carpeta = os.path.join(BASE, 'fixture')
    salida = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
    check('fixture creada', mc.abre(salida, 'SK_CREATE_CREADO_PROYECTO_FMT'), salida[:200])
    proyecto = os.path.join(carpeta, 'Fixture.dproj')
    with open(proyecto, 'rb') as f:
        dproj = f.read()
    r = sube(proyecto, dproj)
    check('U1 upload de un .dproj: projectNote UPLOAD-014 (el build lo juzga)', nota(r), r[:300])
    r = sube(os.path.join(carpeta, 'Paquete.dpk'),
             b'package Paquete;\r\n{$R *.res}\r\nrequires rtl;\r\nend.\r\n')
    check('U2 upload de un .dpk: projectNote', nota(r), r[:300])
    dpr = os.path.join(carpeta, 'Fixture.dpr')
    with open(dpr, 'rb') as f:
        bytes_dpr = f.read()
    # con el fichero ya CERRADO: subirlo con mi handle abierto daba SYS-027
    r = sube(dpr, bytes_dpr)
    check('U3 upload de un .dpr: projectNote', nota(r), r[:300])
    r = sube(os.path.join(carpeta, 'notas.txt'), b'hola\r\n')
    check('U4 control: un .txt no lleva projectNote',
          'written' in mc.como_json(r) and 'projectNote' not in mc.como_json(r), r[:300])
    r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64'}, 600)
    check('U5 el .dproj resubido con sus bytes sigue compilando',
          mc.como_json(r).get('success') is True, mc.como_json(r).get('firstError') or r[:400])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('upload dice que el build juzga un fichero de proyecto 1213')
