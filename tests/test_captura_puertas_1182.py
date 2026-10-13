# -*- coding: utf-8 -*-
"""La captura es trabajo nuestro (1.18.2, puntos 2b y 2af).

Una captura que el servidor hace para devolverla (sin out=) vive en SU casa
de capturas: la temporal del servidor, por workspace y por agente
(Lsp.Casa.CasaDeCapturas). Nunca en el workspace ni por la jaula: lo que
INTENTA el agente pasa los filtros (que pueda leer el .dfm, el out= que
nombre); hacer la captura, guardarla y devolverla es nuestro proceso (David,
12-oct-2026). Hasta la 1.18.2 vivia en el __delphi-temp de la primera raiz
escribible, con un criterio equivocado (delphi_fetch pasaba por la jaula), y
costo: enlaces plantados alli que sacaban el dibujo de las raices (2b),
DESK-019 con un agente confinado o sin raiz escribible (2i), un PNG dibujado
DENTRO de una raiz de solo lectura (revisor del 2i) y un enlace de descarga
que la jaula negaba cuando la captura caia en la temporal (medido el 12-oct).
Y el agente no ve nuestra casa (David, 12-oct-2026: "nuestros procesos
internos y nuestro temp, los agentes no deben ni olerlo"): ninguna respuesta
nombra su ruta, el enlace pide la captura por su NOMBRE y delphi_fetch es
para los ficheros del agente.

  C0  el agente de la bateria esta confinado (lo que sigue mide su caso)
  C1  component= sin out=: el recorte (344x41) en NUESTRA casa de capturas,
      con su carpeta de agente, y nada en la raiz
  C2  ...en linea: la imagen viaja recortada y su temporal se consume
  C3  ...con out= en su carpeta: alli el recorte, y ninguno suelto en la casa
  K1  un junction plantado en el __delphi-temp de la raiz hacia una victima de
      fuera: no cambia nada, ahi ya no escribimos (la victima, vacia)
  K6  un png con forma de captura en el workspace (a traves de un enlace a la
      carpeta de otro agente): se lee, pero no es nuestro y no se borra
  K7  un enlace DENTRO de nuestra casa: con out= tambien se niega (CAPT-010
      lo dice), el out= no se escribe y la victima queda vacia
  S1  sin raiz escribible: la captura en nuestra casa, recortada, nada en la raiz
  S2  ...y en linea: viaja recortada y se consume
  S3  un enlace DENTRO de nuestra casa de capturas: CAPT-010, la victima vacia
  S4  la raiz en 8.3 y su entrada de solo lectura en largo (y S5 al reves):
      nada en la raiz (el PNG caia DENTRO de ella; revisor del 2i)
  S6  entradas de solo lectura y referencias DENTRO del __delphi-temp de una
      raiz: la captura en nuestra casa y nada alli
  F1  inline=false por stdio (sin la ruta /files): la respuesta no nombra
      nuestra casa (ni screenshot) y dice que use out=; la captura se queda
  F2  delphi_fetch de la ruta de nuestra casa: negado, y no consume nada
  E0  servidor HTTP con dos workspaces: el enlace pide la captura por su
      NOMBRE (/files?capture=), sin screenshot ni nada de nuestra casa
  E1  delphi_fetch de la ruta de la casa: negado al otro workspace Y al dueño
      (E4), y no se consume nada
  E2  el enlace con el token del otro workspace: 404 (no es suya), y se queda
  E3  su dueño la baja por el enlace (200, el PNG), y la segunda vez 404
  E5  capture= con carpeta o unidad: 400 FILE-044; ?path= de la casa: 403, y se queda
  E6  diez GET a la vez del mismo enlace: UNA la baja (200), las demas 404
      FILE-045 sin nombrar la casa, y no queda nada (revisor del 2af: daba
      dos 200 y un 500 con la ruta de la casa)
  R1  una raiz declarada a traves de un junction: el recorte en nuestra casa

Uso:  python tests/test_captura_puertas_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import atexit, concurrent.futures, glob, json, os, shutil, urllib.error, urllib.request
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('captura_puertas_1182')
# se borra AUNQUE la bateria caiga a medias; mc.borra quita un enlace como
# enlace, nunca lo de detras
atexit.register(mc.borra, BASE)
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
SOLO = os.path.join(BASE, 'solo')
for d in (JAIL, FUERA, SOLO):
    os.makedirs(d, exist_ok=True)

FORM = """object FormPrueba: TFormPrueba
  Left = 0
  Top = 0
  Caption = 'Prueba'
  ClientHeight = 200
  ClientWidth = 400
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  PixelsPerInch = 96
  TextHeight = 15
  object Panel1: TPanel
    Left = 16
    Top = 140
    Width = 344
    Height = 41
    Caption = ''
    Color = clSkyBlue
    ParentBackground = False
    TabOrder = 0
  end
end
"""


def escribe(carpeta, nombre, texto):
    ruta = os.path.join(carpeta, nombre)
    with open(ruta, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write(texto)
    return ruta


def J(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


def contenido(carpeta):
    """Todo lo que hay debajo, carpetas incluidas: una victima que recibe una
    carpeta vacia tampoco esta intacta."""
    todo = []
    for raiz, dirs, ficheros in os.walk(carpeta):
        todo += [os.path.join(raiz, n) for n in dirs + ficheros]
    return sorted(todo)


def tamano(ruta):
    return mc.png_pixeles(ruta)[:2] if ruta and os.path.isfile(ruta) else None


def quita_enlace(ruta):
    if os.path.isjunction(ruta) or os.path.islink(ruta):
        os.rmdir(ruta)


def casa(srv_dir):
    """Las capturas de designer en la casa de un servidor (su temporal), de
    todos sus workspaces y agentes: por el nombrador de las baterias."""
    return os.path.join(mc.casa_de_capturas(srv_dir), '**', 'designer', '*.png')


def sin_casa(t):
    """La respuesta no nombra nuestra casa: ni su carpeta de temporales ni la
    de capturas, ni un 'screenshot' (lo era siempre, sin out=)."""
    b = t.lower()
    return (mc.TEMPORALES.lower() not in b and
            os.path.basename(mc.casa_de_capturas('')).lower() not in b and
            'screenshot"' not in b)


def pngs_en(raiz):
    return glob.glob(os.path.join(raiz, '**', '*.png'), recursive=True)


PRUEBA = escribe(JAIL, 'Prueba.dfm', FORM)
PRUEBA_SOLO = escribe(SOLO, 'Prueba.dfm', FORM)
TEMP_JAULA = os.path.join(JAIL, '__delphi-temp')
RECT = '16,140,344,41'

# ---------------------------------------------------- servidor A: confinado
SRV1 = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRV1, con_render=True)
CAPS = casa(SRV1)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_AGENT_CONFINEMENT': '1'}),
               nombre='ana', t=180)


def preview(cli, **kw):
    a = {'command': 'preview'}
    a.update(kw)
    return cli.call('delphi_designer', a, t=180)


try:
    r = srv.call('delphi_textedit', {'path': os.path.join(JAIL, 'suelto.txt'), 'create': True, 'content': 'x'})
    check('C0 el agente de la bateria esta confinado (escribir suelto en la raiz se niega)',
          mc.rechazado(r) and mc.es(r, 'SR_AGENT_CONFINED_FMT'), r[:300])

    # ------------------------------------------------------------------ C1
    antes = set(glob.glob(CAPS, recursive=True))
    r = preview(srv, path=PRUEBA, component='Panel1', inline='false')
    j = J(r)
    nuevos = sorted(set(glob.glob(CAPS, recursive=True)) - antes)
    uno = nuevos[0] if len(nuevos) == 1 else ''
    check('C1 confinado, component= sin out=: el recorte (344x41) en NUESTRA casa, con su carpeta, y nada en la raiz',
          j.get('componentRect') == RECT and tamano(uno) == (344, 41) and
          (os.sep + 'ana' + os.sep) in uno and not os.path.exists(TEMP_JAULA),
          (r[:400], nuevos, tamano(uno), os.path.exists(TEMP_JAULA)))
    for n in nuevos:
        os.remove(n)

    # ------------------------------------------------------------------ C2
    antes = set(glob.glob(CAPS, recursive=True))
    r = preview(srv, path=PRUEBA, component='Panel1')
    j = J(r)
    sueltos = sorted(set(glob.glob(CAPS, recursive=True)) - antes)
    check('C2 ...en linea: la imagen viaja recortada (344 de ancho) y su temporal se consume',
          j.get('inlineImage') is True and j.get('inlineWidth') == 344 and
          j.get('consumed') is True and not sueltos, (r[:400], sueltos))

    # ------------------------------------------------------------------ C3
    PROPIA = os.path.join(JAIL, 'ana')
    os.makedirs(PROPIA, exist_ok=True)
    OUT3 = os.path.join(PROPIA, 'c3.png')
    antes = set(glob.glob(CAPS, recursive=True))
    r = preview(srv, path=PRUEBA, component='Panel1', out=OUT3, inline='false')
    sueltos = sorted(set(glob.glob(CAPS, recursive=True)) - antes)
    check('C3 ...con out= en su carpeta: alli el recorte (344x41), y ninguno suelto en la casa',
          tamano(OUT3) == (344, 41) and not sueltos, (r[:400], tamano(OUT3), sueltos))

    # ------------------------------------------------------------------ K1
    V1 = os.path.join(FUERA, 'v1')
    os.makedirs(V1)
    CARP = os.path.join(TEMP_JAULA, 'ana', 'designer')
    os.makedirs(os.path.dirname(CARP), exist_ok=True)
    check('K1a el enlace en el __delphi-temp de la raiz hacia una victima de fuera quedo plantado',
          mc.junction(CARP, V1), CARP)
    antes = set(glob.glob(CAPS, recursive=True))
    r = preview(srv, path=PRUEBA, component='Panel1', inline='false')
    nuevos = sorted(set(glob.glob(CAPS, recursive=True)) - antes)
    check('K1 un enlace en el __delphi-temp de la raiz no cambia nada: la captura en nuestra casa y la victima vacia',
          not mc.fallo(r) and len(nuevos) == 1 and not contenido(V1), (r[:400], nuevos, contenido(V1)))
    quita_enlace(CARP)
    shutil.rmtree(TEMP_JAULA, ignore_errors=True)

    # ------------------------------------------------------------------ K6
    BOB = os.path.join(JAIL, 'bob')
    os.makedirs(os.path.join(BOB, 'designer'))
    AJENA = os.path.join(BOB, 'designer', 'v.png')
    open(AJENA, 'wb').write(b'\x89PNG\r\n\x1a\n' + b'0' * 64)
    check('K6a __delphi-temp de la raiz como enlace a la carpeta de otro agente quedo plantado',
          mc.junction(TEMP_JAULA, BOB), TEMP_JAULA)
    r = srv.call('delphi_fetch', {'path': os.path.join(TEMP_JAULA, 'designer', 'v.png'), 'offset': 0})
    check('K6 un png con forma de captura en el workspace se lee, pero no es nuestro y no se borra',
          os.path.isfile(AJENA) and mc.como_json(r).get('consumedOnServer') is not True,
          (r[:300], os.path.isfile(AJENA)))
    quita_enlace(TEMP_JAULA)
    # ------------------------------------------------------------------ K7
    V7 = os.path.join(FUERA, 'v7')
    os.makedirs(V7)
    CARP1 = os.path.join(mc.casa_de_capturas(SRV1, 'ana', ''), 'designer')
    shutil.rmtree(CARP1, ignore_errors=True)
    os.makedirs(os.path.dirname(CARP1), exist_ok=True)
    check('K7a el enlace dentro de nuestra casa de capturas quedo plantado', mc.junction(CARP1, V7), CARP1)
    OUT7 = os.path.join(PROPIA, 'k7.png')
    r = preview(srv, path=PRUEBA, component='Panel1', out=OUT7, inline='false')
    check('K7 con un enlace en nuestra casa, out= tambien se niega (CAPT-010 lo dice), sin escribir el out= ni la victima',
          mc.rechazado(r) and mc.es(r, 'SR_CAPTURE_CASA_ENLACE') and 'with or without out=' in r and sin_casa(r)
          and not os.path.exists(OUT7) and not contenido(V7), (r[:400], os.path.exists(OUT7), contenido(V7)))
    quita_enlace(CARP1)
    check('K4 el servidor sigue vivo', not mc.fallo(srv.call('delphi_list', {'root': JAIL})))
finally:
    srv.cierra()

# ------------------------------------- servidor B: sin raiz escribible (S1-S3, F1)
SRV2 = os.path.join(BASE, 'srv2')
EXE2 = mc.copia_exe(SRV2, con_render=True)
CAPS2 = casa(SRV2)
srv2 = mc.Stdio(EXE2, mc.entorno({'DELPHI_MCP_ROOTS': SOLO, 'DELPHI_MCP_READONLY_PATHS': SOLO}),
                nombre='ana', t=180)
try:
    antes = set(glob.glob(CAPS2, recursive=True))
    r = preview(srv2, path=PRUEBA_SOLO, component='Panel1', inline='false')
    j = J(r)
    nuevos = sorted(set(glob.glob(CAPS2, recursive=True)) - antes)
    uno = nuevos[0] if len(nuevos) == 1 else ''
    check('S1 sin raiz escribible: la captura en nuestra casa, recortada (344x41), nada en la raiz',
          j.get('componentRect') == RECT and tamano(uno) == (344, 41) and not pngs_en(SOLO),
          (r[:400], nuevos, tamano(uno), pngs_en(SOLO)))
    # ------------------------------------------------------------------ F1
    check('F1 inline=false por stdio: la respuesta no nombra nuestra casa y dice que use out=; la captura se queda',
          sin_casa(r) and mc.es(r, 'SN_CAPTURE_SIN_ENLACE') and 'download' not in j and os.path.isfile(uno),
          (r[:400], os.path.isfile(uno)))
    # ------------------------------------------------------------------ F2
    f = srv2.call('delphi_fetch', {'path': uno, 'maxbytes': 65536})
    check('F2 delphi_fetch es para los ficheros del agente: la ruta de nuestra casa se niega y no se consume',
          mc.rechazado(f) and os.path.isfile(uno), (f[:300], os.path.isfile(uno)))
    antes = set(glob.glob(CAPS2, recursive=True))
    r = preview(srv2, path=PRUEBA_SOLO, component='Panel1')
    j = J(r)
    sueltos = sorted(set(glob.glob(CAPS2, recursive=True)) - antes)
    check('S2 ...y en linea: viaja recortada (344 de ancho) y se consume',
          j.get('inlineImage') is True and j.get('inlineWidth') == 344 and
          j.get('consumed') is True and not sueltos, (r[:400], sueltos))
    # ------------------------------------------------------------------ S3
    CARP2 = os.path.join(mc.casa_de_capturas(SRV2, 'ana', ''), 'designer')
    V4 = os.path.join(FUERA, 'v4')
    os.makedirs(V4)
    shutil.rmtree(CARP2, ignore_errors=True)
    os.makedirs(os.path.dirname(CARP2), exist_ok=True)
    check('S3a el enlace dentro de nuestra casa de capturas quedo plantado', mc.junction(CARP2, V4), CARP2)
    r = preview(srv2, path=PRUEBA_SOLO, component='Panel1', inline='false')
    check('S3 un enlace DENTRO de nuestra casa de capturas: se niega (CAPT-010, sin nombrar la casa) y la victima queda vacia',
          mc.rechazado(r) and mc.es(r, 'SR_CAPTURE_CASA_ENLACE') and sin_casa(r) and not contenido(V4),
          (r[:400], contenido(V4)))
    quita_enlace(CARP2)
finally:
    srv2.cierra()

# ------------- servidor B': la raiz y su entrada de solo lectura en dos formas (S4-S5)
LARGA_SOLO = mc.larga(SOLO)
check('S4a la carpeta de solo lectura tiene dos formas (8.3 y larga)', LARGA_SOLO.lower() != SOLO.lower(),
      (SOLO, LARGA_SOLO))
for nombre, raiz, entrada in (('S4 la raiz en 8.3 y su entrada en largo', SOLO, LARGA_SOLO),
                              ('S5 la raiz en largo y su entrada en 8.3', LARGA_SOLO, SOLO)):
    srv2 = mc.Stdio(EXE2, mc.entorno({'DELPHI_MCP_ROOTS': raiz, 'DELPHI_MCP_READONLY_PATHS': entrada}),
                    nombre='ana', t=180)
    try:
        antes = set(glob.glob(CAPS2, recursive=True))
        r = preview(srv2, path=PRUEBA_SOLO, component='Panel1', inline='false')
        nuevos = sorted(set(glob.glob(CAPS2, recursive=True)) - antes)
        check(nombre + ': la captura en nuestra casa, nada dentro de la raiz de solo lectura',
              len(nuevos) == 1 and not pngs_en(SOLO), (r[:400], nuevos, pngs_en(SOLO)))
    finally:
        srv2.cierra()

# ------------- servidor B'': solo lectura y referencias DENTRO del __delphi-temp de una raiz (S6)
RAIZ3 = os.path.join(BASE, 'raiz3')
os.makedirs(RAIZ3)
PRUEBA3 = escribe(RAIZ3, 'Prueba.dfm', FORM)
TEMP3 = os.path.join(RAIZ3, '__delphi-temp')
for clave, entrada in (('DELPHI_MCP_READONLY_PATHS', os.path.join(TEMP3, 'ana')),
                       ('DELPHI_MCP_READONLY_PATHS', TEMP3),
                       ('DELPHI_MCP_READONLY_ROOTS', os.path.join(TEMP3, 'ana'))):
    srv2 = mc.Stdio(EXE2, mc.entorno({'DELPHI_MCP_ROOTS': RAIZ3, clave: entrada}), nombre='ana', t=180)
    try:
        antes = set(glob.glob(CAPS2, recursive=True))
        r = preview(srv2, path=PRUEBA3, component='Panel1', inline='false')
        nuevos = sorted(set(glob.glob(CAPS2, recursive=True)) - antes)
        check('S6 %s=%s: la captura en nuestra casa y nada en la raiz' % (clave[11:], os.path.relpath(entrada, RAIZ3)),
              len(nuevos) == 1 and not pngs_en(RAIZ3), (r[:400], nuevos, pngs_en(RAIZ3)))
    finally:
        srv2.cierra()

# ------------- servidor D: HTTP con dos workspaces, la ENTREGA a su dueño (E1-E4)
SRV4 = os.path.join(BASE, 'srv4')
EXE4 = mc.copia_exe(SRV4, con_render=True)
RAIZ_OP, RAIZ_OTRO = os.path.join(BASE, 'op'), os.path.join(BASE, 'otro')
for d in (RAIZ_OP, RAIZ_OTRO):
    os.makedirs(d)
PRUEBA_OP = escribe(RAIZ_OP, 'Prueba.dfm', FORM)
T_OP, T_OTRO = 'captura1182-op-0123456789', 'captura1182-otro-0123456789'
PUERTO = mc.puerto_libre()
with open(os.path.join(SRV4, 'settings.ini'), 'w') as f:
    f.write('[Server]\nPort=%d\nBindIP=127.0.0.1\n\n[Workspace.Op]\nToken=%s\nRoots=%s\n\n'
            '[Workspace.Otro]\nToken=%s\nRoots=%s\n' % (PUERTO, T_OP, RAIZ_OP, T_OTRO, RAIZ_OTRO))


def get(dl, token):
    req = urllib.request.Request('http://127.0.0.1:%d%s' % (PUERTO, dl))
    req.add_header('Authorization', 'Bearer ' + token)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


CAPS4 = os.path.join(mc.casa_de_capturas(SRV4, 'ana', 'Op'), 'designer', '*.png')
proc4 = mc.lanza_http(EXE4, None, mc.entorno(), espera_en=PUERTO)
try:
    op = mc.Http(PUERTO, T_OP, t=180)
    op.session('ana')
    otro = mc.Http(PUERTO, T_OTRO, t=180)
    otro.session('bob')
    antes = set(glob.glob(CAPS4))
    r = op.call('delphi_designer', {'command': 'preview', 'path': PRUEBA_OP, 'inline': False}, t=180)
    j = J(r)
    dl = j.get('download', '')
    nuevos = sorted(set(glob.glob(CAPS4)) - antes)
    cap = nuevos[0] if len(nuevos) == 1 else ''
    check('E0 el enlace pide la captura por su NOMBRE (?capture=), sin screenshot ni nada de nuestra casa; nada en su raiz',
          bool(cap) and dl == '/files?capture=' + os.path.basename(cap) and sin_casa(r) and
          j.get('consumedOnDownload') is True and not pngs_en(RAIZ_OP),
          (r[:400], nuevos, pngs_en(RAIZ_OP)))
    f = otro.call('delphi_fetch', {'path': cap, 'maxbytes': 65536})
    check('E1 delphi_fetch de la ruta de la casa: el OTRO workspace no se la lleva, y se queda',
          mc.rechazado(f) and os.path.isfile(cap), (f[:300], os.path.isfile(cap)))
    codigo, cuerpo = get(dl, T_OTRO)
    check('E2 ...ni por el enlace (404: no es de su workspace), y se queda',
          codigo == 404 and os.path.isfile(cap), (codigo, cuerpo[:200]))
    f = op.call('delphi_fetch', {'path': cap, 'maxbytes': 65536})
    check('E4 delphi_fetch es para los ficheros del agente: al DUEÑO tambien se le niega, y se queda',
          mc.rechazado(f) and os.path.isfile(cap), (f[:300], os.path.isfile(cap)))
    codigo, cuerpo = get('/files?path=' + urllib.request.quote(cap), T_OP)
    check('E5a ?path= de la ruta de la casa: la jaula lo niega (403) y no se consume',
          codigo == 403 and os.path.isfile(cap), (codigo, cuerpo[:200]))
    for malo in ('..\\..\\settings.ini', 'designer/x.png', 'C:x.png', ''):
        codigo, cuerpo = get('/files?capture=' + urllib.request.quote(malo), T_OP)
        check('E5 capture=%r no es un nombre de captura: 400 FILE-044 sin nombrar la casa' % malo,
              codigo == 400 and mc.es(cuerpo.decode('utf-8', 'replace'), 'SR_FILES_CAPTURA_NOMBRE') and
              sin_casa(cuerpo.decode('utf-8', 'replace')), (codigo, cuerpo[:200]))
    codigo, cuerpo = get(dl, T_OP)
    codigo2, _ = get(dl, T_OP)
    check('E3 su dueño la baja por el enlace (200, el PNG entero), y la segunda vez 404 (consumida)',
          codigo == 200 and cuerpo[:8] == b'\x89PNG\r\n\x1a\n' and codigo2 == 404 and not os.path.isfile(cap),
          (codigo, codigo2, cuerpo[:16]))
    # ------------------------------------------------------------------ E6
    r = op.call('delphi_designer', {'command': 'preview', 'path': PRUEBA_OP, 'inline': False}, t=180)
    dl6 = J(r).get('download', '')
    with concurrent.futures.ThreadPoolExecutor(10) as ex:
        res6 = list(ex.map(lambda _: get(dl6, T_OP), range(10)))
    codigos = sorted(c for c, _ in res6)
    textos = [(c, b.decode('utf-8', 'replace')) for c, b in res6 if c != 200]
    restos = glob.glob(os.path.join(mc.casa_de_capturas(SRV4, 'ana', 'Op'), '**', '*'), recursive=True)
    check('E6 diez GET a la vez del mismo enlace: UNA la baja (200), las demas 404 FILE-045 sin nombrar la casa, y no queda nada',
          bool(dl6) and codigos.count(200) == 1 and codigos.count(404) == 9 and
          all(mc.es(t, 'SR_FILES_CAPTURA_NO_ESTA') and sin_casa(t) for c, t in textos) and
          not [p for p in restos if os.path.isfile(p)],
          (codigos, [t[:120] for _, t in textos if not mc.es(t, 'SR_FILES_CAPTURA_NO_ESTA')], restos))
finally:
    proc4.kill()
    proc4.wait()

# ------------------------- servidor C: la raiz declarada por un junction (R1)
REAL = os.path.join(BASE, 'real')
os.makedirs(REAL)
PRUEBA_REAL = escribe(REAL, 'Prueba.dfm', FORM)
POR_ENLACE = os.path.join(BASE, 'por_enlace')
check('R1a la raiz por junction quedo plantada', mc.junction(POR_ENLACE, mc.larga(REAL)), POR_ENLACE)
SRV3 = os.path.join(BASE, 'srv3')
EXE3 = mc.copia_exe(SRV3, con_render=True)
CAPS3 = casa(SRV3)
srv3 = mc.Stdio(EXE3, mc.entorno({'DELPHI_MCP_ROOTS': POR_ENLACE}), nombre='ana', t=180)
try:
    antes = set(glob.glob(CAPS3, recursive=True))
    r = preview(srv3, path=os.path.join(POR_ENLACE, 'Prueba.dfm'), component='Panel1', inline='false')
    j = J(r)
    nuevos = sorted(set(glob.glob(CAPS3, recursive=True)) - antes)
    uno = nuevos[0] if len(nuevos) == 1 else ''
    check('R1 una raiz declarada a traves de un junction: el recorte (344x41) en nuestra casa, nada en la raiz',
          j.get('componentRect') == RECT and tamano(uno) == (344, 41) and not pngs_en(REAL),
          (r[:400], nuevos, tamano(uno), pngs_en(REAL)))
finally:
    srv3.cierra()
    quita_enlace(POR_ENLACE)

check('las victimas de fuera, intactas al acabar', not contenido(FUERA) or
      all(os.path.isdir(p) and p in [os.path.join(FUERA, v) for v in ('v1', 'v4', 'v7')]
          for p in contenido(FUERA)), contenido(FUERA))
mc.fin('captura por las puertas 1182')
