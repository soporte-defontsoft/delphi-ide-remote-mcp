"""E2E battery for 1.11.0 - the cage of delphi_test: a Windows AppContainer of
its own for EVERY run, on a COPY of the test's output folder in the server's
house, born with the call and gone with its answer.

Measured 2026-10-02 (David's question about a test on the NAS): the
low-integrity label the tests ran under until 1.10 is only enforced by
Windows on the LOCAL disk. A test at low integrity wrote on a network drive
with the session's credentials, read any file and opened connections; on a
network root not even its own output folder could be labelled. Every promise
of the new description is measured here by name:

  K1  a test runs and passes in its container; sandboxed=true
  K2  it writes in its own folder (the copy), and the agent's output folder
      is untouched: what it wrote is not there, nothing there is relabelled
  K3  what it wrote comes back in "files", a text file with its content;
      text is decided by the server's one rule (a NUL), not by the extension:
      a binary .txt comes without content, a text .out with it
  K4  it cannot write ABOVE its folder: the server's temp, the server's house
  K5  it cannot write in the jail outside its folder, nor outside the jail
  K6  it cannot READ outside its folder: a file of the jail, one of the house
  K7  it cannot see the folders next to its own (another test's copy)
  K8  no network: not even the port listening on this machine
  K9  a Delphi test's temp file (TPath.GetTempPath, empty in a container)
      lands in its own folder
  K10 a big log comes back cut: 16,384 characters, "truncated" and the note
      (TEST-030); a cut that falls inside a surrogate pair leaves the pair out
  K15 ...and all the contents together stop at 65,536 characters: the file
      past the total comes with its name and size, without content, and
      "noContent" says why
  K20 the list itself stops at 500 entries and says how many are left out
      (TEST-033)
  K14 it does not see the server's configuration: not ONE DELPHI_MCP_* in
      its environment (the server's own unit tests passed only because they
      inherited its roots - measured the day this battery was born)
  K11 a project built with runtime packages is refused BEFORE building
      (TEST-028): the container reads no .bpl of components or of the project
  K16 an output folder over the copy cap is refused (TEST-029) - a sparse
      file, 300 MB that cost nothing on disk; K16b the same through a
      symlink, counted by what is behind it (a NOTA without the privilege)
  K17 a copy that cannot be made (a broken junction in the output folder)
      says so with its tag (TEST-031) and nothing runs
  K12 nothing is left: no container, no copy in the server's temp
  K13 a container a crash left behind (the server killed mid-run) is purged
      at the next start of the SAME server - launched by its long path after
      the first one by its 8.3 path: the mark comes from the canonical
      folder, not from its text -, and one of another house is not

The containers are told apart by the MARK of this battery's server (the hash
of its folder, the one Lsp.Sandbox puts in their names), not by the prefix:
the service of this machine runs as the same account and could make one
while the battery looks.

Usage:  python tests/test_delphi_test_contenedor.py [path-to-DelphiLspMcp.exe]
"""
import atexit, ctypes, hashlib, json, os, re, socket, subprocess, threading, time, uuid, winreg
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('caja')
SRV = os.path.join(BASE, 'srv')        # la casa del servidor
JAIL = os.path.join(BASE, 'jail')      # su unica raiz
FUERA = os.path.join(BASE, 'fuera')    # fuera de todo
for _d in (JAIL, FUERA):
    os.makedirs(_d)
EXE = mc.copia_exe(SRV)
open(os.path.join(JAIL, 'secreto.txt'), 'w').write('de la jaula')
open(os.path.join(SRV, 'casa.txt'), 'w').write('de la casa del servidor')
TEMP_SRV = os.path.join(SRV, '__delphi-temp')
MAP = (r'Software\Classes\Local Settings\Software\Microsoft\Windows'
       r'\CurrentVersion\AppContainer\Mappings')
ue = ctypes.WinDLL('userenv')
ue.CreateAppContainerProfile.restype = ctypes.c_long
ue.DeleteAppContainerProfile.restype = ctypes.c_long


def _minusculas(s):
    # LowerCase de Delphi: solo A-Z
    return ''.join(ch.lower() if 'A' <= ch <= 'Z' else ch for ch in s)


# la marca de ESTE servidor: MarcaDeEstaCasa = los 8 primeros de ClaveDeCarpeta
# (el MD5 de la ruta canonica LARGA de su carpeta, en minusculas)
MARCA = hashlib.md5(_minusculas(mc.larga(os.path.dirname(EXE))).rstrip('\\').encode('utf-8')).hexdigest()[:8]
MIO = 'delphilspmcp.test.' + MARCA + '.'
# la misma casa por dos caminos: el primer servidor se lanza por la ruta 8.3
# y el segundo por la larga (K13), y la marca tiene que ser la misma
EXE_CORTO = mc.corta(EXE) or EXE
EXE_LARGO = mc.larga(EXE)


def contenedores(todos=False):
    """Los perfiles de contenedor de tests de ESTE servidor (por su marca), o
    los de cualquiera de esta cuenta con todos=True, por su nombre."""
    out = set()
    try:
        k = winreg.OpenKey(winreg.HKEY_CURRENT_USER, MAP)
    except OSError:
        return out  # sin la clave no hay ningun contenedor
    with k:
        i = 0
        while True:
            try:
                sid = winreg.EnumKey(k, i)
            except OSError:
                break
            i += 1
            try:
                with winreg.OpenKey(k, sid) as s:
                    m = winreg.QueryValueEx(s, 'Moniker')[0].lower()
                    if m.startswith(MIO if not todos else 'delphilspmcp.test.'):
                        out.add(m)
            except OSError:
                pass
    return out


def copias():
    return [d for d in os.listdir(TEMP_SRV) if d.startswith('test-')] if os.path.isdir(TEMP_SRV) else []


junction = mc.junction  # EL de mcp_cliente (vivia aqui)


def etiqueta_baja(p):
    o = subprocess.run(['icacls', p], capture_output=True).stdout.decode('cp850', 'replace').lower()
    return 'low mandatory' in o or 'obligatorio bajo' in o


def J(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


ENTORNO = mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_ALLOW_TESTS': '1'})
VIVOS = []          # los servidores de la bateria, para la limpieza
AJENO = 'DelphiLspMcp.Test.00000000.' + uuid.uuid4().hex   # la marca de OTRA casa


def spawn(exe=EXE_CORTO):
    s = mc.Stdio(exe, ENTORNO, nombre='caja', t=600)
    VIVOS.append(s)
    return s


def limpia():
    """Pase lo que pase: los servidores, el contenedor ajeno, el puerto y la
    carpeta de la bateria (unos 40 MB: el exe, los proyectos y su salida)."""
    for s in VIVOS:
        try:
            s.mata()
        except Exception:
            pass
    try:
        ue.DeleteAppContainerProfile(AJENO)
    except Exception:
        pass
    # ...y los de ESTA bateria que hayan quedado (si K12 fallo, no se quedan)
    for m in contenedores():
        try:
            ue.DeleteAppContainerProfile(m)
        except Exception:
            pass
    parar.set()
    try:
        oido.close()
    except Exception:
        pass
    mc.borra(BASE)


atexit.register(limpia)


# un puerto que escucha en ESTA maquina: el test no debe llegar
oido = socket.socket()
oido.bind(('127.0.0.1', 0))
oido.listen(5)
oido.settimeout(0.5)
PUERTO = oido.getsockname()[1]
llegadas = []
parar = threading.Event()


def escucha():
    while not parar.is_set():
        try:
            c, _ = oido.accept()
            llegadas.append(1)
            c.close()
        except socket.timeout:
            pass
        except OSError:
            break


threading.Thread(target=escucha, daemon=True).start()

PROGRAMA = r"""program CajaTest;

{$APPTYPE CONSOLE}

uses
  Winapi.Windows, System.SysUtils, System.IOUtils, Winapi.Winsock2;

procedure Escribe(const AQue, ARuta: string);
begin
  try
    TFile.WriteAllText(ARuta, 'x');
    Writeln('SONDA ', AQue, ' ESCRIBE');
  except
    Writeln('SONDA ', AQue, ' NO');
  end;
end;

procedure Lee(const AQue, ARuta: string);
begin
  try
    if TFile.ReadAllText(ARuta) <> '' then
      Writeln('SONDA ', AQue, ' LEE')
    else
      Writeln('SONDA ', AQue, ' LEE');
  except
    Writeln('SONDA ', AQue, ' NO');
  end;
end;

procedure Lista(const AQue, ACarpeta: string);
begin
  try
    var Cuantas := Length(TDirectory.GetDirectories(ACarpeta));
    Writeln('SONDA ', AQue, ' VE ', Cuantas);
  except
    Writeln('SONDA ', AQue, ' NO');
  end;
end;

procedure Conecta(const AQue: string; APuerto: Word);
var
  Wsa: TWSAData;
  S: TSocket;
  A: TSockAddrIn;
  Modo: u_long;
  W: TFDSet;
  T: TTimeVal;
  Err, Len: Integer;
begin
  WSAStartup($0202, Wsa);
  S := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  Modo := 1;
  ioctlsocket(S, FIONBIO, Modo);
  FillChar(A, SizeOf(A), 0);
  A.sin_family := AF_INET;
  A.sin_port := htons(APuerto);
  A.sin_addr.S_addr := inet_addr('127.0.0.1');
  connect(S, PSockAddr(@A)^, SizeOf(A));
  FD_ZERO(W);
  _FD_SET(S, W);
  T.tv_sec := 3;
  T.tv_usec := 0;
  Err := 1;
  Len := SizeOf(Err);
  if (select(0, nil, @W, nil, @T) = 1) and
     (getsockopt(S, SOL_SOCKET, SO_ERROR, PAnsiChar(@Err), Len) = 0) and (Err = 0) then
    Writeln('SONDA ', AQue, ' CONECTA')
  else
    Writeln('SONDA ', AQue, ' NO');
  closesocket(S);
end;

procedure Entorno(const AQue: string);
var
  P, Q: PChar;
  N: Integer;
begin
  // TODAS las de la configuracion del servidor, no una
  N := 0;
  P := GetEnvironmentStrings;
  Q := P;
  while Q^ <> #0 do
  begin
    if string(Q).StartsWith('DELPHI_MCP_', True) then
      Inc(N);
    Inc(Q, StrLen(Q) + 1);
  end;
  FreeEnvironmentStrings(P);
  Writeln('SONDA ', AQue, ' ', N);
end;

procedure Handles(const AQue: string);
var
  h: NativeUInt;
  fl: DWORD;
  malos, tipo, len: Integer;
  o, e: THandle;
  wsa: TWSAData;
begin
  // un guard que mide el DANO, no un numero magico: ningun handle heredable
  // del test debe ser un SOCKET (el listener de Indy en produccion) ni un
  // PIPE que no sea su propia tuberia (los stdio del servidor). Su stdout y
  // su stderr son el MISMO handle, asi que no se cuentan como ajenos.
  WSAStartup($0202, wsa);
  o := GetStdHandle(STD_OUTPUT_HANDLE);
  e := GetStdHandle(STD_ERROR_HANDLE);
  malos := 0;
  h := 4;
  while h <= 16384 do
  begin
    try
      if GetHandleInformation(THandle(h), fl) and ((fl and HANDLE_FLAG_INHERIT) <> 0) then
      begin
        len := SizeOf(tipo);
        if getsockopt(TSocket(h), SOL_SOCKET, SO_TYPE, PAnsiChar(@tipo), len) = 0 then
          Inc(malos)
        else if (GetFileType(THandle(h)) = FILE_TYPE_PIPE) and
                (THandle(h) <> o) and (THandle(h) <> e) then
          Inc(malos);
      end;
    except
    end;
    Inc(h, 4);
  end;
  Writeln('SONDA ', AQue, ' ', malos);
end;

var
  I: Integer;

begin
  Handles('K18');
  Escribe('K2', 'escrito.txt');
  Escribe('K4a', '..\arriba.txt');
  Escribe('K4b', '..\..\casa_escrita.txt');
  Escribe('K5a', '%(jail)s\fuera_de_su_carpeta.txt');
  Escribe('K5b', '%(fuera)s\fuera_de_la_jaula.txt');
  Lee('K6a', '%(jail)s\secreto.txt');
  Lee('K6b', '%(srv)s\casa.txt');
  Lista('K7', '..');
  Conecta('K8', %(puerto)d);
  Entorno('K14');
  TFile.WriteAllText(TPath.Combine(TPath.GetTempPath, 'temporal.txt'), 't');
  TFile.WriteAllText('grande.log', StringOfChar('g', 20000));
  TFile.WriteAllText('resultado.log', 'linea de log');
  TFile.WriteAllBytes('binario.txt', TBytes.Create(0, 1, 2, 0));
  TFile.WriteAllText('notas.out', 'nota');
  // el corte de 16.384 cae en medio de un par sustituto
  TFile.WriteAllText('emoji.log', StringOfChar('a', 16383) + #$D83D#$DE00 + 'bbbb');
  // detras de todos en el orden de "files": se comen lo que queda del total
  TFile.WriteAllText('z1.log', StringOfChar('z', 20000));
  TFile.WriteAllText('z2.log', StringOfChar('z', 20000));
  TFile.WriteAllText('z3.log', StringOfChar('z', 20000));
  TFile.WriteAllText('z4.log', StringOfChar('z', 20000));
  // muchos ficheros, detras de todos: la lista para en 500 (TEST-033)
  TDirectory.CreateDirectory('zz_muchos'); // ForceDirectories con un nivel relativo lanza
  for I := 1000 to 1599 do
    TFile.WriteAllText('zz_muchos\f' + IntToStr(I) + '.txt', 'm');
  Writeln('PASS caja');
end.
"""

antes = contenedores()
srv = spawn()
r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'CajaTest',
                               'dir': os.path.join(JAIL, 'CajaTest')})
check('K fixture: proyecto de test creado', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
open(os.path.join(JAIL, 'CajaTest', 'CajaTest.dpr'), 'w', encoding='utf-8-sig', newline='\r\n').write(
    PROGRAMA % {'jail': JAIL, 'fuera': FUERA, 'srv': SRV, 'puerto': PUERTO})
# otra copia en la temporal del servidor, plantada DESPUES del arranque (que la vacia)
os.makedirs(os.path.join(TEMP_SRV, 'vecina'), exist_ok=True)
# Contratos con DUnitX REAL: token, datos externos de fixture y token del hijo.
contrato = os.path.join(JAIL, 'ContratoApp')
r = srv.call('delphi_create', {'kind': 'project-test', 'name': 'ContratoApp', 'dir': contrato})
check('A1 fixture: proyecto DUnitX real', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
unidades = mc.ficheros(J(srv.call('delphi_list', {'root': contrato, 'pattern': '*.pas'})))
unidad = mc.real(unidades[0]['path'])
leido = srv.call('delphi_read', {'path': unidad})
texto = '\n'.join(l.split('|', 1)[1] for l in leido.splitlines() if re.match(r'^\d+\|', l))
clase = re.search(r'\b(\w+)\s*=\s*class\b', texto).group(1)
nombre_unidad = re.search(r'\bunit\s+([\w.]+)\s*;', texto).group(1)
externo = os.path.join(FUERA, 'contrato-externo.txt')
with open(externo, 'w') as f:
    f.write('fixture del arnes')
srv.call('delphi_edit', {'path': unidad, 'adduses': 'Winapi.Windows;System.IOUtils;System.SysUtils', 'section': 'implementation'})
metodos = (
r"""[Test] procedure TokenEstaConfinado;
var
  Token: THandle;
  Flag, Len: DWORD;
begin
  Assert.IsTrue(OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token));
  try
    Flag := 0;
    // TokenIsAppContainer=29 (winnt.h); RAD 13 no declara ese miembro.
    Assert.IsTrue(GetTokenInformation(Token, TTokenInformationClass(29), @Flag, SizeOf(Flag), Len));
    Assert.AreEqual<Cardinal>(1, Flag, 'el token es AppContainer');
    TFile.WriteAllText('token-' + IntToStr(GetCurrentProcessId) + '.txt', 'AppContainer');
  finally
    CloseHandle(Token);
  end;
end;""",
r"""[Test] procedure NoAbreDatosExternosDelArnes;
var
  H: THandle;
  Err: DWORD;
begin
  H := CreateFile('%s', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
    nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  Err := GetLastError;
  if H <> INVALID_HANDLE_VALUE then CloseHandle(H);
  Assert.IsTrue(H = INVALID_HANDLE_VALUE, 'no lee el testigo externo');
  Assert.AreEqual<Cardinal>(ERROR_ACCESS_DENIED, Err, 'la lectura se niega por permisos');
  H := CreateFile('%s', GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE,
    nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  Err := GetLastError;
  if H <> INVALID_HANDLE_VALUE then CloseHandle(H);
  Assert.IsTrue(H = INVALID_HANDLE_VALUE, 'no escribe el testigo externo');
  Assert.AreEqual<Cardinal>(ERROR_ACCESS_DENIED, Err, 'la escritura se niega por permisos');
end;""" % (externo.replace("'", "''"), externo.replace("'", "''")),
r"""[Test] procedure ElHijoSigueEnAppContainer;
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  Cmd: string;
  Codigo: DWORD;
begin
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  Cmd := '"' + ParamStr(0) + '" --run:%s.%s.TokenEstaConfinado';
  UniqueString(Cmd);
  Assert.IsTrue(CreateProcess(nil, PChar(Cmd), nil, nil, False,
    CREATE_NO_WINDOW, nil, nil, SI, PI), 'lanza un hijo de la propia fixture');
  try
    Assert.AreEqual<Cardinal>(WAIT_OBJECT_0, WaitForSingleObject(PI.hProcess, 15000), 'el hijo termina');
    Assert.IsTrue(GetExitCodeProcess(PI.hProcess, Codigo));
    Assert.AreEqual<Cardinal>(0, Codigo, 'el test del token pasa en el hijo');
    Assert.IsTrue(TFile.Exists('token-' + IntToStr(PI.dwProcessId) + '.txt'), 'el hijo ejecuto el contrato');
  finally
    TerminateProcess(PI.hProcess, 1);
    CloseHandle(PI.hThread);
    CloseHandle(PI.hProcess);
  end;
end;""" % (nombre_unidad, clase),
)
for metodo in metodos:
    r = srv.call('delphi_edit', {'path': unidad, 'insert': 'metodo', 'inclass': clase, 'visibility': 'public', 'code': metodo})
    check('A1 fixture: atributo y metodo DUnitX insertados', mc.es(r, 'SK_EDIT_ESCRITO_EN_FMT'), r[:300])
r = srv.call('delphi_test', {'command': 'run', 'project': os.path.join(contrato, 'ContratoApp.dproj')}, 600)
contrato_j = J(r)
check('A1 DUnitX real: token, fichero externo y token del hijo pasan en AppContainer',
      contrato_j.get('result') == 'pass' and contrato_j.get('sandboxed') is True and
      contrato_j.get('total') == 4 and contrato_j.get('failed') == 0,
      contrato_j.get('build', {}).get('firstError') or r[:1600])
with open(externo) as f:
    check('A1 el testigo externo sigue intacto', f.read() == 'fixture del arnes')
# 1.13.0 (revisor de tokens): el recuadro de DUnitX (copyright y licencia,
# '*' a los dos lados) ya no viaja en la cola; el resumen, si
_cola = contrato_j.get('outputTail') or ''
check('A1 DUnitX: la cola sin el recuadro de copyright, con el resumen',
      'License' not in _cola and '*****' not in _cola and 'Tests Passed' in _cola and
      'note' not in contrato_j, _cola[:400])

out = srv.call('delphi_test', {'command': 'run', 'project': os.path.join(JAIL, 'CajaTest', 'CajaTest.dproj')}, 600)
j = J(out)
sonda = {}
for _l in (j.get('outputTail') or '').splitlines():
    _l = _l.strip().lstrip('.')
    if _l.startswith('SONDA '):
        _p = _l.split()
        sonda[_p[1]] = ' '.join(_p[2:])
files = {f.get('name'): f for f in (j.get('files') or [])}
if j.get('result') != 'pass':
    # lo que dijo el test, para saber POR QUE (el detalle del check lo corta)
    print('SALIDA DEL TEST:', j.get('result'), j.get('exitCode'), j.get('error'), j.get('timedOut'),
          (j.get('outputTail') or '')[-1500:])
SALIDA = os.path.join(JAIL, 'CajaTest', 'Win64', 'Debug')

check('K1 el test corre y pasa en su contenedor (sandboxed=true)',
      j.get('result') == 'pass' and j.get('sandboxed') is True and j.get('total') == 1, out[:400])
check('K2 escribe en su carpeta (la copia)', sonda.get('K2') == 'ESCRIBE', str(sonda))
check('K2b ...y la carpeta de salida del agente queda intacta: lo escrito no esta alli',
      os.path.isdir(SALIDA) and not os.path.exists(os.path.join(SALIDA, 'escrito.txt'))
      and not os.path.exists(os.path.join(SALIDA, 'resultado.log')),
      str(os.listdir(SALIDA)) if os.path.isdir(SALIDA) else 'sin salida')
check('K2c ...ni se etiqueta nada suyo (hasta la 1.10 se le bajaba la etiqueta)',
      os.path.exists(os.path.join(SALIDA, 'CajaTest.exe'))
      and not etiqueta_baja(os.path.join(SALIDA, 'CajaTest.exe')), '')
check('K3 lo que escribio vuelve en "files", con su contenido',
      files.get('resultado.log', {}).get('content') == 'linea de log', str(list(files)))
check('K3b es texto por la regla de la casa, no por la extension: un .txt binario sin contenido, un .out con el',
      'binario.txt' in files and 'content' not in files['binario.txt']
      and files['binario.txt'].get('noContent') == 'binary'
      and files.get('notas.out', {}).get('content') == 'nota',
      '%s %s' % (files.get('binario.txt'), files.get('notas.out')))
check('K4 no escribe encima de su carpeta: la temporal del servidor',
      sonda.get('K4a') == 'NO' and not os.path.exists(os.path.join(TEMP_SRV, 'arriba.txt')), str(sonda))
check('K4b ...ni en la casa del servidor',
      sonda.get('K4b') == 'NO' and not os.path.exists(os.path.join(SRV, 'casa_escrita.txt')), str(sonda))
check('K5 no escribe en la jaula fuera de su carpeta',
      sonda.get('K5a') == 'NO' and not os.path.exists(os.path.join(JAIL, 'fuera_de_su_carpeta.txt')), str(sonda))
check('K5b ...ni fuera de la jaula',
      sonda.get('K5b') == 'NO' and not os.path.exists(os.path.join(FUERA, 'fuera_de_la_jaula.txt')), str(sonda))
check('K6 no lee un fichero de la jaula', sonda.get('K6a') == 'NO', str(sonda))
check('K6b ...ni uno de la casa del servidor', sonda.get('K6b') == 'NO', str(sonda))
check('K7 no ve las carpetas de al lado (otra copia)', sonda.get('K7') in ('NO', 'VE 0'), str(sonda))
check('K8 sin red: no llega ni al puerto que escucha en esta maquina',
      sonda.get('K8') == 'NO' and not llegadas, '%s, llegadas=%d' % (sonda, len(llegadas)))
check('K18 ningun handle heredable del test es un socket ni un pipe del servidor (solo su tuberia)',
      sonda.get('K18') == '0', 'handles ajenos=%s (0 = solo su stdout/stderr; HANDLE_LIST)' % sonda.get('K18'))
check('K9 la temporal de un test Delphi (TPath.GetTempPath, vacia en el contenedor) cae en su carpeta y vuelve en "files"',
      'temporal.txt' in files, str(list(files)))
_g = files.get('grande.log', {})
check('K10 un log grande vuelve cortado: 16.384 caracteres, "truncated" y la nota (TEST-030)',
      _g.get('truncated') is True and len(_g.get('content', '')) == 16 * 1024
      and mc.abre(j.get('filesNote', ''), 'SN_TEST_FICHEROS_RECORTE_FMT'),
      '%s %s' % ({k: v for k, v in _g.items() if k != 'content'}, j.get('filesNote', '')[:120]))
_e = files.get('emoji.log', {})
check('K10b ...y un corte en medio de un par sustituto deja el par fuera, entero',
      _e.get('truncated') is True and _e.get('content') == 'a' * 16383,
      '%s, %d' % ({k: v for k, v in _e.items() if k != 'content'}, len(_e.get('content', ''))))
_z = [files.get('z%d.log' % i, {}) for i in range(1, 5)]
check('K15 ...y entre todos no pasan de 65.536 caracteres: el de detras del total, sin contenido',
      sum(len(f.get('content', '')) for f in files.values()) == 64 * 1024
      and any(z.get('truncated') for z in _z) and 'content' not in _z[3] and _z[3].get('size') == 20000
      and _z[3].get('noContent') == 'past-total',
      '%d %s' % (sum(len(f.get('content', '')) for f in files.values()),
                 [{k: v for k, v in f.items() if k != 'content'} for f in _z]))
# 11 ficheros de la sonda + 600 en zz_muchos = 611: 500 en la lista, 111 fuera
_muchos = [f for f in files if f.startswith('zz_muchos')]
check('K20 la lista para en 500 entradas y dice cuantos quedan fuera (TEST-033); los de detras del total, past-total',
      len(files) == 500 and j.get('filesNotListed') == 111
      and mc.abre(j.get('filesListNote', ''), 'SN_TEST_FICHEROS_FUERA_FMT')
      and all(files[f].get('noContent') == 'past-total' for f in _muchos),
      '%d listados (%d de zz_muchos), fuera %s' % (len(files), len(_muchos), j.get('filesNotListed')))
_control = [k for k in ENTORNO if k.upper().startswith('DELPHI_MCP_')]
check('K14 no ve la configuracion del servidor: NI UNA DELPHI_MCP_* en su entorno',
      sonda.get('K14') == '0' and len(_control) >= 2, '%s, el servidor tenia %s' % (sonda, _control))

# K11: paquetes en tiempo de ejecucion -> fuera ANTES de compilar
r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'PaqTest',
                               'dir': os.path.join(JAIL, 'PaqTest')})
DPROJ = os.path.join(JAIL, 'PaqTest', 'PaqTest.dproj')
_x = open(DPROJ, encoding='utf-8-sig').read()
_m = "<PropertyGroup Condition=\"'$(Base)'!=''\">"
check('K11 fixture: el grupo Base del .dproj existe', _m in _x, _x[:300])
open(DPROJ, 'w', encoding='utf-8-sig', newline='').write(
    _x.replace(_m, _m + '\r\n        <UsePackages>true</UsePackages>', 1))
out = srv.call('delphi_test', {'command': 'run', 'project': DPROJ}, 300)
check('K11 un proyecto con paquetes en tiempo de ejecucion se rechaza ANTES de compilar (TEST-028)',
      mc.es(out, 'SR_TEST_PAQUETES_FMT') and not os.path.exists(os.path.join(JAIL, 'PaqTest', 'Win64')),
      out[:300])

# K16: una salida por encima del tope de la copia (256 MB). Un fichero DISPERSO:
# 300 MB de tamano que no ocupan disco
CAJA = os.path.join(JAIL, 'CajaTest', 'CajaTest.dproj')
ENORME = os.path.join(SALIDA, 'enorme.bin')
open(ENORME, 'wb').close()
_disperso = subprocess.run(['fsutil', 'sparse', 'setflag', ENORME], capture_output=True).returncode == 0
with open(ENORME, 'r+b') as _f:
    _f.truncate(300 * 1024 * 1024)
check('K16 fixture: 300 MB dispersos en la salida del test', _disperso and os.path.getsize(ENORME) == 300 * 1024 * 1024, '')
out = srv.call('delphi_test', {'command': 'run', 'project': CAJA, 'nobuild': True}, 300)
check('K16 una salida por encima del tope de la copia se rechaza (TEST-029) y el test no corre',
      mc.abre(out, 'SR_TEST_COPIA_TOPE_FMT') and '"total"' not in out, out[:300])
os.remove(ENORME)

# K16b: un SYMLINK a un fichero grande cuenta lo de DETRAS: antes contaba la
# entrada del enlace (0 bytes) y copiaba los 300 MB. Crear un symlink pide
# el privilegio (o el modo desarrollador): sin el, se dice y no se mide
DISPERSO = os.path.join(JAIL, 'disperso.bin')
open(DISPERSO, 'wb').close()
subprocess.run(['fsutil', 'sparse', 'setflag', DISPERSO], capture_output=True)
with open(DISPERSO, 'r+b') as _f:
    _f.truncate(300 * 1024 * 1024)
ENLACE = os.path.join(SALIDA, 'enlace.bin')
try:
    os.symlink(DISPERSO, ENLACE)
    _sym = True
except OSError:
    _sym = False
if _sym:
    out = srv.call('delphi_test', {'command': 'run', 'project': CAJA, 'nobuild': True}, 300)
    check('K16b ...y un symlink a 300 MB cuenta lo de detras, no su entrada: TEST-029 y no corre',
          mc.abre(out, 'SR_TEST_COPIA_TOPE_FMT') and '"total"' not in out, out[:300])
    os.remove(ENLACE)  # el enlace, nunca lo de detras
else:
    print('NOTA: K16b no se mide: esta cuenta no puede crear symlinks (privilegio o modo desarrollador)')
os.remove(DISPERSO)

# K17: un junction roto en la salida: la copia no se puede hacer, se dice con
# su etiqueta y el test no corre (antes, una excepcion sin nombre)
BORRADA = os.path.join(JAIL, 'borrada')
os.makedirs(BORRADA)
ROTO = os.path.join(SALIDA, 'enlace_roto')
_hecho = junction(ROTO, BORRADA)
os.rmdir(BORRADA)
check('K17 fixture: un junction roto en la salida del test', _hecho and not os.path.exists(BORRADA), '')
out = srv.call('delphi_test', {'command': 'run', 'project': CAJA, 'nobuild': True}, 300)
check('K17 una copia que no se puede hacer lo dice con su etiqueta (TEST-031) y el test no corre',
      mc.abre(out, 'SR_TEST_COPIA_FMT') and '"total"' not in out, out[:300])
os.rmdir(ROTO)  # quita el enlace, nunca lo de detras

# K19: un hijo PERSISTENTE del test (sigue vivo tras el padre) con un fichero
# abierto en la copia. Al acabar no queda ni el hijo ni la copia: el job mata
# el arbol y EsperaJobVacio aguarda a que muera ANTES de la foto y el borrado
# (revision Opus 4.8). El mutante sin la espera no expone la carrera de forma
# determinista -kill-on-close suele ganar el margen-: es garantia de orden.
PROG_HIJO = r'''program HijoTest;
{$APPTYPE CONSOLE}
uses Winapi.Windows, System.SysUtils, System.Classes;
var SI: TStartupInfo; PI: TProcessInformation; Cmd: string; f: TFileStream;
begin
  if (ParamCount >= 1) and (ParamStr(1) = 'child') then
  begin
    f := TFileStream.Create('abierto.lock', fmCreate);
    Sleep(15000);
    f.Free;
    Halt(0);
  end;
  FillChar(SI, SizeOf(SI), 0); SI.cb := SizeOf(SI);
  Cmd := '"' + ParamStr(0) + '" child'; UniqueString(Cmd);
  if CreateProcess(nil, PChar(Cmd), nil, nil, False, CREATE_NO_WINDOW, nil, nil, SI, PI) then
  begin
    Writeln('CHILDPID ', PI.dwProcessId);
    CloseHandle(PI.hThread); CloseHandle(PI.hProcess);
  end
  else
    Writeln('CHILDPID 0');
  Writeln('PASS hijo');
end.'''
HIJO = os.path.join(JAIL, 'HijoTest')
srv.call('delphi_create', {'kind': 'project-console', 'name': 'HijoTest', 'dir': HIJO})
open(os.path.join(HIJO, 'HijoTest.dpr'), 'w', encoding='utf-8-sig', newline='\r\n').write(PROG_HIJO)
out = srv.call('delphi_test', {'command': 'run', 'project': os.path.join(HIJO, 'HijoTest.dproj')}, 300)
j19 = J(out)
pid19 = next((l.strip().lstrip('.').split()[1] for l in (j19.get('outputTail') or '').splitlines()
              if l.strip().lstrip('.').startswith('CHILDPID')), '0')
time.sleep(0.3)
vivo19 = pid19 not in ('0', '') and pid19 in subprocess.run(
    ['tasklist', '/fi', 'PID eq ' + pid19], capture_output=True, text=True).stdout
check('K19 un hijo persistente del test acaba muerto y su copia borrada (job + EsperaJobVacio)',
      j19.get('result') == 'pass' and not vivo19 and not copias(),
      'pid=%s vivo=%s copias=%s' % (pid19, vivo19, copias()))

check('K12 no queda ningun contenedor', not (contenedores() - antes), str(contenedores() - antes))
check('K12b ...ni copias en la temporal del servidor', not copias(), str(copias()))

# K13: el servidor muere con un test dentro; su contenedor queda huerfano
LENTO = os.path.join(JAIL, 'LentoTest')
srv.call('delphi_create', {'kind': 'project-console', 'name': 'LentoTest', 'dir': LENTO})
open(os.path.join(LENTO, 'LentoTest.dpr'), 'w', encoding='utf-8-sig', newline='\r\n').write(
    "program LentoTest;\n\n{$APPTYPE CONSOLE}\n\nuses\n  System.SysUtils;\n\nbegin\n"
    "  Sleep(60000);\n  Writeln('PASS lento');\nend.\n")
_sid = ctypes.c_void_p()
ue.CreateAppContainerProfile(AJENO, AJENO, AJENO, None, 0, ctypes.byref(_sid))
antes2 = contenedores()
check('K13 fixture: el contenedor de otra casa existe', AJENO.lower() in contenedores(todos=True),
      str(contenedores(todos=True)))
hilo = threading.Thread(target=lambda: srv.call(
    'delphi_test', {'command': 'run', 'project': os.path.join(LENTO, 'LentoTest.dproj'),
                    'timeoutms': 120000}, 300), daemon=True)
hilo.start()
huerfano = None
_fin = time.time() + 240
while time.time() < _fin and not huerfano:
    nuevos = contenedores() - antes2
    huerfano = next(iter(nuevos), None)
    time.sleep(0.5)
time.sleep(2)
srv.mata()
time.sleep(1)
check('K13 fixture: muerto el servidor a mitad de un test, su contenedor (con SU marca) queda huerfano',
      huerfano is not None and huerfano in contenedores(),
      'marca %s; los de la cuenta: %s' % (MARCA, contenedores(todos=True)))
# el mismo exe por OTRO camino: el primero se lanzo por la ruta 8.3, este por
# la larga; la marca sale de la ruta canonica (ClaveDeCarpeta), no del texto
check('K13 fixture: la CARPETA del exe se nombra de dos formas (8.3 y larga)',
      os.path.dirname(EXE_CORTO).lower() != os.path.dirname(EXE_LARGO).lower(),
      '%s | %s' % (EXE_CORTO, EXE_LARGO))
srv2 = spawn(EXE_LARGO)
srv2.call('delphi_workspace', {})
check('K13 el siguiente arranque del MISMO servidor, por su ruta larga, lo borra',
      huerfano is not None and huerfano not in contenedores(), str(contenedores()))
check('K13b ...y no toca el de otra casa (puede estar en uso)', AJENO.lower() in contenedores(todos=True),
      str(contenedores(todos=True)))
check('K13c ...y la copia de aquel test se fue con la temporal', not copias(), str(copias()))
mc.fin('delphi_test container battery')  # limpia() deja la maquina como estaba
