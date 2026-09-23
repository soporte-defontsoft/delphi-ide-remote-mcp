#!/usr/bin/env python3
"""Stub de paclient.exe para probar remote-run sin PAServer real.

Traduce --put / --get / --Remove a copias sobre una carpeta 'scratch' local
apuntada por MCP_STUB_SCRATCH. Ignora el ProfileName.

Los FLAGS del --put SI cuentan, porque son el mecanismo de ejecucion: PAServer
ARRANCA el fichero subido, sin argumentos, y espera a que termine (medido
2026-09-22 en Zorin, Fedora y Windows: flag 3 arranca un ELF en Linux, flag 5
un PE en Windows). Desde 1.0.16 lo que sube el servidor es siempre el
LANZADOR nativo (src_run_job, McpRunJob) como run-<trabajo>, junto a un
fichero run-<trabajo>.job con el binario, la salida y un argumento por
linea. No hay shell en ningun sitio.

El stub lo imita ARRANCANDO EL LANZADOR DE VERDAD: con flag 5 corre el PE tal
cual; con flag 3 le llega el ELF de Linux, que aqui no puede correr, asi que
ejecuta en su lugar el gemelo Win64 (MCP_STUB_RUNJOB_EXE: la misma fuente
compilada para Windows) con el mismo nombre run-<trabajo>.exe, para que el
lanzador encuentre su .job. Asi la bateria prueba el lanzador real (su
comprobacion de binario nativo, su ___ENV=, su argv, su centinela ___RC=) y
no una reimplementacion nuestra de lo que creemos que hace.
"""
import os, shutil, subprocess, sys, time

SCRATCH = os.environ['MCP_STUB_SCRATCH']


def rel(p):
    return os.path.join(SCRATCH, p.replace('/', os.sep))


def ejecutar(lanzador):
    """Lo que hace PAServer con un flag 3/5: arrancar el fichero y esperar.

    OJO con una trampa del banco de pruebas, que costo un rato: el servidor
    lanza paclient dentro de un Job Object con KILL_ON_JOB_CLOSE, asi que TODO
    lo que cuelgue de esta llamada muere cuando la llamada termina -- incluido
    el programa y el vigia que el lanzador deja en segundo plano. En la
    realidad eso no pasa, porque el trabajo corre en la OTRA maquina, fuera de
    cualquier job; aqui si. Por eso el stub espera a que el trabajo remate su
    centinela antes de devolver el control: es la unica forma de que el
    proceso siga vivo el tiempo suficiente.

    La espera tiene tope (MCP_STUB_ESPERA, 20 s por defecto): agotarla deja el
    fichero a medias, que es justo lo que necesita el caso "sigue corriendo".
    """
    d = os.path.dirname(lanzador)
    antes = {f: os.path.getmtime(os.path.join(d, f))
             for f in os.listdir(d) if f.endswith('.out')}
    # 2026-09-23: el lanzador se arranca FUERA del Job Object del servidor, a
    # traves de WMI (Win32_Process.Create lo crea el proveedor de WMI, no este
    # proceso), para que el programa y su vigia SOBREVIVAN a la vuelta de
    # paclient como en la realidad. Sin esto no habia forma de medir kill
    # contra un proceso vivo: al llegar el kill el pid ya estaba muerto
    # (OpenProcess -> "El parametro no es correcto"). Si WMI no esta, se
    # vuelve a la ejecucion directa (el caso "sigue corriendo" sigue valiendo).
    cmd = ['powershell', '-NoProfile', '-NonInteractive', '-Command',
           "$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create "
           "-Arguments @{CommandLine='\"%s\"'; CurrentDirectory='%s'}; exit $r.ReturnValue"
           % (lanzador.replace("'", "''"), d.replace("'", "''"))]
    try:
        rc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            timeout=60).returncode
    except Exception:
        rc = -1
    if rc != 0:
        subprocess.run([lanzador], cwd=d,
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
            if flag in ('3', '5'):
                # PAServer arranca el fichero. El ELF de Linux (flag 3) no
                # corre aqui: en su lugar, el gemelo Win64 del lanzador con
                # el MISMO nombre + .exe, para que encuentre su .job
                corrido = destino
                with open(destino, 'rb') as fh:
                    es_elf = fh.read(4) == b'\x7fELF'
                if es_elf:
                    gemelo = os.environ.get('MCP_STUB_RUNJOB_EXE', '')
                    if not os.path.isfile(gemelo):
                        sys.stderr.write('stub: MCP_STUB_RUNJOB_EXE no apunta al '
                                         'lanzador Win64 (McpRunJob.exe)\n')
                        sys.exit(2)
                    corrido = destino + '.exe'
                    shutil.copy(gemelo, corrido)
                ejecutar(corrido)
                # PAServer no deja el fichero arrancado
                for f in {destino, corrido}:
                    try:
                        os.remove(f)
                    except OSError:
                        pass
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
            # paclient admite comodines (el servidor barre *.wait*.exe); un
            # fichero en uso (el vigia de un programa vivo) se queda, como alli
            import glob as _glob
            for p in (_glob.glob(rel(one)) if '*' in one else [rel(one)]):
                try:
                    if os.path.isfile(p):
                        os.remove(p)
                except OSError:
                    pass
sys.exit(0)
