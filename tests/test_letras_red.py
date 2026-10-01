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

Usage:  python tests/test_letras_red.py [path-to-DelphiLspMcp.exe]
"""
import ctypes, os, string, subprocess, winreg
import mcp_cliente as mc
from mcp_cliente import check


def letras_libres(cuantas):
    """Letras que no son una unidad de esta sesion ni un mapeo persistente de
    la cuenta: para el servidor, letras que no existen y que no puede conectar."""
    mapa = ctypes.windll.kernel32.GetLogicalDrives()
    libres = []
    for i, letra in reversed(list(enumerate(string.ascii_uppercase))):
        if i < 2 or mapa & (1 << i):
            continue
        try:
            winreg.CloseKey(winreg.OpenKey(winreg.HKEY_CURRENT_USER, 'Network\\' + letra))
            continue
        except OSError:
            pass
        libres.append(letra)
        if len(libres) == cuantas:
            break
    return libres


BASE = mc.carpeta('letras_red')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
JAIL2 = os.path.join(BASE, 'jail2')
os.makedirs(EXEDIR)
os.makedirs(JAIL)
os.makedirs(os.path.join(JAIL2, 'dentro'))
EXE = mc.copia_exe(EXEDIR)

LIBRES = letras_libres(5)
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

mc.fin('letras de red battery')
