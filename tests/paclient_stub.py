#!/usr/bin/env python3
"""Stub de paclient.exe para probar remote-run sin PAServer real.
Traduce --put / --get / --Remove a copias sobre una carpeta 'scratch' local
apuntada por MCP_STUB_SCRATCH. Ignora el ProfileName y el resto de flags."""
import os, sys, shutil

SCRATCH = os.environ['MCP_STUB_SCRATCH']

def rel(p):
    return os.path.join(SCRATCH, p.replace('/', os.sep))

for arg in sys.argv[1:]:
    if arg.startswith('--put='):
        spec = arg[len('--put='):]
        for one in spec.split(';'):
            parts = one.split(',')
            src = parts[0]; destdir = parts[1] if len(parts) > 1 else ''
            destname = parts[3] if len(parts) > 3 else os.path.basename(src)
            d = rel(destdir); os.makedirs(d, exist_ok=True)
            shutil.copy(src, os.path.join(d, destname))
    elif arg.startswith('--get='):
        spec = arg[len('--get='):]
        for one in spec.split(';'):
            parts = one.split(',')
            src = rel(parts[0]); destdir = parts[1] if len(parts) > 1 else '.'
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
