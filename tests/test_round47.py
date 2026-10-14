# -*- coding: utf-8 -*-
"""Round 47: dos de las tres medidas que la 1.0.13 dejo a deber.

La auditoria del 21-sep arreglo tres cosas sin poder medirlas, y lo dijo en
voz alta. Aqui se pagan dos:

  C  La caida CESU-8 del decodificador de hijos. Hacia falta "un hijo que
     emita esos bytes", y lo hay sin inventar nada: `git show HEAD:fichero`
     escupe el contenido CRUDO de un fichero (desde la 1.19.0, show con
     ref=HEAD:fichero). Se versiona uno con un par
     suplente en CESU-8 (ED A0 BD ED B8 80: bien FORMADO, que es lo que mira
     LooksUtf8, e INVALIDO para el decodificador estricto) y se pide por
     delphi_git. Antes del arreglo eso mataba la llamada con "No mapping for
     the Unicode character..."; ahora cae a la red y el ASCII llega entero.

  R  (AgentTempDir con la PRIMERA raiz declarada de solo lectura) ya no se
     mide aqui: desde la 1.18.2 (2af) las capturas viven en la casa del
     servidor y no en una raiz, y desde la 1.0.16 el escritorio pide un
     perfil, asi que R1/R2 no median nada. Lo mide test_desktop_casa_1182
     (D2, D5) contra el Zorin, y sin escritorio test_captura_puertas_1182.

La tercera (la clave de cache entre workspaces solapados) se paga en
test_round48: un servidor, dos tokens, y el exe de la 1.0.12 de control.
"""
import os
import time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('round47')
EXEDIR = os.path.join(BASE, 'srv')
RO = os.path.join(BASE, 'referencia')     # la PRIMERA raiz, de solo lectura
RW = os.path.join(BASE, 'trabajo')        # la segunda, escribible
os.makedirs(os.path.join(EXEDIR, 'node'))
os.makedirs(RO)
os.makedirs(RW)
EXE = mc.copia_exe(EXEDIR)

TOK = 'r47'
PORT = mc.puerto_libre()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R47]', 'Token=%s' % TOK, 'Roots=%s;%s' % (RO, RW),
    'ReadOnlyPaths=%s' % RO, '']))

proc = mc.lanza_http(EXE, PORT, mc.entorno())
# sin texto, el mensaje entero en JSON: es lo que ensena el detalle de un FAIL
cli = mc.Http(PORT, TOK, respaldo_json=True)
cli.session('r47')
call = cli.call


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
    # 1.19.0: sin args; cada comando con sus campos
    call('delphi_git', {'repo': repo, 'command': 'config',
                        'name': 'user.name', 'message': 'r47'})
    call('delphi_git', {'repo': repo, 'command': 'config',
                        'name': 'user.email', 'message': 'r47@example.invalid'})
    call('delphi_git', {'repo': repo, 'command': 'add', 'paths': ['cesu.txt']})
    c = call('delphi_git', {'repo': repo, 'command': 'commit',
                            'message': 'fichero con un par suplente CESU-8'})
    check('C0 el fichero venenoso queda versionado', c.startswith('exit=0'), c[:200])
    s = call('delphi_git', {'repo': repo, 'command': 'show',
                            'ref': 'HEAD:cesu.txt'})
    # la llamada VIVA: git contesto (exit=0) y su salida llego; no basta con
    # que no diga "No mapping" (un timeout tampoco lo dice)
    check('C1 un hijo que emite CESU-8 ya no mata la llamada',
          s.startswith('exit=0') and 'No mapping' not in s and
          mc.resultado(s) != 'INTERNAL', s[:240])
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
          isinstance(mc.como_json(a).get('folders'), list) and 'Generado.pas' not in a,
          a[:200])
    b = call('delphi_search', {'root': salida, 'query': 'agujaenelartefacto'})
    check('S2 nombrada como raiz, se busca dentro (como hace delphi_list)',
          'Generado.pas' in b, b[:200])

    # ------------------------------------------------------------------- P
    # La papelera de una carpeta que NADIE edita ya se purga: el recorredor
    # de delphi_list pasa por delante y tira lo caducado (>15 dias). Antes la
    # purga solo salia de BackupFile, asi que esas copias eran para siempre.
    # Recorrer las raices al arrancar se midio y se descarto (5,9 s).
    quieta = os.path.join(RW, 'quieta', mc.PAPELERA)
    os.makedirs(os.path.join(quieta, '20200101'))
    open(os.path.join(quieta, '20200101', 'Vieja.pas'), 'w').write('x')
    hoy = mc.dia_de_papelera()
    os.makedirs(os.path.join(quieta, hoy))
    open(os.path.join(quieta, hoy, 'Reciente.pas'), 'w').write('x')
    # ...y la misma trampa bajo la raiz de SOLO LECTURA: ahi no se toca nada.
    intocable = os.path.join(RO, 'vendor', mc.PAPELERA, '20200101')
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
          isinstance(mc.como_json(lro).get('folders'), list) and
          os.path.exists(os.path.join(intocable, 'Ajena.pas')), (intocable, lro[:160]))

finally:
    try:
        proc.kill()
    except Exception:
        pass
    time.sleep(0.5)
    mc.borra(BASE)

mc.fin('test_round47')
