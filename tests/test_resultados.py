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
  Tercera revision:
  E24 delphi_package con un outfile que no es .zip (lo sustituia por el zip)
  E25 git diff --quiet con diferencias no es un fallo (exit=1 es su respuesta)
  E26 crear DENTRO de un fichero es INVALID_PARAM (salia INTERNAL)
  E27 changeset: crear donde hay una CARPETA se niega en el preview
  E28 changeset sin id es INVALID_PARAM
  E29 compilar una CARPETA es INVALID_PARAM (decia "no existe")
  E30 una entrada con "new" que no es texto (dejaba la linea en blanco con OK)
  E31 createunit con un eol que no existe (creaba en CRLF)
  E32 set-sdk / set-profile sin valor (quitaban el pin con exito)
  E33 dos agentes a la vez sobre un fichero: lo que cada uno recibio como OK
      esta en el disco (la tanda de delphi_edit no tomaba el cerrojo)
  E34 un commit y un delphi_create del mismo fichero a la vez: lo que recibio
      OK esta en el disco (el deshacer borraba lo que delphi_create creo)
  E35 una tanda de delphi_textedit sobre una CARPETA es INVALID_PARAM (decia
      "no existe, crealo con create=true")
  E36 delphi_package: un FICHERO en el camino del outfile es INVALID_PARAM
      (salia INTERNAL); una carpeta nueva se crea; un .zip que ya estaba se
      copia antes de pisarlo
  E37 una ruta RELATIVA es INVALID_PARAM (decia "fuera de la jaula", DENIED)
  E38 un entero negativo es INVALID_PARAM en cualquier tool (se aceptaba
      en silencio como el valor por defecto en delphi_read)
  E39 delphi_search con una mascara que no casa con nada lo dice
  E40 delphi_help no anuncia vault_* en un workspace sin vault
  E41 createunit eol=lf sin content escribe LF (decia LF y escribia CRLF)
  E42 git diff --exit-code con cambios no hereda las pistas de fallo
  E43 un fichero que otro proceso tiene abierto es DENIED (era INTERNAL)
  E44 insert rutina-global visible=true: si la declaracion no se puede,
      no se escribe nada (salia exito con la rutina privada)
  E45 el deshacer de un commit quita las carpetas que creo
  E46 un FICHERO donde el servidor guarda sus copias es DENIED, no
      INVALID_PARAM (la ruta del agente era buena)
  E47 una entrada con "new": null es "sin new" (delete sigue borrando)
  Quinta revision:
  E48 delete/move con la papelera enlazada FUERA de la jaula: DENIED, nada
      se mueve (la copia caia en la victima)
  E50 upload que no puede copiar lo que pisa: DENIED y no escribe
  E51 stdio: el UTF-8 del cliente llega entero (se leia con la pagina de
      la consola)
  E52 una entrada de "edits" con un booleano o un entero que no lo es
  E53 un texto que llega como lista es INVALID_PARAM; "edits" como lista si
  E54 un .groupproj que otro tiene abierto es DENIED (SYS-027)
  E55 una ruta de Linux o relativa: INVALID_PARAM en la entrada
  E56 modos de delphi_edit que no combinan: INVALID_PARAM
  E57 createunit con un content que no casa: INVALID_PARAM, nada creado
  E58 delphi_create con un proyecto que no se deja registrar: nada creado
  E59 borrar una unit con un proyecto que no se deja tocar: la unit sigue
  E60 styles lint con un project que no existe: NOT_FOUND
  E61 leer un fichero vacio es un exito; sin linea fantasma al final
  E62 delphi_list includetrash con mascaras solapadas: cada fichero una vez
  E63 un proyecto VCL para Linux64 se niega antes de compilar
  E64 un move rechazado no deja copia en la papelera
  E65 old == new: UNCHANGED, sin escribir ni copiar (las dos gemelas)
  E66 textedit con un atline equivocado y ancla unica: se niega
  E67 set-sdk en Win64: INVALID_PARAM
  E69 las tools del LSP: carpeta, no esta, no es Pascal - una regla
  E70 un paquete que se cae a medias no deja su .tmp
  E71 el proyecto de tests lee su linea de comandos (--run:)
  E72 una relativa en una tool que resuelve ANTES de preguntar a la jaula
      (package, upload): la para la puerta, la ultima de sus reglas
  E73 barra inicial / "C:x": ni relativa al proyecto ni completa (config path,
      unit suelta): INVALID_PARAM, no resuelta contra la unidad del proceso
  E74 la papelera por su alias 8.3 (__DELP~1) es la papelera tambien para
      delphi_delete (un lector, EnPapelera; antes miraba el texto)
  E75 la RAIZ por su alias 8.3 sigue siendo la raiz: no se borra (GUARD-014)
  E77 una tanda o un changeset que no cambian nada: UNCHANGED, sin escribir
      ni prometer copias (decian APPLIED / COMMIT COMPLETE)
  E78 un form con su designer ya en disco: nada creado (quedaba el .pas)
  E79 un fichero de SOLO LECTURA (atributo): SYS-029, no "otro lo tiene"
  E80 borrar una carpeta que no se puede mover: sus proyectos intactos
  E81 LSP-004 cuenta las lineas como delphi_read (sin la fantasma)
  E82 buscar en una carpeta con UN fichero bloqueado: los aciertos de los
      demas y la nota SEARCH-003 (se caia entera con SYS-027)
  E83 delphi_config con un parametro que no es de su comando: CFG-110
      (set-output con path= contestaba exito poniendo el valor por defecto)
  E84 un UNC que no es de ningun sitio declarado: GUARD-002 al momento, sin
      abrir SMB hacia ese host (21 s por llamada), tambien con un ~ dentro
  E85 changeset delete-line con old (lo compara): CHSET-030 lo rechazaba
  E86 delete-line pasada del final: el preview no dice limpio (se aceptaba y
      solo quitaba el salto final)
  E87 buscar donde TODO lo que casa esta bloqueado: SEARCH-003 sin SEARCH-002
  E88 delphi_config: section con su valor por defecto no es CFG-110; otro si;
      view de un .groupproj con section tambien
  E89 delphi_create con un parametro que no es de su kind: CREATE-035
  E90 delphi_edit / textedit con un parametro que no es del modo: EDIT-115
      (code sin insert, eol sin create, atline con edits)
  E91 la forma de la ruta: comodin GUARD-024, fichero con separador final
      GUARD-025 (leer y crear; no queda una carpeta con su nombre)
  E92 changeset delete de un fichero +R: SYS-029 y sin copia en deleted
  E93 borrar una junction a un antepasado (era "dentro de si misma")
  E94 protocolo: id 1.5 / null -> SYS-031, method null -> SYS-032, name null
      no es la tool "null", el 404 lleva el id, el GET con sesion muerta es
      404, el 202 va sin cuerpo, SYS-015 de una tool sin parametros
  E95 dos copias del mismo fichero en el mismo golpe de reloj (~15 ms): la
      segunda tenia el mismo nombre sellado y la operacion fallaba (E95b,
      determinista: los sellos de los proximos 400 ms ocupados)
  Octava revision - los checks que les faltaban a arreglos de la SEPTIMA
  (E95b, E96-E101, E103: contra la septima salen verdes, es lo esperado):
  E96 delphi_delete de un fichero +R: SYS-029 (lo borraba)
  E97 una carpeta que no se deja mover no deja su cajon vacio
  E98 una tanda cuyo BLOQUE no cambia nada: EDIT-114
  E99 delphi_package sobre un .zip +R: SYS-029
  E100 buscar con CR sueltos: las lineas como delphi_read
  E101 //?/ con barras normales: GUARD-022
  E103 initialize con clientInfo que no es objeto
  ...y los de los arreglos de la OCTAVA (rojos contra la septima):
  E102 un bloque en un fichero mixto: el salto dominante, como una linea
  E104 mover una junction: el enlace, sin copia de lo de detras
  E105-E107 la regla de parametros en styles, git y changeset
  E108 un nombre de mas de 255: GUARD-026; E109 GUARD-010 de "..."
  E110 un kind que no existe: CREATE-034 antes que CREATE-035
  E111 delete-line compara old con la regla del motor; E112 el preview
      ve el ancla como el motor
  E113 /files: filename* y la ruta tal cual; E114 lo que no se contesta
      (una regla para HTTP y stdio) y lo mal formado, -32600
  E115 una sesion muerta no vuelve en la cabecera; el GET sin flujo, 404
  E116 un recurso que no existe: -32002; E117 los enteros, integer
  E118 un .dproj en LF sigue en LF; E119 deshacer el borrado de una unit
      no deja la copia del form; E120 LIST-008 cuenta las marcas aparte
  E121 project-test en ingles; E122 el zip sin la papelera
  E123 mover una unit con su form: todo o nada (MOVE-017)
  E124 / E125 el destino de un move y el create de un changeset con
      separador final: GUARD-025
  E127 la sesion cerrada para hacer sitio: SYS-033
  E76 un fichero de dentro por su alias 8.3 se lee (la jaula decia "fuera")
  Novena revision:
  E128 REGRESION de la octava: un new de varias lineas en un fichero CRLF
      metia LF; E129 add-unit / create con project en un .dproj LF
  E130 renombrar una unit con usuarios en CR sueltos; E131 un proyecto
      bloqueado no es "ninguno la lista" (unit y carpeta)
  E132 un UNC con prefijo de dispositivo en un .dpr, sin SMB; E133 .dfm y .fmx, todo o nada;
      E134 renombrar una unit +R se dice antes; E135 / E136 un move o una
      copia que fallan no dejan carpetas ni copia a medias; E137 restaurar
      con el form bloqueado conserva la marca; E138 la copia de seguridad
      no sigue enlaces; E139 occurrence con la regla del motor; E140 el
      create de un changeset con CR sueltos; E141 el preview avisa del +R
      de un edit; E142 GROUP-005 dice lo que falta; E92b la regla del commit
  Decima revision:
  E143 el commit de un changeset mueve el atline solo por lo cambiado ENCIMA
      (borraba o editaba la linea equivocada con COMMIT COMPLETE); E144 el
      rename en un .dproj LF; E145 el +R de un delete-line en el preview; E146
      renombrar una unit con su .dpr bloqueado; E147 una junction rota sobrevive a
      un move que falla; E148 EDIT-078 sin consejo Pascal en un fichero de texto
  E149-E151 los deshaceres quitan lo suyo aunque traiga el +R del original, y
      el original vuelve con su +R (changeset, copy=true, la copia de seguridad);
      E152 la ultima unit de un .dpk/.dpr se va con su clausula, y add-unit la
      estrena; E153 una cabecera con directivas se reescribe, y MOVE-018 si no
      esta; E154 SYS-018 no dice "the unit is back"
  1.7.1 (la lista de la decima, medida contra la 1.7.0 en produccion):
  E155 un bloque hasta la ultima linea no anade el salto final; E156 un old de
      varias lineas se niega al apilar; E157 SYS-029 sin copia diaria; E158 la
      nota nombra .dfm y .fmx; E159 textedit old sin new dice BLANKED; E160 la
      copia de un +R es del agente; E161 bearer en minusculas; E162 nombres
      reservados (GUARD-027); E163 rutina-global repetida avisa (EDIT-116); E164
      delphi_edit de un .pas con NUL; E165 minimum 0 en el esquema; E167 junction
      al antepasado del destino en copy=true; E168 lo que no va con el comando en
      test/designer/adb/paserver; E169 el preview ENSAYA con el motor

Usage:  python tests/test_resultados.py [path-to-DelphiLspMcp.exe]
"""
import base64
import datetime
import json
import os
import re
import stat
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('resultados')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
# la jaula vive bajo %TEMP%: con una ruta larga (~200 caracteres) seis checks
# salen rojos por MAX_PATH (E138 con MOVE-012 "nombre demasiado largo") y no
# por lo que miden; se dice, para no perseguir un fantasma (decima revision)
if len(JAIL) > 150:
    print('NOTA: la jaula tiene %d caracteres (%s): los checks de rutas largas pueden '
          'fallar por MAX_PATH y no por lo que miden; TEMP mas corto' % (len(JAIL), JAIL))
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
    check('E6 y un exito sigue siendo exito',
          t.strip() != '' and not mc.fallo(t) and not res.get('isError') and sc.get('ok') is not False,
          t[:200])

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

    # ---- tercera revision ----
    NOTAS = os.path.join(JAIL, 'notas.txt')
    open(NOTAS, 'w').write('mis notas\n')
    rechazo('E24 delphi_package con un outfile que no es .zip: INVALID_PARAM', 'delphi_package',
            {'dir': NOREPO, 'outfile': NOTAS}, 'INVALID_PARAM', 'SR_PACKAGE_OUTFILE_ZIP_FMT')
    check('E24 ...y las notas siguen siendo las notas', open(NOTAS).read() == 'mis notas\n',
          open(NOTAS, 'rb').read()[:20])

    GREPO = os.path.join(JAIL, 'grepo')
    os.makedirs(GREPO)
    llama('delphi_git', {'repo': GREPO, 'command': 'init'})
    llama('delphi_git', {'repo': GREPO, 'command': 'config', 'args': 'user.name', 'message': 'Probe Bot'})
    llama('delphi_git', {'repo': GREPO, 'command': 'config', 'args': 'user.email', 'message': 'probe@example.com'})
    open(os.path.join(GREPO, 'a.txt'), 'w').write('uno\n')
    llama('delphi_git', {'repo': GREPO, 'command': 'add', 'args': 'a.txt'})
    res, sc, t = llama('delphi_git', {'repo': GREPO, 'command': 'commit', 'message': 'uno'})
    open(os.path.join(GREPO, 'a.txt'), 'w').write('dos\n')
    res, sc, t = llama('delphi_git', {'repo': GREPO, 'command': 'diff', 'args': '--quiet'})
    check('E25 git diff --quiet con diferencias es un exito que lo dice (exit=1)',
          not res.get('isError') and t.startswith('exit=1') and mc.es(t, 'SN_GIT_DIFF_HAY_CAMBIOS'),
          '%s | %s' % (json.dumps(sc)[:120], t[:200]))

    rechazo('E26 crear DENTRO de un fichero es INVALID_PARAM (salia INTERNAL)', 'delphi_textedit',
            {'path': os.path.join(ECO, 'x.txt'), 'create': True, 'content': 'x'}, 'INVALID_PARAM',
            'SR_GUARD_FICHERO_EN_RUTA_FMT')

    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    cid3 = mc.id_changeset(t)
    # se niega ya al APILAR (octava revision: stage mira lo que el preview)
    res, sc, t = llama('delphi_changeset', {'command': 'stage', 'id': cid3, 'kind': 'create',
                                            'path': NOREPO, 'content': 'x'})
    check('E27 changeset: crear donde hay una CARPETA se niega al apilar (INVALID_PARAM)',
          cid3 != '' and mc.abre(t, 'SR_LSP_IS_FOLDER_FMT') and mc.resultado(t) == 'INVALID_PARAM',
          '%s | %s' % (json.dumps(sc)[:120], t[:200]))
    llama('delphi_changeset', {'command': 'rollback', 'id': cid3})

    rechazo('E28 changeset sin id: INVALID_PARAM (decia "ese changeset no existe")', 'delphi_changeset',
            {'command': 'stage', 'kind': 'create', 'path': os.path.join(JAIL, 'n.txt'), 'content': 'x'},
            'INVALID_PARAM', 'SR_CHANGESET_NEED_ID')

    rechazo('E29 compilar una CARPETA es INVALID_PARAM (decia "no existe")', 'delphi_build',
            {'project': NOREPO, 'platform': 'Win64'}, 'INVALID_PARAM', 'SR_LSP_IS_FOLDER_FMT')

    rechazo('E30 una entrada con "new" que no es texto: INVALID_PARAM (dejaba la linea en blanco con OK)',
            'delphi_edit', {'path': U1252, 'edits': json.dumps([{'old': 'implementation', 'new': {'x': 1}}])},
            'INVALID_PARAM', 'SR_PATCH_EDIT_NO_TEXTO_FMT')
    check('E30 ...y el fichero sigue igual', open(U1252, 'rb').read() == U1252_ANTES, '')

    MAC = os.path.join(JAIL, 'Mac.pas')
    rechazo('E31 createunit con un eol que no existe: INVALID_PARAM (creaba en CRLF)', 'delphi_edit',
            {'path': MAC, 'createunit': True, 'eol': 'mac'}, 'INVALID_PARAM', 'SR_TEXT_EOL_FMT')
    check('E31 ...y no crea nada', not os.path.exists(MAC), os.listdir(JAIL))

    DPCFG = os.path.join(PCFG, 'Cfg.dproj')
    DPCFG_ANTES = open(DPCFG, 'rb').read()
    rechazo('E32 set-sdk sin sdk: INVALID_PARAM (quitaba el que hubiera, con exito)', 'delphi_config',
            {'project': DPCFG, 'command': 'set-sdk', 'platform': 'Linux64'}, 'INVALID_PARAM',
            'SR_CFG_NEED_SDK_FMT')
    rechazo('E32 set-profile sin profile: INVALID_PARAM', 'delphi_config',
            {'project': DPCFG, 'command': 'set-profile', 'platform': 'Linux64'}, 'INVALID_PARAM',
            'SR_CFG_NEED_PROFILE_FMT')
    check('E32 ...y el .dproj no se toca', open(DPCFG, 'rb').read() == DPCFG_ANTES, '')

    # dos agentes a la vez: el 1 alterna un bloque con una TANDA, el 2 sube
    # una marca con ediciones sueltas (medido en vivo el 27-sep: el 2 recibia
    # OK para "marca 1" y en el disco quedaba "marca 0")
    import threading
    BIG = os.path.join(JAIL, 'Big.pas')
    llama('delphi_edit', {'path': BIG, 'createunit': True})
    relleno = '\n'.join('// relleno %d' % i for i in range(20000))
    llama('delphi_edit', {'path': BIG, 'old': 'implementation',
                          'new': 'implementation\n\nprocedure A;\nbegin\nend;\n\n// marca 0\n' + relleno})
    cli2 = mc.Http(PORT, TOK, t=180, respaldo_json=True)
    cli2.session('resultados-2')
    BX = 'procedure A;\nbegin\nend;'
    BY = 'procedure A;\nbegin\n  // y\nend;'
    est = {'a1': BX, 'a2': 0}

    def agente1():
        for _ in range(10):
            otro = BY if est['a1'] == BX else BX
            r = cli.call_msg('delphi_edit', {'path': BIG, 'edits': json.dumps([{'old': est['a1'], 'new': otro}])},
                             300)
            if (r or {}).get('result') and not r['result'].get('isError'):
                est['a1'] = otro

    def agente2():
        for _ in range(10):
            n = est['a2']
            r = cli2.call_msg('delphi_edit', {'path': BIG, 'old': '// marca %d' % n,
                                              'new': '// marca %d' % (n + 1)}, 300)
            if (r or {}).get('result') and not r['result'].get('isError'):
                est['a2'] = n + 1

    h1, h2 = threading.Thread(target=agente1), threading.Thread(target=agente2)
    h1.start(); h2.start(); h1.join(); h2.join()
    disco = open(BIG, encoding='utf-8-sig').read().replace('\r\n', '\n')
    check('E33 dos agentes a la vez: lo que cada uno recibio como OK esta en el disco',
          est['a2'] == 10 and ('// marca %d\n' % est['a2']) in disco and est['a1'] in disco,
          'agente2 OK hasta marca %d; en disco: %s' % (est['a2'],
                                                      [l for l in disco.split('\n') if 'marca' in l]))

    # un commit y un delphi_create del MISMO fichero a la vez (medido en la
    # verificacion de la tercera ronda: delphi_create no tomaba el cerrojo,
    # creaba con OK a mitad del commit, el commit fallaba por "ya existe" y su
    # deshacer BORRABA el fichero del otro agente)
    import time
    CR = os.path.join(JAIL, 'carrera')
    os.makedirs(CR)
    fsc = []
    for i in range(200):
        p = os.path.join(CR, 'c%03d.txt' % i)
        open(p, 'w', newline='\n').write('linea\n')
        fsc.append(p)
    UX = os.path.join(CR, 'UAgente2.pas')
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    cid4 = mc.id_changeset(t)
    for p in fsc:
        llama('delphi_changeset', {'command': 'stage', 'id': cid4, 'kind': 'edit', 'path': p,
                                   'old': 'linea', 'new': 'linea del commit'})
    llama('delphi_changeset', {'command': 'stage', 'id': cid4, 'kind': 'create', 'path': UX,
                               'content': 'unit UAgente2;\ninterface\nimplementation\nend.\n'})
    llama('delphi_changeset', {'command': 'preview', 'id': cid4})
    fin_commit = {}

    def hace_commit():
        fin_commit['r'] = cli.call_msg('delphi_changeset', {'command': 'commit', 'id': cid4}, 300)

    hc = threading.Thread(target=hace_commit)
    hc.start()
    t0 = time.time()
    while time.time() - t0 < 60:
        try:
            if open(fsc[50]).read() != 'linea\n':
                break
        except OSError:
            pass
        time.sleep(0.001)
    r2 = cli2.call_msg('delphi_create', {'kind': 'unit', 'name': 'UAgente2', 'dir': CR,
                                         'content': 'unit UAgente2;\n\ninterface\n\n// DEL AGENTE 2\n\n'
                                                    'implementation\n\nend.\n'}, 300)
    hc.join()
    ok2 = bool((r2 or {}).get('result')) and not r2['result'].get('isError')
    okc = bool((fin_commit.get('r') or {}).get('result')) and not fin_commit['r']['result'].get('isError')
    cont = open(UX).read() if os.path.exists(UX) else None
    check('E34 un commit y un delphi_create del mismo fichero a la vez: lo que recibio OK esta en el disco',
          ok2 != okc and cont is not None and (('DEL AGENTE 2' in cont) == ok2),
          'create OK=%s, commit OK=%s, en disco: %r' % (ok2, okc, (cont or '')[:60]))

    rechazo('E35 una tanda de delphi_textedit sobre una CARPETA: INVALID_PARAM (decia "no existe")',
            'delphi_textedit', {'path': NOREPO, 'edits': json.dumps([{'old': 'a', 'new': 'b'}])},
            'INVALID_PARAM', 'SR_LSP_IS_FOLDER_FMT')

    PKD = os.path.join(JAIL, 'paq')
    os.makedirs(PKD)
    open(os.path.join(PKD, 'app.txt'), 'w').write('app\n')
    rechazo('E36 package con un FICHERO en el camino del outfile: INVALID_PARAM (salia INTERNAL)',
            'delphi_package', {'dir': PKD, 'outfile': os.path.join(ECO, 'p.zip')}, 'INVALID_PARAM',
            'SR_GUARD_FICHERO_EN_RUTA_FMT')
    res, sc, t = llama('delphi_package', {'dir': PKD, 'outfile': os.path.join(JAIL, 'nueva', 'sub', 'p.zip')})
    check('E36 ...una carpeta que no existia se crea', not res.get('isError') and
          os.path.exists(os.path.join(JAIL, 'nueva', 'sub', 'p.zip')), t[:200])
    VAL = os.path.join(JAIL, 'valioso.zip')
    open(VAL, 'wb').write(b'PK-lo-mio')
    res, sc, t = llama('delphi_package', {'dir': PKD, 'outfile': VAL})
    copias = [os.path.join(r, n) for r, d, fs in os.walk(os.path.join(JAIL, '__delphi-patch')) for n in fs
              if n.startswith('valioso.zip')]
    check('E36 ...y un .zip que ya estaba se copia antes de pisarlo',
          not res.get('isError') and any(open(p, 'rb').read() == b'PK-lo-mio' for p in copias),
          '%s | copias=%s' % (t[:150], copias))

    rechazo('E37 una ruta RELATIVA es INVALID_PARAM (decia "fuera de la jaula")', 'delphi_textedit',
            {'path': 'relativa\\x.txt', 'old': 'a', 'new': 'b'}, 'INVALID_PARAM', 'SR_GUARD_RUTA_RELATIVA_FMT')

    rechazo('E38 un entero negativo es INVALID_PARAM (delphi_read lo tomaba por el defecto)', 'delphi_read',
            {'path': NOTES, 'fromline': -2}, 'INVALID_PARAM', 'SR_SYS_PARAM_VALUE_FMT')

    res, sc, t = llama('delphi_search', {'root': JAIL, 'query': 'First', 'pattern': '*.nadadenada'})
    check('E39 delphi_search con una mascara que no casa con nada lo dice (maskNote)',
          not res.get('isError') and mc.es(mc.como_json(t).get('maskNote', ''), 'SN_SEARCH_MASK_NO_MATCH_FMT'),
          t[:250])

    res, sc, t = llama('delphi_help', {})
    # desde la 1.17.0 dice ademas POR QUE faltan (un agente creyo que se habian
    # fusionado): la fila del vault no esta y la nota de "sin vault" si
    check('E40 delphi_help no anuncia vault_* sin vault (y dice por que faltan)', not res.get('isError') and
          'delphi_git' in t and mc.catalogo()['SF_HELP_TASKS_VAULT_LEER'].strip()[:20] not in t
          and mc.catalogo()['SF_HELP_TASKS_SIN_VAULT'].strip()[:30] in t, t[-400:])

    LFU = os.path.join(JAIL, 'Lf.pas')
    res, sc, t = llama('delphi_edit', {'path': LFU, 'createunit': True, 'eol': 'lf'})
    check('E41 createunit eol=lf sin content escribe LF',
          not res.get('isError') and os.path.exists(LFU) and b'\r' not in open(LFU, 'rb').read(), t[:200])

    open(os.path.join(GREPO, 'a.txt'), 'w').write('rebase\n')
    res, sc, t = llama('delphi_git', {'repo': GREPO, 'command': 'diff', 'args': '--exit-code'})
    check('E42 git diff --exit-code con cambios: exito, sin las pistas de un fallo',
          not res.get('isError') and t.startswith('exit=1') and not mc.es(t, 'SN_GIT_HINT_OVERRIDE'), t[:300])

    # (el bloqueo por otro proceso es mc.bloqueado: aqui habia CreateFileW a mano)
    OCUP = os.path.join(JAIL, 'ocupado.txt')
    open(OCUP, 'w').write('alguien lo tiene\n')
    with mc.bloqueado(OCUP): # GENERIC_READ, sin compartir
        res, sc, t = llama('delphi_read', {'path': OCUP})
    check('E43 un fichero que otro proceso tiene abierto es DENIED (era INTERNAL)',
          res.get('isError') is True and sc.get('code') == 'DENIED' and mc.abre(t, 'SR_FICHERO_OCUPADO_FMT'),
          '%s | %s' % (json.dumps(sc)[:120], t[:200]))

    # sin sitio DE VERDAD: una unit sin implementation (el cuerpo va delante
    # del end., la declaracion no tiene donde ir). Hasta la 1.10.0 se forzaba
    # con un 'implementation' DENTRO de un comentario, que el lector de
    # entonces contaba como un segundo; el lexico de la casa ya no lo cuenta
    VIS = os.path.join(JAIL, 'Vis.pas')
    open(VIS, 'w', newline='\r\n').write('unit Vis;\n\ninterface\n\nend.\n')
    VIS_ANTES = open(VIS, 'rb').read()
    res, sc, t = llama('delphi_edit', {'path': VIS, 'insert': 'rutina-global', 'visible': True,
                                       'code': 'procedure Hola;\nbegin\nend;'})
    check('E44 insert visible=true sin sitio para la declaracion: FALLO y nada escrito',
          res.get('isError') is True and mc.abre(t, 'SR_EDIT_VISIBLE_DESHECHO_FMT') and
          open(VIS, 'rb').read() == VIS_ANTES, '%s | %s' % (json.dumps(sc)[:120], t[:250]))

    NV = os.path.join(JAIL, 'nv1')
    N2 = os.path.join(JAIL, 'nueva2')
    os.makedirs(N2)
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    cid5 = mc.id_changeset(t)
    llama('delphi_changeset', {'command': 'stage', 'id': cid5, 'kind': 'create',
                               'path': os.path.join(NV, 'nv2', 'c.txt'), 'content': 'x'})
    llama('delphi_changeset', {'command': 'stage', 'id': cid5, 'kind': 'create',
                               'path': os.path.join(N2, 'sub.txt'), 'content': 'x'})
    llama('delphi_changeset', {'command': 'preview', 'id': cid5})
    os.rmdir(N2)
    open(N2, 'w').write('ahora soy un fichero')
    res, sc, t = llama('delphi_changeset', {'command': 'commit', 'id': cid5})
    check('E45 el deshacer de un commit quita las carpetas que creo',
          res.get('isError') is True and not os.path.exists(NV), '%s | %s' % (t[:200], os.listdir(JAIL)))
    os.remove(N2)

    TAP = os.path.join(JAIL, 'tapada')
    os.makedirs(TAP)
    open(os.path.join(TAP, '__delphi-patch'), 'w').write('un fichero donde van las copias')
    open(os.path.join(TAP, 'n.txt'), 'w').write('uno\n')
    rechazo('E46 un FICHERO donde el servidor guarda sus copias es DENIED (la ruta era buena)',
            'delphi_textedit', {'path': os.path.join(TAP, 'n.txt'), 'old': 'uno', 'new': 'dos'},
            'DENIED', 'SR_GUARD_FICHERO_EN_CARPETA_SERVIDOR_FMT')

    NUL = os.path.join(JAIL, 'nulo.txt')  # ('nul.txt' es un nombre reservado: GUARD-027)
    open(NUL, 'w').write('queda\nborrame\nqueda\n')
    res, sc, t = llama('delphi_textedit', {'path': NUL, 'edits': json.dumps(
        [{'old': 'borrame', 'new': None, 'delete': True}])})
    check('E47 "new": null es "sin new": delete sigue borrando',
          not res.get('isError') and open(NUL).read() == 'queda\nqueda\n', t[:200])

    # ---- quinta revision ------------------------------------------------
    import stat

    def copias_de(nombre):
        return [os.path.join(r, n) for r, d, fs in os.walk(os.path.join(JAIL, '__delphi-patch'))
                for n in fs if n.startswith(nombre)]

    TJ = os.path.join(JAIL, 'tj')
    os.makedirs(TJ)
    VICT = os.path.join(BASE, 'victima')   # fuera de la jaula
    # La papelera de OTRO proyecto, con su carpeta del dia y su cajon: es el
    # montaje en el que el codigo de antes SI fugaba (contestaba DELETED y
    # dejaba la copia dentro de la victima). Sin la carpeta del dia fallaba
    # antes de escribir y el check caia solo por el codigo (sexta revision).
    os.makedirs(os.path.join(VICT, time.strftime('%Y%m%d'), 'deleted'))
    open(os.path.join(VICT, 'suyo.txt'), 'w').write('de otro\n')

    def arbol(d):
        return sorted(os.path.relpath(os.path.join(r, n), d)
                      for r, ds, fs in os.walk(d) for n in fs + ds)
    ANTES_VICT = arbol(VICT)
    JUNCTION = os.path.join(TJ, '__delphi-patch')
    subprocess.run(['cmd', '/c', 'mklink', '/J', JUNCTION, VICT], capture_output=True)
    # sin el junction la prueba mide otra cosa (una papelera normal): se dice
    check('E48 fixture: la papelera es de verdad un junction a la victima',
          os.path.isjunction(JUNCTION), JUNCTION)
    XJ = os.path.join(TJ, 'x.txt')
    open(XJ, 'w').write('x\n')
    res, sc, t = llama('delphi_delete', {'path': XJ})
    check('E48 delete con la papelera enlazada FUERA de la jaula: DENIED y nada se mueve',
          os.path.isdir(JUNCTION) and res.get('isError') is True and
          sc.get('code') == 'DENIED' and os.path.exists(XJ) and arbol(VICT) == ANTES_VICT,
          '%s | %s | victima=%s' % (json.dumps(sc)[:100], t[:200], arbol(VICT)))
    res, sc, t = llama('delphi_move', {'path': XJ, 'dest': os.path.join(TJ, 'y.txt')})
    # control: el codigo de antes tambien lo paraba (fallaba al copiar)
    check('E48 ...y move (control, su copia previa va a esa papelera): DENIED y nada se mueve',
          res.get('isError') is True and os.path.exists(XJ) and arbol(VICT) == ANTES_VICT,
          '%s | victima=%s' % (t[:200], arbol(VICT)))

    res, sc, t = llama('delphi_upload', {'path': os.path.join(TAP, 'n.txt'), 'offset': 0,
                                         'chunkbase64': base64.b64encode(b'nuevo\n').decode()})
    check('E50 upload sin poder copiar lo que pisa: DENIED y no escribe',
          res.get('isError') is True and sc.get('code') == 'DENIED' and
          open(os.path.join(TAP, 'n.txt')).read() == 'uno\n', '%s | %s' % (json.dumps(sc)[:100], t[:200]))

    UTF = os.path.join(JAIL, 'utf.txt')
    st = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='utf8')
    try:
        st.send(json.dumps({"jsonrpc": "2.0", "id": 77, "method": "tools/call", "params": {
            "name": "delphi_textedit",
            "arguments": {"path": UTF, "create": True, "content": 'canción ✔ ñ\n'}}},
            ensure_ascii=False))
        rs = st.recv(77)
    finally:
        st.cierra()
    en_disco = open(UTF, 'rb').read().decode('utf-8', 'replace') if os.path.exists(UTF) else None
    check('E51 stdio: lo que el cliente manda en UTF-8 llega entero (acentos y un simbolo)',
          rs is not None and en_disco is not None and 'canción ✔ ñ' in en_disco,
          '%r | %s' % (en_disco, mc.texto(rs, True)[:150]))

    NOTES_ANTES = open(NOTES, 'rb').read()
    res, sc, t = llama('delphi_textedit', {'path': NOTES, 'edits': json.dumps(
        [{'old': 'First line.', 'new': 'X', 'delete': 'yes'}])})
    check('E52 una entrada de "edits" con un booleano que no lo es: INVALID_PARAM y nada escrito',
          res.get('isError') is True and sc.get('code') == 'INVALID_PARAM' and
          mc.es(t, 'SR_PATCH_EDIT_VALOR_FMT') and open(NOTES, 'rb').read() == NOTES_ANTES,
          '%s | %s' % (json.dumps(sc)[:100], t[:200]))
    res, sc, t = llama('delphi_textedit', {'path': NOTES, 'edits': json.dumps(
        [{'old': 'First line.', 'new': 'X', 'toline': -1}])})
    check('E52 ...y un entero negativo en una entrada, igual',
          res.get('isError') is True and sc.get('code') == 'INVALID_PARAM' and
          mc.es(t, 'SR_PATCH_EDIT_VALOR_FMT') and open(NOTES, 'rb').read() == NOTES_ANTES, t[:200])

    rechazo('E53 un texto que llega como lista es INVALID_PARAM (se escribia su JSON)',
            'delphi_textedit', {'path': NOTES, 'old': ['First line.'], 'new': 'X'},
            'INVALID_PARAM', 'SR_SYS_PARAM_VALUE_FMT')
    res, sc, t = llama('delphi_textedit', {'path': NOTES, 'edits': [{'old': 'Second line.',
                                                                    'new': 'Second line.'}]})
    check('E53 ...pero "edits" como lista JSON de verdad se acepta',
          not res.get('isError') and open(NOTES, 'rb').read() == NOTES_ANTES, t[:200])

    GRP = os.path.join(JAIL, 'Grupo.groupproj')
    open(GRP, 'w').write('<Project><ItemGroup><Projects Include="App.dproj"/></ItemGroup></Project>\n')
    with mc.bloqueado(GRP):
        res, sc, t = llama('delphi_config', {'command': 'view', 'project': GRP})
    check('E54 config view de un .groupproj que otro tiene abierto: DENIED (SYS-027)',
          res.get('isError') is True and sc.get('code') == 'DENIED' and mc.es(t, 'SR_FICHERO_OCUPADO_FMT'),
          '%s | %s' % (json.dumps(sc)[:100], t[:200]))

    rechazo('E55 una ruta de Linux (/home/x) es INVALID_PARAM en la entrada',
            'delphi_list', {'root': '/home/x'}, 'INVALID_PARAM', 'SR_GUARD_RUTA_RELATIVA_FMT')
    rechazo('E55 ...y una relativa en delphi_search',
            'delphi_search', {'root': 'rel\\dir', 'query': 'x'}, 'INVALID_PARAM', 'SR_GUARD_RUTA_RELATIVA_FMT')

    LF_ANTES = open(LFU, 'rb').read()
    res, sc, t = llama('delphi_edit', {'path': LFU, 'old': 'interface', 'new': 'x',
                                       'edits': json.dumps([{'old': 'interface', 'new': 'y'}])})
    check('E56 modos de delphi_edit que no combinan: INVALID_PARAM y nada escrito',
          res.get('isError') is True and sc.get('code') == 'INVALID_PARAM' and
          mc.abre(t, 'SR_EDIT_MODOS_NO_COMBINAN_FMT') and open(LFU, 'rb').read() == LF_ANTES, t[:200])

    OTRA = os.path.join(JAIL, 'Otra.pas')
    res, sc, t = llama('delphi_edit', {'path': OTRA, 'createunit': True,
                                       'content': 'unit NoCasa;\n\ninterface\n\nimplementation\n\nend.\n'})
    check('E57 createunit con un content cuyo "unit" no casa: INVALID_PARAM y nada creado',
          res.get('isError') is True and sc.get('code') == 'INVALID_PARAM' and
          mc.abre(t, 'SR_CREATE_CONTENT_NAME_FMT') and not os.path.exists(OTRA), t[:200])

    PAN = os.path.join(JAIL, 'pan')
    res, sc, t = llama('delphi_create', {'kind': 'project-console', 'name': 'Pan', 'dir': PAN})
    DPR_PAN = os.path.join(PAN, 'Pan.dpr')
    DPROJ_PAN = os.path.join(PAN, 'Pan.dproj')
    check('E58 fixture: el proyecto se crea', os.path.exists(DPR_PAN) and os.path.exists(DPROJ_PAN), t[:200])
    if os.path.exists(DPROJ_PAN):
        ANT_DPR, ANT_DPROJ = open(DPR_PAN, 'rb').read(), open(DPROJ_PAN, 'rb').read()
        with mc.solo_lectura(DPROJ_PAN):
            res, sc, t = llama('delphi_create', {'kind': 'unit', 'name': 'UPan', 'project': DPROJ_PAN})
        check('E58 delphi_create con un proyecto que no se deja registrar: fallo y NADA creado',
              res.get('isError') is True and mc.abre(t, 'SR_CREATE_CREADA_NO_REGISTRADA_FMT') and
              not os.path.exists(os.path.join(PAN, 'UPan.pas')) and
              open(DPR_PAN, 'rb').read() == ANT_DPR and open(DPROJ_PAN, 'rb').read() == ANT_DPROJ,
              '%s | %s | %s' % (json.dumps(sc)[:100], t[:250], os.listdir(PAN)))

        res, sc, t = llama('delphi_create', {'kind': 'unit', 'name': 'UDel', 'project': DPROJ_PAN})
        UDEL = os.path.join(PAN, 'UDel.pas')
        check('E59 fixture: la unit se crea y registra', not res.get('isError') and os.path.exists(UDEL),
              t[:200])
        ANT_DPR = open(DPR_PAN, 'rb').read()
        with mc.solo_lectura(DPROJ_PAN):
            res, sc, t = llama('delphi_delete', {'path': UDEL})
        check('E59 borrar una unit con un proyecto que no se deja tocar: fallo y la unit sigue',
              res.get('isError') is True and mc.abre(t, 'SR_FILE_UNIT_DESHECHO_FMT') and
              os.path.exists(UDEL) and open(DPR_PAN, 'rb').read() == ANT_DPR,
              '%s | %s' % (json.dumps(sc)[:100], t[:250]))

    rechazo('E60 styles lint con un project que no existe: NOT_FOUND',
            'delphi_styles', {'command': 'lint', 'path': JAIL, 'project': os.path.join(JAIL, 'nada.dproj')},
            'NOT_FOUND', 'SR_STYLES_PROJECT_NO_EXISTE_FMT')

    VACIO = os.path.join(JAIL, 'vacio.txt')
    open(VACIO, 'w').close()
    res, sc, t = llama('delphi_read', {'path': VACIO})
    check('E61 leer un fichero VACIO es un exito (salia EDIT-100 INVALID_PARAM)',
          not res.get('isError') and mc.abre(t, 'SK_EDIT_LECTURA_VACIO_FMT'), t[:200])
    res, sc, t = llama('delphi_read', {'path': NOTES})
    check('E61 ..."a\\nb\\n" son 2 lineas, sin una tercera fantasma',
          not res.get('isError') and 'Lines 1-2 of 2 ' in t and '3|' not in t, t[:300])

    LT = os.path.join(JAIL, 'lt')
    os.makedirs(LT)
    for n in ('a.txt', 'b.txt', 'c.txt'):
        open(os.path.join(LT, n), 'w').write(n + '\n')
    llama('delphi_delete', {'path': os.path.join(LT, 'a.txt')})
    res, sc, t = llama('delphi_list', {'root': LT, 'pattern': '*;*.txt', 'includetrash': True})
    j = mc.como_json(t)
    rutas = [f.get('path') for f in mc.ficheros(j)]
    vivas = [r for r in rutas if '__delphi-patch' not in r]
    check('E62 delphi_list includetrash con mascaras solapadas: cada fichero UNA vez',
          len(vivas) == 2 and len(rutas) > 2 and len(set(rutas)) == len(rutas) and
          # shownTrash cuenta COPIAS: la marca de dueno (.by) no es otra (septima)
          j.get('total') == len(rutas) and j.get('shownTrash') == len(
              [r for r in rutas if r not in vivas and not mc.es_marca_dueno(r)]),
          '%s | %s' % (j.get('total'), rutas))
    marcas = [r for r in rutas if mc.es_marca_dueno(r)]
    check('E120 LIST-008 cuenta las marcas .by aparte (las llamaba "live files")',
          len(marcas) >= 1 and mc.abre(j.get('trashNote', ''), 'SN_LIST_SHOWN_TRASH_FMT') and
          j.get('shownMarkers') == len(marcas),
          '%s | %s' % (marcas, j.get('trashNote')))

    VCLP = os.path.join(JAIL, 'Vc.dproj')
    open(VCLP, 'w').write('<Project><PropertyGroup><FrameworkType>VCL</FrameworkType>'
                          '<MainSource>Vc.dpr</MainSource></PropertyGroup></Project>\n')
    open(os.path.join(JAIL, 'Vc.dpr'), 'w').write('program Vc;\n\nuses\n  Vcl.Forms;\n\nbegin\nend.\n')
    res, sc, t = llama('delphi_build', {'project': VCLP, 'platform': 'Linux64'})
    check('E63 compilar un proyecto VCL para Linux64 se niega ANTES (la regla de add-platform)',
          res.get('isError') is True and sc.get('code') == 'DENIED' and mc.abre(t, 'SR_RECHAZADO_FMT') and
          'VCL' in t and 'add-searchpath' not in t, '%s | %s' % (json.dumps(sc)[:100], t[:250]))

    MV = os.path.join(JAIL, 'mv.txt')
    open(MV, 'w').write('mv\n')
    res, sc, t = llama('delphi_move', {'path': MV, 'dest': os.path.join(ECO, 'sub', 'mv.txt')})
    check('E64 move rechazado (un FICHERO en el camino): no deja copia en la papelera',
          res.get('isError') is True and os.path.exists(MV) and not copias_de('mv.txt'),
          '%s | %s' % (t[:200], copias_de('mv.txt')))

    antes_c = len(copias_de('Lf.pas'))
    res, sc, t = llama('delphi_edit', {'path': LFU, 'old': 'interface', 'new': 'interface'})
    check('E65 delphi_edit con old == new: UNCHANGED, sin escribir ni copiar',
          not res.get('isError') and mc.abre(t, 'SN_EDIT_SIN_CAMBIOS_FMT') and
          open(LFU, 'rb').read() == LF_ANTES and len(copias_de('Lf.pas')) == antes_c, t[:200])
    antes_c = len(copias_de('NOTES.md'))
    res, sc, t = llama('delphi_textedit', {'path': NOTES, 'old': 'First line.', 'new': 'First line.'})
    check('E65 ...y su gemela delphi_textedit, igual',
          not res.get('isError') and mc.abre(t, 'SN_EDIT_SIN_CAMBIOS_FMT') and
          open(NOTES, 'rb').read() == NOTES_ANTES and len(copias_de('NOTES.md')) == antes_c, t[:200])

    rechazo('E66 textedit con un atline que no es el de la unica ocurrencia: se niega (como delphi_edit)',
            'delphi_textedit', {'path': NOTES, 'old': 'First line.', 'new': 'X', 'atline': 2},
            'INVALID_PARAM', 'SR_TEXT_ATLINE_NINGUNA_OCURRENCIAS_FMT')

    rechazo('E67 set-sdk en Win64: INVALID_PARAM (decia "Registered for Win64: .")',
            'delphi_config', {'command': 'set-sdk', 'project': DPROJ, 'platform': 'Win64', 'sdk': 'x'},
            'INVALID_PARAM', 'SR_CONFIG_SDK_LOCAL_FMT')

    rechazo('E69 hover sobre una CARPETA: INVALID_PARAM (decia "no es un fuente ()")',
            'delphi_hover', {'path': NOREPO, 'line': 0, 'character': 0}, 'INVALID_PARAM',
            'SR_LSP_IS_FOLDER_FMT')
    rechazo('E69 ...sobre un .pas que no existe: NOT_FOUND',
            'delphi_hover', {'path': os.path.join(JAIL, 'nada.pas'), 'line': 0, 'character': 0},
            'NOT_FOUND', 'SR_LSP_NO_FILE_FMT')
    rechazo('E69 ...y references sobre un .txt: INVALID_PARAM (se lo mandaba al motor)',
            'delphi_references', {'path': ECO, 'line': 0, 'character': 0}, 'INVALID_PARAM',
            'SR_LSP_NOT_SOURCE_FMT')

    PKF = os.path.join(JAIL, 'paqf')
    os.makedirs(PKF)
    open(os.path.join(PKF, 'a.txt'), 'w').write('a\n')
    BLOQ = os.path.join(PKF, 'b.txt')
    open(BLOQ, 'w').write('b\n')
    with mc.bloqueado(BLOQ):
        res, sc, t = llama('delphi_package', {'dir': PKF, 'outfile': os.path.join(JAIL, 'paqf.zip')})
    tmps = [n for n in os.listdir(JAIL) if n.startswith('paqf.zip') and n.endswith('.tmp')]
    check('E70 un paquete que se cae a medias no deja su .tmp',
          res.get('isError') is True and not tmps, '%s | %s' % (t[:200], tmps))

    TT = os.path.join(JAIL, 'tt')
    res, sc, t = llama('delphi_create', {'kind': 'project-test', 'name': 'Tt', 'dir': TT})
    TTDPR = os.path.join(TT, 'Tt.dpr')
    check('E71 el proyecto de tests lee su linea de comandos (el filter de delphi_test)',
          os.path.exists(TTDPR) and 'TDUnitX.CheckCommandLine;' in open(TTDPR).read(), t[:200])

    # E55 mide list/search, que ya niegan la relativa ellas: pasaria sin la
    # puerta. package y upload la resolvian contra la carpeta del proceso
    # ANTES de mirar la jaula: solo las para la pasada de relativas.
    rechazo('E72 delphi_package con dir relativo: INVALID_PARAM en la puerta',
            'delphi_package', {'dir': 'rel\\dir'}, 'INVALID_PARAM', 'SR_GUARD_RUTA_RELATIVA_FMT')
    rechazo('E72 ...y delphi_upload con path relativo, sin escribir nada',
            'delphi_upload', {'path': 'subido.txt', 'chunkbase64': 'aG9sYQ=='},
            'INVALID_PARAM', 'SR_GUARD_RUTA_RELATIVA_FMT')
    # (control: con el servidor lanzado fuera de la jaula no puede fallar; mide
    # que la negativa de arriba no escribio nada en ningun sitio)
    check('E72 ...(control) y el upload no dejo el fichero junto al proceso',
          not os.path.exists(os.path.join(EXEDIR, 'subido.txt')) and
          not os.path.exists(os.path.join(os.getcwd(), 'subido.txt')), os.getcwd())

    # TPath.IsPathRooted da por completas "\x" y "C:x": se resolvian contra la
    # unidad del PROCESO (fuera: un DENIED enganoso; dentro: donde nadie dijo)
    if os.path.exists(DPROJ_PAN):
        rechazo('E73 add-searchpath con "\\lib": INVALID_PARAM, ni relativa ni completa',
                'delphi_config', {'project': DPROJ_PAN, 'command': 'add-searchpath',
                                  'path': '\\lib'}, 'INVALID_PARAM', 'SR_CONFIG_PATH_A_MEDIAS_FMT')
        rechazo('E73 ...y add-deployfile con "C:x.txt"', 'delphi_config',
                {'project': DPROJ_PAN, 'command': 'add-deployfile', 'platform': 'Win64',
                 'path': 'C:x.txt'}, 'INVALID_PARAM', 'SR_CONFIG_PATH_A_MEDIAS_FMT')
    rechazo('E73 ...y una unit suelta con dir "\\suelta": INVALID_PARAM', 'delphi_create',
            {'kind': 'unit', 'name': 'USuelta', 'dir': '\\suelta'},
            'INVALID_PARAM', 'SR_CREATE_UNIT_NEED_PROJECT')

    # La papelera se reconocia de dos formas: la puerta de escritura sobre la
    # ruta larga, delphi_delete / delphi_move sobre el texto tal cual
    import ctypes
    E74 = os.path.join(JAIL, 'e74')
    os.makedirs(E74)
    open(os.path.join(E74, 'borrame.txt'), 'w').write('x')
    res, sc, t = llama('delphi_delete', {'path': os.path.join(E74, 'borrame.txt')})
    # sin este borrado no hay papelera y la NOTA de abajo mentiria ("sin 8.3")
    check('E74 fixture: el borrado que crea la papelera funciona',
          not res.get('isError') and not os.path.exists(os.path.join(E74, 'borrame.txt')),
          t[:200])
    PAPE = os.path.join(E74, '__delphi-patch')
    CORTA = mc.corta(PAPE)
    if os.path.isdir(PAPE) and CORTA and os.path.basename(CORTA).lower() != '__delphi-patch':
        rechazo('E74 delete de la papelera por su alias 8.3 (%s): DENIED, la papelera'
                % os.path.basename(CORTA),
                'delphi_delete', {'path': CORTA}, 'DENIED', 'SR_FILE_PAPELERA_NO_SE_BORRA_FMT')
        check('E74 ...y la papelera sigue ahi', os.path.isdir(PAPE), os.listdir(E74))
    else:
        print('NOTA: E74 sin medir: este volumen no da nombres 8.3 (%r)' % CORTA)

    # La jaula comparaba el TEXTO con las raices: con OTROS nombres cortos que
    # los declarados, una carpeta suya salia "fuera" (FormaLarga, 28-sep). Y
    # la raiz misma por su alias tiene que seguir siendo LA RAIZ: si solo
    # casase la contencion, entraria como "dentro" y se podria borrar.
    JAIL_CORTA = mc.corta(JAIL)
    if JAIL_CORTA and JAIL_CORTA.lower() != JAIL.lower():
        rechazo('E75 borrar la RAIZ por su alias 8.3: DENIED, es la raiz (%s)' % JAIL_CORTA[-30:],
                'delphi_delete', {'path': JAIL_CORTA}, 'DENIED', 'SR_ROOT_ITSELF_FMT')
        check('E75 ...y la raiz sigue ahi', os.path.isdir(JAIL), JAIL)
        LEIBLE = os.path.join(JAIL, 'UE76.pas')
        open(LEIBLE, 'w').write('unit UE76; // dentro\n')
        res, sc, t = llama('delphi_read', {'path': os.path.join(JAIL_CORTA, 'UE76.pas')})
        check('E76 un fichero de dentro por su alias 8.3 se lee',
              not res.get('isError') and 'dentro' in t, t[:200])
    else:
        print('NOTA: E75/E76 sin medir: la jaula no tiene otro nombre 8.3 (%r)' % JAIL_CORTA)

    # E78 un form cuyo designer ya esta en disco: CREATE-027 y NADA creado (el
    # .pas se quedaba y repetir chocaba con "ya existe"; sexta revision)
    if os.path.exists(DPROJ_PAN):
        open(os.path.join(PAN, 'UFicha.dfm'), 'w').write('object FormFicha: TFormFicha\nend\n')
        res, sc, t = llama('delphi_create', {'kind': 'form-vcl', 'name': 'UFicha',
                                              'project': DPROJ_PAN})
        check('E78 form con su .dfm ya en disco: CREATE-027 y ningun .pas creado',
              res.get('isError') is True and mc.abre(t, 'SR_CREATE_YA_EXISTE_SOBREESCRIBE_FMT') and
              'UFicha.dfm' in t and not os.path.exists(os.path.join(PAN, 'UFicha.pas')), t[:200])

    # E79 SOLO LECTURA (atributo): SYS-029, que no es "otro proceso lo tiene"
    # (EDIT-106 mandaba repetir para siempre) ni SYS-006 INTERNAL (upload)
    import stat as _stat
    RO = os.path.join(JAIL, 'solo_lectura.txt')
    open(RO, 'w', newline='\n').write('fijo\n')
    with mc.solo_lectura(RO):
        res, sc, t = llama('delphi_textedit', {'path': RO, 'old': 'fijo', 'new': 'otro'})
        check('E79 editar un fichero de solo lectura: SYS-029 DENIED y nada escrito',
              res.get('isError') is True and mc.abre(t, 'SR_SOLO_LECTURA_ATRIBUTO_FMT') and
              open(RO).read() == 'fijo\n', t[:200])
        res, sc, t = llama('delphi_upload', {'path': RO, 'chunkbase64': base64.b64encode(b'x\n').decode()})
        check('E79 ...y subir encima: SYS-029 DENIED, no SYS-006 INTERNAL',
              res.get('isError') is True and mc.abre(t, 'SR_SOLO_LECTURA_ATRIBUTO_FMT') and
              open(RO).read() == 'fijo\n', t[:200])

    # E80 borrar una CARPETA que no se puede mover (un fichero abierto dentro):
    # "no he tocado NADA" era mentira, sus units ya habian salido de los
    # proyectos (sexta revision). Ahora vuelven.
    if os.path.exists(DPROJ_PAN):
        res, sc, t = llama('delphi_create', {'kind': 'unit', 'name': 'UModulo',
                                              'project': DPROJ_PAN, 'dir': 'mods'})
        UMOD = os.path.join(PAN, 'mods', 'UModulo.pas')
        DPR_ANTES = open(DPR_PAN, 'rb').read()
        DPROJ_ANTES = open(DPROJ_PAN, 'rb').read()
        check('E80 fixture: la unit de la carpeta esta en el proyecto',
              os.path.exists(UMOD) and b'UModulo' in DPR_ANTES, t[:200])
        abierto = open(UMOD, 'r')
        try:
            res, sc, t = llama('delphi_delete', {'path': os.path.join(PAN, 'mods')})
        finally:
            abierto.close()
        check('E80 borrar una carpeta que no se deja mover: FILE-036 y el proyecto INTACTO',
              res.get('isError') is True and mc.abre(t, 'SR_FILE_DELETE_LOCKED_FMT') and
              os.path.exists(UMOD) and open(DPR_PAN, 'rb').read() == DPR_ANTES and
              open(DPROJ_PAN, 'rb').read() == DPROJ_ANTES,  # el .dproj tambien vuelve
              '%s | lista UModulo: %s' % (t[:200], b'UModulo' in open(DPR_PAN, 'rb').read()))

    # E81 LSP-004 cuenta como delphi_read: sin la linea fantasma del salto final
    TRES = os.path.join(JAIL, 'Tres.pas')
    open(TRES, 'w', newline='\n').write('unit Tres;\ninterface\nend.\n')
    res, sc, t = llama('delphi_hover', {'path': TRES, 'line': 3, 'character': 0})
    check('E81 LSP-004: "has 3 lines" como delphi_read (decia 4)',
          res.get('isError') is True and mc.abre(t, 'SR_LSP_LINE_RANGE_FMT') and 'has 3 lines' in t,
          t[:200])

    # E82 una busqueda de CARPETA no se cae entera por un fichero bloqueado
    BUSCA = os.path.join(JAIL, 'e82')
    os.makedirs(BUSCA)
    open(os.path.join(BUSCA, 'UUno.pas'), 'w').write('unit UUno; // aguja\n')
    BLOQ = os.path.join(BUSCA, 'UDos.pas')
    open(BLOQ, 'w').write('unit UDos; // aguja\n')
    with mc.bloqueado(BLOQ): # sin compartir
        res, sc, t = llama('delphi_search', {'root': BUSCA, 'query': 'aguja'})
    j = mc.como_json(t)
    check('E82 buscar en una carpeta con un fichero bloqueado: los demas y SEARCH-003',
          not res.get('isError') and j.get('total') == 1 and
          mc.es(j.get('unreadableNote', ''), 'SN_SEARCH_ILEGIBLES_FMT') and
          'UDos.pas' in j.get('unreadableNote', ''), t[:300])

    # E83 un parametro que no es del comando se DICE: set-output con path=
    # contestaba "puesto en Compiled" (el valor por defecto) ignorando path
    # con un proyecto REAL (grupo $(Base)): con el App.dproj minimo la version
    # de antes contestaba CFG-087 y no el exito callado que se arreglo
    P83 = DPROJ_PAN if os.path.exists(DPROJ_PAN) else DPROJ
    ANTES = open(P83, 'rb').read()
    t = rechazo('E83 set-output con path= (el suyo es output): CFG-110', 'delphi_config',
                {'command': 'set-output', 'project': P83, 'path': '.\\bin'},
                'INVALID_PARAM', 'SR_CONFIG_NO_ES_DEL_COMANDO_FMT')
    check('E83 ...nombra lo que toma el comando y el .dproj no se toco',
          'set-output takes output' in t and open(P83, 'rb').read() == ANTES, t[:200])
    rechazo('E83 view con platform= tampoco se ignora', 'delphi_config',
            {'command': 'view', 'project': DPROJ, 'platform': 'Win64'},
            'INVALID_PARAM', 'SR_CONFIG_NO_ES_DEL_COMANDO_FMT')

    # E84 un UNC ajeno se niega por TEXTO: resolverlo (RealPath, el alargado de
    # un ~) abria SMB hacia el host que dijera el agente. 192.0.2.1 es de
    # documentacion y no contesta: con SMB de por medio serian ~20 s
    for unc in (r'\\192.0.2.1\share\f.txt', r'\\192.0.2.1\share\PROGRA~1\f.txt'):
        t0 = time.time()
        res, sc, t = llama('delphi_read', {'path': unc})
        dt = time.time() - t0
        check('E84 %s: GUARD-002 en %.1f s, sin tocar la red' % (unc, dt),
              res.get('isError') is True and mc.abre(t, 'SR_JAIL_FMT') and dt < 3, t[:160])

    # E85 delete-line lleva old (lo compara con su linea): CHSET-030 lo rechazaba
    DL = os.path.join(JAIL, 'dl.txt')
    open(DL, 'w', newline='\n').write('uno\ndos\ntres\n')
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    c85 = mc.id_changeset(t)
    res, sc, t = llama('delphi_changeset', {'command': 'stage', 'id': c85, 'kind': 'delete-line',
                                            'path': DL, 'atline': 2, 'old': 'dos'})
    check('E85 delete-line con old se apila (CHSET-030 lo rechazaba)', not res.get('isError'), t[:200])
    llama('delphi_changeset', {'command': 'preview', 'id': c85})
    res, sc, t = llama('delphi_changeset', {'command': 'commit', 'id': c85})
    check('E85 ...y el commit borra ESA linea y conserva el salto final',
          not res.get('isError') and open(DL, newline='').read() == 'uno\ntres\n',
          '%s | %r' % (t[:160], open(DL, newline='').read()))

    # E86 delete-line pasada del final: la fantasma del salto final contaba
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    c86 = mc.id_changeset(t)
    llama('delphi_changeset', {'command': 'stage', 'id': c86, 'kind': 'delete-line',
                               'path': DL, 'atline': 3})
    res, sc, t = llama('delphi_changeset', {'command': 'preview', 'id': c86})
    check('E86 delete-line atline=3 en un fichero de 2: el preview NO sale limpio',
          mc.como_json(t).get('unresolved') == 1 and 'has 2' in t, t[:300])
    llama('delphi_changeset', {'command': 'rollback', 'id': c86})  # 'discard' no existe
    check('E86 ...y el fichero sigue igual', open(DL, newline='').read() == 'uno\ntres\n',
          repr(open(DL, newline='').read()))

    # E87 todo lo que casa con la mascara esta bloqueado: no es "la mascara no caso"
    B87 = os.path.join(JAIL, 'e87')
    os.makedirs(B87)
    SOLO = os.path.join(B87, 'solo.md')
    open(SOLO, 'w').write('aguja\n')
    with mc.bloqueado(SOLO): # sin compartir
        res, sc, t = llama('delphi_search', {'root': B87, 'query': 'aguja', 'pattern': '*.md'})
    j = mc.como_json(t)
    check('E87 todo lo que casa esta bloqueado: SEARCH-003 y SIN SEARCH-002',
          'maskNote' not in j and mc.es(j.get('unreadableNote', ''), 'SN_SEARCH_ILEGIBLES_FMT'), t[:300])

    # E88 section con su valor por defecto (el que publica el esquema) no es CFG-110
    # con un proyecto de verdad: con App.dproj (sin App.dpr) pasaba con un
    # CFG-034 NOT_FOUND, sin llegar a usar el defecto (octava revision)
    res, sc, t = llama('delphi_config', {'command': 'fix-references', 'project': P83,
                                         'section': 'summary'})
    check('E88 fix-references con section=summary (el defecto): NO es CFG-110 y funciona',
          not res.get('isError') and not mc.abre(t, 'SR_CONFIG_NO_ES_DEL_COMANDO_FMT'), t[:200])
    rechazo('E88 ...y con section=platforms si (la regla sigue viva)', 'delphi_config',
            {'command': 'fix-references', 'project': DPROJ, 'section': 'platforms'},
            'INVALID_PARAM', 'SR_CONFIG_NO_ES_DEL_COMANDO_FMT')
    if os.path.exists(GRP):
        rechazo('E88 view de un .groupproj con section: CFG-110 (se ignoraba)', 'delphi_config',
                {'command': 'view', 'project': GRP, 'section': 'platforms'},
                'INVALID_PARAM', 'SR_CONFIG_NO_ES_DEL_COMANDO_FMT')

    # E89 delphi_create con un parametro que no es de su kind
    rechazo('E89 delphi_create unit con formname: CREATE-035 (se ignoraba)', 'delphi_create',
            {'kind': 'unit', 'name': 'USinForm', 'dir': JAIL, 'formname': 'FormX'},
            'INVALID_PARAM', 'SR_CREATE_NO_VA_CON_KIND_FMT')
    check('E89 ...y no se creo nada', not os.path.exists(os.path.join(JAIL, 'USinForm.pas')), '')
    rechazo('E89 project-console con content: CREATE-035 (CREATED con el esqueleto)', 'delphi_create',
            {'kind': 'project-console', 'name': 'ConX', 'dir': os.path.join(JAIL, 'conx'),
             'content': 'program ConX; begin end.'}, 'INVALID_PARAM', 'SR_CREATE_NO_VA_CON_KIND_FMT')

    # E90 delphi_edit / textedit: lo que no es del modo se dice
    rechazo('E90 delphi_edit code sin insert: EDIT-115', 'delphi_edit',
            {'path': U1252, 'old': 'interface', 'new': 'interface', 'code': 'x'},
            'INVALID_PARAM', 'SR_EDIT_NO_VA_CON_MODO_FMT')
    rechazo('E90 delphi_textedit eol sin create: EDIT-115', 'delphi_textedit',
            {'path': NOTES, 'old': 'First line.', 'new': 'First line!', 'eol': 'lf'},
            'INVALID_PARAM', 'SR_EDIT_NO_VA_CON_MODO_FMT')
    rechazo('E90 edits con atline: EDIT-115 (se ignoraba en silencio)', 'delphi_textedit',
            {'path': NOTES, 'edits': json.dumps([{'old': 'First line.', 'new': 'First line!'}]),
             'atline': 3}, 'INVALID_PARAM', 'SR_EDIT_NO_VA_CON_MODO_FMT')
    check('E90 ...NOTES sin tocar', open(NOTES).read() == 'First line.\nSecond line.\n',
          repr(open(NOTES).read()))

    # E91 la forma de la ruta, a la entrada
    rechazo('E91 un comodin en la ruta: GUARD-024 (acababa INTERNAL)', 'delphi_textedit',
            {'path': os.path.join(JAIL, 'm*.txt'), 'create': True, 'content': 'x'},
            'INVALID_PARAM', 'SR_GUARD_COMODIN_FMT')
    rechazo('E91 un fichero con separador final, leido: GUARD-025 (SYS-006 INTERNAL)', 'delphi_read',
            {'path': NOTES + '\\'}, 'INVALID_PARAM', 'SR_GUARD_BARRA_FINAL_FMT')
    rechazo('E91 ...y creado: GUARD-025', 'delphi_textedit',
            {'path': os.path.join(JAIL, 'c7.txt') + '\\', 'create': True, 'content': 'x'},
            'INVALID_PARAM', 'SR_GUARD_BARRA_FINAL_FMT')
    check('E91 ...sin una carpeta c7.txt', not os.path.exists(os.path.join(JAIL, 'c7.txt')), '')

    # E92 changeset delete de un fichero +R: SYS-029 antes de copiar
    ROF = os.path.join(JAIL, 'ro92.txt')
    open(ROF, 'w').write('ro\n')
    with mc.solo_lectura(ROF):
        res, sc, t = llama('delphi_changeset', {'command': 'begin'})
        c92 = mc.id_changeset(t)
        llama('delphi_changeset', {'command': 'stage', 'id': c92, 'kind': 'delete', 'path': ROF})
        # el PREVIEW ya lo dice (octava revision: salia limpio y caia el commit)
        res, sc, t = llama('delphi_changeset', {'command': 'preview', 'id': c92})
        check('E92 changeset delete de un fichero +R: el preview dice SYS-029',
              mc.como_json(t).get('unresolved') == 1 and 'SYS-029' in t, t[:300])
        res, sc, t = llama('delphi_changeset', {'command': 'commit', 'id': c92})
        check('E92 ...el commit no se hace: sigue ahi y SIN copia en deleted',
              res.get('isError') is True and
              os.path.exists(ROF) and not mc.copias(JAIL, 'ro92.txt', 'CAJON_BORRADOS'), t[:300])
        llama('delphi_changeset', {'command': 'rollback', 'id': c92})

    # E93 una junction a un antepasado se borra (el enlace, no lo de detras)
    JA = os.path.join(JAIL, 'e93')
    os.makedirs(JA)
    LNK = os.path.join(JA, 'arriba')
    subprocess.run(['cmd', '/c', 'mklink', '/J', LNK, JAIL], capture_output=True)
    if os.path.isdir(LNK):
        res, sc, t = llama('delphi_delete', {'path': LNK})
        check('E93 borrar una junction a un antepasado: sale, y lo de detras sigue',
              not res.get('isError') and not os.path.lexists(LNK) and os.path.exists(NOTES), t[:200])
        for c in mc.copias(JA, 'arriba', 'CAJON_BORRADOS'):
            os.rmdir(c)  # el enlace aparcado, no lo de detras
    else:
        check('E93 fixture: mklink /J crea la junction', False, LNK)

    # E94 protocolo
    code, h, b = cli.post({'jsonrpc': '2.0', 'id': 1.5, 'method': 'tools/list', 'params': {}},
                          accept='application/json')
    check('E94 id 1.5: -32600 con SYS-031 en JSON (era un 500 sin etiqueta)',
          code == 200 and '-32600' in b and 'SYS-031' in b, '%s %s' % (code, b[:200]))
    code, h, b = cli.post({'jsonrpc': '2.0', 'id': None, 'method': 'tools/list'},
                          accept='application/json')
    check('E94 id null: SYS-031 (se tomaba por notificacion y no se contestaba)',
          code == 200 and 'SYS-031' in b, '%s %s' % (code, b[:200]))
    code, h, b = cli.post({'jsonrpc': '2.0', 'id': 7, 'method': None}, accept='application/json')
    check('E94 method null: SYS-032 con el id 7 (buscaba el metodo "null")',
          'SYS-032' in b and '"id":7' in b.replace(' ', ''), '%s %s' % (code, b[:200]))
    code, h, b = cli.post({'jsonrpc': '2.0', 'id': 8, 'method': 'tools/call', 'params': {'name': None}},
                          accept='application/json')
    check('E94 tools/call con name null: no busca la tool "null"',
          'Tool not found: null' not in b and 'INVALID_PARAM' in b, '%s %s' % (code, b[:200]))
    code, h, b = cli.post({'jsonrpc': '2.0', 'id': 11, 'method': 'tools/list'},
                          sid='{MUERTA-E94}', accept='application/json')
    check('E94 el 404 de una sesion muerta lleva el id de la peticion',
          code == 404 and '"id":11' in b.replace(' ', ''), '%s %s' % (code, b[:200]))
    req = urllib.request.Request(cli.url, method='GET', headers={
        'Accept': 'text/event-stream', 'Authorization': 'Bearer ' + TOK, 'Mcp-Session-Id': '{MUERTA-E94}'})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            gcode = r.status
    except urllib.error.HTTPError as e:
        gcode = e.code
    check('E94 el GET del flujo con una sesion muerta es 404 (era 200)', gcode == 404, gcode)
    # 5.1 de la 1.18.0: con una sesion VIVA, el GET del flujo es 405 (la
    # especificacion se lo deja al servidor que no ofrece flujo en el GET): un
    # 200 que se cerraba al momento hacia que el SDK de Python lo reabriera
    # cada segundo
    req = urllib.request.Request(cli.url, method='GET', headers={
        'Accept': 'text/event-stream', 'Authorization': 'Bearer ' + TOK, 'Mcp-Session-Id': cli.sid or ''})
    gallow = ''
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            gcode = r.status
    except urllib.error.HTTPError as e:
        gcode = e.code
        gallow = e.headers.get('Allow', '')
    check('E94b el GET del flujo con una sesion viva es 405 con su Allow (era 200 y se cerraba)',
          bool(cli.sid) and gcode == 405 and 'POST' in gallow, '%s %r %r' % (gcode, gallow, cli.sid))
    code, h, b = cli.post({'jsonrpc': '2.0', 'method': 'notifications/initialized'},
                          accept='application/json')
    check('E94 el 202 de una notificacion va SIN cuerpo (llevaba el HTML de Indy)',
          code == 202 and b == '', '%s %r' % (code, b[:80]))
    res, sc, t = llama('delphi_installs', {'zz': 1})
    check('E94 SYS-015 de una tool sin parametros: "(none)" (decia "Valid parameters: .")',
          mc.abre(t, 'SR_SYS_UNKNOWN_PARAM_FMT') and '(none)' in t, t[:200])

    # E95 un commit que borra el mismo fichero DOS veces (delete, create,
    # delete): las dos copias caen en el mismo golpe de reloj, tenian el mismo
    # sello y la segunda no se podia escribir (la puerta 18 lo cazo con
    # to-binary + to-text)
    DOS = os.path.join(JAIL, 'dos95.txt')
    open(DOS, 'w').write('v0\n')
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    c95 = mc.id_changeset(t)
    llama('delphi_changeset', {'command': 'stage', 'id': c95, 'kind': 'delete', 'path': DOS})
    llama('delphi_changeset', {'command': 'stage', 'id': c95, 'kind': 'create', 'path': DOS,
                               'content': 'v1\n'})
    llama('delphi_changeset', {'command': 'stage', 'id': c95, 'kind': 'delete', 'path': DOS})
    llama('delphi_changeset', {'command': 'preview', 'id': c95})
    res, sc, t = llama('delphi_changeset', {'command': 'commit', 'id': c95})
    cop95 = sorted(open(c).read() for c in mc.copias(JAIL, 'dos95.txt', 'CAJON_BORRADOS'))
    check('E95 dos copias del mismo fichero seguidas: las DOS, con nombres distintos',
          not res.get('isError') and not os.path.exists(DOS) and cop95 == ['v0\n', 'v1\n'],
          '%s | %s' % (t[:200], cop95))

    # E95b lo mismo, DETERMINISTA: E95 solo caia si las dos copias coincidian en
    # el golpe de reloj (4 de 30 contra la version sin arreglo). Se plantan los
    # nombres sellados de los proximos 400 ms en deleted\ y se borra: sin la
    # espera al sello siguiente, la copia chocaba con uno plantado (FILE-020).
    # La ventana se abre DESPUES de plantar (7.5 de la 1.18.0): empezaba al
    # plantar, y 400 ficheros tardan 0,26 s solos y 0,38 con las baterias en
    # paralelo recien arrancado el PC, asi que un rojo de carga costaba un
    # run_all. Ahora se planta para dentro de medio segundo y la llamada
    # espera a que se abra: el guardian mide lo mismo con margen.
    D95 = os.path.join(JAIL, 'e95b')
    os.makedirs(D95)
    F95 = os.path.join(D95, 'dos95.txt')
    open(F95, 'w').write('v0\n')
    PAP = mc._papelera()
    ahora = datetime.datetime.now()
    CAJ95 = os.path.join(D95, PAP['BACKUP_SUB'], ahora.strftime('%Y%m%d'), PAP['CAJON_BORRADOS'])
    os.makedirs(CAJ95)
    ABRE95 = 0.5  # segundos: la ventana se abre aqui, despues de plantar
    inicio95 = ahora + datetime.timedelta(seconds=ABRE95)
    for ms in range(0, 400):
        sello = (inicio95 + datetime.timedelta(milliseconds=ms)).strftime('%H%M%S%f')[:9]
        open(os.path.join(CAJ95, 'dos95.txt-' + sello), 'w').write('plantado\n')
    espera95 = (inicio95 - datetime.datetime.now()).total_seconds()
    if espera95 > 0:
        time.sleep(espera95 + 0.01)  # nunca un milisegundo antes de abrirse
    plantado_en = (datetime.datetime.now() - inicio95).total_seconds() # tras abrirse la ventana
    res, sc, t = llama('delphi_delete', {'path': F95})
    buenas = [c for c in mc.copias(D95, 'dos95.txt', 'CAJON_BORRADOS') if open(c).read() == 'v0\n']
    # la llamada EMPEZO dentro de la ventana y su copia se sello al final de
    # ella: solo pudo esperar (una llamada tardia pasaba sin ejercitar nada)
    sello95 = -1.0
    if len(buenas) == 1:
        s95 = buenas[0][-9:]
        sello95 = (inicio95.replace(hour=int(s95[0:2]), minute=int(s95[2:4]), second=int(s95[4:6]),
                                    microsecond=int(s95[6:9]) * 1000) - inicio95).total_seconds()
    check('E95b fixture: la llamada empieza dentro de la ventana (%.2f s de 0.40)' % plantado_en,
          0 <= plantado_en < 0.35, plantado_en)
    check('E95b ...y su copia se sella al acabar la ventana (%.3f s): espero' % sello95,
          0.399 <= sello95 <= 0.7, sello95)
    check('E95b con los sellos de los proximos 400 ms ocupados, el borrado espera al siguiente libre',
          not res.get('isError') and not os.path.exists(F95) and len(buenas) == 1,
          '%s | %s' % (t[:200], buenas))

    # E96 delphi_delete de un fichero +R: SYS-029 (lo borraba; el changeset ya lo decia)
    D96 = os.path.join(JAIL, 'e96')
    os.makedirs(D96)
    RO96 = os.path.join(D96, 'ro96.txt')
    open(RO96, 'w').write('ro\n')
    with mc.solo_lectura(RO96):
        t = rechazo('E96 delphi_delete de un fichero +R: SYS-029 (lo borraba)', 'delphi_delete',
                    {'path': RO96}, 'DENIED', 'SR_SOLO_LECTURA_ATRIBUTO_FMT')
        check('E96 ...sigue ahi y no queda papelera', os.path.exists(RO96) and
              not os.path.exists(os.path.join(D96, PAP['BACKUP_SUB'])), os.listdir(D96))

    # E97 una carpeta que no se deja mover no deja su cajon del dia vacio
    D97 = os.path.join(JAIL, 'e97')
    os.makedirs(os.path.join(D97, 'dentro'))
    F97 = os.path.join(D97, 'dentro', 'f.txt')
    open(F97, 'w').write('x\n')
    abierto = open(F97, 'r')
    try:
        res, sc, t = llama('delphi_delete', {'path': os.path.join(D97, 'dentro')})
    finally:
        abierto.close()
    check('E97 una carpeta que no se deja mover: fallo, sigue ahi y SIN papelera vacia a su lado',
          res.get('isError') is True and os.path.exists(F97) and
          not os.path.exists(os.path.join(D97, PAP['BACKUP_SUB'])), '%s | %s' % (t[:200], os.listdir(D97)))

    # E98 una tanda con un BLOQUE que no cambia nada: UNCHANGED (EDIT-114)
    D98 = os.path.join(JAIL, 'e98')
    os.makedirs(D98)
    B98 = os.path.join(D98, 'Bloque.pas')
    open(B98, 'w', newline='\r\n').write('unit Bloque;\ninterface\nimplementation\nend.\n')
    res, sc, t = llama('delphi_edit', {'path': B98, 'edits': json.dumps(
        [{'old': 'interface\nimplementation', 'new': 'interface\nimplementation'}])})
    check('E98 una tanda cuyo bloque no cambia nada: EDIT-114 y sin papelera',
          not res.get('isError') and mc.abre(t, 'SN_PATCH_EDITS_SIN_CAMBIOS_FMT') and
          not os.path.exists(os.path.join(D98, PAP['BACKUP_SUB'])), t[:200])

    # E99 delphi_package sobre un .zip +R: SYS-029 (decia "reintenta en unos segundos")
    D99 = os.path.join(JAIL, 'e99')
    os.makedirs(os.path.join(D99, 'src'))
    open(os.path.join(D99, 'src', 'a.txt'), 'w').write('a\n')
    Z99 = os.path.join(D99, 'out.zip')
    open(Z99, 'wb').write(b'PK\x05\x06' + b'\0' * 18)
    with mc.solo_lectura(Z99):
        rechazo('E99 delphi_package sobre un .zip +R: SYS-029', 'delphi_package',
                {'dir': os.path.join(D99, 'src'), 'outfile': Z99}, 'DENIED', 'SR_SOLO_LECTURA_ATRIBUTO_FMT')

    # E100 buscar en un fichero de CR sueltos: las lineas como delphi_read
    D100 = os.path.join(JAIL, 'e100')
    os.makedirs(D100)
    open(os.path.join(D100, 'cr.txt'), 'wb').write(b'uno\rdos\raguja\r')
    res, sc, t = llama('delphi_search', {'root': D100, 'query': 'aguja', 'pattern': '*.txt'})
    lineas = [h.get('line') for h in mc.aciertos(t)]
    check('E100 buscar en un fichero de CR sueltos: linea 3 (el CR suelto es salto)',
          lineas == [3], '%s | %s' % (lineas, t[:200]))

    # E101 //?/ con barras normales es un prefijo de dispositivo como \\?\
    rechazo('E101 //?/ con barras normales: GUARD-022', 'delphi_read',
            {'path': '//?/' + NOTES.replace('\\', '/')}, 'INVALID_PARAM', 'SR_GUARD_PREFIJO_DISPOSITIVO_FMT')

    # E102 el salto DOMINANTE en un bloque: un fichero LF con un CRLF queda en
    # LF (el bloque unia con CRLF si habia alguno; una edicion de linea, con LF)
    D102 = os.path.join(JAIL, 'e102')
    os.makedirs(D102)
    MX = os.path.join(D102, 'mx.txt')
    open(MX, 'wb').write(b'uno\ndos\r\ntres\ncuatro\ncinco\n')
    res, sc, t = llama('delphi_textedit', {'path': MX, 'edits': json.dumps(
        [{'old': 'tres\ncuatro', 'new': 'TRES\nCUATRO'}])})
    b102 = open(MX, 'rb').read()
    check('E102 un bloque en un fichero LF con un CRLF: todo en LF, como una edicion de linea',
          not res.get('isError') and b102 == b'uno\ndos\nTRES\nCUATRO\ncinco\n', '%s | %r' % (t[:160], b102))

    # E103 un clientInfo que no es un objeto no rompe el initialize
    code, h, b = cli.post({'jsonrpc': '2.0', 'id': 21, 'method': 'initialize', 'params': {
        'protocolVersion': '2025-03-26', 'capabilities': {}, 'clientInfo': 5}}, sid='{NUEVA-E103}',
        accept='application/json')
    check('E103 initialize con clientInfo=5: sesion nueva (era -32603 "Invalid class typecast")',
          code == 200 and '"result"' in b and '-32603' not in b and bool(h.get('Mcp-Session-Id')),
          '%s %s' % (code, b[:200]))

    # E104 mover una junction: se mueve el ENLACE, sin copia de lo de detras (la
    # copia de seguridad copiaba el arbol al que apunta; a un antepasado fallaba)
    D104 = os.path.join(JAIL, 'e104')
    os.makedirs(D104)
    L104 = os.path.join(D104, 'arriba')
    subprocess.run(['cmd', '/c', 'mklink', '/J', L104, JAIL], capture_output=True)
    if os.path.isdir(L104):
        L104B = os.path.join(D104, 'arriba2')
        res, sc, t = llama('delphi_move', {'path': L104, 'dest': L104B})
        es_enlace = os.path.lexists(L104B) and bool(
            os.lstat(L104B).st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT)
        check('E104 mover una junction a un antepasado: se mueve el enlace y no hay copia',
              not res.get('isError') and not os.path.lexists(L104) and es_enlace and
              os.path.exists(NOTES) and not mc.copias(D104, 'arriba', 'CAJON_BORRADOS'), t[:200])
        if os.path.lexists(L104B):
            os.rmdir(L104B)  # el enlace, no lo de detras
    else:
        check('E104 fixture: mklink /J crea la junction', False, L104)

    # E105 styles delete con child: se borraba el estilo ENTERO
    ANT105 = open(ESTILO, 'rb').read()
    rechazo('E105 styles delete con child: STYLE-043 (borraba el estilo entero)', 'delphi_styles',
            {'command': 'delete', 'path': ESTILO, 'style': 'boton', 'child': 'x'},
            'INVALID_PARAM', 'SR_STYLES_NO_VA_CON_COMANDO_FMT')
    check('E105 ...el .style sin tocar', open(ESTILO, 'rb').read() == ANT105, '')

    # E106 git commit con path: commiteaba TODO el indice
    rechazo('E106 git commit con path: GIT-038 (commiteaba todo el indice)', 'delphi_git',
            {'command': 'commit', 'repo': NOREPO, 'message': 'x', 'path': NOTES},
            'INVALID_PARAM', 'SR_GIT_NO_VA_CON_COMANDO_FMT')

    # E107 changeset: lo que no va con el comando (CHSET-031) y lo que no va con
    # el kind, diciendo lo que el kind toma (CHSET-030)
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    c107 = mc.id_changeset(t)
    rechazo('E107 changeset commit con kind: CHSET-031 (se ignoraba)', 'delphi_changeset',
            {'command': 'commit', 'id': c107, 'kind': 'edit'}, 'INVALID_PARAM',
            'SR_CHANGESET_NO_VA_CON_COMANDO_FMT')
    t = rechazo('E107 stage create con old: CHSET-030', 'delphi_changeset',
                {'command': 'stage', 'id': c107, 'kind': 'create', 'path': os.path.join(JAIL, 'n107.txt'),
                 'content': 'x', 'old': 'y'}, 'INVALID_PARAM', 'SR_CHANGESET_NO_ES_DE_KIND_FMT')
    check('E107 ...y dice lo que toma create (path content)', 'path content' in t, t[:200])
    llama('delphi_changeset', {'command': 'rollback', 'id': c107})

    # E108 un nombre de mas de 255 caracteres: SYS-009 INTERNAL al escribir
    rechazo('E108 un nombre de 300 caracteres: GUARD-026', 'delphi_textedit',
            {'path': os.path.join(JAIL, 'n' * 300 + '.txt'), 'create': True, 'content': 'x'},
            'INVALID_PARAM', 'SR_GUARD_NOMBRE_LARGO_FMT')

    # E109 GUARD-010 de "...": sugeria 'Did you mean ""?'
    t = rechazo('E109 una carpeta "...": GUARD-010', 'delphi_read',
                {'path': os.path.join(JAIL, '...', 'x.txt')}, 'INVALID_PARAM',
                'SR_GUARD_NOMBRE_EMPIEZA_TERMINA_PUNTO_FMT')
    check('E109 ...sin sugerir un nombre vacio', 'Did you mean ""' not in t, t[:200])

    # E110 un kind que no existe lo dice antes que la regla de parametros
    rechazo('E110 kind=project-foo con content: CREATE-011 (CREATE-035 decia lo que toma)',
            'delphi_create', {'kind': 'project-foo', 'name': 'Foo', 'dir': os.path.join(JAIL, 'foo'),
                              'content': 'x'}, 'INVALID_PARAM', 'SR_CREATE_PROJECT_KIND')
    rechazo('E110 ...kind=frame-foo: CREATE-021', 'delphi_create',
            {'kind': 'frame-foo', 'name': 'Foo', 'dir': os.path.join(JAIL, 'foo'), 'content': 'x'},
            'INVALID_PARAM', 'SR_CREATE_KIND_DEBE_SER_FORM')
    rechazo('E110 ...y kind=widget: CREATE-034', 'delphi_create',
            {'kind': 'widget', 'name': 'Foo', 'dir': os.path.join(JAIL, 'foo'), 'content': 'x'},
            'INVALID_PARAM', 'SR_CREATE_KIND_DEBE_SER_ALL')

    # E111 delete-line compara old con la regla del motor (sin la sangria en Pascal)
    D111 = os.path.join(JAIL, 'e111')
    os.makedirs(D111)
    P111 = os.path.join(D111, 'Dl.pas')
    open(P111, 'w', newline='\n').write('unit Dl;\ninterface\n  const X = 1;\nimplementation\nend.\n')
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    c111 = mc.id_changeset(t)
    llama('delphi_changeset', {'command': 'stage', 'id': c111, 'kind': 'delete-line', 'path': P111,
                               'atline': 3, 'old': 'const X = 1;'})
    res, sc, t = llama('delphi_changeset', {'command': 'preview', 'id': c111})
    check('E111 delete-line con old sin la sangria (Pascal): el preview sale limpio',
          mc.como_json(t).get('unresolved') == 0, t[:300])
    res, sc, t = llama('delphi_changeset', {'command': 'commit', 'id': c111})
    check('E111 ...y el commit borra esa linea',
          not res.get('isError') and open(P111, newline='').read() ==
          'unit Dl;\ninterface\nimplementation\nend.\n', '%s | %r' % (t[:160], open(P111, newline='').read()))

    # E112 el preview ve el ancla como el motor: dos lineas que casan (con y sin
    # sangria) salian limpias en el preview y el commit hacia ROLLBACK EDIT-077
    P112 = os.path.join(D111, 'Pr.pas')
    open(P112, 'w', newline='\n').write('program Pr;\nbegin\nWriteln(1);\n  Writeln(1);\nend.\n')
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    c112 = mc.id_changeset(t)
    llama('delphi_changeset', {'command': 'stage', 'id': c112, 'kind': 'edit', 'path': P112,
                               'old': 'Writeln(1);', 'new': 'Writeln(2);'})
    res, sc, t = llama('delphi_changeset', {'command': 'preview', 'id': c112})
    check('E112 un ancla que el motor ve dos veces: el preview no sale limpio',
          mc.como_json(t).get('unresolved') == 1, t[:300])
    llama('delphi_changeset', {'command': 'rollback', 'id': c112})

    # E113 /files: el nombre con tilde en filename*, y la ruta TAL CUAL a las reglas
    ACC = os.path.join(JAIL, 'canci\u00f3n.txt')
    open(ACC, 'w').write('x\n')

    def files_get(ruta):
        req = urllib.request.Request('http://127.0.0.1:%d/files?path=%s' % (
            PORT, urllib.parse.quote(ruta, safe='')), headers={'Authorization': 'Bearer ' + TOK})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.status, r.headers, r.read()
        except urllib.error.HTTPError as e:
            return e.code, e.headers, e.read()

    code, h, b = files_get(ACC)
    cd = (h.get('Content-Disposition') or '') if h else ''
    check('E113 /files de un nombre con tilde: filename* en UTF-8 (llegaba "canci?n")',
          code == 200 and "filename*=UTF-8''canci%C3%B3n.txt" in cd, '%s %s' % (code, cd))
    code, h, b = files_get(NOTES + ' ')
    check('E113 /files con un espacio al final: 400 GUARD-010 (servia el fichero sin el espacio)',
          code == 400 and b'GUARD-010' in b, '%s %r' % (code, b[:160]))

    # E114 protocolo: UNA regla para lo que no se contesta, y lo mal formado es -32600
    code, h, b = cli.post({}, accept='application/json')
    check('E114 {}: -32600 (no recibia nada)', '-32600' in b, '%s %r' % (code, b[:160]))
    code, h, b = cli.post([], accept='application/json')
    check('E114 []: -32600 (era un 202)', code == 200 and '-32600' in b, '%s %r' % (code, b[:160]))
    code, h, b = cli.post([{'jsonrpc': '2.0', 'id': 31, 'method': 'tools/list'}], accept='application/json')
    check('E114 un lote con peticiones: -32600 (era -32700 "no es JSON")',
          '-32600' in b and '-32700' not in b, '%s %r' % (code, b[:160]))
    code, h, b = cli.post({'jsonrpc': '2.0', 'id': 32, 'result': {}}, accept='application/json')
    check('E114 una respuesta del cliente por HTTP: 202 sin cuerpo', code == 202 and b == '',
          '%s %r' % (code, b[:160]))
    code, h, b = cli.post([{'jsonrpc': '2.0', 'method': 'notifications/x'}], accept='application/json')
    check('E114 un lote solo de notificaciones: 202', code == 202 and b == '', '%s %r' % (code, b[:160]))
    # E172 (1.7.2) lo mal formado SIN id tambien se contesta: {"method":5} sin
    # id no es una notificacion (JSON-RPC pide -32600 con id null); se callaba
    code, h, b = cli.post({'jsonrpc': '2.0', 'method': 5}, accept='application/json')
    check('E172 {"method":5} sin id: -32600 con id null y SYS-032 (era un 202 mudo)',
          code == 200 and '-32600' in b and 'SYS-032' in b and '"id":null' in b.replace(' ', ''),
          '%s %r' % (code, b[:200]))
    code, h, b = cli.post({'jsonrpc': '2.0', 'id': 7, 'method': 'notifications/initialized'},
                          accept='application/json')
    check('E172 notifications/initialized como PETICION: lleva result {} (contestaba sin result)',
          code == 200 and mc.como_json(b).get('result') == {}, '%s %r' % (code, b[:200]))
    std = mc.Stdio(EXE, env=mc.entorno(), nombre='e114')
    try:
        std.send({'jsonrpc': '2.0', 'id': 33, 'result': {}})
        std.send({'jsonrpc': '2.0', 'id': 34, 'method': 'tools/list'})
        vistos = []
        fin114 = time.time() + 60
        while time.time() < fin114 and 34 not in vistos:
            try:
                vistos.append(json.loads(std.q.get(timeout=1)).get('id'))
            except Exception:
                pass
        check('E114 ...y por stdio la misma regla: sin respuesta (contestaba SYS-032)',
              34 in vistos and 33 not in vistos, vistos)
    finally:
        std.cierra()

    # E115 una sesion muerta: un initialize que falla no la devuelve en la
    # cabecera, y el GET sin flujo tambien es 404
    code, h, b = cli.post({'jsonrpc': '2.0', 'id': 1.5, 'method': 'initialize', 'params': {}},
                          sid='{MUERTA-E115}', accept='application/json')
    check('E115 un initialize que falla con una sesion muerta: no la devuelve en la cabecera',
          '-32600' in b and (h.get('Mcp-Session-Id') if h else None) != '{MUERTA-E115}',
          '%s %s %s' % (code, h.get('Mcp-Session-Id') if h else None, b[:160]))
    req = urllib.request.Request(cli.url, method='GET', headers={
        'Accept': 'application/json', 'Authorization': 'Bearer ' + TOK, 'Mcp-Session-Id': '{MUERTA-E115}'})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            gcode = r.status
    except urllib.error.HTTPError as e:
        gcode = e.code
    check('E115 el GET sin event-stream con una sesion muerta es 404 (era 200 sin puerta)',
          gcode == 404, gcode)

    # E116 un recurso que no existe es -32002, el codigo de MCP (era -32602)
    code, h, b = cli.post({'jsonrpc': '2.0', 'id': 41, 'method': 'resources/read',
                           'params': {'uri': 'nope://x'}}, accept='application/json')
    check('E116 resources/read de un recurso que no existe: -32002', '-32002' in b, '%s %r' % (code, b[:160]))

    # E117 los enteros se publican como integer (el binder solo acepta enteros)
    m117 = cli.request('tools/list')
    props = next((x.get('inputSchema', {}).get('properties', {})
                  for x in ((m117 or {}).get('result') or {}).get('tools', [])
                  if x.get('name') == 'delphi_read'), {})
    check('E117 delphi_read fromline es "integer" en el esquema (decia "number")',
          props.get('fromline', {}).get('type') == 'integer', props.get('fromline'))

    # E118 un .dproj en LF sigue en LF tras delphi_config (quedaba mezclado)
    D118 = os.path.join(JAIL, 'e118')
    os.makedirs(os.path.join(D118, 'lib'))
    LF118 = os.path.join(D118, 'Lf.dproj')
    open(LF118, 'w', newline='\n').write(
        '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n'
        '    <PropertyGroup>\n'
        '        <MainSource>Lf.dpr</MainSource>\n'
        '    </PropertyGroup>\n'
        '    <PropertyGroup Condition="\'$(Base)\'!=\'\'">\n'
        '        <DCC_Namespace>System</DCC_Namespace>\n'
        '    </PropertyGroup>\n'
        '</Project>\n')
    res, sc, t = llama('delphi_config', {'command': 'add-searchpath', 'project': LF118, 'path': 'lib'})
    b118 = open(LF118, 'rb').read()
    check('E118 add-searchpath en un .dproj en LF: sigue en LF',
          not res.get('isError') and b'DCC_UnitSearchPath' in b118 and b'\r\n' not in b118,
          '%s | %r' % (t[:160], b118[:300]))

    # E119 deshacer el borrado de una unit no deja la copia de su form en deleted\
    D119 = os.path.join(JAIL, 'e119')
    os.makedirs(D119)
    P119 = os.path.join(D119, 'UFo.pas')
    F119 = os.path.join(D119, 'UFo.dfm')
    open(P119, 'w').write('unit UFo;\ninterface\nimplementation\n{$R *.dfm}\nend.\n')
    open(F119, 'w').write('object Fo: TFo\nend\n')
    ANT119 = open(F119, 'rb').read()
    with mc.bloqueado(P119, lectura=True): # leer si; mover no
        res, sc, t = llama('delphi_delete', {'path': P119})
    check('E119 borrar una unit cuyo .pas no se deja mover: el form vuelve y SIN su copia',
          res.get('isError') is True and os.path.exists(P119) and open(F119, 'rb').read() == ANT119 and
          not mc.copias(D119, 'UFo.dfm') and not os.path.exists(os.path.join(D119, PAP['BACKUP_SUB'])),
          '%s | %s' % (t[:250], os.listdir(D119)))

    # E121 lo que genera project-test, en ingles
    D121 = os.path.join(JAIL, 'e121')
    res, sc, t = llama('delphi_create', {'kind': 'project-test', 'name': 'PruebasX', 'dir': D121})
    gen = ''
    for raiz, _d, fs in os.walk(D121):
        for f in fs:
            if f.lower().endswith(('.pas', '.dpr')):
                gen += open(os.path.join(raiz, f), encoding='utf-8', errors='replace').read()
    check('E121 project-test genera en ingles (Skeleton; ni Esqueleto ni "filtro")',
          not res.get('isError') and 'Skeleton' in gen and 'Esqueleto' not in gen and 'filtro' not in gen,
          t[:200])

    # E122 delphi_package no mete la papelera en el zip
    D122 = os.path.join(JAIL, 'e122')
    SRC122 = os.path.join(D122, 'src')
    os.makedirs(os.path.join(SRC122, PAP['BACKUP_SUB'], ahora.strftime('%Y%m%d')))
    open(os.path.join(SRC122, 'a.txt'), 'w').write('a\n')
    open(os.path.join(SRC122, PAP['BACKUP_SUB'], ahora.strftime('%Y%m%d'), 'a.txt'), 'w').write('antes\n')
    Z122 = os.path.join(D122, 'p.zip')
    res, sc, t = llama('delphi_package', {'dir': SRC122, 'outfile': Z122})
    nombres = zipfile.ZipFile(Z122).namelist() if os.path.exists(Z122) else []
    check('E122 delphi_package: a.txt dentro y la papelera fuera',
          not res.get('isError') and any(n.endswith('a.txt') for n in nombres) and
          not any(PAP['BACKUP_SUB'] in n for n in nombres), '%s | %s' % (t[:160], nombres))

    # E123 mover una unit cuyo form no se deja mover: todo o nada (MOVE-017)
    D123 = os.path.join(JAIL, 'e123')
    os.makedirs(D123)
    P123 = os.path.join(D123, 'UMv.pas')
    F123 = os.path.join(D123, 'UMv.dfm')
    open(P123, 'w').write('unit UMv;\ninterface\nimplementation\n{$R *.dfm}\nend.\n')
    open(F123, 'w').write('object Mv: TMv\nend\n')
    with mc.bloqueado(F123, lectura=True): # leer si; mover no
        res, sc, t = llama('delphi_move', {'path': P123, 'dest': os.path.join(D123, 'sub', 'UMv.pas')})
    check('E123 mover una unit cuyo .dfm no se deja: MOVE-017 y NADA movido',
          res.get('isError') is True and mc.abre(t, 'SR_MOVE_FORM_NO_VA_FMT') and os.path.exists(P123) and
          os.path.exists(F123) and not os.path.exists(os.path.join(D123, 'sub', 'UMv.pas')),
          '%s | %s' % (t[:250], os.listdir(D123)))
    check('E123 ...y sin copia de seguridad en la papelera', not mc.copias(D123),
          mc.copias(D123))

    # E124 el DESTINO de un move con separador final: GUARD-025 (creaba la carpeta)
    D124 = os.path.join(JAIL, 'e124')
    os.makedirs(D124)
    G124 = os.path.join(D124, 'g.txt')
    open(G124, 'w').write('g\n')
    rechazo('E124 move a "h.txt\\": GUARD-025', 'delphi_move',
            {'path': G124, 'dest': os.path.join(D124, 'h.txt') + '\\'}, 'INVALID_PARAM',
            'SR_GUARD_BARRA_FINAL_FMT')
    check('E124 ...sin carpeta h.txt, el origen sigue y sin copia',
          not os.path.exists(os.path.join(D124, 'h.txt')) and os.path.exists(G124) and
          not mc.copias(D124), os.listdir(D124))

    # E125 un changeset que crea "n.txt\" se para al apilar (solo lo paraba el preview)
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    c125 = mc.id_changeset(t)
    rechazo('E125 stage create de "n.txt\\": GUARD-025 al apilar', 'delphi_changeset',
            {'command': 'stage', 'id': c125, 'kind': 'create', 'path': os.path.join(D124, 'n.txt') + '\\',
             'content': 'x'}, 'INVALID_PARAM', 'SR_GUARD_BARRA_FINAL_FMT')
    llama('delphi_changeset', {'command': 'rollback', 'id': c125})

    # ------------------------------------------------------------ novena revision
    # E128 REGRESION de la octava: una edicion de UNA linea con un new de VARIAS
    # en un fichero CRLF metia sus saltos en LF (el motor unia con el salto del
    # fichero y los de dentro de la linea editada se quedaban). Ninguna bateria
    # miraba los bytes tras un new multilinea; lo cazo EDIT-082 en vivo
    D128 = os.path.join(JAIL, 'e128')
    os.makedirs(D128)
    P128 = os.path.join(D128, 'Multi.pas')
    open(P128, 'wb').write(b'unit Multi;\r\ninterface\r\nimplementation\r\nend.\r\n')
    res, sc, t = llama('delphi_edit', {'path': P128, 'old': 'implementation',
                                       'new': 'implementation\n\nconst\n  X = 1;'})
    b128 = open(P128, 'rb').read()
    check('E128 un new de varias lineas en un fichero CRLF: todo CRLF (quedaba mezclado)',
          not res.get('isError') and b128 == b'unit Multi;\r\ninterface\r\nimplementation\r\n\r\n'
          b'const\r\n  X = 1;\r\nend.\r\n', '%s | %r' % (t[:160], b128))

    # E129 registrar una unit en un .dproj en LF lo deja en LF (add-unit y
    # delphi_create con project metian su DCCReference en CRLF)
    D129 = os.path.join(JAIL, 'e129')
    res, sc, t = llama('delphi_create', {'kind': 'project-console', 'name': 'Lf129', 'dir': D129})
    DPROJ129 = os.path.join(D129, 'Lf129.dproj')
    if os.path.exists(DPROJ129):
        for f in (DPROJ129, os.path.join(D129, 'Lf129.dpr')):
            datos = open(f, 'rb').read()  # ANTES de abrir para escribir (lo truncaba)
            open(f, 'wb').write(datos.replace(b'\r\n', b'\n'))
        res, sc, t = llama('delphi_create', {'kind': 'unit', 'name': 'UEnLf', 'project': DPROJ129})
        b129 = open(DPROJ129, 'rb').read()
        check('E129 delphi_create unit con project en un .dproj LF: sigue en LF',
              not res.get('isError') and b'UEnLf' in b129 and b'\r\n' not in b129, t[:200])
        open(os.path.join(D129, 'UOtra.pas'), 'w', newline='\n').write(
            'unit UOtra;\ninterface\nimplementation\nend.\n')
        res, sc, t = llama('delphi_config', {'command': 'add-unit', 'project': DPROJ129,
                                             'path': os.path.join(D129, 'UOtra.pas')})
        b129 = open(DPROJ129, 'rb').read()
        check('E129 ...y add-unit tambien', not res.get('isError') and b'UOtra' in b129 and
              b'\r\n' not in b129, t[:200])
    else:
        check('E129 fixture: el proyecto se crea', False, t[:200])

    # E130 renombrar una unit cuyos usuarios estan en CR sueltos reescribe sus
    # referencias (troceaba solo por LF: MOVED y el build caia)
    D130 = os.path.join(JAIL, 'e130')
    res, sc, t = llama('delphi_create', {'kind': 'project-console', 'name': 'Cr130', 'dir': D130})
    DPROJ130 = os.path.join(D130, 'Cr130.dproj')
    open(os.path.join(D130, 'UDos.pas'), 'wb').write(
        b'unit UDos;\rinterface\rprocedure P;\rimplementation\rprocedure P;\rbegin\rend;\rend.\r')
    UUNO = os.path.join(D130, 'UUno.pas')
    open(UUNO, 'wb').write(
        b'unit UUno;\rinterface\ruses UDos;\rimplementation\rprocedure Q;\rbegin\r  UDos.P;\rend;\rend.\r')
    for u in ('UDos.pas', 'UUno.pas'):
        llama('delphi_config', {'command': 'add-unit', 'project': DPROJ130, 'path': os.path.join(D130, u)})
    res, sc, t = llama('delphi_move', {'path': os.path.join(D130, 'UDos.pas'),
                                       'dest': os.path.join(D130, 'UTres.pas')})
    b130 = open(UUNO, 'rb').read()
    check('E130 renombrar UDos con usuarios en CR sueltos: UUno pasa a UTres, byte a byte',
          not res.get('isError') and b130 == b130.replace(b'UDos', b'UTres') and
          b'uses UTres;\r' in b130 and b'  UTres.P;\r' in b130 and b'\n' not in b130,
          '%s | %r' % (t[:200], b130))

    # E131 un proyecto que otro proceso tiene abierto NO es "ninguno la lista":
    # la unit suelta (.dpr bloqueado) y la carpeta (.dproj bloqueado)
    D131 = os.path.join(JAIL, 'e131')
    res, sc, t = llama('delphi_create', {'kind': 'project-console', 'name': 'Lk131', 'dir': D131})
    DPR131 = os.path.join(D131, 'Lk131.dpr')
    DPROJ131 = os.path.join(D131, 'Lk131.dproj')
    llama('delphi_create', {'kind': 'unit', 'name': 'UUnaSuelta', 'project': DPROJ131})
    llama('delphi_create', {'kind': 'unit', 'name': 'UEnMods', 'project': DPROJ131, 'dir': 'mods'})
    ANT131 = open(DPR131, 'rb').read()
    with mc.bloqueado(DPR131): # sin compartir
        res, sc, t = llama('delphi_delete', {'path': os.path.join(D131, 'UUnaSuelta.pas')})
    check('E131 borrar una unit con su .dpr bloqueado: CFG-111 con SYS-027 y la unit sigue (decia "ningun .dpr la lista")',
          res.get('isError') is True and mc.abre(t, 'SR_PROYECTO_NO_LEIDO_AL_BUSCAR_FMT') and
          mc.es(t, 'SR_FICHERO_OCUPADO_FMT') and
          os.path.exists(os.path.join(D131, 'UUnaSuelta.pas')) and open(DPR131, 'rb').read() == ANT131,
          t[:250])
    with mc.bloqueado(DPROJ131):
        res, sc, t = llama('delphi_delete', {'path': os.path.join(D131, 'mods')})
    check('E131 ...y una carpeta con el .dproj bloqueado: SYS-027 y nada tocado (decia DELETED)',
          res.get('isError') is True and mc.abre(t, 'SR_FICHERO_OCUPADO_FMT') and
          os.path.exists(os.path.join(D131, 'mods', 'UEnMods.pas')) and
          open(DPR131, 'rb').read() == ANT131, t[:250])

    # E132 un \\?\UNC\ leido de un .dpr no se resuelve en el disco (21 s de SMB)
    D132 = os.path.join(JAIL, 'e132')
    res, sc, t = llama('delphi_create', {'kind': 'project-console', 'name': 'Unc132', 'dir': D132})
    DPR132 = os.path.join(D132, 'Unc132.dpr')
    DPROJ132 = os.path.join(D132, 'Unc132.dproj')
    llama('delphi_create', {'kind': 'unit', 'name': 'ULocal', 'project': DPROJ132})
    txt132 = open(DPR132, encoding='utf-8-sig').read()
    open(DPR132, 'w').write(txt132.replace(
        'uses', "uses\n  ULejos in '\\\\?\\UNC\\10.255.255.1\\share\\a~1\\ULejos.pas',", 1))
    t0 = time.time()
    res, sc, t = llama('delphi_move', {'path': os.path.join(D132, 'ULocal.pas'),
                                       'dest': os.path.join(D132, 'ULocal2.pas')})
    dt = time.time() - t0
    check('E132 mover una unit con un \\\\?\\UNC\\ en el .dpr: en %.1f s, sin SMB' % dt,
          not res.get('isError') and dt < 5, t[:200])

    # E133 una unit con .dfm Y .fmx: si el .fmx no se deja mover, el .dfm vuelve
    # (se quedaba en el destino) y la carpeta de destino que se creo, tambien fuera
    D133 = os.path.join(JAIL, 'e133')
    os.makedirs(D133)
    for ext, txt in (('.pas', 'unit UF;\ninterface\nimplementation\n{$R *.dfm}\nend.\n'),
                     ('.dfm', 'object F: TF\nend\n'), ('.fmx', 'object F: TF\nend\n')):
        open(os.path.join(D133, 'UF' + ext), 'w').write(txt)
    with mc.bloqueado(os.path.join(D133, 'UF.fmx'), lectura=True):
        res, sc, t = llama('delphi_move', {'path': os.path.join(D133, 'UF.pas'),
                                           'dest': os.path.join(D133, 'sub', 'VF.pas')})
    check('E133 .dfm y .fmx con el .fmx bloqueado: MOVE-017, los tres en su sitio y sin carpeta sub',
          res.get('isError') is True and mc.abre(t, 'SR_MOVE_FORM_NO_VA_FMT') and
          all(os.path.exists(os.path.join(D133, 'UF' + e)) for e in ('.pas', '.dfm', '.fmx')) and
          not os.path.exists(os.path.join(D133, 'sub')), '%s | %s' % (t[:250], os.listdir(D133)))

    # E134 renombrar una unit +R: se dice ANTES de mover (MOVED con "unit UOld;")
    D134 = os.path.join(JAIL, 'e134')
    os.makedirs(D134)
    P134 = os.path.join(D134, 'URo.pas')
    open(P134, 'w').write('unit URo;\ninterface\nimplementation\nend.\n')
    with mc.solo_lectura(P134):
        rechazo('E134 renombrar una unit +R: SYS-029 y nada movido', 'delphi_move',
                {'path': P134, 'dest': os.path.join(D134, 'URo2.pas')}, 'DENIED',
                'SR_SOLO_LECTURA_ATRIBUTO_FMT')
        check('E134 ...sigue donde estaba', os.path.exists(P134) and
              not os.path.exists(os.path.join(D134, 'URo2.pas')), os.listdir(D134))

    # E135 un move que falla no deja las carpetas de destino que creo
    D135 = os.path.join(JAIL, 'e135')
    os.makedirs(D135)
    F135 = os.path.join(D135, 'lk.txt')
    open(F135, 'w').write('x\n')
    with mc.bloqueado(F135):
        res, sc, t = llama('delphi_move', {'path': F135, 'dest': os.path.join(D135, 'n1', 'n2', 'n3', 'lk.txt')})
    check('E135 un move que falla: sin n1\\n2\\n3 (quedaban vacias)',
          res.get('isError') is True and not os.path.exists(os.path.join(D135, 'n1')), os.listdir(D135))

    # E136 un copy=true que falla a mitad no deja la copia a medias
    D136 = os.path.join(JAIL, 'e136')
    os.makedirs(os.path.join(D136, 'src', 'z'))
    open(os.path.join(D136, 'src', 'a.txt'), 'w').write('a\n')
    B136 = os.path.join(D136, 'src', 'z', 'bloqueado.txt')
    open(B136, 'w').write('b\n')
    with mc.bloqueado(B136):
        res, sc, t = llama('delphi_move', {'path': os.path.join(D136, 'src'),
                                           'dest': os.path.join(D136, 'dst'), 'copy': True})
    check('E136 copy=true que falla a mitad: sin la copia a medias (el "repite" daba FILE-025)',
          res.get('isError') is True and not os.path.exists(os.path.join(D136, 'dst')), t[:200])

    # E137 restaurar una unit de la papelera con su form bloqueado: MOVE-017 y
    # la copia conserva su marca de dueno (otro agente podia purgarla)
    D137 = os.path.join(JAIL, 'e137')
    os.makedirs(D137)
    open(os.path.join(D137, 'UFicha.pas'), 'w').write('unit UFicha;\ninterface\nimplementation\n{$R *.dfm}\nend.\n')
    open(os.path.join(D137, 'UFicha.dfm'), 'w').write('object Ficha: TFicha\nend\n')
    llama('delphi_delete', {'path': os.path.join(D137, 'UFicha.pas')})
    CP137 = mc.copias(D137, 'UFicha.pas', 'CAJON_BORRADOS')
    CF137 = mc.copias(D137, 'UFicha.dfm', 'CAJON_BORRADOS')
    if CP137 and CF137 and os.path.exists(mc.marca_dueno(CP137[0])):
        with mc.bloqueado(CF137[0], lectura=True):
            res, sc, t = llama('delphi_move', {'path': CP137[0], 'dest': os.path.join(D137, 'UFicha.pas')})
        check('E137 restaurar con el form bloqueado: MOVE-017 y la copia CON su marca de dueno',
              res.get('isError') is True and mc.abre(t, 'SR_MOVE_FORM_NO_VA_FMT') and
              os.path.exists(CP137[0]) and os.path.exists(mc.marca_dueno(CP137[0])), t[:250])
    else:
        check('E137 fixture: el borrado deja las dos copias con su marca', False, (CP137, CF137))

    # E138 la copia de seguridad de un move de carpeta no sigue sus enlaces (una
    # junction a la raiz dentro: MOVE-012 "nombre demasiado largo")
    D138 = os.path.join(JAIL, 'e138')
    os.makedirs(os.path.join(D138, 'carpeta'))
    open(os.path.join(D138, 'carpeta', 'propio.txt'), 'w').write('p\n')
    L138 = os.path.join(D138, 'carpeta', 'alaraiz')
    subprocess.run(['cmd', '/c', 'mklink', '/J', L138, JAIL], capture_output=True)
    if os.path.isdir(L138):
        res, sc, t = llama('delphi_move', {'path': os.path.join(D138, 'carpeta'),
                                           'dest': os.path.join(D138, 'carpeta2')})
        copia138 = mc.copias(D138, 'carpeta', 'CAJON_BORRADOS')
        check('E138 mover una carpeta con una junction a la raiz dentro: se mueve, y su copia no sigue el enlace',
              not res.get('isError') and os.path.lexists(os.path.join(D138, 'carpeta2', 'alaraiz')) and
              len(copia138) == 1 and os.path.exists(os.path.join(copia138[0], 'propio.txt')) and
              not os.path.exists(os.path.join(copia138[0], 'alaraiz')), t[:250])
        for lk in (os.path.join(D138, 'carpeta2', 'alaraiz'), L138):
            if os.path.lexists(lk):
                os.rmdir(lk)  # el enlace, no lo de detras
    else:
        check('E138 fixture: mklink /J crea la junction', False, L138)

    # E139 occurrence cuenta con la regla del motor de Pascal: "  foo;  " no es
    # una ocurrencia de "foo;" para el motor (daba EDIT-062)
    D139 = os.path.join(JAIL, 'e139')
    os.makedirs(D139)
    P139 = os.path.join(D139, 'Occ.pas')
    open(P139, 'wb').write(b'unit Occ;\r\ninterface\r\nimplementation\r\nprocedure X;\r\nbegin\r\n'
                           b'  foo;  \r\n  foo;\r\nend;\r\nend.\r\n')
    res, sc, t = llama('delphi_edit', {'path': P139, 'edits': json.dumps(
        [{'old': 'foo;', 'new': 'bar;', 'occurrence': 1}])})
    b139 = open(P139, 'rb').read()
    check('E139 occurrence:1 con la regla del motor: edita "  foo;" (era EDIT-062)',
          not res.get('isError') and b'  foo;  \r\n  bar;\r\n' in b139, '%s | %r' % (t[:200], b139))

    # E140 el create de un changeset normaliza el CR suelto como sus gemelos
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    c140 = mc.id_changeset(t)
    P140 = os.path.join(D139, 'cr140.txt')
    llama('delphi_changeset', {'command': 'stage', 'id': c140, 'kind': 'create', 'path': P140,
                               'content': 'uno\rdos\r'})
    llama('delphi_changeset', {'command': 'preview', 'id': c140})
    res, sc, t = llama('delphi_changeset', {'command': 'commit', 'id': c140})
    b140 = open(P140, 'rb').read() if os.path.exists(P140) else b''
    check('E140 changeset create de "uno\\rdos\\r": CRLF (salia "uno\\rdos\\r\\r\\n")',
          b140 == b'uno\r\ndos\r\n', '%s | %r' % (t[:160], b140))

    # E141 el preview avisa del +R tambien para un edit (salia limpio y el commit
    # hacia ROLLBACK)
    P141 = os.path.join(D139, 'ro141.txt')
    open(P141, 'w').write('a\nb\n')
    with mc.solo_lectura(P141):
        res, sc, t = llama('delphi_changeset', {'command': 'begin'})
        c141 = mc.id_changeset(t)
        llama('delphi_changeset', {'command': 'stage', 'id': c141, 'kind': 'edit', 'path': P141,
                                   'old': 'a', 'new': 'z'})
        res, sc, t = llama('delphi_changeset', {'command': 'preview', 'id': c141})
        check('E141 preview de un edit sobre un fichero +R: no sale limpio (SYS-029)',
              mc.como_json(t).get('unresolved') == 1 and 'SYS-029' in t, t[:300])
        llama('delphi_changeset', {'command': 'rollback', 'id': c141})

    # E142 GROUP-005 dice lo que FALTA: un grupo sin </Project> (decia que le
    # faltaban un <Projects> y un </PropertyGroup> que si tenia)
    if os.path.exists(DPROJ_PAN):
        G142 = os.path.join(D139, 'Roto.groupproj')
        open(G142, 'w').write(
            '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n'
            '  <PropertyGroup>\n    <ProjectGuid>{11111111-2222-3333-4444-555555555555}</ProjectGuid>\n'
            '  </PropertyGroup>\n  <ItemGroup>\n    <Projects Include="Otro.dproj">\n'
            '      <Dependencies/>\n    </Projects>\n  </ItemGroup>\n')
        t = rechazo('E142 un grupo sin </Project>: GROUP-005', 'delphi_config',
                    {'command': 'add-project', 'project': G142, 'path': DPROJ_PAN}, 'DENIED',
                    'SR_GRUPO_FORMA_FMT')
        check('E142 ...y nombra lo que falta', '</Project>' in t and '</PropertyGroup>' not in t, t[:250])

    # E92b la regla del COMMIT: un +R que aparece DESPUES de un preview limpio lo
    # para el commit (SYS-029), sin copia (E92 ya lo para el preview)
    R92 = os.path.join(D139, 'ro92b.txt')
    open(R92, 'w').write('x\n')
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    c92b = mc.id_changeset(t)
    llama('delphi_changeset', {'command': 'stage', 'id': c92b, 'kind': 'delete', 'path': R92})
    res, sc, t = llama('delphi_changeset', {'command': 'preview', 'id': c92b})
    limpio = mc.como_json(t).get('unresolved') == 0
    with mc.solo_lectura(R92):
        res, sc, t = llama('delphi_changeset', {'command': 'commit', 'id': c92b})
        check('E92b +R tras un preview limpio: el commit lo para con SYS-029, sin copia',
              limpio and res.get('isError') is True and 'SYS-029' in t and os.path.exists(R92) and
              not mc.copias(D139, 'ro92b.txt'), t[:300])

    # ------------------------------------------------------------ decima revision
    # E143 el commit de un changeset mueve el atline de lo que viene despues solo
    # por lo que cambio POR ENCIMA (movia por el cambio del fichero entero:
    # COMMIT COMPLETE en la linea equivocada; ya en la 1.6.2)
    D143 = os.path.join(JAIL, 'e143')
    os.makedirs(D143)
    T143 = os.path.join(D143, 'blancos.txt')
    open(T143, 'w', newline='\n').write('uno\ndos\ntres\ncuatro\n\nseis\nsiete\nocho\nnueve\n\nonce\ndoce\n')
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    c143 = mc.id_changeset(t)
    llama('delphi_changeset', {'command': 'stage', 'id': c143, 'kind': 'delete-line', 'path': T143, 'atline': 10})
    llama('delphi_changeset', {'command': 'stage', 'id': c143, 'kind': 'delete-line', 'path': T143, 'atline': 5})
    llama('delphi_changeset', {'command': 'preview', 'id': c143})
    res, sc, t = llama('delphi_changeset', {'command': 'commit', 'id': c143})
    b143 = open(T143, newline='').read()
    check('E143 borrar las lineas 10 y luego 5: quedan "cuatro" y "nueve" (borraba la 4)',
          not res.get('isError') and b143 == 'uno\ndos\ntres\ncuatro\nseis\nsiete\nocho\nnueve\nonce\ndoce\n',
          '%s | %r' % (t[:160], b143))
    X143 = os.path.join(D143, 'dup.txt')
    open(X143, 'w', newline='\n').write('a\nx = 1\nb\nx = 1\nc\nfin\n')
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    c143b = mc.id_changeset(t)
    llama('delphi_changeset', {'command': 'stage', 'id': c143b, 'kind': 'edit', 'path': X143,
                               'old': 'fin', 'new': 'fin\nmas1\nmas2'})
    llama('delphi_changeset', {'command': 'stage', 'id': c143b, 'kind': 'edit', 'path': X143,
                               'old': 'x = 1', 'new': 'x = 2', 'atline': 2})
    llama('delphi_changeset', {'command': 'preview', 'id': c143b})
    res, sc, t = llama('delphi_changeset', {'command': 'commit', 'id': c143b})
    b143b = open(X143, newline='').read()
    check('E143 ...un edit que anade lineas DEBAJO no mueve el atline 2 (editaba la 4)',
          not res.get('isError') and b143b == 'a\nx = 2\nb\nx = 1\nc\nfin\nmas1\nmas2\n',
          '%s | %r' % (t[:160], b143b))

    # E144 renombrar una unit en un .dproj LF lo deja en LF (el tercer escritor)
    if os.path.exists(DPROJ129) and os.path.exists(os.path.join(D129, 'UOtra.pas')):
        res, sc, t = llama('delphi_move', {'path': os.path.join(D129, 'UOtra.pas'),
                                           'dest': os.path.join(D129, 'UOtraBis.pas')})
        b144 = open(DPROJ129, 'rb').read()
        check('E144 renombrar una unit en un .dproj LF: sigue en LF',
              not res.get('isError') and b'UOtraBis' in b144 and b'\r\n' not in b144, t[:200])

    # E145 el preview avisa del +R tambien para un delete-line
    P145 = os.path.join(D143, 'ro145.txt')
    open(P145, 'w').write('a\nb\n')
    with mc.solo_lectura(P145):
        res, sc, t = llama('delphi_changeset', {'command': 'begin'})
        c145 = mc.id_changeset(t)
        llama('delphi_changeset', {'command': 'stage', 'id': c145, 'kind': 'delete-line', 'path': P145,
                                   'atline': 1})
        res, sc, t = llama('delphi_changeset', {'command': 'preview', 'id': c145})
        check('E145 preview de un delete-line sobre un +R: no sale limpio (SYS-029)',
              mc.como_json(t).get('unresolved') == 1 and 'SYS-029' in t, t[:300])
        llama('delphi_changeset', {'command': 'rollback', 'id': c145})

    # E146 mover (renombrar) una unit con su .dpr bloqueado: SYS-027 y nada movido
    U146 = os.path.join(D131, 'UUnaSuelta.pas')
    if os.path.exists(U146):
        with mc.bloqueado(DPR131):
            res, sc, t = llama('delphi_move', {'path': U146, 'dest': os.path.join(D131, 'UUnaSuelta2.pas')})
        # decima: la negativa dice que se LEIA el .dpr para saber si lista la unit
        # (CFG-111) y lleva la causa (SYS-027); salia el SYS-027 pelado
        check('E146 renombrar una unit con su .dpr bloqueado: CFG-111 con SYS-027 dentro, y sigue donde estaba',
              res.get('isError') is True and mc.abre(t, 'SR_PROYECTO_NO_LEIDO_AL_BUSCAR_FMT') and
              mc.es(t, 'SR_FICHERO_OCUPADO_FMT') and os.path.exists(U146) and
              not os.path.exists(os.path.join(D131, 'UUnaSuelta2.pas')), t[:250])

    # E147 un move que falla no quita una junction ROTA del usuario (el deshacer
    # la tomaba por carpeta creada: TDirectory.Exists dice False de ella)
    D147 = os.path.join(JAIL, 'e147')
    os.makedirs(D147)
    F147 = os.path.join(D147, 'f.txt')
    open(F147, 'w').write('f\n')
    ROTA = os.path.join(D147, 'rota')
    subprocess.run(['cmd', '/c', 'mklink', '/J', ROTA, os.path.join(BASE, 'no_existe_147')], capture_output=True)
    if os.path.lexists(ROTA):
        res, sc, t = llama('delphi_move', {'path': F147, 'dest': os.path.join(ROTA, 'g.txt')})
        check('E147 un move a traves de una junction rota falla y la junction SIGUE (la quitaba)',
              res.get('isError') is True and os.path.lexists(ROTA) and os.path.exists(F147), t[:200])
        if os.path.lexists(ROTA):  # el enlace (el fallo que vigila lo quitaba)
            os.rmdir(ROTA)
    else:
        check('E147 fixture: mklink /J crea la junction rota', False, ROTA)

    # E148 EDIT-078 no aconseja un literal Pascal en un fichero de TEXTO
    T148 = os.path.join(D147, 'ansi.txt')
    open(T148, 'wb').write('canción\r\n'.encode('cp1252'))
    t = rechazo('E148 textedit con un caracter que no cabe en CP1252: EDIT-078', 'delphi_textedit',
                {'path': T148, 'old': 'canción', 'new': '日本'}, 'DENIED',
                'SR_EDIT_CARACTERES_NO_CABEN_FMT')
    check('E148 ...sin el consejo del literal Pascal (era para los fuentes)', '#$' not in t and 'ChrW' not in t,
          t[:300])

    # E149 el deshacer de un changeset devuelve el +R: move de un fichero que se
    # pone +R DESPUES del preview (antes lo veia; E169) y edit del destino: el
    # commit se niega. El deshacer no podia borrar el destino +R ni le devolvia
    # el atributo al original: SYS-018 con los dos ficheros, el original sin +R
    D149 = os.path.join(JAIL, 'e149')
    os.makedirs(D149)
    R149 = os.path.join(D149, 'ro.txt')
    R149b = os.path.join(D149, 'ro2.txt')
    open(R149, 'w', newline='\n').write('uno\ndos\n')
    try:
        res, sc, t = llama('delphi_changeset', {'command': 'begin'})
        c149 = mc.id_changeset(t)
        llama('delphi_changeset', {'command': 'stage', 'id': c149, 'kind': 'move', 'path': R149,
                                   'dest': R149b})
        llama('delphi_changeset', {'command': 'stage', 'id': c149, 'kind': 'edit', 'path': R149b,
                                   'old': 'uno', 'new': 'UNO'})
        llama('delphi_changeset', {'command': 'preview', 'id': c149})
        os.chmod(R149, stat.S_IREAD)  # tras el preview limpio: el commit se lo encuentra
        res, sc, t = llama('delphi_changeset', {'command': 'commit', 'id': c149})
        check('E149 changeset move de un +R + edit del destino: deshecho ENTERO (salia SYS-018)',
              res.get('isError') is True and mc.abre(t, 'SR_CHANGESET_ROLLED_BACK_FMT') and
              os.path.exists(R149) and not os.path.exists(R149b) and
              open(R149, newline='').read() == 'uno\ndos\n', '%s | %s' % (t[:300], os.listdir(D149)))
        check('E149 ...y el original vuelve con su +R (volvia sin el)',
              os.path.exists(R149) and not os.access(R149, os.W_OK), os.listdir(D149))
    finally:
        for f in (R149, R149b):
            if os.path.exists(f):
                os.chmod(f, stat.S_IREAD | stat.S_IWRITE)

    # E150 copy=true de una unit +R cuyo .dfm no se deja leer: MOVE-017 y la copia
    # fuera (la copia de un +R es +R: TFile.Delete fallaba, SYS-018 y se quedaba)
    D150 = os.path.join(JAIL, 'e150')
    os.makedirs(D150)
    P150 = os.path.join(D150, 'URc.pas')
    F150 = os.path.join(D150, 'URc.dfm')
    open(P150, 'w').write('unit URc;\ninterface\nimplementation\n{$R *.dfm}\nend.\n')
    open(F150, 'w').write('object Rc: TRc\nend\n')
    os.chmod(P150, stat.S_IREAD)
    with mc.bloqueado(F150): # ni leer
        res, sc, t = llama('delphi_move', {'path': P150, 'dest': os.path.join(D150, 'sub', 'URc.pas'),
                                           'copy': True})
    try:
        check('E150 copy=true de una unit +R con el .dfm bloqueado: MOVE-017 y ni copia ni carpeta sub',
              res.get('isError') is True and mc.abre(t, 'SR_MOVE_FORM_NO_VA_FMT') and
              not os.path.exists(os.path.join(D150, 'sub')), '%s | %s' % (t[:300], os.listdir(D150)))
    finally:
        os.chmod(P150, stat.S_IREAD | stat.S_IWRITE)
        if os.path.exists(os.path.join(D150, 'sub', 'URc.pas')):
            os.chmod(os.path.join(D150, 'sub', 'URc.pas'), stat.S_IREAD | stat.S_IWRITE)

    # E151 mover dos veces una unit +R cuyo .dfm no se deja mover: ninguna copia
    # en la papelera (la copia de seguridad era +R y cada reintento dejaba una)
    D151 = os.path.join(JAIL, 'e151')
    os.makedirs(D151)
    P151 = os.path.join(D151, 'URm.pas')
    F151 = os.path.join(D151, 'URm.dfm')
    open(P151, 'w').write('unit URm;\ninterface\nimplementation\n{$R *.dfm}\nend.\n')
    open(F151, 'w').write('object Rm: TRm\nend\n')
    os.chmod(P151, stat.S_IREAD)
    with mc.bloqueado(F151, lectura=True): # leer si; mover no
        for _ in range(2):
            res, sc, t = llama('delphi_move', {'path': P151, 'dest': os.path.join(D151, 'sub', 'URm.pas')})
    try:
        check('E151 mover dos veces una unit +R con el .dfm bloqueado: MOVE-017 y sin copias en la papelera',
              res.get('isError') is True and mc.abre(t, 'SR_MOVE_FORM_NO_VA_FMT') and os.path.exists(P151) and
              not mc.copias(D151), '%s | %s' % (t[:250], mc.copias(D151)))
        check('E151 ...y la unit sigue en su sitio con su +R', os.path.exists(P151) and
              not os.access(P151, os.W_OK), os.listdir(D151))
    finally:
        os.chmod(P151, stat.S_IREAD | stat.S_IWRITE)
        for f in mc.copias(D151):
            os.chmod(f, stat.S_IREAD | stat.S_IWRITE)

    # E152 quitar la ULTIMA unit de un paquete o de un programa quita la clausula
    # entera (dejaba la palabra sola: no compila, con OK); y add-unit la vuelve a
    # estrenar en el programa (decia CFG-040)
    D152 = os.path.join(JAIL, 'e152')
    os.makedirs(D152)
    U152 = os.path.join(D152, 'USola.pas')
    open(U152, 'w', newline='\r\n').write('unit USola;\n\ninterface\n\nimplementation\n\nend.\n')
    DPK152 = os.path.join(D152, 'PkSola.dpk')
    open(DPK152, 'w', newline='\r\n').write("package PkSola;\n\nrequires\n  rtl;\n\ncontains\n"
                                            "  USola in 'USola.pas';\n\nend.\n")
    res, sc, t = llama('delphi_config', {'project': DPK152, 'command': 'remove-unit', 'path': U152})
    b152 = open(DPK152, newline='').read()
    check('E152 quitar la ultima unit de un .dpk: sin clausula contains (quedaba "contains" solo)',
          not res.get('isError') and b152 == 'package PkSola;\r\n\r\nrequires\r\n  rtl;\r\n\r\nend.\r\n',
          '%s | %r' % (t[:200], b152))
    DPR152 = os.path.join(D152, 'PrSola.dpr')
    open(DPR152, 'w', newline='\r\n').write("program PrSola;\n\nuses\n  USola in 'USola.pas';\n\nbegin\nend.\n")
    res, sc, t = llama('delphi_config', {'project': DPR152, 'command': 'remove-unit', 'path': U152})
    b152 = open(DPR152, newline='').read()
    check('E152 ...y de un .dpr: sin uses (quedaba "uses" solo)',
          not res.get('isError') and b152 == 'program PrSola;\r\n\r\nbegin\r\nend.\r\n',
          '%s | %r' % (t[:200], b152))
    res, sc, t = llama('delphi_config', {'project': DPR152, 'command': 'add-unit', 'path': U152})
    b152 = open(DPR152, newline='').read()
    check('E152 ...y add-unit la vuelve a estrenar tras la cabecera (decia CFG-040)',
          not res.get('isError') and
          b152 == "program PrSola;\r\n\r\nuses\r\n  USola in 'USola.pas';\r\n\r\nbegin\r\nend.\r\n",
          '%s | %r' % (t[:200], b152))

    # E153 renombrar una unit con directivas en la cabecera ("unit X platform;")
    # la reescribe, y add-unit la lee; si la cabecera no dice el nombre, MOVE-018
    # y no "rewritten" (MOVE-015 lo decia sin cambiar nada: el build daba E1038)
    D153 = os.path.join(JAIL, 'e153')
    os.makedirs(D153)
    P153 = os.path.join(D153, 'UPlat.pas')
    Q153 = os.path.join(D153, 'UPlat2.pas')
    open(P153, 'w', newline='\r\n').write('unit UPlat platform;\n\ninterface\n\nimplementation\n\nend.\n')
    res, sc, t = llama('delphi_move', {'path': P153, 'dest': Q153})
    b153 = open(Q153, newline='').read() if os.path.exists(Q153) else ''
    check('E153 renombrar "unit UPlat platform;": la cabecera sigue al fichero (MOVE-015 sin hacerlo)',
          not res.get('isError') and b153.startswith('unit UPlat2 platform;\r\n') and
          mc.es(t, 'SN_MOVE_CABECERA_REESCRITA_FMT'), '%s | %r' % (t[:300], b153[:60]))
    P153b = os.path.join(D153, 'UMal.pas')
    Q153b = os.path.join(D153, 'UMal2.pas')
    open(P153b, 'w', newline='\r\n').write('unit OtroNombre;\n\ninterface\n\nimplementation\n\nend.\n')
    res, sc, t = llama('delphi_move', {'path': P153b, 'dest': Q153b})
    b153 = open(Q153b, newline='').read() if os.path.exists(Q153b) else ''
    check('E153 ...una cabecera que no dice el nombre: MOVE-018, sin "rewritten" y sin tocarla',
          mc.es(t, 'SN_MOVE_CABECERA_NO_ENCONTRADA_FMT') and not mc.es(t, 'SN_MOVE_CABECERA_REESCRITA_FMT') and
          b153.startswith('unit OtroNombre;\r\n'), '%s | %r' % (t[:300], b153[:60]))
    DPR153 = os.path.join(D153, 'Pl.dpr')
    open(DPR153, 'w', newline='\r\n').write('program Pl;\n\nuses\n  System.SysUtils;\n\nbegin\nend.\n')
    res, sc, t = llama('delphi_config', {'project': DPR153, 'command': 'add-unit', 'path': Q153})
    check('E153 ...y add-unit lee "unit UPlat2 platform;" (decia que no tenia cabecera)',
          not res.get('isError') and "UPlat2 in 'UPlat2.pas'" in open(DPR153).read(), t[:200])

    # E154 el SYS-018 de un move cuyo form no va Y cuyo deshacer no pudo con todo
    # no dice debajo "the unit is back... Nothing was done": lleva la causa sola.
    # Que falle la VUELTA no se puede provocar de forma determinista desde aqui
    # (haria falta bloquear lo recien movido entre dos llamadas del servidor):
    # se mira el catalogo y quien lo compone
    TXT154 = open(os.path.join(mc.REPO, 'src', 'Server', 'Lsp.Texts.pas'), encoding='utf-8').read()
    FO154 = open(os.path.join(mc.REPO, 'src', 'Server', 'Mcp.Tools.FileOps.pas'), encoding='utf-8').read()
    m154 = re.search(r"SF_MOVE_FORM_NO_VA_FMT\s*=\s*'([^']*)'", TXT154)
    check('E154 la causa de MOVE-017 dentro de SYS-018 no dice que la unit volvio',
          bool(m154) and 'back' not in m154.group(1) and 'Nothing' not in m154.group(1) and
          re.search(r'SR_FOTO_NO_VOLVIO_FMT, \[NoVolvio, ACausa\]', FO154) is not None and
          re.search(r'DeshaceMove\(MsgFmt\(SR_MOVE_FORM_NO_VA_FMT, [^;]*MsgFmt\(SF_MOVE_FORM_NO_VA_FMT',
                    FO154, re.S) is not None,
          m154.group(1) if m154 else 'sin SF_MOVE_FORM_NO_VA_FMT')
    # ...y la de MOVE-019, por el MISMO deshacer (DeshaceMove)
    m170 = re.search(r"SF_MOVE_PROYECTO_NO_VA_FMT\s*=\s*'([^']*)'", TXT154)
    check('E170 la causa de MOVE-019 dentro de SYS-018 tampoco dice que la unit volvio (el mismo deshacer)',
          bool(m170) and 'back' not in m170.group(1) and 'Nothing' not in m170.group(1) and
          re.search(r'DeshaceMove\(MsgFmt\(SR_MOVE_PROYECTO_NO_VA_FMT, [^;]*MsgFmt\(SF_MOVE_PROYECTO_NO_VA_FMT',
                    FO154, re.S) is not None,
          m170.group(1) if m170 else 'sin SF_MOVE_PROYECTO_NO_VA_FMT')

    # ------------------------------------------------------------ 1.7.1
    # E155 un bloque que llega a la ULTIMA linea de un fichero SIN salto final no
    # se lo anade (una linea sola lo conservaba; el bloque montaba el sufijo a mano)
    D155 = os.path.join(JAIL, 'e155')
    os.makedirs(D155)
    B155 = os.path.join(D155, 'bloque.txt')
    open(B155, 'wb').write(b'uno\r\ndos\r\ntres')
    res, sc, t = llama('delphi_textedit', {'path': B155, 'edits': json.dumps([{'old': 'dos\ntres', 'new': 'DOS\nTRES'}])})
    b155 = open(B155, 'rb').read()
    check('E155 un bloque hasta la ultima linea de un fichero SIN salto final: sigue sin el',
          not res.get('isError') and b155 == b'uno\r\nDOS\r\nTRES', '%s | %r' % (t[:120], b155))
    open(B155, 'wb').write(b'uno\r\ndos\r\ntres\r\n')
    res, sc, t = llama('delphi_textedit', {'path': B155, 'edits': json.dumps([{'old': 'dos\ntres', 'new': 'DOS\nTRES'}])})
    b155 = open(B155, 'rb').read()
    check('E155 ...y CON salto final lo conserva', not res.get('isError') and b155 == b'uno\r\nDOS\r\nTRES\r\n', b155)

    # E156 un old de VARIAS lineas en un changeset se niega al apilar (se apilaba y el
    # preview decia NOT FOUND aconsejando atline)
    T156 = os.path.join(D155, 'ml.txt')
    open(T156, 'w', newline='\n').write('a\nb\nc\n')
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    c156 = mc.id_changeset(t)
    rechazo('E156 stage de un edit con un old de dos lineas: CHSET-013 al apilar', 'delphi_changeset',
            {'command': 'stage', 'id': c156, 'kind': 'edit', 'path': T156, 'old': 'a\nb', 'new': 'A\nB'},
            'INVALID_PARAM', 'SR_CHANGESET_EDIT_NEEDS')
    rechazo('E156 ...y un delete-line con un old de dos lineas: CHSET-014', 'delphi_changeset',
            {'command': 'stage', 'id': c156, 'kind': 'delete-line', 'path': T156, 'atline': 1, 'old': 'a\nb'},
            'INVALID_PARAM', 'SR_CHANGESET_DELLINE_NEEDS')
    llama('delphi_changeset', {'command': 'rollback', 'id': c156})

    # E157 un edit rechazado por +R no deja la copia DIARIA en la papelera ("Nothing
    # was written" la dejaba: la copia iba antes de la pregunta del escritor)
    def copias_diarias(carpeta, nombre):
        return [os.path.join(d, f) for d, _, fs in os.walk(os.path.join(carpeta, '__delphi-patch'))
                for f in fs if f == nombre]
    R157 = os.path.join(D155, 'ro.txt')
    open(R157, 'w').write('a\nb\n')
    with mc.solo_lectura(R157):
        rechazo('E157 textedit sobre un +R: SYS-029', 'delphi_textedit', {'path': R157, 'old': 'a', 'new': 'A'},
                'DENIED', 'SR_SOLO_LECTURA_ATRIBUTO_FMT')
        check('E157 ...y SIN copia diaria en la papelera (la dejaba)', not copias_diarias(D155, 'ro.txt'),
              copias_diarias(D155, 'ro.txt'))
    P157 = os.path.join(D155, 'URo.pas')
    open(P157, 'wb').write(b'unit URo;\r\ninterface\r\n// x\r\nimplementation\r\nend.\r\n')
    with mc.solo_lectura(P157):
        rechazo('E157 delphi_edit sobre un +R: SYS-029', 'delphi_edit', {'path': P157, 'old': '// x', 'new': '// y'},
                'DENIED', 'SR_SOLO_LECTURA_ATRIBUTO_FMT')
        res, sc, t = llama('delphi_edit', {'path': P157, 'edits': json.dumps([{'old': '// x', 'new': '// y'}])})
        check('E157 ...edits= igual: rechazado y sin copia diaria', res.get('isError') is True and 'SYS-029' in t and
              not copias_diarias(D155, 'URo.pas'), '%s | %s' % (t[:120], copias_diarias(D155, 'URo.pas')))

    # E158 con .dfm Y .fmx la nota del move nombra a los DOS (nombraba solo el ultimo)
    D158 = os.path.join(JAIL, 'e158')
    os.makedirs(D158)
    open(os.path.join(D158, 'UDos.pas'), 'w').write('unit UDos;\ninterface\nimplementation\n{$R *.dfm}\nend.\n')
    open(os.path.join(D158, 'UDos.dfm'), 'w').write('object Dos: TDos\nend\n')
    open(os.path.join(D158, 'UDos.fmx'), 'w').write('object Dos: TDos\nend\n')
    res, sc, t = llama('delphi_move', {'path': os.path.join(D158, 'UDos.pas'), 'dest': os.path.join(D158, 'sub', 'UDos.pas')})
    check('E158 move de una unit con .dfm y .fmx: la nota nombra los dos designers',
          not res.get('isError') and 'UDos.dfm' in t and 'UDos.fmx' in t and
          os.path.exists(os.path.join(D158, 'sub', 'UDos.dfm')) and os.path.exists(os.path.join(D158, 'sub', 'UDos.fmx')),
          t[:400])

    # E159 textedit con old y SIN new deja la linea en blanco y lo DICE (TEXT-016,
    # como delphi_edit EDIT-089; contestaba "OK line")
    S159 = os.path.join(D155, 'sinnew.txt')
    open(S159, 'w', newline='\n').write('a\nb\n')
    res, sc, t = llama('delphi_textedit', {'path': S159, 'old': 'a'})
    check('E159 textedit con old y sin new: BLANKED (TEXT-016), la linea queda vacia',
          not res.get('isError') and mc.abre(t, 'SK_TEXT_BLANQUEADA_LINEA_FMT') and open(S159, 'rb').read() == b'\nb\n',
          t[:200])

    # E160 copy=true de una unit +R: la copia es del agente, sin el +R (a otro nombre
    # daba SYS-029 sobre el ORIGEN, que no se toca; al mismo nombre salia +R)
    D160 = os.path.join(JAIL, 'e160')
    os.makedirs(D160)
    P160 = os.path.join(D160, 'URc.pas')
    open(P160, 'wb').write(b'unit URc;\r\ninterface\r\nimplementation\r\nend.\r\n')
    with mc.solo_lectura(P160):
        res, sc, t = llama('delphi_move', {'path': P160, 'dest': os.path.join(D160, 'URc2.pas'), 'copy': True})
        C160 = os.path.join(D160, 'URc2.pas')
        check('E160 copy=true de una unit +R a OTRO nombre: COPIED, cabecera reescrita y la copia escribible',
              not res.get('isError') and mc.es(t, 'SN_MOVE_CABECERA_REESCRITA_FMT') and os.path.exists(C160) and
              os.access(C160, os.W_OK) and open(C160, 'rb').read().startswith(b'unit URc2;'), t[:300])
        res, sc, t = llama('delphi_move', {'path': P160, 'dest': os.path.join(D160, 'sub', 'URc.pas'), 'copy': True})
        C160b = os.path.join(D160, 'sub', 'URc.pas')
        check('E160 ...y al MISMO nombre: la copia sale sin el +R', not res.get('isError') and os.path.exists(C160b) and
              os.access(C160b, os.W_OK), t[:200])

    # E161 el esquema Bearer no distingue mayusculas (RFC 9110); el token si
    INIT161 = {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {
        'protocolVersion': '2025-03-26', 'capabilities': {}, 'clientInfo': {'name': 'e161', 'version': '1'}}}
    code161, h161, b161 = mc.post(cli.url, INIT161, None, None, 'application/json',
                                  cabeceras={'Authorization': 'bearer ' + TOK})
    check('E161 Authorization: bearer <token> (minusculas) entra (daba 401)', code161 == 200 and 'serverInfo' in b161,
          '%s %s' % (code161, b161[:120]))
    code161, h161, b161 = mc.post(cli.url, INIT161, None, None, 'application/json',
                                  cabeceras={'Authorization': 'Bearer ' + TOK.upper()})
    check('E161 ...y el TOKEN si distingue mayusculas', code161 == 401, '%s %s' % (code161, b161[:120]))

    # E162 un nombre reservado de Windows (CON, NUL...) es INVALID_PARAM (GUARD-027):
    # en este Windows 11 CON.txt se creaba como fichero normal
    rechazo('E162 crear CON.txt: GUARD-027', 'delphi_textedit',
            {'path': os.path.join(D155, 'CON.txt'), 'create': True, 'content': 'x'}, 'INVALID_PARAM',
            'SR_GUARD_NOMBRE_RESERVADO_FMT')
    check('E162 ...y nada en disco', not os.path.lexists(os.path.join(D155, 'CON.txt')), os.listdir(D155))
    rechazo('E162 leer NUL: GUARD-027', 'delphi_read', {'path': os.path.join(D155, 'NUL')}, 'INVALID_PARAM',
            'SR_GUARD_NOMBRE_RESERVADO_FMT')
    rechazo('E162 una carpeta COM1 en el camino: GUARD-027', 'delphi_read',
            {'path': os.path.join(D155, 'COM1', 'a.txt')}, 'INVALID_PARAM', 'SR_GUARD_NOMBRE_RESERVADO_FMT')
    res, sc, t = llama('delphi_textedit', {'path': os.path.join(D155, 'console.txt'), 'create': True, 'content': 'x'})
    check('E162 ...y "console.txt" no es reservado', not res.get('isError'), t[:160])

    # E163 insert rutina-global de una rutina que YA existe: se AVISA (EDIT-116), no se
    # niega (dcc dira si es la misma; no somos la ninera) - se insertaba a ciegas
    U163 = os.path.join(D155, 'UDup.pas')
    open(U163, 'wb').write(b'unit UDup;\r\n\r\ninterface\r\n\r\nprocedure Foo;\r\n\r\nimplementation\r\n\r\n'
                           b'procedure Foo;\r\nbegin\r\nend;\r\n\r\nend.\r\n')
    res, sc, t = llama('delphi_edit', {'path': U163, 'insert': 'rutina-global', 'code': 'procedure Foo;\nbegin\nend;'})
    check('E163 insert rutina-global de una Foo que ya existe: escrita CON aviso EDIT-116 y su linea',
          not res.get('isError') and mc.es(t, 'SN_EDIT_RUTINA_YA_EXISTE_FMT') and 'line 5' in t and
          open(U163, 'rb').read().count(b'procedure Foo;') == 3, t[:400])

    # E164 delphi_edit sobre un .pas con bytes NUL: TEXT-008 (la puerta binaria solo la
    # usaban delphi_read y delphi_textedit; este motor lo editaba)
    U164 = os.path.join(D155, 'UBin.pas')
    A164 = b'unit UBin;\r\n\x00\x00interface\r\nimplementation\r\nend.\r\n'
    open(U164, 'wb').write(A164)
    rechazo('E164 delphi_edit de un .pas con bytes NUL: TEXT-008', 'delphi_edit',
            {'path': U164, 'old': 'interface', 'new': 'interface // x'}, 'DENIED', 'SR_TEXT_PARECE_BINARIO_FMT')
    check('E164 ...intacto', open(U164, 'rb').read() == A164)

    # E165 los enteros del esquema llevan minimum 0 (el binder rechaza negativos en todos)
    m165 = cli.request('tools/list')
    props165 = next((x.get('inputSchema', {}).get('properties', {})
                     for x in ((m165 or {}).get('result') or {}).get('tools', []) if x.get('name') == 'delphi_read'), {})
    check('E165 delphi_read fromline lleva minimum 0 en el esquema', props165.get('fromline', {}).get('minimum') == 0,
          props165.get('fromline'))

    # E167 copy=true de una carpeta con una junction a un ANTEPASADO del destino: el
    # enlace no se sigue (se copiaba a si misma hasta agotar la ruta y el move caia)
    D167 = os.path.join(JAIL, 'e167')
    S167 = os.path.join(D167, 'src')
    os.makedirs(S167)
    open(os.path.join(S167, 'f.txt'), 'w').write('f\n')
    UP167 = os.path.join(S167, 'up')
    subprocess.run(['cmd', '/c', 'mklink', '/J', UP167, D167], capture_output=True)
    if os.path.lexists(UP167):
        res, sc, t = llama('delphi_move', {'path': S167, 'dest': os.path.join(D167, 'copia'), 'copy': True})
        check('E167 copy=true con una junction al antepasado del destino: COPIED, el enlace no seguido',
              not res.get('isError') and mc.es(t, 'SN_COPY_LINKS_NOT_FOLLOWED_FMT') and
              os.path.exists(os.path.join(D167, 'copia', 'f.txt')) and
              not os.path.lexists(os.path.join(D167, 'copia', 'up')), '%s | %s' % (t[:300], os.listdir(D167)))
        os.rmdir(UP167)
    else:
        check('E167 fixture: mklink /J', False, UP167)

    # E168 lo que no es del comando se dice tambien en test, designer, adb y paserver
    rechazo('E168 delphi_test discover con filter: TEST-025', 'delphi_test',
            {'command': 'discover', 'path': D155, 'filter': 'x'}, 'INVALID_PARAM', 'SR_TEST_NO_VA_CON_COMANDO_FMT')
    rechazo('E168 delphi_designer tree con class: DSGN-047', 'delphi_designer',
            {'command': 'tree', 'path': os.path.join(D158, 'sub', 'UDos.dfm'), 'class': 'TX'}, 'INVALID_PARAM',
            'SR_DESIGNER_NO_VA_CON_COMANDO_FMT')
    rechazo('E168 delphi_adb devices con key: ADB-028', 'delphi_adb', {'command': 'devices', 'key': 'back'},
            'INVALID_PARAM', 'SR_ADB_NO_VA_CON_COMANDO_FMT')
    rechazo('E168 delphi_paserver platforms con sdk: PAS-051', 'delphi_paserver',
            {'command': 'platforms', 'sdk': 'x'}, 'INVALID_PARAM', 'SR_PASERVER_NO_VA_CON_COMANDO_FMT')
    res, sc, t = llama('delphi_designer', {'command': 'tree', 'path': os.path.join(D158, 'sub', 'UDos.dfm')})
    check('E168 ...y una llamada con lo suyo sigue funcionando (designer tree)', not res.get('isError'), t[:160])

    # E169 el preview ENSAYA con el motor lo que el commit va a comprobar (copiaba
    # tres reglas del commit y le faltaban las demas: decia Clean y el commit caia)
    D169 = os.path.join(JAIL, 'e169')
    os.makedirs(D169)
    A169 = os.path.join(D169, 'ansi.txt')
    open(A169, 'wb').write('canción\r\n'.encode('cp1252'))
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    c169 = mc.id_changeset(t)
    llama('delphi_changeset', {'command': 'stage', 'id': c169, 'kind': 'edit', 'path': A169,
                               'old': 'canción', 'new': '日本'})
    res, sc, t = llama('delphi_changeset', {'command': 'preview', 'id': c169})
    check('E169 preview de un new que NO CABE en cp1252: no sale limpio (EDIT-078)',
          mc.como_json(t).get('unresolved') == 1 and 'EDIT-078' in t, t[:300])
    llama('delphi_changeset', {'command': 'rollback', 'id': c169})
    R169 = os.path.join(D169, 'ro.txt')
    open(R169, 'w', newline='\n').write('uno\ndos\n')
    with mc.solo_lectura(R169):
        res, sc, t = llama('delphi_changeset', {'command': 'begin'})
        c169 = mc.id_changeset(t)
        llama('delphi_changeset', {'command': 'stage', 'id': c169, 'kind': 'move', 'path': R169,
                                   'dest': os.path.join(D169, 'ro2.txt')})
        llama('delphi_changeset', {'command': 'stage', 'id': c169, 'kind': 'edit',
                                   'path': os.path.join(D169, 'ro2.txt'), 'old': 'uno', 'new': 'UNO'})
        res, sc, t = llama('delphi_changeset', {'command': 'preview', 'id': c169})
        check('E169 ...move de un +R y edit del destino: el preview ve el +R por el ORIGEN del move (decia pending)',
              mc.como_json(t).get('unresolved') == 1 and 'SYS-029' in t, t[:300])
        llama('delphi_changeset', {'command': 'rollback', 'id': c169})
    M169 = os.path.join(D169, 'mv.txt')
    open(M169, 'w', newline='\n').write('uno\ndos\n')
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    c169 = mc.id_changeset(t)
    llama('delphi_changeset', {'command': 'stage', 'id': c169, 'kind': 'move', 'path': M169,
                               'dest': os.path.join(D169, 'mv2.txt')})
    llama('delphi_changeset', {'command': 'stage', 'id': c169, 'kind': 'edit',
                               'path': os.path.join(D169, 'mv2.txt'), 'old': 'uno', 'new': 'UNO'})
    res, sc, t = llama('delphi_changeset', {'command': 'preview', 'id': c169})
    j169 = mc.como_json(t)
    ops169 = j169.get('operations') or [{}, {}]
    check('E169 ...y sin +R el ancla se resuelve contra el origen del move: ok en la linea 1 (era "pending")',
          j169.get('unresolved') == 0 and ops169[1].get('anchor') == 'ok' and ops169[1].get('atline') == 1, t[:300])
    res, sc, t = llama('delphi_changeset', {'command': 'commit', 'id': c169})
    check('E169 ...y el commit lo hace', not res.get('isError') and
          open(os.path.join(D169, 'mv2.txt'), 'rb').read() == b'UNO\ndos\n', t[:200])

    # ------------------------------------------------------------ 1.7.2
    # E170 mover una unit cuyo proyecto no se deja re-apuntar: TODO O NADA
    # (MOVE-019), como su form (MOVE-017) y como borrarla (FILE-039). Salia
    # MOVED con el .dpr re-apuntado, el .dproj no y "nothing was written" en
    # una nota (medido en vivo, 28-sep-2026)
    D170 = os.path.join(JAIL, 'e170')
    llama('delphi_create', {'kind': 'project-console', 'name': 'Pm', 'dir': D170})
    DPR170 = os.path.join(D170, 'Pm.dpr')
    DPROJ170 = os.path.join(D170, 'Pm.dproj')
    res, sc, t = llama('delphi_create', {'kind': 'unit', 'name': 'UMov', 'project': DPROJ170})
    U170 = os.path.join(D170, 'UMov.pas')
    check('E170 fixture: un proyecto con una unit registrada',
          os.path.exists(U170) and os.path.exists(DPROJ170), t[:200])
    ANT170 = [open(f, 'rb').read() for f in (DPR170, DPROJ170, U170)]
    COPIAS170 = mc.copias(D170, 'UMov.pas', 'CAJON_BORRADOS')
    N170 = os.path.join(D170, 'sub', 'UNuevo.pas')
    with mc.solo_lectura(DPROJ170):
        res, sc, t = llama('delphi_move', {'path': U170, 'dest': N170})
    check('E170 move con el .dproj +R: MOVE-019 y NADA movido (la unit en su sitio, con su cabecera)',
          res.get('isError') is True and mc.abre(t, 'SR_MOVE_PROYECTO_NO_VA_FMT') and
          os.path.exists(U170) and not os.path.exists(N170) and
          open(U170, 'rb').read() == ANT170[2], '%s | %s' % (t[:300], os.listdir(D170)))
    check('E170 ...y el .dpr y el .dproj como estaban (el .dpr quedaba re-apuntado)',
          [open(f, 'rb').read() for f in (DPR170, DPROJ170)] == ANT170[:2], t[:200])
    check('E170 ...sin carpeta sub y sin copia nueva en la papelera',
          not os.path.exists(os.path.join(D170, 'sub')) and
          mc.copias(D170, 'UMov.pas', 'CAJON_BORRADOS') == COPIAS170, os.listdir(D170))
    # con el .dpr +R falla el primer escritor: lo mismo
    with mc.solo_lectura(DPR170):
        res, sc, t = llama('delphi_move', {'path': U170, 'dest': N170})
    check('E170 ...con el .dpr +R: MOVE-019, la unit en su sitio y el par intacto',
          res.get('isError') is True and mc.abre(t, 'SR_MOVE_PROYECTO_NO_VA_FMT') and
          os.path.exists(U170) and not os.path.exists(N170) and
          [open(f, 'rb').read() for f in (DPR170, DPROJ170, U170)] == ANT170, t[:300])

    # E171 DOS proyectos la listan y el segundo no se deja: el primero vuelve
    # (la foto del move cubre todos), y sin el +R el rename va con los dos
    llama('delphi_create', {'kind': 'project-console', 'name': 'Pn', 'dir': D170})
    DPR171 = os.path.join(D170, 'Pn.dpr')
    DPROJ171 = os.path.join(D170, 'Pn.dproj')
    res, sc, t = llama('delphi_config', {'command': 'add-unit', 'project': DPROJ171, 'path': U170})
    check('E171 fixture: la unit en dos proyectos', not res.get('isError') and
          b'UMov' in open(DPR171, 'rb').read(), t[:200])
    ANT171 = [open(f, 'rb').read() for f in (DPR170, DPROJ170, DPR171, DPROJ171, U170)]
    with mc.solo_lectura(DPROJ171):
        res, sc, t = llama('delphi_move', {'path': U170, 'dest': N170})
    check('E171 el segundo proyecto no se deja: MOVE-019 y los DOS proyectos como estaban',
          res.get('isError') is True and mc.abre(t, 'SR_MOVE_PROYECTO_NO_VA_FMT') and
          os.path.exists(U170) and not os.path.exists(N170) and
          [open(f, 'rb').read() for f in (DPR170, DPROJ170, DPR171, DPROJ171, U170)] == ANT171,
          t[:300])
    res, sc, t = llama('delphi_move', {'path': U170, 'dest': N170})
    check('E171 ...sin +R el rename va y los dos proyectos la listan por el nombre nuevo',
          not res.get('isError') and os.path.exists(N170) and not os.path.exists(U170) and
          all(b'UNuevo' in open(f, 'rb').read() for f in (DPR170, DPROJ170, DPR171, DPROJ171)) and
          open(N170, 'rb').read().startswith(b'\xef\xbb\xbfunit UNuevo;'), t[:300])

    # E173 (1.7.2) 1.0 es un entero (JSON Schema): se rechazaba con SYS-016;
    # 1.5 sigue sin serlo. Y changeset status no lleva id (su tabla decia que
    # si y SP_CHANGESET_ID que no)
    res, sc, t = llama('delphi_read', {'path': NOTES, 'fromline': 1.0, 'toline': 1.0})
    check('E173 fromline=1.0 se acepta como entero (era SYS-016)',
          not res.get('isError') and not mc.es(t, 'SR_SYS_PARAM_VALUE_FMT'), t[:200])
    res, sc, t = llama('delphi_read', {'path': NOTES, 'fromline': 1.5})
    check('E173 ...y 1.5 sigue siendo SYS-016', res.get('isError') is True and 'SYS-016' in t, t[:200])
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    c173 = mc.id_changeset(t)
    res, sc, t = llama('delphi_changeset', {'command': 'status', 'id': c173})
    check('E173 changeset status con id: no va con el comando (su tabla lo admitia)',
          res.get('isError') is True and mc.es(t, 'SR_CHANGESET_NO_VA_CON_COMANDO_FMT'), t[:200])
    llama('delphi_changeset', {'command': 'rollback', 'id': c173})

    # E174 una ruta mas larga que MAX_PATH menos el sufijo del escritor: GUARD-028
    # a la entrada, sin fichero ni carpetas (era SYS-009 INTERNAL "Cannot create
    # file" con las carpetas ya creadas); LEERLA sigue valiendo
    D174 = os.path.join(JAIL, 'e174')
    # 250 caracteres justos: mas de 232 (no se escribe) y menos de 260 (se lee)
    P174 = os.path.join(D174, 'x' * (250 - len(D174) - 7), 'f.txt')
    rechazo('E174 crear en una ruta de %d caracteres: GUARD-028 (era SYS-009 INTERNAL)' % len(P174),
            'delphi_textedit', {'path': P174, 'create': True, 'content': 'x'}, 'INVALID_PARAM',
            'SR_GUARD_RUTA_LARGA_FMT')
    check('E174 ...y no deja carpetas por el camino', not os.path.exists(D174), D174)
    os.makedirs(os.path.dirname(P174), exist_ok=True)
    open(P174, 'w').write('largo\n')
    res, sc, t = llama('delphi_read', {'path': P174})
    check('E174 ...leer una ruta larga sigue valiendo', not res.get('isError') and 'largo' in t, t[:200])
    res, sc, t = llama('delphi_textedit', {'path': P174, 'old': 'largo', 'new': 'corto'})
    check('E174 ...editarla: GUARD-028, sin tocarla', res.get('isError') is True and
          mc.abre(t, 'SR_GUARD_RUTA_LARGA_FMT') and open(P174).read() == 'largo\n', t[:200])

    # E175 la negativa de una tool exenta del enmascarado (textedit) que CITA
    # lineas del disco: las lineas citadas van tal cual (con su D:\), lo demas
    # de la negativa enmascarado. Una pista enmascarada no servia de ancla
    D175 = os.path.join(JAIL, 'e175')
    os.makedirs(D175)
    P175 = os.path.join(D175, 'rutas.txt')
    open(P175, 'w', newline='\n').write("uno\nx := 'D:\\Datos\\algo.txt';\ntres\n")
    res, sc, t = llama('delphi_textedit', {'path': P175, 'old': "'D:\\Datos", 'new': 'y'})
    check('E175 la pista EDIT-095 cita la linea con su D:\\ sin enmascarar',
          res.get('isError') is True and mc.es(t, 'SN_ANCLA_CONTIENEN') and
          "2|x := 'D:\\Datos\\algo.txt';" in t and 'srvd:\\Datos' not in t, t[:300])

    # E176 git: las tablas de "lo que no va" por SUBcomando (stash list con
    # message, worktree list con path): eran por comando
    rechazo('E176 git stash list con message: no va con el subcomando', 'delphi_git',
            {'command': 'stash', 'args': 'list', 'repo': NOREPO, 'message': 'x'},
            'INVALID_PARAM', 'SR_GIT_NO_VA_CON_COMANDO_FMT')
    rechazo('E176 git worktree list con path: no va con el subcomando', 'delphi_git',
            {'command': 'worktree', 'args': 'list', 'repo': NOREPO, 'path': NOTES},
            'INVALID_PARAM', 'SR_GIT_NO_VA_CON_COMANDO_FMT')

    # E174b la regla de la ruta larga NO abre la jaula: una ruta larga FUERA de
    # las raices sigue negada al leer, listar y descargar (la 1.7.2 la servia:
    # GUARD-028 salia de PathDenied antes de la jaula y la lectura lo perdonaba;
    # undecima revision, r11a/r11c)
    F174 = os.path.join(BASE, 'fuera174')
    P174b = os.path.join(F174, 'x' * (250 - len(F174) - 7), 'f.txt')
    os.makedirs(os.path.dirname(P174b), exist_ok=True)
    open(P174b, 'w').write('SECRETO fuera de la jaula\n')
    res, sc, t = llama('delphi_read', {'path': P174b})
    check('E174b leer una ruta LARGA fuera de la jaula: GUARD-002, no el contenido',
          res.get('isError') is True and mc.abre(t, 'SR_JAIL_FMT') and 'SECRETO' not in t, t[:200])
    res, sc, t = llama('delphi_list', {'root': os.path.dirname(P174b), 'pattern': '*.txt'})
    check('E174b ...ni se lista', res.get('isError') is True and mc.abre(t, 'SR_JAIL_FMT'), t[:200])
    code, h, b = files_get(P174b)
    check('E174b .../files tampoco la sirve (403 GUARD-002)', code == 403 and b'GUARD-002' in b and b'SECRETO' not in b,
          '%s %r' % (code, b[:160]))
    # E174c ...y las rutas que el servidor COMPONE (la copia de la papelera, la
    # carpeta del dia) no se miden con el tope del escritor: un delete a 200 y
    # un edit a 215 caracteres siguen yendo (la 1.7.2 los negaba desde 191)
    D174c = os.path.join(JAIL, 'e174c')
    P174c = os.path.join(D174c, 'y' * (200 - len(D174c) - 7), 'b.txt')
    os.makedirs(os.path.dirname(P174c), exist_ok=True)
    open(P174c, 'w').write('b\n')
    res, sc, t = llama('delphi_delete', {'path': P174c})
    check('E174c borrar un fichero de %d caracteres va (su copia en la papelera pasa de 232)' % len(P174c),
          not res.get('isError') and not os.path.exists(P174c), t[:200])
    P174d = os.path.join(D174c, 'z' * (215 - len(D174c) - 7), 'a.txt')
    os.makedirs(os.path.dirname(P174d), exist_ok=True)
    open(P174d, 'w', newline='\n').write('uno\n')
    res, sc, t = llama('delphi_textedit', {'path': P174d, 'old': 'uno', 'new': 'dos'})
    check('E174c editar un fichero de %d caracteres va (la carpeta del dia pasa de 232)' % len(P174d),
          not res.get('isError') and open(P174d).read() == 'dos\n', t[:200])

    # E177 MOVE-019 con DOS proyectos y una unit que se NOMBRA a si misma (un
    # comentario "UMv"): el rename del primero reescribe la unit por segunda
    # vez y, si el segundo falla, el deshacer la tomaba por cambiada "por otro"
    # y dejaba la unit vieja con la cabecera nueva (undecima revision, r11a H3)
    D177 = os.path.join(JAIL, 'e177')
    llama('delphi_create', {'kind': 'project-console', 'name': 'Pq', 'dir': D177})
    llama('delphi_create', {'kind': 'project-console', 'name': 'Pr', 'dir': D177})
    DPQ, DPR177 = os.path.join(D177, 'Pq.dproj'), os.path.join(D177, 'Pr.dproj')
    res, sc, t = llama('delphi_create', {'kind': 'unit', 'name': 'UMv', 'project': DPQ,
                                         'content': 'unit UMv;\n\n{ UMv: helpers; see UMv.Foo }\n\ninterface\n\nimplementation\n\nend.\n'})
    U177 = os.path.join(D177, 'UMv.pas')
    llama('delphi_config', {'command': 'add-unit', 'project': DPR177, 'path': U177})
    ANT177 = [open(f, 'rb').read() for f in (U177, os.path.join(D177, 'Pq.dpr'), DPQ, os.path.join(D177, 'Pr.dpr'), DPR177)]
    check('E177 fixture: la unit se nombra a si misma y la listan dos proyectos',
          b'see UMv.Foo' in ANT177[0] and b'UMv' in ANT177[3], ANT177[0][:80])
    N177 = os.path.join(D177, 'UMw.pas')
    with mc.solo_lectura(DPR177):
        res, sc, t = llama('delphi_move', {'path': U177, 'dest': N177})
    check('E177 el segundo proyecto no se deja: MOVE-019 y la unit vuelve BYTE A BYTE (cabecera y comentario)',
          res.get('isError') is True and mc.abre(t, 'SR_MOVE_PROYECTO_NO_VA_FMT') and 'SYS-018' not in t and
          os.path.exists(U177) and not os.path.exists(N177) and
          [open(f, 'rb').read() for f in (U177, os.path.join(D177, 'Pq.dpr'), DPQ, os.path.join(D177, 'Pr.dpr'), DPR177)] == ANT177,
          '%s | %r' % (t[:300], open(U177, 'rb').read()[:60] if os.path.exists(U177) else None))

    # E77 una tanda y un changeset que no cambian nada lo DICEN: contestaban
    # APPLIED / COMMIT COMPLETE prometiendo copias que no existian
    SIN = os.path.join(JAIL, 'e77')
    os.makedirs(SIN)
    T77 = os.path.join(SIN, 'igual.txt')
    open(T77, 'w', newline='\n').write('uno\ndos\n')
    res, sc, t = llama('delphi_textedit', {'path': T77, 'edits': json.dumps(
        [{'old': 'uno', 'new': 'uno'}, {'old': 'dos', 'new': 'dos'}])})
    check('E77 tanda en la que nada cambia: UNCHANGED y sin papelera',
          not res.get('isError') and mc.abre(t, 'SN_PATCH_EDITS_SIN_CAMBIOS_FMT') and
          not os.path.exists(os.path.join(SIN, '__delphi-patch')), t[:200])
    res, sc, t = llama('delphi_textedit', {'path': T77, 'fragment': 'no', 'new': 'no',
                                           'atline': 1})
    check('E77 ...y fragment == new: la misma nota (era un error EDIT-009)',
          not res.get('isError') and mc.abre(t, 'SN_EDIT_SIN_CAMBIOS_FMT'), t[:200])
    res, sc, t = llama('delphi_changeset', {'command': 'begin'})
    cid = mc.id_changeset(t)
    llama('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'edit',
                               'path': T77, 'old': 'uno', 'new': 'uno'})
    llama('delphi_changeset', {'command': 'preview', 'id': cid})
    res, sc, t = llama('delphi_changeset', {'command': 'commit', 'id': cid})
    check('E77 ...y un changeset que no cambia nada: UNCHANGED',
          not res.get('isError') and mc.abre(t, 'SN_CHANGESET_SIN_CAMBIOS_FMT') and
          not os.path.exists(os.path.join(SIN, '__delphi-patch')), t[:200])

    # E127 la sesion que se cierra para hacer sitio lo dice (SYS-033): decia "el
    # servidor se reinicio". Al final: se lleva tambien la de la bateria
    TOPE = int(re.search(r'\bSESIONES_MAX\s*=\s*(\d+)', open(os.path.join(
        mc.REPO, 'src', 'Server', 'Lsp.Identidad.pas'), encoding='utf-8', errors='replace').read()).group(1))

    def sesion_nueva(nombre):
        code, h, b = mc.post(cli.url, {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {
            'protocolVersion': '2025-03-26', 'capabilities': {},
            'clientInfo': {'name': nombre, 'version': '1'}}}, TOK, None, 'application/json')
        return h.get('Mcp-Session-Id') if h else None

    PRIMERA = sesion_nueva('e127-primera')
    for i in range(TOPE + 4):
        sesion_nueva('e127-%d' % i)
    code, h, b = mc.post(cli.url, {'jsonrpc': '2.0', 'id': 51, 'method': 'tools/list'}, TOK, PRIMERA,
                         'application/json')
    check('E127 una sesion cerrada para hacer sitio (%d): 404 SYS-033' % TOPE,
          bool(PRIMERA) and code == 404 and 'SYS-033' in b, '%s %r' % (code, b[:200]))

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
