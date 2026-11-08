# -*- coding: utf-8 -*-
"""EL juez del texto de una ruta de delphi_config, por sus tres llamadores (B21 de la 1.29).

TextoDeRutaVetado junta lo que eran tres copias del par "largo + caracteres" en
Mcp.Tools.Config, cada una con su tope escrito a mano: el search path (400, admite
&), el fichero desplegado (400, sin &) y su carpeta remota (200, sin & ni ':').
Es un cambio de forma: esta bateria es la GUARDA de cada camino que ya existia
(regla 7), y pasa igual contra el build anterior. Ninguna bateria media los topes.

  S1 add-searchpath de 401 caracteres: CFG-016, nada escrito
  S2 ...de 400: no es CFG-016 (pasa al juez siguiente)
  S3 ...una carpeta R&D que existe: se anade (el & se admite en un search path)
  D1 add-deployfile de 401 caracteres: CFG-016, nada escrito
  D2 ...de 400: no es CFG-016
  D3 ...un fichero R&D.txt que existe: CFG-016 (lo que viaja al destino no lleva &)
  R1 remotedir de 201 caracteres: su negativa, nada escrito
  R2 ...de 200: se anade
  R3 ...con ':': su negativa

Uso:  python tests/test_texto_de_ruta_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('test_texto_de_ruta_129')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def igual(p, antes):
    return open(p, 'rb').read() == antes


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='test-texto-de-ruta', t=120)
try:
    PDIR = os.path.join(JAIL, 'proy')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Tr', 'dir': PDIR})
    assert mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:300]
    DPROJ = os.path.join(PDIR, 'Tr.dproj')
    os.makedirs(os.path.join(PDIR, 'R&D'))
    DEP = os.path.join(PDIR, 'datos.txt')
    with open(DEP, 'wb') as f:
        f.write(b'x\r\n')
    with open(os.path.join(PDIR, 'R&D.txt'), 'wb') as f:
        f.write(b'x\r\n')

    def config(**kw):
        a = {'project': DPROJ}
        a.update(kw)
        return srv.call('delphi_config', a)

    a = open(DPROJ, 'rb').read()
    r = config(command='add-searchpath', path='a\\' * 200 + 'b')
    check('S1 add-searchpath de 401 caracteres: CFG-016, nada escrito',
          mc.abre(r, 'SR_CONFIG_PATH_CHARS') and igual(DPROJ, a), r[:300])
    r = config(command='add-searchpath', path='a\\' * 200)
    check('S2 ...de 400: no es CFG-016 (pasa al juez siguiente)',
          mc.rechazado(r) and not mc.es(r, 'SR_CONFIG_PATH_CHARS') and igual(DPROJ, a), r[:300])
    r = config(command='add-searchpath', path='R&D')
    check('S3 ...una carpeta R&D que existe: se anade',
          mc.abre(r, 'SN_CONFIG_PATH_ADDED_FMT') and 'R&amp;D' in open(DPROJ, 'rb').read().decode('utf-8-sig'),
          r[:300])

    a = open(DPROJ, 'rb').read()
    r = config(command='add-deployfile', platform='Win64', path='a\\' * 200 + 'b')
    check('D1 add-deployfile de 401 caracteres: CFG-016, nada escrito',
          mc.abre(r, 'SR_CONFIG_PATH_CHARS') and igual(DPROJ, a), r[:300])
    r = config(command='add-deployfile', platform='Win64', path='a\\' * 200)
    check('D2 ...de 400: no es CFG-016',
          mc.rechazado(r) and not mc.es(r, 'SR_CONFIG_PATH_CHARS') and igual(DPROJ, a), r[:300])
    r = config(command='add-deployfile', platform='Win64', path='R&D.txt')
    check('D3 ...un fichero R&D.txt que existe: CFG-016 (lo que viaja al destino no lleva &)',
          mc.abre(r, 'SR_CONFIG_PATH_CHARS') and igual(DPROJ, a), r[:300])

    r = config(command='add-deployfile', platform='Win64', path=DEP, remotedir='r\\' * 100 + 'x')
    check('R1 remotedir de 201 caracteres: su negativa, nada escrito',
          mc.rechazado(r) and mc.es(r, 'SR_CONFIG_REMOTEDIR_CHARS') and igual(DPROJ, a), r[:300])
    r = config(command='add-deployfile', platform='Win64', path=DEP, remotedir='a:b')
    check('R3 ...con \':\': su negativa',
          mc.rechazado(r) and mc.es(r, 'SR_CONFIG_REMOTEDIR_CHARS') and igual(DPROJ, a), r[:300])
    r = config(command='add-deployfile', platform='Win64', path=DEP, remotedir='r\\' * 100)
    check('R2 ...de 200: se anade',
          not mc.rechazado(r) and not mc.es(r, 'SR_CONFIG_REMOTEDIR_CHARS') and not igual(DPROJ, a), r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('el juez del texto de una ruta de delphi_config, B21 de la 1.29')
