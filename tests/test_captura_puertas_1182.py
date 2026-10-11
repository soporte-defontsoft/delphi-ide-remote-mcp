# -*- coding: utf-8 -*-
"""La captura por las puertas (1.18.2, punto 2b).

Una captura que el servidor deja en SU carpeta (sin out=) vive en la casa de
los entregables: el __delphi-temp de la primera raiz escribible, con la
carpeta del agente, o el temporal del servidor si no hay ninguna (Lsp.Guard,
AgentTempDir). Hasta la 1.18.1 nadie miraba si en ese camino habia un enlace:
el renderizador dibujaba alli y RecortaPng releia y reescribia EN SITIO, sin
puerta, asi que un enlace plantado en la carpeta de capturas llevaba las dos
escrituras FUERA de las raices. Y el recorte no podia ir por la puerta de la
jaula: a un agente confinado la jaula le niega __delphi-temp, y sus capturas
viven alli.

  C0  el agente de la bateria esta confinado (lo que sigue mide su caso)
  C1  component= sin out=: el recorte, con el tamano del componente, en SU
      carpeta de capturas (la puerta de los entregables: la de la jaula se lo
      negaria)
  C2  ...en linea: la imagen viaja recortada y su temporal se consume
  C3  ...con out= en su carpeta: alli el recorte, y ninguno suelto
  K1  un enlace en la carpeta de capturas del agente que apunta fuera: se
      niega ANTES de dibujar (CAPT-010) y la victima queda vacia
  K2  ...tambien sin recorte y en linea
  K5  ...y un enlace que apunta DENTRO de la jaula tambien: ningun enlace, vaya
      adonde vaya (lo promete CAPT-010; revisor del 2b)
  K3  el enlace en el propio __delphi-temp de la raiz: igual
  K6  consumir una captura es BORRARLA: con __delphi-temp como enlace a la
      carpeta de OTRO agente, delphi_fetch de un png de alli lo lee pero no lo
      borra (el lector de la casa iba por la ruta real; revisor del 2b)
  S1  sin raiz escribible (la unica es de solo lectura) la captura cae en el
      temporal del servidor, y el recorte se lee y se escribe alli
  S2  ...y en linea: viaja recortada y se consume
  S3  un enlace DENTRO del temporal del servidor: CAPT-010, la victima vacia
  S4  la raiz en 8.3 y su entrada de ReadOnlyPaths en largo: sigue sin ser
      escribible y la captura cae en el temporal del servidor, no DENTRO de
      ella (la casa comparaba ReadOnlyPaths por su texto crudo; revisor del
      2i, medido: el PNG caia en solo\__delphi-temp)
  S5  ...y al reves: la raiz en largo y la entrada en 8.3
  S6  una entrada de ReadOnlyPaths DENTRO de la casa (la carpeta del agente
      en __delphi-temp): se niega diciendolo (GUARD-012, no un enlace) y nada
      se dibuja alli
  S7  ...y una que cubre el __delphi-temp entero: la casa no es esa, la
      captura cae en el temporal del servidor
  S8  una REFERENCIA (ReadOnlyRoots) dentro de la casa (la carpeta del agente):
      se niega diciendolo (GUARD-016) y nada se dibuja alli (revisor del 2i)
  R1  una raiz declarada a traves de un junction: el recorte funciona (la
      raiz la declara el operador; su __delphi-temp, no). Una raiz en 8.3 la
      cubren todas: la jaula de la bateria cuelga de %TEMP%, que es 8.3

Uso:  python tests/test_captura_puertas_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import atexit, glob, json, os, shutil
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


PRUEBA = escribe(JAIL, 'Prueba.dfm', FORM)
PRUEBA_SOLO = escribe(SOLO, 'Prueba.dfm', FORM)
TEMP_JAULA = os.path.join(JAIL, '__delphi-temp')
CAPS = os.path.join(TEMP_JAULA, '**', 'designer', '*.png')
RECT = '16,140,344,41'

# ---------------------------------------------------- servidor A: confinado
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
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
    check('C1 confinado, component= sin out=: el recorte (344x41) en SU carpeta de capturas',
          j.get('componentRect') == RECT and tamano(uno) == (344, 41) and
          (os.sep + 'ana' + os.sep) in uno, (r[:400], nuevos, tamano(uno)))
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
    check('C3 ...con out= en su carpeta: alli el recorte (344x41), y ninguno suelto en la de capturas',
          tamano(OUT3) == (344, 41) and not sueltos, (r[:400], tamano(OUT3), sueltos))

    # ------------------------------------------------------------------ K1-K2
    CARP = os.path.join(TEMP_JAULA, 'ana', 'designer')
    V1 = os.path.join(FUERA, 'v1')
    os.makedirs(V1)
    shutil.rmtree(CARP, ignore_errors=True)
    os.makedirs(os.path.dirname(CARP), exist_ok=True)
    check('K0 el enlace de la carpeta de capturas del agente a una victima de fuera quedo plantado',
          mc.junction(CARP, V1), CARP)
    r = preview(srv, path=PRUEBA, component='Panel1', inline='false')
    check('K1 un enlace en la carpeta de capturas que sale de las raices: se niega (CAPT-010) y la victima queda vacia',
          mc.rechazado(r) and mc.es(r, 'SR_CAPTURE_CASA_ENLACE_FMT') and not contenido(V1),
          (r[:400], contenido(V1)))
    r = preview(srv, path=PRUEBA)
    check('K2 ...tambien sin recorte y en linea: el renderizador no llega a dibujar alli',
          mc.rechazado(r) and mc.es(r, 'SR_CAPTURE_CASA_ENLACE_FMT') and not contenido(V1),
          (r[:400], contenido(V1)))
    quita_enlace(CARP)

    # ------------------------------------------------------------------ K5
    DENTRO = os.path.join(JAIL, 'dentro')
    os.makedirs(DENTRO)
    check('K5a el enlace de la carpeta de capturas a una carpeta DE LA JAULA quedo plantado',
          mc.junction(CARP, DENTRO), CARP)
    r = preview(srv, path=PRUEBA, component='Panel1', inline='false')
    check('K5 ...un enlace que apunta dentro tambien se niega (CAPT-010), y alli no cae nada',
          mc.rechazado(r) and mc.es(r, 'SR_CAPTURE_CASA_ENLACE_FMT') and not contenido(DENTRO),
          (r[:400], contenido(DENTRO)))
    quita_enlace(CARP)

    # ------------------------------------------------------------------ K3
    V3 = os.path.join(FUERA, 'v3')
    os.makedirs(V3)
    shutil.rmtree(TEMP_JAULA, ignore_errors=True)
    check('K3a el enlace en el propio __delphi-temp de la raiz quedo plantado',
          not os.path.exists(TEMP_JAULA) and mc.junction(TEMP_JAULA, V3), TEMP_JAULA)
    r = preview(srv, path=PRUEBA, component='Panel1', inline='false')
    check('K3 el enlace en el __delphi-temp de la raiz: se niega (CAPT-010) y la victima queda vacia',
          mc.rechazado(r) and mc.es(r, 'SR_CAPTURE_CASA_ENLACE_FMT') and not contenido(V3),
          (r[:400], contenido(V3)))
    quita_enlace(TEMP_JAULA)

    # ------------------------------------------------------------------ K6
    BOB = os.path.join(JAIL, 'bob')
    os.makedirs(os.path.join(BOB, 'designer'))
    AJENA = os.path.join(BOB, 'designer', 'v.png')
    open(AJENA, 'wb').write(b'\x89PNG\r\n\x1a\n' + b'0' * 64)
    check('K6a __delphi-temp como enlace a la carpeta de otro agente quedo plantado',
          mc.junction(TEMP_JAULA, BOB), TEMP_JAULA)
    r = srv.call('delphi_fetch', {'path': os.path.join(TEMP_JAULA, 'designer', 'v.png'), 'offset': 0})
    check('K6 consumir es borrar: el png de OTRO agente detras del enlace se lee pero no se borra',
          os.path.isfile(AJENA) and mc.como_json(r).get('consumedOnServer') is not True,
          (r[:300], os.path.isfile(AJENA)))
    quita_enlace(TEMP_JAULA)
    check('K4 el servidor sigue vivo', not mc.fallo(srv.call('delphi_list', {'root': JAIL})))
finally:
    srv.cierra()

# ------------------------------------- servidor B: sin raiz escribible (S1-S2)
EXE2 = mc.copia_exe(os.path.join(BASE, 'srv2'), con_render=True)
CAPS2 = os.path.join(BASE, 'srv2', '__delphi-temp', '**', '*.png')
srv2 = mc.Stdio(EXE2, mc.entorno({'DELPHI_MCP_ROOTS': SOLO, 'DELPHI_MCP_READONLY_PATHS': SOLO}),
                nombre='ana', t=180)
try:
    antes = set(glob.glob(CAPS2, recursive=True))
    r = preview(srv2, path=PRUEBA_SOLO, component='Panel1', inline='false')
    j = J(r)
    nuevos = sorted(set(glob.glob(CAPS2, recursive=True)) - antes)
    uno = nuevos[0] if len(nuevos) == 1 else ''
    check('S1 sin raiz escribible: la captura cae en el temporal del servidor, recortada (344x41)',
          j.get('componentRect') == RECT and tamano(uno) == (344, 41) and
          not os.path.exists(os.path.join(SOLO, '__delphi-temp')), (r[:400], nuevos, tamano(uno)))
    antes = set(glob.glob(CAPS2, recursive=True))
    r = preview(srv2, path=PRUEBA_SOLO, component='Panel1')
    j = J(r)
    sueltos = sorted(set(glob.glob(CAPS2, recursive=True)) - antes)
    check('S2 ...y en linea: viaja recortada (344 de ancho) y se consume',
          j.get('inlineImage') is True and j.get('inlineWidth') == 344 and
          j.get('consumed') is True and not sueltos, (r[:400], sueltos))
    # ------------------------------------------------------------------ S3
    CARP2 = os.path.join(BASE, 'srv2', '__delphi-temp', 'designer')
    V4 = os.path.join(FUERA, 'v4')
    os.makedirs(V4)
    shutil.rmtree(CARP2, ignore_errors=True)
    check('S3a el enlace dentro del temporal del servidor quedo plantado', mc.junction(CARP2, V4), CARP2)
    r = preview(srv2, path=PRUEBA_SOLO, component='Panel1', inline='false')
    check('S3 un enlace DENTRO del temporal del servidor: se niega (CAPT-010) y la victima queda vacia',
          mc.rechazado(r) and mc.es(r, 'SR_CAPTURE_CASA_ENLACE_FMT') and not contenido(V4),
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
        check(nombre + ': la captura en el temporal del servidor, NO dentro de la raiz de solo lectura',
              len(nuevos) == 1 and not os.path.exists(os.path.join(SOLO, '__delphi-temp')),
              (r[:400], nuevos, os.path.exists(os.path.join(SOLO, '__delphi-temp'))))
    finally:
        srv2.cierra()
        shutil.rmtree(os.path.join(SOLO, '__delphi-temp'), ignore_errors=True)

# ------------- servidor B'': solo lectura DENTRO de la casa (S6-S7)
RAIZ3 = os.path.join(BASE, 'raiz3')
os.makedirs(RAIZ3)
PRUEBA3 = escribe(RAIZ3, 'Prueba.dfm', FORM)
TEMP3 = os.path.join(RAIZ3, '__delphi-temp')
for nombre, entrada in (('S6', os.path.join(TEMP3, 'ana')), ('S7', TEMP3), ('S8', os.path.join(TEMP3, 'ana'))):
    clave = 'DELPHI_MCP_READONLY_ROOTS' if nombre == 'S8' else 'DELPHI_MCP_READONLY_PATHS'
    srv2 = mc.Stdio(EXE2, mc.entorno({'DELPHI_MCP_ROOTS': RAIZ3, clave: entrada}),
                    nombre='ana', t=180)
    try:
        antes = set(glob.glob(CAPS2, recursive=True))
        r = preview(srv2, path=PRUEBA3, component='Panel1', inline='false')
        nuevos = sorted(set(glob.glob(CAPS2, recursive=True)) - antes)
        dentro = glob.glob(os.path.join(TEMP3, '**', '*.png'), recursive=True)
        if nombre == 'S6':
            check('S6 solo lectura DENTRO de la casa (su carpeta del agente): GUARD-012, y nada dibujado alli',
                  mc.rechazado(r) and mc.es(r, 'SR_READONLY_PATH_FMT') and not dentro, (r[:400], dentro))
        elif nombre == 'S7':
            check('S7 solo lectura en todo su __delphi-temp: la captura en el temporal del servidor',
                  len(nuevos) == 1 and not dentro, (r[:400], nuevos, dentro))
        else:
            check('S8 una referencia DENTRO de la casa (su carpeta del agente): GUARD-016, y nada dibujado alli',
                  mc.rechazado(r) and mc.es(r, 'SR_REFERENCE_ROOT_FMT') and not dentro, (r[:400], dentro))
    finally:
        srv2.cierra()
        shutil.rmtree(TEMP3, ignore_errors=True)

# ------------------------- servidor C: la raiz declarada por un junction (R1)
REAL = os.path.join(BASE, 'real')
os.makedirs(REAL)
PRUEBA_REAL = escribe(REAL, 'Prueba.dfm', FORM)
POR_ENLACE = os.path.join(BASE, 'por_enlace')
check('R1a la raiz por junction quedo plantada', mc.junction(POR_ENLACE, mc.larga(REAL)), POR_ENLACE)
EXE3 = mc.copia_exe(os.path.join(BASE, 'srv3'), con_render=True)
srv3 = mc.Stdio(EXE3, mc.entorno({'DELPHI_MCP_ROOTS': POR_ENLACE}), nombre='ana', t=180)
try:
    # la carpeta de capturas, ya hecha: AQUI no se puede crear una carpeta a
    # traves de un junction (SYS-006 "ya existe"), y no es del servidor. Medido
    # el 11-oct-2026 (2j) sin nuestro codigo: os.makedirs por un junction falla
    # bajo AppData (Local, Local\Temp, Roaming) y va bien en D:\ y en C:\Users\<yo>
    # fuera de AppData; produccion (servicio) crea por un junction sin problema.
    # Es la virtualizacion de AppData de la app MSIX que lanza las baterias, y
    # esta bateria vive en %TEMP%. Aqui se mide el juicio de la casa y la
    # escritura del recorte
    os.makedirs(os.path.join(REAL, '__delphi-temp', 'ana', 'designer'), exist_ok=True)
    CAPS3 = os.path.join(REAL, '__delphi-temp', '**', 'designer', '*.png')
    antes = set(glob.glob(CAPS3, recursive=True))
    r = preview(srv3, path=os.path.join(POR_ENLACE, 'Prueba.dfm'), component='Panel1', inline='false')
    j = J(r)
    nuevos = sorted(set(glob.glob(CAPS3, recursive=True)) - antes)
    uno = nuevos[0] if len(nuevos) == 1 else ''
    check('R1 una raiz declarada a traves de un junction: el recorte (344x41) en su carpeta de capturas',
          j.get('componentRect') == RECT and tamano(uno) == (344, 41), (r[:400], nuevos, tamano(uno)))
finally:
    srv3.cierra()
    quita_enlace(POR_ENLACE)

check('las victimas de fuera, intactas al acabar', not contenido(FUERA) or
      all(os.path.isdir(p) and p in [os.path.join(FUERA, v) for v in ('v1', 'v3', 'v4')]
          for p in contenido(FUERA)), contenido(FUERA))
mc.fin('captura por las puertas 1182')
