# -*- coding: utf-8 -*-
"""Un servidor, un Delphi (5-oct-2026).

David: la version de Delphi es del SERVIDOR y sale de su settings.ini y de
nada mas - [Server] DelphiVersion, al lado de Port -; sin la clave, la mas
moderna con DelphiLSP, y el servidor la ESCRIBE en su ini al arrancar: desde
ahi manda la clave. Sin su Delphi NO arranca ("es un servidor MCP para
Delphi"). Nada de esta bateria se escribe a mano: las instalaciones, sus
nombres y su build los dice el propio servidor (delphi_installs).

  U1  sin [Server] DelphiVersion: arranca con la mas moderna, ESCRIBE la clave
      en su settings.ini (una linea, dentro de [Server]) y lo dice en el log;
      el resto del fichero queda byte a byte (CRLF y los acentos que mas
      facil se rompen: Í Ð Ý caen en los huecos de CP1252). El log lista CADA
      instalacion, linea entera, con la clave que el operador copiaria, y
      marca la del servidor
  U2  [Workspace.x] DelphiVersion= ya no se lee y el log lo avisa; de una
      seccion que se ignora entera (sin token) no se dice. Y quien lo tenia
      queria una version: la mas nueva NO se fija en [Server] por el
  U3  segundo arranque en esa misma carpeta: la clave ya esta y manda ella
      ("pinned by"), sin volver a escribir: el ini no se toca
  U4  [Server] DelphiVersion=37 (sin decimal): activa y pedida la 37.0; el
      ini no se toca
  U5  [Server] DelphiVersion=<una que NO esta>: el servidor NO arranca - no
      escucha y sale con codigo 1 - y lo que escribe dice por que y que
      claves sirven aqui; el ini no se toca
  U6  DELPHI_MCP_DELPHI_VERSION ya no existe (David: "de variables de
      Windows, nada"): puesta en el entorno, no cambia nada
  U7  sin settings.ini (el modo local de lanzamiento, por stdio): arranca con
      la mas moderna y NO crea un ini
  U8  el texto del update que apunto el instalador (InstalledUpdates, valor Main
      Product Update: "... Update 1" es la 13.1, "... Update 2" la 13.2, las
      dos 37.0) es solo una PISTA para el operador: sale tal cual en
      delphi_installs (installedUpdate) y en el log de arranque, y NO en
      delphi_workspace; se compara con el registro mismo
  U9  [Server] DelphiUpdate=13.2 lo DECLARA el operador (David, 5-oct-2026:
      hoy no decide nada, es prevision): sale en delphi_workspace
      (delphiUpdate), delphi_installs (requestedUpdate) y el log. Se declara
      a proposito uno que NO es el de esta maquina: se declara, no se deduce
  U10 DelphiUpdate=13,2 (otra forma que numero.numero): el log lo avisa y se
      ignora, como si no estuviera; sin la clave (U1), ningun update
  U11 un settings.ini con el BOM de UTF-8 justo delante de [Server]: Windows
      no ve esa cabecera y la seccion se pierde entera (Port, BindIP,
      DelphiVersion): NO arranca y dice por que; con un comentario delante
      el BOM no molesta, arranca y la clave entra en SU [Server]; a MITAD
      del fichero (un trozo pegado) tampoco arranca, y dice la linea. En
      UTF-16 big endian (FE FF) esa API no ve ninguna seccion: NO arranca
      (U11d); en UTF-16 little endian con su BOM si, y la clave se escribe
      en LE (U11e, el control). Uno que esta y NO se puede leer (abierto en
      exclusiva por otro proceso): arranca cerrado - nada de el en vigor -
      y lo dicen el log de arranque y delphi_workspace, sin tocarlo (U11f)
  U12 [Server] dos veces: Windows lee el primero y la version del operador
      puede estar en el otro - arranca, NO escribe la clave y lo dice
  U13 [Server] DelphiVersion=37,0 (la coma decimal de un teclado espanol) y
      37.00 (ceros de mas): la misma version, arranca y no toca el ini
      (1.15.0; antes no arrancaba: "si escribes mal, te aguantas?")

Lo que NO mide, y por que: que cada tool use solo el Delphi del servidor y
nunca el de otra instalacion necesita una maquina con DOS Delphi (aqui hay
uno). Lo sostienen la revision de R1 (5-oct-2026, todos los sitios
recorridos) y que todos pasan por un solo lector, DiscoverRadStudio.

Usage:  python tests/test_un_delphi.py [path-to-DelphiLspMcp.exe]
"""
import ctypes, json, os, re, subprocess, winreg
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('un_delphi')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
TOKEN = 'un-delphi'
CAT = mc.catalogo()
procs = []   # (proceso, fichero de salida): el finally los para todos


def ini_bytes(server, extra=()):
    """Un settings.ini en CRLF con una linea de comentario de acentos que se
    rompen facil, [Server] con esas lineas y el workspace de la bateria."""
    lineas = (['; prueba de bytes: Gestoría, Ñandú, Í Ð Ý, 10 €', '[Server]'] + list(server)
              + ['', '[Workspace.Op]', 'Token=%s' % TOKEN, 'Roots=%s' % JAIL] + list(extra) + [''])
    return '\r\n'.join(lineas).encode('utf-8')


def carpeta_servidor(nombre, ini=None):
    d = os.path.join(BASE, nombre)
    os.makedirs(d)
    exe = mc.copia_exe(d)
    if ini is not None:
        with open(os.path.join(d, 'settings.ini'), 'wb') as f:
            f.write(ini)
    return d, exe


def lanza(exe, nombre, extra=None):
    """--http con su salida (el log de arranque) a un fichero. El proceso
    queda apuntado ANTES de esperar nada: si algo falla a medias, el finally
    lo para igual. cli es None si no llego a escuchar."""
    ruta = os.path.join(BASE, nombre + '.txt')
    salida = open(ruta, 'wb')
    env = mc.entorno(dict({'DELPHI_MCP_BIND_IP': '127.0.0.1'}, **(extra or {})))
    puerto = mc.puerto_libre()
    try:
        proc = subprocess.Popen([exe, '--http', str(puerto)], env=env,
                                stdout=salida, stderr=subprocess.STDOUT)
    except Exception:
        salida.close()  # sin proceso no entra en procs: se cierra aqui
        raise
    procs.append((proc, salida))
    cli = None
    if mc.espera_puerto(puerto, proc, 30):
        cli = mc.Http(puerto, TOKEN, t=120, respaldo_json=True)
        cli.session(nombre)
    return proc, ruta, cli


def para(proc):
    for i, (p, s) in enumerate(procs):
        if p is proc:
            try:
                p.kill()
                p.wait(10)
            except Exception:
                pass
            s.close()
            del procs[i]
            return


def mensajes(ruta):
    """Las lineas del log de arranque sin la hora ni el nivel del logger."""
    with open(ruta, 'rb') as f:
        texto = f.read().decode('utf-8', 'replace')
    out = []
    for l in texto.splitlines():
        m = re.match(r'^\[[^\]]*\] \[[^\]]*\] ?(.*)$', l)
        out.append(m.group(1) if m else l)
    return out


def llama(cli, tool, args):
    t = mc.texto(cli.call_msg(tool, args, 120), True)
    return mc.como_json(t)


def ini_de(d):
    with open(os.path.join(d, 'settings.ini'), 'rb') as f:
        return f.read()


def linea_de(info, la_del_servidor):
    """La linea de arranque de UNA instalacion, compuesta con el catalogo y
    con lo que la instalacion dice de si misma."""
    quien = ('%s %s' % (info.get('name', ''), info.get('build', ''))).strip()
    if info.get('installedUpdate'):
        quien = '%s, %s' % (quien, info['installedUpdate']) if quien else info['installedUpdate']
    quien = quien or info['version']
    if not info.get('delphilsp'):
        return CAT['SL_DISC_SIN_DELPHILSP_FMT'] % (quien, info['version'])
    marca = CAT['SL_DISC_LA_DEL_SERVIDOR'] if info['version'] == la_del_servidor else ''
    return CAT['SL_DISC_INSTALACION_FMT'] % (quien, info['version'], marca)


def nombre_con_version(info):
    """'37.0 (RAD Studio 13, Delphi 13 and C++Builder 13 Update 1)': la version
    con lo que la instalacion dice de si misma."""
    dice = ', '.join(x for x in (info.get('name', ''), info.get('installedUpdate', '')) if x)
    return '%s (%s)' % (info['version'], dice) if dice else info['version']


def update_del_registro(version):
    """Lo que el instalador apunto como update de esa version, leido aqui del
    registro y no del servidor: el usuario primero y luego la maquina, como
    las busca el servidor. '' si no lo dice."""
    for raiz, vista in ((winreg.HKEY_CURRENT_USER, 0), (winreg.HKEY_CURRENT_USER, winreg.KEY_WOW64_32KEY),
                        (winreg.HKEY_LOCAL_MACHINE, 0), (winreg.HKEY_LOCAL_MACHINE, winreg.KEY_WOW64_32KEY)):
        try:
            with winreg.OpenKey(raiz, r'SOFTWARE\Embarcadero\BDS\%s\InstalledUpdates' % version,
                                0, winreg.KEY_READ | vista) as k:
                return str(winreg.QueryValueEx(k, 'Main Product Update')[0]).strip()
        except OSError:
            continue
    return ''


def en_server(ini, linea):
    """La linea esta DENTRO de [Server]: despues de su cabecera y antes de la
    siguiente seccion."""
    i = ini.find(b'[Server]')
    j = ini.find(linea)
    k = ini.find(b'\n[', i + 1)
    return i >= 0 and j > i and (k < 0 or j < k)


try:
    # ------------------------------------------------------------- U1 / U2
    INI1 = ini_bytes(['SessionTimeoutMinutes=720'],
                     ['', '[Workspace.SinToken]', 'Roots=%s' % JAIL,
                      'DelphiVersion=99.0'])
    d1, exe1 = carpeta_servidor('sin-clave', INI1)
    proc, ruta, c = lanza(exe1, 'sin-clave')
    if c is None:
        raise RuntimeError('el servidor sin clave no arranco: %s' % mensajes(ruta)[-5:])
    ins = llama(c, 'delphi_installs', {})
    TODAS = ins.get('installs') or []
    CON_LSP = [i for i in TODAS if i.get('delphilsp')]
    if not CON_LSP:
        raise RuntimeError('esta maquina no tiene ningun RAD Studio con DelphiLSP: %s' % json.dumps(ins)[:300])
    # la mas moderna, calculada AQUI por su numero (no el orden de la lista
    # del servidor: el check seria circular); con una sola instalacion no se
    # mide cual es la mas moderna, y el titulo lo dice (revisores, 6-oct-2026)
    NUEVA_I = max(CON_LSP, key=lambda i: tuple(int(x) for x in i['version'].split('.')))
    NUEVA = NUEVA_I['version']
    QUE = ('la mas moderna de %d con DelphiLSP' % len(CON_LSP) if len(CON_LSP) > 1 else
           'la UNICA con DelphiLSP (con una sola no se mide cual es la mas moderna)')
    NO_ESTA = next(v for v in ('23.0', '22.0', '99.0') if v not in [i['version'] for i in TODAS])
    ws = llama(c, 'delphi_workspace', {})
    log = mensajes(ruta)
    LINEA = ('DelphiVersion=%s\r\n' % NUEVA).encode('ascii')
    ESCRITO = ini_de(d1)
    check('U1 sin clave: activa %s (%s), y desde ya es la pedida' % (QUE, NUEVA),
          ws.get('activeDelphi') == NUEVA and ws.get('delphiVersionRequested') == NUEVA
          and ins.get('activeForLsp') == NUEVA, json.dumps(ws)[:300])
    check('U1 ...la ESCRIBE en su settings.ini, una linea dentro de [Server]',
          ESCRITO.count(LINEA) == 1 and en_server(ESCRITO, LINEA), ESCRITO[:300])
    check('U1 ...y el resto del fichero queda byte a byte (CRLF, Í Ð Ý, €)',
          ESCRITO.replace(LINEA, b'', 1) == INI1, ESCRITO[:300])
    check('U1 ...y el log dice que la escribio', CAT['SL_DISC_ESCRITA_FMT'] % NUEVA in log, log[-12:])
    # 5-oct-2026, en produccion: su propia escritura salia como "settings.ini
    # editado despues de arrancar, reinicia" (SYS-001). Lo escrito ESTA cargado
    check('U1 ...y su propia escritura no es un ini editado: delphi_workspace sin SYS-001',
          ws.get('server', {}).get('version') and 'settingsChangedNote' not in ws.get('server', {}),
          json.dumps(ws.get('server', {}))[:400])
    faltan = [linea_de(i, NUEVA) for i in TODAS if linea_de(i, NUEVA) not in log]
    check('U1 el log lista CADA instalacion, linea entera, con la clave que copiaria el operador',
          not faltan, json.dumps(faltan)[:400])
    usa = CAT['SL_DISC_USA_FMT'] % (nombre_con_version(NUEVA_I), CAT['SL_DISC_POR_CLAVE'])
    check('U1 ...y cual usa: "DelphiVersion=%s (nombre), pinned by [Server] DelphiVersion"' % NUEVA,
          usa in log, log[-12:])
    check('U2 ...pero de una seccion que se ignora entera (sin token) no se dice',
          CAT['SL_GUARD_SIN_TOKEN_IGNORADA_FMT'] % 'SinToken' in log
          and CAT['SL_GUARD_DELPHIVERSION_EN_WORKSPACE_FMT'] % 'SinToken' not in log, log[-12:])
    check('U10 sin [Server] DelphiUpdate: ningun update (ni en delphi_workspace ni en delphi_installs) '
          'y el log dice que no hay ninguno declarado',
          'delphiUpdate' not in ws and 'requestedUpdate' not in ins
          and CAT['SL_DISC_UPDATE_SIN_DECLARAR'] in log, json.dumps(ws)[:300])
    UPDATE = update_del_registro(NUEVA)
    check('U8 el registro de esta maquina dice el update de la %s (si no, U8 no mide nada): %r'
          % (NUEVA, UPDATE), UPDATE != '', UPDATE)
    check('U8 ...y es una pista: sale tal cual en delphi_installs (installedUpdate) y NO en delphi_workspace',
          UPDATE != '' and NUEVA_I.get('installedUpdate') == UPDATE and UPDATE not in json.dumps(ws),
          json.dumps(ws)[:300])
    check('U8 ...y en el log de arranque, en la linea de su instalacion y en la de "uses"',
          UPDATE != '' and (', %s  ->' % UPDATE) in linea_de(NUEVA_I, NUEVA)
          and linea_de(NUEVA_I, NUEVA) in log and UPDATE in usa and usa in log, log[-12:])
    para(proc)

    # ------------------------------------------------------------------ U2
    # [Workspace.Op] DelphiVersion= (se leia hasta la 1.13): ya no se lee y el
    # log lo avisa; y quien lo tenia queria una version, asi que la mas nueva
    # NO se fija en [Server] por el (David, 6-oct-2026)
    INI2 = ini_bytes([], ['DelphiVersion=99.0'])
    d2, exe2 = carpeta_servidor('ws-con-version', INI2)
    proc, ruta, c = lanza(exe2, 'ws-con-version')
    log = mensajes(ruta)
    check('U2 [Workspace] DelphiVersion= ya no se lee: el log lo avisa',
          c is not None and CAT['SL_GUARD_DELPHIVERSION_EN_WORKSPACE_FMT'] % 'Op' in log, log[-12:])
    check('U2 ...y la mas nueva NO se fija en [Server] (el ini no se toca), y el log dice por que',
          ini_de(d2) == INI2 and CAT['SF_GUARD_WS_DELPHIVERSION_NO_ESCRIBE_FMT'] % 'Op' in '\n'.join(log),
          '\n'.join(log)[-400:])
    para(proc)

    # ------------------------------------------------------------------ U2b
    # Las claves RETIRADAS no hacian nada y nadie lo decia (11.1 de la 1.18.0):
    # AllowDesktopControl (la tool local, 1.0.16) y AllowRun (delphi_run,
    # 1.1.1). El log lo avisa, como U2. (La seccion [Security] no: desde la
    # 0.98 "ni autentica, ni avisa, ni existe", test_round24 A4b)
    INI2B = ini_bytes([], ['AllowDesktopControl=1', 'AllowRun=1'])
    d2b, exe2b = carpeta_servidor('ws-retiradas', INI2B)
    proc, ruta, c = lanza(exe2b, 'ws-retiradas')
    log = mensajes(ruta)
    check('U2b las claves retiradas de un workspace las avisa el log, con la version que las quito',
          c is not None
          and CAT['SL_GUARD_CLAVE_RETIRADA_FMT'] % ('Workspace.Op', 'AllowDesktopControl', '1.0.16') in log
          and CAT['SL_GUARD_CLAVE_RETIRADA_FMT'] % ('Workspace.Op', 'AllowRun', '1.1.1') in log, log[-12:])
    para(proc)

    # ------------------------------------------------------------------ U3
    proc, ruta, c = lanza(exe1, 'sin-clave-2')
    ws = llama(c, 'delphi_workspace', {}) if c else {}
    log = mensajes(ruta)
    check('U3 segundo arranque: la clave ya escrita no se escribe otra vez, y el log dice la misma linea "pinned by"',
          ws.get('activeDelphi') == NUEVA and usa in log
          and CAT['SL_DISC_ESCRITA_FMT'] % NUEVA not in log, log[-12:])
    check('U3 ...el ini no se toca', ini_de(d1) == ESCRITO, ini_de(d1)[:300])
    para(proc)

    # ------------------------------------------------------------------ U4
    # U9 en el mismo arranque: un update DECLARADO que no es el de esta maquina
    DECLARADO = '13.2' if UPDATE.endswith('Update 1') else '13.1'
    INI4 = ini_bytes(['DelphiVersion=%s' % NUEVA.split('.')[0], 'DelphiUpdate=%s' % DECLARADO])
    d4, exe4 = carpeta_servidor('fijada', INI4)
    proc, ruta, c = lanza(exe4, 'fijada')
    ws = llama(c, 'delphi_workspace', {}) if c else {}
    ins = llama(c, 'delphi_installs', {}) if c else {}
    check('U4 [Server] DelphiVersion=%s: activa y pedida la %s' % (NUEVA.split('.')[0], NUEVA),
          ws.get('activeDelphi') == NUEVA and ws.get('delphiVersionRequested') == NUEVA
          and ins.get('activeForLsp') == NUEVA and ins.get('requested') == NUEVA, json.dumps(ws)[:300])
    check('U4 ...el ini no se toca', ini_de(d4) == INI4, ini_de(d4)[:300])
    log = mensajes(ruta)
    check('U9 [Server] DelphiUpdate=%s, declarado (el instalador de aqui dice %r): sale tal cual en '
          'delphi_workspace (delphiUpdate) y delphi_installs (requestedUpdate)' % (DECLARADO, UPDATE),
          ws.get('delphiUpdate') == DECLARADO and ins.get('requestedUpdate') == DECLARADO, json.dumps(ws)[:300])
    check('U9 ...y el log lo dice, sin el "ninguno declarado"',
          CAT['SL_DISC_UPDATE_DECLARADO_FMT'] % DECLARADO in log
          and CAT['SL_DISC_UPDATE_SIN_DECLARAR'] not in log, log[-12:])
    # el control de U1: tocado el ini con el servidor en marcha, SYS-001 SI sale
    sin_tocar = llama(c, 'delphi_workspace', {}) if c else {}
    with open(os.path.join(d4, 'settings.ini'), 'ab') as f:
        f.write(b'; tocado con el servidor en marcha\r\n')
    tocado = llama(c, 'delphi_workspace', {}) if c else {}
    check('U1 (control) el aviso SYS-001 funciona: sin tocar el ini no sale; tocado con el servidor en marcha, si',
          'settingsChangedNote' not in sin_tocar.get('server', {})
          and '[SYS-001]' in tocado.get('server', {}).get('settingsChangedNote', ''),
          json.dumps(tocado.get('server', {}))[:400])
    para(proc)

    # ------------------------------------------------------------------ U13
    for i, forma in enumerate((NUEVA.replace('.', ','), NUEVA + '0')):
        INI13 = ini_bytes(['DelphiVersion=%s' % forma])
        d13, exe13 = carpeta_servidor('forma%d' % i, INI13)
        proc, ruta, c = lanza(exe13, 'forma%d' % i)
        ws = llama(c, 'delphi_workspace', {}) if c else {}
        check('U13 [Server] DelphiVersion=%s: arranca y es la %s' % (forma, NUEVA),
              ws.get('activeDelphi') == NUEVA and ws.get('delphiVersionRequested') == NUEVA,
              (json.dumps(ws)[:300], mensajes(ruta)[-5:]))
        check('U13 ...el ini no se toca (%s)' % forma, ini_de(d13) == INI13, ini_de(d13)[:200])
        para(proc)

    # ------------------------------------------------------------------ U5
    INI5 = ini_bytes(['DelphiVersion=%s' % NO_ESTA])
    d5, exe5 = carpeta_servidor('no-esta', INI5)
    proc, ruta, c = lanza(exe5, 'no-esta')
    try:
        rc = proc.wait(30)
    except subprocess.TimeoutExpired:
        rc = None
    texto = '\n'.join(mensajes(ruta))
    usables = '; '.join(CAT['SF_DISC_USABLE_FMT'] % (nombre_con_version(i), i['version'])
                        for i in CON_LSP)
    check('U5 [Server] DelphiVersion=%s, que no esta: NO arranca - no escucha y sale con 1' % NO_ESTA,
          c is None and rc == 1, 'cli=%s rc=%s' % (c, rc))
    check('U5 ...y dice por que y que claves sirven aqui',
          CAT['SE_DISC_FIJADA_NO_ESTA_FMT'] % (NO_ESTA, usables) in texto, texto[-600:])
    check('U5 ...el ini no se toca', ini_de(d5) == INI5, ini_de(d5)[:300])
    para(proc)

    # ------------------------------------------------------------------ U11
    # El BOM de UTF-8 delante de [Server]: la API de los ini de Windows (la
    # nuestra y la que lee el Port) no ve esa cabecera y pierde la seccion
    # (medido el 6-oct-2026: Port y BindIP perdidos, el servidor en el 3000 y
    # en todas las interfaces). lanza() fija el puerto y la IP por fuera, asi
    # que ni sin el arreglo se abre nada a la red.
    BOM = b'\xef\xbb\xbf'
    INI11 = BOM + ('[Server]\r\n\r\n[Workspace.Op]\r\nToken=%s\r\nRoots=%s\r\n'
                   % (TOKEN, JAIL)).encode('utf-8')
    d11, exe11 = carpeta_servidor('bom', INI11)
    proc, ruta, c = lanza(exe11, 'bom')
    try:
        rc = proc.wait(30)
    except subprocess.TimeoutExpired:
        rc = None
    texto = '\n'.join(mensajes(ruta))
    partes = re.split(r'%[sd]', CAT['SE_GUARD_INI_BOM_FMT'])
    check('U11 settings.ini con BOM delante de [Server]: NO arranca - no escucha y sale con 1',
          c is None and rc == 1, 'cli=%s rc=%s' % (c, rc))
    check('U11 ...y dice por que, en que linea (la 1) y como arreglarlo',
          all(p in texto for p in partes) and ', on line 1, ' in texto, texto[-600:])
    check('U11 ...el ini no se toca', ini_de(d11) == INI11, ini_de(d11)[:200])
    para(proc)
    # con un comentario delante el BOM se queda en el comentario: arranca, y
    # la clave entra en SU [Server], no en uno nuevo al final
    INI11B = BOM + ini_bytes([])
    d11b, exe11b = carpeta_servidor('bom-comentario', INI11B)
    proc, ruta, c = lanza(exe11b, 'bom-comentario')
    escrito = ini_de(d11b)
    check('U11b con BOM y un comentario delante: arranca y escribe la clave en su [Server], el resto byte a byte',
          c is not None and escrito.replace(LINEA, b'', 1) == INI11B and en_server(escrito, LINEA),
          escrito[:300])
    para(proc)
    # y a MITAD del fichero (un trozo pegado de otro con BOM): la seccion que
    # sigue se pierde igual; no arranca y dice en que linea
    INI11C = ini_bytes([]).replace(b'[Workspace.Op]', BOM + b'[Workspace.Op]')
    d11c, exe11c = carpeta_servidor('bom-medio', INI11C)
    proc, ruta, c = lanza(exe11c, 'bom-medio')
    try:
        rc = proc.wait(30)
    except subprocess.TimeoutExpired:
        rc = None
    texto = '\n'.join(mensajes(ruta))
    linea = INI11C[:INI11C.find(BOM)].count(b'\n') + 1
    check('U11c un BOM a MITAD del fichero, delante de [Workspace.Op]: NO arranca y dice la linea (%d)' % linea,
          c is None and rc == 1 and (', on line %d, ' % linea) in texto,
          'cli=%s rc=%s %s' % (c, rc, texto[-300:]))
    check('U11c ...el ini no se toca', ini_de(d11c) == INI11C, ini_de(d11c)[:200])
    para(proc)
    # 9.2 de la 1.18.0: un settings.ini en UTF-16 BIG endian (FE FF): la API de
    # los ini de Windows no lo lee, no veia ninguna seccion y se arrancaba sin
    # ellas, callado. Ahora no arranca y dice por que
    INI11D = b'\xfe\xff' + ini_bytes([]).decode('utf-8').encode('utf-16-be')
    d11d, exe11d = carpeta_servidor('utf16be', INI11D)
    proc, ruta, c = lanza(exe11d, 'utf16be')
    try:
        rc = proc.wait(30)
    except subprocess.TimeoutExpired:
        rc = None
    texto = '\n'.join(mensajes(ruta))
    partes = re.split(r'%[sd]', CAT['SE_GUARD_INI_UTF16BE_FMT'])
    check('U11d settings.ini en UTF-16 big endian: NO arranca, y dice por que y como guardarlo',
          c is None and rc == 1 and all(p in texto for p in partes), 'cli=%s rc=%s %s' % (c, rc, texto[-300:]))
    check('U11d ...el ini no se toca', ini_de(d11d) == INI11D, ini_de(d11d)[:120])
    para(proc)
    # ...y su control (revisor del 9.2): en UTF-16 LITTLE endian con su BOM, lo
    # que el mensaje recomienda, arranca y la clave entra en su [Server], en
    # LE; el resto, byte a byte
    INI11E = b'\xff\xfe' + ini_bytes([]).decode('utf-8').encode('utf-16-le')
    d11e, exe11e = carpeta_servidor('utf16le', INI11E)
    proc, ruta, c = lanza(exe11e, 'utf16le')
    escrito = ini_de(d11e)
    linea_le = LINEA.decode('ascii').encode('utf-16-le')
    como_texto = escrito[2:].decode('utf-16-le', 'replace').encode('utf-8') if escrito[:2] == b'\xff\xfe' else b''
    check('U11e en UTF-16 little endian (FF FE): arranca y escribe la clave en LE dentro de su [Server], '
          'el resto byte a byte',
          c is not None and escrito.replace(linea_le, b'', 1) == INI11E and en_server(como_texto, LINEA),
          escrito[:200])
    para(proc)
    # U11f (David, 9-oct-2026: cerrado y nunca callado): un settings.ini que
    # esta y no se puede leer - abierto en EXCLUSIVA por otro proceso, sin
    # compartir ni la lectura - se leia callado con lo que diera la API de los
    # ini (nada). Ahora no se lee nada de el, y lo dicen el log de arranque y
    # delphi_workspace (en el modo local, el unico que entra sin sus tokens)
    INI11F = ini_bytes([])
    d11f, exe11f = carpeta_servidor('ini-bloqueado', INI11F)
    k32 = ctypes.WinDLL('kernel32', use_last_error=True)
    k32.CreateFileW.restype = ctypes.c_void_p
    h = k32.CreateFileW(os.path.join(d11f, 'settings.ini'), 0x80000000, 0, None, 3, 0, None)
    try:
        check('U11f preparado: el ini abierto en exclusiva (nadie mas lo lee)',
              h not in (None, ctypes.c_void_p(-1).value), h)
        proc, ruta, c = lanza(exe11f, 'ini-bloqueado')
        texto = '\n'.join(mensajes(ruta))
        partes = [p for p in re.split(r'%[sd]', CAT['SL_GUARD_INI_SIN_LEER_FMT']) if p.strip()]
        check('U11f un settings.ini que no se puede leer: arranca y el log de arranque lo dice',
              c is not None and all(p in texto for p in partes), 'cli=%s %s' % (c, texto[-500:]))
        para(proc)
        U11F_PAS = os.path.join(JAIL, 'U11f.pas')
        open(U11F_PAS, 'wb').write(b'unit U11f;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n')
        s = mc.Stdio(exe11f, env=mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='ini-bloqueado', cwd=d11f)
        try:
            srv11f = mc.como_json(s.call('delphi_workspace', {})).get('server', {})
            r11f_sin = s.call('delphi_read', {'path': U11F_PAS})
        finally:
            s.cierra()
        # sin token, el ini sin leer no cierra nada: el modo local es del
        # entorno de quien lanza (delphi_workspace contesta igual cerrado, asi
        # que se mide LEYENDO; revisor propio, 9-oct-2026)
        check('U11f ...un stdio SIN token sigue en su modo local: lee lo de DELPHI_MCP_ROOTS',
              not mc.rechazado(r11f_sin) and 'unit U11f;' in r11f_sin, r11f_sin[:300])
        check('U11f ...y delphi_workspace tambien (server.settingsUnreadable, con el motivo del sistema)',
              all(p in srv11f.get('settingsUnreadable', '') for p in partes), json.dumps(srv11f)[:400])
        check('U11f ...sin decir que el ini se toco despues de arrancar (no settingsChangedNote: no lo esta)',
              'settingsChangedNote' not in srv11f, json.dumps(srv11f)[:400])
        pne = [p for p in re.split(r'%[sd]', CAT.get('SL_DISC_NO_ESCRITA_FMT', '')) if len(p.strip()) > 10]
        check('U11f ...ni que le falta [Server] DelphiVersion (no se sabe: no se ha leido)',
              bool(pne) and not any(p in texto for p in pne), texto[-400:])
        # un cliente stdio lanzado con un token (o token o nada): el workspace
        # de ese token puede estar en el ini que no se lee - cerrado, y no el
        # modo local de confianza (revisor propio, 9-oct-2026)
        s = mc.Stdio(exe11f, env=mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_TOKEN': TOKEN}),
                     nombre='ini-bloqueado-token', cwd=d11f)
        try:
            r11f = s.call('delphi_read', {'path': U11F_PAS})
        finally:
            s.cierra()
        # (con SU motivo: otros cierres dan el mismo GUARD-030)
        check('U11f ...y un stdio lanzado con un token no entra en el modo local: no admite nada (GUARD-030)',
              mc.es(r11f, 'SR_LOCAL_CERRADO_FMT') and CAT['SF_CIERRE_INI_SIN_LEER'] in r11f, r11f[:300])
    finally:
        if h not in (None, ctypes.c_void_p(-1).value):
            k32.CloseHandle(ctypes.c_void_p(h))
    # (una GUARDA: con el ini en exclusiva tampoco se podria escribir)
    check('U11f ...y el ini no se toca (ni la clave de DelphiVersion)', ini_de(d11f) == INI11F, ini_de(d11f)[:120])
    # U11g: el ini abierto por OTRO con acceso de borrado y compartiendo todo
    # (lectura, escritura y borrado): la API de los ini lo lee, y la lectura de
    # sus bytes tambien - sin FILE_SHARE_DELETE fallaba con un error 32 y el
    # servidor arrancaba cerrado por un ini legible (revisor propio, 9-oct-2026)
    d11g, exe11g = carpeta_servidor('ini-compartido', ini_bytes([]))
    h = k32.CreateFileW(os.path.join(d11g, 'settings.ini'), 0x80000000 | 0x00010000, 7, None, 3, 0, None)
    try:
        check('U11g preparado: el ini abierto por otro con acceso de borrado, compartido del todo',
              h not in (None, ctypes.c_void_p(-1).value), h)
        proc, ruta, c = lanza(exe11g, 'ini-compartido')
        texto = '\n'.join(mensajes(ruta))
        partes11g = [p for p in re.split(r'%[sd]', CAT['SL_GUARD_INI_SIN_LEER_FMT']) if p.strip()]
        w11g = mc.como_json(c.call('delphi_workspace', {})).get('server', {}) if c else {}
        check('U11g ...se lee: ni la nota del ini sin leer, y el token del ini entra (delphi_workspace contesta)',
              c is not None and not any(p in texto for p in partes11g) and bool(w11g) and
              'settingsUnreadable' not in w11g, 'cli=%s %s %s' % (c, texto[-300:], json.dumps(w11g)[:200]))
        para(proc)
    finally:
        if h not in (None, ctypes.c_void_p(-1).value):
            k32.CloseHandle(ctypes.c_void_p(h))

    # ------------------------------------------------------------------ U12
    # [Server] dos veces: Windows lee el primero, y la version del operador
    # puede estar en el segundo; escribir la clave la taparia para siempre.
    # Arranca, NO escribe, y el log dice por que (revision del 6-oct-2026)
    INI12 = ini_bytes([]) + ('[Server]\r\nDelphiVersion=%s\r\n' % NUEVA).encode('ascii')
    d12, exe12 = carpeta_servidor('server-doble', INI12)
    proc, ruta, c = lanza(exe12, 'server-doble')
    texto = '\n'.join(mensajes(ruta))
    check('U12 [Server] dos veces: arranca, NO escribe la clave y el log dice por que',
          c is not None and ini_de(d12) == INI12 and CAT['SF_GUARD_SERVER_DOBLE_NO_ESCRIBE'] in texto,
          texto[-400:])
    para(proc)

    # ------------------------------------------------------------------ U6
    # U10 en el mismo arranque: un DelphiUpdate con otra forma
    # SIN clave en el ini: con ella el ini ganaba igual y el check no veia que
    # la variable volviese como respaldo (revision del 6-oct-2026)
    d6, exe6 = carpeta_servidor('entorno', ini_bytes(['DelphiUpdate=13,2']))
    proc, ruta, c = lanza(exe6, 'entorno', {'DELPHI_MCP_DELPHI_VERSION': NO_ESTA})
    ws = llama(c, 'delphi_workspace', {}) if c else {}
    check('U6 DELPHI_MCP_DELPHI_VERSION ya no existe: con una que no esta en el entorno y SIN clave, '
          'arranca con la mas moderna y escribe ESA',
          ws.get('activeDelphi') == NUEVA and ws.get('delphiVersionRequested') == NUEVA
          and en_server(ini_de(d6), LINEA), json.dumps(ws)[:300])
    log = mensajes(ruta)
    check('U10 [Server] DelphiUpdate=13,2 (no es numero.numero): el log lo avisa y se ignora, como si no estuviera',
          CAT['SL_GUARD_DELPHIUPDATE_MAL_FMT'] % '13,2' in log and 'delphiUpdate' not in ws
          and CAT['SL_DISC_UPDATE_SIN_DECLARAR'] in log, log[-12:])
    para(proc)

    # ------------------------------------------------------------------ U7
    d7 = os.path.join(BASE, 'sin-ini')
    os.makedirs(d7)
    exe7 = mc.copia_exe(d7)
    s = mc.Stdio(exe7, env=mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='un-delphi', cwd=d7)
    try:
        ws = mc.como_json(s.call('delphi_workspace', {}))
    finally:
        s.cierra()
    check('U7 sin settings.ini (modo local, stdio): %s, y NO crea un ini' % QUE,
          ws.get('activeDelphi') == NUEVA and not os.path.exists(os.path.join(d7, 'settings.ini')),
          json.dumps(ws)[:300])
finally:
    for p, s in list(procs):
        para(p)
    mc.borra(BASE)

mc.fin('un servidor, un Delphi')
