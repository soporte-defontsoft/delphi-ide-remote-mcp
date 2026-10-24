# -*- coding: utf-8 -*-
"""get-sdk no pisa lo que no trajo, y lo del IDE que toca lo copia antes (V10, 1.23).

Tres agujeros, medidos leyendo Mcp.Tools.PAServer (24-oct-2026):

  1. La guarda de distro solo actuaba con la ficha del sysroot (mcp-sdk.json)
     y las DOS distros conocidas: con una carpeta sin ficha (del IDE, de antes
     o los restos de un get-sdk que fallo), un /etc/os-release que no se lee o
     una ficha con la distro vacia, paclient bajaba encima.
  2. Un SDK que no trajo get-sdk con el nombre pedido (su .sdk, su asiento en
     el SDK Manager o su carpeta) se pisaba: el .sdk con copia, el asiento sin
     ella, y el sysroot mezclado. reseat-sdk reescribia el asiento de
     cualquier SDK Linux64, tambien los del IDE.
  3. El registro del IDE se tocaba sin copia previa: el asiento de un SDK
     (get-sdk, reseat-sdk, remove-sdk) y el de un perfil (remove-profile).

Sin PAServer: paclient es tests/paclient_stub.py (DELPHI_MCP_PACLIENT), con un
destino de mentira en su scratch (un /etc/os-release de "mcpvdiez 1", un arbol
de gcc y un libc.so.6). APPDATA de prueba (mc.appdata_perfil). Lo UNICO de
fuera que se toca son nombres que no existen: las carpetas mcpvdiez*.sdk de la
carpeta de SDKs del IDE y los asientos PlatformSDKs\\mcpvdiez*.sdk y
RemoteProfiles\\mcpvdiez* (como test_paserver con su perfil), recogidos al
empezar y al salir. Nunca active=yes: el Default_Linux64 es del operador.

  G1  control: un get-sdk nuevo deja carpeta con la ficha de su distro, .sdk y asiento
  G2  un asiento que dice otra cosa se exporta ANTES (previousIdeSeatCopy: el .reg de reg.exe)
  G3  control: repetido sin cambios, el asiento ni se copia
  G4  una carpeta sin ficha con algo dentro: NEGADO (PAS-064), nada bajado ni escrito
  G5  un .sdk que no trajo get-sdk con ese nombre: NEGADO, el .sdk byte a byte
  G6  un asiento del SDK Manager con ese nombre: NEGADO, el asiento igual
  G7  una ficha sin distro: NEGADO
  G8  control: una ficha de OTRA distro: PAS-011, la guarda de siempre
  G9  un /etc/os-release que no se lee: NEGADO (PAS-065) sin crear nada
  G10 un pull que falla deja la ficha (reclamada ANTES de bajar) y el reintento entra
  G11 reseat-sdk de un SDK sin ficha: no se asienta (PAS-066); el suyo si
  G12 remove-sdk: el asiento se exporta antes (removedSeatCopy)
  G13 remove-profile: el asiento del perfil se exporta antes (PAS-067)

Mutante: produccion (el build sin el arreglo): G2, G4-G7, G9, G10a, G11a, G12
y G13 rojos.

Uso:  python tests/test_get_sdk_1230.py [exe]
"""
import atexit, json, os, re, shutil, winreg
import mcp_cliente as mc
from mcp_cliente import check

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = mc.carpeta('getsdk1230')
JAIL = os.path.join(BASE, 'jaula')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
PERFIL = 'mcpvdiez'
PREFIJO = 'mcpvdiez'    # todo lo que esta bateria crea fuera empieza asi
DISTRO = 'mcpvdiez1'    # ID=mcpvdiez + VERSION_ID=1, como lo compone get-sdk
AD, HOST = mc.appdata_perfil(BASE, PERFIL, '127.0.0.1', 'Linux64')

# el destino de mentira: lo que el stub sirve con --get
DESTINO = os.path.join(BASE, 'destino')


def planta(rel, datos):
    p = os.path.join(DESTINO, *rel.split('/'))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'wb') as f:
        f.write(datos)


planta('etc/os-release', b'NAME="Mcp V10"\nID=mcpvdiez\nVERSION_ID="1"\n')
planta('usr/lib/gcc/x86_64-linux-gnu/13/crtbegin.o', b'crtbegin de mentira')
planta('usr/lib/x86_64-linux-gnu/libc.so.6', b'GNU C Library release version 2.39 de mentira')
LOG = os.path.join(BASE, 'paclient.log')
STUB = os.path.join(BASE, 'paclient.cmd')
with open(STUB, 'w') as _f:
    _f.write('@echo off\r\npython "%s" %%*\r\n' % os.path.join(HERE, 'paclient_stub.py'))

srv = mc.Stdio(EXE, mc.entorno({
    'DELPHI_MCP_ROOTS': JAIL, 'APPDATA': AD, 'DELPHI_MCP_REMOTE_HOSTS': HOST,
    'DELPHI_MCP_PACLIENT': STUB, 'MCP_STUB_SCRATCH': DESTINO, 'MCP_STUB_LOG': LOG}),
    nombre='getsdk1230', t=300)

m = re.search(r'"version"\s*:\s*"(\d+\.\d+)"', srv.call('delphi_installs', {}))
VER = m.group(1) if m else ''
PROFILES_DIR = os.path.join(AD, 'Embarcadero', 'BDS', VER)
CLAVE = r'Software\Embarcadero\BDS\%s' % VER
COPIAS = mc.cache_servidor(os.path.join(mc.IDE_COPIAS, VER))
# la carpeta de SDKs del IDE: la de los sysroots que ya tiene (los .sdk de
# verdad, copiados al APPDATA de prueba), como la pregunta el servidor
_sdks = mc.como_json(srv.call('delphi_paserver', {'command': 'profiles'})).get('sdks', [])
_raices = [mc.real(s.get('sysroot', '')) for s in _sdks]
_raices = [r for r in _raices if r.lower().endswith('.sdk')]
SDKS = os.path.dirname(_raices[0]) if _raices else ''


def recoge():
    """SOLO lo de nombre mcpvdiez*: carpetas de SDK, asientos y copias."""
    if SDKS and os.path.isdir(SDKS):
        for n in os.listdir(SDKS):
            if n.lower().startswith(PREFIJO) and n.lower().endswith('.sdk'):
                shutil.rmtree(os.path.join(SDKS, n), ignore_errors=True)
    for sub in ('PlatformSDKs', 'RemoteProfiles'):
        nombres = []
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, CLAVE + '\\' + sub) as k:
                i = 0
                while True:
                    try:
                        nombres.append(winreg.EnumKey(k, i))
                    except OSError:
                        break
                    i += 1
        except OSError:
            pass
        for n in nombres:
            if n.lower().startswith(PREFIJO):
                try:
                    winreg.DeleteKey(winreg.HKEY_CURRENT_USER, CLAVE + '\\' + sub + '\\' + n)
                except OSError:
                    pass
    # la cache de las baterias dura entre corridas
    if os.path.isdir(COPIAS):
        for f in os.listdir(COPIAS):
            if PREFIJO in f.lower():
                os.remove(os.path.join(COPIAS, f))


def asiento(sub):
    """Los valores de una clave del IDE (CLAVE\\sub), o None si no esta."""
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, CLAVE + '\\' + sub) as k:
            d, i = {}, 0
            while True:
                try:
                    n, v, _t = winreg.EnumValue(k, i)
                except OSError:
                    return d
                d[n] = v
                i += 1
    except OSError:
        return None


def pon_asiento(sub, valores):
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, CLAVE + '\\' + sub) as k:
        for n, v in valores.items():
            winreg.SetValueEx(k, n, 0, winreg.REG_DWORD if isinstance(v, int) else winreg.REG_SZ, v)


def seat(nombre):
    return asiento(r'PlatformSDKs\%s.sdk' % nombre)


def ficha(nombre):
    p = os.path.join(SDKS, nombre + '.sdk', 'mcp-sdk.json')
    return json.load(open(p, encoding='utf-8-sig')) if os.path.isfile(p) else None


def pon_ficha(nombre, datos):
    raiz = os.path.join(SDKS, nombre + '.sdk')
    os.makedirs(raiz, exist_ok=True)
    with open(os.path.join(raiz, 'mcp-sdk.json'), 'w', encoding='utf-8') as f:
        json.dump(datos, f)
    return raiz


def ficheros(carpeta):
    """Lo que hay debajo (ruta relativa -> bytes): para ver que nada se toco."""
    r = {}
    for raiz, _d, fs in os.walk(carpeta):
        for f in fs:
            p = os.path.join(raiz, f)
            r[os.path.relpath(p, carpeta)] = open(p, 'rb').read()
    return r


def marca():
    return len(open(LOG, encoding='utf-8').read().splitlines()) if os.path.exists(LOG) else 0


def pidio_bajar(desde):
    """Si paclient recibio un pull de sysroot (--get=/usr/...) desde la marca."""
    lineas = open(LOG, encoding='utf-8').read().splitlines() if os.path.exists(LOG) else []
    return any('--get=/usr/' in l for l in lineas[desde:])


def get_sdk(**kw):
    return srv.call('delphi_paserver', dict(command='get-sdk', profile=PERFIL, **kw), t=300)


def texto_reg(ruta):
    """El .reg de reg.exe (UTF-16 con BOM) de una copia que da la respuesta: la
    casa sale enmascarada (<server-cache>, la cache de las baterias aqui)."""
    ruta = ruta.replace('<server-cache>', mc.cache_servidor().rstrip('\\/'))
    try:
        datos = open(mc.real(ruta), 'rb').read()
    except OSError:
        return ''
    return datos[2:].decode('utf-16-le', 'replace') if datos[:2] == b'\xff\xfe' else ''


def mismo(a, b):
    return os.path.normcase(os.path.abspath(a)) == os.path.normcase(os.path.abspath(b))


def sdk_ajeno(nombre, sysroot):
    with open(os.path.join(PROFILES_DIR, nombre + '.sdk'), 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n'
                '  <PropertyGroup>\n'
                '    <Profile_platform>Linux64</Profile_platform>\n'
                '    <Profile_sysroot>%s</Profile_sysroot>\n'
                '    <Profile_displayname>el del IDE</Profile_displayname>\n'
                '  </PropertyGroup>\n'
                '</Project>\n' % sysroot)
    return os.path.join(PROFILES_DIR, nombre + '.sdk')


try:
    if not (VER and SDKS):
        check('la version del IDE (%r) y su carpeta de SDKs (%r) se leen' % (VER, SDKS), False)
        raise SystemExit
    recoge()
    atexit.register(recoge)

    # --- G1 control ----------------------------------------------------------
    m0 = marca()
    out = get_sdk()
    j = mc.como_json(out)
    f1 = ficha(DISTRO)
    check('G1 control: get-sdk nuevo: %s con la ficha de su distro, su .sdk y su asiento' % DISTRO,
          j.get('sdk') == DISTRO + '.sdk' and mismo(mc.real(j.get('sysroot', '')), os.path.join(SDKS, DISTRO + '.sdk'))
          and bool(f1) and f1.get('distro') == DISTRO
          and os.path.isfile(os.path.join(PROFILES_DIR, DISTRO + '.sdk'))
          and seat(DISTRO) is not None and pidio_bajar(m0), out[:500])

    # --- G2 el asiento que dice otra cosa se exporta antes --------------------
    pon_asiento(r'PlatformSDKs\%s.sdk' % DISTRO, {'SDKDisplayName': 'tocado a mano por G2'})
    out = get_sdk()
    j = mc.como_json(out)
    reg = texto_reg(j.get('previousIdeSeatCopy', ''))
    check('G2 un asiento que dice otra cosa se exporta ANTES de pisarlo (previousIdeSeatCopy, el .reg de reg.exe con lo de antes)',
          'Windows Registry Editor' in reg and 'tocado a mano por G2' in reg
          and (seat(DISTRO) or {}).get('SDKDisplayName') != 'tocado a mano por G2', out[:500])

    # --- G3 control: sin cambios, ni se copia ---------------------------------
    out = get_sdk()
    check('G3 control: repetido sin cambios, el asiento ni se reescribe ni se copia',
          mc.como_json(out).get('sdk') == DISTRO + '.sdk' and 'previousIdeSeatCopy' not in out, out[:400])

    # --- G4 carpeta sin ficha con algo dentro ---------------------------------
    b = PREFIJO + 'b'
    raizb = os.path.join(SDKS, b + '.sdk')
    os.makedirs(os.path.join(raizb, 'usr', 'lib64'))
    with open(os.path.join(raizb, 'usr', 'lib64', 'libc.so.6'), 'wb') as f:
        f.write(b'la de otra distro')
    antes = ficheros(raizb)
    m0 = marca()
    out = get_sdk(sdk=b)
    check('G4 una carpeta sin ficha con algo dentro: NEGADO (PAS-064), sin bajar nada ni escribir .sdk ni asiento',
          mc.rechazado(out) and mc.es(out, 'SR_PASERVER_SDK_AJENO_FMT') and ficheros(raizb) == antes
          and not pidio_bajar(m0) and not os.path.exists(os.path.join(PROFILES_DIR, b + '.sdk'))
          and seat(b) is None, out[:400])

    # --- G5 un .sdk que no trajo get-sdk -------------------------------------
    c = PREFIJO + 'c'
    fichero_c = sdk_ajeno(c, os.path.join(BASE, 'sysroot-del-ide'))
    antes = open(fichero_c, 'rb').read()
    m0 = marca()
    out = get_sdk(sdk=c)
    check('G5 un .sdk que no trajo get-sdk con ese nombre: NEGADO, el .sdk byte a byte, sin carpeta ni asiento',
          mc.rechazado(out) and mc.es(out, 'SR_PASERVER_SDK_AJENO_FMT') and open(fichero_c, 'rb').read() == antes
          and not os.path.exists(os.path.join(SDKS, c + '.sdk')) and seat(c) is None and not pidio_bajar(m0),
          out[:400])

    # --- G6 un asiento del SDK Manager ---------------------------------------
    d = PREFIJO + 'd'
    pon_asiento(r'PlatformSDKs\%s.sdk' % d, {'SDKName': d + '.sdk', 'SDKDisplayName': 'el del IDE',
                                             'PlatformName': 'Linux64', 'PathCount': 0})
    antes = seat(d)
    m0 = marca()
    out = get_sdk(sdk=d)
    check('G6 un asiento del SDK Manager que no trajo get-sdk: NEGADO y el asiento igual',
          mc.rechazado(out) and mc.es(out, 'SR_PASERVER_SDK_AJENO_FMT') and seat(d) == antes
          and not os.path.exists(os.path.join(SDKS, d + '.sdk')) and not pidio_bajar(m0), out[:400])

    # --- G7 una ficha sin distro ---------------------------------------------
    e = PREFIJO + 'e'
    raize = pon_ficha(e, {'sdk': e, 'distro': '', 'profile': PERFIL})
    antes = ficheros(raize)
    m0 = marca()
    out = get_sdk(sdk=e)
    check('G7 una ficha sin distro: NEGADO (nada dice que sea de %s), sin bajar nada' % DISTRO,
          mc.rechazado(out) and mc.es(out, 'SR_PASERVER_SDK_AJENO_FMT') and ficheros(raize) == antes
          and not pidio_bajar(m0), out[:400])

    # --- G8 control: una ficha de otra distro ---------------------------------
    g8 = PREFIJO + 'f'
    pon_ficha(g8, {'sdk': g8, 'distro': 'otradistro9', 'profile': 'otro'})
    m0 = marca()
    out = get_sdk(sdk=g8)
    check('G8 control: una ficha de OTRA distro: PAS-011, la guarda de siempre, sin bajar nada',
          mc.rechazado(out) and mc.es(out, 'SR_PASERVER_SDK_OTRA_FMT') and not pidio_bajar(m0), out[:400])

    # --- G9 un /etc/os-release que no se lee ----------------------------------
    osr = os.path.join(DESTINO, 'etc', 'os-release')
    os.rename(osr, osr + '.fuera')
    try:
        m0 = marca()
        out = get_sdk()
    finally:
        os.rename(osr + '.fuera', osr)
    check('G9 un /etc/os-release que no se lee: NEGADO (PAS-065), sin crear carpeta ni bajar nada',
          mc.rechazado(out) and mc.es(out, 'SR_PASERVER_SDK_SIN_DISTRO_FMT')
          and not os.path.exists(os.path.join(SDKS, PERFIL + '.sdk')) and not pidio_bajar(m0), out[:400])

    # --- G10 un pull que falla deja la ficha; el reintento entra --------------
    g = PREFIJO + 'g'
    gcc = os.path.join(DESTINO, 'usr', 'lib', 'gcc')
    os.rename(gcc, gcc + '.fuera')
    try:
        out = get_sdk(sdk=g)
    finally:
        os.rename(gcc + '.fuera', gcc)
    fg = ficha(g)
    check('G10a un pull que falla (sin gcc) deja la ficha de su distro, puesta ANTES de bajar, y lo dice (PAS-062)',
          mc.es(out, 'SR_PASERVER_SDK_NOGROUP_FMT') and mc.es(out, 'SN_PASERVER_SDK_RESTOS_FMT')
          and bool(fg) and fg.get('distro') == DISTRO, out[:400])
    out = get_sdk(sdk=g)
    check('G10b control: el reintento entra en su carpeta (es suya y de su distro)',
          not mc.fallo(out) and mc.como_json(out).get('sdk') == g + '.sdk' and 'error' not in mc.como_json(out),
          out[:400])

    # --- G11 reseat-sdk solo los que trajo get-sdk ----------------------------
    h = PREFIJO + 'h'
    raizh = os.path.join(SDKS, h + '.sdk')
    os.makedirs(os.path.join(raizh, 'usr', 'lib64'))
    sdk_ajeno(h, raizh)
    out = srv.call('delphi_paserver', {'command': 'reseat-sdk', 'sdk': h})
    check('G11a reseat-sdk de un SDK sin ficha (del IDE): no se asienta y lo dice (PAS-066)',
          seat(h) is None and mc.es(out, 'SN_PASERVER_SDK_RESEAT_AJENO_FMT')
          and h not in mc.como_json(out).get('seated', [h]), out[:400])
    out = srv.call('delphi_paserver', {'command': 'reseat-sdk', 'sdk': DISTRO})
    check('G11b control: reseat-sdk del que trajo get-sdk: se asienta',
          DISTRO in mc.como_json(out).get('seated', []) and seat(DISTRO) is not None, out[:400])

    # --- G12 remove-sdk exporta el asiento antes ------------------------------
    out = srv.call('delphi_paserver', {'command': 'remove-sdk', 'sdk': DISTRO})
    j = mc.como_json(out)
    reg = texto_reg(j.get('removedSeatCopy', ''))
    check('G12 remove-sdk: el asiento se exporta ANTES de borrarlo (removedSeatCopy), y se borra',
          'Windows Registry Editor' in reg and DISTRO in reg and seat(DISTRO) is None and 'removedCopy' in j,
          out[:400])

    # --- G13 remove-profile exporta el asiento del perfil antes ---------------
    pon_asiento(r'RemoteProfiles\%s' % PERFIL, {'Platform': 'Linux64', 'HostName': '127.0.0.1',
                                               'PortNumber': 64211, 'Password': '00', 'LocalRoot': '',
                                               'PathCount': 0})
    out = srv.call('delphi_paserver', {'command': 'remove-profile', 'profile': PERFIL})
    copias = [f for f in (os.listdir(COPIAS) if os.path.isdir(COPIAS) else [])
              if f.endswith('-RemoteProfiles-%s.reg' % PERFIL)]
    reg = texto_reg(os.path.join(COPIAS, copias[0])) if copias else ''
    check('G13 remove-profile: el asiento del perfil se exporta ANTES (PAS-067, con su copia) y se borra',
          mc.es(out, 'SN_PAS_COPIA_DEL_ASIENTO_FMT') and len(copias) == 1 and '127.0.0.1' in reg
          and asiento(r'RemoteProfiles\%s' % PERFIL) is None, (copias, out[:400]))
finally:
    try:
        srv.mata()
    except Exception:
        pass
    if VER and SDKS:
        recoge()
        quedan = [n for n in os.listdir(SDKS) if n.lower().startswith(PREFIJO)]
        check('recogido: ni carpetas mcpvdiez* en la de SDKs ni asientos', not quedan
              and not any(seat(PREFIJO + x) for x in ('1', 'b', 'c', 'd', 'e', 'f', 'g', 'h')), quedan)
    try:
        mc.fin('bateria de get-sdk (V10)')
    finally:
        mc.borra(BASE)
