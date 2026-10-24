"""1.20.1 - set-version on a project the IDE made. The version information
the IDE writes when "Include version information" is checked is the
FileVersion key of VerInfo_Keys - the key the build takes the binary's
version from - and the four VerInfo_MajorVer.. numbers only once the version
is no longer 1.0.0.0. set-version asked for VerInfo_MajorVer and refused with
CFG-003 every new project of the IDE and 284 of the 296 .dproj of the 37.0
samples that include the version (Hermes, targeted test of 1.20.1, measured
17-oct-2026). The fixtures are the IDE's own templates (ObjRepos), found where
delphi_installs says the installation is.

  V1  the IDE's VCL template (SDIApp): set-version answers, and says what it
      had (the key: 1.0.0.0)
  V2  ...the four numbers enter in the group that holds the FileVersion key,
      right before its VerInfo_Keys, and the keys say the new version
  V3  ...and nothing else of the file changes
  V4  the judge: the binary built from it carries that version (FILEVERSION)
  V5  the IDE's FMX template (Tabbed): one block per group with the key
      (Base_Win32 and Base_Win64), none elsewhere, nothing else changed
  V6  a project with no version information at all: CFG-003, nothing written
  V7  a console delphi_create makes is born as the IDE makes one (projects
      the 37.0 IDE had just created, 17-oct-2026): the keys and no
      VerInfo_IncludeVerInfo, and {$R *.res} in its .dpr; set-version writes
      it and says the binary does not carry it (SF_CFG_VERSION_NO_INCLUIDA, a
      fragment of its answer) - and the built exe
      indeed carries none
  V8  a VCL, FMX or package project delphi_create makes includes the version
      in Base_Win32 and Base_Win64, and set-version maintains it there
  V9  the judge: the exe of a VCL project just created carries the version
  V10 include=true (the wall of the targeted test: no tool could check
      "Include version information"): on the console, VerInfo_IncludeVerInfo
      =true in Base_Win32 and Base_Win64, right before the numbers as the IDE
      lays it out, the answer says so - and the judge: its exe carries it
  V11 ...again: no second VerInfo_IncludeVerInfo, the file does not change
  V12 include with another command is refused, not ignored
  V13 a .dproj in delphi_edit and delphi_textedit: the SAME answer, and it
      names delphi_config (they sent the agent to each other: EDIT-032 to
      delphi_textedit, TEXT-001 to the IDE / delphi_create)

V1-V5 and V7-V13 are RED with the binary before this fix, V10-V13 also with
eb35410, the first fix (run the battery
with it as argument); V6 is green with both.

Usage:  python tests/test_set_version_1201.py [path-to-DelphiLspMcp.exe]
"""
import os, re, shutil, ctypes
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('setversion1201')
EXE = mc.copia_exe(BASE)
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='setver', t=600)
# un trozo de la respuesta (SF_) no lleva etiqueta: se busca por su frase
NO_INCLUIDA = mc.catalogo()['SF_CFG_VERSION_NO_INCLUIDA'].strip()[:40]
INCLUIDA = mc.catalogo()['SF_CFG_VERSION_INCLUIDA_FMT'].split('%')[0]

# donde esta la instalacion: lo dice el servidor, no se supone
RAIZ = mc.raiz_ide(S.call)
REPOS = os.path.join(RAIZ, 'ObjRepos', 'en')
check('la instalacion activa trae sus plantillas (ObjRepos)', os.path.isdir(REPOS), RAIZ)

NUM = ('<VerInfo_MajorVer>2</VerInfo_MajorVer>', '<VerInfo_MinorVer>3</VerInfo_MinorVer>',
       '<VerInfo_Release>4</VerInfo_Release>', '<VerInfo_Build>5</VerInfo_Build>')


def plantilla(sub, nombre):
    """Una copia de la plantilla ObjRepos\\en\\<sub> del IDE."""
    d = os.path.join(BASE, nombre)
    shutil.copytree(os.path.join(REPOS, sub), d)
    return d


def esperado(antes):
    """Lo que tiene que quedar: los cuatro numeros delante de cada VerInfo_Keys
    que lleva FileVersion, con su sangria y el salto del fichero, y las claves
    con la version nueva. Nada mas."""
    eol = '\r\n' if '\r\n' in antes else '\n'
    x = re.sub(r'([ \t]*)(<VerInfo_Keys>[^<]*FileVersion=)',
               lambda m: ''.join(m.group(1) + n + eol for n in NUM) + m.group(1) + m.group(2), antes)
    return re.sub(r'((?:File|Product)Version=)[\d.]+', r'\g<1>2.3.4.5', x)


def version_del_exe(exe):
    """El FILEVERSION del recurso de version de un binario ('' si no lo lleva)."""
    v = ctypes.windll.version
    n = v.GetFileVersionInfoSizeW(exe, None)
    if not n:
        return ''
    buf = ctypes.create_string_buffer(n)
    v.GetFileVersionInfoW(exe, 0, n, buf)
    p, l = ctypes.c_void_p(), ctypes.c_uint()
    if not v.VerQueryValueW(buf, '\\', ctypes.byref(p), ctypes.byref(l)):
        return ''
    ms, ls = ctypes.cast(p, ctypes.POINTER(ctypes.c_uint32))[2:4]
    return '%d.%d.%d.%d' % (ms >> 16, ms & 0xffff, ls >> 16, ls & 0xffff)


def set_version(dproj):
    return S.call('delphi_config', {'project': dproj, 'command': 'set-version', 'version': '2.3.4.5'})


# ---- V1..V4 la plantilla VCL del IDE ----
SDI = plantilla(os.path.join('DelphiWin32', 'SDIApp'), 'Sdi')
P1 = os.path.join(SDI, 'SDIAPP.dproj')
b1 = open(P1, 'rb').read()
antes = mc.lee(P1)
check('V1 la plantilla VCL lleva la clave y no los numeros (lo que mide la bateria)',
      antes.count('FileVersion=1.0.0.0') == 1 and '<VerInfo_MajorVer' not in antes, '')
r = set_version(P1)
x = mc.lee(P1)
check('V1 set-version contesta en la plantilla VCL del IDE', mc.abre(r, 'SN_CONFIG_VERSION_OK_FMT'), r[:300])
check('V1 ...y dice lo que tenia: la clave, 1.0.0.0', '(was 1.0.0.0)' in r, r[:200])
check('V2 los cuatro numeros, delante de la VerInfo_Keys de su grupo, y las claves en 2.3.4.5',
      re.search(r'<VerInfo_MajorVer>2</VerInfo_MajorVer>\s*<VerInfo_MinorVer>3</VerInfo_MinorVer>\s*'
                r'<VerInfo_Release>4</VerInfo_Release>\s*<VerInfo_Build>5</VerInfo_Build>\s*'
                r'<VerInfo_Keys>[^<]*FileVersion=2\.3\.4\.5;[^<]*ProductVersion=2\.3\.4\.5', x) is not None,
      re.findall(r'<VerInfo_\w+>[^<]*', x)[:8])
check('V3 ...y nada mas cambia (ni la codificacion)',
      x == esperado(antes) and open(P1, 'rb').read()[:3] == b1[:3], '')
r = S.call('delphi_build', {'project': P1, 'platform': 'Win32', 'config': 'Debug'}, 600)
exe = os.path.join(SDI, 'Win32', 'Debug', 'SDIAPP.exe')
check('V4 el juez: el binario compilado lleva la version 2.3.4.5',
      os.path.isfile(exe) and version_del_exe(exe) == '2.3.4.5',
      (version_del_exe(exe) if os.path.isfile(exe) else 'sin exe') + ' ' + r[:200])

# ---- V5 la plantilla FMX del IDE: la clave en dos grupos ----
TAB = plantilla(os.path.join('MobileApps', 'Tabbed'), 'Tab')
P5 = os.path.join(TAB, 'TabbedApplication.dproj')
antes = mc.lee(P5)
r = set_version(P5)
x = mc.lee(P5)
grupos = re.findall(r'<PropertyGroup Condition="([^"]*)">(.*?)</PropertyGroup>', x, re.S)
con = [c for c, g in grupos if '<VerInfo_MajorVer>' in g]
check('V5 set-version contesta en la plantilla FMX del IDE', mc.abre(r, 'SN_CONFIG_VERSION_OK_FMT'), r[:300])
check('V5 ...un bloque en cada grupo con la clave (Base_Win32 y Base_Win64) y en ninguno mas',
      sorted(con) == sorted(c for c, g in grupos if re.search(r'<VerInfo_Keys>[^<]*FileVersion=', g))
      and len(con) == 2 and all('Win32' in c or 'Win64' in c for c in con), con)
check('V5 ...y nada mas cambia (Android, iOS, macOS intactos)', x == esperado(antes), '')

def crea(kind, nombre):
    d = os.path.join(BASE, nombre)
    r = S.call('delphi_create', {'kind': kind, 'name': nombre, 'dir': d})
    check('%s creado (%s)' % (nombre, kind), mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    return os.path.join(d, nombre + '.dproj')


def grupos_con(x, tag):
    return sorted(re.search(r"'\$\((\w+)\)'!=''$", c.strip()).group(1)
                  for c, g in re.findall(r'<PropertyGroup Condition="([^"]*)">(.*?)</PropertyGroup>', x, re.S)
                  if tag in g)


# ---- V6 un proyecto sin informacion de version ----
P6 = crea('project-console', 'Sin')
b = open(P6, 'rb').read()
t = re.sub(r'[ \t]*<VerInfo_(?:Keys|IncludeVerInfo)>[^<]*</VerInfo_\w+>\r\n', '', b.decode('utf-8-sig'))
assert 'VerInfo_Keys' not in t, 'la fixture no mide'
open(P6, 'wb').write((b'\xef\xbb\xbf' if b.startswith(b'\xef\xbb\xbf') else b'') + t.encode('utf-8'))
b6 = open(P6, 'rb').read()
r = set_version(P6)
check('V6 sin clave ni numeros: CFG-003', mc.rechazado(r) and mc.abre(r, 'SR_CONFIG_VERSION_SIN_VERINFO'), r[:300])
check('V6 ...y no se escribe nada', open(P6, 'rb').read() == b6, '')

# ---- V7 una consola: las claves y no VerInfo_IncludeVerInfo, como la crea el IDE ----
P7 = crea('project-console', 'Cons')
x = mc.lee(P7)
check('V7 la consola nace como la del IDE: las claves en Base_Win32 y Base_Win64, sin IncludeVerInfo',
      grupos_con(x, 'FileVersion=1.0.0.0') == ['Base_Win32', 'Base_Win64'] and 'VerInfo_IncludeVerInfo' not in x,
      grupos_con(x, 'VerInfo_'))
check('V7 ...y su .dpr enlaza el recurso, como la plantilla del IDE',
      '{$APPTYPE CONSOLE}\r\n\r\n{$R *.res}\r\n\r\nuses' in mc.lee(P7[:-6] + '.dpr'), '')
r = set_version(P7)
check('V7 set-version lo escribe', mc.abre(r, 'SN_CONFIG_VERSION_OK_FMT')
      and mc.lee(P7).count('FileVersion=2.3.4.5;') == 2, r[:300])
check('V7 ...y dice que el binario no la lleva', NO_INCLUIDA in r, r[-400:])
r = S.call('delphi_build', {'project': P7, 'platform': 'Win64', 'config': 'Debug'}, 600)
exe = os.path.join(BASE, 'Cons', 'Win64', 'Debug', 'Cons.exe')
check('V7 el juez lo confirma: el exe de la consola compila y no lleva version',
      os.path.isfile(exe) and version_del_exe(exe) == '', r[:300])

# ---- V8 VCL, FMX y paquete, recien creados ----
for kind, nombre in (('project-vcl', 'Vcl8'), ('project-fmx', 'Fmx8'), ('project-package', 'Pkg8')):
    P = crea(kind, nombre)
    x = mc.lee(P)
    check('V8 %s nace con la version incluida en Base_Win32 y Base_Win64' % nombre,
          grupos_con(x, '<VerInfo_IncludeVerInfo>true') == ['Base_Win32', 'Base_Win64']
          and grupos_con(x, 'FileVersion=1.0.0.0') == ['Base_Win32', 'Base_Win64'], grupos_con(x, 'VerInfo_'))
    r = set_version(P)
    x = mc.lee(P)
    check('V8 %s: set-version contesta, sin decir que no la lleva' % nombre,
          mc.abre(r, 'SN_CONFIG_VERSION_OK_FMT') and NO_INCLUIDA not in r, r[:300])
    check('V8 %s: los cuatro numeros en los dos grupos de la clave' % nombre,
          grupos_con(x, '<VerInfo_MajorVer>2</VerInfo_MajorVer>') == ['Base_Win32', 'Base_Win64']
          and x.count('FileVersion=2.3.4.5;') == 2, grupos_con(x, 'VerInfo_'))

# ---- V9 el juez sobre lo que crea delphi_create ----
P9 = os.path.join(BASE, 'Vcl8', 'Vcl8.dproj')
r = S.call('delphi_build', {'project': P9, 'platform': 'Win64', 'config': 'Debug'}, 600)
exe = os.path.join(BASE, 'Vcl8', 'Win64', 'Debug', 'Vcl8.exe')
check('V9 el exe del proyecto VCL recien creado lleva la version 2.3.4.5',
      os.path.isfile(exe) and version_del_exe(exe) == '2.3.4.5',
      (version_del_exe(exe) if os.path.isfile(exe) else 'sin exe') + ' ' + r[:200])

# ---- V10..V12 include=true: lo que hace la casilla del IDE ----
r = S.call('delphi_config', {'project': P7, 'command': 'set-version', 'version': '3.0.0.1', 'include': True})
x = mc.lee(P7)
check('V10 include=true en la consola: contesta y dice que el binario la lleva',
      mc.abre(r, 'SN_CONFIG_VERSION_OK_FMT') and INCLUIDA in r and NO_INCLUIDA not in r, r[-300:])
check('V10 ...VerInfo_IncludeVerInfo=true en Base_Win32 y Base_Win64, delante de los numeros (como el IDE)',
      grupos_con(x, '<VerInfo_IncludeVerInfo>true') == ['Base_Win32', 'Base_Win64']
      and len(re.findall(r'<VerInfo_IncludeVerInfo>true</VerInfo_IncludeVerInfo>\r\n[ \t]*<VerInfo_MajorVer>3<', x)) == 2,
      re.findall(r'<VerInfo_\w+>[^<]*', x)[:12])
r = S.call('delphi_build', {'project': P7, 'platform': 'Win64', 'config': 'Debug'}, 600)
exe = os.path.join(BASE, 'Cons', 'Win64', 'Debug', 'Cons.exe')
check('V10 el juez: el exe de la consola lleva ahora la version 3.0.0.1',
      os.path.isfile(exe) and version_del_exe(exe) == '3.0.0.1',
      (version_del_exe(exe) if os.path.isfile(exe) else 'sin exe') + ' ' + r[:200])
b10 = open(P7, 'rb').read()
r = S.call('delphi_config', {'project': P7, 'command': 'set-version', 'version': '3.0.0.1', 'include': True})
check('V11 otra vez: contesta, sin un segundo IncludeVerInfo y sin cambiar el fichero',
      mc.abre(r, 'SN_CONFIG_VERSION_OK_FMT') and open(P7, 'rb').read() == b10
      and mc.lee(P7).count('<VerInfo_IncludeVerInfo>') == 2, r[:200])
r = S.call('delphi_config', {'project': P7, 'command': 'view', 'include': True})
check('V12 include con otro comando: se dice, no se ignora', mc.rechazado(r)
      and mc.abre(r, 'SR_CONFIG_NO_ES_DEL_COMANDO_FMT') and 'include' in r, r[:300])

# ---- V13 un .dproj en las dos tools de edicion: el mismo texto, que manda a delphi_config ----
r1 = S.call('delphi_edit', {'path': P7, 'old': '<Project', 'new': '<Project'})
r2 = S.call('delphi_textedit', {'path': P7, 'old': '<Project', 'new': '<Project'})
check('V13 delphi_edit y delphi_textedit con un .dproj: EDIT-128 los dos, que nombra delphi_config',
      mc.abre(r1, 'SR_EDIT_FICHERO_DE_PROYECTO_FMT') and mc.abre(r2, 'SR_EDIT_FICHERO_DE_PROYECTO_FMT')
      and 'delphi_config' in r1 and open(P7, 'rb').read() == b10, [r1[:160], r2[:160]])

S.cierra()
mc.fin('set-version 1.20.1')
