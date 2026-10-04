"""The engine's own DUnitX suite (src/LspUnitTests), run THROUGH the server.

The Python batteries are black-box: a non-Delphi client talks to the exe as
shipped. This is the step below: unit tests of the engine's units (the
encoding detector and its inverses, the designer binary shape and the RTL
round trip, the .dproj hazard scan) written in DUnitX, born through
`delphi_create kind=project-test` (24-sep-2026) and executed here by
`delphi_test run`, so the suite is part of the regression and the tool that
runs tests is measured on a real suite every release. Since 1.11.0 that run
is the LOGIC part of the suite (delphi_test's container sees nothing but the
test's own folder), and the whole suite is run directly by the battery.

Usage:  python tests/test_engine_dunitx.py [path-to-DelphiLspMcp.exe]
"""
import json, os, re, subprocess
import mcp_cliente as mc
from mcp_cliente import check

REPO = mc.REPO
SRCDIR = os.path.join(REPO, 'src')
SUITE = os.path.join(SRCDIR, 'UnitTests', 'LspUnitTests.dproj')
BASE = mc.carpeta('engine-dunitx')
EXE = mc.copia_exe(BASE)

# The jail is the whole repo, like the real workspace: the suite lives in src/
# and the engine units it links include files from sibling folders (the
# node key .inc under src/DesktopNode), which a src-only jail refuses -
# measured the day this battery was born. AllowTests comes from the
# environment, the way a workspace would declare it in settings.ini.
env = mc.entorno({'DELPHI_MCP_ROOTS': REPO, 'DELPHI_MCP_ALLOW_TESTS': '1'})
srv = mc.Stdio(EXE, env, nombre='eng', t=900)  # compilar la suite: hasta 900 s
call = srv.call
def J(t):
    try: return json.loads(t)
    except Exception: return {}

check('la suite existe en src/', os.path.isfile(SUITE), SUITE)
j = J(call('delphi_test', {'command': 'discover', 'path': SUITE}))
names = [p.get('project', '') for p in j.get('projects', [])]
check('discover la reconoce como DUnitX', any('LspUnitTests' in n for n in names) and
      all(p.get('framework') == 'DUnitX' for p in j.get('projects', []) if 'LspUnitTests' in p.get('project', '')), str(j)[:300])

# Since 1.11.0 delphi_test runs a test in a Windows container of its own, on
# a copy of its output folder: it sees nothing else (Lsp.Sandbox). Part of
# this suite is not pure logic and cannot run in there - measured 2-oct-2026:
# LspTests.Foto and LspTests.Motor build their fixtures next to the exe and
# ask the jail about them, which only worked because the exe sat inside the
# roots of whoever launched it, and Motor starts the real DelphiLSP engine.
# So the suite is measured twice: the LOGIC part through delphi_test (the tool
# on a real DUnitX suite, every release), and the WHOLE suite run directly by
# this battery - the harness, not the product - with the roots it needs.
# What is NOT in PURAS runs only in the whole suite: Foto and Motor (measured
# above), and GitArgs, which has not been measured inside the container yet.
PURAS = ('LspTests.Pascal,LspTests.Encodings,LspTests.Dproj,LspTests.DesignerBin,'
         'LspTests.Mensajes,LspTests.Rutas,LspTests.Images,LspTests.Docs,'
         'LspTests.Log,LspTests.LetrasDeRed,LspTests.DesignerMetaGen')
# el plazo del EJECUTABLE, dicho: sin el son los 120 s por defecto del servidor, y la suite crece
raw = call('delphi_test', {'command': 'run', 'project': SUITE, 'platform': 'Win64',
                           'filter': PURAS, 'timeoutms': 300000}, t=900)
j = J(raw)
if not j:
    print('RESPUESTA CRUDA:', raw[:1200])
check('run: compila y corre', j.get('result') in ('pass', 'fail'), str(j)[:500])
check('run: la parte de logica pasa en su contenedor (0 fallos, sandboxed)',
      j.get('result') == 'pass' and j.get('failed') == 0 and j.get('sandboxed') is True, str(j)[:600])
check('run: veredicto por numeros, no por exit code', j.get('verdictFrom') == 'counts', str(j)[:200])
check('run: exitCode 0', j.get('exitCode') == 0, str(j)[:200])
if j.get('failures'):
    print('FALLOS:', json.dumps(j.get('failures'), ensure_ascii=False)[:1500])
# Si ni siquiera se lanzo dentro de la jaula, el error ya esta contado:
# no lanzar luego el binario directamente (TEST-026/0xC0000142, 3-oct-2026).
if j.get('result') not in ('pass', 'fail'):
    srv.cierra()
    mc.borra(BASE)
    mc.fin('engine-dunitx battery')
EN_CONTENEDOR = j.get('total') or 0

# la suite ENTERA, lanzada directamente: el ejecutable que acaba de compilar
# delphi_test - el que dice su "binary", no una ruta escrita aqui: con otra
# configuracion o salida se corria uno viejo -, en su carpeta, con las raices
# que sus pruebas de la jaula usan
EXE_SUITE = mc.real(j.get('binary') or '')
check('run: dice que binario compilo y corrio, y existe', os.path.isfile(EXE_SUITE), str(j.get('binary')))
r = subprocess.run([EXE_SUITE], cwd=os.path.dirname(EXE_SUITE), capture_output=True, timeout=300,
                   env=mc.entorno({'DELPHI_MCP_ROOTS': REPO}))
salida = (r.stdout + r.stderr).decode('utf-8', 'replace')


def cuenta(nombre):
    m = re.search(r'Tests %s\s*:\s*(\d+)' % nombre, salida)
    return int(m.group(1)) if m else -1


j = {'total': cuenta('Found'), 'passed': cuenta('Passed'), 'failed': cuenta('Failed'),
     'errored': cuenta('Errored')}
check('suite entera: corre y cuenta', j['total'] > 0, salida[-600:])
check('suite entera: 0 fallos', j['failed'] == 0 and j['errored'] == 0, salida[-1500:])
# con suelo: un filtro que dejase de casar con casi todo seguiria "verde" con 1
MIN_LOGICA = 180  # 1.12.1: +1 LaLineaDeUnObjeto (el lector unico de la linea object); medido el 4-oct-2026: +1 lo publicado antes que lo guardado por codigo (segunda revision); +2 de las secciones de delphi_docs (Hermes); el 3-oct: 154 de 208, +6 imports de Dproj; +16 de las tablas del disenador sacadas del fuente (1.12.0, medidas en su contenedor); +6 de su revision (lo que cortaba una unidad, las clases por su identidad, lo guardado por codigo, el lint con una tabla, los ancestros raros, los ayudantes); solo crece, como MIN_TESTS
check('el filtro de delphi_test corrio la parte de logica: %s de %s, al menos %d' % (
      EN_CONTENEDOR, j['total'], MIN_LOGICA),
      0 < EN_CONTENEDOR < j['total'] and EN_CONTENEDOR >= MIN_LOGICA,
      'contenedor=%s entera=%s' % (EN_CONTENEDOR, j['total']))
MIN_TESTS = 233  # 1.12.1: +1 LaLineaDeUnObjeto (seis regex de la linea object -> una); 1.12.0: +1 LoPublicadoAntesQueLoGuardado (segunda revision: TListBox aceptaba cualquier propiedad); +2 las secciones de delphi_docs que encontro Hermes (UnaSeccionPorSuTituloComoSeLee, LaQueEnvuelveLaPaginaAcabaEnSuPrimerSubtitulo); +6 de la revision de las tablas del disenador (LoQueCortabaLaUnidad, LasClasesPorSuIdentidad, LoQueSeGuardaPorCodigo, ElLintConUnaTabla, LosAncestrosRaros, LosAyudantesDeUnDefineProperties); -3 la nota de build (se va con las tablas compiladas) y +16 LspTests.DesignerMetaGen; +2 GitArgs de la revision Codex, medido 210/210 en la regresion final del 3-oct; +6 imports de Dproj y +1 nombrador git (3-oct-2026); +3 la nota de las tablas del disenador (la misma build calla, sin build calla, otra build lo dice con las dos; 1.11.2); +2 ClaveDeCarpeta: otras mayusculas fuera de A-Z, la barra final (revision de la 1.11.0); +2 los revisores de la 1.10.0 (la directiva sin cerrar entera, la linea acaba donde cierra su comentario); +8 EL lexico Pascal (Lsp.Pascal: dos barras hasta el final, nada de // en una llave, la cadena no pasa de su linea, // tras una cadena con barras, la cadena de varias lineas, el estado entre lineas, la vista con su largo y sus saltos, cada clase en su sitio) (1.10.0); +9 la revision de la 1.10.0 (una palabra de las etiquetas del indice, el id compuesto y leido igual y sin control, la consulta sin comillas ni signos, las entidades y el meta lejano, un .chm cortado no tumba la lectura; y cuatro UNC del enmascarador: una lista de rutas, pegado a una opcion, doblado dos veces, el extendido y el host raro); +12 la ayuda instalada (la lista del IDE, el .chm por dentro, un nombre corto por ayuda) y lo puro de delphi_docs (juego de caracteres, mapa, puntos, pagina a texto, una seccion, la que no esta, la que redirige, el id de un enlace, el de una pagina, el padre por su forma) (1.10.0); +28 las letras de red de los sitios declarados (cual se conecta, desde que mapeo, a que se entra, que se avisa, el plazo y el reintento), la barra final de una raiz que es la unidad entera, la purga con corte de una raiz en red y el barrido de unidades tras un salto de linea de JSON (1.9.0); +19 la forma declarada de lo que contesta y de lo que escribe git en una letra de red (1.8.2); +5 colgado es en vuelo, callado y quieto; quien espera una notificacion lo esta usando; el motor sin uso se para; el colgado se relanza; el que no contesta UNA peticion no esta colgado (1.8.0); +2 retirar otra vez no acorta la espera de shutdown, y un escritor atascado no cuelga la parada (1.7.11); +3 parar un motor ocupado no lo tumba, el que no contesta se para igual y se apunta, y el que acabo mal se apunta (1.7.10); +1 los sin uso y los que se fueron se cierran (1.7.9); +1 el preguntado ilegible no se calla el 30-sep (1.7.8); +11 el motor parado, el lanzamiento, la fabrica, la cache de configuracion y la carpeta que se va el 29-sep (1.7.7); +1 ZonaDelCambio (decima); 14 encodings + 8 designer + 5 dproj on 24-sep-2026; +14 images/frame/capture-out/deletion on 25-sep; git args, mensajes, pascal, foto hasta el 27-sep; +3 buzon del log y +5 nombradores el 28-sep; +3 troceador/ConSalto/motor el 28-sep (novena); only grows
# el total en la linea del check: subir MIN_TESTS sin adivinarlo
check('suite entera: al menos %d tests, todos pasados (hay %s)' % (MIN_TESTS, j.get('total')),
      j.get('total', 0) >= MIN_TESTS and j.get('passed') == j.get('total'), str(j)[:300])
check('suite entera: exitCode 0', r.returncode == 0, salida[-300:])

srv.cierra()  # salida limpia: suelta el exe y la carpeta se puede borrar
mc.borra(BASE)
mc.fin('engine-dunitx battery')
