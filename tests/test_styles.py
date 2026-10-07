"""E2E battery for v0.43.0-beta - delphi_styles (FMX styles by StyleName):
view / get / set / clone / lint / build over a copy of a REAL style pipeline
(a text .style with 200+ styles, a Tokens.ini, an .rc), plus the refusals
and the new `pattern` of delphi_search.

Needs DelphiStyleConvert.exe next to the server exe (built from
src/StyleConvert/DelphiStyleConvert.dproj) for build and for the platform default names.

Usage:  python tests/test_styles.py [path-to-DelphiLspMcp.exe]
"""
import json, os, re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('styles-battery')
# su propia copia del servidor, y A SU LADO el conversor de estilos, que es
# donde lo busca (sin el, build contesta "falta DelphiStyleConvert.exe")
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True)

STY = os.path.join(BASE, 'Styles')
PRJ = os.path.join(BASE, 'codigofuente')
os.makedirs(STY); os.makedirs(PRJ)

# --- a small but realistic style file (the shapes seen in a real export) ---
STYLE = """object TStyleContainer
  object TStyleDescription
    StyleName = 'Description'
    Title = 'Battery'
    Version = '1.0'
  end
  object TLayout
    StyleName = 'formheader'
    Size.Width = 200.000000000000000000
    Size.Height = 44.000000000000000000
    Visible = False
    object TRectangle
      StyleName = 'background'
      Align = Contents
      Fill.Color = xFFF6ECDB
      Stroke.Kind = None
      object TRectangle
        Align = Bottom
        Fill.Color = xFFD0BA8E
        Size.Height = 1.000000000000000000
      end
    end
    object TText
      StyleName = 'text'
      Align = Client
      TextSettings.Font.Size = 14.000000000000000000
      Text = 'cabecera'
    end
  end
  object TLayout
    StyleName = 'cardstyle'
    Size.Width = 100.000000000000000000
    object TRectangle
      StyleName = 'background'
      Fill.Gradient.Points = <
        item
          Color = xFFFFFFFF
          Offset = 0.000000000000000000
        end
        item
          Color = xFFEEEEEE
          Offset = 1.000000000000000000
        end>
      Fill.Color = xFFFFFFFF
    end
    object TPath
      StyleName = 'icon'
      Data.Path = {
        0100000000000000000000000000000000000000}
      Fill.Color = xFF000000
    end
  end
  object TLayout
    StyleName = 'duplicado'
    Visible = False
  end
  object TLayout
    StyleName = 'duplicado'
    Visible = True
  end
end
"""
open(os.path.join(STY, 'Battery.style'), 'w', encoding='utf-8', newline='\n').write(STYLE)
open(os.path.join(STY, 'Battery.Tokens.ini'), 'w', encoding='utf-8').write(
    "[clasico]\nbg=xFF000000\naccent=xFF111111\n\n[oscuro]\nbg=xFF222222\n")
open(os.path.join(STY, 'Battery.Estilos.rc'), 'w', encoding='utf-8').write(
    'BATTERY RCDATA "Battery.bin.style"\nOTRO RCDATA "NoExiste.bin.style"\n')
open(os.path.join(PRJ, 'UMain.fmx'), 'w', encoding='utf-8').write(
    "object FormMain: TFormMain\n  object Panel1: TPanel\n    StyleLookup = 'cardstyle'\n  end\n"
    "  object Button1: TButton\n    StyleLookup = 'buttonstyle'\n  end\n"
    "  object Label1: TLabel\n    StyleLookup = 'labelinventado'\n  end\nend\n")
open(os.path.join(PRJ, 'UMain.pas'), 'w', encoding='utf-8').write(
    "unit UMain;\ninterface\nimplementation\n// NOTA: no usar Lbl.StyleLookup := 'comentado1' aqui\n{ ni StyleLookup := 'comentado2' }\n(* StyleLookup := 'comentado3' *)\nprocedure X;\nbegin\n  Btn.StyleLookup := 'formheader';\n  Lbl.StyleLookup := 'otroinventado'; // StyleLookup := 'comentado4'\nend;\nend.\n")
# a binary style (signature only) to test the refusal
open(os.path.join(STY, 'Battery.bin.style'), 'wb').write(b'FMX_STYLE\x00\x01\x02' + b'\x00' * 40)


def spawn(extra_env=None):
    env = {'DELPHI_MCP_ROOTS': BASE}
    env.update(extra_env or {})
    return mc.Stdio(EXE, mc.entorno(env), nombre='styles-battery')


srv = spawn()
call = srv.call


def tras_etiqueta(t):
    """El mensaje sin la etiqueta que lo abre: set dice CAMBIADA/ANADIDA
    justo detras de ella (el verbo es SF_STYLE_*, sin etiqueta propia)."""
    t = (t or '').lstrip()
    m = mc.ETIQUETA.match(t)
    return t[m.end():].lstrip() if m else t


def rd(p):
    return open(p, 'rb').read().decode('utf-8-sig')


S = os.path.join(STY, 'Battery.style')
print('== styles battery ==')

# ---- view ----
out = call('delphi_styles', {"path": S})
d = json.loads(out)
names = [x['style'] for x in d['styles']]
check('view: 5 estilos de primer nivel', d['count'] == 5 and names[1:3] == ['formheader', 'cardstyle'], names)
check('view: partes contadas (formheader=2)', [x for x in d['styles'] if x['style'] == 'formheader'][0]['parts'] == 2, d['styles'])
check('view: lineas del estilo', [x for x in d['styles'] if x['style'] == 'formheader'][0]['lines'] == '7-29', d['styles'])
check('view: colecciones <item> y binarios {...} no rompen el parseo', [x for x in d['styles'] if x['style'] == 'cardstyle'][0]['parts'] == 2, d['styles'])
out = call('delphi_styles', {"path": S, "command": "view", "filter": "card"})
check('view: filter', json.loads(out)['count'] == 1, out[:200])

# ---- get ----
out = call('delphi_styles', {"path": S, "command": "get", "style": "formheader"})
check('get: bloque entero', out.startswith('formheader (TLayout) lines 7-29') and "Text = 'cabecera'" in out, out[:200])
# (revision de la 1.13.0) como delphi_read: cada linea con su numero, tal cual
# (el gemelo del get de delphi_designer, el mismo BlockText)
check('get: las lineas numeradas como delphi_read',
      re.search(r"(?m)^\s*\d+\|\s*Text = 'cabecera'", out) is not None, out[:400])
out = call('delphi_styles', {"path": S, "command": "get", "style": "formheader", "child": "background"})
check('get: parte por child', 'background (TRectangle)' in out and 'Fill.Color = xFFF6ECDB' in out and 'cabecera' not in out, out[:300])
out = call('delphi_styles', {"path": S, "command": "get", "style": "noexiste"})
check('get: estilo inexistente rechazado con pista', mc.rechazado(out) and 'command=view' in out, out)

# ---- set ----
out = call('delphi_styles', {"path": S, "command": "set", "style": "formheader", "child": "background", "prop": "Fill.Color", "value": "xFF112233"})
check('set: CAMBIADA', mc.abre(out, 'SN_STYLES_PROP_SET_FMT') and tras_etiqueta(out).startswith(mc.catalogo()['SF_STYLE_CAMBIADA']), out[:200])
txt = rd(S)
check('set: valor en disco con la indentacion original', '      Fill.Color = xFF112233' in txt and 'xFFF6ECDB' not in txt, txt)
out = call('delphi_styles', {"path": S, "command": "set", "style": "formheader", "prop": "Opacity", "value": "0.500000000000000000"})
check('set: ANADIDA tras StyleName', mc.abre(out, 'SN_STYLES_PROP_SET_FMT') and tras_etiqueta(out).startswith(mc.catalogo()['SF_STYLE_ANADIDA']), out[:200])
txt = rd(S)
i = txt.index("StyleName = 'formheader'"); j = txt.index('Opacity = 0.5')
check('set: la nueva propiedad va justo tras el StyleName', 0 < j - i < 40, txt[i:j + 40])
out = call('delphi_styles', {"path": S, "command": "set", "style": "formheader", "child": "background/text", "prop": "X", "value": "1"})
check('set: child inexistente rechazado', mc.rechazado(out) and 'has no part' in out, out)
out = call('delphi_styles', {"path": S, "command": "set", "style": "formheader", "prop": "Opacity", "delete": True})
check('set delete: QUITADA', mc.abre(out, 'SN_STYLES_PROP_DELETED_FMT') and 'Opacity' not in rd(S), out[:200])
out = call('delphi_styles', {"path": S, "command": "set", "style": "formheader", "prop": "Fill Color", "value": "x"})
check('set: prop con espacios rechazada', mc.rechazado(out) and mc.es(out, 'SR_STYLES_PROP_CHARS_FMT'), out)
out = call('delphi_styles', {"path": S, "command": "set", "style": "formheader", "prop": "Visible"})
check('set: sin value pide value (y menciona delete)', mc.es(out, 'SR_STYLES_NEED_VALUE') and 'delete=true' in out, out)
check('set: copia previa en __delphi-patch', os.path.isdir(os.path.join(STY, '__delphi-patch')))

# ---- clone ----
out = call('delphi_styles', {"path": S, "command": "clone", "style": "cardstyle", "name": "cardstyle_alt"})
check('clone: CLONADO', mc.abre(out, 'SN_STYLES_CLONED_FMT'), out[:200])
d = json.loads(call('delphi_styles', {"path": S}))
names = [x['style'] for x in d['styles']]
check('clone: el nuevo va justo detras del origen', names.index('cardstyle_alt') == names.index('cardstyle') + 1, names)
check('clone: partes copiadas', [x for x in d['styles'] if x['style'] == 'cardstyle_alt'][0]['parts'] == 2, d['styles'])
check('clone: el origen intacto', rd(S).count("StyleName = 'cardstyle'") == 1 and rd(S).count("StyleName = 'cardstyle_alt'") == 1, '')
out = call('delphi_styles', {"path": S, "command": "clone", "style": "cardstyle", "name": "cardstyle_alt"})
check('clone: nombre ocupado rechazado', mc.rechazado(out) and mc.es(out, 'SR_STYLES_NAME_TAKEN_FMT'), out)
out = call('delphi_styles', {"path": S, "command": "clone", "style": "cardstyle", "name": "mal nombre"})
check('clone: nombre invalido rechazado', mc.rechazado(out) and mc.es(out, 'SR_STYLES_NAME_CHARS_FMT'), out)
# el StyleName como lo escribe el IDE (un acento es #243), por el compositor
# de la casa, al clonar y al renombrar; y el renombrado juzga el nombre como
# clone. Se escribia entre comillas a mano y el renombrado quitaba comillas
# a mano (revision de la 1.17.0)
out = call('delphi_styles', {"path": S, "command": "clone", "style": "cardstyle", "name": "tarjetaBotón"})
check('clone con acento: el StyleName como el IDE (#243)', mc.abre(out, 'SN_STYLES_CLONED_FMT') and
      "StyleName = 'tarjetaBot'#243'n'" in rd(S) and 'tarjetaBotón' not in rd(S), out[:200])
out = call('delphi_styles', {"path": S, "command": "set", "style": "tarjetaBotón", "prop": "StyleName",
                             "value": "'tarjeta'#243'2'"})
d = json.loads(call('delphi_styles', {"path": S}))
check('set StyleName con el literal del IDE: se lee como texto y se escribe igual',
      mc.abre(out, 'SN_STYLES_RENAMED_FMT') and "StyleName = 'tarjeta'#243'2'" in rd(S) and
      'tarjetaó2' in [x['style'] for x in d['styles']], out[:200])
out = call('delphi_styles', {"path": S, "command": "set", "style": "tarjetaó2", "prop": "StyleName",
                             "value": "'mal nombre'"})
check('set StyleName juzga el nombre como clone', mc.rechazado(out) and mc.es(out, 'SR_STYLES_NAME_CHARS_FMT'), out)
# sin comillas y con guion: lo juzga el juez del NOMBRE, no la gramatica de un
# valor de form, que lo negaba (revision de la 1.17.0)
out = call('delphi_styles', {"path": S, "command": "set", "style": "tarjetaó2", "prop": "StyleName",
                             "value": "tarjeta-3"})
check('set StyleName sin comillas con guion: renombra', mc.abre(out, 'SN_STYLES_RENAMED_FMT') and
      "StyleName = 'tarjeta-3'" in rd(S), out[:300])
# un nombre de mas de 64 caracteres va en trozos, como el IDE: el arbol lo lee
# entero (ValorEnteroDe), y clonar DESDE el era un AV (revision de la 1.17.0)
LARGO = 'tarjeta' + 'x' * 63
out = call('delphi_styles', {"path": S, "command": "clone", "style": "cardstyle", "name": LARGO})
d = json.loads(call('delphi_styles', {"path": S}))
check('clone con un nombre de 70 caracteres: en trozos como el IDE, y la lista lo lee entero',
      mc.abre(out, 'SN_STYLES_CLONED_FMT') and LARGO in [x['style'] for x in d['styles']] and
      ("'" + LARGO[:64] + "' +") in rd(S) and ("'" + LARGO + "'") not in rd(S), out[:300])
out = call('delphi_styles', {"path": S, "command": "clone", "style": "cardstyle", "name": LARGO})
check('...otra vez: nombre ocupado (el nombre en trozos se encuentra)', mc.rechazado(out) and
      mc.es(out, 'SR_STYLES_NAME_TAKEN_FMT'), out[:300])
out = call('delphi_styles', {"path": S, "command": "clone", "style": LARGO, "name": "tarjeta_corta"})
check('...y clonar DESDE el largo: el clon con su nombre corto', mc.abre(out, 'SN_STYLES_CLONED_FMT') and
      "StyleName = 'tarjeta_corta'" in rd(S), out[:300])

# ---- lint ----
out = call('delphi_styles', {"path": STY, "command": "lint", "project": PRJ})
d = json.loads(out)
check('lint: parsea', d.get('styleFiles') == 1 and d['styleNames'] >= 5, out[:300])
check('lint: StyleName duplicado detectado', len(d['duplicatedStyleNames']) == 1 and d['duplicatedStyleNames'][0]['style'] == 'duplicado', d['duplicatedStyleNames'])
missing = sorted(x['lookup'] for x in mc.aciertos(d, 'lookupsWithoutStyle'))
check('lint: lookups sin estilo (fmx y pas), no los del proyecto', missing == ['labelinventado', 'otroinventado'], missing)
check('lint: los StyleLookup en COMENTARIOS del .pas no cuentan (//, llaves, paren-star, fin de linea)', not any(m.startswith('comentado') for m in missing), missing)
check('lint: buttonstyle es estandar (estilo por defecto de la plataforma)', d['lookupsStandard'] == 1, d)
check('lint: token ausente en un tema', len(d['tokensMissing']) == 1 and d['tokensMissing'][0]['theme'] == 'oscuro' and d['tokensMissing'][0]['token'] == 'accent', d['tokensMissing'])
check('lint: .rc con fichero ausente', len(d['rcMissingFiles']) == 1 and d['rcMissingFiles'][0]['missing'] == 'NoExiste.bin.style', d['rcMissingFiles'])
check('lint: clean=false (era ok, el nombre de "la llamada fue bien")', d['clean'] is False, d.get('clean'))
check('lint: rutas enmascaradas', 'srv' in d['stylesDir'] and ':' in d['stylesDir'], d['stylesDir'])

# ---- build ----
os.remove(os.path.join(STY, 'Battery.bin.style'))
open(os.path.join(STY, 'Battery.Estilos.rc'), 'w', encoding='utf-8').write('BATTERY RCDATA "Battery.bin.style"\n')
out = call('delphi_styles', {"path": STY, "command": "build"})
d = json.loads(out)
check('build: conversion OK', d['converted'][0]['ok'] is True and d['converted'][0]['bytes'] > 100, out[:300])
check('build: .bin.style creado con firma FMX', open(os.path.join(STY, 'Battery.bin.style'), 'rb').read(9) == b'FMX_STYLE', '')
check('build: .rc -> .res', d.get('rcOk') is True and os.path.exists(os.path.join(STY, 'Battery.Estilos.res')), out[:300])
check('build: ok', d['ok'] is True, d)
# un .rc que brcc32 no compila es un FALLO (salia exito con rcError y la nota
# de recompilar el proyecto; tercera revision)
_RC = os.path.join(STY, 'Battery.Estilos.rc')
open(_RC, 'w', encoding='utf-8').write('BATTERY RCDATA "Battery.bin.style"\nOTRO RCDATA "falta.bin"\n')
out = call('delphi_styles', {"path": STY, "command": "build"})
d = mc.como_json(out)
check('build: un .rc que no compila es un fallo con su motivo (y sin "recompila")',
      mc.abre(d.get('error', ''), 'SR_STYLES_BUILD_RC_FMT') and 'note' not in d, out[:300])
open(_RC, 'w', encoding='utf-8').write('BATTERY RCDATA "Battery.bin.style"\n')
# the binary must not be editable
out = call('delphi_styles', {"path": os.path.join(STY, 'Battery.bin.style'), "command": "view"})
check('binario rechazado para editar/ver', mc.rechazado(out) and mc.es(out, 'SR_STYLES_BINARY_FMT'), out)
# lint again: clean except the duplicate
out = call('delphi_styles', {"path": STY, "command": "lint", "project": PRJ})
d = json.loads(out)
check('lint tras build: rc limpio', d['rcMissingFiles'] == [], d['rcMissingFiles'])

# ---- refusals ----
out = call('delphi_styles', {"path": STY, "command": "get", "style": "x"})
check('get sobre carpeta rechazado', mc.rechazado(out) and mc.es(out, 'SR_STYLES_NEED_FILE'), out)
out = call('delphi_styles', {"command": "view"})
check('sin path: pide path + reconectar',
      mc.abre(out, 'SR_SYS_MISSING_PARAM_FMT') and '"path"' in out and 'reconnect' in out, out)
out = call('delphi_styles', {"path": r'C:\Windows\win.ini', "command": "view"})
check('fuera de la jaula rechazado', mc.rechazado(out) and mc.es(out, 'SR_JAIL_FMT'), out[:200])

# ---- delphi_search pattern ----
out = call('delphi_search', {"root": STY, "query": "StyleName = 'cardstyle'", "pattern": "*.style", "maxresults": 5})
d = json.loads(out)
check('search pattern=*.style: encuentra', d['total'] >= 1 and d['filesScanned'] >= 1, out[:200])
out = call('delphi_search', {"root": STY, "query": "cardstyle", "maxresults": 5})
check('search sin pattern: sigue sin barrer .style', json.loads(out)['filesScanned'] == 0, out[:200])
out = call('delphi_search', {"root": STY, "query": "x", "pattern": "*.style;*.ini"})
check('search pattern compuesto rechazado', mc.rechazado(out) and mc.es(out, 'SR_WS_PATTERN_DEBE_SER_MASCARA'), out[:200])

# ---- delete ----
out = call('delphi_styles', {"path": S, "command": "delete", "style": "cardstyle_alt"})
check('delete: BORRADO con lineas y contador', mc.abre(out, 'SN_STYLES_DELETED_FMT'), out[:200])
d = json.loads(call('delphi_styles', {"path": S}))
names = [x['style'] for x in d['styles']]
check('delete: el estilo ya no esta y el origen sigue', 'cardstyle_alt' not in names and 'cardstyle' in names, names)
check('delete: el resto del fichero intacto (formheader 7-29)', [x for x in d['styles'] if x['style'] == 'formheader'][0]['lines'] == '7-29', d['styles'])
out = call('delphi_styles', {"path": S, "command": "delete", "style": "noexiste"})
check('delete: estilo inexistente rechazado', mc.rechazado(out) and mc.es(out, 'SR_STYLE_HAY_NINGUN_ESTILO_COMMAND_FMT'), out)
out = call('delphi_styles', {"path": S, "command": "delete"})
check('delete: sin style pide style', mc.es(out, 'SR_STYLES_NEED_STYLE') and not mc.abre(out, 'SN_STYLES_DELETED_FMT'), out)

srv.cierra()

# (read-only mode is exercised over HTTP in test_http_auth.py)

mc.fin('styles battery')
