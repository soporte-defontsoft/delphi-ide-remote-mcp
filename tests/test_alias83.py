# -*- coding: utf-8 -*-
"""E2E battery: los LUGARES por su alias 8.3, y lo que se pisa o se borra
ENTERO (sexta revision, 28-sep-2026).

A1  la raiz de OTRO workspace anidada en la mia, por su alias corto: no se
    borra (se borraba y se purgaba para siempre); y al reves, declarada en
    8.3 y nombrada larga
A2  una carpeta que CONTIENE un ReadOnlyPaths, por su alias: no se borra
A3  el vault dentro de la raiz, por su alias: ni se edita ni se borra
A4  borrar una unit por su alias 8.3 la saca de su proyecto (el .dpr seguia
    listandola: F1026 en el build)
A5  una referencia (ReadOnlyRoots) declarada en 8.3: la purga del arranque
    no vacia su __delphi-temp
B1  changeset delete tras dos ediciones del dia: la papelera guarda lo
    ULTIMO (la copia diaria era la de la manana)
B2  upload sobre un fichero editado hoy: la copia sellada es la de antes
    de la subida
A6  vault_read cuenta las lineas como delphi_read (sin la fantasma)
A7  un clone que falla no borra una carpeta vacia que ya estaba; uno
    rechazado no deja la suya
A8  una ruta en 8.3 con punto final o ::$DATA: la negativa de la anomalia,
    y nada creado (alargarla le quitaba el punto y creaba "$DATA")
A9  el vault de OTRO workspace, anidado en esta raiz: ni se edita ni se
    borra con este token (solo se miraba el vault del activo)
A10 la purga del arranque no vacia el __delphi-temp de un vault ni el de
    un ReadOnlyPaths de OTRO workspace anidado en esta raiz
A11 las tools vault_* por el alias 8.3: el fichero de gobierno y la
    carpeta excluida siguen siendolo

Si el volumen no da nombres 8.3, los A se dicen NOTA y no se miden.

Usage:  python tests/test_alias83.py [path-to-DelphiLspMcp.exe]
"""
import base64
import ctypes
import glob
import json
import os
import time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('alias83')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(EXEDIR)


corta = mc.corta


# ---- los lugares, con nombres LARGOS que tienen alias 8.3
OTRA = os.path.join(JAIL, 'otherworkspaceroot')           # raiz de otro ws, declarada LARGA
OTRA2 = os.path.join(JAIL, 'anotherworkspaceroot')        # raiz de otro ws, declarada CORTA
CONT = os.path.join(JAIL, 'subfolderlong')
VENDOR = os.path.join(CONT, 'vendor')                     # ReadOnlyPaths
VAULT = os.path.join(JAIL, 'knowledgevault')              # el vault, dentro de la raiz
REFC = os.path.join(JAIL, 'containerlong')
REF = os.path.join(REFC, 'reference')                     # ReadOnlyRoots, declarada CORTA
for d in (OTRA, OTRA2, VENDOR, VAULT, REF):
    os.makedirs(d)
    open(os.path.join(d, 'dato.txt'), 'w').write('no me borres\n')
open(os.path.join(VAULT, 'AGENTS-VAULT.md'), 'w').write('# reglas\n')
TEMP_REF = os.path.join(REF, '__delphi-temp')
os.makedirs(TEMP_REF)
MIGA_REF = os.path.join(TEMP_REF, 'de-la-referencia.txt')
open(MIGA_REF, 'w').write('de la referencia\n')
# A9/A10: el vault de OTRO workspace y un ReadOnlyPaths suyo, anidados aqui
VAULT_OTRO = os.path.join(JAIL, 'vaultdeotro')
os.makedirs(VAULT_OTRO)
open(os.path.join(VAULT_OTRO, 'AGENTS-VAULT.md'), 'w').write('# de otro\n')
RO_OTRO = os.path.join(OTRA, 'soloconsulta')
os.makedirs(RO_OTRO)
MIGAS = []
for _d in (VAULT, VAULT_OTRO, RO_OTRO):
    os.makedirs(os.path.join(_d, '__delphi-temp'), exist_ok=True)
    MIGAS.append(os.path.join(_d, '__delphi-temp', 'miga.txt'))
    open(MIGAS[-1], 'w').write('no me purgues\n')
os.makedirs(os.path.join(VAULT, '.obsidian'))  # A11: la carpeta excluida

HAY83 = all(corta(p) and os.path.basename(corta(p)).lower() != os.path.basename(p).lower()
            for p in (OTRA, OTRA2, CONT, VAULT, REF))

TOK, TOK2 = 'a83', 'otro'
PORT = mc.puerto_libre()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.A83]',
    'Token=%s' % TOK,
    'Roots=%s' % JAIL,
    'ReadOnlyPaths=%s' % VENDOR,
    'ReadOnlyRoots=%s' % (corta(REF) or REF),
    'VaultPath=%s' % VAULT,
    'VaultReadOnly=0',   # A11: las tools vault_* escriben
    'GitRemotes=127.0.0.1',
    '',
    '[Workspace.Otro]',
    'Token=%s' % TOK2,
    'Roots=%s;%s' % (OTRA, corta(OTRA2) or OTRA2),
    'ReadOnlyPaths=%s' % RO_OTRO,
    'VaultPath=%s' % VAULT_OTRO,
    '',
]))

proc = mc.lanza_http(EXE, PORT, mc.entorno())
cli = mc.Http(PORT, TOK, t=180, respaldo_json=True)
cli.session('alias83')


def llama(tool, args):
    r = cli.call_msg(tool, args, 300)
    res = (r or {}).get('result', {})
    return res, res.get('structuredContent', {}), mc.texto(r, True)


def niega(nombre, tool, args, constante, sigue):
    res, sc, t = llama(tool, args)
    check(nombre, res.get('isError') is True and mc.abre(t, constante) and os.path.exists(sigue),
          '%s | %s' % (t[:220], os.path.exists(sigue)))


try:
    if not HAY83:
        print('NOTA: A1-A5 sin medir: este volumen no da nombres 8.3')
    else:
        # A1 la raiz de otro workspace: declarada larga y nombrada corta...
        niega('A1 la raiz de OTRO workspace por su alias 8.3 no se borra',
              'delphi_delete', {'path': corta(OTRA)}, 'SR_MUDANZA_PROTEGIDA_FMT', OTRA)
        niega('A1 ...ni se mueve', 'delphi_move',
              {'path': corta(OTRA), 'dest': os.path.join(JAIL, 'movida')},
              'SR_MUDANZA_PROTEGIDA_FMT', OTRA)
        # ...y declarada corta y nombrada larga (el comparador de dentro)
        niega('A1 ...y declarada en 8.3, por su nombre largo, tampoco',
              'delphi_delete', {'path': OTRA2}, 'SR_MUDANZA_PROTEGIDA_FMT', OTRA2)
        # A2 lo que CONTIENE un ReadOnlyPaths
        niega('A2 una carpeta que contiene un ReadOnlyPaths, por su alias, no se borra',
              'delphi_delete', {'path': corta(CONT)}, 'SR_MUDANZA_PROTEGIDA_FMT', VENDOR)
        # A3 el vault
        AV = os.path.join(corta(VAULT), 'AGENTS-VAULT.md')
        res, sc, t = llama('delphi_textedit', {'path': AV, 'old': '# reglas', 'new': '# otras'})
        check('A3 el vault por su alias no se edita con las tools de codigo',
              res.get('isError') is True and mc.abre(t, 'SR_VAULT_NOT_CODE') and
              open(os.path.join(VAULT, 'AGENTS-VAULT.md')).read() == '# reglas\n', t[:220])
        niega('A3 ...ni se borra', 'delphi_delete', {'path': corta(VAULT)}, 'SR_VAULT_NOT_CODE',
              os.path.join(VAULT, 'AGENTS-VAULT.md'))
        # A5 la purga del arranque ya paso: la referencia declarada en 8.3
        check('A5 la purga del arranque no vacio el __delphi-temp de una referencia declarada en 8.3',
              os.path.exists(MIGA_REF), TEMP_REF)
        # A11 las tools vault_* por el alias 8.3: comparaban el TEXTO
        AVC = os.path.basename(corta(os.path.join(VAULT, 'AGENTS-VAULT.md')))
        res, sc, t = llama('vault_append', {'path': AVC, 'content': 'intruso'})
        check('A11 vault_append por el alias del fichero de gobierno (%s): VAULT governance' % AVC,
              res.get('isError') is True and mc.abre(t, 'SR_VAULT_GOVERNANCE') and
              open(os.path.join(VAULT, 'AGENTS-VAULT.md')).read() == '# reglas\n', t[:200])
        OBC = os.path.basename(corta(os.path.join(VAULT, '.obsidian')))
        if OBC and OBC.lower() != '.obsidian':
            res, sc, t = llama('vault_create', {'path': OBC + '/x.md', 'content': '# x'})
            check('A11 vault_create en .obsidian por su alias (%s): carpeta excluida' % OBC,
                  res.get('isError') is True and
                  mc.abre(t, 'SR_VAULT_ESTA_CARPETA_EXCLUIDA_BACKUPS_FMT') and
                  not os.path.exists(os.path.join(VAULT, '.obsidian', 'x.md')), t[:200])
        else:
            print('NOTA: A11 .obsidian sin medir: no tiene alias 8.3 (%r)' % OBC)

    # A4 una unit por su alias 8.3 sale de su proyecto
    PROY = os.path.join(JAIL, 'proy')
    res, sc, t = llama('delphi_create', {'kind': 'project-console', 'name': 'App', 'dir': PROY})
    DPR = os.path.join(PROY, 'App.dpr')
    res, sc, t = llama('delphi_create', {'kind': 'unit', 'name': 'UProveedorModelo',
                                          'project': os.path.join(PROY, 'App.dproj')})
    UNIT = os.path.join(PROY, 'UProveedorModelo.pas')
    check('A4 fixture: la unit se crea y el .dpr la lista',
          os.path.exists(UNIT) and 'UProveedorModelo' in open(DPR).read(), t[:200])
    UC = corta(UNIT)
    if os.path.exists(UNIT) and UC and os.path.basename(UC).lower() != 'uproveedormodelo.pas':
        res, sc, t = llama('delphi_delete', {'path': UC})
        check('A4 borrar una unit por su alias 8.3 la saca del .dpr',
              not res.get('isError') and not os.path.exists(UNIT) and
              'UProveedorModelo' not in open(DPR).read(), '%s | %s' % (t[:200], open(DPR).read()[:300]))
    else:
        print('NOTA: A4 sin medir: la unit no tiene alias 8.3 (%r)' % UC)

    # A8 alargar una ruta NUNCA cambia a que fichero se refiere: la forma
    # canonica quita el punto final y deshace ::$DATA. En .txt, para que no
    # la pare la negativa de los .pas (TEXT-001) por otro motivo. Solo con
    # un ~ en la ruta se alarga: sin alias, NOTA (no se mediria nada)
    if '~' in corta(CONT):
        for sufijo, motivo in (('Evade.txt.', 'SR_GUARD_NOMBRE_EMPIEZA_TERMINA_PUNTO_FMT'),
                               ('Evade3.txt::$DATA', 'SR_GUARD_RUTA_CONTIENE_FUERA_UNIDAD_FMT')):
            niega('A8 %s por el alias 8.3: la negativa de la anomalia' % sufijo, 'delphi_textedit',
                  {'path': os.path.join(corta(CONT), sufijo), 'create': True, 'content': 'x'},
                  motivo, CONT)
        check('A8 ...y nada creado en la carpeta',
              not [f for f in os.listdir(CONT) if f.startswith(('Evade', '$DATA'))],
              os.listdir(CONT))
    else:
        print('NOTA: A8 sin medir: la carpeta no tiene alias 8.3 (%r)' % corta(CONT))

    # A9 el vault de OTRO workspace, anidado en esta raiz: tampoco es de las
    # tools de codigo (solo se miraba el del activo)
    AVO = os.path.join(VAULT_OTRO, 'AGENTS-VAULT.md')
    res, sc, t = llama('delphi_textedit', {'path': AVO, 'old': '# de otro', 'new': '# mio'})
    check('A9 el vault de otro workspace no se edita con este token',
          res.get('isError') is True and mc.abre(t, 'SR_VAULT_NOT_CODE') and
          open(AVO).read() == '# de otro\n', t[:200])
    niega('A9 ...ni se borra', 'delphi_delete', {'path': VAULT_OTRO}, 'SR_VAULT_NOT_CODE', AVO)
    # A10 la purga del arranque ya paso
    check('A10 la purga del arranque no vacio los temporales de los vaults ni de un '
          'ReadOnlyPaths de otro workspace', all(os.path.exists(m) for m in MIGAS),
          [m for m in MIGAS if not os.path.exists(m)])

    # A6 vault_read: la nota de 3 lineas es de 3 (salia de 4, con un 4| vacio)
    open(os.path.join(VAULT, 'nota.md'), 'w', newline='\n').write('# t\nuno\ndos\n')
    res, sc, t = llama('vault_read', {'path': 'nota.md'})
    check('A6 vault_read: 3 lineas, sin la fantasma del salto final',
          '3|dos' in t and '\n4|' not in t, t[:300])

    # A7 el clone: una carpeta vacia que YA estaba no se borra al fallar (la
    # raiz vacia de otro workspace se borraba), y uno rechazado no deja la suya
    PRE = os.path.join(JAIL, 'ya_estaba_vacia')
    os.makedirs(PRE)
    res, sc, t = llama('delphi_git', {'repo': PRE, 'command': 'clone',
                                      'message': 'http://127.0.0.1:1/x.git'})
    check('A7 un clone que falla no borra la carpeta vacia que ya estaba',
          res.get('isError') is True and os.path.isdir(PRE), t[:200])
    NUEVA = os.path.join(JAIL, 'no_se_crea')
    res, sc, t = llama('delphi_git', {'repo': NUEVA, 'command': 'clone',
                                      'message': 'ftp://127.0.0.1/x.git'})
    check('A7 ...y uno rechazado por su URL no deja su carpeta',
          res.get('isError') is True and not os.path.exists(NUEVA), t[:200])

    # B1 changeset delete tras dos ediciones del dia
    T = os.path.join(JAIL, 't.txt')
    open(T, 'w', newline='\n').write('v1 manana\n')
    llama('delphi_textedit', {'path': T, 'old': 'v1 manana', 'new': 'v2'})
    llama('delphi_textedit', {'path': T, 'old': 'v2', 'new': 'v3 TRABAJO DE TODO EL DIA'})
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    cid = mc.id_changeset(t)
    llama('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'delete', 'path': T})
    llama('delphi_changeset', {'command': 'preview', 'id': cid})
    res, sc, t = llama('delphi_changeset', {'command': 'commit', 'id': cid})
    copias = [open(f).read() for f in mc.copias(JAIL, 't.txt', 'CAJON_BORRADOS')]
    check('B1 changeset delete tras dos ediciones: la papelera guarda lo ULTIMO',
          not os.path.exists(T) and any('v3 TRABAJO' in c for c in copias),
          '%s | %s' % (t[:200], copias))

    # B2 upload sobre un fichero editado hoy
    U = os.path.join(JAIL, 'u.txt')
    open(U, 'w', newline='\n').write('a\n')
    llama('delphi_textedit', {'path': U, 'old': 'a', 'new': 'b'})
    llama('delphi_textedit', {'path': U, 'old': 'b', 'new': 'c de la tarde'})
    res, sc, t = llama('delphi_upload', {'path': U, 'chunkbase64': base64.b64encode(b'nuevo\n').decode()})
    copias = [open(f).read() for f in mc.copias(JAIL, 'u.txt', 'CAJON_SUSTITUIDOS')]
    check('B2 upload sobre un fichero editado hoy: la copia sellada es la de antes de subir',
          open(U).read() == 'nuevo\n' and any('c de la tarde' in c for c in copias),
          '%s | %s' % (t[:200], copias))
finally:
    try:
        proc.kill()
    except Exception:
        pass
    time.sleep(0.5)
    mc.borra(BASE)

mc.fin('test_alias83')
