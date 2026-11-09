# -*- coding: utf-8 -*-
"""Las operaciones largas en curso: lo que dicen a las demas llamadas (R3 de A22, 1.29.1).

Medido el 7-nov-2026 (opencode): mientras un delphi_move copy seguia en el servidor, delphi_list de su
destino decia WS-008 "does not exist" y repetir un borrado ya hecho SYS-012 NOT_FOUND; el agente lo
repitio encima. Desde la 1.29.1 una llamada LARGA que escribe (Lsp.EnCurso.OPERACIONES_LARGAS) queda
apuntada mientras dura, con sus rutas, y el registro dice a las demas:

  E1 la MISMA llamada (el mismo agente, los mismos argumentos) mientras sigue: SYS-042, nada se hace
  E2 una escritura de OTRO agente sobre su ruta: SYS-043, nada se hace
  E3 una lectura de su ruta: contesta como siempre y lleva SYS-044
  E3b si esa respuesta es JSON, sigue siendolo: la nota va en su campo inProgressNote (ConNota)
  E4 un test de OTRO agente sobre el mismo proyecto: NO se niega (build y test ya esperan su turno
     solos, EN_LA_FILA_DEL_BUILD); corre en su contenedor y pasa. Hasta el 9-nov se negaba con
     SYS-043 y test_delphi_test_servicio (dos agentes, un proyecto) lo cazo
  E5 una escritura en otro sitio: como siempre, sin nota
  E6 al acabar, el registro se suelta: la escritura de E2 ya pasa y la lectura no lleva nota
  E7 y la llamada larga misma contesta lo de siempre (el test pasa)

La llamada larga: delphi_test de un proyecto DUnitX de la jaula cuyo test espera 15 s (build + run). Por
HTTP, dos agentes (clientInfo agente-a / agente-b) a la vez.

Uso:  python tests/test_en_curso_1291.py [ruta-a-DelphiLspMcp.exe]
"""
import io
import json
import os
import threading
import time
import mcp_cliente as mc
from mcp_cliente import check

TITULO = 'las operaciones largas en curso (1.29.1)'
TOKEN = 'en-curso-1291-0123456789abcdef'
BASE = mc.carpeta('en_curso_1291')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
SRV = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRV)
io.open(os.path.join(SRV, 'settings.ini'), 'w', encoding='utf-8').write(
    '[Workspace.P]\nToken=%s\nRoots=%s\nAllowTests=1\n' % (TOKEN, JAIL))
PROY = os.path.join(JAIL, 'Lento')
DPROJ = os.path.join(PROY, 'Lento.dproj')


def texto_de(m):
    return mc.texto(m) if m else ''


try:
    puerto = mc.puerto_libre()
    proc = mc.lanza_http(EXE, puerto, env=mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'}))
    try:
        cli = mc.Http(puerto, token=TOKEN, t=300)

        def llama(agente, tool, args):
            st, hs, m = cli.moderna('tools/call', {'name': tool, 'arguments': args}, nombre=agente)
            return texto_de(m)

        r = llama('agente-a', 'delphi_create', {'kind': 'project-test', 'name': 'Lento', 'dir': PROY})
        unidad = os.path.join(PROY, 'ULento.pas')
        fuente = io.open(unidad, encoding='utf-8-sig').read()
        fuente = fuente.replace('DUnitX.TestFramework;', 'System.SysUtils, DUnitX.TestFramework;', 1)
        fuente = fuente.replace("  Assert.AreEqual(4, 2 + 2", "  Sleep(15000);\n  Assert.AreEqual(4, 2 + 2", 1)
        io.open(unidad, 'w', encoding='utf-8-sig', newline='\r\n').write(fuente)

        largo = {}
        RUN = {'command': 'run', 'project': DPROJ}
        hilo = threading.Thread(target=lambda: largo.setdefault('r', llama('agente-a', 'delphi_test', RUN)))
        hilo.start()
        time.sleep(3)  # ya paso la puerta y esta apuntada (compila y luego espera 15 s)

        r1 = llama('agente-a', 'delphi_test', RUN)
        check('E1 la misma llamada del mismo agente mientras sigue: SYS-042', mc.es(r1, 'SR_SYS_OPERACION_REPETIDA_FMT'),
              r1[:300])
        antes = io.open(DPROJ, encoding='utf-8-sig').read()
        r2 = llama('agente-b', 'delphi_config', {'command': 'set-version', 'project': DPROJ, 'version': '1.2.3.4'})
        check('E2 una escritura de otro agente sobre su ruta: SYS-043 y nada cambia',
              mc.es(r2, 'SR_SYS_OPERACION_EN_CURSO_FMT') and io.open(DPROJ, encoding='utf-8-sig').read() == antes,
              r2[:300])
        r3 = llama('agente-b', 'delphi_read', {'path': DPROJ, 'toline': 2})
        check('E3 una lectura de su ruta contesta y lleva SYS-044',
              mc.es(r3, 'SN_SYS_OPERACION_EN_CURSO_FMT') and '<Project' in r3, r3[-400:])
        r3b = llama('agente-b', 'delphi_list', {'root': PROY})
        try:
            j3b = json.loads(r3b)
        except ValueError:
            j3b = {}
        check('E3b una respuesta JSON con la nota sigue siendo JSON, con la nota en inProgressNote',
              mc.es(str(j3b.get('inProgressNote', '')), 'SN_SYS_OPERACION_EN_CURSO_FMT') and bool(j3b.get('folders')),
              r3b[-400:])
        # sin compilar, como test_delphi_test_servicio: su build pisaria el .exe que el de agente-a esta
        # ejecutando (eso es cosa del build, F2039), y aqui se mide que el registro no lo niega
        r4 = llama('agente-b', 'delphi_test', dict(RUN, nobuild=True))
        check('E4 un test de otro agente sobre el mismo proyecto no se niega: corre y pasa',
              not mc.es(r4, 'SR_SYS_OPERACION_EN_CURSO_FMT') and not mc.es(r4, 'SR_SYS_OPERACION_REPETIDA_FMT')
              and '"result":"pass"' in r4.replace(' ', ''), r4[:400])
        r5 = llama('agente-b', 'delphi_textedit', {'path': os.path.join(JAIL, 'otro.txt'), 'create': True,
                                                   'content': 'hola'})
        check('E5 una escritura en otro sitio: como siempre, sin nota',
              os.path.isfile(os.path.join(JAIL, 'otro.txt')) and not mc.es(r5, 'SN_SYS_OPERACION_EN_CURSO_FMT')
              and not mc.es(r5, 'SR_SYS_OPERACION_EN_CURSO_FMT'), r5[:300])

        hilo.join(240)
        r7 = largo.get('r', '')
        check('E7 la llamada larga contesta lo de siempre (el test pasa)', '"result":"pass"' in r7.replace(' ', ''),
              r7[:400])
        r6a = llama('agente-b', 'delphi_config', {'command': 'set-version', 'project': DPROJ, 'version': '1.2.3.4'})
        r6b = llama('agente-b', 'delphi_read', {'path': DPROJ, 'toline': 2})
        check('E6 al acabar se suelta: la escritura pasa y la lectura no lleva nota',
              not mc.es(r6a, 'SR_SYS_OPERACION_EN_CURSO_FMT') and not mc.es(r6b, 'SN_SYS_OPERACION_EN_CURSO_FMT'),
              (r6a[:200], r6b[-200:]))
    finally:
        proc.kill()
finally:
    mc.borra(BASE)
mc.fin(TITULO)
