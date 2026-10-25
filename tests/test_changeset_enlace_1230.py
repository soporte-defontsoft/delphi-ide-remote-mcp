# -*- coding: utf-8 -*-
r"""changeset delete de un ENLACE: no copia su destino (A18-M1 de la 1.23).

delphi_changeset delete respalda el contenido ACTUAL en la papelera antes de
borrar (GuardaContenidoActual), y para un symlink/junction TFile.Copy SEGUIRIA
el enlace al DESTINO. MEDIDO contra el build 376c42a (scratchpad sonda_a18): ese
delete ya NO llega a copiar; la puerta de staging (WriteTargetDenied) resuelve
el enlace y, si su destino real sale de las raices, lo niega con GUARD-001 ANTES
de apilarlo: el op no entra y no se copia nada. A18-M1 quedo cerrado con la
unificacion de la puerta de escritura de la principal, no hace falta arreglo.
Esta bateria VIGILA que siga cerrado (su mutante: que WriteTargetDenied dejara
de resolver el enlace). Borrar un enlace COMO enlace es del operador
(delphi_delete); por el changeset, un enlace que sale se niega.

Necesita modo desarrollador (crear un symlink de fichero); si no, NOTA.

  A1 (A18-M1) changeset delete de un symlink a FUERA: NO se compromete (GUARD-001
     al apilar) y el contenido de fuera NO entra en la papelera   [vigila lo cerrado]
  A2 (guarda) changeset delete de un .txt NORMAL: se compromete
  A3 (guarda) changeset delete de un symlink a un .txt de DENTRO: se compromete

Uso:  python tests/test_changeset_enlace_1230.py [ruta-a-DelphiLspMcp.exe]
"""
import glob
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('changeset-enlace-1230')
JAIL = os.path.join(BASE, 'jail')
FUERA = mc.carpeta('changeset-enlace-1230-fuera')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='changeset-enlace', t=300)

open(os.path.join(FUERA, 'secret.txt'), 'w').write('SECRETO_A18 ' + 'x' * 40)


def cs(**kw):
    return s.call('delphi_changeset', kw, t=120)


def borra_cs(path):
    i = mc.id_changeset(cs(command='begin'))
    cs(command='stage', id=i, kind='delete', path=path)
    cs(command='preview', id=i)
    cm = cs(command='commit', id=i)
    cs(command='rollback', id=i)  # no-op si ya se commiteo; limpia si fallo
    return cm


def fuga_en_papelera():
    for p in glob.glob(os.path.join(JAIL, '**', mc.PAPELERA, '**', '*'), recursive=True):
        try:
            if os.path.isfile(p) and b'SECRETO_A18' in open(p, 'rb').read():
                return True
        except OSError:
            pass
    return False


def puede_symlink(link, target):
    try:
        os.symlink(target, link)
        return os.path.islink(link)
    except OSError:
        return False


try:
    link = os.path.join(JAIL, 'enlace.txt')
    if not puede_symlink(link, os.path.join(FUERA, 'secret.txt')):
        print('NOTA: no se puede crear un symlink de fichero (modo desarrollador apagado): A18-M1 no se mide')
    else:
        cm = borra_cs(link)
        check('A1 (A18-M1) changeset delete de un symlink a FUERA: no se compromete y nada de fuera en la papelera',
              'CHSET-025' not in cm and not fuga_en_papelera() and os.path.lexists(link), cm[:300])
        normal = os.path.join(JAIL, 'normal.txt')
        open(normal, 'w').write('contenido normal\n')
        cm = borra_cs(normal)
        check('A2 (guarda) changeset delete de un .txt normal: se compromete',
              'CHSET-025' in cm and not os.path.exists(normal), cm[:300])
        dentro = os.path.join(JAIL, 'dentro-real.txt')
        open(dentro, 'w').write('dentro\n')
        linkdentro = os.path.join(JAIL, 'enlace-dentro.txt')
        os.symlink(dentro, linkdentro)
        cm = borra_cs(linkdentro)
        check('A3 (guarda) changeset delete de un symlink a DENTRO: se compromete',
              'CHSET-025' in cm and not os.path.lexists(linkdentro), cm[:300])
finally:
    s.cierra()
mc.borra(BASE)
mc.borra(FUERA)
mc.fin('changeset delete no copia el destino de un enlace, A18-M1 de la 1.23')
