"""E2E battery: the startup purge reaches EVERY __delphi-temp under a write
root, nested ones included (2026-09-25: a nested one kept 90 captures, 66 MB,
through every restart of the day). And it touches nothing it must not: a
.git, a ReadOnlyPaths folder, a reference project (ReadOnlyRoots), whatever
sits behind a junction, a folder that is not called __delphi-temp.

Usage:  python tests/test_purga_temporales.py [path-to-DelphiLspMcp.exe]
"""
import json, os, shutil, subprocess, sys, tempfile, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Server', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'purga-temporales')
shutil.rmtree(BASE, ignore_errors=True)
ROOT = os.path.join(BASE, 'raiz')
REF = os.path.join(BASE, 'referencia')
FUERA = os.path.join(BASE, 'fuera')

P = F = 0


def check(name, cond, detail=''):
    global P, F
    if cond:
        P += 1
        print('  PASS', name)
    else:
        F += 1
        print('  FAIL', name, '--', str(detail)[:200])


def siembra(*partes):
    p = os.path.join(*partes)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'w').write('x')
    return p


arriba = siembra(ROOT, '__delphi-temp', 'agente', 'desktop', 'cap.png')
anidada = siembra(ROOT, 'proy', 'sub', '__delphi-temp', 'viejo.png')
honda = siembra(ROOT, 'a', 'b', 'c', 'd', '__delphi-temp', 'log.txt')
git = siembra(ROOT, 'proy', '.git', '__delphi-temp', 'no-tocar.txt')
vendor = siembra(ROOT, 'vendor', '__delphi-temp', 'no-tocar.txt')
ref = siembra(REF, 'p', '__delphi-temp', 'no-tocar.txt')
fuera = siembra(FUERA, '__delphi-temp', 'no-tocar.txt')
normal = siembra(ROOT, 'proy', 'temp', 'fichero.txt')  # "temp" no es __delphi-temp
enlace = os.path.join(ROOT, 'enlace')
subprocess.run(['cmd', '/c', 'mklink', '/J', enlace, FUERA], capture_output=True)
check('fixture: junction creado dentro de la raiz apuntando fuera', os.path.isdir(enlace), enlace)

env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = ROOT
env['DELPHI_MCP_READONLY_PATHS'] = 'vendor'
env['DELPHI_MCP_READONLY_ROOTS'] = REF
proc = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True)
proc.stdin.write(json.dumps({'jsonrpc': '2.0', 'id': 0, 'method': 'initialize', 'params': {
    'protocolVersion': '2025-03-26', 'capabilities': {},
    'clientInfo': {'name': 'bateria-purga', 'version': '1'}}}) + '\n')
proc.stdin.flush()
proc.stdout.readline()  # el arranque (y su purga) ya paso
time.sleep(0.5)

check('purga: la temporal de la raiz se vacia', not os.path.exists(arriba), arriba)
check('purga: una ANIDADA se vacia', not os.path.exists(anidada), anidada)
check('purga: una anidada a cinco niveles se vacia', not os.path.exists(honda), honda)
check('purga: la carpeta __delphi-temp se conserva (se vacia, no se borra)',
      os.path.isdir(os.path.dirname(anidada)), os.path.dirname(anidada))
check('protegido: dentro de .git no se toca', os.path.exists(git), git)
check('protegido: ReadOnlyPaths (vendor) no se toca', os.path.exists(vendor), vendor)
check('protegido: un proyecto de referencia no se toca', os.path.exists(ref), ref)
check('protegido: lo que hay tras un junction no se toca', os.path.exists(fuera), fuera)
check('una carpeta "temp" cualquiera no se toca', os.path.exists(normal), normal)

try:
    proc.stdin.close()
except Exception:
    pass
time.sleep(0.5)
proc.kill()
if os.path.isdir(enlace):
    os.rmdir(enlace)  # quita el junction, nunca lo que hay detras
shutil.rmtree(BASE, ignore_errors=True)
print()
print('== purga-temporales battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
