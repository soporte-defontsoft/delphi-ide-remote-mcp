"""E2E battery for v1.12.0 - the designer lint over a CORPUS of forms the IDE
wrote and that load: the Samples that come with RAD Studio. Every warning
there is a lie (or a sample that does not load, which is worth knowing).

Why it exists: the 1.12.0 tables are read from the SOURCE of every folder
in the IDE's library paths, third parties included, and a reviewer ported
the lint to Python and ran it over real forms before the tag: 230 warnings
in the Samples and 2.121 in David's forms, none real - enumerations with
the same name in two units (FireDAC and IBX TIBProtocol), what a class
streams by code (DefineProperties: Left/Top of a non-visual, TField.Lookup,
QuickReport FontSize), the root class of a form sharing its name with a
demo's, an unnamed 'object TMemo' whose properties went to its parent.
Unit checks catch each rule; this catches the next one nobody thought of.

Only the Delphi Samples (they are on every machine with RAD Studio; the CPP
folder is C++Builder, and this server is for Delphi only): the warnings
of a family whose real class a package registers without source (the
ListView appearances) are counted apart while that policy is pending.

Usage:  python tests/test_designer_corpus.py [path-to-DelphiLspMcp.exe]
"""
import atexit, glob, json, os, re, shutil, time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer-corpus')
# con los renderizadores: desde la 1.20 el lint pregunta al LECTOR del IDE lo
# que las tablas no juzgan (DSGN-061), y sin ellos cada form que lo necesita
# contestaba DSGN-154 "no se le pudo preguntar" (revisor de baterias,
# 18-oct-2026: el corpus no media al lector desde la 1.20). Y con el conversor:
# es el juez de los StyleLookup de un .fmx (el estilo por defecto de la
# plataforma); sin el, el lint de cada form con uno daba CLEAN sin mirarlo, y
# desde A21 de la 1.29 dice DSGN-199 (8-nov-2026: el corpus no los juzgaba)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True, con_conversor=True)
APPDATA = os.path.join(BASE, 'appdata')
os.makedirs(APPDATA, exist_ok=True)
# por HTTP, para lintar EN PARALELO (mc.en_paralelo): en serie por stdio el
# corpus era la mitad de run_all, 30 de 60 minutos (auditoria de las baterias,
# 18-oct-2026); medido con 96 forms, 8 hilos 3,1 veces mas rapido y las mismas
# respuestas. Una muestra rotatoria no: sus avisos pendientes saldrian rojos o
# verdes segun el dia
TOKEN = 'designer-corpus'
with open(os.path.join(BASE, 'srv', 'settings.ini'), 'w') as f:
    f.write('[Workspace.Corpus]\nToken=%s\nRoots=%s\n' % (TOKEN, BASE))
PORT = mc.puerto_libre()
proc = mc.lanza_http(EXE, PORT, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1', 'LOCALAPPDATA': APPDATA}))
cli = mc.Http(PORT, TOKEN, t=300)
cli.session('dc')
call = cli.call


def para():
    proc.kill()
    proc.wait()


# un servidor HTTP no muere con la bateria (el de stdio si: se le cierra la
# entrada), y uno huerfano tiene cogida la carpeta para la siguiente pasada
# (medido el 18-oct-2026, al reventar un lint por su plazo)
atexit.register(para)


def J(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


version = str(J(call('delphi_workspace', {})).get('activeDelphi') or '')
# los Samples cuelgan del BDSCOMMONDIR que pone el rsvars.bat del IDE (r5-L4: se componia a mano)
SAMPLES = os.path.join(mc.variable_de_rsvars(call, 'BDSCOMMONDIR'), 'Samples')
if not os.path.isdir(SAMPLES):
    # un salto que se dice (sin_checks): salia rojo por 0 checks, sin el motivo (revisor de
    # baterias de la 1.27)
    para()
    mc.borra(BASE)
    mc.fin('designer-corpus battery', sin_checks='no hay Samples de RAD Studio %s en %s' % (version, SAMPLES))

# los forms de TEXTO de los Samples, a la raiz del servidor (los binarios se
# leen al vuelo, pero aqui se mide el lint, no el conversor)
FORMS = os.path.join(BASE, 'forms')
copiados = []
con_pas = 0
for d, dirs, fs in os.walk(SAMPLES):
    # la carpeta CPP es de C++Builder: este MCP es solo de Delphi (David,
    # 18-oct-2026), y sus forms no los escribio el IDE de Delphi
    dirs[:] = [x for x in dirs if x.lower() not in ('__history', '__recovery', 'win32', 'win64') and
               not (d == SAMPLES and x.lower() == 'cpp')]
    for f in fs:
        if f.lower().endswith(('.dfm', '.fmx')):
            src = os.path.join(d, f)
            with open(src, 'rb') as h:
                if h.read(3) == b'TPF':
                    continue
            dst = os.path.join(FORMS, os.path.relpath(src, SAMPLES))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
            copiados.append(dst)
            # ...con su .pas: sin el no corria el form contra su clase
            # (check-binding) ni se encontraba el maestro de una vista FMX, que
            # declara la vista con su R *.<Vista>.fmx (18-oct-2026: un Sample
            # con TLabel sin campo "no cargaba" y nadie lo habia medido aqui)
            pas = os.path.splitext(src)[0] + '.pas'
            if os.path.isfile(pas):
                shutil.copyfile(pas, os.path.splitext(dst)[0] + '.pas')
                con_pas += 1
# (sin los .dpr: con ellos el servidor trae los ancestros de otras carpetas, y medido el
# 4-nov-2026 con las vueltas de entonces costaba 437 -> 765 s. Desde la 1.27 trae la cadena
# entera de una vez (sin tope de tres vueltas): con las carpetas enteras de esos 52 forms y sus
# proyectos, quedan 2 sin ancestro (13 con la 1.26), los dos sin un proyecto que liste su
# unidad; sonda A/B del 4-nov. Aqui siguen a su NOTA, abajo, por su motivo)
check('corpus: los forms de texto de los Samples (%d)' % len(copiados), len(copiados) > 100, str(len(copiados)))
check('corpus: con su .pas los que lo tienen (%d)' % con_pas, con_pas > 100, con_pas)

# que las dos tablas esten (se generan en segundo plano; info espera un rato):
# la espera de la casa, mc.espera_info (este bucle era su gemelo)
a = mc.espera_info(call, {'command': 'info', 'classname': 'TButton', 'framework': 'vcl', 'filter': 'Caption'},
                   cond=lambda r: 'Caption' in r, tope=300)
b = mc.espera_info(call, {'command': 'info', 'classname': 'TButton', 'framework': 'fmx', 'filter': 'Text'},
                   cond=lambda r: '"Text"' in r, tope=300)
listo = 'Caption' in a and '"Text"' in b
check('corpus: las tablas VCL y FMX del Delphi activo estan', listo, (a + ' | ' + b)[:300])

# (revisor de baterias, 18-oct-2026) un lint que no contesta (un error, un
# timeout) no dejaba ninguna linea "line N:" y contaba como limpio; y el
# parser del IDE (DSGN-123, juez desde el 8-oct) no tiene esa forma de linea:
# los dos cuentan. Y el LECTOR del IDE (DSGN-061 de la 1.20) habla cuando las
# tablas callan: lo que dice de un form del IDE es un aviso falso como otro,
# con linea o sin ella (SF_DSGN_LECTOR_SIN_LINEA_FMT); y si no se le pudo
# preguntar (DSGN-154) se cuenta por su motivo, nunca por falta de
# renderizador (este arnes los pone)
LINEA_N = re.compile(r'\s*line (\d+): (.*?)\s+->\s+(.*)$')
# la propiedad que no esta en la familia de la clase (la politica pendiente), por su formato:
# ' nor in any class that descends from it, ...'
FAMILIA = mc.trozo_de_formato('SF_DSGN_NO_EXISTE_EN_LA_FAMILIA_FMT', 2)
# los avisos VERDADEROS, medidos: un Sample que de verdad falla (el form, y lo
# que tiene que decir su aviso). Si uno deja de salir, se quita de aqui.
#  - FireDAC InterBase Admin (2015): un TStringGrid y ninguna unidad del
#    proyecto usa FMX.Grid.Style. Compilado tal cual, el exe no lleva TStyledGrid
#    (0) y con la unidad si (31): FMX pinta su aviso en lugar del grid (V69 de
#    la 1.23.1, medido el 27-oct-2026)
VERDADEROS = {os.path.join('Object Pascal', 'Database', 'FireDAC', 'Samples', 'DBMS Specific', 'InterBase',
                           'Admin', 'AdminUtility.fmx'): 'FMX.Grid.Style'}
vistos_verdaderos = set()
falsos, familia, notas, ejemplos, sin_lint = 0, 0, 0, [], []
sin_lector, sin_render, contesto, sin_conversor, lookups_sin_estilo = {}, [], {}, [], []
# el motivo de DSGN-154 va detras de su cabecera: o el lector CONTESTO y lo que salto no se
# puede cargar a este fichero (un fragmento SF_DSGN_LECTOR_*, sin id: el ancestro que falta,
# la raiz que no ve, una excepcion del codigo de un componente, una clase del proyecto), o no
# se le pudo preguntar, con el id de su fallo. Se buscaba 'could not be asked: [', que el
# mensaje no escribe asi: todo caia en 'sin id' (revisor de baterias de la 1.27)
CABEZA = mc.trozo_de_formato('SN_DESIGNER_LINT_SIN_LECTOR_FMT', 1)
CONTESTO = {n: re.compile(mc.patron_de_formato(n, '.*?'), re.S)
            for n in ('SF_DSGN_LECTOR_SIN_ANCESTRO_FMT', 'SF_DSGN_LECTOR_RAIZ_NO_VISTA_FMT',
                      'SF_DSGN_LECTOR_DEL_CODIGO_FMT', 'SF_DSGN_LECTOR_CLASE_DEL_PROYECTO_FMT')}
# t=300: un lint puede preguntar al lector mas de una vez, y el lector tiene 75
# s (RENDER_TIEMPO_MS; 8 forms de los Samples los agotan, RENDER-007)
# y lo que los renderizadores dejan ver en el escritorio mientras tanto: NADA
# (ventanas en la barra, cuadros modales, el foco; 18/19-oct-2026: lo vio David)
vigilante = mc.VigilanteDeEscritorio().arranca()
respuestas = mc.en_paralelo(PORT, TOKEN, 'delphi_designer',
                            [{'command': 'lint', 'path': dst} for dst in copiados], t=300, nombre='dc')
vigilante.para()
check('corpus: ningun renderizador puso una ventana en la barra ni abrio un cuadro de dialogo',
      vigilante.ventanas == 0 and vigilante.cuadros == 0, vigilante.resumen())
check('corpus: ningun renderizador robo el foco', vigilante.foco == 0, vigilante.resumen())
for dst, r in zip(copiados, respuestas):
    rel = os.path.relpath(dst, FORMS)
    if not any(mc.abre(r, c) for c in ('SN_DESIGNER_LINT_OK_FMT', 'SN_DESIGNER_LINT_BAD_FMT',
                                        'SN_DESIGNER_LINT_NOTAS_FMT', 'SN_DESIGNER_LINT_SIN_LECTOR_FMT',
                                        'SN_DESIGNER_LITERAL_QUE_PREVIEW_NIEGA_FMT',
                                        'SN_DESIGNER_LOOKUPS_SIN_DEFECTO_FMT',
                                        'SN_DESIGNER_LOOKUPS_SIN_ESTILO_FMT',
                                        'SN_DESIGNER_LOOKUPS_FUERA_DE_STYLES_FMT')):
        sin_lint.append('%s: %s' % (rel, r[:100]))
    # contesta, pero sin su juez: el arnes pone el conversor, asi que es un fallo
    if mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_DEFECTO_FMT'):
        sin_conversor.append('%s: %s' % (rel, r[:300]))
    # con su juez, la nota de los que ningun estilo que el form ve define
    # (DSGN-175: no es un error, FMX los pinta con el estilo de su clase; los
    # Samples de iOS en Windows: tabitemmostviewed, medido el 8-nov-2026)
    if mc.es(r, 'SN_DESIGNER_LOOKUPS_SIN_ESTILO_FMT') or mc.es(r, 'SN_DESIGNER_LOOKUPS_FUERA_DE_STYLES_FMT'):
        lookups_sin_estilo.append(rel)
    if mc.es(r, 'SN_DESIGNER_LINT_SIN_LECTOR_FMT'):
        if mc.es(r, 'SR_DESIGNER_SIN_RENDER_FMT'):
            sin_render.append(rel)
        else:
            motivo = r.split(CABEZA, 1)[1] if CABEZA in r else r
            suyo = next((n for n, rx in CONTESTO.items() if rx.match(motivo)), None)
            if suyo:
                contesto.setdefault(suyo, []).append(rel)
            else:
                m = mc.ETIQUETA.match(motivo.lstrip())
                sin_lector.setdefault(m.group(1) if m else 'sin id', []).append(rel)
    # los avisos del bloque de DSGN-038 sin linea de este fichero: los del
    # lector y los del form contra su clase (check-binding)
    bloque = None
    for l in r.splitlines():
        if not l.startswith(' '):
            bloque = 'bad' if mc.abre(l, 'SN_DESIGNER_LINT_BAD_FMT') else 'otro'
        elif bloque == 'bad' and l.strip() and not LINEA_N.match(l):
            if rel in VERDADEROS and VERDADEROS[rel] in l:
                vistos_verdaderos.add(rel)
                continue
            falsos += 1
            ejemplos.append('%s aviso sin linea: %s' % (rel, l.strip()[:160]))
    if mc.es(r, 'SN_DSGN_PARSER_FMT'):
        falsos += 1
        ejemplos.append('%s parser del IDE: %s' % (os.path.relpath(dst, FORMS), r[:160]))
    for l in r.splitlines():
        m = re.match(r'\s*line (\d+): (.*?)\s+->\s+(.*)$', l)
        if not m:
            continue
        msg = m.group(3)
        if mc.es(msg, 'SN_LINT_UNKNOWN_CLASS_FMT') or mc.es(msg, 'SN_LINT_CLASE_AMBIGUA_FMT'):
            notas += 1          # una clase sin fuente, o ambigua: no juzga, lo dice
        elif FAMILIA in msg:
            familia += 1        # politica pendiente (ver la cabecera)
        else:
            falsos += 1
            ejemplos.append('%s:%s %s -> %s' % (os.path.relpath(dst, FORMS), m.group(1), m.group(2)[:60], msg[:120]))
check('corpus: el lint CONTESTA de cada form (limpio, avisos, notas o sin confirmar)',
      not sin_lint, ' || '.join(sin_lint[:5]))
check('corpus: al lector se le pregunta (el arnes pone los renderizadores)',
      not sin_render, ' || '.join(sin_render[:5]))
check('corpus: los StyleLookup se juzgan (el arnes pone el conversor, su juez)',
      not sin_conversor, ' || '.join(sin_conversor[:3]))
print('NOTA: corpus: %d forms con StyleLookup que ningun estilo que ven define (DSGN-175, una nota)' % len(lookups_sin_estilo))
# (18-oct-2026) TODOS, uno por linea: el detalle de check se recorta y con
# los 8 primeros no se podia medir cuantos ni cuales eran
for motivo, forms in sorted(contesto.items()):
    print('NOTA: corpus: %d forms que el lector leyo y no se le pueden cargar, %s:' % (len(forms), motivo))
    for f in forms:
        print('    ' + f)
for motivo, forms in sorted(sin_lector.items()):
    print('NOTA: corpus: %d forms sin confirmar: no se le pudo preguntar al lector, %s:' % (len(forms), motivo))
    for f in forms:
        print('    ' + f)
# un lector que no se pudo preguntar por OTRA cosa que su plazo (RENDER-007: hay Samples que
# lo agotan) es un rojo: un DSGN-177 o un ayudante que no arranca se quedaban en esa NOTA y
# la bateria salia verde (revisor de baterias de la 1.27)
# (y desde la 1.27, el plazo del CLIENTE: los lint van en paralelo y uno puede quedarse sin el
# tiempo que espera un cliente antes de preguntar, DSGN-188; antes era un fragmento sin id)
PLAZOS = (mc.id_de('SR_RENDER_TIEMPO_FMT'), mc.id_de('SR_DESIGNER_RENDER_TIEMPO_FMT'),
          mc.id_de('SR_DSGN_JUEZ_SIN_TIEMPO_FMT'))
# ...ni por el propio form, MEDIDO el 4-nov-2026 (y lo mismo en su sitio): un componente que
# revienta al cargarse aqui (DSGN-061: un AV en vcl370.bpl) o un literal con una ruta fuera de
# lo que se lee (DSGN-115, la jaula). Uno nuevo, o con otro id, es rojo; uno que ya se lee,
# tambien: se quita de aqui (la lista solo encoge). Salieron los dos de Controls (un TEdit y un
# TMemo nativos que pedian COMCTL32 4.70): desde la 1.27 los ayudantes llevan el manifiesto del IDE
_MD = os.path.join('Object Pascal', 'Multi-Device Samples')
NO_SE_LEEN = {
    os.path.join('Object Pascal', 'VCL', 'Windows 10 SharingContract', 'Component', 'FormShareComponent.dfm'):
        'SR_DESIGNER_RENDER_FALLO_FMT',
    os.path.join(_MD, 'Device Sensors and Services', 'Address Book', 'Contacts', 'main_u.fmx'):
        'SR_DESIGNER_LITERAL_FUERA_FMT',
    os.path.join(_MD, 'Device Sensors and Services', 'Address Book', 'Contacts', 'main_u.iPhone47in.fmx'):
        'SR_DESIGNER_LITERAL_FUERA_FMT'}
sin_preguntar = {f: m for m, fs in sin_lector.items() for f in fs}
otros = ['%s: %s' % (f, m) for f, m in sorted(sin_preguntar.items())
         if m not in PLAZOS and (f not in NO_SE_LEEN or mc.id_de(NO_SE_LEEN[f]) != m)]
check('corpus: al lector se le pregunta de cada form, salvo su plazo y los medidos que no se leen (%d)'
      % len(NO_SE_LEEN), not otros, ' || '.join(otros[:5]))
ya_se_leen = sorted(set(NO_SE_LEEN) - set(sin_preguntar))
check('corpus: los medidos que no se leen siguen sin leerse (si ya se leen, fuera de NO_SE_LEEN)',
      not ya_se_leen, ya_se_leen)
for e in ejemplos:
    print('AVISO: ' + e)
check('corpus: ni un aviso sobre los forms que el IDE escribio (%d forms; %d avisos, arriba)' % (len(copiados), falsos),
      falsos == 0, ' || '.join(ejemplos[:3]))
check('corpus: los avisos VERDADEROS medidos siguen saliendo (%d)' % len(VERDADEROS),
      vistos_verdaderos == set(VERDADEROS), sorted(set(VERDADEROS) - vistos_verdaderos))
if familia:
    print('NOTA: corpus: %d avisos de familia (clases que registra un paquete sin fuente: politica pendiente)' % familia)
print('NOTA: corpus: %d notas de clase sin fuente o ambigua (no juzgan)' % notas)

para()
mc.borra(BASE)
mc.fin('designer-corpus battery')
