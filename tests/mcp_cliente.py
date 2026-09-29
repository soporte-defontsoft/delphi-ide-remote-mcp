# -*- coding: utf-8 -*-
"""EL cliente de las baterias: preparar su carpeta, arrancar el servidor,
hablarle MCP (stdio o HTTP) y contar los checks.

Hasta el 26-sep-2026 cada bateria llevaba su propia copia: 82 check(), 71
call() -como mucho tres iguales-, 40 send()/recv() y 33 rpc(). Y 34 de las 37
que arrancan un servidor HTTP dormian un plazo FIJO (2,3-3 s) en vez de
esperar al puerto: con la maquina cargada, la puerta de release salio roja
por eso (test_round20, 26-sep). Un arreglo en una copia no llegaba a las
demas; aqui vive una vez.

No es una bateria (no empieza por test_): run_all no la ejecuta.
"""
import atexit
import ctypes
import glob
import json, os, queue, re, shutil, socket, stat, subprocess, sys, tempfile, threading, time
import urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
EXE_COMPILADO = os.path.join(REPO, 'src', 'Server', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
# La raiz temporal que comparten todas las baterias (run_all la barre).
RAIZ = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests')
PROTOCOLO = '2025-06-18'


# ---------------------------------------------------------------- carpeta

def exe_origen():
    """El exe bajo prueba: el primer argumento de la bateria, o el compilado."""
    return sys.argv[1] if len(sys.argv) > 1 else EXE_COMPILADO


def corta(ruta):
    """El alias 8.3 de una ruta que existe ('' si no lo hay). Uno para todas
    las baterias: estaba escrito a mano tres veces (28-sep-2026)."""
    buf = ctypes.create_unicode_buffer(1024)
    n = ctypes.windll.kernel32.GetShortPathNameW(ruta, buf, 1024)
    return buf.value if n else ''


def larga(ruta):
    """La inversa de corta(): la forma LARGA de una ruta que existe (la misma
    si no se puede). Es la que escribe el servidor desde que la entrada alarga
    las rutas de los argumentos (sexta revision)."""
    buf = ctypes.create_unicode_buffer(1024)
    n = ctypes.windll.kernel32.GetLongPathNameW(ruta, buf, 1024)
    return buf.value if n else ruta


def virtual(ruta):
    """Como ENSENA el servidor una ruta suya: 'D:\\x' -> 'srvd:\\x' (el
    enmascarador de salida). La compone esta funcion y la lee real(), su
    inversa: estaba a mano en cinco baterias (28-sep-2026)."""
    if len(ruta) >= 2 and ruta[1] == ':':
        return 'srv' + ruta[0].lower() + ruta[1:]
    return ruta


def real(texto):
    """La inversa de virtual(), tambien DENTRO de un texto: 'srvd:\\x' ->
    'd:\\x', para cualquier unidad (la de a mano solo entendia la c)."""
    return re.sub(r'(?i)(?<![a-z])srv([a-z]):', r'\1:', texto)


_PAPELERA = {}


def _papelera():
    """Las constantes de la papelera, leidas de Lsp.Patch - el nombrador del
    servidor -: la carpeta, los cajones y la marca de dueno. Las baterias no
    las escriben a mano: tres checks buscaban la forma de antes de la sexta
    revision y se pusieron rojos por eso, no por el servidor (28-sep-2026)."""
    if not _PAPELERA:
        with open(os.path.join(REPO, 'src', 'Server', 'Lsp.Patch.pas'),
                  encoding='utf-8-sig', errors='replace') as fh:
            t = fh.read()
        for n in ('BACKUP_SUB', 'CAJON_BORRADOS', 'CAJON_ANTES_DE_RESTAURAR',
                  'CAJON_SUSTITUIDOS', 'MARCA_DUENO_EXT'):
            _PAPELERA[n] = re.search(r"\b%s\s*=\s*'([^']*)'" % n, t).group(1)
    return _PAPELERA


def marca_dueno(copia):
    """La marca de dueno de una copia sellada (MarcaDeDueno del servidor)."""
    return copia + _papelera()['MARCA_DUENO_EXT']


def es_marca_dueno(nombre):
    """La inversa: este fichero es la marca de dueno de una copia."""
    return nombre.lower().endswith(_papelera()['MARCA_DUENO_EXT'].lower())


def copias(carpeta, nombre=None, cajon=None, bajo=False):
    """Las copias SELLADAS de <nombre> en la papelera de <carpeta>, de todos los
    dias, sin sus marcas: el lector de lo que compone TrashPathFor
    (<carpeta>\\__delphi-patch\\<dia>\\<cajon>\\<nombre>-<hhnnsszzz>). cajon
    es el NOMBRE de la constante de Lsp.Patch (CAJON_BORRADOS,
    CAJON_SUSTITUIDOS, CAJON_ANTES_DE_RESTAURAR); None, todos. nombre None:
    las de cualquier fichero. bajo=True: en TODAS las papeleras bajo carpeta
    (hay una junto a cada carpeta de lo que se tiro)."""
    p = _papelera()
    patron = os.path.join(os.path.join(carpeta, '**') if bajo else carpeta,
                          p['BACKUP_SUB'], '*', p[cajon] if cajon else '*',
                          (glob.escape(nombre) if nombre else '*') + '-*')
    sello = re.compile((re.escape(nombre) if nombre else '.+') + r'-\d{9}$', re.I)
    return sorted(f for f in glob.glob(patron, recursive=bajo)
                  if sello.match(os.path.basename(f)))


def limpia_caches_lsp():
    """Las caches .delphilsp.json que el servidor deja en %LOCALAPPDATA%\\DelphiLspMcp\\configs
    para los proyectos de las baterias (bajo RAIZ) o para proyectos que ya no
    existen: basura de la maquina (131 medidas el 28-sep-2026). Devuelve cuantas
    quito. Las de proyectos vivos fuera de RAIZ no se tocan."""
    from urllib.parse import unquote
    carpeta = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'DelphiLspMcp', 'configs')
    if not os.path.isdir(carpeta):
        return 0
    quitadas = 0
    raiz = os.path.normcase(os.path.abspath(RAIZ)) + os.sep  # con separador: no casa delphi-mcp-tests-otro
    for f in glob.glob(os.path.join(carpeta, '*.delphilsp.json')):
        try:
            proyecto = json.load(open(f, encoding='utf-8-sig')).get('settings', {}).get('project', '')
        except Exception:
            continue
        if not proyecto.startswith('file:///'):
            continue
        ruta = unquote(proyecto[len('file:///'):]).replace('/', os.sep)
        if os.path.normcase(os.path.abspath(ruta)).startswith(raiz) or not os.path.exists(ruta):
            try:
                os.remove(f)
                quitadas += 1
            except OSError:
                pass
    return quitadas


def hijos_lsp(ppid):
    """Los DelphiLSP.exe cuyo padre es ESE proceso (sus pids). Filtrar por
    padre es obligatorio: en esta maquina suele haber un servidor de produccion
    con los suyos, y contar o matar los de otro seria mucho peor que el bug
    buscado. Estaba en test_tray y se escribio otra vez, distinta y sin tope
    de tiempo, en test_round14 (revision de la 1.7.7): UNA.

    Si la pregunta FALLA, lo dice (RuntimeError): devolvia [] y "no queda
    ningun motor" pasaba sin haber mirado (segunda revision de la 1.7.7)."""
    p = subprocess.run(
        ['powershell', '-NoProfile', '-Command',
         "$ErrorActionPreference = 'Stop'; "
         "Get-CimInstance Win32_Process -Filter \"Name='DelphiLSP.exe'\" | "
         "ForEach-Object { \"$($_.ProcessId),$($_.ParentProcessId)\" }"],
        capture_output=True, text=True, timeout=60)
    if p.returncode != 0:
        raise RuntimeError('no se pudo preguntar por los motores (powershell rc=%d): %s'
                           % (p.returncode, ' '.join(p.stderr.split())[:200]))
    out = p.stdout
    r = []
    for l in out.splitlines():
        p = l.strip().split(',')
        if len(p) == 2 and p[1].isdigit() and int(p[1]) == ppid:
            r.append(int(p[0]))
    return sorted(r)


def cwd_de(pid):
    """El directorio de trabajo REAL de otro proceso, leido de su PEB ('' si
    no se deja leer: ya no esta, o no es nuestro). Es lo que RETIENE una
    carpeta: Windows no deja renombrar ni borrar el directorio de trabajo de
    un proceso vivo, y DelphiLSP hace suyo el de la carpeta del .dpr cuando
    carga la configuracion del proyecto (medido el 29-sep-2026). DelphiLSP es
    de 32 bits; la rama de 64 es para cualquier otro."""
    import ctypes.wintypes as wt
    import struct
    k32 = ctypes.WinDLL('kernel32', use_last_error=True)
    nt = ctypes.WinDLL('ntdll')
    k32.OpenProcess.restype = wt.HANDLE
    k32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
    k32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t,
                                      ctypes.POINTER(ctypes.c_size_t)]
    k32.CloseHandle.argtypes = [wt.HANDLE]
    nt.NtQueryInformationProcess.argtypes = [wt.HANDLE, ctypes.c_int, ctypes.c_void_p, ctypes.c_ulong,
                                             ctypes.c_void_p]

    def leer(h, addr, n):
        buf = ctypes.create_string_buffer(n)
        leidos = ctypes.c_size_t(0)
        if not k32.ReadProcessMemory(h, ctypes.c_void_p(addr), buf, n, ctypes.byref(leidos)):
            raise OSError('ReadProcessMemory %d' % ctypes.get_last_error())
        return buf.raw

    h = k32.OpenProcess(0x0400 | 0x0010, False, pid)   # QUERY_INFORMATION | VM_READ
    if not h:
        return ''
    try:
        peb32 = ctypes.c_void_p(0)
        r = nt.NtQueryInformationProcess(h, 26, ctypes.byref(peb32), ctypes.sizeof(peb32), None)
        if r == 0 and peb32.value:                       # proceso de 32 bits (WOW64)
            pp = struct.unpack('<I', leer(h, peb32.value + 0x10, 4))[0]
            ln, _mx, buf = struct.unpack('<HHI', leer(h, pp + 0x24, 8))
            return leer(h, buf, ln).decode('utf-16-le')

        class PBI(ctypes.Structure):
            _fields_ = [('r1', ctypes.c_void_p), ('peb', ctypes.c_void_p), ('r2', ctypes.c_void_p * 2),
                        ('pid', ctypes.c_void_p), ('r3', ctypes.c_void_p)]
        pbi = PBI()
        nt.NtQueryInformationProcess(h, 0, ctypes.byref(pbi), ctypes.sizeof(pbi), None)
        pp = struct.unpack('<Q', leer(h, pbi.peb + 0x20, 8))[0]
        ln, _mx = struct.unpack('<HH', leer(h, pp + 0x38, 4))
        buf = struct.unpack('<Q', leer(h, pp + 0x40, 8))[0]
        return leer(h, buf, ln).decode('utf-16-le')
    except Exception:
        return ''
    finally:
        k32.CloseHandle(h)


def motores_en(ppid, carpeta):
    """Los motores de ESE servidor que RETIENEN la carpeta: su directorio de
    trabajo es ella o esta dentro (por la forma larga de las dos rutas: una
    corta frente a una larga dejo vacia la primera matriz de las sondas)."""
    base = os.path.normcase(larga(os.path.abspath(carpeta))).rstrip('\\') + '\\'
    r = []
    for pid in hijos_lsp(ppid):
        d = cwd_de(pid)
        if d and (os.path.normcase(larga(d)).rstrip('\\') + '\\').startswith(base):
            r.append(pid)
    return r


def es_esta_maquina(host):
    """El "host" que dice un servidor lanzado AQUI es el nombre de esta
    maquina (el NetBIOS, el de %COMPUTERNAME%, que es el que da
    GetComputerName). Vacio no vale. Estaba escrito tres veces."""
    return bool(host) and host.lower() == os.environ.get('COMPUTERNAME', '').lower()


def borra(ruta):
    """Borra un arbol aunque tenga ficheros de SOLO LECTURA (los objetos de un
    .git los son): rmtree con ignore_errors los dejaba ahi, y la pasada
    siguiente de la bateria reventaba en makedirs (medido 2026-09-26 en
    test_v012, 148 objetos). Un enlace se quita como enlace, nunca lo de detras."""
    if os.path.isjunction(ruta) or os.path.islink(ruta):
        if os.path.isdir(ruta):
            os.rmdir(ruta)
        else:
            os.remove(ruta)
        return
    if not os.path.exists(ruta):
        return

    def quita_ro(func, p, _exc):
        try:
            os.chmod(p, stat.S_IWRITE)
            func(p)
        except OSError:
            pass
    shutil.rmtree(ruta, onexc=quita_ro)


import contextlib


@contextlib.contextmanager
def solo_lectura(ruta):
    """Pone el atributo +R a un fichero mientras dura el bloque y lo quita al
    salir, aunque el fichero ya no este: el finally con os.chmod() reventaba la
    bateria (FileNotFoundError) justo cuando volvia el fallo que vigilaba
    (E134 contra la octava; decima revision). Un fichero que la operacion
    movio o copio se destapa por su ruta nueva con el segundo argumento de
    solo_lectura_quita, o borra() lo quita igual."""
    os.chmod(ruta, stat.S_IREAD)
    try:
        yield ruta
    finally:
        solo_lectura_quita(ruta)


def solo_lectura_quita(*rutas):
    """Quita el +R de cada ruta que exista (nunca lanza)."""
    for r in rutas:
        try:
            if os.path.exists(r):
                os.chmod(r, stat.S_IREAD | stat.S_IWRITE)
        except OSError:
            pass


_k32 = None


@contextlib.contextmanager
def bloqueado(ruta, lectura=False):
    """Otro proceso "tiene" el fichero mientras dura el bloque: abierto con
    CreateFileW sin compartir (lectura=False: ni leer) o compartiendo solo la
    lectura (lectura=True: leer si, mover o escribir no). Estaba escrito 13
    veces con los numeros a mano (0x80000000, 3, 0x80)."""
    global _k32
    if _k32 is None:
        from ctypes import wintypes
        _k32 = ctypes.WinDLL('kernel32', use_last_error=True)
        _k32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID,
                                     wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
        _k32.CreateFileW.restype = wintypes.HANDLE
    GENERIC_READ, FILE_SHARE_READ, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL = 0x80000000, 1, 3, 0x80
    h = _k32.CreateFileW(ruta, GENERIC_READ, FILE_SHARE_READ if lectura else 0, None,
                         OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, None)
    if h in (None, 0, -1, 0xFFFFFFFFFFFFFFFF):
        raise OSError('no se pudo abrir sin compartir: %s' % ruta)
    try:
        yield h
    finally:
        _k32.CloseHandle(h)


def carpeta(nombre):
    """<raiz temporal>\\<nombre>, vacia: lo que dejo una pasada anterior no
    puede sostener a esta. Si no se puede vaciar, lo dice (no sigue encima)."""
    base = os.path.join(RAIZ, nombre)
    # Unos intentos: en Windows un proceso que acaba de salir (git, el propio
    # servidor) suelta sus handles con un momento de retraso.
    for _ in range(10):
        borra(base)
        if not os.path.exists(base):
            break
        time.sleep(0.5)
    if os.path.exists(base):
        raise RuntimeError('no puedo vaciar %s (algo lo tiene abierto?)' % base)
    os.makedirs(base)
    return base


CONVERSOR = 'DelphiStyleConvert.exe'
CONVERSOR_COMPILADO = os.path.join(REPO, 'src', 'StyleConvert', 'Compiled', 'Win64', 'Release', CONVERSOR)


def copia_exe(dest_dir, src=None, con_conversor=False):
    """Copia el servidor a dest_dir y devuelve la ruta de la copia: cada
    bateria corre el suyo, con su settings.ini, sus logs y su __delphi-temp.
    con_conversor: delphi_styles necesita DelphiStyleConvert.exe AL LADO del
    servidor; va el que acompane al exe bajo prueba (run_all lo pone junto a
    su copia limpia) o, si no lo trae, el compilado de src/StyleConvert."""
    os.makedirs(dest_dir, exist_ok=True)
    origen = src or exe_origen()
    exe = os.path.join(dest_dir, 'DelphiLspMcp.exe')
    shutil.copy(origen, exe)
    if con_conversor:
        junto = os.path.join(os.path.dirname(os.path.abspath(origen)), CONVERSOR)
        shutil.copy(junto if os.path.exists(junto) else CONVERSOR_COMPILADO,
                    os.path.join(dest_dir, CONVERSOR))
    return exe


# ---------------------------------------------------------------- arranque

def puerto_libre():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    p = s.getsockname()[1]
    s.close()
    return p


def espera_puerto(puerto, proc=None, segundos=30):
    """True en cuanto 127.0.0.1:puerto acepta conexiones; False si se agota
    el plazo o si proc (el servidor) muere antes. Sustituye al sleep fijo."""
    fin = time.time() + segundos
    while time.time() < fin:
        if proc is not None and proc.poll() is not None:
            return False
        try:
            with socket.create_connection(('127.0.0.1', puerto), timeout=0.5):
                return True
        except OSError:
            time.sleep(0.1)
    return False


def lanza_http(exe, puerto=None, env=None, args=(), segundos=30, **popen):
    """Arranca exe --http [puerto] y ESPERA a que escuche. Sin puerto, el que
    diga su settings.ini: entonces hay que pasar el que se espera en
    'espera_en'. Devuelve el proceso; si no llega a escuchar, lo mata y
    lanza RuntimeError con el motivo (la bateria lo ve, no un sleep mudo)."""
    espera_en = popen.pop('espera_en', puerto)
    cmd = [exe, '--http'] + ([str(puerto)] if puerto is not None else []) + list(args)
    popen.setdefault('stdout', subprocess.DEVNULL)
    popen.setdefault('stderr', subprocess.DEVNULL)
    proc = subprocess.Popen(cmd, env=env, **popen)
    if not espera_puerto(espera_en, proc, segundos):
        murio = proc.poll()
        try:
            proc.kill()
        except Exception:
            pass
        raise RuntimeError('el servidor no escucha en %s tras %d s (%s)' % (
            espera_en, segundos, 'murio con %s' % murio if murio is not None else 'sigue sin abrir'))
    return proc


# ---------------------------------------------------------------- contador

P = F = 0


def check(name, ok, detail=''):
    """PASS/FAIL con el formato que cuenta run_all (una linea por check)."""
    global P, F
    if ok:
        P += 1
        print('  PASS', name)
    else:
        F += 1
        # en UNA linea: un detalle con saltos partiria el FAIL, y una linea suya
        # que empezara por PASS/FAIL le cambiaria la cuenta a run_all
        linea = '  FAIL %s | %s' % (name, ' '.join(str(detail).splitlines())[:300])
        # un detalle que no cabe en la pagina de la consola (un 日本 con la salida
        # redirigida en CP1252) reventaba la bateria justo en el FAIL que tenia que
        # contar, y los checks de despues no se veian (E148 contra la novena)
        try:
            print(linea)
        except UnicodeEncodeError:
            print(linea.encode('ascii', 'backslashreplace').decode('ascii'))
    return ok


# ------------------------------------------------------------------- adb
# Una llamada a delphi_adb arranca el servidor de adb (su daemon) y adb lo
# deja vivo al acabar. A un usuario le conviene; una bateria no deja
# procesos en la maquina (26-sep-2026: un adb.exe vivo desde el dia
# anterior, con el padre ya muerto). Se para SOLO el que no estaba al
# empezar: el de David o el del IDE no se tocan. Se habla con el propio
# protocolo de adb (host:kill) en su puerto, el de ANDROID_ADB_SERVER_PORT
# si lo hay: ni se busca el adb.exe ni se matan procesos por nombre.
ADB_PUERTO = int(os.environ.get('ANDROID_ADB_SERVER_PORT') or 5037)
SUITE = 'MCP_BATERIAS_SUITE'  # lo pone run_all: la suite limpia al final


def adb_vivo():
    """True si hay un servidor de adb escuchando en su puerto."""
    try:
        with socket.create_connection(('127.0.0.1', ADB_PUERTO), timeout=0.5):
            return True
    except OSError:
        return False


def adb_para():
    """Para el servidor de adb (host:kill) y espera a que suelte el puerto."""
    try:
        with socket.create_connection(('127.0.0.1', ADB_PUERTO), timeout=2) as s:
            s.sendall(b'0009host:kill')
            s.recv(4)
    except OSError:
        pass
    for _ in range(20):
        if not adb_vivo():
            return True
        time.sleep(0.25)
    return False


ADB_ANTES = adb_vivo()  # al importar = al empezar la bateria


def _para_adb_propio():
    """Suelta (fuera de run_all), el adb que arranco ESTA bateria se para al
    salir, pase por fin o reviente antes: una que lanzaba una excepcion antes
    de fin dejaba vivo su adb (revision del 26-sep-2026). Dentro de run_all
    lo para la suite, una vez al final. OJO, limite sabido: un adb que
    arranque OTRO (el IDE, David) mientras la bateria corre no se distingue
    del suyo, y se para tambien."""
    if not ADB_ANTES and not os.environ.get(SUITE) and adb_vivo():
        adb_para()


atexit.register(_para_adb_propio)


# La marca de una bateria que en ESTA maquina no tiene nada que medir (sin
# el servicio instalado, sin el SDK) y lo dice: fin(sin_checks=) la escribe
# y run_all la lee. Sin ella, 0 checks es ROJO (26-sep-2026: una bateria
# que no media nada salia verde, con rc 0).
SIN_CHECKS = 'SIN CHECKS:'


def sin_checks_de(salida):
    """EL lector de la marca que escribe fin(sin_checks=...): una LINEA que
    empieza por SIN_CHECKS. Se buscaba en cualquier parte de la salida, y una
    respuesta de tool que la citase habria dado por buena una bateria vacia."""
    return any(l.startswith(SIN_CHECKS) for l in salida.splitlines())


def fin(titulo, sin_checks=None):
    """El recuento de la bateria y su codigo de salida: 1 si fallo algo, y
    tambien si no midio NADA - salvo que diga por que en sin_checks.
    Suelta, para el adb que ella arranco; dentro de run_all eso lo hace la
    suite, una vez al final, para no parar el que otra esta usando."""
    global F
    if P == 0 and F == 0:
        if sin_checks:
            print('%s %s' % (SIN_CHECKS, sin_checks))
        else:
            F += 1
            print('  FAIL %s: 0 checks - una bateria que no mide nada no sale '
                  'verde (si aqui no hay nada que medir, fin(sin_checks=motivo))' % titulo)
    print()
    print('== %s: %d PASS / %d FAIL ==' % (titulo, P, F))
    sys.exit(1 if F else 0)


# ---------------------------------------------------------------- respuestas

# Lo que texto() pone cuando NO hay respuesta: lo escribe texto() y lo lee
# resultado(), que lo cuenta como fallo (antes lo daba por exito: un check
# "no fallo" pasaba con el servidor caido; revision 27-sep-2026)
SIN_TIMEOUT = '(timeout)'
SIN_RPC = 'MCPERROR '
SIN_CONTENIDO = '(no content)'
NO_ANSWER = 'NO_ANSWER'


def texto(msg, respaldo_json=False):
    """El texto de una respuesta de tools/call: content[0].text; 'MCPERROR
    <error>' si el JSON-RPC trae error; '(timeout)' si no llego. Sin texto:
    '(no content)', o el mensaje entero en JSON (recortado) con respaldo_json,
    que es lo que varias baterias ensenaban en el detalle de un FAIL."""
    if msg is None:
        return SIN_TIMEOUT
    if 'error' in msg:
        return SIN_RPC + json.dumps(msg['error'])[:300]
    c = (msg.get('result') or {}).get('content') or []
    if c and 'text' in c[0]:
        return c[0]['text']
    # con respaldo_json el detalle va DETRAS de la marca: sin_respuesta la
    # sigue reconociendo (era una cuarta forma que nadie leia)
    return SIN_CONTENIDO + ' ' + json.dumps(msg)[:400] if respaldo_json else SIN_CONTENIDO


def sin_respuesta(t):
    """True si t es lo que texto() pone cuando no hubo respuesta."""
    t = t or ''
    return t == SIN_TIMEOUT or t.startswith(SIN_CONTENIDO) or t.startswith(SIN_RPC)


def entorno(extra=None):
    """El entorno de un servidor de prueba: el de esta maquina SIN las
    DELPHI_MCP_* de quien lanza la bateria -una jaula, un token o una lista
    heredados cambiaban lo que se mide sin que la bateria lo supiera-, mas lo
    que la bateria ponga en extra."""
    env = {k: v for k, v in os.environ.items() if not k.upper().startswith('DELPHI_MCP_')}
    env.update(extra or {})
    return env


# Las etiquetas de los mensajes del catalogo (Lsp.Texts.MSG_TAG_REGEX, decision
# de David 27-sep-2026): [AREA-NNN] o [AREA-NNN RESULTADO] al PRINCIPIO de cada
# mensaje. Las baterias reconocen un mensaje por su id, no por su frase, asi
# el texto se puede traducir sin romperlas. test_catalogo vigila que este
# patron sea el mismo que el del servidor.
ETIQUETA = re.compile(r'\[([A-Z]{2,6}-\d{3})(?: (DENIED|NOT_FOUND|INVALID_PARAM|INTERNAL))?\]')


def ids(t):
    """Los ids de las etiquetas que trae un texto, en orden."""
    return [m.group(1) for m in ETIQUETA.finditer(t or '')]


def tiene(t, msg_id):
    """True si el texto trae el mensaje con ese id ('CFG-007')."""
    return msg_id in ids(t)


def outcome(t):
    """El resultado que declara el mensaje que ABRE el texto: el de la
    etiqueta con la que EMPIEZA; '' si no empieza por una o si esa no declara
    ninguno. El mismo criterio que MsgOutcome del servidor."""
    m = ETIQUETA.match((t or '').lstrip())
    return (m.group(2) or '') if m else ''

def _fin_literal(t, i):
    """Posicion tras el literal Pascal que empieza en t[i] == "'" ('' dentro)."""
    i += 1
    while True:
        if t[i] == "'" and t[i + 1:i + 2] == "'":
            i += 2
        elif t[i] == "'":
            return i + 1
        else:
            i += 1


def constantes(t):
    """{NOMBRE: texto} de las constantes de cadena de un catalogo Pascal, con
    un tokenizador: literales ('' dentro), #nn y #$hh, y comentarios //, { } y
    (* *) solo FUERA de los literales. El lector de antes quitaba los { } con
    una regex y se comia los de DENTRO de un texto ({$I %s.inc}, {old,new}):
    29 textos mal leidos y uno entero perdido, que test_catalogo no vigilaba
    (medido 27-sep-2026). Una referencia a otra constante del mismo catalogo
    (SL_MARCA_AVISO + '...') se resuelve; sLineBreak es CRLF. EL lector del
    catalogo para las baterias (test_catalogo lo usa tambien)."""
    crudo = {}
    for m in re.finditer(r'^  ([A-Z][A-Z0-9_]*)\s*=', t, re.M):
        antes = t[:m.start()]
        if antes.rfind('{') > antes.rfind('}'):
            continue                      # dentro de un comentario { }
        i, toks = m.end(), []
        while True:
            c = t[i]
            if c == "'":
                j = _fin_literal(t, i)
                toks.append(('s', t[i + 1:j - 1].replace("''", "'"))); i = j
            elif c == '#':
                n = re.match(r'#(\$[0-9A-Fa-f]+|\d+)', t[i:])
                v = n.group(1)
                toks.append(('s', chr(int(v[1:], 16) if v.startswith('$') else int(v)))); i += n.end()
            elif t.startswith('//', i):
                i = t.index('\n', i)
            elif c == '{':
                i = t.index('}', i) + 1
            elif t.startswith('(*', i):
                i = t.index('*)', i) + 2
            elif c.isalpha() or c == '_':
                n = re.match(r'[A-Za-z_]\w*', t[i:])
                toks.append(('r', n.group(0))); i += n.end()
            elif c == ';':
                break
            else:
                i += 1
        if any(k == 's' for k, _ in toks):
            crudo.setdefault(m.group(1), toks)
    out = {}

    def texto(nombre, pila=()):
        if nombre in out:
            return out[nombre]
        partes = []
        for k, v in crudo[nombre]:
            if k == 's':
                partes.append(v)
            elif v == 'sLineBreak':
                partes.append('\r\n')
            elif v in crudo and v not in pila:
                partes.append(texto(v, pila + (nombre,)))
        out[nombre] = ''.join(partes)
        return out[nombre]

    for nombre in crudo:
        texto(nombre)
    return out


_CATALOGO = {}


def catalogo():
    """{NOMBRE: texto} de Lsp.Texts y de Mld.Textos (el del nodo y el
    lanzador), leidos una vez por bateria."""
    if not _CATALOGO:
        for rel in (('src', 'Server', 'Lsp.Texts.pas'), ('src', 'DesktopNode', 'Mld.Textos.pas')):
            with open(os.path.join(REPO, *rel), encoding='utf-8-sig') as fh:
                for n, tx in constantes(fh.read()).items():
                    _CATALOGO.setdefault(n, tx)
    return _CATALOGO


def id_de(nombre):
    """El id de la etiqueta de una constante del catalogo ('EDIT-007'). Una
    constante que no existe o no lleva etiqueta es un fallo de la BATERIA."""
    ids_ = ids(catalogo().get(nombre, ''))
    if not ids_:
        raise KeyError('%s: no esta en el catalogo o no lleva etiqueta' % nombre)
    return ids_[0]


def pascal_sin_comentarios(src):
    """El fuente Pascal SIN comentarios ({ }, (* *), //), respetando los
    literales: una llave o dos barras DENTRO de una cadena no abren nada.
    Quitarlos con una regex se comia '{...}' de un literal JSON (medido en
    test_catalogo el 27-sep: un uso sin helper desaparecia del recuento)."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == "'":
            j = i + 1
            while j < n:
                if src[j] == "'" and src[j + 1:j + 2] == "'":
                    j += 2
                elif src[j] == "'" or src[j] == '\n':
                    break
                else:
                    j += 1
            out.append(src[i:j + 1])
            i = j + 1
        elif c == '{':
            j = src.find('}', i)
            i = n if j < 0 else j + 1
        elif src.startswith('(*', i):
            j = src.find('*)', i + 2)
            i = n if j < 0 else j + 2
        elif src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def es(t, nombre):
    """True si el texto trae el mensaje de esa constante, en cualquier sitio:
    es('...', 'SR_ANCLA_NO_ESTA_FMT'). Como HasMsg del servidor."""
    return id_de(nombre) in ids(t)


def abre(t, nombre):
    """True si el mensaje que ABRE el texto es el de esa constante: su
    etiqueta es lo primero (tras los blancos), como EsMsg del servidor. En
    una respuesta JSON, el que abre su campo "error". Antes valia la primera
    etiqueta EN CUALQUIER SITIO: un eco o un JSON que la citara abria."""
    t = t or ''
    if t.lstrip().startswith('{'):
        err = como_json(t).get('error')
        t = err if isinstance(err, str) else ''
    m = ETIQUETA.match(t.lstrip())
    return bool(m) and m.group(1) == id_de(nombre)


def resultado(t):
    """El resultado de una respuesta como lo decide el servidor: el que
    declara la etiqueta que la abre; y si es un objeto JSON, el de su campo
    "error" (su etiqueta, o INVALID_PARAM si no la lleva), como
    OutcomeDelTexto y ErrorDelObjeto de ToolsManager: null, false o ausente
    es que no hay error; otra cosa que no sea texto, un error sin etiqueta.
    Un JSON de exito no declara nada. Sin respuesta: NO_ANSWER."""
    t = t or ''
    if sin_respuesta(t):
        return NO_ANSWER
    if t.lstrip().startswith('{'):
        err = como_json(t).get('error')
        if err is None or err is False:
            return ''
        if isinstance(err, str):
            return (outcome(err) or 'INVALID_PARAM') if err.strip() else ''
        return 'INVALID_PARAM'
    return outcome(t)

def id_changeset(t):
    """El id de un changeset por su FORMA - hhnnss-secuencia[-secreto], la que
    compone Lsp.Changeset.ChangesetBegin -, nunca por la palabra que ocupe en
    la frase (con la etiqueta delante, split()[1] cogia otra cosa: siete
    baterias lo tenian copiado). El secreto es opcional para que una bateria
    pueda comprobar que existe. '' si no hay ninguno."""
    m = re.search(r'\b\d{6}-\d+(?:-[0-9A-F]+)?\b', t or '')
    return m.group(0) if m else ''


def llego_a_adb(t):
    """True si la orden LLEGO a adb (y adb contesto, bien o mal): no la paro
    la puerta, ni fue un timeout. Desde el 27-sep un dispositivo que no esta
    o un adb que acaba con error son FALLOS con su etiqueta (SR_ADB_GONE_FMT,
    SR_ADB_FALLO_FMT); antes salian como exito con una nota. Estaba copiado
    a mano en dos baterias."""
    return abre(t, 'SR_ADB_GONE_FMT') or abre(t, 'SR_ADB_FALLO_FMT') or not fallo(t)


def llego_a_git(t):
    """True si la orden LLEGO a git (y git contesto, bien o mal): no la paro
    la puerta. Un exit<>0 es un fallo con su etiqueta (SR_GIT_EXIT_FMT) desde
    el 27-sep-2026; antes "exit=N" salia como exito y las baterias lo
    miraban con startswith('exit=')."""
    return (t or '').startswith('exit=') or abre(t, 'SR_GIT_EXIT_FMT')


def rechazado(t):
    """Una negativa: DENIED, NOT_FOUND o INVALID_PARAM - como EsRechazo del
    servidor (antes solo las dos primeras: el lector de las baterias no era
    el del servidor). Sin respuesta no es una negativa: es un fallo."""
    return resultado(t) in ('DENIED', 'NOT_FOUND', 'INVALID_PARAM')


def fallo(t):
    """Cualquier resultado de error, INTERNAL y NO_ANSWER incluidos."""
    return resultado(t) != ''


def como_json(t):
    """El texto de una tool como objeto; {} si no lo es."""
    try:
        v = json.loads(t, strict=False)
        return v if isinstance(v, dict) else {}
    except Exception:
        return {}


# ---------------------------------------------------------------- stdio

class Stdio:
    """Un servidor en modo terminal stdio, como lo lanza un cliente local.

    args: argumentos del exe (--readonly...). t: el plazo por defecto de cada
    peticion de ESTE cliente. protocolo: el protocolVersion que se presenta.
    lee_stderr: el log del servidor (stderr en modo terminal) se recoge en
    self.errores -una tuberia que nadie lee acaba bloqueando al servidor-.
    respaldo_json: ver texto(). self.init es la respuesta del initialize."""

    def __init__(self, exe, env=None, nombre='bateria', cwd=None, stderr=subprocess.DEVNULL,
                 inicializa=True, args=(), t=120, protocolo=None, lee_stderr=False,
                 respaldo_json=False):
        self.t = t
        self.protocolo = protocolo or PROTOCOLO
        self.respaldo_json = respaldo_json
        self.errores = []
        self.p = subprocess.Popen([exe] + list(args), env=env, cwd=cwd, stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE if lee_stderr else stderr,
                                  text=True, encoding='utf-8', errors='replace')
        self.q = queue.Queue()
        self.rid = 10
        self._lock = threading.Lock()
        self.init = None
        threading.Thread(target=self._lee, daemon=True).start()
        if lee_stderr:
            threading.Thread(target=self._lee_stderr, daemon=True).start()
        if inicializa:
            self.inicializa(nombre)

    def _lee(self):
        for line in self.p.stdout:
            line = line.strip()
            if line:
                self.q.put(line)

    def _lee_stderr(self):
        for line in self.p.stderr:
            self.errores.append(line.rstrip('\r\n'))

    def send(self, o):
        self.p.stdin.write((o if isinstance(o, str) else json.dumps(o)) + '\n')
        self.p.stdin.flush()

    def recv(self, rid, t=None):
        dl = time.time() + (self.t if t is None else t)
        while time.time() < dl:
            try:
                line = self.q.get(timeout=1)
            except queue.Empty:
                continue
            try:
                m = json.loads(line)
            except Exception:
                continue
            if m.get('id') == rid:
                return m
        return None

    def inicializa(self, nombre='bateria', capacidades=None):
        self.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": self.protocolo, "capabilities": capacidades or {},
            "clientInfo": {"name": nombre, "version": "1"}}})
        self.init = self.recv(1)
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        return self.init

    def request(self, method, params=None, t=None):
        """Una peticion cualquiera; devuelve el mensaje de respuesta o None.
        Cada peticion lleva y espera SU id; pero la cola es una, asi que para
        rafagas desde varios hilos, un Stdio por hilo."""
        with self._lock:
            self.rid += 1
            rid = self.rid
        o = {"jsonrpc": "2.0", "id": rid, "method": method}
        if params is not None:
            o['params'] = params
        self.send(o)
        return self.recv(rid, t)

    def call_msg(self, name, args, t=None):
        return self.request('tools/call', {"name": name, "arguments": args}, t)

    def call(self, name, args, t=None):
        """El texto de la tool (ver texto())."""
        return texto(self.call_msg(name, args, t), self.respaldo_json)

    def cierra(self, t=20):
        """Fin de stdin = el cliente se fue: salida LIMPIA; si no sale, se mata."""
        try:
            self.p.stdin.close()
        except Exception:
            pass
        try:
            self.p.wait(t)
        except subprocess.TimeoutExpired:
            self.p.kill()

    def mata(self):
        try:
            self.p.kill()
        except Exception:
            pass


# ---------------------------------------------------------------- http

ACCEPT_STREAMABLE = 'application/json, text/event-stream'


def post(url, body, token=None, sid=None, accept=ACCEPT_STREAMABLE, t=120, cabeceras=None):
    """POST crudo a url: (status, cabeceras, texto). Un 4xx/5xx NO lanza: es
    una respuesta mas que la bateria mira. accept es lo que pide un cliente
    streamable-HTTP; una bateria que prueba el JSON a secas pasa el suyo."""
    h = {'Content-Type': 'application/json', 'Accept': accept}
    if token:
        h['Authorization'] = 'Bearer ' + token
    if sid:
        h['Mcp-Session-Id'] = sid
    if cabeceras:
        h.update(cabeceras)
    data = body if isinstance(body, (bytes, str)) else json.dumps(body)
    if isinstance(data, str):
        data = data.encode('utf-8')
    req = urllib.request.Request(url, data=data, headers=h, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=t) as r:
            return r.status, r.headers, r.read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read().decode('utf-8', 'replace')


# El sid por defecto de una llamada: la sesion PROPIA del cliente. Un sid
# vacio pasado a proposito (el session() de otro agente que fallo) no cae en
# silencio a la ultima sesion de este cliente -esa llamada hablaria como otro
# agente-: lanza. Visto al pasar test_identity/test_round15 (26-sep).
PROPIA = object()


class Http:
    """Cliente Streamable HTTP contra http://127.0.0.1:<puerto>/mcp.

    t: plazo por defecto de cada peticion de ESTE cliente. protocolo: el
    protocolVersion que se presenta. respaldo_json: ver texto(). self.init
    es la respuesta del initialize (session()). sid=... en una llamada usa
    otra sesion solo para esa llamada."""

    def __init__(self, puerto, token=None, ruta='/mcp', host='127.0.0.1', t=120,
                 protocolo=None, respaldo_json=False):
        self.url = 'http://%s:%d%s' % (host, puerto, ruta)
        self.token = token
        self.sid = None
        self.rid = 100
        self.t = t
        self.protocolo = protocolo or PROTOCOLO
        self.respaldo_json = respaldo_json
        self.init = None
        self._lock = threading.Lock()

    def _sid(self, sid):
        if sid is PROPIA:
            return self.sid
        if not sid:
            raise RuntimeError('sid vacio: el session() de ese agente no dio sesion')
        return sid

    def post(self, body, sid=PROPIA, token=None, t=None, cabeceras=None, accept=ACCEPT_STREAMABLE):
        """POST crudo a este servidor (ver post()); el token y la sesion de
        este cliente salvo que se pasen otros."""
        return post(self.url, body, self.token if token is None else token,
                    self._sid(sid), accept, self.t if t is None else t, cabeceras)

    @staticmethod
    def mensajes(raw):
        """Los mensajes JSON-RPC de una respuesta (SSE 'data:' o JSON suelto)."""
        msgs = []
        for l in raw.splitlines():
            if l.startswith('data:'):
                try:
                    msgs.append(json.loads(l[5:].strip()))
                except Exception:
                    pass
        if not msgs:
            try:
                v = json.loads(raw)
                msgs = v if isinstance(v, list) else [v]
            except Exception:
                pass
        return msgs

    def rpc(self, body, sid=PROPIA, t=None):
        """(mensajes, session-id) como las baterias de siempre."""
        st, h, raw = self.post(body, sid, t=t)
        return self.mensajes(raw), (h.get('Mcp-Session-Id') if h else None)

    def session(self, nombre='bateria', capacidades=None):
        """initialize + initialized; deja el session-id puesto y lo devuelve
        (la respuesta del initialize queda en self.init)."""
        self.sid = None
        msgs, sid = self.rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": self.protocolo, "capabilities": capacidades or {},
            "clientInfo": {"name": nombre, "version": "1"}}})
        self.init = next((m for m in msgs if m.get('id') == 1), None)
        self.sid = sid
        self.rpc({"jsonrpc": "2.0", "method": "notifications/initialized"})
        return sid

    def request(self, method, params=None, t=None, sid=PROPIA):
        """Seguro entre hilos: cada peticion lleva y busca SU id."""
        with self._lock:
            self.rid += 1
            rid = self.rid
        o = {"jsonrpc": "2.0", "id": rid, "method": method}
        if params is not None:
            o['params'] = params
        msgs, _ = self.rpc(o, sid=sid, t=t)
        for m in msgs:
            if m.get('id') == rid:
                return m
        return None

    def call_msg(self, name, args, t=None, sid=PROPIA):
        return self.request('tools/call', {"name": name, "arguments": args}, t, sid)

    def call(self, name, args, t=None, sid=PROPIA):
        return texto(self.call_msg(name, args, t, sid), self.respaldo_json)

    def toolnames(self, sid=PROPIA):
        m = self.request('tools/list', sid=sid)
        return {x['name'] for x in ((m or {}).get('result') or {}).get('tools', [])}
