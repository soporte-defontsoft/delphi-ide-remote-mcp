"""E2E battery: delphi_test must run even when the server sits on a window
desktop that does NOT grant AppContainers access - the condition of a Windows
SERVICE (session 0), where the service window station/desktop lacks the ALL
APPLICATION PACKAGES ACE that the interactive WinSta0\\Default has.

The normal batteries start the server in THIS interactive session, so they
never reproduce it: 1.11.0 shipped with delphi_test broken from the service
(exit 0xC0000142, STATUS_DLL_INIT_FAILED, because the container's user32 could
not connect to the session-0 desktop) and NO battery caught it - only the live
test against the real service did. This battery is that guard: it launches the
server on a freshly created RESTRICTED desktop (built WITHOUT the AC ACE) and
runs a real DUnitX test through it.

With the 1.11.1 fix (Lsp.Sandbox.ConcedeAPaquetes grants the AC ACE to the
server's window station and desktop before launching) the test runs and stays
confined. The mutant that removes the grant (muta_111.py sin_concede_paquetes)
makes this battery red with 0xC0000142 - which also proves the desktop is
genuinely restricted (it does not pass for the wrong reason).

Usage:  python tests/test_delphi_test_servicio.py [path-to-DelphiLspMcp.exe]
"""
import ctypes, ctypes.wintypes as w, json, os, re, subprocess, threading, time
import mcp_cliente as mc
from mcp_cliente import check

STATUS_DLL_INIT_FAILED = 0xC0000142
TOKEN = 'srv-token-123'
PORT = mc.puerto_libre()
BASE = mc.carpeta('servicio')
SRV = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(SRV)
with open(os.path.join(SRV, 'settings.ini'), 'w') as f:
    f.write('[Server]\nPort=%d\nBindIP=127.0.0.1\n\n' % PORT +
            '[Workspace.Srv]\nToken=%s\nRoots=%s\nAllowTests=1\n'
            % (TOKEN, JAIL))

k32 = ctypes.WinDLL('kernel32', use_last_error=True)
u32 = ctypes.WinDLL('user32', use_last_error=True)
adv = ctypes.WinDLL('advapi32', use_last_error=True)


class STARTUPINFOW(ctypes.Structure):
    _fields_ = [('cb', w.DWORD), ('lpReserved', w.LPWSTR), ('lpDesktop', w.LPWSTR),
                ('lpTitle', w.LPWSTR), ('dwX', w.DWORD), ('dwY', w.DWORD),
                ('dwXSize', w.DWORD), ('dwYSize', w.DWORD), ('dwXCountChars', w.DWORD),
                ('dwYCountChars', w.DWORD), ('dwFillAttribute', w.DWORD), ('dwFlags', w.DWORD),
                ('wShowWindow', w.WORD), ('cbReserved2', w.WORD), ('lpReserved2', ctypes.c_void_p),
                ('hStdInput', w.HANDLE), ('hStdOutput', w.HANDLE), ('hStdError', w.HANDLE)]


class PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [('hProcess', w.HANDLE), ('hThread', w.HANDLE),
                ('dwProcessId', w.DWORD), ('dwThreadId', w.DWORD)]


class SECURITY_ATTRIBUTES(ctypes.Structure):
    _fields_ = [('nLength', w.DWORD), ('lpSecurityDescriptor', ctypes.c_void_p),
                ('bInheritHandle', w.BOOL)]


u32.CreateDesktopW.restype = w.HANDLE
u32.CreateDesktopW.argtypes = [w.LPCWSTR, w.LPCWSTR, ctypes.c_void_p, w.DWORD, w.DWORD, ctypes.c_void_p]
k32.CreateProcessW.argtypes = [w.LPCWSTR, w.LPWSTR, ctypes.c_void_p, ctypes.c_void_p, w.BOOL,
                               w.DWORD, ctypes.c_void_p, w.LPCWSTR, ctypes.c_void_p,
                               ctypes.POINTER(PROCESS_INFORMATION)]
CREATE_NO_WINDOW = 0x08000000
CREATE_UNICODE_ENVIRONMENT = 0x00000400
DESK_ACCESS = 0x000F01FF
WINSTA_ACCESS = 0x000F037F
WINSTA_TEST_ACCESS = 0x20020  # READ_CONTROL y atomos globales, ambos necesarios.
u32.GetProcessWindowStation.restype = w.HANDLE
u32.CreateWindowStationW.restype = w.HANDLE
u32.CreateWindowStationW.argtypes = [w.LPCWSTR, w.DWORD, w.DWORD, ctypes.c_void_p]
u32.SetProcessWindowStation.argtypes = [w.HANDLE]
u32.CloseWindowStation.argtypes = [w.HANDLE]
u32.CloseDesktop.argtypes = [w.HANDLE]


def mi_sid():
    out = subprocess.run(['whoami', '/user', '/fo', 'csv', '/nh'],
                         capture_output=True, text=True).stdout.strip()
    return out.strip('"').split('","')[-1].strip('"')


# escritorio RESTRINGIDO en WinSta0: SYSTEM, administradores y yo con control
# total, pero SIN la ACE de ALL APPLICATION PACKAGES (AC) -> como la sesion 0
SDDL = 'D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;%s)' % mi_sid()
# Medir derechos en ESTE escritorio privado antes de acotar el fuente:
# una ACE ya presente hace que el servidor conserve su mascara.
MASCARA_FIXTURE = os.environ.get('DELPHI_MCP_TEST_DESKTOP_MASK', '0x1')
if MASCARA_FIXTURE:
    SDDL += '(A;;%s;;;AC)' % MASCARA_FIXTURE
DESK = 'dmcp_srv_%d' % os.getpid()
sd = ctypes.c_void_p()
if not adv.ConvertStringSecurityDescriptorToSecurityDescriptorW(SDDL, 1, ctypes.byref(sd), None):
    raise OSError('SDDL: %d' % ctypes.get_last_error())
sa = SECURITY_ATTRIBUTES(ctypes.sizeof(SECURITY_ATTRIBUTES), sd.value, False)
# Estacion tambien PRIVADA: no tocar la DACL de WinSta0 del usuario.
STATION = 'WinSta0'
hstation = None
if os.environ.get('DELPHI_MCP_TEST_PRIVATE_STATION') == '1':
    STATION = 'dmcp_wsta_%d' % os.getpid()
    MASCARA_ESTACION = os.environ.get('DELPHI_MCP_TEST_STATION_MASK', '')
    sddl_station = 'D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;%s)' % mi_sid()
    if MASCARA_ESTACION:
        sddl_station += '(A;;%s;;;AC)' % MASCARA_ESTACION
    sd_station = ctypes.c_void_p()
    if not adv.ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl_station, 1, ctypes.byref(sd_station), None):
        raise OSError('SDDL station: %d' % ctypes.get_last_error())
    sa_station = SECURITY_ATTRIBUTES(ctypes.sizeof(SECURITY_ATTRIBUTES), sd_station.value, False)
    # Este modo exige ejecutar la bateria con un token de administrador.
    # Nombre propio y CREATE_ONLY: nunca abrir ni modificar una estacion existente.
    hstation = u32.CreateWindowStationW(STATION, 1, WINSTA_ACCESS, ctypes.byref(sa_station))
    if not hstation:
        raise OSError('CreateWindowStation: %d' % ctypes.get_last_error())
    u32.GetUserObjectInformationW.argtypes = [w.HANDLE, w.DWORD, ctypes.c_void_p, w.DWORD, ctypes.POINTER(w.DWORD)]
    station_name = ctypes.create_unicode_buffer(256)
    station_bytes = w.DWORD()
    if not u32.GetUserObjectInformationW(hstation, 2, station_name, ctypes.sizeof(station_name), ctypes.byref(station_bytes)):
        raise OSError('GetUserObjectInformation station: %d' % ctypes.get_last_error())
    STATION = station_name.value
    anterior = u32.GetProcessWindowStation()
    if not u32.SetProcessWindowStation(hstation):
        raise OSError('SetProcessWindowStation: %d' % ctypes.get_last_error())
    try:
        hdesk = u32.CreateDesktopW(DESK, None, None, 0, DESK_ACCESS, ctypes.byref(sa))
    finally:
        u32.SetProcessWindowStation(anterior)
else:
    hdesk = u32.CreateDesktopW(DESK, None, None, 0, DESK_ACCESS, ctypes.byref(sa))
if not hdesk:
    raise OSError('CreateDesktop: %d' % ctypes.get_last_error())

pi = PROCESS_INFORMATION()
si = STARTUPINFOW()
si.cb = ctypes.sizeof(si)
si.lpDesktop = STATION + '\\' + DESK
env = mc.entorno()
envblock = ''.join('%s=%s\0' % (k, v) for k, v in env.items()) + '\0'
cmd = ctypes.create_unicode_buffer('"%s" --http' % EXE)
ok = k32.CreateProcessW(None, cmd, None, None, False,
                        CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
                        ctypes.create_unicode_buffer(envblock), SRV, ctypes.byref(si), ctypes.byref(pi))
if not ok:
    raise OSError('CreateProcess del servidor: %d' % ctypes.get_last_error())


def foto_permisos(hobj):
    u32.GetUserObjectSecurity.argtypes = [w.HANDLE, ctypes.POINTER(w.DWORD), ctypes.c_void_p, w.DWORD, ctypes.POINTER(w.DWORD)]
    adv.GetSecurityDescriptorDacl.argtypes = [ctypes.c_void_p, ctypes.POINTER(w.BOOL), ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(w.BOOL)]
    adv.GetAce.argtypes = [ctypes.c_void_p, w.DWORD, ctypes.POINTER(ctypes.c_void_p)]
    adv.ConvertSidToStringSidW.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_wchar_p)]
    k32.LocalFree.argtypes = [ctypes.c_void_p]
    si = w.DWORD(4)
    needed = w.DWORD()
    u32.GetUserObjectSecurity(hobj, ctypes.byref(si), None, 0, ctypes.byref(needed))
    buf = ctypes.create_string_buffer(needed.value)
    if not u32.GetUserObjectSecurity(hobj, ctypes.byref(si), buf, len(buf), ctypes.byref(needed)):
        raise ctypes.WinError(ctypes.get_last_error())
    hay = w.BOOL(); defecto = w.BOOL(); dacl = ctypes.c_void_p()
    if not adv.GetSecurityDescriptorDacl(buf, ctypes.byref(hay), ctypes.byref(dacl), ctypes.byref(defecto)):
        raise ctypes.WinError(ctypes.get_last_error())
    if not hay.value or not dacl.value:
        return {'aces': None, 'permitidos': []}
    count = ctypes.c_ushort.from_address(dacl.value + 4).value
    result = {'aces': [], 'permitidos': []}
    for i in range(count):
        ace = ctypes.c_void_p()
        if not adv.GetAce(dacl, i, ctypes.byref(ace)):
            raise ctypes.WinError(ctypes.get_last_error())
        size = ctypes.c_ushort.from_address(ace.value + 2).value
        result['aces'].append(ctypes.string_at(ace.value, size).hex())
        if ctypes.c_ubyte.from_address(ace.value).value != 0:
            continue
        sid = ctypes.c_wchar_p()
        if not adv.ConvertSidToStringSidW(ace.value + 8, ctypes.byref(sid)):
            raise ctypes.WinError(ctypes.get_last_error())
        try:
            result['permitidos'].append((sid.value, w.DWORD.from_address(ace.value + 4).value))
        finally:
            k32.LocalFree(ctypes.cast(sid, ctypes.c_void_p))
    return result


def permisos_nuevos(hobj, antes):
    return [x for x in foto_permisos(hobj)['permitidos'] if x not in antes['permitidos']]


def permisos_estacion_esperados(escritorio, necesarios):
    return sorted((sid, WINSTA_TEST_ACCESS) for sid, _ in escritorio) if necesarios else []


def J(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


try:
    check('fixture: el servidor arranca en el escritorio restringido (sesion 0 simulada)',
          mc.espera_puerto(PORT, None, 30), 'no escucho en %d' % PORT)
    cli = mc.Http(PORT, TOKEN, t=900)
    cli.session('servicio')

    r = cli.call('delphi_create', {'kind': 'project-test', 'name': 'SrvTest',
                                   'dir': os.path.join(JAIL, 'SrvTest')})
    check('fixture: proyecto de test DUnitX creado', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])

    unidades = J(cli.call('delphi_list', {'root': os.path.join(JAIL, 'SrvTest'), 'pattern': '*.pas'})).get('files', [])
    unidad = mc.real(unidades[0]['path'])
    leido = cli.call('delphi_read', {'path': unidad})
    texto = '\n'.join(l.split('|', 1)[1] for l in leido.splitlines() if re.match(r'^\d+\|', l))
    clase = re.search(r'\b(\w+)\s*=\s*class\b', texto).group(1)
    cli.call('delphi_edit', {'path': unidad, 'adduses': 'Winapi.Windows', 'section': 'implementation'})
    r = cli.call('delphi_edit', {'path': unidad, 'insert': 'metodo', 'inclass': clase,
                               'code': '[Test] procedure MantieneLaEjecucion;\nbegin\n  Winapi.Windows.Sleep(4000);\nend;'})
    check('fixture: test DUnitX mantiene viva la ejecucion durante la medida', mc.es(r, 'SK_EDIT_ESCRITO_EN_FMT'), r[:300])
    antes = foto_permisos(hdesk)
    antes_estacion = foto_permisos(hstation) if hstation else None
    requiere_sid_estacion = bool(hstation) and not any(
        sid == 'S-1-15-2-1' and mascara & WINSTA_TEST_ACCESS == WINSTA_TEST_ACCESS
        for sid, mascara in antes_estacion['permitidos'])
    respuesta = []
    def ejecuta():
        respuesta.append(cli.call('delphi_test', {'command': 'run',
                                  'project': os.path.join(JAIL, 'SrvTest', 'SrvTest.dproj')}, 900))
    trabajo = threading.Thread(target=ejecuta, daemon=True)
    trabajo.start()
    durante = antes
    limite = time.monotonic() + 120
    while trabajo.is_alive() and time.monotonic() < limite:
        durante = foto_permisos(hdesk)
        if durante['aces'] != antes['aces']:
            break
        time.sleep(.02)
    nuevos = [x for x in durante['permitidos'] if x not in antes['permitidos']]
    check('S3 durante el test, solo SU SID recibe 0x81 en el escritorio',
          len(nuevos) == 1 and nuevos[0][0].startswith('S-1-15-2-') and
          nuevos[0][0] != 'S-1-15-2-1' and nuevos[0][1] == 0x81, str(nuevos))
    if hstation:
        durante_estacion = permisos_nuevos(hstation, antes_estacion)
        check('S9 estacion: solo los SID necesarios reciben el minimo 0x20020',
              sorted(durante_estacion) == permisos_estacion_esperados(nuevos, requiere_sid_estacion),
              str(durante_estacion))
    trabajo.join(900)
    out = respuesta[0] if respuesta else 'sin respuesta del test'
    j = J(out)
    ec = j.get('exitCode')
    # la regresion EXACTA: el contenedor no pasaba del init de user32
    check('S1 delphi_test NO muere en 0xC0000142 desde un escritorio de sesion 0',
          (ec & 0xFFFFFFFF) != STATUS_DLL_INIT_FAILED if isinstance(ec, int) else bool(j.get('result')),
          'exitCode=%s result=%s' % (ec, j.get('result')))
    check('S2 el test corre y pasa en su contenedor (sandboxed, exit 0)',
          j.get('result') == 'pass' and j.get('sandboxed') is True and ec == 0,
          out[:400])
    despues = foto_permisos(hdesk)
    check('S4 al terminar quedan exactamente las ACE de antes', despues['aces'] == antes['aces'], str(despues['permitidos']))
    if hstation:
        check('S10 estacion: al terminar queda su ACL original',
              foto_permisos(hstation)['aces'] == antes_estacion['aces'])

    # Dos ejecuciones reales comparten el escritorio pero tienen SID distintos.
    cli2 = mc.Http(PORT, TOKEN, t=900)
    cli2.session('servicio-paralelo')
    salidas = [[], []]
    def simultaneo(cliente, indice):
        salidas[indice].append(cliente.call('delphi_test', {
            'command': 'run', 'project': os.path.join(JAIL, 'SrvTest', 'SrvTest.dproj'),
            'nobuild': True}, 900))
    primero = threading.Thread(target=simultaneo, args=(cli, 0), daemon=True)
    segundo = threading.Thread(target=simultaneo, args=(cli2, 1), daemon=True)
    primero.start()
    limite = time.monotonic() + 30
    inicial = []
    while primero.is_alive() and time.monotonic() < limite:
        inicial = permisos_nuevos(hdesk, antes)
        if inicial: break
        time.sleep(.01)
    inicial_estacion = permisos_nuevos(hstation, antes_estacion) if hstation else []
    time.sleep(1.5)
    segundo.start()
    ambos = []
    limite = time.monotonic() + 30
    while primero.is_alive() and segundo.is_alive() and time.monotonic() < limite:
        ambos = permisos_nuevos(hdesk, antes)
        if len(ambos) == 2: break
        time.sleep(.01)
    check('S5 dos tests vivos reciben dos SID propios con 0x81',
          len(inicial) == 1 and len(ambos) == 2 and len({x[0] for x in ambos}) == 2 and
          all(x[0].startswith('S-1-15-2-') and x[0] != 'S-1-15-2-1' and x[1] == 0x81 for x in ambos), str(ambos))
    if hstation:
        ambos_estacion = permisos_nuevos(hstation, antes_estacion)
        check('S11 estacion: solapamiento conserva solo los SID necesarios con 0x20020',
              sorted(ambos_estacion) == permisos_estacion_esperados(ambos, requiere_sid_estacion),
              str(ambos_estacion))
    primero.join(900)
    restante = permisos_nuevos(hdesk, antes)
    check('S6 terminar uno retira solo SU permiso y conserva el del otro vivo',
          segundo.is_alive() and len(restante) == 1 and restante == [x for x in ambos if x not in inicial], str(restante))
    if hstation:
        restante_estacion = permisos_nuevos(hstation, antes_estacion)
        check('S12 estacion: terminar uno retira solo SU permiso',
              segundo.is_alive() and sorted(restante_estacion) ==
              sorted(x for x in ambos_estacion if x not in inicial_estacion), str(restante_estacion))
    segundo.join(900)
    resultados = [J(x[0]) if x else {} for x in salidas]
    check('S7 ambos tests pasan dentro de su AppContainer',
          all(x.get('result') == 'pass' and x.get('sandboxed') is True and x.get('exitCode') == 0 for x in resultados), str(resultados)[:500])
    despues = foto_permisos(hdesk)
    check('S8 el solapamiento tampoco deja ACE nuevas', despues['aces'] == antes['aces'], str(despues['permitidos']))
    if hstation:
        check('S13 estacion: el solapamiento devuelve su ACL original',
              foto_permisos(hstation)['aces'] == antes_estacion['aces'])
finally:
    try:
        k32.TerminateProcess(pi.hProcess, 0)
    except Exception:
        pass
    try:
        k32.CloseHandle(pi.hThread); k32.CloseHandle(pi.hProcess)
    except Exception:
        pass
    u32.CloseDesktop(hdesk)
    if hstation:
        u32.CloseWindowStation(hstation)
    time.sleep(0.5)
    mc.borra(BASE)
mc.fin('delphi_test service-desktop battery')
