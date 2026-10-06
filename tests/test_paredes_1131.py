# -*- coding: utf-8 -*-
"""Las paredes de Hermes (1.13.1).

Los informes nocturnos de Hermes en la VM 13.2 (5-oct-2026) eran, casi todos,
el mismo golpe: una respuesta que no decia de quien era el arreglo ni que
podia hacer el agente. Esta bateria mide cada uno.

  W1  una raiz en una letra que NO esta conectada en el servidor: la tool que
      la toque recibe WS-022 DENIED de la puerta de cada llamada - nombra la
      raiz con su unidad virtual, dice que la letra no esta conectada y en que
      raices seguir; la letra real no sale. Antes: WS-008 "Directory not found"
      en cada tool, como si fuera un error de nombre
  W2  ...lo mismo dentro de una referencia (ReadOnlyRoots); y (guarda) escribir
      en ella es DENIED - la regla de solo lectura va antes y lo decide ella;
      sigue verde sin la puerta nueva -, nunca un "no encontrado"
  W3  delphi_workspace lista las que no alcanza (unavailableRoots) con su
      motivo: la letra que no esta conectada y la raiz LOCAL cuya carpeta no
      existe; la que esta no sale
  W4  delphi_projects SIN root salta las raices que no estan, lo dice
      (PROJ-005) y lista los proyectos de las demas. Antes: PROJ-003 de la
      primera que faltaba y ningun proyecto
  W5  (guarda) con root que no existe sigue siendo PROJ-003, y una raiz LOCAL
      cuya carpeta no existe no la niega la puerta (una tool que crea podria
      crearla): delphi_list contesta WS-008 como siempre
  W6  git que no se fia del dueno de la carpeta ("dubious ownership": un NAS,
      un recurso de red): GIT-036 lleva la pista GIT-057, que dice que el
      arreglo es del operador. Tambien cuando falla la JAULA del repo, antes
      de la orden: el status despues de un init que vio Hermes. Se reproduce
      con GIT_TEST_ASSUME_DIFFERENT_OWNER=1 y la config de git de la maquina
      aislada (medido el 5-oct-2026 con git 2.53: la respuesta del NAS)
  W7  (guarda) sin esa variable, el mismo status va bien y sin la pista
  W8  delphi_fetch de un fichero de 1,5 MB contesta SOLO el enlace (FETCH-003,
      sin chunkBase64); con maxbytes=1048576, el trozo. Antes, todo en base64
      hasta 4 MB: un zip de 1,37 MB eran 3,6 millones de caracteres
  W9  los textos que no decian la verdad: la nota de las menciones (LSP-015)
      y la descripcion de delphi_references dicen que una cadena SI bloquea el
      rename (RENAME-020); WS-020, delphi_fetch y su maxbytes dicen 1 MB; region
      y window dicen que no se combinan

Usage:  python tests/test_paredes_1131.py [path-to-DelphiLspMcp.exe]
"""
import json, os, re, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('paredes_1131')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
PROY = os.path.join(JAIL, 'Proy')
REPO = os.path.join(JAIL, 'repo')
NUEVO = os.path.join(JAIL, 'nuevo')
LOCAL_NO = os.path.join(BASE, 'no-existe')   # raiz LOCAL cuya carpeta no existe
for d in (EXEDIR, PROY, REPO, NUEVO):
    os.makedirs(d)
EXE = mc.copia_exe(EXEDIR)

LIBRES = mc.letras_libres(2)
if len(LIBRES) < 2:
    raise RuntimeError('esta maquina no tiene dos letras libres: %s' % LIBRES)
FALTA, REF = LIBRES
RAIZ_FALTA = '%s:\\nada' % FALTA
RAIZ_REF = '%s:\\referencia' % REF

with open(os.path.join(PROY, 'Pared.dproj'), 'w') as f:
    f.write('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"/>\n')
MEDIO = os.path.join(JAIL, 'medio.bin')
with open(MEDIO, 'wb') as f:
    f.write(os.urandom(1536 * 1024))  # 1,5 MB: entre el umbral nuevo (1 MB) y el viejo (4 MB)
subprocess.run(['git', 'init', '-q', REPO], check=True, capture_output=True)

TOKEN = 'pared-1131'
with open(os.path.join(EXEDIR, 'settings.ini'), 'w') as f:
    f.write('\n'.join([
        '[Workspace.Pared]', 'Token=%s' % TOKEN,
        'Roots=%s;%s;%s' % (JAIL, RAIZ_FALTA, LOCAL_NO),
        'ReadOnlyRoots=%s' % RAIZ_REF, '']))

# git sin la config global ni la del sistema de esta maquina: una
# safe.directory de quien corre la bateria no cambia lo que se mide
GITCFG = os.path.join(BASE, 'gitconfig-vacio')
open(GITCFG, 'w').close()
GIT_AISLADO = {'GIT_CONFIG_GLOBAL': GITCFG, 'GIT_CONFIG_NOSYSTEM': '1'}

VFALTA = mc.virtual(RAIZ_FALTA)
VREF = mc.virtual(RAIZ_REF)
VJAIL = mc.virtual(JAIL)
VLOCAL_NO = mc.virtual(LOCAL_NO)


def lanza(extra, nombre):
    """Un servidor con este settings.ini, su salida a un FICHERO (por una
    tuberia que nadie lee se quedaba escribiendo su log) y una sesion."""
    puerto = mc.puerto_libre()
    salida = open(os.path.join(BASE, nombre + '.txt'), 'wb')
    env = mc.entorno(dict({'DELPHI_MCP_BIND_IP': '127.0.0.1'}, **extra))
    proc = mc.lanza_http(EXE, puerto, env, stdout=salida, stderr=subprocess.STDOUT)
    cli = mc.Http(puerto, TOKEN, t=120, respaldo_json=True)
    cli.session(nombre)
    return proc, salida, cli


def llama(cli, tool, args):
    return mc.texto(cli.call_msg(tool, args, 120), True)


def fuga(texto, letra):
    """La letra REAL en el texto, con barra detras o sin ella ('x:' dentro de
    'srvx:' no cuenta). Con la barra solamente, la primera pasada no vio la
    letra suelta del motivo, 'drive Z: is not connected'."""
    return bool(re.search(r'(?<![a-z0-9])' + letra.lower() + ':', texto.lower()))


def no_conectada(letra):
    """Como dice el motivo que una letra no esta conectada (su unidad virtual)."""
    return mc.catalogo()['SF_WS_LETRA_NO_CONECTADA_FMT'] % ('srv' + letra.lower())


proc, salida, c = lanza(GIT_AISLADO, 'paredes-normal')
try:
    # ------------------------------------------------------------------ W1
    t = llama(c, 'delphi_list', {'root': VFALTA, 'dirs': True})
    check('W1 una raiz en una letra no conectada: WS-022 DENIED de la puerta, no WS-008',
          mc.abre(t, 'SR_WS_RAIZ_NO_DISPONIBLE_FMT') and mc.resultado(t) == 'DENIED', t[:300])
    check('W1 ...nombra la raiz, dice que la letra no esta conectada y en que raiz seguir',
          VFALTA in t and no_conectada(FALTA) in t and VJAIL in t, t[:400])
    check('W1 ...y la letra real no sale', not fuga(t, FALTA), t[:300])
    t = llama(c, 'delphi_search', {'root': VFALTA + '\\sub', 'query': 'program'})
    check('W1 ...una ruta DENTRO de esa raiz, en otra tool: la misma negativa',
          mc.abre(t, 'SR_WS_RAIZ_NO_DISPONIBLE_FMT'), t[:300])
    t = llama(c, 'delphi_textedit', {'path': VFALTA + '\\x.txt', 'create': True, 'content': 'x\n'})
    check('W1 ...y una que escribe tambien: en una letra que no existe no hay nada que crear',
          mc.abre(t, 'SR_WS_RAIZ_NO_DISPONIBLE_FMT'), t[:300])

    # ------------------------------------------------------------------ W2
    t = llama(c, 'delphi_list', {'root': VREF, 'dirs': True})
    check('W2 una referencia en una letra no conectada: WS-022 al leerla',
          mc.abre(t, 'SR_WS_RAIZ_NO_DISPONIBLE_FMT') and VREF in t and not fuga(t, REF), t[:300])
    t = llama(c, 'delphi_textedit', {'path': VREF + '\\x.txt', 'create': True, 'content': 'x\n'})
    check('W2 (guarda) ...y escribir en ella es DENIED (la referencia no se escribe), nunca un "no encontrado"',
          mc.resultado(t) == 'DENIED' and not mc.es(t, 'SR_WS_DIR_NOT_FOUND_FMT'), t[:300])

    # ------------------------------------------------------------------ W3
    r = c.call_msg('delphi_workspace', {}, 120)
    sc = ((r or {}).get('result') or {}).get('structuredContent') or {}
    nd = {u.get('root'): u.get('reason', '') for u in sc.get('unavailableRoots') or []}
    check('W3 delphi_workspace lista la raiz y la referencia de las letras no conectadas, con su motivo',
          nd.get(VFALTA) == no_conectada(FALTA) and nd.get(VREF) == no_conectada(REF),
          json.dumps(sc)[:700])
    check('W3 ...y la raiz LOCAL cuya carpeta no existe',
          nd.get(VLOCAL_NO) == mc.catalogo()['SF_WS_CARPETA_RAIZ_NO_EXISTE'], json.dumps(nd)[:400])
    check('W3 ...la que esta no sale, y la nota lo explica (WS-023)',
          VJAIL not in nd and len(nd) == 3
          and mc.es(sc.get('unavailableRootsNote', ''), 'SN_WS_RAICES_NO_DISPONIBLES'),
          json.dumps(sc)[:700])
    check('W3 ...sin la letra real de ninguna', not fuga(json.dumps(sc), FALTA) and not fuga(json.dumps(sc), REF),
          json.dumps(nd)[:400])

    # ------------------------------------------------------------------ W4
    t = llama(c, 'delphi_projects', {})
    js = mc.como_json(t)
    nombres = [os.path.splitext(p.get('name', ''))[0] for p in mc.ficheros(js, 'projects')]
    check('W4 delphi_projects sin root lista los proyectos de la raiz que esta (antes: PROJ-003 y ninguno)',
          'Pared' in nombres and not mc.fallo(t), t[:400])
    nota = js.get('skippedRootsNote', '')
    check('W4 ...y dice cuales salto (PROJ-005): las dos letras y la carpeta local',
          mc.es(nota, 'SN_PROJECTS_RAICES_SALTADAS_FMT') and VFALTA in nota and VREF in nota
          and VLOCAL_NO in nota, nota[:400])

    # ------------------------------------------------------------------ W5
    t = llama(c, 'delphi_projects', {'root': os.path.join(JAIL, 'no-hay')})
    check('W5 (guarda) con root que no existe sigue siendo PROJ-003',
          mc.abre(t, 'SR_PROJECTS_NO_ROOT_FMT'), t[:300])
    t = llama(c, 'delphi_list', {'root': VLOCAL_NO, 'dirs': True})
    check('W5 (guarda) una raiz LOCAL cuya carpeta no existe no la niega la puerta: WS-008 de la tool',
          mc.abre(t, 'SR_WS_DIR_NOT_FOUND_FMT'), t[:300])

    # ------------------------------------------------------------------ W7
    t = llama(c, 'delphi_git', {'command': 'status', 'repo': REPO})
    check('W7 (guarda) sin la variable, el status de ese repo va bien y sin la pista GIT-057',
          t.startswith('exit=0') and not mc.es(t, 'SN_GIT_PISTA_PROPIEDAD_DUDOSA'), t[:300])

    # ------------------------------------------------------------------ W8
    t = llama(c, 'delphi_fetch', {'path': MEDIO})
    js = mc.como_json(t)
    check('W8 delphi_fetch de 1,5 MB: SOLO el enlace, sin chunkBase64, con FETCH-003',
          'chunkBase64' not in js and js.get('bytes') == 0 and js.get('inline') is False
          and js.get('download', '').startswith('/files?path=srv')
          and mc.es(js.get('note', ''), 'SN_FETCH_BIG_FMT'), t[:300])
    check('W8 ...y una respuesta corta', len(t) < 4000, len(t))
    t = llama(c, 'delphi_fetch', {'path': MEDIO, 'maxbytes': 1048576})
    js = mc.como_json(t)
    check('W8 ...con maxbytes=1048576, el trozo en linea (los clientes sin shell)',
          'chunkBase64' in js and js.get('bytes') == 1048576, t[:200])

    # ------------------------------------------------------------------ W9
    m = c.request('tools/list')
    tools = {x['name']: x for x in ((m or {}).get('result') or {}).get('tools', [])}

    def desc(n):
        return tools.get(n, {}).get('description', '')

    def prop(n, p):
        props = (tools.get(n, {}).get('inputSchema') or {}).get('properties') or {}
        return props.get(p, {}).get('description', '')

    cat = mc.catalogo()
    check('W9 la nota de las menciones (LSP-015) dice que una cadena SI bloquea el rename (RENAME-020)',
          'RENAME-020' in cat['SN_REFS_MENTIONS_FMT'] and 'do not block' not in cat['SN_REFS_MENTIONS_FMT'],
          cat['SN_REFS_MENTIONS_FMT'][:300])
    check('W9 ...y la descripcion de delphi_references (decia "listed but harmless")',
          'RENAME-020' in desc('delphi_references') and 'listed but harmless' not in desc('delphi_references'),
          desc('delphi_references')[:400])
    fetch = desc('delphi_fetch') + ' | ' + prop('delphi_fetch', 'maxbytes') + ' | ' + cat['SN_WS_DOWNLOAD_WITH_FETCH']
    check('W9 WS-020, delphi_fetch y su maxbytes dicen el umbral de 1 MB, y ninguno los 4 MB de antes',
          'over 1 MB' in desc('delphi_fetch') and 'above 1 MB' in prop('delphi_fetch', 'maxbytes')
          and '1 MB' in cat['SN_WS_DOWNLOAD_WITH_FETCH'] and '4 MB' not in fetch, fetch[:600])
    # del tools/list VIVO, no de las constantes del catalogo; y solo
    # delphi_desktop tiene region y window (revision del 6-oct-2026)
    check('W9 region y window de delphi_desktop dicen que no se combinan',
          'Not with window' in prop('delphi_desktop', 'region')
          and 'Not with region' in prop('delphi_desktop', 'window'),
          prop('delphi_desktop', 'region')[-200:] + ' | ' + prop('delphi_desktop', 'window')[-120:])
finally:
    proc.kill()
proc.wait(10)
salida.close()

# ---------------------------------------------------------------------- W6
proc, salida, c = lanza(dict(GIT_AISLADO, GIT_TEST_ASSUME_DIFFERENT_OWNER='1'), 'paredes-dueno')
try:
    t = llama(c, 'delphi_git', {'command': 'status', 'repo': REPO})
    check('W6 un repo de otra cuenta: GIT-036 con la respuesta de git y la pista GIT-057 (en la JAULA del repo)',
          mc.abre(t, 'SR_GIT_EXIT_FMT') and 'dubious ownership' in t
          and mc.es(t, 'SN_GIT_PISTA_PROPIEDAD_DUDOSA'), t[:500])
    t1 = llama(c, 'delphi_git', {'command': 'init', 'repo': NUEVO})
    t2 = llama(c, 'delphi_git', {'command': 'status', 'repo': NUEVO})
    check('W6 ...el camino de Hermes: init va bien y el status de despues lleva la pista',
          t1.startswith('exit=0') and mc.es(t2, 'SN_GIT_PISTA_PROPIEDAD_DUDOSA'),
          '%s | %s' % (t1[:200], t2[:300]))
finally:
    proc.kill()
proc.wait(10)
salida.close()

mc.fin('paredes 1.13.1 battery')
