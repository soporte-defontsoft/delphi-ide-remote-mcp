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
import ctypes, ctypes.wintypes as w, json, os, subprocess, time
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
            '[Workspace.Srv]\nToken=%s\nRoots=%s\nAllowTests=1\nDelphiVersion=37.0\n'
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


def mi_sid():
    out = subprocess.run(['whoami', '/user', '/fo', 'csv', '/nh'],
                         capture_output=True, text=True).stdout.strip()
    return out.strip('"').split('","')[-1].strip('"')


# escritorio RESTRINGIDO en WinSta0: SYSTEM, administradores y yo con control
# total, pero SIN la ACE de ALL APPLICATION PACKAGES (AC) -> como la sesion 0
SDDL = 'D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;%s)' % mi_sid()
DESK = 'dmcp_srv_%d' % os.getpid()
sd = ctypes.c_void_p()
if not adv.ConvertStringSecurityDescriptorToSecurityDescriptorW(SDDL, 1, ctypes.byref(sd), None):
    raise OSError('SDDL: %d' % ctypes.get_last_error())
sa = SECURITY_ATTRIBUTES(ctypes.sizeof(SECURITY_ATTRIBUTES), sd.value, False)
hdesk = u32.CreateDesktopW(DESK, None, None, 0, DESK_ACCESS, ctypes.byref(sa))
if not hdesk:
    raise OSError('CreateDesktop: %d' % ctypes.get_last_error())

pi = PROCESS_INFORMATION()
si = STARTUPINFOW()
si.cb = ctypes.sizeof(si)
si.lpDesktop = 'WinSta0\\' + DESK
env = mc.entorno()
envblock = ''.join('%s=%s\0' % (k, v) for k, v in env.items()) + '\0'
cmd = ctypes.create_unicode_buffer('"%s" --http' % EXE)
ok = k32.CreateProcessW(None, cmd, None, None, False,
                        CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
                        ctypes.create_unicode_buffer(envblock), SRV, ctypes.byref(si), ctypes.byref(pi))
if not ok:
    raise OSError('CreateProcess del servidor: %d' % ctypes.get_last_error())


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

    out = cli.call('delphi_test', {'command': 'run',
                                   'project': os.path.join(JAIL, 'SrvTest', 'SrvTest.dproj')}, 900)
    j = J(out)
    ec = j.get('exitCode')
    # la regresion EXACTA: el contenedor no pasaba del init de user32
    check('S1 delphi_test NO muere en 0xC0000142 desde un escritorio de sesion 0',
          (ec & 0xFFFFFFFF) != STATUS_DLL_INIT_FAILED if isinstance(ec, int) else bool(j.get('result')),
          'exitCode=%s result=%s' % (ec, j.get('result')))
    check('S2 el test corre y pasa en su contenedor (sandboxed, exit 0)',
          j.get('result') == 'pass' and j.get('sandboxed') is True and ec == 0,
          out[:400])
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
    time.sleep(0.5)
    mc.borra(BASE)
mc.fin('delphi_test service-desktop battery')
