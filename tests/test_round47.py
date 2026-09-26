# -*- coding: utf-8 -*-
"""Round 47: dos de las tres medidas que la 1.0.13 dejo a deber.

La auditoria del 21-sep arreglo tres cosas sin poder medirlas, y lo dijo en
voz alta. Aqui se pagan dos:

  C  La caida CESU-8 del decodificador de hijos. Hacia falta "un hijo que
     emita esos bytes", y lo hay sin inventar nada: `git show HEAD:fichero`
     escupe el contenido CRUDO de un fichero. Se versiona uno con un par
     suplente en CESU-8 (ED A0 BD ED B8 80: bien FORMADO, que es lo que mira
     LooksUtf8, e INVALIDO para el decodificador estricto) y se pide por
     delphi_git. Antes del arreglo eso mataba la llamada con "No mapping for
     the Unicode character..."; ahora cae a la red y el ASCII llega entero.

  R  AgentTempDir con la PRIMERA raiz declarada de solo lectura: el
     entregable tiene que caer en la primera raiz ESCRIBIBLE. Necesita el
     nodo del escritorio y una sesion que pueda capturar; si no, se DICE.

La tercera (la clave de cache entre workspaces solapados) se paga en
test_round48: un servidor, dos tokens, y el exe de la 1.0.12 de control.
"""
import os
import shutil
import time
import mcp_cliente as mc
from mcp_cliente import check

REPO = mc.REPO
NODO = os.path.join(REPO, 'node', 'McpDesktopNode.exe')

BASE = mc.carpeta('round47')
EXEDIR = os.path.join(BASE, 'srv')
RO = os.path.join(BASE, 'referencia')     # la PRIMERA raiz, de solo lectura
RW = os.path.join(BASE, 'trabajo')        # la segunda, escribible
os.makedirs(os.path.join(EXEDIR, 'node'))
os.makedirs(RO)
os.makedirs(RW)
EXE = mc.copia_exe(EXEDIR)
HAY_NODO = os.path.exists(NODO)
if HAY_NODO:
    shutil.copy(NODO, os.path.join(EXEDIR, 'node', 'McpDesktopNode.exe'))

TOK = 'r47'
PORT = mc.puerto_libre()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R47]', 'Token=%s' % TOK, 'Roots=%s;%s' % (RO, RW),
    'ReadOnlyPaths=%s' % RO, 'AllowDesktopControl=1', '']))

proc = mc.lanza_http(EXE, PORT, mc.entorno())
# sin texto, el mensaje entero en JSON: es lo que ensena el detalle de un FAIL
cli = mc.Http(PORT, TOK, respaldo_json=True)
cli.session('r47')
call = cli.call


def pngs(d):
    if not os.path.isdir(d):
        return []
    return [os.path.join(r, f)
            for r, _, fs in os.walk(d) for f in fs if f.lower().endswith('.png')]


try:
    # ------------------------------------------------------------------- C
    # El fichero lo planta la bateria A MANO: son bytes que ninguna tool de
    # edicion escribiria. El par suplente en CESU-8 va entre dos marcas ASCII.
    repo = os.path.join(RW, 'cesu')
    os.makedirs(repo)
    veneno = b'MARCA-ANTES ' + bytes([0xED, 0xA0, 0xBD, 0xED, 0xB8, 0x80]) + \
        b' MARCA-DESPUES\n'
    open(os.path.join(repo, 'cesu.txt'), 'wb').write(veneno)
    call('delphi_git', {'repo': repo, 'command': 'init'})
    call('delphi_git', {'repo': repo, 'command': 'config',
                        'args': 'user.name', 'message': 'r47'})
    call('delphi_git', {'repo': repo, 'command': 'config',
                        'args': 'user.email', 'message': 'r47@example.invalid'})
    call('delphi_git', {'repo': repo, 'command': 'add', 'args': 'cesu.txt'})
    c = call('delphi_git', {'repo': repo, 'command': 'commit',
                            'message': 'fichero con un par suplente CESU-8'})
    check('C0 el fichero venenoso queda versionado', c.startswith('exit=0'), c[:200])
    s = call('delphi_git', {'repo': repo, 'command': 'show',
                            'args': 'HEAD:cesu.txt'})
    # la llamada VIVA: git contesto (exit=0) y su salida llego; no basta con
    # que no diga "No mapping" (un timeout tampoco lo dice)
    check('C1 un hijo que emite CESU-8 ya no mata la llamada',
          s.startswith('exit=0') and 'No mapping' not in s and
          'Error executing tool' not in s, s[:240])
    check('C2 ...y el ASCII de los dos lados llega entero',
          'MARCA-ANTES' in s and 'MARCA-DESPUES' in s, s[:240])

    # ------------------------------------------------------------------- S
    # delphi_search filtra los artefactos como su gemela delphi_list: sobre
    # la ruta RELATIVA a la raiz, y si nombras la carpeta de compilacion es
    # que la quieres ver. Filtraba la absoluta: buscar DENTRO de
    # Win64\Release devolvia cero, en silencio.
    salida = os.path.join(RW, 'proy', 'Win64', 'Release')
    os.makedirs(salida)
    open(os.path.join(salida, 'Generado.pas'), 'w').write(
        'unit Generado;\n// agujaenelartefacto\ninterface\nimplementation\nend.\n')
    a = call('delphi_search', {'root': os.path.join(RW, 'proy'),
                               'query': 'agujaenelartefacto'})
    # una busqueda de VERDAD (su JSON con hits) que no trae el artefacto
    check('S1 desde arriba, la carpeta de compilacion sigue oculta',
          isinstance(mc.como_json(a).get('hits'), list) and 'Generado.pas' not in a,
          a[:200])
    b = call('delphi_search', {'root': salida, 'query': 'agujaenelartefacto'})
    check('S2 nombrada como raiz, se busca dentro (como hace delphi_list)',
          'Generado.pas' in b, b[:200])

    # ------------------------------------------------------------------- P
    # La papelera de una carpeta que NADIE edita ya se purga: el recorredor
    # de delphi_list pasa por delante y tira lo caducado (>15 dias). Antes la
    # purga solo salia de BackupFile, asi que esas copias eran para siempre.
    # Recorrer las raices al arrancar se midio y se descarto (5,9 s).
    quieta = os.path.join(RW, 'quieta', '__delphi-patch')
    os.makedirs(os.path.join(quieta, '20200101'))
    open(os.path.join(quieta, '20200101', 'Vieja.pas'), 'w').write('x')
    hoy = time.strftime('%Y%m%d')
    os.makedirs(os.path.join(quieta, hoy))
    open(os.path.join(quieta, hoy, 'Reciente.pas'), 'w').write('x')
    # ...y la misma trampa bajo la raiz de SOLO LECTURA: ahi no se toca nada.
    intocable = os.path.join(RO, 'vendor', '__delphi-patch', '20200101')
    os.makedirs(intocable)
    open(os.path.join(intocable, 'Ajena.pas'), 'w').write('x')
    call('delphi_list', {'root': RW})
    lro = call('delphi_list', {'root': RO})
    check('P1 un listado que pasa por delante tira la carpeta de dia caducada',
          not os.path.exists(os.path.join(quieta, '20200101')),
          os.listdir(quieta))
    check('P2 ...y deja en paz la reciente',
          os.path.exists(os.path.join(quieta, hoy, 'Reciente.pas')),
          os.listdir(quieta))
    # el listado de la referencia se HIZO (su JSON) y aun asi no purgo: si la
    # llamada fallaba, "sigue ahi" pasaba sin que el recorredor pasara
    check('P3 bajo ReadOnlyPaths no se purga nada: se lee, no se toca',
          isinstance(mc.como_json(lro).get('files'), list) and
          os.path.exists(os.path.join(intocable, 'Ajena.pas')), (intocable, lro[:160]))

    # ------------------------------------------------------------------- R
    # Roots=referencia;trabajo con ReadOnlyPaths=referencia. El entregable
    # por defecto caia en Roots[0] a pelo: justo donde la jaula prohibe
    # escribir (y donde la misma ruta pasada en "out" se rechaza).
    shot = call('delphi_desktop', {'command': 'screenshot'}) if HAY_NODO else ''
    if not HAY_NODO:
        print('NOTA: no hay node/McpDesktopNode.exe; R1/R2 no se miden.')
    elif 'NO pude capturar' in shot or '"screenshot"' not in shot:
        # Desde 1.0.16 el escritorio solo se alcanza por PAServer y un perfil
        # (ni hay perfil aqui ni remote-run encendido): se dice el motivo REAL
        # que da el servidor, no se supone una sesion bloqueada.
        print('NOTA: R1/R2 no se miden: delphi_desktop no capturo: %s'
              % ' '.join(shot.split())[:160])
    else:
        check('R1 la captura por defecto cae en la raiz ESCRIBIBLE',
              bool(pngs(os.path.join(RW, '__delphi-temp'))), shot[:240])
        check('R2 ...y en la raiz de solo lectura no se ha creado nada',
              not os.path.exists(os.path.join(RO, '__delphi-temp')),
              os.listdir(RO))
finally:
    try:
        proc.kill()
    except Exception:
        pass
    time.sleep(0.5)
    mc.borra(BASE)

mc.fin('test_round47')
