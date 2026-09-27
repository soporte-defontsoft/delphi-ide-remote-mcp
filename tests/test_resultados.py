# -*- coding: utf-8 -*-
"""El RESULTADO de un rechazo lo declara su etiqueta (catalogo de mensajes,
27-sep-2026), y un rechazo es un error para el cliente: isError y un code
en structuredContent. Hasta ese dia, lo que no empezaba por RECHAZADO ni por
error: salia con ok:true aunque la tool no hubiera hecho nada - "Falta
path" en delphi_config y delphi_styles, una plataforma que no existe en
delphi_components. David: "Arreglarlos".

  E1  delphi_styles sin path                      -> INVALID_PARAM
  E2  delphi_styles get sin style                 -> INVALID_PARAM
  E3  delphi_config add-unit sin path             -> INVALID_PARAM
  E4  delphi_config add-searchpath sin path       -> INVALID_PARAM
  E5  delphi_components con plataforma inventada  -> INVALID_PARAM
  E6  y un exito sigue siendo exito (delphi_styles view de un .style bueno)
  E7  un puerto ocupado dice CUAL y que hacer (issue #5: Indy solo decia
      "Could not bind socket." y el operador de la bandeja no sabia mas)
  E8  delphi_read devuelve el fichero TAL CUAL aunque traiga etiquetas con
      resultado: una linea con [CFG-001 DENIED] hacia que la lectura se
      tomara por una negativa y se enmascarara el contenido ('%s:' salia
      '%srv0:', medido 27-sep leyendo Lsp.Texts)

La revision del 27-sep (antes de publicar la 1.7.0) encontro fallos que
salian como EXITO o con el resultado equivocado; cada uno, aqui:
  E9  insert rutina-global que el motor rechaza (un caracter que no cabe en
      CP1252): era un exito que no escribia nada
  E10 un commit de changeset que revienta a mitad (la carpeta de una
      operacion aparece como FICHERO entre el preview y el commit): no
      deshacia lo ya aplicado
  E11 git con exit<>0 es un fallo (salia como exito)
  E12 una subida cuya sha no cuadra es un fallo (iba en "warning", ok:true)
  E13 un fichero que SE LLAMA como una etiqueta se lee como exito (la
      lectura abria con el nombre: un dato)
  E14 sin ruta: INVALID_PARAM y lo dice ("Invalid path: " vacio)
  E15 una tanda que cae porque un ancla no esta es NOT_FOUND (el envoltorio
      decia DENIED siempre)
  E16 compilar un .dproj que no existe es NOT_FOUND (salia INTERNAL)

La segunda revision (27-sep, antes de publicar) encontro mas:
  E17 crear dentro de un FICHERO se niega en el PREVIEW (reventaba en commit)
  E18 un parametro obligatorio que falta es INVALID_PARAM (se trabajaba con
      su valor por defecto: vault_patch sin new_text BORRABA el fragmento)
  E19 una TANDA que revienta a mitad deshace la primera edicion (la dejaba)
  E20 compilar con una configuracion que el proyecto no tiene es NOT_FOUND
      (compilaba en Win64/Relase/ con los ajustes de Base)
  E21 una CARPETA donde va un fichero es INVALID_PARAM (decia "no existe")
  E22 un comando de changeset mal escrito es INVALID_PARAM (decia "ese
      changeset no existe")
  E23 delphi_create con un "project" que no es un proyecto no escribe nada

Usage:  python tests/test_resultados.py [path-to-DelphiLspMcp.exe]
"""
import base64
import json
import os
import subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('resultados')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(EXEDIR)

ESTILO = os.path.join(JAIL, 'Claro.style')
open(ESTILO, 'w').write('object TStyleContainer\n'
                        '  object TLayout\n'
                        '    StyleName = \'boton\'\n'
                        '  end\n'
                        'end\n')
ECO = os.path.join(JAIL, 'eco.txt')
open(ECO, 'w').write('uno [CFG-001 DENIED]\n'
                     "  '%s (%s) lineas %d-%d de %s:'#10 +\n"
                     'Roots=D:\\Projects\\Galatea\n')
DPROJ = os.path.join(JAIL, 'App.dproj')
open(DPROJ, 'w').write('<?xml version="1.0" encoding="utf-8"?>\n'
                       '<Project><PropertyGroup><MainSource>App.dpr</MainSource>'
                       '</PropertyGroup></Project>\n')
U1252 = os.path.join(JAIL, 'U1252.pas')
with open(U1252, 'wb') as fh:
    fh.write('unit U1252;\r\n\r\n// canci\u00f3n\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n'
             .encode('cp1252'))
U1252_ANTES = open(U1252, 'rb').read()
NOTES = os.path.join(JAIL, 'NOTES.md')
open(NOTES, 'w', newline='\n').write('First line.\nSecond line.\n')
NOREPO = os.path.join(JAIL, 'norepo')
os.makedirs(NOREPO)
ETIQUETADO = os.path.join(JAIL, '[OPS-001 DENIED] notas.txt')
open(ETIQUETADO, 'w').write('contenido normal\n')

TOK = 'res'
PORT = mc.puerto_libre()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.Res]',
    'Token=%s' % TOK,
    'Roots=%s' % JAIL,
    '',
]))

proc = mc.lanza_http(EXE, PORT, mc.entorno())
cli = mc.Http(PORT, TOK, t=180, respaldo_json=True)
cli.session('resultados')


def llama(tool, args):
    r = cli.call_msg(tool, args, 300)
    res = (r or {}).get('result', {})
    return res, res.get('structuredContent', {}), mc.texto(r, True)


def rechazo(nombre, tool, args, code, constante):
    res, sc, t = llama(tool, args)
    check(nombre, res.get('isError') is True and sc.get('ok') is False and sc.get('code') == code
          and mc.abre(t, constante), '%s | %s' % (json.dumps(sc)[:160], t[:200]))
    return t


try:
    rechazo('E1 delphi_styles sin path es un error INVALID_PARAM',
            'delphi_styles', {'command': 'view'}, 'INVALID_PARAM', 'SR_SYS_MISSING_PARAM_FMT')
    rechazo('E2 delphi_styles get sin style es un error INVALID_PARAM',
            'delphi_styles', {'command': 'get', 'path': ESTILO}, 'INVALID_PARAM', 'SR_STYLES_NEED_STYLE')
    rechazo('E3 delphi_config add-unit sin path es un error INVALID_PARAM',
            'delphi_config', {'command': 'add-unit', 'project': DPROJ}, 'INVALID_PARAM', 'SR_UNIT_NEED_PATH')
    rechazo('E4 delphi_config add-searchpath sin path es un error INVALID_PARAM',
            'delphi_config', {'command': 'add-searchpath', 'project': DPROJ}, 'INVALID_PARAM',
            'SR_CONFIG_NEED_PATH')
    rechazo('E5 delphi_components con una plataforma inventada es un error INVALID_PARAM',
            'delphi_components', {'platform': 'Amiga500'}, 'INVALID_PARAM', 'SR_COMPONENTS_PLATFORM_FMT')

    res, sc, t = llama('delphi_styles', {'command': 'view', 'path': ESTILO})
    check('E6 y un exito sigue siendo exito', not res.get('isError') and sc.get('ok') is not False, t[:200])

    res, sc, t = llama('delphi_read', {'path': ECO})
    check('E8 delphi_read devuelve el contenido tal cual aunque cite etiquetas con resultado',
          "de %s:'#10" in t and 'Roots=D:\\Projects\\Galatea' in t and 'srv0' not in t, t[-300:])

    # E9: el caracter no cabe en CP1252 -> el motor se niega; eso ES la respuesta
    res, sc, t = llama('delphi_edit', {'path': U1252, 'insert': 'rutina-global',
                                       'code': "procedure Marca;\nbegin\n  Writeln('\u2714');\nend;"})
    check('E9 insert rutina-global rechazado por el motor es un FALLO, y no escribe',
          res.get('isError') is True and sc.get('code') == 'DENIED' and
          mc.abre(t, 'SR_EDIT_CARACTERES_NO_CABEN_FMT') and open(U1252, 'rb').read() == U1252_ANTES,
          '%s | %s' % (json.dumps(sc)[:120], t[:200]))

    # E10: la carpeta de la segunda operacion aparece como FICHERO entre el
    # preview y el commit: lo imprevisible revienta a mitad y todo se deshace
    NUEVA = os.path.join(JAIL, 'nueva')
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    cid = mc.id_changeset(t)
    llama('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'edit', 'path': NOTES,
                               'old': 'Second line.', 'new': 'Second line, cs.'})
    llama('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'create',
                               'path': os.path.join(NUEVA, 'sub.txt'), 'content': 'x'})
    res, sc, t = llama('delphi_changeset', {'command': 'preview', 'id': cid})
    limpio = mc.como_json(t).get('unresolved') == 0
    open(NUEVA, 'w').write('ahora soy un fichero')
    res, sc, t = llama('delphi_changeset', {'command': 'commit', 'id': cid})
    check('E10 un commit que revienta a mitad es un fallo y DESHACE lo aplicado',
          cid != '' and limpio and res.get('isError') is True and
          mc.abre(t, 'SR_CHANGESET_ROLLED_BACK_FMT') and open(NOTES).read() == 'First line.\nSecond line.\n',
          '%s | %s | %r' % (json.dumps(sc)[:120], t[:200], open(NOTES).read()))
    os.remove(NUEVA)

    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    cid2 = mc.id_changeset(t)
    llama('delphi_changeset', {'command': 'stage', 'id': cid2, 'kind': 'create',
                               'path': os.path.join(NOTES, 'sub.txt'), 'content': 'x'})
    res, sc, t = llama('delphi_changeset', {'command': 'preview', 'id': cid2})
    check('E17 crear dentro de un FICHERO se niega en el preview (INVALID_PARAM)',
          mc.abre(t, 'SR_CHANGESET_PADRE_FICHERO_FMT') and mc.resultado(t) == 'INVALID_PARAM',
          '%s | %s' % (json.dumps(sc)[:120], t[:200]))
    llama('delphi_changeset', {'command': 'rollback', 'id': cid2})

    res, sc, t = llama('delphi_git', {'command': 'status', 'repo': NOREPO})
    check('E11 git con exit<>0 es un fallo que lo dice (y trae la salida de git)',
          res.get('isError') is True and mc.abre(t, 'SR_GIT_EXIT_FMT') and 'not a git repository' in t,
          '%s | %s' % (json.dumps(sc)[:120], t[:200]))

    BAD = os.path.join(JAIL, 'subida.bin')
    res, sc, t = llama('delphi_upload', {'path': BAD, 'chunkbase64': base64.b64encode(b'abc').decode(),
                                         'offset': 0, 'sha256': '0' * 64})
    check('E12 una subida cuya sha no cuadra es un fallo (y queda apartada)',
          res.get('isError') is True and mc.abre(t, 'SR_UPLOAD_SHA_MISMATCH_FMT') and
          not os.path.exists(BAD) and os.path.exists(BAD + '.corrupt'),
          '%s | %s' % (json.dumps(sc)[:120], t[:200]))

    res, sc, t = llama('delphi_read', {'path': ETIQUETADO})
    check('E13 un fichero que se llama como una etiqueta se lee como exito',
          not res.get('isError') and 'contenido normal' in t, '%s | %s' % (json.dumps(sc)[:120], t[:200]))

    rechazo('E14 sin ruta: INVALID_PARAM, y dice que falta', 'delphi_read', {'path': ''},
            'INVALID_PARAM', 'SR_GUARD_RUTA_VACIA')

    tanda = json.dumps([{'old': 'First line.', 'new': 'First line!'},
                        {'old': 'ESTA LINEA NO EXISTE', 'new': 'x'}])
    rechazo('E15 una tanda que cae por un ancla que no esta es NOT_FOUND', 'delphi_textedit',
            {'path': NOTES, 'edits': tanda}, 'NOT_FOUND', 'SR_PATCH_EDITS_ROLLED_FMT')

    rechazo('E16 compilar un .dproj que no existe es NOT_FOUND', 'delphi_build',
            {'project': os.path.join(JAIL, 'NoEsta.dproj'), 'platform': 'Win64'}, 'NOT_FOUND',
            'SR_BUILD_DPROJ_NO_EXISTE_FMT')

    rechazo('E18 un parametro obligatorio que falta es INVALID_PARAM (no su valor por defecto)',
            'delphi_hover', {'path': U1252, 'character': 0}, 'INVALID_PARAM', 'SR_SYS_MISSING_PARAM_FMT')

    tanda = json.dumps([{'old': 'interface', 'new': 'interface // uno'},
                        {'old': 'implementation\n\nend.', 'new': 'implementation\n// ✔\nend.'}])
    res, sc, t = llama('delphi_edit', {'path': U1252, 'edits': tanda})
    check('E19 una tanda que revienta a mitad deshace la primera edicion (DENIED, no INTERNAL)',
          res.get('isError') is True and sc.get('code') == 'DENIED' and
          mc.abre(t, 'SR_PATCH_EDITS_ROLLED_FMT') and open(U1252, 'rb').read() == U1252_ANTES,
          '%s | %s' % (json.dumps(sc)[:120], t[:200]))

    PCFG = os.path.join(JAIL, 'Cfg')
    llama('delphi_create', {'kind': 'project-console', 'name': 'Cfg', 'dir': PCFG})
    rechazo('E20 compilar con una configuracion que el proyecto no tiene es NOT_FOUND',
            'delphi_build', {'project': os.path.join(PCFG, 'Cfg.dproj'), 'platform': 'Win64',
                             'config': 'Relase'}, 'NOT_FOUND', 'SR_TEST_CONFIG_FMT')
    check('E20 ...y no queda la carpeta Relase', not os.path.exists(os.path.join(PCFG, 'Win64', 'Relase')),
          os.listdir(PCFG))

    rechazo('E21 una CARPETA donde va un fichero es INVALID_PARAM', 'delphi_textedit',
            {'path': NOREPO, 'old': 'a', 'new': 'b'}, 'INVALID_PARAM', 'SR_LSP_IS_FOLDER_FMT')

    rechazo('E22 un comando de changeset mal escrito es INVALID_PARAM (no "no existe")',
            'delphi_changeset', {'command': 'stauts'}, 'INVALID_PARAM', 'SR_CHANGESET_CMD')

    rechazo('E23 delphi_create con un "project" que no es un proyecto: INVALID_PARAM',
            'delphi_create', {'kind': 'form-vcl', 'name': 'FZ', 'project': ECO}, 'INVALID_PARAM',
            'SR_UNIT_PROJECT_EXT_FMT')
    check('E23 ...y no escribe nada', not os.path.exists(os.path.join(JAIL, 'FZ.pas')), os.listdir(JAIL))

    # un segundo servidor al MISMO puerto que el que ya escucha
    b = subprocess.run([EXE, '--http', str(PORT)], cwd=EXEDIR, capture_output=True, timeout=60,
                       env=mc.entorno())
    err = b.stderr.decode('utf-8', 'replace')
    check('E7 un puerto ocupado dice cual, por que y que hacer (issue #5)',
          b.returncode != 0 and ('port %d' % PORT) in err and 'already in use' in err and
          'Port=' in err, err[-400:])
finally:
    try:
        proc.kill()
    except Exception:
        pass

mc.fin('test_resultados')
