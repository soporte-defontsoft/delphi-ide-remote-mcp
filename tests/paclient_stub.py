#!/usr/bin/env python3
"""Stub de paclient.exe para probar remote-run sin PAServer real.

Traduce --put / --get / --Remove a copias sobre una carpeta 'scratch' local
apuntada por MCP_STUB_SCRATCH. Ignora el ProfileName.

Los FLAGS del --put SI cuentan, porque son el mecanismo de ejecucion desde que
se retiro el runner (19-sep-2026): PAServer ejecuta el fichero cuando va con
flag 5 (con /bin/sh) o con flag 3 (el binario directamente). El stub lo imita
corriendo el guion con `bash`, que en Windows llega con git -- asi la bateria
prueba EL GUION DE VERDAD (su comprobacion de binario nativo, su redireccion,
su centinela ___RC=), no una reimplementacion nuestra de lo que creemos que
hace. Sin bash no se puede fingir con honestidad, asi que se dice y se falla:
un test que se salta en silencio es un agujero.
"""
import os, shutil, subprocess, sys, time

SCRATCH = os.environ['MCP_STUB_SCRATCH']


def rel(p):
    return os.path.join(SCRATCH, p.replace('/', os.sep))


def bash():
    """El bash de Git para Windows, o el del PATH."""
    cand = [shutil.which('bash')]
    cand += [os.path.join(os.environ.get(v, ''), 'Git', 'bin', 'bash.exe')
             for v in ('ProgramFiles', 'ProgramW6432', 'LOCALAPPDATA')]
    for c in cand:
        if c and os.path.isfile(c):
            return c
    return None


def ejecutar(guion):
    """Lo que hace PAServer con un flag 5: correr el fichero.

    OJO con una trampa del banco de pruebas, que costo un rato: el servidor
    lanza paclient dentro de un Job Object con KILL_ON_JOB_CLOSE, asi que TODO
    lo que cuelgue de esta llamada muere cuando la llamada termina -- incluido
    el trabajo que el guion deja en segundo plano. En la realidad eso no pasa,
    porque el trabajo corre en la OTRA maquina, fuera de cualquier job; aqui
    si. Por eso el stub espera a que el trabajo remate su centinela antes de
    devolver el control: es la unica forma de que el proceso siga vivo el
    tiempo suficiente. El runner viejo no sufria esto porque era un proceso
    aparte que arrancaba la propia bateria.

    La espera tiene tope (MCP_STUB_ESPERA, 20 s por defecto): agotarla deja el
    fichero a medias, que es justo lo que necesita el caso "sigue corriendo".
    """
    sh = bash()
    if not sh:
        sys.stderr.write(
            'stub: no encuentro bash para ejecutar el guion (flag 5). La '
            'bateria de remote-run necesita el bash que viene con git.\n')
        sys.exit(2)
    d = os.path.dirname(guion)
    antes = {f: os.path.getmtime(os.path.join(d, f))
             for f in os.listdir(d) if f.endswith('.out')}
    subprocess.run([sh, guion.replace(os.sep, '/')], cwd=d,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   timeout=120)
    tope = float(os.environ.get('MCP_STUB_ESPERA', '20'))
    fin = time.time() + tope
    while time.time() < fin:
        for f in os.listdir(d):
            if not f.endswith('.out') or antes.get(f) == os.path.getmtime(
                    os.path.join(d, f)):
                continue
            try:
                if '___RC=' in open(os.path.join(d, f), encoding='utf-8',
                                    errors='replace').read():
                    return
            except OSError:
                pass
        time.sleep(0.2)


for arg in sys.argv[1:]:
    if arg.startswith('--put='):
        spec = arg[len('--put='):]
        for one in spec.split(';'):
            parts = one.split(',')
            src = parts[0]
            destdir = parts[1] if len(parts) > 1 else ''
            flag = parts[2] if len(parts) > 2 else '0'
            destname = parts[3] if len(parts) > 3 else os.path.basename(src)
            d = rel(destdir)
            os.makedirs(d, exist_ok=True)
            destino = os.path.join(d, destname)
            shutil.copy(src, destino)
            if flag == '5':
                ejecutar(destino)
                # "the copy does not stay": PAServer no deja el guion
                try:
                    os.remove(destino)
                except OSError:
                    pass
            elif flag == '3':
                subprocess.Popen([destino], cwd=d,
                                 stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
    elif arg.startswith('--get='):
        spec = arg[len('--get='):]
        for one in spec.split(';'):
            parts = one.split(',')
            src = rel(parts[0])
            destdir = parts[1] if len(parts) > 1 else '.'
            if not os.path.isfile(src):
                sys.exit(1)   # not there yet -> non-zero, like paclient
            os.makedirs(destdir, exist_ok=True)
            shutil.copy(src, os.path.join(destdir, os.path.basename(src)))
    elif arg.startswith('--Remove='):
        spec = arg[len('--Remove='):]
        for one in spec.split(';'):
            p = rel(one)
            if os.path.isfile(p):
                os.remove(p)
sys.exit(0)
