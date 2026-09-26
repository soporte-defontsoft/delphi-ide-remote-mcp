# -*- coding: utf-8 -*-
"""E2E battery: la ruta de salida que elige QUIEN LLAMA.

Varias tools aceptan un destino local: donde dejar la captura, donde escribir
el logcat, donde armar el zip. Esa ruta viene del cliente, asi que tiene que
pasar por la jaula igual que cualquier otra. La regla esta centralizada en UNA
funcion (PathDenied); lo que no estaba centralizado es acordarse de llamarla,
y se medio el 2026-09-21:

    delphi_adb  logcat  out      SI
    delphi_adb  screenshot out   SI
    delphi_package  outfile      SI
    delphi_desktop  out          NO   <- el servidor creaba la carpeta y
    delphi_adb_linux out         NO      soltaba el PNG donde le dijeran

Tres de cinco se acordaron. Aqui se miden LAS CINCO: las dos que fallaban y
las tres que no, porque una familia con un guardia en unos miembros y no en
otros es como se llego hasta aqui.

Usage:  python tests/test_round43.py [path-to-DelphiLspMcp.exe]
"""
import os
import time
import mcp_cliente as mc
from mcp_cliente import check


BASE = mc.carpeta('round43')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(EXEDIR, exist_ok=True)
os.makedirs(JAIL, exist_ok=True)
EXE = mc.copia_exe(EXEDIR)

# (Hasta 1.0.15 aqui se copiaba el nodo de escritorio junto al servidor: la
# captura era LOCAL. Desde 1.0.16 delphi_desktop va por perfil PAServer y el
# nodo se despliega en el destino; con un perfil ficticio la llamada muere en
# la puerta de ejecucion remota, antes de mirar el nodo. Era andamiaje muerto.)

# El destino PROHIBIDO va dentro del arbol de la bateria, no suelto por la
# maquina: nada de dejar cebos en el %TEMP% del PC (regla de David, y el dia
# que se incumplio tres baterias acabaron apoyadas en el cebo de otra).
FUERA = os.path.join(BASE, 'fuera')
os.makedirs(FUERA, exist_ok=True)
# OJO al contrato, que no es el mismo en toda la familia: el "out" de
# delphi_desktop y delphi_adb_linux es una CARPETA donde dejar la captura (lo
# dice su descripcion), mientras que el de delphi_adb es un FICHERO y hasta le
# exige la extension. Medido el 2026-09-21 pasandole un .png a delphi_desktop:
# creo un DIRECTORIO llamado robada.png. La bateria usa cada forma como es.
DIR_FUERA = os.path.join(FUERA, 'capturas')
LOG_FUERA = os.path.join(FUERA, 'robado.log')
ZIP_FUERA = os.path.join(FUERA, 'robado.zip')
DIR_DENTRO = os.path.join(JAIL, 'capturas')

TOK = 'r43'
PORT = mc.puerto_libre()
# Los interruptores encendidos A PROPOSITO. Sin ellos las tools contestan
# "desactivada" o "no declarado" y no se llega a mirar la ruta, que es lo
# unico que mide esta bateria. El dispositivo y el proyecto remoto son
# ficticios: no hace falta que existan, porque la ruta se comprueba ANTES de
# salir a buscarlos - y eso tambien es parte del contrato.
DEV = '127.0.0.1:5555'
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R43]', 'Token=%s' % TOK, 'Roots=%s' % JAIL,
    'AllowRemoteRun=1',
    'RemoteRunProjects=NodoLinux', 'AdbAllowedDevices=%s' % DEV, '',
]))

proc = mc.lanza_http(EXE, PORT, mc.entorno())
# sin texto, el mensaje entero en el detalle (como siempre en esta bateria)
cli = mc.Http(PORT, TOK, t=180, respaldo_json=True)
cli.session('r43')
call = cli.call


def rechazada_por_jaula(txt):
    """La negativa de la jaula, no otra cualquiera. Se mira el texto de
    PathDenied para no dar por bueno un 'no hay nodo' o un 'perfil
    desconocido', que tambien empiezan por RECHAZADO."""
    return 'FUERA de los workspaces permitidos' in txt


def nada_en(d):
    """Ni una captura -de ningun formato: la extension sale de la captura,
    no de una constante- ni la carpeta que el servidor viejo creaba."""
    return not os.path.exists(d) or not os.listdir(d)


def llego_al_dispositivo(txt):
    """La regla del "out" dejo pasar la llamada y lo que fallo fue el
    dispositivo (ficticio: nadie contesta en DEV), no otra negativa
    cualquiera."""
    return DEV in txt and 'SIN CONEXION CON EL DISPOSITIVO' in txt


try:
    # ------------------------------------------------------------------ W1
    # El agujero: delphi_desktop escribia donde le dijeran. Desde 1.0.16 la
    # tool va por perfil PAServer (Linux o Windows); la ruta LOCAL se sigue
    # comprobando ANTES del perfil, asi que no hace falta un destino vivo.
    a = call('delphi_desktop', {'command': 'screenshot', 'profile': 'x',
                                'out': DIR_FUERA})
    check('W1 delphi_desktop rechaza un "out" fuera de la jaula',
          rechazada_por_jaula(a), a[:280])
    # EL DANO, no la ausencia del guardia: contra un binario sin el arreglo
    # esto falla porque la pantalla del operador acaba escrita ahi fuera.
    # Solo, y con la sesion bloqueada, esta asercion seria vacua (ni un
    # servidor roto podria escribir): la medida DE VERDAD la remata W4c,
    # cuando consta que capturar funciona (auditoria 2026-09-21).
    # (Con un perfil ficticio ningun servidor, ni uno roto, llega a capturar:
    # esta mitad solo muerde en vivo, contra un PAServer. Lo que mira aqui es
    # que no haya NADA fuera, ni la carpeta que el servidor viejo creaba.)
    check('W1b ...y NO acaba una captura escrita fuera de la jaula',
          nada_en(FUERA),
          'hay algo bajo %s: %s' % (FUERA, os.listdir(FUERA)))

    # ------------------------------------------------------------------ W2
    # (El alias delphi_adb_linux ya no existe; W1 cubre la unica tool.)

    # ------------------------------------------------------------------ W3
    # Las tres que SI se acordaban: se fijan para que no se desvien.
    ROBADA = os.path.join(FUERA, 'robada.png')
    c = call('delphi_adb', {'command': 'screenshot', 'device': DEV,
                            'out': ROBADA})
    check('W3 delphi_adb screenshot sigue rechazandolo',
          rechazada_por_jaula(c), c[:280])
    d = call('delphi_adb', {'command': 'logcat', 'device': DEV,
                            'out': LOG_FUERA})
    check('W3b delphi_adb logcat sigue rechazandolo',
          rechazada_por_jaula(d), d[:280])
    e = call('delphi_package', {'dir': JAIL, 'outfile': ZIP_FUERA})
    check('W3c delphi_package sigue rechazando su "outfile"',
          rechazada_por_jaula(e), e[:280])
    # Decia "las tres" y media DOS: faltaba la captura de delphi_adb
    # (auditoria 2026-09-21).
    check('W3d ...y ninguna de las tres ha escrito nada fuera',
          not os.path.exists(ROBADA) and
          not os.path.exists(LOG_FUERA) and not os.path.exists(ZIP_FUERA),
          os.listdir(FUERA))

    # ------------------------------------------------------------------ W5
    # UNA regla para el "out" de toda la familia (CaptureTarget, v1.0.14).
    # Antes era CARPETA en los escritorios y FICHERO obligatorio acabado en
    # ".png" en delphi_adb. Ahora: carpeta o fichero, y el fichero tiene que
    # llevar la extension REAL de la captura - que sale de la captura, no de
    # una constante ("y si un dia no es png?", David). En delphi_adb la
    # regla muerde ANTES de tocar el dispositivo, asi que se mide sin el.
    g = call('delphi_adb', {'command': 'screenshot', 'device': DEV,
                            'out': os.path.join(JAIL, 'foto.jpg')})
    check('W5 un fichero con la extension de OTRO formato se rechaza',
          'RECHAZADO' in g and '.png' in g and '.jpg' in g, g[:280])
    h = call('delphi_adb', {'command': 'screenshot', 'device': DEV,
                            'out': os.path.join(JAIL, 'foto.png')})
    check('W5b ...con la suya pasa la regla (lo que falle sera el dispositivo)',
          'No escribo una imagen' not in h and not rechazada_por_jaula(h)
          and llego_al_dispositivo(h),
          h[:280])
    i = call('delphi_adb', {'command': 'screenshot', 'device': DEV,
                            'out': os.path.join(JAIL, 'capturas')})
    check('W5c ...y una CARPETA tambien vale ya en delphi_adb',
          'No escribo una imagen' not in i and 'terminar en .png' not in i
          and not rechazada_por_jaula(i) and llego_al_dispositivo(i), i[:280])
    j = call('delphi_adb', {'command': 'screenshot', 'device': DEV})
    check('W5d ...y sin "out" ya no se rechaza: tiene un defecto, como sus hermanas',
          'necesita "out"' not in j and llego_al_dispositivo(j), j[:280])

    # ------------------------------------------------------------------ W4
    # Y el otro lado, que es la mitad que se olvida: cerrar la puerta no sirve
    # de nada si se cierra tambien para quien SI puede pasar. Con un perfil
    # ficticio la llamada pasa la ruta y muere en la SIGUIENTE puerta, la de
    # ejecucion remota (EjecucionRemotaDenegada: el nodo de escritorio no esta
    # en RemoteRunProjects): eso es lo que se mide, y no "cualquier negativa
    # que no sea la de la jaula". (Hasta 1.0.15 aqui capturaba de verdad con
    # el nodo local; ahora la captura real necesita un PAServer y se mide en
    # vivo, no en la bateria.)
    f = call('delphi_desktop', {'command': 'screenshot', 'profile': 'x',
                                'out': DIR_DENTRO})
    check('W4 un "out" DENTRO de la jaula no muere por la ruta',
          not rechazada_por_jaula(f) and 'RemoteRunProjects' in f
          and 'McpDesktopNode' in f, f[:280])
    check('W4c ...y fuera sigue vacio', nada_en(FUERA),
          'hay algo bajo %s: %s' % (FUERA, os.listdir(FUERA)))
    print('NOTA: W4b, W5e y W5f (captura real por perfil) se miden en vivo '
          'contra un PAServer, no aqui.')
finally:
    try:
        proc.kill()
    except Exception:
        pass
    # Se recoge SIEMPRE, y no es mania: lo que produce esta bateria es una
    # captura de la pantalla del operador. No se queda en la maquina.
    time.sleep(0.5)
    mc.borra(BASE)

mc.fin('test_round43')
