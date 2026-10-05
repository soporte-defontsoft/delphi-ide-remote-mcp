# -*- coding: utf-8 -*-
"""Un sitio se declara con su LETRA, y las letras de red las conecta el
servidor (1.9.0; Lsp.NetDrives y el cargador de Lsp.Guard).

Un servicio no ve las letras de red del escritorio aunque corra con la misma
cuenta (medido el 1-oct-2026): una raiz en una letra asi fallaba ("the drive
cannot be found") y el arranque no decia nada. Ahora el arranque mira la letra
de cada raiz, referencia y vault de sus workspaces: la que no ve la busca en
los mapeos persistentes de la cuenta (HKCU\\Network), la conecta, comprueba
que entra, y lo dice en el log.

La regla de la conexion, con la maquina simulada, la miden las unitarias
(LspTests.LetrasDeRed). Conectar de verdad NO se mide aqui ni alli: haria
falta un mapeo persistente sin conectar, y esta bateria no toca ni el registro
ni las unidades de la maquina. Lo midio el log de un servicio instalado asi.
Aqui, el arranque de verdad: QUE sitios mira y que dice.

  L1  (guarda) el servidor atiende con una raiz en una letra que no existe:
      lo declarado sigue declarado
  L2  el arranque AVISA de esa raiz: la letra, que no hay mapeo, y la raiz
  L3  lo mismo con una referencia (ReadOnlyRoots)
  L4  un workspace CERRADO no cuenta: de su letra no se dice nada
  L5  de las raices en unidades locales no se dice nada
  L7  las raices del modo local (las del entorno) tambien se miran
  L8  ...y el vault (VaultPath)
  L6  una raiz en una unidad de red CONECTADA: el arranque dice que se entra,
      y de una que no existe alli, que no se abre. Solo si
      DELPHI_MCP_TEST_NETDIR nombra una carpeta de una unidad de red conectada
      (la misma variable que J17 de test_git_jaula)

Y la otra mitad (David, 1-oct-2026): una entrada que no sea una ruta con
letra - una ruta de red, un prefijo de dispositivo - no se carga, y el arranque
lo dice. El host de estas pruebas no existe: nada de esto sale a la red.

  U1  un workspace cuya unica raiz es una ruta de red queda CERRADO (401), en
      todas sus escrituras: \\\\host\\..., //host/..., \\\\?\\UNC\\..., \\\\.\\UNC\\...,
      \\\\?\\GLOBALROOT\\... y \\\\?\\C:\\...; y la que empieza por UNA barra
      (\\carpeta: la raiz de la unidad actual del proceso)
  U2  el arranque AVISA de cada una: la clave y la entrada
  U3  el que mezcla en Roots letra y ruta de red carga lo de letra y sigue
      atendiendo: sus raices son las de letra
  U5  ...y la ruta de red que NO se cargo esta fuera para su agente (GUARD-002)
  U4  una PROTECCION (ReadOnlyRoots, ReadOnlyPaths, VaultPath) que no se carga
      - una ruta de red, o una entrada que no parsea - CIERRA el workspace
      (401): sin ella, lo que nombra podria escribirse. El aviso lo dice.
      Tambien la que empieza por una barra (ReadOnlyPaths=\\dentro se cargaba
      contra la unidad del proceso y "dentro" se escribia: medido)
  U6  las del entorno (modo local, por stdio): una raiz en ruta de red no se
      carga y la de letra sigue; una proteccion que no se carga lo cierra
      todo, con SU motivo (GUARD-030): la jaula antes de mirar nada en el
      disco, delphi_projects sin root, y el vault del entorno, que no se lee
  U7  un cliente local con el token de un workspace CERRADO no pasa al modo
      local de confianza (leia toda la maquina): queda cerrado (GUARD-030).
      Con el de uno abierto, su jaula
  U8  el cierre del modo local (una proteccion del entorno que no se cargo,
      o unas DELPHI_MCP_ROOTS de las que no cargo ninguna) no le toca a quien
      entra con el token de un workspace abierto
  U9  el token de LECTURA de un workspace en el entorno del servidor ata al
      cliente LOCAL: quien entra por HTTP con su token de escritura, escribe
      (dejaba el servidor entero en solo lectura)

Y una entrada de ReadOnlyPaths que cae FUERA de las raices de su workspace
(1.9.1). ReadOnlyPaths marca de solo lectura lo que ya esta DENTRO de la
jaula; para leer una carpeta de fuera la clave es ReadOnlyRoots. Medido el
2-oct-2026 en la VM: dos workspaces con ReadOnlyPaths=L:\\... para leer codigo
de fuera, y ninguno lo leia, sin una palabra en el arranque.

  R1  esa entrada se carga: el workspace atiende, otro workspace cuya raiz la
      contiene no la borra (es un lugar que no se toca), y su agente no la
      lee: esta fuera (GUARD-002)
  R2  el arranque lo AVISA con la clave y la entrada, y dice que la clave para
      leer fuera es ReadOnlyRoots; una unidad entera sale con su barra (X:\\);
      la que esta en la raiz por el texto y sale por un junction, tambien (la
      jaula mide la ruta real); la relativa que sale al mismo sitio desde dos
      raices, una vez; de una seccion sin token, que se ignora, nada
  R3  de las que caen dentro no se dice nada: absoluta dentro de la raiz,
      relativa (la carpeta de cada raiz), dentro de una referencia propia, la
      escrita en 8.3 cuya forma larga esta dentro, la que CONTIENE la raiz
      (la deja entera de solo lectura: se mide) y la escrita por la ruta real
      de una raiz que es un junction. La que contiene la raiz por el TEXTO
      tambien protege: no se avisa, con nombres largos o alias 8.3.
      La medida anterior dependia del TEMP corto (corregida el 4-oct-2026).
  R4  las del entorno (modo local): con DELPHI_MCP_ROOTS se avisa igual, con
      la clave del entorno (DELPHI_MCP_READONLY_ROOTS), sin cerrar nada; sin
      raices no hay "fuera" (el modo local de confianza lee toda la maquina)
      y no se dice nada
  (R2-R4 vienen tambien de la primera revision de la 1.9.1: el primer aviso
  comparaba por el texto, y una entrada que contenia la raiz o un junction
  eran un aviso falso o uno que faltaba)

Usage:  python tests/test_letras_red.py [path-to-DelphiLspMcp.exe]
"""
import ctypes, os, string, subprocess, winreg
import mcp_cliente as mc
from mcp_cliente import check


BASE = mc.carpeta('letras_red')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
JAIL2 = os.path.join(BASE, 'jail2')
os.makedirs(EXEDIR)
os.makedirs(JAIL)
os.makedirs(os.path.join(JAIL2, 'dentro'))
EXE = mc.copia_exe(EXEDIR)

LIBRES = mc.letras_libres(5)
if len(LIBRES) < 5:
    raise RuntimeError('esta maquina no tiene cinco letras libres: %s' % LIBRES)
FALTA, REF, CERRADA, ENTORNO, VAULT = LIBRES
RAIZ_FALTA = '%s:\\nada' % FALTA
RAIZ_REF = '%s:\\referencia' % REF
RAIZ_CERRADA = '%s:\\cerrada' % CERRADA
RAIZ_ENTORNO = '%s:\\entorno' % ENTORNO
RAIZ_VAULT = '%s:\\vault' % VAULT

NETDIR = os.environ.get('DELPHI_MCP_TEST_NETDIR', '').strip().rstrip('\\')
NET_FALTA = NETDIR + '\\no-existe-lr' if NETDIR else ''

# las entradas que NO son una ruta con letra (un host que no existe: no se
# sale a la red). nombre del workspace -> su unica raiz
SIN_LETRA = {
    'Unc': '\\\\servidor-lr\\recurso\\proyectos',
    'Barras': '//servidor-lr/recurso/barras',
    'Largo': '\\\\?\\UNC\\servidor-lr\\recurso\\largo',
    'Punto': '\\\\.\\UNC\\servidor-lr\\recurso\\punto',
    'Global': '\\\\?\\GLOBALROOT\\Device\\Mup\\servidor-lr\\recurso\\global',
    'Dispositivo': '\\\\?\\C:\\dispositivo-lr',
    # relativa a la carpeta ACTUAL de esa unidad: no es un sitio
    'DeUnidad': '%s:carpeta-lr' % JAIL[0],
    'Comodin': os.path.join(JAIL, 'proy*'),
    # la raiz de la unidad ACTUAL del proceso: tampoco
    'DeRaiz': '\\proyectos-lr',
    'DeRaiz2': '/proyectos-lr',
    # ...ni la RELATIVA: se cargaba contra la carpeta del proceso
    'Relativa': 'proyectos-lr',
    # ...ni la que, escrita con su letra, Windows completa como un DISPOSITIVO
    # (un nombre reservado: X:\carpeta\nul es \\.\nul): la regla se mira
    # tambien sobre la ruta ya completa
    'Reservado': '%s:\\carpeta-lr\\nul' % JAIL[0],
}
UNC_RAIZ = '\\\\servidor-lr\\recurso\\otra'
UNC_REF = '\\\\servidor-lr\\recurso\\ref'
UNC_RO = '\\\\servidor-lr\\recurso\\solo'
UNC_VAULT = '\\\\servidor-lr\\recurso\\vault'
UNC_ENTORNO = '\\\\servidor-lr\\recurso\\entorno'
COMODIN = 'dentro\\*'
# workspace -> (clave, entrada): una proteccion que no se carga
PROTEGEN = {
    'Protege': ('ReadOnlyRoots', UNC_REF),
    'Protege2': ('ReadOnlyPaths', UNC_RO),
    'Protege3': ('ReadOnlyPaths', COMODIN),
    'Protege4': ('VaultPath', UNC_VAULT),
    # un comodin se cargaba tal cual, no casaba con nada y no protegia nada
    'Protege5': ('ReadOnlyRoots', os.path.join(JAIL, 'ref*')),
    'Protege6': ('VaultPath', os.path.join(JAIL, 'vault?')),
    # ...y la que no parsea (un caracter que Windows no admite en una ruta)
    'Protege7': ('ReadOnlyPaths', 'dentro\\a|b'),
    # ...y la que empieza por una barra: es la raiz de la unidad actual del
    # proceso, no "dentro" de la raiz del workspace (se cargaba, sin aviso, y
    # lo que el operador creia protegido se escribia)
    'Protege8': ('ReadOnlyPaths', '\\dentro'),
    'Protege9': ('ReadOnlyRoots', '\\ref-lr'),
    'Protege10': ('VaultPath', '/vault-lr'),
    # ...y la relativa, que solo vale en ReadOnlyPaths ("vendor" de cada raiz)
    'Protege11': ('ReadOnlyRoots', 'ref-lr'),
    'Protege12': ('VaultPath', 'vault-lr'),
    'Protege13': ('ReadOnlyPaths', '%s:\\carpeta-lr\\nul' % JAIL[0]),
}


def forma(ruta, larga):
    """La forma larga, o la 8.3, de una ruta que existe ('' si Windows no la da)."""
    k = ctypes.windll.kernel32
    buf = ctypes.create_unicode_buffer(1024)
    return buf.value if (k.GetLongPathNameW if larga else k.GetShortPathNameW)(ruta, buf, 1024) else ''


# (R) ReadOnlyPaths fuera de las raices de su workspace: workspace -> (raiz, lineas)
FUERA_RO = os.path.join(JAIL, 'fuera-ro')
os.makedirs(FUERA_RO)
os.makedirs(os.path.join(JAIL, 'sub-ro'))
JAIL2_LARGO = forma(JAIL2, True) or JAIL2
CORTO_RO = forma(os.path.join(JAIL2, 'dentro'), False)
# solo si el volumen da nombres 8.3 y el corto es otro texto que el largo
HAY_CORTO = '~' in CORTO_RO and CORTO_RO.lower() != os.path.join(JAIL2_LARGO, 'dentro').lower()


def enlace(link, destino):
    """Un junction de Windows (mklink /J): True si quedo hecho."""
    subprocess.run(['cmd', '/c', 'mklink', '/J', link, destino], capture_output=True)
    return os.path.isdir(link)


# una raiz que ES un junction a JAIL2; uno DENTRO de JAIL2 que sale fuera (a
# otra carpeta que FUERA_RO: si apuntase a ella, la protegeria tambien y el
# check del borrado de R1 tendria dos protectores; segunda revision); y una
# caja con una raiz dentro que es un junction a JAIL2
ENLACE_RAIZ = os.path.join(BASE, 'raiz-enlace')
ENLAZADA_RO = os.path.join(JAIL, 'enlazada-ro')
os.makedirs(ENLAZADA_RO)
ENLACE_FUERA = os.path.join(JAIL2, 'ext')
CAJA = os.path.join(BASE, 'caja')
os.makedirs(CAJA)
CAJA_RAIZ = os.path.join(CAJA, 'proj')
HAY_ENLACES = (enlace(ENLACE_RAIZ, JAIL2) and enlace(ENLACE_FUERA, ENLAZADA_RO)
               and enlace(CAJA_RAIZ, JAIL2))
COMUN_RO = os.path.join(BASE, 'comun-ro')
SOLO = {
    'SoloFuera': (JAIL2, ['ReadOnlyPaths=%s' % FUERA_RO]),
    'SoloUnidad': (JAIL2, ['ReadOnlyPaths=%s:\\' % FALTA]),
    'SoloDentro': (JAIL2, ['ReadOnlyPaths=%s' % os.path.join(JAIL2, 'dentro')]),
    'SoloRelativa': (JAIL2, ['ReadOnlyPaths=dentro']),
    'SoloEnRef': (JAIL2, ['ReadOnlyRoots=%s' % JAIL, 'ReadOnlyPaths=%s' % os.path.join(JAIL, 'sub-ro')]),
    # CONTIENE la raiz: la deja entera de solo lectura, no es de fuera
    'SoloEncima': (os.path.join(JAIL2, 'dentro'), ['ReadOnlyPaths=%s' % JAIL2]),
    # relativa que sale fuera, al mismo sitio desde las dos raices
    'SoloRelFuera': ('%s;%s' % (JAIL, JAIL2), ['ReadOnlyPaths=..\\comun-ro']),
}
if HAY_CORTO:
    SOLO['SoloCorto'] = (JAIL2_LARGO, ['ReadOnlyPaths=%s' % CORTO_RO])
if HAY_ENLACES:
    SOLO['SoloEnlaceRaiz'] = (ENLACE_RAIZ, ['ReadOnlyPaths=%s' % os.path.join(JAIL2, 'dentro')])
    SOLO['SoloEnlaceFuera'] = (JAIL2, ['ReadOnlyPaths=%s' % ENLACE_FUERA])
    # CONTIENE la raiz por el texto (la raiz sale a JAIL2): protege su
    # descendencia tambien por el alias 8.3, igual que por el nombre largo.
    SOLO['SoloEncimaTexto'] = (CAJA_RAIZ, ['ReadOnlyPaths=%s' % CAJA])
# de las que el arranque tiene que avisar; de las demas, nada
SE_AVISAN = ('SoloFuera', 'SoloUnidad', 'SoloRelFuera', 'SoloEnlaceFuera')
FUERA_FMT = mc.catalogo()['SL_GUARD_SOLO_LECTURA_FUERA_FMT']
# el trozo fijo del aviso, entre la clave y la entrada: para decir que NO esta
FUERA_TROZO = FUERA_FMT.split('%s')[1]

ini = [
    '[Workspace.Local]', 'Token=local-lr', 'Roots=%s' % JAIL,
    'ReadOnlyRoots=%s' % RAIZ_REF, 'VaultPath=%s' % RAIZ_VAULT, '',
    '[Workspace.Falta]', 'Token=falta-lr', 'Roots=%s' % RAIZ_FALTA, '',
    # el mismo valor en los dos tokens: el arranque lo CIERRA
    '[Workspace.Cerrado]', 'Token=cerrado-lr', 'ReadOnlyToken=cerrado-lr',
    'Roots=%s' % RAIZ_CERRADA, '',
    '[Workspace.Mixto]', 'Token=mixto-lr', 'Roots=%s;%s' % (JAIL2, UNC_RAIZ), '',
    '[Workspace.Lector]', 'Token=lector-lr', 'ReadOnlyToken=lector-ro-lr', 'Roots=%s' % JAIL2, '',
]
for nombre, raiz in SIN_LETRA.items():
    ini += ['[Workspace.%s]' % nombre, 'Token=%s-lr' % nombre.lower(), 'Roots=%s' % raiz, '']
for nombre, (clave, entrada) in PROTEGEN.items():
    ini += ['[Workspace.%s]' % nombre, 'Token=%s-lr' % nombre.lower(), 'Roots=%s' % JAIL2,
            '%s=%s' % (clave, entrada), '']
for nombre, (raiz, lineas) in SOLO.items():
    ini += ['[Workspace.%s]' % nombre, 'Token=%s-lr' % nombre.lower(), 'Roots=%s' % raiz] + lineas + ['']
# sin token: la seccion se ignora entera (y se dice), de su ReadOnlyPaths nada
ini += ['[Workspace.SoloSinToken]', 'Roots=%s' % JAIL2, 'ReadOnlyPaths=%s' % FUERA_RO, '']
if NETDIR:
    ini += ['[Workspace.Red]', 'Token=red-lr', 'Roots=%s;%s' % (NETDIR, NET_FALTA), '']
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join(ini))

PORT = mc.puerto_libre()
# (su salida va a un FICHERO: por una tuberia, los avisos de arranque la
# llenaban antes de que nadie la leyese y el servidor se quedaba escribiendo
# su log, sin llegar a escuchar)
SALIDA = open(os.path.join(BASE, 'arranque.txt'), 'wb')
proc = mc.lanza_http(EXE, PORT, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1',
                                            'DELPHI_MCP_ROOTS': RAIZ_ENTORNO,
                                            # (U9) el token de LECTURA de un workspace, en el entorno
                                            'DELPHI_MCP_READONLY_TOKEN': 'lector-ro-lr'}),
                     stdout=SALIDA, stderr=subprocess.STDOUT)


def init(tok):
    """El status HTTP del initialize con ese token: un 401 no lanza."""
    st, _, _ = mc.Http(PORT, tok).post({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "letras-red", "version": "1"}}})
    return st


try:
    check('L1 (guarda) el servidor atiende al workspace cuya raiz esta en una letra que no existe',
          init('falta-lr') == 200)
    check('L4a (control) el workspace de los dos tokens iguales esta cerrado: 401',
          init('cerrado-lr') == 401)

    sts = {n: init('%s-lr' % n.lower()) for n in SIN_LETRA}
    check('U1 un workspace cuya unica raiz no es una ruta con letra queda CERRADO: 401 en sus %d escrituras' % len(SIN_LETRA),
          all(st == 401 for st in sts.values()), sts)
    cm = mc.Http(PORT, 'mixto-lr', t=120, respaldo_json=True)
    cm.session('letras-red-mixto')
    r = cm.call_msg('delphi_workspace', {}, 120)
    sc = ((r or {}).get('result') or {}).get('structuredContent') or {}
    check('U3 el que mezcla letra y ruta de red atiende, y sus raices son las de letra',
          sc.get('roots') == [mc.virtual(JAIL2)], mc.texto(r, True)[:300])
    t = mc.texto(cm.call_msg('delphi_read', {'path': UNC_RAIZ + '\\f.txt'}, 120), True)
    check('U5 la ruta de red que no se cargo esta fuera para su agente (GUARD-002)',
          mc.abre(t, 'SR_JAIL_FMT'), t[:200])
    f9 = os.path.join(JAIL2, 'escrito-por-http.txt')
    t = mc.texto(cm.call_msg('delphi_textedit', {'path': f9, 'create': True, 'content': 'x\n'}, 120), True)
    check('U9 con el token de LECTURA de otro workspace en el entorno del servidor, quien entra por HTTP con su token de escritura ESCRIBE',
          os.path.isfile(f9) and not mc.fallo(t), t[:200])
    sts = {n: init('%s-lr' % n.lower()) for n in PROTEGEN}
    check('U4 una proteccion que no se carga CIERRA el workspace: 401 (referencia, solo lectura, vault, y sus comodines)',
          all(st == 401 for st in sts.values()), sts)
    sts = {n: init('%s-lr' % n.lower()) for n in SOLO}
    check('R1 (guarda) una entrada de ReadOnlyPaths fuera de las raices se carga: los %d workspaces atienden' % len(SOLO),
          all(st == 200 for st in sts.values()), sts)
    cf = mc.Http(PORT, 'solofuera-lr', t=120, respaldo_json=True)
    cf.session('letras-red-solo-fuera')
    t = mc.texto(cf.call_msg('delphi_list', {'root': FUERA_RO, 'dirs': True}, 120), True)
    check('R1 (guarda) ...pero su agente no la lee: esta fuera (GUARD-002)',
          mc.abre(t, 'SR_JAIL_FMT'), t[:200])
    cl = mc.Http(PORT, 'local-lr', t=120, respaldo_json=True)
    cl.session('letras-red-local')
    t = mc.texto(cl.call_msg('delphi_delete', {'path': FUERA_RO}, 120), True)
    check('R1 (guarda) ...y se CARGA: otro workspace cuya raiz la contiene no la borra (un lugar que no se toca)',
          (mc.abre(t, 'SR_MUDANZA_PROTEGIDA_FMT') or mc.abre(t, 'SR_BORRADO_DENEGADO_FMT'))
          and os.path.isdir(FUERA_RO), t[:300])
    ce = mc.Http(PORT, 'soloencima-lr', t=120, respaldo_json=True)
    ce.session('letras-red-solo-encima')
    fe = os.path.join(JAIL2, 'dentro', 'escrito-encima.txt')
    t = mc.texto(ce.call_msg('delphi_textedit', {'path': fe, 'create': True, 'content': 'x\n'}, 120), True)
    check('R3 (guarda) una entrada que CONTIENE la raiz la deja entera de solo lectura: no es de fuera',
          mc.abre(t, 'SR_READONLY_PATH_FMT') and not os.path.exists(fe), t[:200])
    if HAY_ENLACES:
        cx = mc.Http(PORT, 'soloencimatexto-lr', t=120, respaldo_json=True)
        cx.session('letras-red-solo-encima-texto')
        fx = os.path.join(CAJA_RAIZ, 'escrito-encima-texto.txt')
        t = mc.texto(cx.call_msg('delphi_textedit', {'path': fx, 'create': True, 'content': 'x\n'}, 120), True)
        check('R2 la que contiene la raiz por el texto protege aunque sea un junction a otro sitio',
              mc.abre(t, 'SR_READONLY_PATH_FMT') and
              not os.path.exists(os.path.join(JAIL2, 'escrito-encima-texto.txt')), t[:200])
finally:
    proc.kill()

proc.wait(10)
SALIDA.close()
out = open(os.path.join(BASE, 'arranque.txt'), encoding='utf-8', errors='replace').read()
lineas = out.splitlines()
AVISOS = [l for l in lineas if 'WARN' in l]


def de_letra(letra):
    return [l for l in lineas if ('drive %s:' % letra) in l]


def sin_mapeo(letra, sitio):
    return any(('drive %s:' % letra) in l and 'names no share' in l and sitio in l for l in AVISOS)


def avisa_de(avisos, clave, entrada, ademas=''):
    return any(clave in l and entrada in l and 'NOT loaded' in l and ademas in l for l in avisos)


check('L2 el arranque AVISA de la raiz en una letra que no existe: letra, sin mapeo y raiz',
      sin_mapeo(FALTA, RAIZ_FALTA), AVISOS)
check('L3 ...y de la referencia (ReadOnlyRoots) en otra', sin_mapeo(REF, RAIZ_REF), AVISOS)
check('L8 ...y del vault (VaultPath) en otra', sin_mapeo(VAULT, RAIZ_VAULT), AVISOS)
check('L4 un workspace CERRADO no cuenta: de su letra no se dice nada',
      not de_letra(CERRADA) and RAIZ_CERRADA not in out, de_letra(CERRADA))
check('L7 las raices del modo local (el entorno) tambien se miran',
      sin_mapeo(ENTORNO, RAIZ_ENTORNO), AVISOS)
check('L5 de la raiz en una unidad local no se dice nada',
      not de_letra(JAIL[0].upper()) and not any('is reachable' in l and JAIL in l for l in lineas),
      de_letra(JAIL[0].upper()))

faltan = [n for n, raiz in SIN_LETRA.items() if not avisa_de(AVISOS, '[Workspace.%s] Roots=' % n, raiz)]
check('U2 el arranque AVISA de cada raiz que no cargo: la clave y la entrada', not faltan, faltan)
check('U3 ...y el arranque avisa de la entrada de Roots que no cargo, sin cerrar a nadie',
      avisa_de(AVISOS, '[Workspace.Mixto] Roots=', UNC_RAIZ)
      and not any('[Workspace.Mixto]' in l and 'NOBODY' in l for l in AVISOS), AVISOS)
faltan = [n for n, (clave, entrada) in PROTEGEN.items()
          if not avisa_de(AVISOS, '[Workspace.%s] %s=' % (n, clave), entrada, 'NOBODY')]
check('U4 ...y el aviso dice la clave, la entrada y que no admite a nadie', not faltan, faltan)
check('R2 el arranque AVISA de la entrada de ReadOnlyPaths fuera de las raices: la clave, la entrada y ReadOnlyRoots',
      any(FUERA_FMT % ('[Workspace.SoloFuera] ReadOnlyPaths=', FUERA_RO, 'ReadOnlyRoots') in l for l in AVISOS),
      AVISOS)
check('R2 ...y una unidad entera sale con su barra (%s:\\, no %s:)' % (FALTA, FALTA),
      any(FUERA_FMT % ('[Workspace.SoloUnidad] ReadOnlyPaths=', FALTA + ':\\', 'ReadOnlyRoots') in l
          for l in AVISOS), AVISOS)
rel = [l for l in AVISOS if '[Workspace.SoloRelFuera]' in l and FUERA_TROZO in l]
check('R2 ...y la relativa que sale al mismo sitio desde dos raices, UNA vez',
      len(rel) == 1 and COMUN_RO in rel[0], rel)
if HAY_ENLACES:
    check('R2 ...y la que esta en la raiz por el texto y sale por un junction: la jaula mide la ruta real',
          any(FUERA_FMT % ('[Workspace.SoloEnlaceFuera] ReadOnlyPaths=', ENLACE_FUERA, 'ReadOnlyRoots') in l
              for l in AVISOS), AVISOS)
    check('R2 la que contiene la raiz por el texto no da el aviso de fuera: protege (medido arriba)',
          not any(FUERA_FMT % ('[Workspace.SoloEncimaTexto] ReadOnlyPaths=', CAJA, 'ReadOnlyRoots') in l
                  for l in AVISOS), AVISOS)
else:
    print('NOTA R2/R3: no se pudo crear un junction aqui: no se miden las entradas por un junction')
check('R2 (guarda) de una seccion sin token, que se ignora entera, no se dice nada (y la seccion se leyo)',
      not any('[Workspace.SoloSinToken]' in l and FUERA_TROZO in l for l in AVISOS)
      and any('SoloSinToken' in l for l in AVISOS), AVISOS)
dichos = [n for n in SOLO if n not in SE_AVISAN
          and any('[Workspace.%s]' % n in l and FUERA_TROZO in l for l in AVISOS)]
check('R3 (guarda) de las que caen dentro no se dice nada: absoluta, relativa, en una referencia propia, la que contiene la raiz%s%s'
      % (', en 8.3' if HAY_CORTO else '',
         ' y por la ruta real de una raiz que es un junction' if HAY_ENLACES else ''),
      not dichos, dichos)
if not HAY_CORTO:
    print('NOTA R3: este volumen no da un nombre 8.3 distinto para %s: no se mide la entrada escrita en 8.3'
          % os.path.join(JAIL2, 'dentro'))
if NETDIR:
    de_red = [l for l in lineas if NETDIR[0].upper() + ':' in l]
    check('L6 una raiz en una unidad de red conectada: el arranque dice que se entra',
          any(('Network drive %s:' % NETDIR[0].upper()) in l and NETDIR in l and 'is reachable' in l
              and 'WARN' not in l and NET_FALTA not in l for l in lineas), de_red)
    check('L6 ...y de una que no existe alli, que no se abre',
          any(NET_FALTA in l and 'could not be opened' in l for l in AVISOS), de_red)
else:
    print('NOTA L6: sin DELPHI_MCP_TEST_NETDIR (una carpeta de una unidad de red conectada) no se '
          'mide la raiz en una letra de red que ya esta conectada')


# ---- el modo local (stdio): el entorno, y el token de un workspace
ULTIMO = {}


def local(env, nombre, ruta, vault=False):
    """(texto de delphi_list de ruta, avisos del arranque) de un servidor por
    stdio con ese entorno. Lleva el settings.ini de arriba. En ULTIMO deja lo
    que ese servidor contesta a las dos tools que no pasan por una ruta
    (delphi_workspace y delphi_projects sin root), a un FICHERO nombrado con
    barra final, a una ruta de red (de un host que no existe) y, con
    vault=True, a vault_read de la nota del vault."""
    s = mc.Stdio(EXE, mc.entorno(env), nombre, lee_stderr=True, respaldo_json=True)
    try:
        t = s.call('delphi_list', {'root': ruta, 'dirs': True}, 60)
        ULTIMO['workspace'] = s.call('delphi_workspace', {}, 60)
        ULTIMO['projects'] = s.call('delphi_projects', {}, 60)
        ULTIMO['fichero'] = s.call('delphi_list', {'root': os.path.join(JAIL2, 'Local.dproj') + '\\'}, 60)
        ULTIMO['unc'] = s.call('delphi_list', {'root': UNC_ENTORNO + '\\otra\\'}, 60)
        ULTIMO['fuera'] = s.call('delphi_list', {'root': os.path.join(JAIL, 'fuera.txt') + '\\'}, 60)
        if vault:
            ULTIMO['vault'] = s.call('vault_read', {'path': 'nota.md'}, 60)
    finally:
        s.cierra()
    return t, [l for l in s.errores if 'WARN' in l]


# un proyecto en la raiz del modo local: lo que delphi_projects encontraria
open(os.path.join(JAIL2, 'Local.dproj'), 'w').write('<Project/>\n')
# ...un fichero FUERA de esa raiz, y un vault de verdad para el modo local
open(os.path.join(JAIL, 'fuera.txt'), 'w').write('fuera\n')
VAULTDIR = os.path.join(BASE, 'vault')
os.makedirs(VAULTDIR)
open(os.path.join(VAULTDIR, 'nota.md'), 'w').write('# nota\nSECRETO-LR\n')


t, av = local({'DELPHI_MCP_ROOTS': '%s;%s' % (JAIL2, UNC_ENTORNO)}, 'lr-entorno', JAIL2)
check('U6 una raiz del entorno en ruta de red no se carga, se avisa, y la de letra sigue',
      avisa_de(av, 'DELPHI_MCP_ROOTS', UNC_ENTORNO) and 'dentro' in t and not mc.fallo(t),
      '%s | %s' % (t[:160], av))
check('U6 (control) ...y ahi delphi_projects sin root SI encuentra el proyecto de la raiz',
      'Local.dproj' in ULTIMO['projects'], ULTIMO['projects'][:300])
check('U6 (control) ...y un fichero nombrado con barra final dice que es un fichero (GUARD-025)',
      mc.abre(ULTIMO['fichero'], 'SR_GUARD_BARRA_FINAL_FMT'), ULTIMO['fichero'][:300])
check('U6 ...pero de uno de FUERA de la jaula no: la jaula va antes (se contestaba si alli habia un fichero)',
      mc.abre(ULTIMO['fuera'], 'SR_JAIL_FMT'), ULTIMO['fuera'][:300])
for clave, entrada in (('DELPHI_MCP_READONLY_ROOTS', UNC_ENTORNO),
                       ('DELPHI_MCP_READONLY_PATHS', UNC_ENTORNO),
                       ('DELPHI_MCP_VAULT_PATH', UNC_ENTORNO)):
    t, av = local({'DELPHI_MCP_ROOTS': JAIL2, clave: entrada}, 'lr-' + clave[-5:].lower(), JAIL2)
    check('U6 ...y %s en ruta de red lo cierra todo, con su motivo (GUARD-030)' % clave,
          avisa_de(av, clave, entrada, 'NOBODY') and mc.abre(t, 'SR_LOCAL_CERRADO_FMT')
          and 'was not loaded' in t, '%s | %s' % (t[:200], av))
    check('U6 ...tambien para lo que no pasa por una ruta: delphi_workspace dice cerrado y no ensena raices, y delphi_projects, el motivo del cierre (%s)' % clave,
          '"jail":"closed (' in ULTIMO['workspace'].replace('": "', '":"')
          and '"roots":[]' in ''.join(ULTIMO['workspace'].split())
          and mc.abre(ULTIMO['projects'], 'SR_LOCAL_CERRADO_FMT') and 'Local.dproj' not in ULTIMO['projects'],
          '%s | %s' % (ULTIMO['workspace'][:200], ULTIMO['projects'][:200]))
    check('U6 ...y antes de mirar nada en el disco: de un fichero con barra final no se dice que existe, '
          'y una ruta de red sale con el motivo del cierre, no como "fuera de" unas raices que no hay (%s)' % clave,
          mc.abre(ULTIMO['fichero'], 'SR_LOCAL_CERRADO_FMT') and mc.abre(ULTIMO['unc'], 'SR_LOCAL_CERRADO_FMT'),
          '%s | %s' % (ULTIMO['fichero'][:200], ULTIMO['unc'][:200]))

local({'DELPHI_MCP_ROOTS': JAIL2, 'DELPHI_MCP_VAULT_PATH': VAULTDIR}, 'lr-vault-abierto', JAIL2, vault=True)
check('U6 (control) el vault del entorno se lee en el modo local abierto',
      'SECRETO-LR' in ULTIMO['vault'], ULTIMO['vault'][:200])
local({'DELPHI_MCP_ROOTS': JAIL2, 'DELPHI_MCP_VAULT_PATH': VAULTDIR, 'DELPHI_MCP_READONLY_ROOTS': UNC_ENTORNO},
      'lr-vault-cerrado', JAIL2, vault=True)
check('U6 ...y en el modo local cerrado no se lee: no hay vault',
      'SECRETO-LR' not in ULTIMO['vault'] and mc.fallo(ULTIMO['vault']), ULTIMO['vault'][:200])

t, _ = local({'DELPHI_MCP_TOKEN': 'unc-lr'}, 'lr-token-cerrado', JAIL2)
check('U7 un cliente local con el token de un workspace CERRADO queda cerrado (no lee la maquina)',
      mc.abre(t, 'SR_LOCAL_CERRADO_FMT') and '[Workspace.Unc]' in t, t[:300])
t, _ = local({'DELPHI_MCP_TOKEN': 'mixto-lr'}, 'lr-token-abierto', JAIL2)
t2, _ = local({'DELPHI_MCP_TOKEN': 'mixto-lr'}, 'lr-token-abierto2', JAIL)
check('U7 (control) ...y con el de uno abierto, su jaula: lo suyo si, lo de fuera no',
      'dentro' in t and not mc.fallo(t) and mc.abre(t2, 'SR_JAIL_FMT'), '%s | %s' % (t[:160], t2[:160]))
for variable, token in (('DELPHI_MCP_TOKEN', 'lector-ro-lr'), ('DELPHI_MCP_READONLY_TOKEN', 'lector-ro-lr'),
                        ('DELPHI_MCP_READONLY_TOKEN', 'lector-lr')):
    t, _ = local({variable: token}, 'lr-lector', JAIL)
    ws = ''.join(ULTIMO['workspace'].split())
    check('U7 %s=%s ata el proceso a la jaula de ese workspace, en solo lectura (no ataba nada: modo local)' % (variable, token),
          mc.abre(t, 'SR_JAIL_FMT') and '"workspace":"Lector"' in ws and '"access":"read-only"' in ws,
          '%s | %s' % (t[:160], ULTIMO['workspace'][:300]))
t, av = local({'DELPHI_MCP_TOKEN': 'mixto-lr', 'DELPHI_MCP_READONLY_ROOTS': UNC_ENTORNO}, 'lr-token-y-cierre', JAIL2)
check('U8 el cierre del modo local no le toca a quien entra con el token de un workspace abierto',
      avisa_de(av, 'DELPHI_MCP_READONLY_ROOTS', UNC_ENTORNO) and 'dentro' in t and not mc.fallo(t),
      '%s | %s' % (t[:200], av))
t, av = local({'DELPHI_MCP_TOKEN': 'mixto-lr', 'DELPHI_MCP_ROOTS': UNC_ENTORNO}, 'lr-token-y-raices', JAIL2)
check('U8 ...ni unas DELPHI_MCP_ROOTS de las que no cargo ninguna (se le negaba todo: WS-004)',
      avisa_de(av, 'DELPHI_MCP_ROOTS', UNC_ENTORNO) and 'dentro' in t and not mc.fallo(t)
      and 'Local.dproj' in ULTIMO['projects'], '%s | %s' % (t[:200], ULTIMO['projects'][:160]))
t, _ = local({'DELPHI_MCP_ROOTS': UNC_ENTORNO}, 'lr-raices-sin-token', JAIL2)
check('U8 (control) ...y sin token, esas raices cierran el modo local como siempre (WS-004)',
      mc.abre(t, 'SR_ROOTS_INVALID'), t[:200])
t, av = local({'DELPHI_MCP_ROOTS': JAIL2, 'DELPHI_MCP_READONLY_PATHS': FUERA_RO}, 'lr-ro-fuera', JAIL2)
check('R4 una DELPHI_MCP_READONLY_PATHS fuera de DELPHI_MCP_ROOTS se avisa igual, con la clave del entorno, y no cierra nada',
      any(FUERA_FMT % ('DELPHI_MCP_READONLY_PATHS', FUERA_RO, 'DELPHI_MCP_READONLY_ROOTS') in l for l in av)
      and 'dentro' in t and not mc.fallo(t), '%s | %s' % (t[:200], av))
t, av = local({'DELPHI_MCP_READONLY_PATHS': FUERA_RO}, 'lr-ro-sin-raices', JAIL2)
# (control: los avisos de ese proceso SI se leyeron - el del ini sale en los dos)
check('R4 (guarda) ...y sin raices no hay fuera: el modo local de confianza no dice nada',
      not any('DELPHI_MCP_READONLY_PATHS' in l and FUERA_TROZO in l for l in av)
      and any('[Workspace.SoloFuera]' in l and FUERA_TROZO in l for l in av)
      and 'dentro' in t and not mc.fallo(t), '%s | %s' % (t[:200], av))

mc.fin('letras de red battery')
