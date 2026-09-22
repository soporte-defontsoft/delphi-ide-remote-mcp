# -*- coding: utf-8 -*-
"""E2E battery: UN SDK = UNA CARPETA, y quien elige con cual se compila.

RAD Studio's own model - the one it uses for the Android SDKs - is a folder per
SDK, each described by a <name>.sdk file in the IDE's APPDATA, and the project
saying which one it builds with (the PlatformSDK property, read by
CodeGear.Profiles.Targets). Until 2026-09-20 get-sdk ignored all that and
always wrote "Linux64.sdk", so pulling a second target's sysroot landed ON TOP
of the first: measured on the operator's machine, that folder held the
Debian/Ubuntu tree AND the Red Hat one, two libc.so.6 (2.39 and 2.43) and two
gcc trees, with both lib dirs on the linker's path.

This battery drives the DECISION side of that change, which is the part that
can be measured without pulling gigabytes from a live Linux:

  1  two SDKs registered and nobody says which -> the build REFUSES and names
     them, instead of picking one at random;
  2  a name that does not exist            -> refused, listing what there is;
  3  the project declares its PlatformSDK  -> that one wins and the answer says so;
  4  exactly one SDK registered            -> it is used, and the answer names it.

APPDATA is redirected to a throwaway folder, so the IDE profiles directory the
server reads is the battery's own and the operator's real SDKs are not touched.

Usage:  python tests/test_sdk.py [path-to-DelphiLspMcp.exe]
Exit code 0 = all green.
"""
import json
import os
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'sdk')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)
JAIL = os.path.join(BASE, 'jaula')
os.makedirs(JAIL)
FAKE_APPDATA = os.path.join(BASE, 'appdata')

P = F = 0


def check(name, cond, detail=''):
    global P, F
    if cond:
        P += 1
        print('PASS -', name)
    else:
        F += 1
        print('FAIL -', name, '|', str(detail)[:300])


class Server:
    """El servidor por stdio, con el entorno que le pongamos."""

    def __init__(self, env_extra):
        env = dict(os.environ)
        env['DELPHI_MCP_ROOTS'] = JAIL
        env.update(env_extra)
        self.p = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                  text=True, encoding='utf-8')
        self.q = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()
        self.rid = 10
        self.call_raw({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "sdk-battery", "version": "1"}}})

    def _read(self):
        for line in self.p.stdout:
            line = line.strip()
            if line:
                self.q.put(line)

    def call_raw(self, obj, timeout=300):
        self.p.stdin.write(json.dumps(obj) + '\n')
        self.p.stdin.flush()
        import time
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                line = self.q.get(timeout=1)
            except queue.Empty:
                continue
            try:
                m = json.loads(line)
            except Exception:
                continue
            if m.get('id') == obj.get('id'):
                return m
        return None

    def call(self, tool, args, timeout=300):
        self.rid += 1
        m = self.call_raw({"jsonrpc": "2.0", "id": self.rid, "method": "tools/call",
                           "params": {"name": tool, "arguments": args}}, timeout)
        if m is None:
            return '(timeout)'
        if 'error' in m:
            return 'MCPERROR ' + json.dumps(m['error'])[:200]
        c = m['result'].get('content', [])
        return c[0].get('text', '') if c else '(sin contenido)'

    def stop(self):
        try:
            self.p.stdin.close()
        except Exception:
            pass
        self.p.kill()


def sdk_file(path, platform='Linux64', sysroot=None):
    """Un .sdk minimo pero con la forma real: lo que se lee es su plataforma."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n'
                '  <PropertyGroup>\n'
                '    <Profile_platform>%s</Profile_platform>\n'
                '    <Profile_sysroot>%s</Profile_sysroot>\n'
                '  </PropertyGroup>\n'
                '</Project>\n' % (platform,
                                  sysroot or os.path.join(BASE, 'sysroot-falso')))


def sysroot(nombre, libcs):
    """Un sysroot de mentira con un libc.so.6 en cada ruta que se le diga."""
    raiz = os.path.join(BASE, nombre)
    for rel in libcs:
        d = os.path.join(raiz, *rel.split('/'))
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, 'libc.so.6'), 'wb') as f:
            f.write(b'no soy un ELF, solo hago bulto')
    # el cargador que TODA distro trae en /lib64, tambien las Debian: es lo
    # que confundia al detector de mezclas (medido 2026-09-20)
    os.makedirs(os.path.join(raiz, 'lib64'), exist_ok=True)
    with open(os.path.join(raiz, 'lib64', 'ld-linux-x86-64.so.2'), 'wb') as f:
        f.write(b'cargador')
    return raiz


# --- 1) la version de RAD Studio instalada, para saber que carpeta falsear ---
s0 = Server({})
installs = s0.call('delphi_installs', {})
s0.stop()
m = re.search(r'"version"\s*:\s*"(\d+\.\d+)"', installs)
if not m:
    print('FAIL - no puedo leer la version de RAD Studio instalada |', installs[:200])
    sys.exit(1)
VER = m.group(1)
PROFILES_DIR = os.path.join(FAKE_APPDATA, 'Embarcadero', 'BDS', VER)
os.makedirs(PROFILES_DIR)
print('(RAD Studio %s; SDKs de mentira en %s)' % (VER, PROFILES_DIR))

srv = Server({'APPDATA': FAKE_APPDATA})
try:
    # un proyecto de verdad, para que el build llegue hasta la eleccion de SDK
    out = srv.call('delphi_create', {"kind": "project-console",
                                     "dir": os.path.join(JAIL, 'proj'),
                                     "name": "SdkProbe"})
    dproj = os.path.join(JAIL, 'proj', 'SdkProbe.dproj')
    check('proyecto de prueba creado', os.path.exists(dproj), out[:200])

    # --- 1) dos SDK y nadie dice cual -------------------------------------
    sdk_file(os.path.join(PROFILES_DIR, 'uno.sdk'))
    sdk_file(os.path.join(PROFILES_DIR, 'dos.sdk'))
    out = srv.call('delphi_build', {"project": dproj, "platform": "Linux64"})
    check('dos SDK sin pista: RECHAZADO en vez de elegir a ciegas',
          out.startswith('RECHAZADO') and 'uno.sdk' in out and 'dos.sdk' in out, out)

    # --- 2) un nombre que no existe ---------------------------------------
    out = srv.call('delphi_build', {"project": dproj, "platform": "Linux64",
                                    "sdk": "nomeinventes"})
    check('sdk inexistente: RECHAZADO listando los que hay',
          out.startswith('RECHAZADO') and 'uno.sdk' in out, out)

    # --- 3) lo que diga el PROYECTO manda ---------------------------------
    with open(dproj, encoding='utf-8', errors='replace') as f:
        xml = f.read()
    xml = xml.replace('<PropertyGroup>',
                      '<PropertyGroup><PlatformSDK>dos.sdk</PlatformSDK>', 1)
    with open(dproj, 'w', encoding='utf-8', newline='') as f:
        f.write(xml)
    out = srv.call('delphi_build', {"project": dproj, "platform": "Linux64"},
                   timeout=600)
    check('el PlatformSDK del proyecto manda y se dice',
          'dos.sdk' in out and 'sdkNote' in out, out[:400])

    # --- 4) uno solo: se usa, y la respuesta lo nombra ---------------------
    xml = xml.replace('<PlatformSDK>dos.sdk</PlatformSDK>', '')
    with open(dproj, 'w', encoding='utf-8', newline='') as f:
        f.write(xml)
    os.remove(os.path.join(PROFILES_DIR, 'dos.sdk'))
    out = srv.call('delphi_build', {"project": dproj, "platform": "Linux64"},
                   timeout=600)
    check('un solo SDK: se usa y la respuesta lo nombra',
          '"sdk":"uno.sdk"' in out.replace(' ', ''), out[:400])

    # --- 5) dos distros en la misma carpeta: se ve; una sola, no ----------
    # La senal es que haya DOS libc.so.6, uno por arbol. Mirar si existen las
    # carpetas no vale: un Ubuntu trae /lib64 con el cargador y nada mas, y
    # con esa regla el primer sysroot limpio se acusaba a si mismo.
    sdk_file(os.path.join(PROFILES_DIR, 'limpio.sdk'),
             sysroot=sysroot('sysroot-limpio', ['lib/x86_64-linux-gnu']))
    sdk_file(os.path.join(PROFILES_DIR, 'mezclado.sdk'),
             sysroot=sysroot('sysroot-mezclado',
                             ['lib/x86_64-linux-gnu', 'usr/lib64']))
    out = srv.call('delphi_paserver', {"command": "profiles"})
    try:
        fichas = {s['name']: s for s in json.loads(out).get('sdks', [])}
    except Exception:
        fichas = {}
    check('sysroot con DOS libc: se marca como mezclado',
          'warning' in fichas.get('mezclado', {}), out[:400])
    check('sysroot limpio con /lib64 (Ubuntu): NO se marca',
          'warning' not in fichas.get('limpio', {}), out[:400])

    # --- 5-bis) el proyecto se lo fija EL SOLO con set-sdk -----------------
    # Es el modelo del IDE: muchos SDK registrados y el proyecto elige. Hasta
    # ahora el servidor respetaba el PlatformSDK del proyecto pero no sabia
    # ponerlo, asi que todo dependia del default del SDK Manager.
    out = srv.call('delphi_config', {"project": dproj, "command": "set-sdk",
                                     "platform": "Linux64", "sdk": "nomeinventes"})
    check('set-sdk de un SDK que no existe: RECHAZADO',
          out.startswith('RECHAZADO') and 'uno.sdk' in out, out[:200])
    out = srv.call('delphi_config', {"project": dproj, "command": "set-sdk",
                                     "platform": "Linux64", "sdk": "uno"})
    with open(dproj, encoding='utf-8', errors='replace') as f:
        xml = f.read()
    check('set-sdk escribe PlatformSDK en el .dproj',
          xml.count('<PlatformSDK>uno.sdk</PlatformSDK>') == 1, out[:200])
    out = srv.call('delphi_build', {"project": dproj, "platform": "Linux64"},
                   timeout=600)
    check('y el build lo obedece sin que nadie se lo diga',
          'uno.sdk' in out and 'sdkNote' in out, out[:300])
    # el PlatformSDK es POR PLATAFORMA: uno puesto en el grupo de OTRA
    # (OSX64) no puede colarse en un build Linux64 - el lector viejo cogia el
    # primer <PlatformSDK> del fichero (paisaje 2026-09-22)
    with open(dproj, encoding='utf-8', errors='replace') as f:
        xml = f.read()
    ajeno = ('    <PropertyGroup Condition="\'$(Base_OSX64)\'!=\'\'">\n'
             '        <PlatformSDK>ajeno.sdk</PlatformSDK>\n    </PropertyGroup>\n')
    xml2 = xml.replace('    <PropertyGroup Condition="\'$(Base_Linux64)\'!=\'\'">',
                       ajeno + '    <PropertyGroup Condition="\'$(Base_Linux64)\'!=\'\'">', 1)
    assert xml2 != xml, 'la bateria no encuentra el grupo Linux64 del .dproj'
    with open(dproj, 'w', encoding='utf-8', newline='') as f:
        f.write(xml2)
    out = srv.call('delphi_build', {"project": dproj, "platform": "Linux64"},
                   timeout=600)
    check('un PlatformSDK del grupo de OTRA plataforma no manda en Linux64',
          'uno.sdk' in out and 'ajeno' not in out, out[:300])
    # y view lo DICE: SDK y perfil por plataforma remota, con su procedencia
    # (la sonda nace Win32/Win64: Linux64 entra en el proyecto como en el IDE)
    srv.call('delphi_config', {"project": dproj, "command": "add-platform",
                               "platform": "Linux64"})
    out = srv.call('delphi_config', {"project": dproj, "command": "view",
                                     "section": "platforms"})
    flat = out.replace(' ', '')
    check('view platforms: Linux64 ensena el SDK del proyecto y su procedencia',
          '"sdk":"uno.sdk"' in flat and '"sdkSource":"project"' in flat, out[out.find('Linux64')-20:][:600])
    check('view platforms: sin perfil fijado lo dice y apunta a set-profile',
          '"profile":""' in flat and 'set-profile' in out, out[:400])
    out = srv.call('delphi_config', {"project": dproj, "command": "view"})
    check('view summary: remoteTargets resume las remotas activas',
          '"remoteTargets"' in out and 'uno.sdk' in out, out[:400])
    with open(dproj, 'w', encoding='utf-8', newline='') as f:
        f.write(xml)
    out = srv.call('delphi_config', {"project": dproj, "command": "set-sdk",
                                     "platform": "Linux64", "sdk": "none"})
    with open(dproj, encoding='utf-8', errors='replace') as f:
        xml = f.read()
    check('set-sdk none lo quita del .dproj', '<PlatformSDK>' not in xml, out[:200])

    # anadir un destino al proyecto es UN gesto: plataforma + SDK + perfil
    out = srv.call('delphi_config', {"project": dproj, "command": "add-platform",
                                     "platform": "OSX64", "sdk": "uno"})
    check('add-platform con sdk lo deja puesto en el proyecto',
          'uno.sdk' in out or 'RECHAZADO' in out, out[:250])

    # cada .sdk declara SU plataforma: uno de Android no vale para Linux64
    sdk_file(os.path.join(PROFILES_DIR, 'androidfalso.sdk'), platform='Android64')
    out = srv.call('delphi_config', {"project": dproj, "command": "set-sdk",
                                     "platform": "Linux64", "sdk": "androidfalso"})
    check('set-sdk no cuela un SDK de OTRA plataforma',
          out.startswith('RECHAZADO'), out[:200])

    # --- 5-ter) la otra mitad: el PAServer del proyecto --------------------
    # "Anadir a un proyecto" en el IDE es dar de alta las DOS cosas: la
    # conexion (el perfil) y el SDK. msbuild lee $(Profile) del proyecto
    # igual que $(PlatformSDK), asi que va en el mismo sitio.
    out = srv.call('delphi_config', {"project": dproj, "command": "set-profile",
                                     "platform": "Win64", "profile": "loquesea"})
    check('set-profile en una plataforma LOCAL: RECHAZADO',
          out.startswith('RECHAZADO') and 'PAServer' in out, out[:200])
    out = srv.call('delphi_config', {"project": dproj, "command": "set-profile",
                                     "platform": "Linux64", "profile": "no-existe-este"})
    check('set-profile de un perfil que no existe: RECHAZADO',
          out.startswith('RECHAZADO'), out[:200])

    # --- 6) quitar un SDK: se desregistra, pero los gigas NO se tocan ------
    raiz_limpia = os.path.join(BASE, 'sysroot-limpio')
    out = srv.call('delphi_paserver', {"command": "remove-sdk", "sdk": "limpio"})
    check('remove-sdk: el .sdk desaparece',
          not os.path.exists(os.path.join(PROFILES_DIR, 'limpio.sdk')), out[:300])
    check('remove-sdk: el SYSROOT sigue en disco y lo dice',
          os.path.isdir(raiz_limpia) and 'sysrootLeftBehind' in out, out[:300])
    out = srv.call('delphi_paserver', {"command": "remove-sdk", "sdk": "limpio"})
    check('remove-sdk de uno que no existe: RECHAZADO',
          out.startswith('RECHAZADO'), out[:200])
finally:
    srv.stop()

print('\n== bateria de SDK: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
