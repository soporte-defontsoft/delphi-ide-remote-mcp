# -*- coding: utf-8 -*-
"""E2E battery for v1.0.4-beta - lo que encontraron tres agentes usando el
servidor como cliente, no testeandolo.

El hilo comun de casi todo: el servidor contestaba "no esta ahi" cuando la
verdad era "no es de ese tipo", y contaba cosas en vez de decirlas.

  R1  delphi_references preguntado DESDE EL CUERPO de una rutina encuentra
      sus llamadas. Una rutina Pascal tiene DOS lineas de definicion
      (declaracion adelantada e implementacion) y solo se aceptaba una: el
      flujo natural (delphi_symbols da la declaracion -> "quien la usa")
      contestaba "nadie" sobre una rutina con llamantes. Respuesta
      EQUIVOCADA, no ausente.
  R1b los descartes se LISTAN, no solo se cuentan (la descripcion de la tool
      promete que nunca se tiran en silencio)
  R2  delphi_search devuelve el texto del fichero VERBATIM - el filtro de
      salida reescribia "D:\\" a "srvd:\\" DENTRO de la linea, asi que un
      ancla copiada de un resultado no casaba nunca - mientras que el campo
      "path" SI sale enmascarado
  R3  delphi_build sobre algo que no es un proyecto se niega por su motivo
      real, sin inventarse una tarea <exec> ni nombrar AllowBuildScripts
  R4  delphi_read sobre una CARPETA lo dice; sobre un fichero que falta usa
      "error:" (corrige y repite), no "RECHAZADO:" (no insistas)
  R5  delphi_list sobre un FICHERO lo dice
  R6  una negativa que viaja dentro de un objeto JSON no dice "ok": true
  R7  la coletilla del buzon no anuncia el correo de OTROS agentes

Usage:  python tests/test_round31.py [path-to-DelphiLspMcp.exe]
"""
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

P = F = 0


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:240])


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round31')
shutil.rmtree(BASE, ignore_errors=True)
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(EXEDIR)
os.makedirs(JAIL)
EXE = os.path.join(EXEDIR, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)

# Fichero con una letra de unidad REAL dentro: es lo que el filtro de salida
# reescribia. Se escribe aqui y no se busca en el README para que la bateria
# no dependa de lo que diga la documentacion ese dia.
CEBO = 'Roots=D:\\Projects\\Galatea;D:\\Projects\\Shared'
open(os.path.join(JAIL, 'cebo.md'), 'w').write(
    'linea uno\n%s\nlinea tres\n' % CEBO)

# Un proyecto con una COPIA de si mismo en la papelera del servidor. La copia
# no es un proyecto que se pueda abrir, asi que no debe declararse - pero
# tampoco debe desaparecer sin decir nada.
PROY = os.path.join(JAIL, 'proy')
# Con la fecha de HOY (v1.0.14): el recorredor purga al pasar las carpetas de
# dia caducadas (>15 dias), y una fija como '20260101' desaparecia -con razon-
# antes de que R8b/R8c pudieran contarla. Lo que se mide aqui es que la
# papelera se ESCONDE y se CUENTA, no cuanto dura.
BASURA = os.path.join(PROY, '__delphi-patch', __import__('time').strftime('%Y%m%d'))
os.makedirs(BASURA)
DPROJ_MIN = ('<?xml version="1.0" encoding="utf-8"?>\n'
             '<Project><PropertyGroup><MainSource>App.dpr</MainSource>'
             '</PropertyGroup></Project>\n')
open(os.path.join(PROY, 'App.dproj'), 'w').write(DPROJ_MIN)
open(os.path.join(BASURA, 'App.dproj'), 'w').write(DPROJ_MIN)

# Correo dirigido a OTRO agente: no es nuestro, no podemos leerlo ni
# limpiarlo, y no tiene por que salir en nuestras respuestas.
BUZON = os.path.join(EXEDIR, 'messages', 'otro-agente')
os.makedirs(BUZON)
open(os.path.join(BUZON, '20260920_000000_algo.md'), 'w').write(
    '# Para otro agente\n\nEsto no es para quien lee.\n')

TOK = 'r26'
sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()

open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R26]',
    'Token=%s' % TOK,
    'Roots=%s;%s' % (REPO, JAIL),
    '',
]))

proc = subprocess.Popen([EXE, '--http', str(PORT)],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(3)
URL = 'http://127.0.0.1:%d/mcp' % PORT
SID = None


def rpc(body, timeout=180):
    h = {'Content-Type': 'application/json',
         'Accept': 'application/json, text/event-stream',
         'Authorization': 'Bearer ' + TOK}
    if SID:
        h['Mcp-Session-Id'] = SID
    r = urllib.request.urlopen(urllib.request.Request(
        URL, data=json.dumps(body).encode(), headers=h, method='POST'),
        timeout=timeout)
    raw = r.read().decode('utf-8', 'replace')
    msgs = []
    for l in raw.splitlines():
        if l.startswith('data:'):
            try:
                msgs.append(json.loads(l[5:].strip()))
            except Exception:
                pass
    if not msgs:
        try:
            msgs.append(json.loads(raw))
        except Exception:
            pass
    return (msgs[-1] if msgs else None), r.headers.get('Mcp-Session-Id')


_, SID = rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                         "clientInfo": {"name": "r26", "version": "1"}}})
rpc({"jsonrpc": "2.0", "method": "notifications/initialized"})

RID = [100]


def call(tool, args, timeout=180):
    RID[0] += 1
    r, _ = rpc({"jsonrpc": "2.0", "id": RID[0], "method": "tools/call",
                "params": {"name": tool, "arguments": args}}, timeout)
    return r


def texto(r):
    try:
        return r['result']['content'][0]['text']
    except Exception:
        return json.dumps(r)[:400]


try:
    # ------------------------------------------------------------ R1 / R1b
    # Se localizan las apariciones reales con delphi_search en vez de fijar
    # numeros de linea: el fichero se edita y la bateria no debe envejecer.
    ayuda = os.path.join(REPO, 'src', 'Mcp.Tools.Help.pas')
    hits = json.loads(texto(call('delphi_search', {
        'root': ayuda, 'query': 'OneTool', 'wholeword': True})))
    lineas = sorted(h['line0'] for h in hits['hits'])
    check('R1 preparacion: OneTool aparece >=3 veces en Mcp.Tools.Help.pas',
          len(lineas) >= 3, lineas)

    if len(lineas) >= 3:
        # La ULTIMA aparicion es una llamada; la del CUERPO es la que fallaba.
        # El cuerpo es la 2a (declaracion adelantada, cuerpo, llamadas...).
        cuerpo = lineas[1]
        col = hits['hits'][[h['line0'] for h in hits['hits']].index(cuerpo)][
            'character0']
        refs = json.loads(texto(call('delphi_references', {
            'path': ayuda, 'line': cuerpo, 'character': col + 1})))
        confirmadas = sorted(c['line'] for c in refs.get('confirmed', []))
        check('R1 preguntando DESDE EL CUERPO salen las llamadas, no solo '
              'ella misma (%s de %s)' % (len(confirmadas), len(lineas)),
              len(confirmadas) >= 3,
              'confirmed=%s reales=%s' % (confirmadas, lineas))
        check('R1b los descartes se listan, no solo se cuentan',
              len(refs.get('rejected', [])) >= refs.get('rejectedHomonyms', 0),
              'rejectedHomonyms=%s rejected=%s'
              % (refs.get('rejectedHomonyms'), len(refs.get('rejected', []))))

    # ----------------------------------------------------------------- R2
    r = json.loads(texto(call('delphi_search', {
        'root': JAIL, 'query': 'Roots=', 'pattern': '*.md'})))
    linea = r['hits'][0]['text'] if r.get('hits') else ''
    ruta = r['hits'][0]['path'] if r.get('hits') else ''
    check('R2 el texto del fichero llega VERBATIM (un ancla copiada de aqui '
          'casa con el disco)', linea.strip() == CEBO, repr(linea))
    check('R2b la RUTA si sale enmascarada como unidad virtual',
          ruta.lower().startswith('srv') and ':' in ruta[:6], ruta)

    # ----------------------------------------------------------------- R3
    t = texto(call('delphi_build', {
        'project': os.path.join(REPO, 'CHANGELOG.md'), 'platform': 'Win64'}))
    check('R3 build sobre un .md se niega por no ser un proyecto',
          'no es un proyecto' in t.lower(), t[:200])
    # Ojo con buscar 'exec' a secas: el envoltorio "Error executing tool:"
    # lo contiene, y el primer intento de este check dio un falso rojo.
    check('R3b y NO se inventa una tarea <exec> ni nombra AllowBuildScripts',
          'AllowBuildScripts' not in t and '<exec>' not in t.lower(), t[:200])
    check('R3c la negativa no se disfraza de fallo interno del servidor',
          not t.startswith('Error executing tool'), t[:200])

    # ----------------------------------------------------------------- R4
    t = texto(call('delphi_read', {'path': os.path.join(REPO, 'src')}))
    check('R4 delphi_read sobre una CARPETA lo dice',
          'CARPETA' in t and 'delphi_list' in t, t[:200])
    t = texto(call('delphi_read', {
        'path': os.path.join(REPO, 'src', 'NoExisteJamas.pas')}))
    check('R4b un fichero que falta es "error:", no "RECHAZADO:" (regla 11)',
          t.strip().startswith('error:') and 'RECHAZADO' not in t, t[:200])

    # ----------------------------------------------------------------- R5
    t = texto(call('delphi_list', {
        'root': os.path.join(REPO, 'README.md')}))
    check('R5 delphi_list sobre un FICHERO lo dice',
          'FICHERO' in t and 'delphi_read' in t, t[:200])

    # ----------------------------------------------------------------- R6
    RID[0] += 1
    r, _ = rpc({"jsonrpc": "2.0", "id": RID[0], "method": "tools/call",
                "params": {"name": "delphi_test", "arguments": {
                    'command': 'run',
                    'project': os.path.join(REPO, 'NoExisteEsteProyecto.dproj')
                }}})
    sc = r.get('result', {}).get('structuredContent', {})
    check('R6 una negativa dentro de un objeto JSON no dice ok:true',
          sc.get('ok') is False, json.dumps(sc)[:200])
    check('R6b y lleva un code legible por maquina',
          sc.get('code') in ('DENIED', 'NOT_FOUND', 'INVALID_PARAM'),
          json.dumps(sc)[:200])

    # ----------------------------------------------------------------- R7
    t = texto(call('delphi_help', {'command': 'tasks'}))
    check('R7 la respuesta no anuncia el correo de otros agentes',
          'agentes concretos' not in t, t[-200:])
    w = json.loads(texto(call('delphi_workspace', {})))
    check('R7b ese correo se cuenta en delphi_workspace, que es la llamada '
          'de orientacion', w.get('server', {}).get('mailboxes') == 1,
          json.dumps(w.get('server', {}))[:200])

    # ----------------------------------------------------------------- R8
    # Las copias de la papelera no son proyectos que puedas abrir, asi que no
    # se declaran - pero desaparecer en silencio es la misma mentira que todo
    # lo de arriba: apuntar a __delphi-patch contestaba total 0 teniendo un
    # .dproj dentro. delphi_list ya lo hacia bien; el arreglo no habia viajado.
    r = json.loads(texto(call('delphi_projects', {'root': PROY})))
    nombres = [p['project'] for p in r.get('projects', [])]
    check('R8 un barrido normal NO declara la copia de la papelera',
          r.get('total') == 1 and not any('delphi-patch' in n for n in nombres),
          json.dumps(r)[:240])
    check('R8b ...pero dice cuantas ha escondido, en vez de tragarselas',
          r.get('hidden') == 1 and 'hiddenNote' in r, json.dumps(r)[:240])
    r = json.loads(texto(call('delphi_projects', {
        'root': os.path.join(PROY, '__delphi-patch')})))
    check('R8c y si NOMBRAS la papelera como raiz, te la ensena (misma regla '
          'que delphi_list)', r.get('total') == 1, json.dumps(r)[:240])
finally:
    try:
        proc.kill()
    except Exception:
        pass

print('== test_round31: %d OK | %d fallos ==' % (P, F))
sys.exit(1 if F else 0)
