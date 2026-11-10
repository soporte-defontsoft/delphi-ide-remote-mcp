# -*- coding: utf-8 -*-
"""El latido de una llamada larga: notifications/progress mientras dura (F8 de la 1.29.1).

Medido el 9-nov-2026 (P1 de plan-1-29-1): Claude Code (app y CLI) abandona una llamada tras 300 s sin
noticias y opencode tras 60, y un notifications/progress con el progressToken de la llamada les reinicia la
cuenta. Hasta la 1.29 el servidor no mandaba ninguno. Ahora, una llamada que pidio progreso y sigue en
marcha manda uno cada ProgressSeconds (Lsp.Progreso), por stdio como una linea mas y por HTTP abriendo el
stream de la respuesta (text/event-stream, chunked) cuando hay el primero; la que acaba antes sale como
siempre.

La llamada larga: delphi_db contra 192.0.2.1 (TEST-NET, no existe), que tarda los 12 s del plazo de
conexion y contesta DB-007; con DELPHI_MCP_PROGRESS_SECONDS=2 caben varios latidos. Necesita las DLL de
PostgreSQL de produccion (sin ellas, la bateria termina sin checks y lo dice).

  L1 stdio con progressToken: latidos antes de la respuesta, con SU token, progreso creciente, SYS-040 y
     el nombre de la tool; luego la respuesta (DB-007)
  L2 stdio sin progressToken: ningun latido
  L3 stdio, una llamada rapida con token: ningun latido
  L4 stdio con ProgressSeconds=0: ningun latido
  H1 HTTP moderno aceptando un stream: text/event-stream en trozos, latidos con su token y la respuesta como
     ultimo evento
  H2 HTTP moderno aceptando solo JSON: la respuesta JSON de siempre, sin latidos
  H3 HTTP con sesion (SSE): latidos y la respuesta en el mismo stream
  H4 HTTP moderno, una llamada rapida con token: application/json como antes (no se abre el stream)
  H5 un cliente que se va a mitad del stream: el servidor sigue contestando a la siguiente
  R1 (A22) ...y la respuesta que no le llego queda en SU buzon (messages\\<workspace>\\<agente>), una vez
  R2 ...la siguiente respuesta de ese agente avisa de que hay correo (MESSAGES_PENDING)
  R3 ...y delphi_messages la entrega: SYS-041, la tool y su respuesta tal como habria llegado
  R4 las llamadas cuyo cliente se quedo (H1, H3) no dejan nada en el buzon
  C1 (A22, medido con Hermes el 9-nov: corta a los 300 s, manda notifications/cancelled con el id y NO
     cuelga) un cliente con stream manda su cancelled por otra peticion y sigue leyendo: su respuesta le
     llega igual Y queda en su buzon, una vez (hasta esto se perdia: el latido seguia llegando)
  C2 ...lo mismo con un cliente de JSON a secas (sin latido)
  C3 un cancelled con un id que no esta en vuelo no deja nada
  C4 cancelled y luego cuelga: en el buzon UNA vez (el procesador la dejo; el transporte, que tampoco puede
     escribirla, no la deja otra vez)
  C5 (medido con Hermes en la VM el 10-nov) con otro mensaje ya esperando, la respuesta que se deja en el
     buzon no lleva la nota PENDING MESSAGES: quien la lee la recibe con el otro, y la cuenta ya no es
     verdad. En prosa (la negativa de la base), la linea de detras
  C6 ...y en JSON (un delphi_test cortado, como el de Hermes), el campo mailbox

Uso:  python tests/test_progreso_1291.py [ruta-a-DelphiLspMcp.exe]
"""
import http.client
import io
import json
import os
import shutil
import mcp_cliente as mc
from mcp_cliente import check

PROD_LIB = r'C:\Delphi-mcp-Server\drivers\PG\lib'
TITULO = 'el latido de una llamada larga (1.29.1)'
if not os.path.isfile(os.path.join(PROD_LIB, 'libpq.dll')):
    print('NOTA: sin %s no hay llamada larga inofensiva: no se mide nada' % PROD_LIB)
    mc.fin(TITULO, sin_checks='sin las DLL de PostgreSQL de produccion en esta maquina')
    raise SystemExit(0)

BASE = mc.carpeta('progreso_1291')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
SRV = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRV)
shutil.copytree(PROD_LIB, os.path.join(SRV, 'drivers', 'PG', 'lib'))
d = os.path.join(SRV, 'connections', 'databases')
os.makedirs(d)
io.open(os.path.join(d, 'db-connections.json'), 'w', encoding='utf-8').write(json.dumps(
    {'db-connections': {'projects': {'p': {'databases': {'pg': {
        'server': '192.0.2.1', 'database': 'inventada', 'user': 'nadie', 'password': 'x1',
        'engine': 'PG', 'provider': 'FIREDAC', 'access': 'read'}}}}}}))
LARGA = {'name': 'delphi_db', 'arguments': {'command': 'tables', 'db': 'p/pg'}}
RAPIDA = {'name': 'delphi_workspace', 'arguments': {}}


TOKEN = 'progreso-1291-0123456789abcdef'


def entorno(segundos='2'):
    return mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_DB_PROJECTS': 'p', 'DELPHI_MCP_TOKEN': TOKEN,
                       'DELPHI_MCP_PROGRESS_SECONDS': segundos})


def negativa_de_siempre(t):
    """La de una base que no contesta: DB-007 (el plazo del servidor) o DB-009 (el de libpq, que vence antes)."""
    return mc.es(t, 'SR_DB_NO_RESPONDE_FMT') or mc.es(t, 'SR_DB_NO_ABRE_FMT')


def con_token(params, token):
    p = json.loads(json.dumps(params))
    if token is not None:
        p.setdefault('_meta', {})['progressToken'] = token
    return p


def por_stdio(srv, rid, params, t=60):
    """Manda un tools/call y recoge, en orden, lo que llega hasta su respuesta: (latidos, respuesta)."""
    srv.send({'jsonrpc': '2.0', 'id': rid, 'method': 'tools/call', 'params': params})
    latidos, resp = [], None
    import time
    hasta = time.time() + t
    while time.time() < hasta and resp is None:
        try:
            linea = srv.q.get(timeout=1)
        except Exception:
            continue
        try:
            m = json.loads(linea)
        except Exception:
            continue
        if m.get('method') == 'notifications/progress':
            latidos.append(m)
        elif m.get('id') == rid:
            resp = m
    return latidos, resp


def bien_formados(latidos, token):
    """Todos con SU token, progreso estrictamente creciente, SYS-040 y el nombre de la tool."""
    prog = [l['params'].get('progress') for l in latidos]
    return (all(l['params'].get('progressToken') == token for l in latidos)
            and all(isinstance(p, (int, float)) for p in prog)
            and all(b > a for a, b in zip(prog, prog[1:]))
            and all(mc.es(l['params'].get('message', ''), 'SN_SYS_SIGUE_EN_MARCHA_FMT')
                    and 'delphi_db' in l['params'].get('message', '') for l in latidos))


def texto_de(resp):
    return mc.texto(resp) if resp else ''


try:
    # ---- stdio
    srv = mc.Stdio(EXE, entorno(), nombre='progreso', t=90)
    try:
        lat, resp = por_stdio(srv, 901, con_token(LARGA, 'tok-s'))
        check('L1 stdio con token: latidos (>= 3) antes de la respuesta', len(lat) >= 3 and resp is not None,
              (len(lat), str(resp)[:200]))
        check('L1 ...con su token, progreso creciente, SYS-040 y el nombre de la tool', lat and bien_formados(lat, 'tok-s'),
              [l['params'] for l in lat][:3])
        check('L1 ...y la respuesta es la de siempre (DB-007 o DB-009)', negativa_de_siempre(texto_de(resp)),
              texto_de(resp)[:300])
        lat, resp = por_stdio(srv, 902, LARGA)
        check('L2 stdio sin progressToken: ningun latido', not lat and resp is not None, (len(lat), str(resp)[:200]))
        lat, resp = por_stdio(srv, 903, con_token(RAPIDA, 7))
        check('L3 stdio, una llamada rapida con token: ningun latido', not lat and resp is not None,
              (len(lat), str(resp)[:200]))
    finally:
        srv.cierra()
    srv = mc.Stdio(EXE, entorno('0'), nombre='progreso', t=90)
    try:
        lat, resp = por_stdio(srv, 904, con_token(LARGA, 'tok-0'))
        check('L4 stdio con ProgressSeconds=0: ningun latido', not lat and resp is not None,
              (len(lat), str(resp)[:200]))
    finally:
        srv.cierra()

    # ---- HTTP: un workspace con su token, como las demas baterias HTTP
    io.open(os.path.join(SRV, 'settings.ini'), 'w', encoding='utf-8').write(
        '[Workspace.P]\nToken=%s\nRoots=%s\nDbAllowedProjects=p\nAllowTests=1\n' % (TOKEN, JAIL))  # C6: un delphi_test
    puerto = mc.puerto_libre()
    proc = mc.lanza_http(EXE, puerto, env=mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1',
                                                    'DELPHI_MCP_PROGRESS_SECONDS': '2'}))
    try:
        cli = mc.Http(puerto, token=TOKEN, t=90)
        url = cli.url
        cab = {'MCP-Protocol-Version': mc.PROTOCOLO_MODERNO, 'Mcp-Method': 'tools/call'}

        def moderna(params, token, accept, rid):
            p = con_token(mc.params_modernos(params, 'progreso'), None)
            if token is not None:
                p['_meta']['progressToken'] = token
            h = dict(cab, **{'Mcp-Name': params['name']})
            return mc.post(url, {'jsonrpc': '2.0', 'id': rid, 'method': 'tools/call', 'params': p}, TOKEN, None,
                           accept, 90, h)

        st, hs, raw = moderna(LARGA, 'tok-h', mc.ACCEPT_STREAMABLE, 911)
        msgs = mc.Http.mensajes(raw)
        lat = [m for m in msgs if m.get('method') == 'notifications/progress']
        fin = [m for m in msgs if m.get('id') == 911]
        check('H1 HTTP moderno con stream: text/event-stream en trozos',
              st == 200 and 'text/event-stream' in (hs.get('Content-Type') or '')
              and (hs.get('Transfer-Encoding') or '').lower() == 'chunked', (st, dict(hs or {})))
        check('H1 ...latidos (>= 3) bien formados y la respuesta como ULTIMO evento',
              len(lat) >= 3 and bien_formados(lat, 'tok-h') and fin and msgs[-1] is fin[0]
              and negativa_de_siempre(texto_de(fin[0])), (len(lat), raw[-300:]))
        st, hs, raw = moderna(LARGA, 'tok-j', 'application/json', 912)
        msgs = mc.Http.mensajes(raw)
        check('H2 HTTP moderno aceptando solo JSON: la respuesta JSON de siempre, sin latidos',
              st == 200 and 'application/json' in (hs.get('Content-Type') or '')
              and not any(m.get('method') == 'notifications/progress' for m in msgs)
              and any(m.get('id') == 912 for m in msgs), (st, raw[:300]))
        st, hs, raw = moderna(RAPIDA, 'tok-r', mc.ACCEPT_STREAMABLE, 913)
        check('H4 HTTP moderno, una llamada rapida con token: application/json como antes',
              st == 200 and 'application/json' in (hs.get('Content-Type') or '') and '"id":913' in raw.replace(' ', ''),
              (st, dict(hs or {}), raw[:200]))
        # H3: con sesion, por la ruta SSE
        cli.session('progreso')
        st, hs, raw = cli.post({'jsonrpc': '2.0', 'id': 914, 'method': 'tools/call', 'params': con_token(LARGA, 'tok-ss')})
        msgs = mc.Http.mensajes(raw)
        lat = [m for m in msgs if m.get('method') == 'notifications/progress']
        check('H3 HTTP con sesion: latidos y la respuesta en el mismo stream',
              st == 200 and len(lat) >= 3 and bien_formados(lat, 'tok-ss') and msgs and msgs[-1].get('id') == 914,
              (st, len(lat), raw[-300:]))
        buzon = os.path.join(SRV, 'messages', 'Workspace.P', 'progreso')

        def en_el_buzon():
            return sorted(f for f in os.listdir(buzon) if f.endswith('.md')) if os.path.isdir(buzon) else []
        check('R4 las llamadas cuyo cliente se quedo no dejan nada en el buzon', not en_el_buzon(), en_el_buzon())
        # H5: el cliente se va tras el primer latido
        c = http.client.HTTPConnection('127.0.0.1', puerto, timeout=60)
        p = mc.params_modernos(LARGA, 'progreso')
        p['_meta']['progressToken'] = 'tok-x'
        c.request('POST', '/mcp', json.dumps({'jsonrpc': '2.0', 'id': 915, 'method': 'tools/call', 'params': p}),
                  dict(cab, **{'Mcp-Name': 'delphi_db', 'Content-Type': 'application/json',
                               'Accept': mc.ACCEPT_STREAMABLE, 'Authorization': 'Bearer ' + TOKEN}))
        r = c.getresponse()
        primero = r.fp.readline()
        c.close()
        st, hs, raw = moderna(RAPIDA, None, mc.ACCEPT_STREAMABLE, 916)
        check('H5 un cliente que se va a mitad del stream: el servidor contesta a la siguiente',
              r.status == 200 and primero and st == 200 and '"id":916' in raw.replace(' ', ''), (r.status, primero, st, raw[:200]))
        # la llamada abandonada acaba sola (los 10-12 s de la base que no contesta)
        import time
        hasta = time.time() + 40
        while time.time() < hasta and not en_el_buzon():
            time.sleep(1)
        time.sleep(1)
        dejados = en_el_buzon()
        check('R1 la respuesta que no llego queda en SU buzon, una vez', len(dejados) == 1 and 'delphi-db' in dejados[0],
              dejados)
        st, hs, raw = moderna(RAPIDA, None, mc.ACCEPT_STREAMABLE, 917)
        check('R2 la siguiente respuesta de ese agente avisa de que hay correo', mc.es(raw, 'SN_MESSAGES_PENDING_FMT'),
              raw[-300:])
        st, hs, raw = moderna({'name': 'delphi_messages', 'arguments': {'command': 'read'}}, None,
                              mc.ACCEPT_STREAMABLE, 918)
        leido = texto_de(next((m for m in mc.Http.mensajes(raw) if m.get('id') == 918), None))
        check('R3 delphi_messages la entrega: SYS-041, la tool y su respuesta tal como habria llegado',
              mc.es(leido, 'SN_SYS_RESPUESTA_PERDIDA_FMT') and 'delphi_db' in leido and negativa_de_siempre(leido)
              and not en_el_buzon(), (leido[:500], en_el_buzon()))

        # ---- C: el cliente que avisa de que deja de esperar (notifications/cancelled), como Hermes
        import threading

        def cancela(rid):
            return mc.post(url, {'jsonrpc': '2.0', 'method': 'notifications/cancelled',
                                 'params': {'requestId': rid, 'reason': 'timed out'}}, TOKEN, None,
                           mc.ACCEPT_STREAMABLE, 30, dict(cab, **{'Mcp-Method': 'notifications/cancelled'}))

        def vacia_el_buzon():
            for f in en_el_buzon():
                os.remove(os.path.join(buzon, f))

        def lee_el_buzon():
            return [io.open(os.path.join(buzon, f), encoding='utf-8-sig').read() for f in en_el_buzon()]

        for etiqueta, rid, token, accept in (('C1 con stream', 921, 'tok-c', mc.ACCEPT_STREAMABLE),
                                             ('C2 JSON a secas', 922, None, 'application/json')):
            vacia_el_buzon()
            res = {}
            hilo = threading.Thread(target=lambda: res.setdefault('r', moderna(LARGA, token, accept, rid)))
            hilo.start()
            time.sleep(4)
            stc, _, _ = cancela(rid)
            hilo.join(60)
            st, hs, raw = res.get('r', (None, None, ''))
            fin = [m for m in mc.Http.mensajes(raw) if m.get('id') == rid]
            time.sleep(1)
            dejados = lee_el_buzon()
            check('%s: el cancelled (202) deja su respuesta en el buzon, una vez, y al cliente le llega igual' % etiqueta,
                  stc == 202 and fin and negativa_de_siempre(texto_de(fin[0])) and len(dejados) == 1
                  and mc.es(dejados[0], 'SN_SYS_RESPUESTA_PERDIDA_FMT') and 'delphi_db' in dejados[0],
                  (stc, raw[-200:], [d[:200] for d in dejados]))
        vacia_el_buzon()
        stc, _, _ = cancela(999)
        time.sleep(1)
        check('C3 un cancelled con un id que no esta en vuelo no deja nada', stc == 202 and not en_el_buzon(),
              (stc, en_el_buzon()))
        # C4: cancelled tras el primer latido, y cuelga
        c = http.client.HTTPConnection('127.0.0.1', puerto, timeout=60)
        p = mc.params_modernos(LARGA, 'progreso')
        p['_meta']['progressToken'] = 'tok-c4'
        c.request('POST', '/mcp', json.dumps({'jsonrpc': '2.0', 'id': 924, 'method': 'tools/call', 'params': p}),
                  dict(cab, **{'Mcp-Name': 'delphi_db', 'Content-Type': 'application/json',
                               'Accept': mc.ACCEPT_STREAMABLE, 'Authorization': 'Bearer ' + TOKEN}))
        r = c.getresponse()
        primero = r.fp.readline()
        stc, _, _ = cancela(924)
        c.close()
        hasta = time.time() + 40
        while time.time() < hasta and not en_el_buzon():
            time.sleep(1)
        time.sleep(3)
        check('C4 cancelled y luego cuelga: en el buzon UNA vez', primero and stc == 202 and len(en_el_buzon()) == 1,
              (primero, stc, en_el_buzon()))
        vacia_el_buzon()

        # C5 y C6: con un mensaje del operador ya esperando en el buzon
        os.makedirs(buzon, exist_ok=True)
        io.open(os.path.join(buzon, '20261110-000000-del-operador.md'), 'w', encoding='utf-8').write('hola\n')

        def cortada(params, rid, espera):
            """Una llamada JSON cancelada a los espera s: (el texto de lo que dejo en el buzon, '' si nada; lo que
            le llego al cliente)."""
            antes = set(en_el_buzon())
            res = {}
            hilo = threading.Thread(target=lambda: res.setdefault('r', moderna(params, None, 'application/json', rid)))
            hilo.start()
            time.sleep(espera)
            cancela(rid)
            hilo.join(240)
            time.sleep(1)
            nuevos = sorted(set(en_el_buzon()) - antes)
            return (io.open(os.path.join(buzon, nuevos[0]), encoding='utf-8-sig').read() if nuevos else '',
                    res.get('r', (None, None, ''))[2])

        dejado, _ = cortada(LARGA, 925, 4)
        check('C5 con otro mensaje esperando, la respuesta (prosa) que se deja en el buzon no lleva PENDING MESSAGES',
              mc.es(dejado, 'SN_SYS_RESPUESTA_PERDIDA_FMT') and negativa_de_siempre(dejado)
              and not mc.es(dejado, 'SN_MESSAGES_PENDING_FMT'),
              dejado[-400:])
        proy = os.path.join(JAIL, 'C6')
        st, hs, raw = moderna({'name': 'delphi_create', 'arguments': {'kind': 'project-test', 'name': 'C6', 'dir': proy}},
                              None, 'application/json', 926)
        # que el test dure 8 s (el esqueleto acaba en menos de 3 con su build): el corte llega con el en marcha
        unidad = os.path.join(proy, 'UC6.pas')
        u = io.open(unidad, encoding='utf-8-sig', newline='').read()
        u = u.replace('  DUnitX.TestFramework;', '  DUnitX.TestFramework, System.SysUtils;', 1).replace(
            '  Assert.AreEqual(', '  Sleep(8000);\r\n  Assert.AreEqual(', 1)
        io.open(unidad, 'w', encoding='utf-8-sig', newline='').write(u)
        dejado, llego = cortada({'name': 'delphi_test', 'arguments': {'command': 'run',
                                                                      'project': os.path.join(proy, 'C6.dproj')}}, 927, 4)
        cuerpo = dejado[dejado.find('{'):] if '{' in dejado else ''
        check('C6 ...y en JSON (un delphi_test cortado): sin el campo mailbox',
              mc.es(dejado, 'SN_SYS_RESPUESTA_PERDIDA_FMT') and '"verdictFrom"' in cuerpo and '"mailbox"' not in dejado
              and not mc.es(dejado, 'SN_MESSAGES_PENDING_FMT'), ('buzon: ' + dejado[-300:], 'cliente: ' + llego[-300:]))
        vacia_el_buzon()
    finally:
        proc.kill()
finally:
    mc.borra(BASE)
mc.fin(TITULO)
