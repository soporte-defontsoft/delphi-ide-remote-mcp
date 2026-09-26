"""E2E battery for v0.71.0-beta - round 9 security re-audit (agent sec9).

What sec9 found after the round-8 trash fixes, and what is pinned here:

  R1  the trash guard matched the literal segment "__delphi-patch", so the NTFS
      8.3 short name "__DELP~1" - which resolves to the SAME directory - walked
      straight past it and reopened writing into another agent's recoverable
      copies (via textedit AND upload). The whole round-8 fix was bypassable
      with an alias. Now every segment guard canonicalises the path first
      (GetLongPathName on the longest existing prefix). The jail itself is left
      on the non-expanded path: a root can legitimately BE a short name
      (DFONTA~1), and expanding only for the segment guards keeps both honest.
  R2  a file renamed to "<x>.by" had its CONTENT read as an owner name, so a
      planted marker made a folder unpurgeable by anyone and showed invented
      owners. A marker now only owns the copy sitting next to it; an orphan or
      a planted .by marks nothing.
  R3  an agent could not purge its own or an orphan .by, so the trash could
      never be left clean. Now an orphan/own marker is sweepable, and restoring
      a copy with delphi_move takes its marker with it.

  And the counter-tests, because a fix that refuses too much is a bug too:
  the literal-path guards, the jail, and the legitimate delete/restore/purge
  flow all still work.

Usage:  python tests/test_round13.py [path-to-DelphiLspMcp.exe]
"""
import os, glob, ctypes
# 'mc' es aqui una copia de la papelera (R3): el modulo entra por sus nombres
from mcp_cliente import carpeta, copia_exe, entorno, Stdio, check, fin

BASE = carpeta('round13')
EXE = copia_exe(BASE)

env = entorno({'DELPHI_MCP_ROOTS': BASE})
srv = Stdio(EXE, env, inicializa=False)
sess = srv.inicializa   # re-handshake con otra identidad (otro / alicia)
call = srv.call


def copies_of(stem):
    return [x for x in glob.glob(os.path.join(
        BASE, '**', '__delphi-patch', '**', stem + '-*'), recursive=True)
        if not x.endswith('.by')]


def short_dir(path):
    buf = ctypes.create_unicode_buffer(1024)
    ctypes.windll.kernel32.GetShortPathNameW(path, buf, 1024)
    return buf.value


# (aqui habia un sleep(0.3) sin motivo: el transporte stdio procesa las
# lineas de una en una y en orden, asi que el initialized ya esta atendido
# cuando llega la primera llamada - y el re-handshake de 'alicia', mas
# abajo, nunca lo tuvo y su identidad se aplica igual)
sess('otro')

# ---- R1: the 8.3 short-name alias must not dodge the trash guard ----------
open(os.path.join(BASE, 'victima.txt'), 'w').write('de otro\n')
call('delphi_delete', {'path': os.path.join(BASE, 'victima.txt')})
copy = copies_of('victima.txt')[0]
short = short_dir(os.path.join(BASE, '__delphi-patch'))
has83 = '~' in os.path.basename(short)
# SOLO el tramo de la papelera en 8.3, el resto en largo como la raiz. Antes
# se acortaba la ruta ENTERA (.../Temp/DELPHI~1/round13/__DELP~1): esa ya
# no casa con la raiz de la jaula, y los tres R1 los paraba la JAULA ("FUERA
# de los workspaces"), no la guarda de la papelera que dicen medir.
shortcopy = copy.replace(os.path.join(BASE, '__delphi-patch'),
                         os.path.join(BASE, os.path.basename(short)))


def por_la_papelera(r):
    """Rechazado por la guarda de la PAPELERA, no por otra puerta."""
    return 'RECHAZADO' in r and 'es la papelera' in r and 'FUERA de los workspaces' not in r


import base64
if has83:
    r = call('delphi_textedit', {'path': shortcopy, 'old': 'de otro', 'new': 'HIJACK'})
    check('R1 textedit via 8.3 (__DELP~1) rechazado',
          por_la_papelera(r) and open(copy).read().strip() == 'de otro', r[:160])
    r = call('delphi_upload', {'path': shortcopy,
                               'chunkbase64': base64.b64encode(b'X').decode(), 'offset': 0})
    check('R1 upload via 8.3 rechazado',
          por_la_papelera(r) and open(copy).read().strip() == 'de otro', r[:160])
    r = call('delphi_move', {'path': os.path.join(BASE, 'victima.txt'),
                             'dest': shortcopy.replace('victima.txt-', 'inj-')})
    check('R1 move DENTRO de la papelera via 8.3 rechazado', por_la_papelera(r), r[:160])
else:
    print('SKIP R1 - el volumen no genera nombres 8.3')

# the literal path is of course still guarded
r = call('delphi_textedit', {'path': copy, 'old': 'de otro', 'new': 'X'})
check('R1b la papelera por su nombre literal sigue protegida',
      por_la_papelera(r) and open(copy).read().strip() == 'de otro', r[:160])

# ---- R2: a planted .by must not own anything ----------
open(os.path.join(BASE, 'trampa'), 'w').write('carpeta con trampa\n')
os.makedirs(os.path.join(BASE, 'zona'), exist_ok=True)
open(os.path.join(BASE, 'zona', 'real.txt'), 'w').write('mio de otro\n')
call('delphi_delete', {'path': os.path.join(BASE, 'zona', 'real.txt')})
rc = copies_of('real.txt')[0]
# plant a lone .by (no sibling copy) with a fake owner, next to my own copy
planted = os.path.join(os.path.dirname(rc), 'plantado.by')
open(planted, 'w').write('fantasma')
folder = os.path.dirname(os.path.dirname(rc))  # ...\<date>
r = call('delphi_delete', {'path': folder, 'purge': True})
check('R2 un .by huerfano/plantado NO bloquea la purga de la carpeta',
      'PURGADO' in r and not os.path.exists(rc), r[:180])

# ---- R3: orphan / own markers are sweepable; legit restore is clean --------
open(os.path.join(BASE, 'mio.txt'), 'w').write('mio\n')
call('delphi_delete', {'path': os.path.join(BASE, 'mio.txt')})
mc = copies_of('mio.txt')[0]
by = mc + '.by'
check('R3 al borrar, la copia lleva su marcador', os.path.exists(by), by)
r = call('delphi_move', {'path': mc, 'dest': os.path.join(BASE, 'mio_vuelto.txt')})
check('R3 restaurar con move barre el .by (no deja huerfano)',
      'MOVIDO' in r and not os.path.exists(by) and not os.path.exists(mc), r[:120])

# an orphan .by left around: its owner can purge it
open(os.path.join(BASE, 'x.txt'), 'w').write('x\n')
call('delphi_delete', {'path': os.path.join(BASE, 'x.txt')})
xc = copies_of('x.txt')[0]
os.remove(xc)  # copy gone, marker orphaned
r = call('delphi_delete', {'path': xc + '.by', 'purge': True})
check('R3 un .by huerfano se puede purgar',
      'PURGADO' in r and not os.path.exists(xc + '.by'), r[:150])

# ---- counter-tests: nothing over-tightened ----------
# still cannot purge someone else's LIVE copy or its marker
open(os.path.join(BASE, 'suyo.txt'), 'w').write('suyo\n')
sess('alicia')
call('delphi_delete', {'path': os.path.join(BASE, 'suyo.txt')})
ac = copies_of('suyo.txt')[0]
sess('otro')
r = call('delphi_delete', {'path': ac, 'purge': True})
check('contra: no purgo la copia VIVA de otro agente',
      'RECHAZADO' in r and 'alicia' in r and os.path.exists(ac), r[:180])
r = call('delphi_delete', {'path': ac + '.by', 'purge': True})
check('contra: ni su marcador vivo',
      'RECHAZADO' in r and os.path.exists(ac + '.by'), r[:180])
# ...but the owner still can
sess('alicia')
r = call('delphi_delete', {'path': ac, 'purge': True})
check('contra: el dueno SI purga la suya',
      'PURGADO' in r and not os.path.exists(ac), r[:150])
# the jail still holds
r = call('delphi_read', {'path': 'C:\\Windows\\win.ini'})
check('contra: la carcel sigue firme', 'RECHAZADO' in r and 'FUERA de los workspaces' in r, r[:120])
# a normal delete + restore round trip still works
open(os.path.join(BASE, 'ida.txt'), 'w').write('ida\n')
r = call('delphi_delete', {'path': os.path.join(BASE, 'ida.txt')})
check('contra: borrar sigue funcionando', 'BORRADO' in r, r[:120])
ic = copies_of('ida.txt')[0]
r = call('delphi_move', {'path': ic, 'dest': os.path.join(BASE, 'ida.txt')})
check('contra: restaurar sigue funcionando',
      'MOVIDO' in r and os.path.exists(os.path.join(BASE, 'ida.txt')), r[:120])

srv.mata()
fin('round-13 battery')
