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
      seccion que se ignora entera (sin token) no se dice
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

Lo que NO mide, y por que: que cada tool use solo el Delphi del servidor y
nunca el de otra instalacion necesita una maquina con DOS Delphi (aqui hay
uno). Lo sostienen la revision de R1 (5-oct-2026, todos los sitios
recorridos) y que todos pasan por un solo lector, DiscoverRadStudio.

Usage:  python tests/test_un_delphi.py [path-to-DelphiLspMcp.exe]
"""
import json, os, re, subprocess, winreg
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
    proc = subprocess.Popen([exe, '--http', str(puerto)], env=env,
                            stdout=salida, stderr=subprocess.STDOUT)
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
                     ['DelphiVersion=99.0', '', '[Workspace.SinToken]', 'Roots=%s' % JAIL,
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
    NUEVA = CON_LSP[0]['version']          # newest first, como las lista el servidor
    NO_ESTA = next(v for v in ('23.0', '22.0', '99.0') if v not in [i['version'] for i in TODAS])
    ws = llama(c, 'delphi_workspace', {})
    log = mensajes(ruta)
    LINEA = ('DelphiVersion=%s\r\n' % NUEVA).encode('ascii')
    ESCRITO = ini_de(d1)
    check('U1 sin clave: activa la mas moderna (%s), y desde ya es la pedida' % NUEVA,
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
    usa = CAT['SL_DISC_USA_FMT'] % (nombre_con_version(CON_LSP[0]), CAT['SL_DISC_POR_CLAVE'])
    check('U1 ...y cual usa: "DelphiVersion=%s (nombre), pinned by [Server] DelphiVersion"' % NUEVA,
          usa in log, log[-12:])
    check('U2 [Workspace] DelphiVersion= ya no se lee: el log lo avisa',
          CAT['SL_GUARD_DELPHIVERSION_EN_WORKSPACE_FMT'] % 'Op' in log, log[-12:])
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
          UPDATE != '' and CON_LSP[0].get('installedUpdate') == UPDATE and UPDATE not in json.dumps(ws),
          json.dumps(ws)[:300])
    check('U8 ...y en el log de arranque, en la linea de su instalacion y en la de "uses"',
          UPDATE != '' and (', %s  ->' % UPDATE) in linea_de(CON_LSP[0], NUEVA)
          and linea_de(CON_LSP[0], NUEVA) in log and UPDATE in usa and usa in log, log[-12:])
    para(proc)

    # ------------------------------------------------------------------ U3
    proc, ruta, c = lanza(exe1, 'sin-clave-2')
    ws = llama(c, 'delphi_workspace', {}) if c else {}
    log = mensajes(ruta)
    check('U3 segundo arranque: manda la clave escrita ("pinned by") y no se escribe otra vez',
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

    # ------------------------------------------------------------------ U6
    # U10 en el mismo arranque: un DelphiUpdate con otra forma
    d6, exe6 = carpeta_servidor('entorno', ini_bytes(['DelphiVersion=%s' % NUEVA, 'DelphiUpdate=13,2']))
    proc, ruta, c = lanza(exe6, 'entorno', {'DELPHI_MCP_DELPHI_VERSION': NO_ESTA})
    ws = llama(c, 'delphi_workspace', {}) if c else {}
    check('U6 DELPHI_MCP_DELPHI_VERSION ya no existe: con una que no esta en el entorno, arranca igual',
          ws.get('activeDelphi') == NUEVA and ws.get('delphiVersionRequested') == NUEVA, json.dumps(ws)[:300])
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
    check('U7 sin settings.ini (modo local, stdio): la mas moderna, y NO crea un ini',
          ws.get('activeDelphi') == NUEVA and not os.path.exists(os.path.join(d7, 'settings.ini')),
          json.dumps(ws)[:300])
finally:
    for p, s in list(procs):
        para(p)
    mc.borra(BASE)

mc.fin('un servidor, un Delphi')
