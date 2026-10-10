# -*- coding: utf-8 -*-
"""Un repositorio ENTERO en la papelera se purga, a mano y a los 15 dias, y un
dia de la papelera que no se deja borrar no frena a los demas (1.18.1).

Medido el 10-oct-2026 contra la 1.18.0, en vivo: delphi_delete purge=true de
un repo mandado a la papelera daba FILE-011 con GUARD-033 (su .git); y la
purga de 15 dias (BackupFile -> PurgeOldBackups) borraba con el mismo
BorraArbol dentro de UN try para todo el bucle: un dia viejo con un repo y otro
viejo limpio detras sobrevivian LOS DOS, y sin el del repo el limpio se iba.

Lo que no cambia, medido igual: un .git suelto (en la papelera o vivo) sigue
negado, y un enlace dentro del repo nunca borra lo de detras (la victima de
fuera de las raices sale intacta)."""
import os, subprocess, time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('purga-repo-118')
MINE, OUT = [os.path.join(BASE, n) for n in ('mio', 'victima')]
os.makedirs(MINE)
os.makedirs(OUT)
open(os.path.join(OUT, 'secreto.txt'), 'w').write('no se toca')
VICTIMA = sorted(os.listdir(OUT))
ENLACES = []


def git_init(carpeta):
    os.makedirs(carpeta)
    subprocess.run(['git', 'init', '-q', carpeta], check=True, capture_output=True)
    open(os.path.join(carpeta, 'a.txt'), 'w').write('a\n')


def dia_viejo(dias):
    return mc.dia_de_papelera(time.localtime(time.time() - dias * 86400))


def dia(nombre):
    return os.path.join(MINE, mc.PAPELERA, nombre)


def cajon(nombre):
    return os.path.join(dia(nombre), mc.CAJON_BORRADOS)


def a_la_papelera(nombre):
    """delphi_delete de una carpeta de MINE: la ruta de su copia en la papelera de
    hoy ('' si no esta), y la respuesta."""
    antes = set(os.listdir(cajon(mc.dia_de_papelera()))) if os.path.isdir(cajon(mc.dia_de_papelera())) else set()
    r = srv.call('delphi_delete', {'path': os.path.join(MINE, nombre)})
    hoy = cajon(mc.dia_de_papelera())
    nuevas = [n for n in (set(os.listdir(hoy)) - antes if os.path.isdir(hoy) else [])
              if n.lower().startswith(nombre.lower()) and not mc.es_marca_dueno(n)]
    return (os.path.join(hoy, nuevas[0]) if len(nuevas) == 1 else ''), r


def enlace(link, target):
    ok = mc.junction(link, target)
    if ok:
        ENLACES.append(link)
    return ok


def victima_intacta():
    return sorted(os.listdir(OUT)) == VICTIMA and open(os.path.join(OUT, 'secreto.txt')).read() == 'no se toca'


EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': MINE}), nombre='purga-repo-118')
try:
    # P1 - un repo ENTERO va a la papelera (ya iba) y de ahi se purga a mano
    git_init(os.path.join(MINE, 'repo1'))
    copia, r = a_la_papelera('repo1')
    check('P1 fixture: delete de un repo entero lo manda a la papelera',
          not mc.fallo(r) and copia != '' and not os.path.exists(os.path.join(MINE, 'repo1')), r[:300])
    if copia:
        r = srv.call('delphi_delete', {'path': copia, 'purge': True})
        check('P1 purge=true de un repo entero en la papelera lo borra (era FILE-011 con GUARD-033)',
              not mc.fallo(r) and not os.path.exists(copia), r[:400])

    # P2 - la purga de 15 dias: un dia viejo con un repo y otro viejo detras (por
    # nombre, el orden en que la purga los recorre)
    A, B = dia_viejo(40), dia_viejo(30)
    git_init(os.path.join(cajon(A), 'repo2'))
    os.makedirs(os.path.join(cajon(B), 'plano'))
    open(os.path.join(cajon(B), 'plano', 'b.txt'), 'w').write('b')
    U = os.path.join(MINE, 'u.txt')
    open(U, 'wb').write(b'uno\r\n')
    r = srv.call('delphi_textedit', {'path': U, 'old': 'uno', 'new': 'dos'})
    check('P2 fixture: la primera edicion del dia de u.txt entra (su copia dispara la purga)', not mc.fallo(r), r[:200])
    check('P2 la purga de 15 dias se lleva un dia viejo con un repo entero dentro (se quedaba para siempre)',
          not os.path.exists(dia(A)), sorted(os.listdir(os.path.join(MINE, mc.PAPELERA))))
    check('P2b ...y el dia viejo de detras tambien (la purga entera se cortaba en el del repo)',
          not os.path.exists(dia(B)), sorted(os.listdir(os.path.join(MINE, mc.PAPELERA))))

    # P3 - un dia viejo que no se deja borrar por OTRA causa (un fichero abierto
    # sin compartir) no frena al de detras: un try por dia, no uno para todos
    C, D = dia_viejo(25), dia_viejo(20)
    os.makedirs(os.path.join(cajon(C), 'abierto'))
    TOMADO = os.path.join(cajon(C), 'abierto', 'c.txt')
    open(TOMADO, 'w').write('c')
    os.makedirs(os.path.join(cajon(D), 'plano'))
    open(os.path.join(cajon(D), 'plano', 'd.txt'), 'w').write('d')
    V = os.path.join(MINE, 'v.txt')
    open(V, 'wb').write(b'uno\r\n')
    with mc.bloqueado(TOMADO):
        r = srv.call('delphi_textedit', {'path': V, 'old': 'uno', 'new': 'dos'})
    check('P3 fixture: la primera edicion del dia de v.txt entra con el fichero tomado', not mc.fallo(r), r[:200])
    check('P3 fixture: el dia con el fichero tomado se queda (no se dejaba borrar)', os.path.exists(TOMADO))
    check('P3 ...y el dia viejo de detras se purga igual (el primero que fallaba cortaba la purga)',
          not os.path.exists(dia(D)), sorted(os.listdir(os.path.join(MINE, mc.PAPELERA))))

    # P4 - controles: un .git SUELTO sigue negado, en la papelera y vivo
    git_init(os.path.join(MINE, 'repo4'))
    copia4, r = a_la_papelera('repo4')
    if copia4:
        r = srv.call('delphi_delete', {'path': os.path.join(copia4, '.git'), 'purge': True})
        check('P4 control: purge=true de SOLO el .git de un repo de la papelera, negado (GUARD-033) y sigue ahi',
              mc.rechazado(r) and mc.es(r, 'SR_GUARD_GIT_METADATA_FMT') and
              os.path.isdir(os.path.join(copia4, '.git')), r[:300])
    else:
        check('P4 fixture: repo4 en la papelera', False, r[:300])
    git_init(os.path.join(MINE, 'vivo'))
    r = srv.call('delphi_delete', {'path': os.path.join(MINE, 'vivo', '.git')})
    check('P4b control: delete del .git de un repo VIVO, negado (GUARD-033) y sigue ahi',
          mc.rechazado(r) and mc.es(r, 'SR_GUARD_GIT_METADATA_FMT') and
          os.path.isdir(os.path.join(MINE, 'vivo', '.git')), r[:300])

    # P5 - enlaces dentro de un repo de la papelera hacia una victima de FUERA de
    # las raices (plantados ya en la papelera: con uno en el .git no se dejaria
    # mandar). (a) en el .git: no se purga y la victima sigue; (b) en el arbol de
    # trabajo: se purga quitando el enlace como enlace, la victima sigue
    git_init(os.path.join(MINE, 'repo5a'))
    copia5a, _ = a_la_papelera('repo5a')
    git_init(os.path.join(MINE, 'repo5b'))
    copia5b, _ = a_la_papelera('repo5b')
    if copia5a and copia5b:
        check('P5 fixture: enlace en el .git hacia la victima', enlace(os.path.join(copia5a, '.git', 'enlace'), OUT))
        check('P5 fixture: enlace en el arbol de trabajo hacia la victima', enlace(os.path.join(copia5b, 'enlace'), OUT))
        r = srv.call('delphi_delete', {'path': copia5a, 'purge': True})
        check('P5a un repo de la papelera con un enlace de sus metadatos hacia fuera NO se purga (GUARD-033), no se '
              'toca nada de el y la victima sigue',
              mc.rechazado(r) and mc.es(r, 'SR_GUARD_GIT_METADATA_FMT') and
              os.path.isfile(os.path.join(copia5a, 'a.txt')) and os.path.isfile(os.path.join(copia5a, '.git', 'HEAD'))
              and victima_intacta(), r[:300])
        r = srv.call('delphi_delete', {'path': copia5b, 'purge': True})
        check('P5b uno con un enlace en el arbol de trabajo se purga (el enlace como enlace) y la victima sigue',
              not mc.fallo(r) and not os.path.exists(copia5b) and victima_intacta(), r[:300])
    else:
        check('P5 fixture: repo5a y repo5b en la papelera', False, (copia5a, copia5b))

    # P6 - una junction llamada .git en la papelera hacia el .git de un repo VIVO de
    # la jaula (P4b): el enlace se queda dentro de la jaula, asi que se purga, y se
    # quita como enlace: el .git vivo sigue entero (revisor propio del arreglo)
    os.makedirs(os.path.join(MINE, 'carpeta6'))
    open(os.path.join(MINE, 'carpeta6', 'b.txt'), 'w').write('b')
    copia6, _ = a_la_papelera('carpeta6')
    VIVO_HEAD = os.path.join(MINE, 'vivo', '.git', 'HEAD')
    vivo_antes = open(VIVO_HEAD, 'rb').read() if os.path.isfile(VIVO_HEAD) else None
    if copia6 and vivo_antes is not None:
        check('P6 fixture: junction .git en la papelera hacia el .git del repo vivo',
              enlace(os.path.join(copia6, '.git'), os.path.join(MINE, 'vivo', '.git')))
        r = srv.call('delphi_delete', {'path': copia6, 'purge': True})
        check('P6 una junction .git hacia un .git vivo de la jaula se purga como enlace y el repo vivo sigue entero',
              not mc.fallo(r) and not os.path.exists(copia6) and os.path.isfile(VIVO_HEAD) and
              open(VIVO_HEAD, 'rb').read() == vivo_antes, r[:300])
    else:
        check('P6 fixture: carpeta6 en la papelera y el repo vivo de P4b', False, (copia6, vivo_antes))
finally:
    srv.cierra()
    for L in ENLACES:
        if os.path.isjunction(L):
            os.rmdir(L)
check('la victima de fuera de las raices sale intacta', victima_intacta(), sorted(os.listdir(OUT)))
mc.borra(BASE)
check('BASE eliminada con su copia del exe', not os.path.exists(BASE), BASE)
mc.fin('purga de un repo en la papelera (1.18.1)')
