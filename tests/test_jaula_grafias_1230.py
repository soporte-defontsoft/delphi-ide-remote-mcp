# -*- coding: utf-8 -*-
r"""H1 (1.23): la jaula decide "dentro de la raiz?" con una comparacion de rutas.
Hasta r1222ci lo hacia con StartsText (lingueistica, con la config regional del
usuario), que daba por DENTRO el hermano de FUERA cuyo nombre NTFS trata como
entrada DISTINTA -la raiz con la eszett minuscula (U+00DF) y el hermano con la
MAYUSCULA (U+1E9E), o el par U+01C5 / U+01C4- y se leia y se escribia fuera de la
raiz. Con el juez ORDINAL (RutaDentroDe / SameFileName, el del sistema de
ficheros) ya no: solo yerra hacia "fuera".

Cada pareja: la raiz es la grafia MINUSCULA (el unico sitio de la jaula) y el
hermano es la MAYUSCULA, creado FUERA con un secreto dentro. Leer y crear en el
hermano -> GUARD-002 (SR_JAIL_FMT) y nada escrito fuera; leer de DENTRO de la
raiz se sirve (no GUARD-002). ROJA contra r1222ci y contra la 1.22.1 publicada
(es la sonda_raiz_lingu del peer, llevada a bateria). argv[1] = exe (produccion
por defecto). Los nombres van por punto de codigo para que el fuente quede en
ASCII.
"""
import os
import mcp_cliente as mc

# (minuscula = la raiz, mayuscula = el hermano de fuera, etiqueta)
PAREJAS = [
    ('stra' + chr(0x00DF) + 'e', 'stra' + chr(0x1E9E) + 'e', 'eszett U+00DF / U+1E9E'),
    (chr(0x01C5) + 'x', chr(0x01C4) + 'x', 'U+01C5 / U+01C4'),
]

BASE = mc.carpeta('jaula-grafias')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

try:
    for minus, mayus, etiqueta in PAREJAS:
        RAIZ = os.path.join(BASE, minus)
        FUERA = os.path.join(BASE, mayus)
        os.makedirs(RAIZ, exist_ok=True)
        os.makedirs(FUERA, exist_ok=True)
        mc.check('%s: la raiz y el hermano de fuera son entradas DISTINTAS para NTFS (si no, no se mide nada)' % etiqueta,
                 not os.path.samefile(RAIZ, FUERA), (RAIZ, FUERA))
        open(os.path.join(FUERA, 'secreto.txt'), 'w', encoding='utf-8').write('de fuera\n')
        nuevo = os.path.join(FUERA, 'nuevo.txt')
        srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': RAIZ}), nombre='jaula-grafias', t=120)
        try:
            r = srv.call('delphi_read', {'path': os.path.join(FUERA, 'secreto.txt')})
            mc.check('%s: leer el hermano de FUERA -> GUARD-002, sin filtrar el secreto' % etiqueta,
                     mc.abre(r, 'SR_JAIL_FMT') and 'de fuera' not in r, r[:200])
            r = srv.call('delphi_textedit', {'path': nuevo, 'create': True, 'content': 'x'})
            mc.check('%s: crear en el hermano de FUERA -> GUARD-002 y nada escrito fuera' % etiqueta,
                     mc.abre(r, 'SR_JAIL_FMT') and not os.path.exists(nuevo), (r[:200], os.path.exists(nuevo)))
            r = srv.call('delphi_read', {'path': os.path.join(RAIZ, 'nada.txt')})
            mc.check('%s: DENTRO de la raiz se sirve, no GUARD-002 (la jaula no niega lo suyo)' % etiqueta,
                     not mc.abre(r, 'SR_JAIL_FMT'), r[:200])
        finally:
            srv.cierra()
finally:
    mc.borra(BASE)
mc.fin('la jaula compara rutas con el juez ordinal: el hermano de fuera por otra grafia no entra (H1)')
