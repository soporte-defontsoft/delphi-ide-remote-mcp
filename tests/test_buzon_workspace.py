# -*- coding: utf-8 -*-
"""Bateria de la 1.18.0 (8.5): el buzon de cada workspace.

David, 10-oct-2026: "la misma estructura actual pero separada por workspace",
"el workspace lo detectamos nosotros". reports\\<workspace>\\<agente>\\ y
messages\\<workspace>\\<agente>\\, con la carpeta del workspace por el TOKEN de
la sesion (BuzonDeInformes / BuzonDeMensajes, Lsp.Casa), nunca por un
parametro; y delphi_report command=list|read, la via de operador: los
informes del propio workspace, sin moverlos ni borrarlos.

  W1  un informe cae en reports\\<workspace>\\<agente>\\ (el del token)
  W2  dos workspaces cuyo nombre da el mismo slug ('Hermes VM', 'Hermes-VM')
      no comparten carpeta
  W3  list: los del propio workspace por carpeta de agente, el mas nuevo
      primero; nada de otro
  W4  read: uno entero, por las dos formas del nombre, y se queda donde estaba
  W5  read de un informe de OTRO workspace: REPORT-008, nada leido
  W6  read con nombres que no son de un informe del buzon (.., absoluto,
      settings.ini, dos carpetas): REPORT-008, nada leido
  W7  una carpeta de agente que es una union a una victima de fuera: list no
      la ensena y read la niega
  W8  el correo de un workspace no lo ve ni lo consume otro (check, read y la
      linea PENDING)
  W9  el token de LECTURA del workspace lista y lee lo suyo
  W10 command desconocido REPORT-006, read sin name REPORT-007, report sin
      message REPORT-002 (message ya no es "required" en el esquema)
  W11 la carpeta de un agente del formato de ANTES con el nombre de un
      workspace (reports\\uno\\, de todos los tokens) no es el buzon de 'Uno':
      list no la ensena y read no la lee (revisor de version de la 1.18.0)

Usage:  python tests/test_buzon_workspace.py [path-to-DelphiLspMcp.exe]
"""
import glob, os, time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('buzon-workspace')
EXE = mc.copia_exe(BASE)
RAIZ1, RAIZ2, RAIZ3 = (os.path.join(BASE, n) for n in ('raiz-uno', 'raiz-vm', 'raiz-vm2'))
for _r in (RAIZ1, RAIZ2, RAIZ3):
    os.makedirs(_r)
WS1, WS2, WS3 = 'Uno', 'Hermes VM', 'Hermes-VM'
T1, T1RO, T2, T3 = 'buzon-uno', 'buzon-uno-ro', 'buzon-vm', 'buzon-vm2'
with open(os.path.join(BASE, 'settings.ini'), 'w') as _f:
    _f.write('[Workspace.%s]\nToken=%s\nReadOnlyToken=%s\nRoots=%s\n\n' % (WS1, T1, T1RO, RAIZ1))
    _f.write('[Workspace.%s]\nToken=%s\nRoots=%s\n\n' % (WS2, T2, RAIZ2))
    _f.write('[Workspace.%s]\nToken=%s\nRoots=%s\n' % (WS3, T3, RAIZ3))
REPORTS = os.path.join(BASE, 'reports')
MESSAGES = os.path.join(BASE, 'messages')
VICTIMA = mc.carpeta('buzon-workspace-victima')
SECRETO = '20260101-000000-bug-secreto.md'
open(os.path.join(VICTIMA, SECRETO), 'w', encoding='utf-8').write('# x\n\nSECRETO-DE-FUERA\n')
# W11: un informe del formato de antes (reports\<agente>\) de un agente 'uno'
VIEJO = '20260101-000000-bug-viejo.md'
os.makedirs(os.path.join(REPORTS, 'uno'))
open(os.path.join(REPORTS, 'uno', VIEJO), 'w', encoding='utf-8').write('# x\n\nVIEJO-DE-OTRO-TOKEN\n')

PORT = mc.puerto_libre()
proc = mc.lanza_http(EXE, PORT, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'}))


def cliente(token, agente):
    c = mc.Http(PORT, token)
    assert c.session(agente), (token, agente)
    return c


def md(carpeta):
    return sorted(glob.glob(os.path.join(carpeta, '*.md')))


def informe(c, mensaje, titulo, agente='', kind='bug'):
    a = {'message': mensaje, 'title': titulo, 'kind': kind}
    if agente:
        a['agent'] = agente
    return c.call('delphi_report', a)


union = mc.buzon(REPORTS, 'victima', WS1)
try:
    c1, c2, c3 = cliente(T1, 'hermes'), cliente(T2, 'hermes'), cliente(T3, 'hermes')

    # W1
    r = informe(c1, 'informe de uno', 'de uno', 'hermes')
    B1 = mc.buzon(REPORTS, 'hermes', WS1)
    check('W1 el informe cae en reports\\<workspace>\\<agente> (el workspace, el del token)',
          mc.abre(r, 'SN_REPORT_OK_FMT') and len(md(B1)) == 1
          and B1.lower().endswith('\\workspace.uno\\hermes')
          and not os.path.exists(os.path.join(REPORTS, 'hermes')), (r[:150], B1, os.listdir(REPORTS)))

    # W2
    r2 = informe(c2, 'informe de vm', 'de vm', 'hermes')
    r3 = informe(c3, 'informe de vm2', 'de vm2', 'hermes')
    B2, B3 = mc.buzon(REPORTS, 'hermes', WS2), mc.buzon(REPORTS, 'hermes', WS3)
    check('W2 "Hermes VM" y "Hermes-VM" (el mismo slug) no comparten carpeta',
          mc.abre(r2, 'SN_REPORT_OK_FMT') and mc.abre(r3, 'SN_REPORT_OK_FMT')
          and B2.lower() != B3.lower() and len(md(B2)) == 1 and len(md(B3)) == 1
          and mc.carpeta_de_workspace(WS3) == 'Workspace.hermes-vm', (os.listdir(REPORTS), md(B2), md(B3)))

    # W3
    informe(c1, 'sin agente', 'raiz', kind='question')
    informe(c1, 'de codex', 'otro', 'codex', 'suggestion')
    time.sleep(1.1)  # otro segundo: el nombre empieza por la hora
    informe(c1, 'el mas nuevo', 'nuevo', 'hermes')
    r = c1.call('delphi_report', {'command': 'list'})
    j = mc.como_json(r)
    ents = mc.ficheros(j) if j else []
    dirs = sorted({os.path.dirname(e['path']) for e in ents})
    de_hermes = [e for e in ents if os.path.dirname(e['path']) == '.\\hermes']
    check('W3 list: los 4 del propio workspace por carpeta de agente, el mas nuevo primero, nada de otro',
          j.get('total') == 4 and dirs == ['.', '.\\codex', '.\\hermes']
          and len(de_hermes) == 2 and 'nuevo' in de_hermes[0]['name']
          and not any('vm' in e['name'] for e in ents), r[:600])

    # W4
    nuevo = de_hermes[0]['path'] if de_hermes else '?'
    r = c1.call('delphi_report', {'command': 'read', 'name': nuevo})
    r_b = c1.call('delphi_report', {'command': 'read', 'name': nuevo[2:].replace('\\', '/')})
    check('W4 read: el informe entero, por ".\\hermes\\x" y por "hermes/x", y se queda donde estaba',
          mc.abre(r, 'SN_REPORT_LEIDO_FMT') and 'el mas nuevo' in r and 'Server version' in r
          and mc.abre(r_b, 'SN_REPORT_LEIDO_FMT') and 'el mas nuevo' in r_b
          and len(md(B1)) == 2, (r[:300], r_b[:200]))

    # W5
    ajeno = 'hermes\\' + os.path.basename(md(B2)[0]) if md(B2) else 'hermes\\?'
    r = c1.call('delphi_report', {'command': 'read', 'name': ajeno})
    check('W5 read de un informe de OTRO workspace: REPORT-008 y nada leido',
          mc.rechazado(r) and mc.es(r, 'SR_REPORT_NO_ESTA_FMT') and 'informe de vm' not in r, r[:300])

    # W6
    de_vm = md(B2)[0] if md(B2) else os.path.join(B2, '20260101-000000-bug-x.md')
    malos = ['..\\..\\settings.ini', 'settings.ini',
             'hermes\\..\\..\\' + mc.carpeta_de_workspace(WS2) + '\\hermes\\' + os.path.basename(de_vm),
             de_vm, '..\\' + mc.carpeta_de_workspace(WS2) + '\\hermes\\' + os.path.basename(de_vm),
             'hermes\\sub\\' + (os.path.basename(md(B1)[0]) if md(B1) else 'x.md')]
    malas = []
    for n in malos:
        r = c1.call('delphi_report', {'command': 'read', 'name': n})
        # ni el contenido (un informe ajeno, settings.ini) ni, para un nombre
        # relativo, donde vive la casa; el absoluto sale en el eco de lo que
        # tecleo el agente, enmascarado como todo
        if not (mc.es(r, 'SR_REPORT_NO_ESTA_FMT') and 'informe de' not in r and 'Token=' not in r
                and (os.path.isabs(n) or 'delphi-mcp-tests' not in r)):
            malas.append((n, r[:200]))
    check('W6 read con nombres que no son de un informe del buzon: REPORT-008 los %d, nada leido' % len(malos),
          not malas, malas)

    # W7
    check('W7 la union de una carpeta de agente se planta', mc.junction(union, VICTIMA), union)
    r = c1.call('delphi_report', {'command': 'list'})
    rr = c1.call('delphi_report', {'command': 'read', 'name': 'victima\\' + SECRETO})
    check('W7 una carpeta de agente que es una union hacia fuera: list no la ensena, read la niega',
          'secreto' not in r and mc.como_json(r).get('total') == 4
          and mc.es(rr, 'SR_REPORT_NO_ESTA_FMT') and 'SECRETO-DE-FUERA' not in rr, (r[:300], rr[:200]))

    # W8
    M1, M2 = mc.buzon(MESSAGES, 'alice', WS1), mc.buzon(MESSAGES, 'alice', WS2)
    for carpeta, que in ((M1, 'uno'), (M2, 'vm')):
        os.makedirs(carpeta)
        open(os.path.join(carpeta, '20261010-0900-para-%s.md' % que), 'w',
             encoding='utf-8').write('# PARA-%s\n\nsolo para %s\n' % (que.upper(), que))
    a1, a2, a3 = cliente(T1, 'alice'), cliente(T2, 'alice'), cliente(T3, 'alice')
    chk = a1.call('delphi_messages', {'command': 'check'})
    # la linea PENDING sale del filtro de resultados: con el workspace de la
    # peticion (el de VM, con correo, la ve) y solo con el suyo (el de VM2 no)
    pend2 = a2.call('delphi_help', {})
    pend3 = a3.call('delphi_help', {})
    lee1 = a1.call('delphi_messages', {'command': 'read'})
    check('W8 el correo de un workspace no lo ve ni lo consume otro (check, read, PENDING)',
          'para-uno' in chk and 'para-vm' not in chk
          and mc.tiene(pend2, 'MSGS-001') and not mc.tiene(pend3, 'MSGS-001')
          and 'PARA-UNO' in lee1 and 'PARA-VM' not in lee1
          and not md(M1) and len(md(M2)) == 1, (chk[:200], pend2[-200:], pend3[-200:], lee1[:200]))

    # W9
    ro = cliente(T1RO, 'hermes')
    r = ro.call('delphi_report', {'command': 'list'})
    rr = ro.call('delphi_report', {'command': 'read', 'name': nuevo})
    check('W9 el token de LECTURA del workspace lista y lee lo suyo',
          mc.como_json(r).get('total') == 4 and 'el mas nuevo' in rr, (r[:200], rr[:200]))

    # W10
    e1 = c1.call('delphi_report', {'command': 'borra'})
    e2 = c1.call('delphi_report', {'command': 'read'})
    e3 = c1.call('delphi_report', {'title': 'sin mensaje'})
    check('W10 command desconocido REPORT-006, read sin name REPORT-007, report sin message REPORT-002',
          mc.es(e1, 'SR_REPORT_COMMAND') and mc.es(e2, 'SR_REPORT_READ_SIN_NAME')
          and mc.es(e3, 'SR_REPORT_EMPTY'), (e1[:120], e2[:120], e3[:120]))

    # W11
    r = c1.call('delphi_report', {'command': 'list'})
    rr = c1.call('delphi_report', {'command': 'read', 'name': VIEJO})
    check('W11 la carpeta vieja reports\\uno\\ (de todos los tokens) no es el buzon del workspace Uno',
          'viejo' not in r and mc.es(rr, 'SR_REPORT_NO_ESTA_FMT') and 'VIEJO-DE-OTRO' not in rr,
          (r[:300], rr[:200]))
finally:
    mc.borra(union)  # la union como union: lo de detras no se toca
    proc.kill()
check('W7 la victima de fuera sigue intacta', os.path.exists(os.path.join(VICTIMA, SECRETO)))
mc.borra(VICTIMA)

mc.fin('buzon-workspace battery')
