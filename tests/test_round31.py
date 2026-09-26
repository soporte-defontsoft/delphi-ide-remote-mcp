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
import mcp_cliente as mc
from mcp_cliente import check

REPO = mc.REPO
BASE = mc.carpeta('round31')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(EXEDIR)

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
PORT = mc.puerto_libre()

open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R26]',
    'Token=%s' % TOK,
    'Roots=%s;%s' % (REPO, JAIL),
    '',
]))

proc = mc.lanza_http(EXE, PORT, mc.entorno())
# sin texto, el mensaje entero en JSON: es lo que ensena el detalle de un FAIL
cli = mc.Http(PORT, TOK, t=180, respaldo_json=True)
cli.session('r26')
call = cli.call

try:
    # ------------------------------------------------------------ R1 / R1b
    # Se localizan las apariciones reales con delphi_search en vez de fijar
    # numeros de linea: el fichero se edita y la bateria no debe envejecer.
    ayuda = os.path.join(REPO, 'src', 'Server', 'Mcp.Tools.Help.pas')
    hits = json.loads(call('delphi_search', {
        'root': ayuda, 'query': 'OneTool', 'wholeword': True}))
    lineas = sorted(h['line0'] for h in hits['hits'])
    check('R1 preparacion: OneTool aparece >=3 veces en Mcp.Tools.Help.pas',
          len(lineas) >= 3, lineas)

    if len(lineas) >= 3:
        # La ULTIMA aparicion es una llamada; la del CUERPO es la que fallaba.
        # El cuerpo es la 2a (declaracion adelantada, cuerpo, llamadas...).
        cuerpo = lineas[1]
        col = hits['hits'][[h['line0'] for h in hits['hits']].index(cuerpo)][
            'character0']
        refs = json.loads(call('delphi_references', {
            'path': ayuda, 'line': cuerpo, 'character': col + 1}))
        confirmadas = sorted(c['line'] for c in refs.get('confirmed', []))
        check('R1 preguntando DESDE EL CUERPO salen las llamadas, no solo '
              'ella misma (%s de %s)' % (len(confirmadas), len(lineas)),
              len(confirmadas) >= 3,
              'confirmed=%s reales=%s' % (confirmadas, lineas))

    # ---------------------------------------------------------------- R1b
    # Los descartes se LISTAN, medido sobre un fixture que TIENE descartes.
    # OneTool no tiene homonimos en Mcp.Tools.Help.pas (rejectedHomonyms 0,
    # rejected []) y "0 >= 0" pasaba sin medir nada (2026-09-26). Aqui, dos
    # units con su propio Saluda y un .dpr que llama a las dos: preguntando
    # desde UUno, los TRES Saluda de UDos (declaracion, cuerpo y llamada) son
    # homonimos, y cada uno tiene que salir LISTADO, diciendo a donde resolvio.
    HOMO = os.path.join(JAIL, 'homo')
    call('delphi_create', {'kind': 'project-console', 'name': 'Homo', 'dir': HOMO})
    UNIDAD = ('unit %s;\r\n\r\ninterface\r\n\r\nprocedure Saluda;\r\n\r\n'
              'implementation\r\n\r\nprocedure Saluda;\r\nbegin\r\n  Writeln(%s);\r\n'
              'end;\r\n\r\nend.\r\n')
    UUNO = os.path.join(HOMO, 'UUno.pas')
    open(UUNO, 'w', newline='').write(UNIDAD % ('UUno', "'uno'"))
    open(os.path.join(HOMO, 'UDos.pas'), 'w', newline='').write(UNIDAD % ('UDos', "'dos'"))
    open(os.path.join(HOMO, 'Homo.dpr'), 'w', newline='').write(
        "program Homo;\r\n\r\n{$APPTYPE CONSOLE}\r\n\r\nuses\r\n  System.SysUtils,\r\n"
        "  UUno in 'UUno.pas',\r\n  UDos in 'UDos.pas';\r\n\r\nbegin\r\n  UUno.Saluda;\r\n"
        "  UDos.Saluda;\r\nend.\r\n")
    _uno = open(UUNO).read().split('\n')
    _decl = [i for i, x in enumerate(_uno) if x.strip() == 'procedure Saluda;'][0]
    hom = mc.como_json(call('delphi_references', {
        'path': UUNO, 'line': _decl, 'character': _uno[_decl].index('Saluda') + 1}))
    rej = hom.get('rejected') if isinstance(hom.get('rejected'), list) else []
    check('R1b los descartes se listan, no solo se cuentan',
          hom.get('rejectedHomonyms') == 3 and len(rej) == 3 and
          all(x.get('resolvedTo', '').lower().endswith('udos.pas') for x in rej) and
          any(x.get('text') == 'UDos.Saluda;' and
              x.get('path', '').lower().endswith('homo.dpr') for x in rej),
          'rejectedHomonyms=%s rejected=%s' % (hom.get('rejectedHomonyms'), [
              (os.path.basename(x.get('path', '')), x.get('line'),
               os.path.basename(x.get('resolvedTo', ''))) for x in rej]))

    # ----------------------------------------------------------------- R2
    r = json.loads(call('delphi_search', {
        'root': JAIL, 'query': 'Roots=', 'pattern': '*.md'}))
    linea = r['hits'][0]['text'] if r.get('hits') else ''
    ruta = r['hits'][0]['path'] if r.get('hits') else ''
    check('R2 el texto del fichero llega VERBATIM (un ancla copiada de aqui '
          'casa con el disco)', linea.strip() == CEBO, repr(linea))
    check('R2b la RUTA si sale enmascarada como unidad virtual',
          ruta.lower().startswith('srv') and ':' in ruta[:6], ruta)

    # ----------------------------------------------------------------- R3
    t = call('delphi_build', {
        'project': os.path.join(REPO, 'CHANGELOG.md'), 'platform': 'Win64'})
    check('R3 build sobre un .md se niega por no ser un proyecto',
          'no es un proyecto' in t.lower(), t[:200])
    # Ojo con buscar 'exec' a secas: el envoltorio "Error executing tool:"
    # lo contiene, y el primer intento de este check dio un falso rojo.
    # R3b/R3c miran la negativa CONCRETA ("no es un proyecto" como error de
    # la tool): lo que no dice NO vale nada si no ha dicho eso.
    check('R3b y NO se inventa una tarea <exec> ni nombra AllowBuildScripts',
          'no es un proyecto' in t.lower() and
          'AllowBuildScripts' not in t and '<exec>' not in t.lower(), t[:200])
    check('R3c la negativa no se disfraza de fallo interno del servidor',
          t.startswith('error:') and 'no es un proyecto' in t.lower(), t[:200])

    # ----------------------------------------------------------------- R4
    t = call('delphi_read', {'path': os.path.join(REPO, 'src')})
    check('R4 delphi_read sobre una CARPETA lo dice',
          'CARPETA' in t and 'delphi_list' in t, t[:200])
    t = call('delphi_read', {
        'path': os.path.join(REPO, 'src', 'Server', 'NoExisteJamas.pas')})
    check('R4b un fichero que falta es "error:", no "RECHAZADO:" (regla 11)',
          t.strip().startswith('error:') and 'RECHAZADO' not in t, t[:200])

    # ----------------------------------------------------------------- R5
    t = call('delphi_list', {
        'root': os.path.join(REPO, 'README.md')})
    check('R5 delphi_list sobre un FICHERO lo dice',
          'FICHERO' in t and 'delphi_read' in t, t[:200])

    # ----------------------------------------------------------------- R6
    r = cli.call_msg('delphi_test', {
        'command': 'run',
        'project': os.path.join(REPO, 'NoExisteEsteProyecto.dproj')})
    sc = r.get('result', {}).get('structuredContent', {})
    check('R6 una negativa dentro de un objeto JSON no dice ok:true',
          sc.get('ok') is False, json.dumps(sc)[:200])
    check('R6b y lleva un code legible por maquina',
          sc.get('code') in ('DENIED', 'NOT_FOUND', 'INVALID_PARAM'),
          json.dumps(sc)[:200])

    # ----------------------------------------------------------------- R7
    t = call('delphi_help', {'command': 'tasks'})
    # la respuesta de VERDAD (la tabla de tasks), y sin el correo ajeno
    check('R7 la respuesta no anuncia el correo de otros agentes',
          t.startswith('QUE USO PARA CADA COSA') and
          'agentes concretos' not in t and 'otro-agente' not in t, t[-200:])
    w = json.loads(call('delphi_workspace', {}))
    check('R7b ese correo se cuenta en delphi_workspace, que es la llamada '
          'de orientacion', w.get('server', {}).get('mailboxes') == 1,
          json.dumps(w.get('server', {}))[:200])

    # ----------------------------------------------------------------- R8
    # Las copias de la papelera no son proyectos que puedas abrir, asi que no
    # se declaran - pero desaparecer en silencio es la misma mentira que todo
    # lo de arriba: apuntar a __delphi-patch contestaba total 0 teniendo un
    # .dproj dentro. delphi_list ya lo hacia bien; el arreglo no habia viajado.
    r = json.loads(call('delphi_projects', {'root': PROY}))
    nombres = [p['project'] for p in r.get('projects', [])]
    check('R8 un barrido normal NO declara la copia de la papelera',
          r.get('total') == 1 and not any('delphi-patch' in n for n in nombres),
          json.dumps(r)[:240])
    check('R8b ...pero dice cuantas ha escondido, en vez de tragarselas',
          r.get('hidden') == 1 and 'hiddenNote' in r, json.dumps(r)[:240])
    r = json.loads(call('delphi_projects', {
        'root': os.path.join(PROY, '__delphi-patch')}))
    check('R8c y si NOMBRAS la papelera como raiz, te la ensena (misma regla '
          'que delphi_list)', r.get('total') == 1, json.dumps(r)[:240])
finally:
    try:
        proc.kill()
    except Exception:
        pass

mc.fin('test_round31')
