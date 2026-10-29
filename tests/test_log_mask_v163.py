# -*- coding: utf-8 -*-
"""V163 (1.23.1): the log masker reads keys the way the binder does.

The transports log the raw request body before the tool gate runs, masking the
value of secret-named keys. The masker matched the LITERAL key ("password",
"token"...), but the binder normalizes keys (NormalizeKey: lowercase, drop '_'),
so "pass_word":"x" and "pa\\u0073sword":"x" - bound as Password - were written in
cleartext in the log. The masker now parses the body and masks the value of any
key whose normalized form is a secret (falling back to the literal scan for a
body that is not valid JSON).

  P1 a secret passed as "pass_word" is NOT in the log (RED against 06f59ce: it is)
  P2 (control) the literal "password" is masked too (was already)
  P3 (control) a non-secret value ("name") is still readable in the log

The instance has its OWN logs next to its exe; production is untouched.

Usage:  python tests/test_log_mask_v163.py [path-to-DelphiLspMcp.exe]
"""
import os, sys, glob, time
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('log_mask_v163')
WORK = os.path.join(BASE, 'work')
os.makedirs(WORK)
EXE = mc.copia_exe(os.path.join(BASE, 's'), src=exe_src)
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': WORK}), nombre='v163', t=120)
try:
    S.call('delphi_paserver', {'command': 'add-profile', 'name': 'perfilVISIBLE', 'platform': 'Linux64',
                               'host': '192.0.2.9', 'pass_word': 'probe123SECRETO'})
    S.call('delphi_paserver', {'command': 'add-profile', 'name': 'q', 'platform': 'Linux64',
                               'host': '192.0.2.9', 'password': 'probe456CONTROL'})
finally:
    S.cierra()
time.sleep(0.5)
texto = ''
for f in glob.glob(os.path.join(os.path.dirname(EXE), 'logs', '*.log')):
    try:
        texto += open(f, encoding='utf-8', errors='replace').read()
    except Exception:
        pass

check('P1 (V163) un secreto con clave "pass_word" NO sale en claro en el log (como lo lee el binder)',
      'probe123SECRETO' not in texto, texto[-400:])
check('P2 control: la clave literal "password" tambien queda enmascarada',
      'probe456CONTROL' not in texto, texto[-400:])
check('P3 control: un valor NO secreto ("name") sigue legible en el log (no se sobre-enmascara)',
      'perfilVISIBLE' in texto, texto[-400:])

mc.borra(BASE)
mc.fin('V163 log mask battery')
