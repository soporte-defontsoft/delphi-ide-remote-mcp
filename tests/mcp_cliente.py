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
import base64
import ctypes
import glob
import hashlib
import json, os, queue, re, shutil, signal, socket, stat, subprocess, sys, tempfile, threading, time
import urllib.error, urllib.parse, urllib.request
import string, winreg
import concurrent.futures

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
EXE_COMPILADO = os.path.join(REPO, 'src', 'Server', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
# La raiz temporal que comparten todas las baterias (run_all la barre).
RAIZ = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests')
# el LOCALAPPDATA de los servidores de prueba (entorno): su cache, no la de
# produccion. Bajo RAIZ, que run_all vacia al empezar
CACHE_BATERIAS = os.path.join(RAIZ, '_cache_servidor')
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


def fuga_de_letra(texto, letras=None, con_separador=True):
    """Las apariciones de una unidad REAL en un texto: [] si no se escapa
    ninguna. EL lector de la casa (revisor de baterias, 18-oct-2026: siete
    baterias con el suyo, y cada uno con su ceguera: solo la mayuscula, solo
    tras una comilla, ciego tras un \\n escapado en JSON...).
    letras: la o las que se buscan ('C', 'z:', ['d', 'e']); sin ellas,
    cualquiera. La forma virtual (srvX:) no cuenta. Cuenta la letra sola o
    tras algo que no es letra ni digito, o tras un escape de JSON (\\n \\r \\t
    \\"), en mayuscula o minuscula; detras, los dos puntos y una barra (\\ o /,
    tambien escapadas en JSON o en URL, o los dos puntos en URL: %3A) o, con
    con_separador=False, los dos puntos solos (el motivo de una raiz: "drive
    Z: is not connected"; sin letras daria falsos con cualquier 'x:')."""
    low = re.sub(r'srv[a-z]:', '', (texto or '').lower())
    if letras is None:
        cuales = '[a-z]'
    else:
        if isinstance(letras, str):
            letras = [letras]
        cuales = '[' + ''.join(l.strip()[0].lower() for l in letras if l and l.strip()) + ']'
    antes = r'(?:(?<![a-z0-9])|(?<=\\[nrt"]))'
    despues = r'(?::(?:\\|/|%5c|%2f)|%3a)' if con_separador else r'(?::|%3a)'
    return re.findall(antes + cuales + despues, low)


_PAPELERA = {}


def _papelera():
    """Las constantes de la papelera, leidas de sus nombradores en el servidor:
    la carpeta y la marca de dueno de Lsp.Casa (desde el 8-oct-2026), los
    cajones de Lsp.Patch. Las baterias no las escriben a mano: tres checks
    buscaban la forma de antes de la sexta revision y se pusieron rojos por
    eso, no por el servidor (28-sep-2026)."""
    if not _PAPELERA:
        for unidad, nombres in (('Lsp.Casa.pas', ('BACKUP_SUB', 'MARCA_DUENO_EXT',
                                                  'BUZON_SIN_WORKSPACE', 'BUZON_PREFIJO_WORKSPACE',
                                                  'IDE_COPIAS_SUB', 'CAPTURAS_SUB', 'DESCARGA_PREFIJO')),
                                ('Lsp.Patch.pas', ('CAJON_BORRADOS', 'CAJON_ANTES_DE_RESTAURAR',
                                                   'CAJON_SUSTITUIDOS', 'CAJON_CORRUPTOS',
                                                   'TEMPORAL_DE_SUSTITUCION_EXT'))):
            with open(os.path.join(REPO, 'src', 'Server', unidad),
                      encoding='utf-8-sig', errors='replace') as fh:
                t = fh.read()
            for n in nombres:
                _PAPELERA[n] = re.search(r"\b%s\s*=\s*'([^']*)'" % n, t).group(1)
            # y los nombres que la casa compone en una funcion: la carpeta de los
            # temporales (TempFolderName) y la de los informes (CarpetaDeInformes)
            if unidad == 'Lsp.Casa.pas':
                _PAPELERA['TempFolderName'] = re.search(
                    r"function TempFolderName: string;\s*begin\s*Result := '([^']*)'", t).group(1)
                _PAPELERA['CarpetaDeInformes'] = re.search(
                    r"function CarpetaDeInformes: string;\s*begin\s*Result := ServerDir\('([^']*)'\)", t).group(1)
    return _PAPELERA


def dia_de_papelera(t=None):
    """El nombre de la carpeta de un dia de la papelera, como NombreDeDia del
    servidor ('yyyymmdd'; hoy si no se dice otro): las baterias no lo
    componen a mano (revisor de 9a9c4cc, 9-oct-2026)."""
    return time.strftime('%Y%m%d', t or time.localtime())


# EL nombre de la carpeta de la papelera y el del cajon de lo borrado, leidos
# de sus nombradores en el servidor: las baterias no los escriben a mano
# (test_paisaje lo vigila tambien en tests/*.py; 2.3 de la 1.18.0). Con el
# nombre a mano, una comprobacion de AUSENCIA pasaria en verde si cambiara.
PAPELERA = _papelera()['BACKUP_SUB']
CAJON_BORRADOS = _papelera()['CAJON_BORRADOS']
CAJON_CORRUPTOS = _papelera()['CAJON_CORRUPTOS']
# ...y los de las comprobaciones de AUSENCIA que se escribian a mano (revisor de
# version de la 1.18.0): el intermedio del escritor atomico, la carpeta de los
# temporales, la de las copias del IDE y la de los informes
TEMPORAL_SUSTITUCION_EXT = _papelera()['TEMPORAL_DE_SUSTITUCION_EXT']
TEMPORALES = _papelera()['TempFolderName']
IDE_COPIAS = _papelera()['IDE_COPIAS_SUB']
INFORMES = _papelera()['CarpetaDeInformes']
# ...y el prefijo de la carpeta de cada llamada (NuevaCarpetaDescarga): tres
# baterias lo escribian a mano en sus comprobaciones de que no queda (V22)
DESCARGA_PREFIJO = _papelera()['DESCARGA_PREFIJO']


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
    CAJON_SUSTITUIDOS, CAJON_ANTES_DE_RESTAURAR, CAJON_CORRUPTOS); None,
    todos. nombre None:
    las de cualquier fichero. bajo=True: en TODAS las papeleras bajo carpeta
    (hay una junto a cada carpeta de lo que se tiro)."""
    p = _papelera()
    patron = os.path.join(os.path.join(carpeta, '**') if bajo else carpeta,
                          p['BACKUP_SUB'], '*', p[cajon] if cajon else '*',
                          (glob.escape(nombre) if nombre else '*') + '-*')
    sello = re.compile((re.escape(nombre) if nombre else '.+') + r'-\d{9}$', re.I)
    return sorted(f for f in glob.glob(patron, recursive=bajo)
                  if sello.match(os.path.basename(f)))


def subida_en_dos(ruta, datos, sha256):
    """Los argumentos de un delphi_upload de DOS trozos, con el sha256 final en el
    segundo: la forma en que un sha256 final que no casa con lo YA escrito manda la
    subida a la cuarentena (UPLOAD-011, cajon CAJON_CORRUPTOS). Con el fichero entero
    en UNA llamada el servidor lo comprueba antes de escribir y no escribe nada
    (UPLOAD-015, 1.22.0: test completo de Hermes). datos: 2 bytes o mas."""
    assert len(datos) >= 2, 'una subida en dos necesita 2 bytes o mas'
    m = len(datos) // 2
    return [{'path': ruta, 'offset': 0, 'chunkbase64': base64.b64encode(datos[:m]).decode('ascii')},
            {'path': ruta, 'offset': m, 'chunkbase64': base64.b64encode(datos[m:]).decode('ascii'),
             'sha256': sha256}]


def slug(s):
    """Slug del servidor (Lsp.Casa): letras y cifras ASCII, lo demas un guion,
    40 como mucho, sin guiones en los bordes, en minusculas."""
    r, prev = '', '-'
    for c in s:
        if c.isascii() and c.isalnum():
            r, prev = r + c, c
        elif prev != '-':
            r, prev = r + '-', '-'
        if len(r) >= 40:
            break
    return r.strip('-').lower()


def carpeta_de_workspace(ws=''):
    """La carpeta de un workspace dentro de un buzon (CarpetaDeWorkspace del
    servidor): sin workspace -el proceso local, las baterias en stdio-
    BUZON_SIN_WORKSPACE; si no, BUZON_PREFIJO_WORKSPACE y su slug, y si el
    slug no lo dice entero, ocho del MD5 del nombre en minusculas detras."""
    if not ws:
        return _papelera()['BUZON_SIN_WORKSPACE']
    s = slug(ws)
    if s != ws.lower():
        s = (s + '-' if s else '') + hashlib.md5(ws.lower().encode('utf-8')).hexdigest()[:8]
    return _papelera()['BUZON_PREFIJO_WORKSPACE'] + s


def buzon(raiz, agente='', ws=''):
    """<raiz>\\<workspace>[\\<agente>]: el buzon de BuzonDeMensajes /
    BuzonDeInformes, con raiz la carpeta messages o reports junto al exe. Las
    baterias no componen el buzon a mano: la estructura cambio el 10-oct-2026
    (una carpeta por workspace) y seis lo hacian."""
    b = os.path.join(raiz, carpeta_de_workspace(ws))
    return os.path.join(b, slug(agente)) if slug(agente) else b


def casa_de_capturas(srv_dir, agente='', ws=None):
    """La casa de capturas del servidor de srv_dir (CasaDeCapturas):
    <srv_dir>\\<temporales>\\<capturas>\\<workspace>[\\<agente>], con el buzon de
    siempre. ws=None: la carpeta de capturas ENTERA, la de todos los
    workspaces (para un glob con '**'). Las baterias no la componen a mano:
    seis lo hacian (revisor del 2af de la 1.18.2)."""
    raiz = os.path.join(srv_dir, TEMPORALES, _papelera()['CAPTURAS_SUB'])
    return raiz if ws is None else buzon(raiz, agente, ws)


def cache_servidor(sub='', appdata=None):
    """<LOCALAPPDATA>\\DelphiLspMcp\\<sub>: la cache del servidor (ServerCacheDir).
    Sin appdata, la de las BATERIAS (CACHE_BATERIAS, la que da entorno). El
    compositor de esa ruta: estaba a mano en mcp_cliente y en una bateria."""
    return os.path.join(appdata or CACHE_BATERIAS, 'DelphiLspMcp', sub)


def ajustes_fabricados(dpr, appdata=None):
    """El .delphilsp.json que fabrico el servidor para ese .dpr (su cache de
    configuraciones), por la ruta LARGA y entera: la bateria la tiene corta
    (8.3, del %TEMP%) y el servidor la escribe larga; comparar solo la cola
    cruzaba las dos formas en las carpetas cortas (j3, j9 de json_nuestro,
    18-oct-2026). '' si no hay. Vivia en test_json_nuestro_1202: la segunda
    bateria que lo necesito (V91 de la 1.23.1) lo trajo aqui."""
    quiero = os.path.normcase(larga(dpr))
    carpeta = cache_servidor('configs', appdata)
    for f in (os.listdir(carpeta) if os.path.isdir(carpeta) else []):
        p = os.path.join(carpeta, f)
        try:
            proj = json.load(open(p, encoding='utf-8-sig'))['settings']['project']
        except Exception:
            continue
        ruta = (urllib.parse.unquote(urllib.parse.urlparse(proj).path).lstrip('/')
                if proj.startswith('file:') else real(proj))
        if os.path.normcase(larga(ruta)) == quiero:
            return p
    return ''


def planta_intermedios(carpeta):
    """Dos intermedios del escritor atomico ('.<nombre>.<8 hex>' + su extension,
    Lsp.Patch.TemporalDeSustitucion) en carpeta: uno de hace dos horas (un
    escritor que murio a medias: la purga de la casa lo quita) y uno de ahora
    (uno vivo: se queda). (viejo, fresco). V17 de la 1.23: las purgas de las
    tablas del disenador y de los ajustes del motor no los veian."""
    os.makedirs(carpeta, exist_ok=True)
    viejo = os.path.join(carpeta, '.muerto.txt.0123abcd' + TEMPORAL_SUSTITUCION_EXT)
    fresco = os.path.join(carpeta, '.vivo.txt.89abcdef' + TEMPORAL_SUSTITUCION_EXT)
    for p in (viejo, fresco):
        open(p, 'wb').write(b'x')
    hace = time.time() - 2 * 3600
    os.utime(viejo, (hace, hace))
    return viejo, fresco


def limpia_caches_lsp():
    """Las caches .delphilsp.json de proyectos de las BATERIAS (bajo RAIZ) que
    hayan caido en la cache REAL del usuario (%LOCALAPPDATA%\\DelphiLspMcp\\configs):
    basura de la maquina (131 medidas el 28-sep-2026). Desde el 4-oct-2026 las
    baterias tienen su propia cache (entorno), asi que una aqui es de una
    bateria que no paso por entorno. Solo esas: la cache real es la del
    servicio de produccion, y 'un proyecto que ya no existe' puede ser suyo
    (una letra de red sin montar). Devuelve cuantas quito."""
    from urllib.parse import unquote
    carpeta = cache_servidor('configs', os.environ.get('LOCALAPPDATA', ''))
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
        if os.path.normcase(os.path.abspath(ruta)).startswith(raiz):
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


def pid_vivo(pid):
    """True si el proceso pid sigue vivo (su codigo de salida es STILL_ACTIVE,
    259); False si ya no existe o acabo. Vivia en test_render_hijos_118 y lo
    necesita test_remoterun (revisor de baterias, 18-oct-2026: "el proceso ha
    muerto" miraba la ausencia de un .pid que borro la propia bateria)."""
    import ctypes
    k = ctypes.WinDLL('kernel32', use_last_error=True)
    k.OpenProcess.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_uint32]
    k.OpenProcess.restype = ctypes.c_void_p
    k.CloseHandle.argtypes = [ctypes.c_void_p]
    k.GetExitCodeProcess.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
    h = k.OpenProcess(0x1000, 0, pid)                     # QUERY_LIMITED_INFORMATION
    if not h:
        err = ctypes.get_last_error()
        if err == 87:                                     # ERROR_INVALID_PARAMETER: no existe
            return False
        raise ctypes.WinError(err)
    try:
        code = ctypes.c_uint32()
        if not k.GetExitCodeProcess(h, ctypes.byref(code)):
            raise ctypes.WinError(ctypes.get_last_error())
        return code.value == 259
    finally:
        k.CloseHandle(h)


def consola(args, **kw):
    """Un programa de CONSOLA de Windows (sc, icacls, cmd /c dir, mklink...) con
    su salida leida en SU pagina, la OEM, y no en UTF-8: con -X utf8 una tilde
    de su texto ("INFORMACION", "Accion") reventaba el hilo lector y stdout
    llegaba None (27-oct-2026: test_service_smoke con sc query, y
    test_delphi_test_contenedor con tasklist). Lo demas, como subprocess.run."""
    return subprocess.run(args, capture_output=True, encoding='oem', errors='replace', **kw)


def memoria_pico(pid):
    """Los bytes PRIVADOS que el proceso pid ha llegado a tener (PeakPagefileUsage
    de GetProcessMemoryInfo): lo que mide si un servidor leyo entero algo que
    no debia (test_cola_salida_1231, V80 de la 1.23.1)."""
    import ctypes
    from ctypes import wintypes

    class _Cuentas(ctypes.Structure):
        _fields_ = [('cb', wintypes.DWORD), ('PageFaultCount', wintypes.DWORD)] + [
            (n, ctypes.c_size_t) for n in (
                'PeakWorkingSetSize', 'WorkingSetSize', 'QuotaPeakPagedPoolUsage', 'QuotaPagedPoolUsage',
                'QuotaPeakNonPagedPoolUsage', 'QuotaNonPagedPoolUsage', 'PagefileUsage', 'PeakPagefileUsage')]
    k = ctypes.WinDLL('kernel32', use_last_error=True)
    k.OpenProcess.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_uint32]
    k.OpenProcess.restype = ctypes.c_void_p
    k.CloseHandle.argtypes = [ctypes.c_void_p]
    p = ctypes.WinDLL('psapi', use_last_error=True)
    p.GetProcessMemoryInfo.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32]
    h = k.OpenProcess(0x1000 | 0x0010, 0, pid)            # QUERY_LIMITED_INFORMATION | VM_READ
    if not h:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        c = _Cuentas()
        c.cb = ctypes.sizeof(c)
        if not p.GetProcessMemoryInfo(h, ctypes.byref(c), c.cb):
            raise ctypes.WinError(ctypes.get_last_error())
        return c.PeakPagefileUsage
    finally:
        k.CloseHandle(h)


def etiqueta_de_integridad(ruta):
    """El SID de la etiqueta de integridad de ruta, preguntado a WINDOWS (su
    SACL, GetNamedSecurityInfo): 'S-1-16-4096' Low, 'S-1-16-8192' Medium...;
    None si no lleva etiqueta explicita (la de por defecto, Medium). Dos
    baterias leian el texto de icacls en ingles o en castellano: en otro
    idioma no la veian nunca (revisor de baterias, 18-oct-2026)."""
    import ctypes
    from ctypes import wintypes as wt
    adv = ctypes.WinDLL('advapi32', use_last_error=True)
    k = ctypes.WinDLL('kernel32')
    adv.GetNamedSecurityInfoW.argtypes = [wt.LPCWSTR, ctypes.c_int, wt.DWORD, ctypes.c_void_p, ctypes.c_void_p,
                                          ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p),
                                          ctypes.POINTER(ctypes.c_void_p)]
    adv.GetNamedSecurityInfoW.restype = wt.DWORD
    adv.GetAce.argtypes = [ctypes.c_void_p, wt.DWORD, ctypes.POINTER(ctypes.c_void_p)]
    adv.ConvertSidToStringSidW.argtypes = [ctypes.c_void_p, ctypes.POINTER(wt.LPWSTR)]
    k.LocalFree.argtypes = [ctypes.c_void_p]
    sacl, sd = ctypes.c_void_p(), ctypes.c_void_p()
    # SE_FILE_OBJECT = 1, LABEL_SECURITY_INFORMATION = 0x10 (se lee sin privilegios)
    err = adv.GetNamedSecurityInfoW(ruta, 1, 0x10, None, None, None, ctypes.byref(sacl), ctypes.byref(sd))
    if err:
        raise ctypes.WinError(err)
    try:
        if not sacl.value:
            return None
        cuantos = ctypes.c_ushort.from_address(sacl.value + 4).value     # ACL.AceCount
        for i in range(cuantos):
            ace = ctypes.c_void_p()
            if not adv.GetAce(sacl, i, ctypes.byref(ace)):
                continue
            if ctypes.c_ubyte.from_address(ace.value).value != 0x11:     # SYSTEM_MANDATORY_LABEL_ACE
                continue
            texto = wt.LPWSTR()
            if adv.ConvertSidToStringSidW(ace.value + 8, ctypes.byref(texto)):   # header(4) + mask(4)
                try:
                    return texto.value
                finally:
                    k.LocalFree(texto)
        return None
    finally:
        k.LocalFree(sd)


def suspende(pid):
    """Suspende un proceso: sigue vivo y deja de leer, de contestar y de gastar
    CPU. Asi se ve un motor COLGADO. Andamio, no lo que se mide. Estaba en
    test_lsp_paralelo y lo necesita tambien test_motor_vida: UNA."""
    import ctypes
    k32 = ctypes.windll.kernel32
    k32.OpenProcess.restype = ctypes.c_void_p
    h = k32.OpenProcess(0x0800, False, pid)              # PROCESS_SUSPEND_RESUME
    if not h:
        return False
    rc = ctypes.windll.ntdll.NtSuspendProcess(ctypes.c_void_p(h))
    k32.CloseHandle(ctypes.c_void_p(h))
    return rc == 0


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
    # unas pasadas: un proceso que acaba de morir (el servidor, un
    # renderizador suyo) suelta sus ficheros un poco despues, y una sola
    # pasada dejaba el arbol a medias en %TEMP% (segunda revision de la 1.17.0)
    for i in range(20):
        shutil.rmtree(ruta, onexc=quita_ro)
        if not os.path.exists(ruta):
            return
        if i == 0:
            # un deny de ilegible() que viajo con su carpeta (la operacion la
            # movio): fuera en todo el arbol, o rmtree no entra nunca
            subprocess.run(['icacls', ruta, '/remove:d', os.environ.get('USERNAME', ''), '/t', '/c', '/q'],
                           capture_output=True)
        time.sleep(0.5)


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


@contextlib.contextmanager
def ilegible(ruta):
    """La CARPETA no se deja listar mientras dura el bloque: un deny de
    "leer datos / listar" (RD) para el usuario que corre la bateria, que es el
    del servidor que lanza, sin herencia. Al salir se quita el deny; si la
    operacion la movio, lo quita borra() en el arbol que la contenga."""
    yo = os.environ.get('USERNAME', '')
    subprocess.run(['icacls', ruta, '/deny', yo + ':(RD)'], capture_output=True, check=True)
    try:
        yield ruta
    finally:
        if os.path.exists(ruta):
            subprocess.run(['icacls', ruta, '/remove:d', yo], capture_output=True)


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


# donde busca el RTL de Delphi el idioma de un exe (System.pas,
# GetLocaleOverride): un valor por exe, con su ruta LARGA
LOCALES_RTL = r'Software\Embarcadero\Locales'


@contextlib.contextmanager
def idioma_rtl(exe, idioma):
    """El RTL de Delphi de ESE exe habla otro idioma mientras dura el bloque
    ('DE', 'FR', 'JA': los rtl370.de/.fr/.ja que instala el IDE junto a
    rtl370.bpl), y se quita al salir. Un Windows es-ES no tiene ES y lee en
    ingles; uno aleman, en aleman (medido el 18-oct-2026 con el ayudante FMX:
    "Fehler beim Lesen von EditRight.FontColor")."""
    nombre = larga(exe)
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, LOCALES_RTL) as k:
        winreg.SetValueEx(k, nombre, 0, winreg.REG_SZ, idioma)
    try:
        yield nombre
    finally:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, LOCALES_RTL, 0, winreg.KEY_SET_VALUE) as k:
            winreg.DeleteValue(k, nombre)


def raiz_del_ide(bds='37.0'):
    """La carpeta del IDE sin la barra final, leida del registro: lo que el
    servidor le dice al renderizador con --bdsroot."""
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, 'Software\\Embarcadero\\BDS\\%s' % bds) as k:
        return winreg.QueryValueEx(k, 'RootDir')[0].rstrip('\\')


def juez_en_idioma(render, form, idioma, bds='37.0'):
    """Lo que dice el renderizador RENDER, lanzado a mano y con su RTL en ese
    idioma, al cargar FORM como lo juzga el servidor. A mano: el idioma de un
    exe se elige en HKCU (idioma_rtl), que dentro del contenedor no se lee y
    alli no llegaria; dentro habla el de Windows (V65 de la 1.24)."""
    with idioma_rtl(render, idioma):
        p = subprocess.run([render, '--path', form, '--writeback', 'on', '--timeout', '120000', '--bds', bds,
                            '--bdsroot', raiz_del_ide(bds)], capture_output=True, timeout=240,
                           cwd=os.path.dirname(form))
    return p.stdout.decode('utf-8', 'replace')


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
# Win32, como el IDE: su escritor de texto es el del IDE (los flotantes con 18 decimales; V141 de la 1.23.1)
CONVERSOR_COMPILADO = os.path.join(REPO, 'src', 'StyleConvert', 'Compiled', 'Win32', 'Release', CONVERSOR)
# Los renderizadores de forms de delphi_designer preview (1.17.0): Win32, junto
# al servidor como el conversor. UNA tabla de ayudantes -> donde se compilan,
# para run_all (la copia limpia) y copia_exe (la de cada bateria).
RENDERIZADORES = ('DelphiFormRenderVcl.exe', 'DelphiFormRenderFmx.exe')
AYUDANTES = {CONVERSOR: CONVERSOR_COMPILADO}
AYUDANTES.update({r: os.path.join(REPO, 'src', 'Render', 'Win32', 'Release', r) for r in RENDERIZADORES})


def copia_exe(dest_dir, src=None, con_conversor=False, con_render=False):
    """Copia el servidor a dest_dir y devuelve la ruta de la copia: cada
    bateria corre el suyo, con su settings.ini, sus logs y su __delphi-temp.
    con_conversor: delphi_styles necesita DelphiStyleConvert.exe AL LADO del
    servidor; va el que acompane al exe bajo prueba (run_all lo pone junto a
    su copia limpia) o, si no lo trae, el compilado de src/StyleConvert.
    con_render: los dos renderizadores de delphi_designer preview, igual."""
    os.makedirs(dest_dir, exist_ok=True)
    origen = src or exe_origen()
    exe = os.path.join(dest_dir, 'DelphiLspMcp.exe')
    shutil.copy(origen, exe)
    for nombre in ((CONVERSOR,) if con_conversor else ()) + (RENDERIZADORES if con_render else ()):
        junto = os.path.join(os.path.dirname(os.path.abspath(origen)), nombre)
        shutil.copy(junto if os.path.exists(junto) else AYUDANTES[nombre],
                    os.path.join(dest_dir, nombre))
    return exe


# ---------------------------------------------------------------- arranque

def puerto_libre():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    p = s.getsockname()[1]
    s.close()
    return p


def letras_libres(cuantas):
    """Letras que no son una unidad de esta sesion ni un mapeo persistente de
    la cuenta: para el servidor, letras que no existen y que no puede conectar.
    Una copia: estaba igual en test_letras_red y test_raiz_unidad, y la tercera
    bateria que la necesitaba (test_paredes_1131) la trajo aqui."""
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


class ServidorHttp(subprocess.Popen):
    """Un servidor HTTP de bateria se PARA, no se mata. El exe lleva VCL
    (la bandeja y el servicio) y registra atomos globales al arrancar que
    solo borra su finalizacion: matado con TerminateProcess los deja en la
    tabla de la sesion (16384 para todos los procesos) para siempre. Medido
    el 18-oct-2026: 3.894 servidores de bateria matados con proc.kill() (81
    sitios en tests/) la llenaron, y con la tabla llena Windows no arranca
    NINGUN proceso (0xC0000142): 195 baterias rojas y la maquina de David
    caida. kill() y terminate() aqui son CTRL_BREAK, que el servidor atiende
    (DelphiLspMcp.dpr ConsoleCtrl -> ShutdownEvent: para el HTTP y finaliza);
    el kill de verdad, solo si no sale en 15 s. Los 81 sitios no cambian:
    siguen llamando a proc.kill(), que ahora para. Un servidor lanzado SIN
    consola (CREATE_NO_WINDOW, DETACHED_PROCESS: lanza_http lo apunta en
    sin_consola) no recibe el CTRL_BREAK: se mata y se recoge sin esperar
    (medido el 19-oct-2026 con test_handles_heredados)."""
    PLAZO_PARADA = 15
    sin_consola = False

    def kill(self):
        if self.poll() is None and not self.sin_consola:
            try:
                self.send_signal(signal.CTRL_BREAK_EVENT)
                self.wait(self.PLAZO_PARADA)
                return
            except (OSError, ValueError, subprocess.TimeoutExpired):
                pass
        mata_y_recoge(self)

    terminate = kill


def lanza_http(exe, puerto=None, env=None, args=(), segundos=30, espera=True, **popen):
    """Arranca exe --http [puerto] y ESPERA a que escuche. Sin puerto, el que
    diga su settings.ini: entonces hay que pasar el que se espera en
    'espera_en'. Devuelve el proceso (ServidorHttp: su kill() lo PARA); si no
    llega a escuchar, lo mata y lanza RuntimeError con el motivo (la bateria
    lo ve, no un sleep mudo). espera=False: lo devuelve en cuanto existe, para
    la bateria que lo apunta ANTES de esperar (y espera ella, con
    espera_puerto): el lanzamiento y la parada son los de aqui igual."""
    espera_en = popen.pop('espera_en', puerto)
    cmd = [exe, '--http'] + ([str(puerto)] if puerto is not None else []) + list(args)
    popen.setdefault('stdout', subprocess.DEVNULL)
    popen.setdefault('stderr', subprocess.DEVNULL)
    # su propio grupo de procesos: CTRL_BREAK le llega a el y no a la bateria
    popen['creationflags'] = popen.get('creationflags', 0) | subprocess.CREATE_NEW_PROCESS_GROUP
    proc = ServidorHttp(cmd, env=env, **popen)
    proc.sin_consola = bool(popen['creationflags'] & (subprocess.CREATE_NO_WINDOW | subprocess.DETACHED_PROCESS))
    if not espera:
        return proc
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


def imprime(linea):
    """Una linea a la consola, tambien si no cabe en su pagina: un detalle con
    un caracter de fuera (un 日本 con la salida redirigida en CP1252, una o con
    tilde en una 1251) reventaba la bateria justo en la linea que tenia que
    contar, y lo de despues no se veia (E148 contra la novena)."""
    try:
        print(linea)
    except UnicodeEncodeError:
        print(linea.encode('ascii', 'backslashreplace').decode('ascii'))


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
        imprime('  FAIL %s | %s' % (name, ' '.join(str(detail).splitlines())[:300]))
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
# V52 (25-oct-2026): una bateria NUNCA despliega lo suyo (el nodo, un proyecto) en un destino REAL -el Zorin
# de David, un PAServer de verdad- salvo que quien la corre lo pida con esta variable a '1'. Dos veces una
# bateria con un perfil real empujo SU nodo al Zorin, y produccion, que mira el sello una vez por sesion,
# siguio con el nodo ajeno sin saberlo
DESTINO_REAL = 'MCP_BATERIAS_DESTINO_REAL'


def destino_real_pedido():
    """True si quien corre la bateria pide medir contra un destino real (DESTINO_REAL=1)."""
    return os.environ.get(DESTINO_REAL, '') == '1'


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


# ------------------------------------------------------------ la pagina ANSI
# LA pagina ANSI de esta maquina, preguntada a Windows: en la que el servidor
# lee y escribe un fuente sin BOM (Lsp.Codificacion.PaginaAnsi). Tres
# baterias la preguntaban cada una por su cuenta.
ANSI = ctypes.windll.kernel32.GetACP()


def en_la_1252(que):
    """True si esta maquina lee en la 1252. Si no, dice que QUE no se mide
    (SKIP, que run_all lista): sus bytes o lo que espera son de la 1252 y en
    otra pagina daria un rojo falso (r5-L4). Las otras paginas las miden los
    DUnitX (UsaPaginaAnsi). Medido el 24-oct-2026 con una copia del exe en la
    1251 (activeCodePage en su manifiesto): 44 checks de 13 baterias."""
    if ANSI == 1252:
        return True
    imprime('SKIP %s: sus bytes o lo que espera son de la pagina 1252, y esta maquina lee en la %d'
            % (que, ANSI))
    return False


def check_1252(name, ok, detail=''):
    """check() de lo que solo vale en la 1252 (en_la_1252)."""
    return check(name, ok, detail) if en_la_1252(name) else True


def bateria_de_la_1252(titulo):
    """Al empezar una bateria cuyos fixtures y lo que espera son de la 1252 de
    punta a punta (partirla check a check dejaba verdes vacios: un ancla que
    no casa da otra negativa, y "sin el consejo" pasaba igual): en otra pagina
    lo dice y sale sin checks."""
    if not en_la_1252(titulo):
        fin(titulo, sin_checks='sus fixtures y lo que espera son de la pagina 1252')


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
    # ...ni lo que el arnes de Claude pone y el servicio NO tiene (medido el
    # 13-oct-2026, ni de usuario ni de maquina): NoDefaultCurrentDirectoryInExePath
    # le quita a cmd la busqueda en su carpeta actual, y con ella heredada la
    # sonda del msbuild.bat plantado (2an de la 1.18.2) salio NEGATIVA contra
    # una produccion que si lo ejecutaba
    env = {k: v for k, v in env.items() if k.upper() != 'NODEFAULTCURRENTDIRECTORYINEXEPATH'}
    # La cache del servidor (ServerCacheDir: tablas del disenador, configs del
    # LSP, el estilo de Windows) es la de las BATERIAS, no la de produccion:
    # con la del usuario, un servidor de prueba (otra huella, otra generacion)
    # PURGABA las tablas del servicio, que tenia que regenerarlas (medido el
    # 4-oct-2026: sus g4 desaparecieron tras una pasada y volvieron a las
    # 11:07), y una bateria pasaba apoyada en las tablas que dejo otra. Bajo
    # RAIZ: run_all la vacia al empezar, y la primera que la necesita la espera
    # (espera_info). Una bateria que mide la cache la pone suya en extra.
    env['LOCALAPPDATA'] = CACHE_BATERIAS
    os.makedirs(env['LOCALAPPDATA'], exist_ok=True)
    env.update(extra or {})
    return env


def host_de_perfil(nombre):
    """El host de un perfil REAL del IDE, leido de su .profile (solo esa clave:
    el fichero lleva la contrasena del PAServer). Una direccion de la red no se
    escribe en una bateria: el repo es publico."""
    p = os.path.join(os.environ['APPDATA'], 'Embarcadero', 'BDS', '37.0', nombre + '.profile')
    with open(p, encoding='utf-8-sig') as f:
        m = re.search(r'<Profile_host>([^<]+)</Profile_host>', f.read())
    return m.group(1) if m else ''


def appdata_perfil(base, nombre='x', host='127.0.0.1', platform='Win64', por_defecto=False):
    """Un %APPDATA% de PRUEBA para un servidor de bateria, con un perfil FALSO.
    Copia del real los ficheros de config que HEREDAN los hijos (paclient,
    msbuild): los .sdk y .proj de cada BDS\\<ver> -copiar es solo leer-, y
    planta <nombre>.profile con host propio. Los .profile reales NO se copian:
    llevan la contrasena del PAServer, y ninguna bateria los necesita.
    por_defecto=True escribe ademas <DefaultProfile> de esa plataforma en la
    copia de EnvOptions.proj: el perfil que msbuild usa cuando nadie le da
    uno (lo que el IDE llama perfil por defecto). Devuelve (appdata_dir,
    host): el primero a env['APPDATA'], el segundo a DELPHI_MCP_REMOTE_HOSTS.
    Desde 1.15.1 la puerta ProfileHostDenido FALLA CERRADO: un perfil de
    bateria tiene que EXISTIR y tener un host permitido para pasar.
    OJO: confina al SERVIDOR (y a msbuild), no al paclient REAL: paclient
    --local escribe y busca los perfiles en la carpeta real diga lo que diga
    APPDATA (medido 9-oct-2026). Lo que no deba llegar a un paclient de verdad
    va contra uno FALSO (DELPHI_MCP_PACLIENT), como test_paserver."""
    import shutil
    ad = os.path.join(base, 'appdata')
    real = os.path.join(os.environ.get('APPDATA', ''), 'Embarcadero', 'BDS')
    xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003" DefaultTargets="">\n'
           '  <PropertyGroup>\n'
           '    <Profile_platform>%s</Profile_platform>\n'
           '    <Profile_host>%s</Profile_host>\n'
           '    <Profile_port>64211</Profile_port>\n'
           '    <Profile_password>00</Profile_password>\n'
           '  </PropertyGroup>\n'
           '</Project>\n' % (platform, host))
    for ver in (os.listdir(real) if os.path.isdir(real) else []):
        sv = os.path.join(real, ver)
        if not os.path.isdir(sv):
            continue
        dv = os.path.join(ad, 'Embarcadero', 'BDS', ver)
        os.makedirs(dv, exist_ok=True)
        for f in os.listdir(sv):
            if f.lower().endswith(('.proj', '.sdk')):
                try:
                    shutil.copy(os.path.join(sv, f), os.path.join(dv, f))
                except Exception:
                    pass
        open(os.path.join(dv, nombre + '.profile'), 'w', encoding='utf-8').write(xml)
        env_opts = os.path.join(dv, 'EnvOptions.proj')
        if por_defecto and os.path.isfile(env_opts):
            t = open(env_opts, encoding='utf-8-sig').read()
            grupo = '<PropertyGroup Condition="\'$(Platform)\'==\'%s\'">' % platform
            assert grupo in t, 'EnvOptions.proj sin el grupo de ' + platform
            t = t.replace(grupo, grupo + '\n        <DefaultProfile>%s</DefaultProfile>' % nombre, 1)
            open(env_opts, 'w', encoding='utf-8').write(t)
    return ad, host


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


def instalacion_activa(call):
    """La instalacion de Delphi que usa el servidor bajo prueba, como la dice su
    delphi_installs (que la lee del registro): {} si no hay ninguna. Estaba a
    mano en seis baterias, y otras cinco componian Program Files (r5-L4)."""
    return next((i for i in (como_json(call('delphi_installs', {})) or {}).get('installs', [])
                 if i.get('active')), {})


def raiz_de_instalacion(inst):
    """La carpeta de una instalacion de delphi_installs, real y sin barra final."""
    return real(inst.get('rootdir', '')).rstrip('\\')


def raiz_ide(call):
    """La carpeta de la instalacion activa ('' si no hay)."""
    return raiz_de_instalacion(instalacion_activa(call))


def variable_de_rsvars(call, nombre):
    """Lo que el rsvars.bat de la instalacion activa pone en una variable
    (BDSCOMMONDIR, de la que cuelga el CatalogRepository): el fichero del IDE,
    el mismo que lee el servidor. '' si no la pone."""
    try:
        with open(os.path.join(raiz_ide(call), 'bin', 'rsvars.bat'), encoding='mbcs', errors='replace') as fh:
            texto = fh.read()
    except OSError:
        return ''
    m = re.search(r'(?im)^\s*@?SET\s+%s=(.*)$' % re.escape(nombre), texto)
    return m.group(1).strip() if m else ''


def a_la_vez(call, primera, segunda, retraso=0.5):
    """La llamada PRIMERA, (tool, args[, plazo]), en un hilo y, RETRASO segundos
    despues, la SEGUNDA, por el MISMO servidor: el call de un Http (por stdio
    serian dos procesos, cada uno con su cerrojo). Para medir que una no
    espera a la otra. ((respuesta, segundos) de la primera, (respuesta,
    segundos) de la segunda, y si la primera seguia cuando volvio la segunda).
    Estaba en test_lector_cerrojo_120 y lo pidio test_designer_tablas."""
    res = {}

    def lanza():
        t0 = time.time()
        res['r'] = call(*primera)
        res['t'] = time.time() - t0
    hilo = threading.Thread(target=lanza)
    hilo.start()
    time.sleep(retraso)
    t0 = time.time()
    r = call(*segunda)
    t = time.time() - t0
    seguia = hilo.is_alive()
    hilo.join(600)
    return (res.get('r', ''), res.get('t', 0)), (r, t), seguia


def espera_tablas(call, tope=240):
    """Las tablas del disenador VCL y FMX, listas: [(marco, respuesta)]. Para
    las baterias que validan contra ellas (el bloque estaba escrito igual en
    dos). Quien llama comprueba: tabla_lista(r)."""
    return [(fw, espera_info(call, {'command': 'info', 'classname': cls, 'framework': fw}, tope=tope))
            for fw, cls in (('vcl', 'TButton'), ('fmx', 'TLabel'))]


def tabla_lista(r):
    """La respuesta de espera_info / espera_tablas dice que la tabla del
    disenador esta lista: ni se esta generando ni ha fallado. Estaba escrito
    igual en diecisiete baterias, con el id a mano (V56)."""
    return not es(r, 'SR_DESIGNER_GENERANDOSE_FMT') and not fallo(r)


def build_ok(call, dproj):
    """delphi_build de un proyecto (Win64 Debug Build): (exito, errores). Estaba
    escrito en tres baterias."""
    out = call('delphi_build', {"project": dproj, "platform": "Win64",
                                "config": "Debug", "target": "Build"}, 600)
    d = como_json(out)
    if not d:
        return False, out[:300]
    return d.get('success') is True, json.dumps(d.get('errors'))[:300]


def lee(p):
    """El texto de un fichero (utf-8 con o sin BOM); '' si no existe: un check
    rojo, no una bateria que se cae."""
    if not os.path.exists(p):
        return ''
    return open(p, 'rb').read().decode('utf-8-sig')


def clave_de_config(dproj_xml, config):
    """La clave (Cfg_N) con la que un .dproj nombra una configuracion: se lee de
    su <BuildConfiguration>, nunca se supone (desde la 1.20.2 delphi_create
    numera como el IDE, Debug Cfg_1 y Release Cfg_2: antes al reves, y una
    bateria que tenia Cfg_2 por Debug se puso roja). '?' si no la declara.
    Estaba en test_auditoria_1201; test_escritor_guardado la necesitaba."""
    m = re.search(r'<BuildConfiguration\s+Include="%s">\s*<Key>(\w+)</Key>' % re.escape(config), dproj_xml)
    return m.group(1) if m else '?'


def espera_info(call, args, cond=lambda r: False, tope=240):
    """delphi_designer con args (info o prop), repetido mientras diga DSGN-051:
    la tabla del disenador se genera en segundo plano la primera vez (tras
    instalar, actualizar o subir su generacion) y info espera un rato y, si no
    ha acabado, lo dice. Para tambien en cuanto cond(respuesta). Una bateria
    que valida contra las tablas las pide con esto antes: test_delphi_patch
    solo pasaba si otra le habia dejado la cache caliente (4-oct-2026, al subir
    GENERACION_TABLAS). Vivia en test_designer_tablas."""
    t0, r = time.time(), ''
    while time.time() - t0 < tope:
        r = call('delphi_designer', args, t=120)
        if cond(r) or not es(r, 'SR_DESIGNER_GENERANDOSE_FMT'):
            return r
        time.sleep(2)
    return r


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
    """{NOMBRE: texto} de Lsp.Texts, de Mld.Textos (el del nodo y el
    lanzador) y de FormRender.Textos (los renderizadores de forms), leidos
    una vez por bateria."""
    if not _CATALOGO:
        for rel in (('src', 'Server', 'Lsp.Texts.pas'), ('src', 'DesktopNode', 'Mld.Textos.pas'),
                    ('src', 'Render', 'FormRender.Textos.pas')):
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


def png_pixeles(ruta):
    """(ancho, alto, pixel) de un PNG de 8 bits RGB o RGBA sin entrelazar (lo
    que escriben la VCL y FMX); pixel(x, y) -> (r, g, b). Sin PIL: zlib y los
    cinco filtros del estandar. Para las baterias que miran DENTRO de una
    captura (delphi_designer preview, 1.17.0): el tamano no dice si se pinto."""
    import zlib, struct
    datos = open(ruta, 'rb').read()
    if datos[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('no es un PNG: %s' % ruta)
    i, idat, ancho, alto, prof, color, entrelazado = 8, b'', 0, 0, 0, 0, 0
    while i < len(datos):
        n, tipo = struct.unpack('>I4s', datos[i:i + 8])
        cuerpo = datos[i + 8:i + 8 + n]
        if tipo == b'IHDR':
            ancho, alto, prof, color, _, _, entrelazado = struct.unpack('>IIBBBBB', cuerpo)
        elif tipo == b'IDAT':
            idat += cuerpo
        i += 12 + n
    if prof != 8 or color not in (2, 6) or entrelazado:
        raise ValueError('PNG no soportado (profundidad %d, color %d, entrelazado %d)' % (prof, color, entrelazado))
    bpp = 3 if color == 2 else 4
    crudo, fila = zlib.decompress(idat), ancho * bpp
    filas, prev, p = [], bytearray(fila), 0
    for _ in range(alto):
        filtro, linea = crudo[p], bytearray(crudo[p + 1:p + 1 + fila])
        p += 1 + fila
        for x in range(fila):
            a = linea[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if filtro == 1:
                linea[x] = (linea[x] + a) & 255
            elif filtro == 2:
                linea[x] = (linea[x] + b) & 255
            elif filtro == 3:
                linea[x] = (linea[x] + (a + b) // 2) & 255
            elif filtro == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                linea[x] = (linea[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        filas.append(linea)
        prev = linea

    def pixel(x, y):
        return tuple(filas[y][x * bpp:x * bpp + 3])
    return ancho, alto, pixel


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
    a mano en dos baterias. Desde la 1.23 (V63), tambien un connect o un am
    start que adb dio por buenos (exit 0) y sus palabras dicen que no."""
    return (abre(t, 'SR_ADB_GONE_FMT') or abre(t, 'SR_ADB_FALLO_FMT') or abre(t, 'SR_ADB_CONNECT_FALLO_FMT')
            or abre(t, 'SR_ADB_RUN_FALLO_FMT') or not fallo(t))


def llego_a_git(t):
    """True si la orden LLEGO a git (y git contesto, bien o mal): no la paro
    la puerta. Un exit<>0 es un fallo con su etiqueta (SR_GIT_EXIT_FMT) desde
    el 27-sep-2026; antes "exit=N" salia como exito y las baterias lo
    miraban con startswith('exit=')."""
    # ...y una carpeta que no es un repo, desde la 1.22.2 su propio NOT_FOUND: tambien lo dijo git (rev-parse)
    return (t or '').startswith('exit=') or abre(t, 'SR_GIT_EXIT_FMT') or abre(t, 'SR_GIT_NO_ES_REPO_FMT')


def arbol_limpio(t):
    """True si la respuesta de delphi_git status dice arbol LIMPIO: git
    contesto con exit=0 y tras la linea de la rama ("## ...", status sale en
    --porcelain=v1 -b desde la 1.19.0) no hay ni un fichero. Un status con
    " M x" tambien sale con exit=0 (revisor de baterias, 18-oct-2026: "el
    clone queda limpio" miraba solo eso)."""
    lineas = (t or '').splitlines()
    return (bool(lineas) and lineas[0].strip() == 'exit=0' and
            all(not l.strip() or l.startswith('## ') for l in lineas[1:]))


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


def junction(link, target):
    """Un junction (mklink /J, sin privilegios); True si el enlace quedo. Lo
    escribian a mano varias baterias (el plantado de un enlace a una victima
    de fuera de las raices: CLAUDE.md, 'Nothing outside the workspace')."""
    r = subprocess.run(['cmd', '/c', 'mklink', '/J', link, target], capture_output=True)
    return r.returncode == 0 and os.path.isdir(link)


def junction_nt(link, destino_nt):
    """Un junction con su destino escrito en forma NT tal cual
    (\\??\\UNC\\host\\share\\..., que mklink /J no deja escribir: pide un volumen
    local), por FSCTL_SET_REPARSE_POINT: el plantado de un enlace que Windows
    no seguiria. True si el enlace quedo. Lo escribia a mano una sonda del
    revisor de cierre de la 1.18.2 (J2)."""
    import struct
    from ctypes import wintypes as wt
    k = ctypes.WinDLL('kernel32', use_last_error=True)
    k.CreateFileW.restype = wt.HANDLE
    k.CreateFileW.argtypes = [wt.LPCWSTR, wt.DWORD, wt.DWORD, ctypes.c_void_p, wt.DWORD, wt.DWORD, wt.HANDLE]
    k.DeviceIoControl.argtypes = [wt.HANDLE, wt.DWORD, ctypes.c_void_p, wt.DWORD, ctypes.c_void_p, wt.DWORD,
                                  ctypes.POINTER(wt.DWORD), ctypes.c_void_p]
    k.CloseHandle.argtypes = [wt.HANDLE]
    os.makedirs(link)
    # GENERIC_WRITE, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS
    h = k.CreateFileW(link, 0x40000000, 0, None, 3, 0x00200000 | 0x02000000, None)
    if h is None or h == wt.HANDLE(-1).value:
        return False
    try:
        s = destino_nt.encode('utf-16-le')
        datos = struct.pack('<HHHH', 0, len(s), len(s) + 2, 0) + s + b'\0\0' + b'\0\0'
        buf = struct.pack('<IHH', 0xA0000003, len(datos), 0) + datos  # IO_REPARSE_TAG_MOUNT_POINT
        ret = wt.DWORD(0)
        ok = k.DeviceIoControl(h, 0x000900A4, buf, len(buf), None, 0, ctypes.byref(ret), None)
    finally:
        k.CloseHandle(h)
    return bool(ok) and os.path.lexists(link)


def junta(carpeta, nombre):
    """La ruta de un nombre en su carpeta, como la compondria un agente.
    Una carpeta que acaba en ':' (una unidad sin su barra: para Windows es
    la carpeta ACTUAL de esa unidad) no se arregla aqui: es la regresion que
    vigila test_raiz_unidad (GUARD-021), y poner la barra por el servidor la
    tapaba (revisor de baterias de la 1.15.0). Se dice."""
    if carpeta.endswith(':'):
        raise AssertionError('dir de una unidad SIN barra (la carpeta actual para Windows): %r' % carpeta)
    return carpeta + nombre if carpeta.endswith('\\') else carpeta + '\\' + nombre


def ficheros(t, campo='folders', hijos='files'):
    """EL lector de una lista de ficheros del servidor (su organizador,
    Lsp.Listas.TListaDeFicheros, 1.15.0): folders = [{dir, files = [{name,
    ...}]}], la carpeta una vez. Devuelve las entradas planas, cada una con
    su 'path' (dir + name) y sus campos; las de una lista de nombres sueltos
    (dirs = ["c000", ...]) salen como {'path', 'name'}. Las baterias leen
    la forma por aqui, nunca a mano: si cambia, cambia en un sitio. t: el
    texto de la tool o su JSON ya leido.
    ESTRICTO con la forma: un grupo sin dir o sin su lista, o una entrada que
    ya trae su propia ruta (path/dir, que el organizador quita), es un
    AssertionError y la bateria sale roja. Aplanando a ciegas, el path del
    lector pisaba el que el servidor siguiera mandando y ninguna bateria lo
    veia (revisor de baterias de la 1.15.0, con dos mutantes que pasaban)."""
    j = como_json(t) if isinstance(t, str) else (t or {})
    out = []
    for g in j.get(campo) or []:
        if not isinstance(g, dict) or 'dir' not in g or not isinstance(g.get(hijos), list):
            raise AssertionError('%s: un grupo sin la forma {dir, %s = [...]}: %r' % (campo, hijos, g))
        for e in g[hijos]:
            if isinstance(e, str):
                out.append({'path': junta(g['dir'], e), 'name': e})
            else:
                if 'path' in e or 'dir' in e:
                    raise AssertionError('%s: una entrada trae su propia ruta, que el organizador '
                                         'quita: %r' % (campo, e))
                out.append(dict(e, path=junta(g['dir'], e.get('name', ''))))
    return out


def unicos(t, campo='folders', hijos='files'):
    """True si la lista agrupada nombra cada carpeta UNA vez y, dentro de
    cada una, cada fichero una vez: la promesa del organizador. Aplanando
    con ficheros() o aciertos() un fichero repetido no se ve (revisor de
    baterias de la 1.15.0: rename anade la fila de la definicion al final)."""
    j = como_json(t) if isinstance(t, str) else (t or {})
    grupos = j.get(campo) or []
    dirs = [g.get('dir', '').lower() for g in grupos]
    if len(dirs) != len(set(dirs)):
        return False
    for g in grupos:
        nombres = [(e if isinstance(e, str) else e.get('name', '')).lower() for e in g.get(hijos) or []]
        if len(nombres) != len(set(nombres)):
            return False
    return True


def aciertos(t, campo='folders'):
    """Los aciertos de una lista agrupada por carpeta y fichero (folders =
    [{dir, files = [{name, hits}]}]), planos y cada uno con su path: los de
    delphi_search (por fichero desde la 1.13.0), y desde la 1.15.0 tambien
    los usos de delphi_references (campo confirmed, unverified, mentions,
    rejected) y los cambios de delphi_rename_symbol (changes, unverified,
    lookalikes). EL lector de esa forma para las baterias, encima de
    ficheros(). t: el texto de la tool o su JSON ya leido. Igual de estricto:
    un acierto con su propia ruta es un AssertionError."""
    out = []
    for f in ficheros(t, campo):
        for h in f.get('hits', []):
            if 'path' in h or 'dir' in h:
                raise AssertionError('%s: un acierto trae su propia ruta, que el organizador '
                                     'quita: %r' % (campo, h))
            out.append(dict(h, path=f['path']))
    return out


# ---------------------------------------------------------------- stdio

class Stdio:
    """Un servidor en modo terminal stdio, como lo lanza un cliente local.

    args: argumentos del exe (--readonly...). t: el plazo por defecto de cada
    peticion de ESTE cliente. protocolo: el protocolVersion que se presenta.
    lee_stderr: el log del servidor (stderr en modo terminal) se recoge en
    self.errores -una tuberia que nadie lee acaba bloqueando al servidor-;
    entero solo tras cierra(), que espera al hilo que lo lee.
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
        self._hilo_err = None
        if lee_stderr:
            self._hilo_err = threading.Thread(target=self._lee_stderr, daemon=True)
            self._hilo_err.start()
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
        """Fin de stdin = el cliente se fue: salida LIMPIA; si no sale, se mata
        y se recoge lo que deje (mata_y_recoge)."""
        try:
            self.p.stdin.close()
        except Exception:
            pass
        try:
            self.p.wait(t)
        except subprocess.TimeoutExpired:
            mata_y_recoge(self.p)
        if self._hilo_err:
            # el stderr ENTERO antes de que la bateria lo lea: con carga el hilo
            # iba por detras del initialize y un check leyo [] (run_all del
            # 7-oct-2026, test_readonly_rutas_83)
            self._hilo_err.join(10)

    def mata(self):
        """Como cierra: un servidor de bateria se PARA (fin de stdin), no se
        mata - matado con kill() dejaba sus 3 atomos globales (medido el
        19-oct-2026 en designer y preview: ver ServidorHttp); el kill, solo si
        no sale en 15 s, y entonces se recoge lo que deja. Y a que muera: el
        borrado de su carpeta justo detras (el atexit de una bateria) fallaba
        con el exe aun abierto (segunda revision de la 1.17.0). Los 62 sitios
        de tests/ que llaman a mata() no cambian."""
        try:
            self.cierra(15)
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
        st, _, raw = self.post(o, sid=sid, t=t)
        for m in self.mensajes(raw):
            if m.get('id') == rid:
                return m
        # un 4xx/5xx sin respuesta JSON-RPC (el 401 de un token que no vale, o
        # el de un workspace CERRADO) no es un timeout: se dice lo que contesto.
        # Salia '(timeout)' al instante y una bateria pasaba apoyada en eso (V1
        # de test_sitio_virtual_1182; J7 del revisor de cierre de la 1.18.2)
        if isinstance(st, int) and st >= 400:
            return {'error': {'httpStatus': st, 'body': raw[:300]}}
        return None

    def call_msg(self, name, args, t=None, sid=PROPIA):
        return self.request('tools/call', {"name": name, "arguments": args}, t, sid)

    def call(self, name, args, t=None, sid=PROPIA):
        return texto(self.call_msg(name, args, t, sid), self.respaldo_json)

    def toolnames(self, sid=PROPIA):
        m = self.request('tools/list', sid=sid)
        return {x['name'] for x in ((m or {}).get('result') or {}).get('tools', [])}


# ---------------------------------------------------------------- atomos

# La forma de los atomos del RTL de Delphi en la tabla global de la sesion
# (Lsp.AtomosRtl es su casa en el servidor; esta es la del arnes, para MEDIR):
# Vcl.Controls 'Delphi<pid>' y 'ControlOfs<HInstance><tid>', Vcl.Dialogs
# 'WndProcPtr<HInstance><tid>', FMX.Platform.Win 'FIREMONKEY<pid>_<tid>'. Un
# proceso muerto sin finalizar los deja; llena la tabla (16384), Windows no
# arranca ningun proceso mas (0xC0000142; medido el 18-oct-2026).
_ATOMO_RTL = re.compile(r'^(?:(ControlOfs|WndProcPtr)[0-9A-F]+?([0-9A-F]{8})|(FIREMONKEY)([0-9A-F]{8})_([0-9A-F]{8})|(Delphi)([0-9A-F]{8}))$')


def _vivo(abre, derecho, ident, codigo_de):
    """vivo = existe Y no ha terminado (un muerto EXISTE mientras alguien tenga
    un handle, y su id no se reutiliza mientras exista: Lsp.AtomosRtl igual)"""
    h = abre(derecho, False, ident)
    if h:
        c = ctypes.c_uint32(0)
        vivo = bool(codigo_de(h, ctypes.byref(c))) and c.value == 259  # STILL_ACTIVE
        ctypes.windll.kernel32.CloseHandle(h)
        return vivo
    return ctypes.get_last_error() != 87  # 87 = no hay nada con ese id; otro error = lo hay


def atomos_rtl():
    """Los atomos del RTL que hay ahora en la tabla global: [(nombre, vivo)],
    vivo = su hilo o su proceso existen (un id reutilizado cuenta como vivo)."""
    k32 = ctypes.WinDLL('kernel32', use_last_error=True)
    k32.GlobalGetAtomNameW.argtypes = [ctypes.c_uint16, ctypes.c_wchar_p, ctypes.c_int]
    k32.OpenThread.restype = k32.OpenProcess.restype = ctypes.c_void_p
    k32.GetExitCodeThread.argtypes = k32.GetExitCodeProcess.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
    buf = ctypes.create_unicode_buffer(512)
    res = []
    for a in range(0xC000, 0x10000):
        if not k32.GlobalGetAtomNameW(a, buf, 512):
            continue
        m = _ATOMO_RTL.match(buf.value)
        if not m:
            continue
        if m.group(1):
            vivo = _vivo(k32.OpenThread, 0x0800, int(m.group(2), 16), k32.GetExitCodeThread)
        elif m.group(3):
            vivo = (_vivo(k32.OpenProcess, 0x1000, int(m.group(4), 16), k32.GetExitCodeProcess) or
                    _vivo(k32.OpenThread, 0x0800, int(m.group(5), 16), k32.GetExitCodeThread))
        else:
            vivo = _vivo(k32.OpenProcess, 0x1000, int(m.group(7), 16), k32.GetExitCodeProcess)
        res.append((buf.value, vivo))
    return res


def atomos_rtl_nombres():
    """Los nombres de los atomos del RTL que hay ahora: la foto de ANTES."""
    return {n for n, _v in atomos_rtl()}


def atomos_rtl_dejados(antes):
    """Los atomos del RTL de procesos muertos que NO estaban en la foto de
    antes: lo que dejo lo que corrio entre medias (una suite, una bateria).
    Por nombres nuevos y no por la cuenta: un atomo viejo cuyo id reutilizado
    era de un hilo vivo pasa a 'muerto' en cuanto ese hilo acaba, y la cuenta
    subia sin fuga ninguna (medido el 19-oct-2026, con restos en la tabla)."""
    return [n for n, vivo in atomos_rtl() if not vivo and n not in antes]


def atomos_rtl_recoge(pid, tid):
    """Lo que matamos, lo limpiamos, tambien el arnes (Lsp.AtomosRtl lo hace
    en el servidor): los atomos del RTL que dejo un proceso MUERTO de pid y
    hilo principal tid - por su nombre exacto (Delphi<pid>, FIREMONKEY<pid>_)
    o por el tid del final (ControlOfs/WndProcPtr<HInstance><tid>) -, y solo
    si ese proceso y ese hilo han terminado (existir no basta): un id
    reutilizado por un vivo se respeta. Cuantos borro."""
    k32 = ctypes.WinDLL('kernel32', use_last_error=True)
    k32.OpenThread.restype = k32.OpenProcess.restype = ctypes.c_void_p
    k32.GetExitCodeThread.argtypes = k32.GetExitCodeProcess.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
    k32.GlobalFindAtomW.argtypes = [ctypes.c_wchar_p]
    if _vivo(k32.OpenProcess, 0x1000, pid, k32.GetExitCodeProcess):
        return 0
    if tid and _vivo(k32.OpenThread, 0x0800, tid, k32.GetExitCodeThread):
        return 0
    borrados = 0
    for nombre, _v in atomos_rtl():
        m = _ATOMO_RTL.match(nombre)
        suyo = (nombre == 'Delphi%08X' % pid or nombre.startswith('FIREMONKEY%08X_' % pid) or
                (bool(m.group(1)) and bool(tid) and m.group(2) == '%08X' % tid))
        if not suyo:
            continue
        a = k32.GlobalFindAtomW(nombre)
        # GlobalDeleteAtom devuelve 0 si quito una referencia (dos muertos con la
        # misma cadena son dos referencias) y el atomo si no
        while a and k32.GlobalDeleteAtom(a) == 0:
            borrados += 1
            a = k32.GlobalFindAtomW(nombre)
    return borrados


def mata_y_recoge(p, t=15):
    """El kill de verdad de un servidor de bateria que no ha salido solo, y lo
    que deja: su hilo principal se mide ANTES (muerto ya no se ve), se espera
    a que muera y se recogen sus atomos del RTL (atomos_rtl_recoge)."""
    if p.poll() is not None:
        return
    tid = hilo_principal(p.pid)
    try:
        # el kill de Popen, el de VERDAD: el de ServidorHttp es la parada suave,
        # que vuelve aqui si no sale, y sin consola (el CTRL_BREAK no le llega)
        # se llamaban el uno al otro 15 s por vuelta: test_handles_heredados
        # colgo el release_check 52 minutos (medido el 19-oct-2026)
        subprocess.Popen.kill(p)
        p.wait(t)
    except Exception:
        pass
    atomos_rtl_recoge(p.pid, tid)


def hilo_principal(pid):
    """El id del hilo principal de un proceso vivo (el primero de los suyos en
    la foto de Toolhelp), o 0: el que llevan sus atomos del RTL."""
    k32 = ctypes.WinDLL('kernel32', use_last_error=True)

    class THREADENTRY32(ctypes.Structure):
        _fields_ = [('dwSize', ctypes.c_uint32), ('cntUsage', ctypes.c_uint32), ('th32ThreadID', ctypes.c_uint32),
                    ('th32OwnerProcessID', ctypes.c_uint32), ('tpBasePri', ctypes.c_int32),
                    ('tpDeltaPri', ctypes.c_int32), ('dwFlags', ctypes.c_uint32)]
    k32.CreateToolhelp32Snapshot.restype = ctypes.c_void_p
    k32.Thread32First.argtypes = k32.Thread32Next.argtypes = [ctypes.c_void_p, ctypes.POINTER(THREADENTRY32)]
    snap = k32.CreateToolhelp32Snapshot(0x4, 0)  # TH32CS_SNAPTHREAD
    if not snap or snap == ctypes.c_void_p(-1).value:
        return 0
    try:
        e = THREADENTRY32()
        e.dwSize = ctypes.sizeof(e)
        ok = k32.Thread32First(snap, ctypes.byref(e))
        while ok:
            if e.th32OwnerProcessID == pid:
                return e.th32ThreadID
            ok = k32.Thread32Next(snap, ctypes.byref(e))
    finally:
        k32.CloseHandle(snap)
    return 0


# ---------------------------------------------------------------- escritorio

class VigilanteDeEscritorio:
    """Lo que un renderizador deja ver en el escritorio del servidor, que
    ninguna bateria miraba (produccion es un servicio sin escritorio y las
    baterias leen respuestas): cada 100 ms, las ventanas VISIBLES de los
    DelphiFormRender* que son de aplicacion (WS_EX_APPWINDOW: salen en la
    barra), sus cuadros de dialogo (clase #32770: un MessageBox modal que
    ademas los deja colgados hasta el plazo) y si uno tiene el primer plano
    (roba el foco). Medido el 18/19-oct-2026 en el escritorio de David
    durante el corpus: siete "Delphiformrenderfmx" en la barra, cuadros de
    FireDAC y el foco perdido; solo lo vio una persona delante del monitor."""

    def __init__(self):
        self.ventanas = self.cuadros = self.foco = self.muestras = 0
        self.detalles = {}  # hwnd -> quien era (resumen)
        self._parar = False
        self._hilo = None

    def arranca(self):
        self._hilo = threading.Thread(target=self._vigila, daemon=True)
        self._hilo.start()
        return self

    def para(self):
        self._parar = True
        if self._hilo:
            self._hilo.join(2)
        return self

    def resumen(self):
        """Las cuentas y, de cada ventana vista, quien era: exe, clase, titulo,
        estilo extendido, el hilo que la creo y si es el principal. El release
        check del 19-oct-2026 vio 2 muestras con ventana en la barra que ni el
        corpus solo ni con carga reprodujeron: la siguiente se explica sola."""
        return 'ventanas de aplicacion visibles %d, cuadros %d, muestras con el foco %d (de %d)%s' % (
            self.ventanas, self.cuadros, self.foco, self.muestras,
            ''.join('\n    %s' % d for d in list(self.detalles.values())[:6]))

    def _vigila(self):
        u32 = ctypes.WinDLL('user32', use_last_error=True)
        k32 = ctypes.WinDLL('kernel32', use_last_error=True)
        PROC = ctypes.WINFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)
        u32.EnumWindows.argtypes = [PROC, ctypes.c_void_p]
        u32.GetWindowThreadProcessId.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
        u32.GetForegroundWindow.restype = ctypes.c_void_p
        u32.IsWindowVisible.argtypes = u32.GetWindowTextLengthW.argtypes = [ctypes.c_void_p]
        u32.GetClassNameW.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_int]
        u32.GetWindowLongW.argtypes = [ctypes.c_void_p, ctypes.c_int]
        k32.OpenProcess.restype = ctypes.c_void_p
        k32.QueryFullProcessImageNameW.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_wchar_p,
                                                   ctypes.POINTER(ctypes.c_uint32)]
        u32.GetWindowTextW.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_int]

        def apunta(hwnd, pid, tid, cls):
            if hwnd in self.detalles:
                return
            tit = ctypes.create_unicode_buffer(128)
            u32.GetWindowTextW(hwnd, tit, 128)
            self.detalles[hwnd] = dict(
                muestra=self.muestras, exe=nombre_de(pid), pid=pid, clase=cls, titulo=tit.value, hilo=tid,
                es_principal=(tid == hilo_principal(pid)),
                ex='%08X' % (u32.GetWindowLongW(hwnd, -20) & 0xFFFFFFFF))

        def nombre_de(pid):
            # El exe se pregunta CADA vez, nunca por una cache por pid: Windows
            # reutiliza los pid, y el nombre de un renderizador muerto se le
            # colgaba al proceso que heredaba su numero. Release check del
            # 31-oct-2026: MuestrasEstilos.exe (un FMX ajeno, en marcha dos
            # minutos con el pid de un renderizador anterior) conto 1087
            # muestras como ventana del renderizador; lo delato su titulo, que
            # CreateAppHandle compone con el nombre del exe. Solo se pregunta
            # por las ventanas VISIBLES y por la del primer plano: pocas.
            n = ''
            h = k32.OpenProcess(0x1000, False, pid)
            if h:
                b = ctypes.create_unicode_buffer(1024)
                s = ctypes.c_uint32(1024)
                if k32.QueryFullProcessImageNameW(h, 0, b, ctypes.byref(s)):
                    n = os.path.basename(b.value)
                k32.CloseHandle(h)
            return n

        def de_render(pid):
            return nombre_de(pid).lower().startswith('delphiformrender')

        def cb(hwnd, _lp):
            pid = ctypes.c_uint32()
            tid = u32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
            if u32.IsWindowVisible(hwnd) and de_render(pid.value):
                cls = ctypes.create_unicode_buffer(64)
                u32.GetClassNameW(hwnd, cls, 64)
                if cls.value == '#32770':
                    self.cuadros += 1
                    apunta(hwnd, pid.value, tid, cls.value)
                elif u32.GetWindowLongW(hwnd, -20) & 0x40000:
                    self.ventanas += 1
                    apunta(hwnd, pid.value, tid, cls.value)
            return 1
        f = PROC(cb)
        while not self._parar:
            u32.EnumWindows(f, None)
            fg = ctypes.c_uint32()
            u32.GetWindowThreadProcessId(u32.GetForegroundWindow(), ctypes.byref(fg))
            if de_render(fg.value):
                self.foco += 1
            self.muestras += 1
            time.sleep(0.1)


def en_paralelo(puerto, token, tool, lista, hilos=None, t=120, nombre='paralelo'):
    """UNA tool sobre muchos argumentos a la vez, por HTTP: un cliente y una
    sesion por hilo, las respuestas (su texto) en el orden de la lista; una
    llamada que revienta (un plazo vencido) vuelve como 'EXCEPCION ...' en su
    sitio, no tumba las demas: la bateria la cuenta como no contestada. hilos:
    por defecto el doble de nucleos, hasta 8 - el lint de un form espera sobre
    todo a que arranque su renderizador (medido el 18-oct-2026 con 96 forms de
    los Samples: 8 hilos en 4 nucleos, 3,1 veces lo de en serie y las mismas
    respuestas)."""
    locales = threading.local()

    def una(args):
        c = getattr(locales, 'c', None)
        if c is None:
            c = locales.c = Http(puerto, token, t=max(t, 120))
            c.session('%s-%d' % (nombre, threading.get_ident()))
        try:
            return c.call(tool, args, t)
        except Exception as e:
            return 'EXCEPCION en %s: %r' % (tool, e)

    if hilos is None:
        hilos = max(2, min(8, 2 * (os.cpu_count() or 1)))
    with concurrent.futures.ThreadPoolExecutor(hilos) as ex:
        return list(ex.map(una, lista))
