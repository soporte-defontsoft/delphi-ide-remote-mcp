# -*- coding: utf-8 -*-
"""Una raiz que es la UNIDAD ENTERA (Roots=N:\\), a fondo (1.9.0).

Con "un sitio se declara con su letra", la raiz natural de un recurso de red
dedicado al codigo es la unidad entera. El servidor guarda sus sitios con la
barra final y, para compararlos y ensenarlos, se la quitaba: de "N:\\" quedaba
"N:", que para Windows no es la raiz sino la carpeta ACTUAL de esa unidad.
Encontrado el 1-oct-2026 en produccion: delphi_workspace ensenaba la raiz como
"srvn:" y eso, devuelto, era GUARD-021 ("is a RELATIVE path").

El banco: unidades de prueba hechas con subst sobre carpetas temporales (se
quitan al acabar, y las de una pasada anterior, al empezar). El servidor corre
DESDE la unidad que es su raiz, con su carpeta actual en una subcarpeta: es el
caso en que "Q:" deja de coincidir con "Q:\\" (un servidor instalado en la
misma unidad que tiene entera por raiz). Una unidad de subst no es un volumen:
su ruta real es la carpeta de debajo; lo que es propio de la raiz de un
volumen de verdad no se mide aqui.

  D1  delphi_workspace ensena la raiz, la referencia y el vault con su barra
      (srvq:\\), y lo que ensena se puede devolver
  D2  listar, leer y buscar en la raiz ven la UNIDAD, no la carpeta actual
  D3  crear, editar, mover y borrar en la raiz: el fichero, su copia y la
      papelera caen donde toca
  D4  la raiz misma no se borra ni se mueve, y lo dice con su barra
  D5  fuera sigue fuera, y la negativa nombra las raices con su barra; la
      unidad a secas (srvq:) no es la raiz: se niega, diciendo cual es
  D6  una REFERENCIA que es una unidad entera: se lee y no se escribe
  D7  un ReadOnlyPaths relativo bajo la raiz-unidad: se lee y no se escribe
  D8  un VAULT que es una unidad entera: las tools del vault lo leen y las de
      codigo no entran
  D9  (no se mide: git nombra una unidad de subst por la carpeta de debajo)
  D10 un proyecto en la raiz-unidad: se crea, el motor contesta y compila
  D11 la carpeta temporal del servidor es la de la raiz, no la de la carpeta
      actual: una captura dejada en <unidad>:\\__delphi-temp se consume al
      recogerla; y delphi_package de la raiz sin outfile dice que hace falta
      (una unidad no tiene "al lado")
  D12 una raiz escrita como la unidad a secas (Roots=Q:) es la raiz de la
      unidad, no la carpeta desde la que corre el servidor; y un ReadOnlyPaths
      escrito igual protege la unidad, no esa carpeta
  D13 cada workspace, con SUS letras: la primera llamada al servidor la hace
      otro workspace, con su raiz en otra unidad, y todo lo de arriba sigue
      valiendo (las letras servidas se calculaban una vez por proceso, con el
      de la primera llamada: a este le salia su raiz como srv0:\\)
  D14 purgar la ULTIMA copia de una papelera no deja sus carpetas vacias en
      la raiz (deleted, la del dia, __delphi-patch): se vieron en la raiz de
      un NAS
  D15 un enlace borrado va a la papelera como enlace: purgar un fichero A
      TRAVES de el no borra el fichero vivo de detras (se borraba para siempre)
  y, en el codigo: la barra final de una ruta solo la quitan las dos
      funciones de Lsp.NetDrives

Usage:  python tests/test_raiz_unidad.py [path-to-DelphiLspMcp.exe]
"""
import atexit, ctypes, glob, os, re, string, subprocess, winreg
import mcp_cliente as mc
from mcp_cliente import check

BASE_NOMBRE = 'raiz_unidad'


def substs():
    """{letra: carpeta} de las unidades de subst de esta sesion."""
    out = subprocess.run(['subst'], capture_output=True, text=True, errors='replace').stdout
    res = {}
    for linea in out.splitlines():
        if ': => ' in linea:
            letra, carpeta = linea.split(': => ', 1)
            res[letra.strip()[0].upper()] = carpeta.strip()
    return res


def quita(letra):
    subprocess.run(['subst', letra + ':', '/d'], capture_output=True)


# las de una pasada anterior que no llego a quitarlas
for _l, _c in substs().items():
    if ('\\%s\\' % BASE_NOMBRE) in _c + '\\':
        quita(_l)

BASE = mc.carpeta(BASE_NOMBRE)


LETRAS = mc.letras_libres(3)
if len(LETRAS) < 3:
    raise RuntimeError('esta maquina no tiene tres letras libres: %s' % LETRAS)
Q, R, V = LETRAS
UNIDAD = os.path.join(BASE, 'unidad')        # sera Q:\  la raiz
REFERENCIA = os.path.join(BASE, 'referencia')  # sera R:\  la referencia
VAULT = os.path.join(BASE, 'vault')          # sera V:\  el vault
FUERA = os.path.join(BASE, 'fuera')
for d in (UNIDAD, REFERENCIA, VAULT, FUERA):
    os.makedirs(d)
PUESTAS = []
atexit.register(lambda: [quita(l) for l in PUESTAS])
for letra, carpeta in ((Q, UNIDAD), (R, REFERENCIA), (V, VAULT)):
    r = subprocess.run(['subst', letra + ':', carpeta], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.isdir(letra + ':\\'):
        raise RuntimeError('subst %s: %s no va: %s' % (letra, carpeta, r.stdout + r.stderr))
    PUESTAS.append(letra)

RQ, RR, RV = Q + ':\\', R + ':\\', V + ':\\'
VQ, VR, VV = ['srv%s:\\' % l.lower() for l in (Q, R, V)]

SRV = os.path.join(RQ, 'srv')                 # el servidor vive EN la raiz-unidad
os.makedirs(os.path.join(SRV, 'aqui'))
EXE = mc.copia_exe(SRV)
open(os.path.join(RQ, 'raiz.txt'), 'w').write('en la raiz de la unidad AGUJA-RU\n')
os.makedirs(os.path.join(RQ, 'vendor'))
open(os.path.join(RQ, 'vendor', 'v.txt'), 'w').write('de terceros\n')
os.makedirs(os.path.join(RQ, 'sub'))
open(os.path.join(RR, 'ref.txt'), 'w').write('de referencia\n')
open(os.path.join(RV, 'AGENTS-VAULT.md'), 'w').write('# reglas del vault RU\n')
open(os.path.join(RV, 'nota.md'), 'w').write('# nota\nuno\n')
open(os.path.join(FUERA, 'victima.txt'), 'w').write('no me toques\n')

TOK = 'ru'
open(os.path.join(SRV, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.RU]', 'Token=%s' % TOK,
    'Roots=%s' % RQ,
    'ReadOnlyRoots=%s' % RR,
    'ReadOnlyPaths=vendor',
    'VaultPath=%s' % RV,
    'VaultReadOnly=0',
    '',
    # la unidad A SECAS es su raiz: con el servidor en esa unidad,
    # GetFullPath("Q:") era la carpeta desde la que corre
    '[Workspace.RU2]', 'Token=ru2',
    'Roots=%s:' % Q,
    '',
    # ...y lo mismo en un ReadOnlyPaths: protege la unidad, no esa carpeta
    '[Workspace.RU3]', 'Token=ru3',
    'Roots=%s' % RQ,
    'ReadOnlyPaths=%s:' % Q,
    '',
    # el de la PRIMERA llamada, con su raiz en otra unidad (D13)
    '[Workspace.RU0]', 'Token=ru0',
    'Roots=%s' % FUERA,
    '',
]))

PORT = mc.puerto_libre()
SALIDA = open(os.path.join(BASE, 'arranque.txt'), 'wb')
# la carpeta ACTUAL del servidor, una subcarpeta de la unidad que es su raiz
proc = mc.lanza_http(EXE, PORT, mc.entorno(), stdout=SALIDA, stderr=subprocess.STDOUT,
                     cwd=os.path.join(SRV, 'aqui'))
# D13: la primera llamada, de OTRO workspace con su raiz en otra unidad
c0 = mc.Http(PORT, 'ru0', t=180, respaldo_json=True)
c0.session('raiz-unidad-0')
r0 = c0.call_msg('delphi_workspace', {}, 120)
cli = mc.Http(PORT, TOK, t=180, respaldo_json=True)
cli.session('raiz-unidad')


def llama(tool, args, t=300):
    r = cli.call_msg(tool, args, t)
    res = (r or {}).get('result', {})
    return res, res.get('structuredContent') or {}, mc.texto(r, True)


def bien(res, t):
    return not res.get('isError') and not mc.fallo(t)


try:
    sc0 = ((r0 or {}).get('result') or {}).get('structuredContent') or {}
    check('D13 (control) la primera llamada al servidor la hizo otro workspace, con su raiz en %s:' % FUERA[0],
          sc0.get('roots') == [mc.virtual(FUERA)], sc0.get('roots'))
    # D1 lo que ensena, y que se puede devolver (y D13: con SUS letras)
    res, sc, t = llama('delphi_workspace', {})
    check('D1 delphi_workspace ensena la raiz-unidad con su barra (%s)' % VQ,
          sc.get('roots') == [VQ], sc.get('roots'))
    check('D1 ...y la referencia-unidad (%s)' % VR, sc.get('readOnlyRoots') == [VR], sc.get('readOnlyRoots'))
    raiz = (sc.get('roots') or [VQ])[0]
    res, sc, t = llama('delphi_list', {'root': raiz, 'dirs': True})
    dirs = [f['path'].lower() for f in mc.ficheros(sc, hijos='dirs')]
    check('D1 ...y la raiz, devuelta tal cual, se lista: las carpetas de la UNIDAD',
          bien(res, t) and (VQ + 'sub').lower() in dirs and (VQ + 'srv').lower() in dirs
          and (VQ + 'vendor').lower() in dirs, t[:300])
    # el dir TAL CUAL llega, con su barra: una raiz-unidad sin ella (srvq:) es
    # la carpeta actual para Windows (GUARD-021), y componiendo la ruta por el
    # servidor el lector la tapaba (revisor de baterias de la 1.15.0)
    check('D1 ...y la carpeta del organizador es la raiz con su barra (%s), no %s' % (VQ, VQ.rstrip('\\')),
          [g.get('dir') for g in sc.get('folders') or []] == [VQ], sc.get('folders'))

    # D2 leer y buscar
    res, sc, t = llama('delphi_read', {'path': VQ + 'raiz.txt'})
    check('D2 leer un fichero de la raiz', bien(res, t) and 'AGUJA-RU' in t, t[:200])
    res, sc, t = llama('delphi_search', {'root': VQ, 'query': 'AGUJA-RU', 'pattern': '*.txt'})
    check('D2 buscar desde la raiz encuentra lo de la UNIDAD',
          bien(res, t) and any('raiz.txt' in h.get('path', '') for h in mc.aciertos(sc)), t[:300])
    res, sc, t = llama('delphi_list', {'root': VQ, 'pattern': '*.txt'})
    rutas = [f.get('path', '').lower() for f in mc.ficheros(sc)]
    check('D2 listar ficheros desde la raiz: con su unidad y su barra',
          bien(res, t) and (VQ + 'raiz.txt').lower() in rutas
          and VQ in [g.get('dir') for g in sc.get('folders') or []], t[:300])

    # D3 escribir: crear, editar, mover, borrar
    res, sc, t = llama('delphi_textedit', {'path': VQ + 'nuevo.txt', 'create': True, 'content': 'uno\ndos\n'})
    check('D3 crear en la raiz: el fichero cae en la raiz de la unidad',
          bien(res, t) and os.path.isfile(os.path.join(UNIDAD, 'nuevo.txt'))
          and not os.path.exists(os.path.join(SRV, 'aqui', 'nuevo.txt')), t[:300])
    res, sc, t = llama('delphi_textedit', {'path': VQ + 'nuevo.txt', 'old': 'uno', 'new': 'UNO'})
    check('D3 editarlo: su copia, en la papelera de la raiz',
          bien(res, t) and open(os.path.join(UNIDAD, 'nuevo.txt')).read().startswith('UNO')
          and os.path.isdir(os.path.join(UNIDAD, '__delphi-patch'))
          and not os.path.exists(os.path.join(SRV, 'aqui', '__delphi-patch')), t[:300])
    res, sc, t = llama('delphi_move', {'path': VQ + 'nuevo.txt', 'dest': VQ + 'sub\\movido.txt'})
    check('D3 moverlo a una carpeta de la raiz',
          bien(res, t) and os.path.isfile(os.path.join(UNIDAD, 'sub', 'movido.txt'))
          and not os.path.exists(os.path.join(UNIDAD, 'nuevo.txt')), t[:300])
    res, sc, t = llama('delphi_move', {'path': VQ + 'sub\\movido.txt', 'dest': VQ + 'vuelta.txt'})
    check('D3 ...y de vuelta a la raiz misma',
          bien(res, t) and os.path.isfile(os.path.join(UNIDAD, 'vuelta.txt')), t[:300])
    res, sc, t = llama('delphi_delete', {'path': VQ + 'vuelta.txt'})
    check('D3 borrarlo: a la papelera de la raiz',
          bien(res, t) and not os.path.exists(os.path.join(UNIDAD, 'vuelta.txt'))
          and VQ.lower() in t.lower() and '__delphi-patch' in t, t[:300])

    # D4 la raiz misma
    res, sc, t = llama('delphi_delete', {'path': VQ})
    check('D4 la raiz-unidad no se borra, y lo dice con su barra',
          mc.abre(t, 'SR_ROOT_ITSELF_FMT') and ('"%s"' % VQ) in t
          and os.path.isfile(os.path.join(UNIDAD, 'raiz.txt')), t[:300])
    res, sc, t = llama('delphi_move', {'path': VQ, 'dest': VQ + 'sub\\otra'})
    check('D4 ...ni se mueve, con la misma negativa',
          mc.abre(t, 'SR_ROOT_ITSELF_FMT') and ('"%s"' % VQ) in t
          and os.path.isfile(os.path.join(UNIDAD, 'raiz.txt')), t[:300])

    # D5 fuera, y la unidad a secas
    res, sc, t = llama('delphi_read', {'path': os.path.join(FUERA, 'victima.txt')})
    check('D5 fuera sigue fuera, y la negativa nombra la raiz con su barra',
          mc.abre(t, 'SR_JAIL_FMT') and VQ in t, t[:300])
    res, sc, t = llama('delphi_list', {'root': VQ[:-1], 'dirs': True})
    check('D5 la unidad a secas (%s) no es la raiz: se niega, y la negativa ensena la raiz con su barra' % VQ[:-1],
          mc.abre(t, 'SR_GUARD_RUTA_RELATIVA_FMT') and ('(%s)' % VQ) in t, t[:300])

    # D6 la referencia-unidad
    res, sc, t = llama('delphi_read', {'path': VR + 'ref.txt'})
    check('D6 una referencia que es una unidad entera se lee', bien(res, t) and 'de referencia' in t, t[:200])
    res, sc, t = llama('delphi_textedit', {'path': VR + 'x.txt', 'create': True, 'content': 'x\n'})
    check('D6 ...y no se escribe, y la negativa la nombra con su barra',
          mc.abre(t, 'SR_REFERENCE_ROOT_FMT') and t.count(VR) >= 2
          and not os.path.exists(os.path.join(REFERENCIA, 'x.txt')), t[:300])
    res, sc, t = llama('delphi_list', {'root': VR, 'pattern': '*.txt'})
    check('D6 ...y se lista desde su raiz',
          bien(res, t) and any('ref.txt' in f.get('path', '') for f in mc.ficheros(sc)), t[:300])

    # D7 ReadOnlyPaths relativo bajo la raiz-unidad
    res, sc, t = llama('delphi_read', {'path': VQ + 'vendor\\v.txt'})
    ok_lee = bien(res, t) and 'de terceros' in t
    res, sc, t = llama('delphi_textedit', {'path': VQ + 'vendor\\v.txt', 'old': 'de terceros', 'new': 'mio'})
    check('D7 un ReadOnlyPaths relativo bajo la raiz-unidad: se lee y no se escribe',
          ok_lee and mc.abre(t, 'SR_READONLY_PATH_FMT')
          and 'de terceros' in open(os.path.join(UNIDAD, 'vendor', 'v.txt')).read(), t[:300])

    # D8 el vault-unidad
    res, sc, t = llama('vault_read', {'path': 'nota.md'})
    check('D8 un vault que es una unidad entera: vault_read lee su nota', bien(res, t) and '2|uno' in t, t[:300])
    res, sc, t = llama('delphi_read', {'path': VV + 'nota.md'})
    check('D8 ...y las tools de codigo no entran en el: es el vault, no "fuera"',
          mc.abre(t, 'SR_VAULT_NOT_CODE') and 'uno' not in t, t[:300])
    res, sc, t = llama('vault_create', {'path': 'nueva.md', 'content': '# nueva\n'})
    check('D8 ...y vault_create escribe en su raiz',
          bien(res, t) and os.path.isfile(os.path.join(VAULT, 'nueva.md')), t[:300])

    # D9 git NO se mide aqui: para git una unidad de subst es la carpeta de
    # debajo, la nombra por ella y la jaula, que juzga por lo declarado, la
    # niega (GIT-041; es lo que el README dice de una letra de subst desde la
    # 1.8.2). Con una letra de RED que es la raiz entera, la regla que traduce
    # lo que contesta git la miden las unitarias (LspTests.Rutas,
    # LaRaizDeLaUnidadLlevaSuBarra)
    print('NOTA D9: git sobre una raiz-unidad no se mide con una unidad de subst (git la nombra '
          'por la carpeta de debajo: GIT-041, como dice el README de una letra de subst)')

    # D10 un proyecto
    PROY = VQ + 'proyecto'
    res, sc, t = llama('delphi_create', {'kind': 'project-console', 'name': 'RU', 'dir': PROY})
    ok = bien(res, t) and os.path.isfile(os.path.join(UNIDAD, 'proyecto', 'RU.dproj'))
    check('D10 un proyecto en la raiz-unidad se crea', ok, t[:300])
    res, sc, t = llama('delphi_projects', {'root': VQ})
    check('D10 ...delphi_projects lo encuentra desde la raiz', bien(res, t) and 'RU.dproj' in t, t[:300])
    res, sc, t = llama('delphi_symbols', {'path': PROY + '\\RU.dpr'})
    check('D10 ...el motor contesta (symbols)', bien(res, t), t[:300])
    res, sc, t = llama('delphi_build', {'project': PROY + '\\RU.dproj', 'platform': 'Win64'}, 600)
    check('D10 ...y compila', bien(res, t) and sc.get('success') is True, t[:400])

    # D12 la raiz escrita como la unidad a secas
    c2 = mc.Http(PORT, 'ru2', t=180, respaldo_json=True)
    c2.session('raiz-unidad-2')
    r = c2.call_msg('delphi_workspace', {}, 120)
    sc2 = ((r or {}).get('result') or {}).get('structuredContent') or {}
    r = c2.call_msg('delphi_read', {'path': VQ + 'raiz.txt'}, 120)
    check('D12 una raiz escrita como la unidad a secas (Roots=%s:) es la raiz de la unidad' % Q,
          sc2.get('roots') == [VQ] and 'AGUJA-RU' in mc.texto(r, True),
          '%s | %s' % (sc2.get('roots'), mc.texto(r, True)[:200]))
    c3 = mc.Http(PORT, 'ru3', t=180, respaldo_json=True)
    c3.session('raiz-unidad-3')
    t = mc.texto(c3.call_msg('delphi_textedit', {'path': VQ + 'ro3.txt', 'create': True, 'content': 'x\n'}, 120), True)
    check('D12 ...y un ReadOnlyPaths escrito asi (ReadOnlyPaths=%s:) protege la unidad entera' % Q,
          mc.abre(t, 'SR_READONLY_PATH_FMT') and not os.path.exists(os.path.join(UNIDAD, 'ro3.txt')), t[:300])

    # D11 la temporal
    res, sc, t = llama('delphi_package', {'dir': VQ + 'sub', 'outfile': VQ + 'sub.zip'})
    check('D11 la carpeta temporal y lo que el servidor crea no caen en su carpeta actual',
          bien(res, t) and os.path.isfile(os.path.join(UNIDAD, 'sub.zip'))
          and sorted(os.listdir(os.path.join(SRV, 'aqui'))) == [],
          '%s | aqui=%s' % (t[:200], os.listdir(os.path.join(SRV, 'aqui'))))
    # la casa de los entregables (CasasDeEntregables) es <unidad>:\__delphi-temp:
    # una captura de alli es NUESTRA y se consume al recogerla. Con "Q:" a
    # secas la casa era la __delphi-temp de la carpeta actual
    CAP = os.path.join(RQ, '__delphi-temp', 'desktop', 'cap.png')
    os.makedirs(os.path.dirname(CAP), exist_ok=True)
    open(CAP, 'wb').write(b'\x89PNG\r\n\x1a\n' + b'0' * 64)
    res, sc, t = llama('delphi_fetch', {'path': VQ + '__delphi-temp\\desktop\\cap.png', 'offset': 0})
    check('D11 ...y la casa de los entregables es la __delphi-temp de la raiz-unidad: su captura se consume al recogerla',
          mc.como_json(t).get('consumedOnServer') is True and not os.path.exists(CAP), t[:300])
    # D14 la papelera de una raiz, vacia otra vez: no quedan sus carpetas
    f0 = os.path.join(FUERA, 'd14.txt')
    c0.call_msg('delphi_textedit', {'path': f0, 'create': True, 'content': 'x\n'}, 120)
    c0.call_msg('delphi_delete', {'path': f0}, 120)
    copias = [p for p in glob.glob(os.path.join(FUERA, '__delphi-patch', '*', 'deleted', '*'))
              if not mc.es_marca_dueno(os.path.basename(p))]
    t = mc.texto(c0.call_msg('delphi_delete', {'path': copias[0], 'purge': True}, 120), True) if copias else '(sin copia)'
    check('D14 purgar la ultima copia de la papelera no deja sus carpetas vacias en la raiz',
          len(copias) == 1 and not mc.fallo(t) and not os.path.exists(os.path.join(FUERA, '__delphi-patch')),
          '%s | %s | queda=%s' % (copias, t[:160], os.path.exists(os.path.join(FUERA, '__delphi-patch'))))
    # D15 la purga, por donde esta de verdad lo que le nombran
    VIVO = os.path.join(FUERA, 'vivo')
    os.makedirs(VIVO)
    open(os.path.join(VIVO, 'dato.txt'), 'w').write('vivo\n')
    LNK = os.path.join(FUERA, 'lnk')
    subprocess.run(['cmd', '/c', 'mklink', '/J', LNK, VIVO], capture_output=True)
    c0.call_msg('delphi_delete', {'path': LNK}, 120)
    enl = [p for p in glob.glob(os.path.join(FUERA, '__delphi-patch', '*', 'deleted', 'lnk*')) if os.path.isdir(p)]
    t = (mc.texto(c0.call_msg('delphi_delete', {'path': os.path.join(enl[0], 'dato.txt'), 'purge': True}, 120), True)
         if enl else '(el enlace no esta en la papelera)')
    check('D15 purgar un fichero a traves de un enlace que esta en la papelera no borra el fichero vivo de detras',
          len(enl) == 1 and mc.abre(t, 'SR_FILE_PURGE_ONLY_TRASH') and os.path.isfile(os.path.join(VIVO, 'dato.txt')),
          '%s | vivo=%s' % (t[:200], os.path.isfile(os.path.join(VIVO, 'dato.txt'))))
    for p in enl:
        os.rmdir(p)  # quita el enlace de la papelera, nunca lo de detras
    res, sc, t = llama('delphi_package', {'dir': VQ})
    check('D11 delphi_package de la raiz-unidad sin outfile: dice que hace falta (PKG-004), no "ruta relativa"',
          mc.abre(t, 'SR_PACKAGE_RAIZ_SIN_OUTFILE_FMT') and ('(%s)' % VQ) in t, t[:300])
finally:
    proc.kill()
    try:
        proc.wait(10)
    except Exception:
        pass
    SALIDA.close()
    for letra in PUESTAS:
        quita(letra)

quedan = [l for l in PUESTAS if l in substs()]
check('las unidades de prueba se han quitado', not quedan, quedan)

# La regla, en el codigo: la barra final solo la quitan las dos funciones de
# Lsp.NetDrives (SinBarraFinal para usar o ensenar una ruta, PrefijoSinBarra
# para hacer cuentas con su texto). Una llamada suelta a la de la RTL es por
# donde una raiz-unidad vuelve a quedarse en "N:".
fuentes = glob.glob(os.path.join(mc.REPO, 'src', 'Server', '*.pas'))
sueltos = []
for f in fuentes:
    if os.path.basename(f).lower() == 'lsp.netdrives.pas':
        continue
    codigo = mc.pascal_sin_comentarios(open(f, encoding='utf-8', errors='replace').read())
    if re.search(r'\bExcludeTrailingPathDelimiter\b', codigo):
        sueltos.append(os.path.basename(f))
check('nadie quita la barra final por su cuenta (solo Lsp.NetDrives llama a la de la RTL)',
      len(fuentes) > 30 and not sueltos, sueltos or len(fuentes))

mc.fin('raiz-unidad battery')
