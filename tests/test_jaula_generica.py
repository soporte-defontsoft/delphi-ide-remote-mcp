# -*- coding: utf-8 -*-
"""Bateria GENERICA de jaula: TODOS los parametros marcados [RutaDelServidor]
del contrato, contra una victima FUERA de las raices, en todas las formas en
que un agente puede escribir una ruta.

Por que existe: hasta la 1.7.3 cada regla de jaula llevaba SU bateria, y
cada una media una tool y una forma. La 1.7.2 se publico con la puerta verde
y toda ruta de mas de 232 caracteres FUERA de las raices se leia: la bateria
de esa regla media dentro de la jaula. Esta no sabe de reglas: toma el
contrato vivo (los pares tool/parametro que el servidor vigila) y una victima
fuera, y exige lo mismo a todos: la respuesta es una negativa, no trae el
secreto, y el arbol de la victima queda como estaba.

Los pares salen del FUENTE (src/Server/*.pas): [RutaDelServidor] en las
clases *Params, la herencia entre ellas, TXTool = class(TMCPToolBase<TXParams>)
y RegisterTool('nombre', ... TXTool.Create). Se contrastan con el esquema
vivo (tools/list) y con jailedParams (delphi_workspace: el mapa por RTTI del
servidor): si el fuente y el servidor no cuentan lo mismo, ROJO.

Formas (cada una un check con la lista de ofensores, y otro con la victima):
  plana, barras normales, MAYUSCULAS, srvX: (la unidad virtual), alias 8.3,
  larga (>= 250 caracteres), traversal (jaula\\..\\victima), por una junction
  desde DENTRO de la jaula, punto final, espacio final, ::$DATA, \\\\?\\ y el
  UNC administrativo (\\\\localhost\\X$, si responde).
Controles: el positivo (lo mismo DENTRO de la jaula se lee, y el detector de
fugas ve un secreto en base64), y los fixtures de dentro siguen intactos al
final (un origen de dentro con un destino de fuera no se mueve).
Cuatro formas (punto final, espacio final, ::$DATA y \\\\?\\) las niega la regla de
anomalias de la puerta ANTES de comparar con las raices, para los 40 parametros:
miden que esa regla sigue en la puerta para todos, no que la ruta este fuera
(medido por r12b: GUARD-010/009/022; las otras nueve, GUARD-002/001 de la jaula).

Medida contra el binario publicado de la 1.7.2 (el del agujero): la forma
larga sale ROJA y las demas verdes. Es la prueba de que esta bateria ve lo
que la de aquella regla no veia.

Limite sabido: la negativa puede venir de la puerta o de un argumento que
falta (a los obligatorios que no son rutas se les pasa 'x'): esta bateria
mide que NO se lee ni se escribe fuera por ningun parametro, no cual puerta
lo paro. Eso lo miden las baterias de cada regla.

Usage:  python tests/test_jaula_generica.py [path-to-DelphiLspMcp.exe]
"""
import base64
import glob
import hashlib
import json
import os
import re
import subprocess
import time
import mcp_cliente as mc
from mcp_cliente import check

SRC = os.path.join(mc.REPO, 'src', 'Server')
SECRETO = 'SECRETO-JAULA-GENERICA'   # solo en CONTENIDO: una negativa cita la ruta
CONTROL = 'CONTROL-POSITIVO'
# los nombres de parametro que son una CARPETA o un DESTINO nuevo: lo demas,
# un fichero que existe
CARPETAS = {'root', 'dir', 'repo', 'folder', 'directory', 'cwd', 'outdir'}
DESTINOS = {'dest', 'out', 'outfile', 'output', 'to', 'target', 'destination'}


# ------------------------------------------------------------------ pares

def fuente(p):
    with open(p, encoding='utf-8-sig', errors='replace') as fh:
        return mc.pascal_sin_comentarios(fh.read())


def pares_del_fuente():
    """[(tool, param)] de todo el contrato, leidos del fuente: la marca, la
    herencia entre clases *Params, la clase de la tool y su registro."""
    clases, tools, registro = {}, {}, {}
    for p in glob.glob(os.path.join(SRC, '*.pas')):
        t = fuente(p)
        for m in re.finditer(r'^\s+(\w+)\s*=\s*class(?:\s*\(\s*([\w.<>]+)\s*\))?\s*$(.*?)^\s+end;',
                             t, re.M | re.S):
            nombre, padre, cuerpo = m.group(1), m.group(2) or '', m.group(3)
            g = re.match(r'TMCPToolBase<(\w+)>', padre)
            if g:
                tools[nombre] = g.group(1)
                continue
            props = re.findall(r'\[RutaDelServidor\][^;]*?property\s+(\w+)\s*:', cuerpo, re.S)
            clases[nombre] = (padre, props)
        for m in re.finditer(r"RegisterTool\('(\w+)',\s*function: IMCPTool begin Result := (\w+)\.Create; end\)", t):
            registro[m.group(1)] = m.group(2)

    def props_de(clase, vistas=()):
        if clase not in clases or clase in vistas:
            return []
        padre, props = clases[clase]
        return props_de(padre, vistas + (clase,)) + props

    pares = []
    for tool, tclase in sorted(registro.items()):
        for prop in props_de(tools.get(tclase, '')):
            pares.append((tool, prop.lower().rstrip('_')))
    return pares


# ---------------------------------------------------------------- terreno

BASE = mc.larga(mc.carpeta('jaula_generica'))   # forma LARGA: con un %TEMP% en 8.3 (DFONTA~1) la "plana" era un alias (r12b)
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jaula')
VICT = os.path.join(BASE, 'victima-jaula-generica')   # hermana de la jaula: FUERA
os.makedirs(JAIL)
os.makedirs(os.path.join(VICT, 'sub'))
EXE = mc.copia_exe(EXEDIR)

# la victima: el secreto solo en el CONTENIDO (una negativa cita la ruta)
NOTA = os.path.join(VICT, 'nota.txt')
open(NOTA, 'w', newline='\n').write(SECRETO + '\n')
open(os.path.join(VICT, 'sub', 'otra.txt'), 'w', newline='\n').write(SECRETO + ' en sub\n')
IDENT = SECRETO.replace('-', '_')
open(os.path.join(VICT, 'Unidad.pas'), 'w', newline='\r\n').write(
    'unit Unidad;\n\ninterface\n\nprocedure %s;\n\nimplementation\n\n'
    'procedure %s;\nbegin\nend;\n\nend.\n' % (IDENT, IDENT))
open(os.path.join(VICT, 'Unidad.dproj'), 'w', newline='\r\n').write(
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n'
    '  <PropertyGroup>\n    <MainSource>Unidad.dpr</MainSource>\n'
    '    <SanitizedProjectName>%s</SanitizedProjectName>\n  </PropertyGroup>\n'
    '</Project>\n' % IDENT)
# la forma LARGA: la misma victima, a mas de 250 caracteres
LARGO = os.path.join(VICT, 'l' * (250 - len(VICT) - 9), 'nota.txt')
os.makedirs(os.path.dirname(LARGO), exist_ok=True)   # un %TEMP% largo la deja corta: J1 lo dice
open(LARGO, 'w', newline='\n').write(SECRETO + ' por la ruta larga\n')
# lo de DENTRO: el control positivo y el valor de los demas parametros
DENTRO = os.path.join(JAIL, 'Dentro.pas')
open(DENTRO, 'w', newline='\r\n').write('unit Dentro;\n\ninterface\n\n// %s\n\nimplementation\n\nend.\n' % CONTROL)
DENTRO_TXT = os.path.join(JAIL, 'dentro.txt')
open(DENTRO_TXT, 'w', newline='\n').write(CONTROL + '\n')
# una junction desde DENTRO de la jaula hacia la victima
ENLACE = os.path.join(JAIL, 'enlace-victima')
subprocess.run(['cmd', '/c', 'mklink', '/J', ENLACE, VICT], capture_output=True)
HAY_ENLACE = os.path.isdir(ENLACE) and os.path.exists(os.path.join(ENLACE, 'nota.txt'))


def unc(p):
    """La misma ruta por el recurso administrativo local (\\\\localhost\\X$\\...)."""
    return '\\\\localhost\\%s$%s' % (p[0], p[2:])


HAY_UNC = os.path.isdir(unc(VICT))
ALIAS_NOTA, ALIAS_VICT = mc.corta(NOTA), mc.corta(VICT)
HAY_83 = bool(ALIAS_VICT) and ALIAS_VICT.lower() != VICT.lower()


def foto(raiz):
    """{ruta relativa: sha256} de los ficheros y las carpetas de un arbol."""
    f = {}
    for d, ds, fs in os.walk(raiz):
        # un junction no se cruza: os.walk entra en el (r12d), y la foto de DENTRO
        # traia a la victima de detras del enlace
        ds[:] = [x for x in ds if not os.path.isjunction(os.path.join(d, x))]
        for x in fs:
            p = os.path.join(d, x)
            with open(p, 'rb') as fh:
                f[os.path.relpath(p, raiz)] = hashlib.sha256(fh.read()).hexdigest()
        for x in ds:
            f[os.path.relpath(os.path.join(d, x), raiz) + os.sep] = ''
    return f


ANTES = foto(VICT)
DENTRO_ANTES = foto(JAIL)

# las formas: nombre -> (fichero, carpeta); None = no se puede medir aqui
FORMAS = [
    ('plana', (NOTA, VICT)),
    ('barras normales', (NOTA.replace('\\', '/'), VICT.replace('\\', '/'))),
    ('MAYUSCULAS', (NOTA.upper(), VICT.upper())),
    ('unidad virtual srvX:', (mc.virtual(NOTA), mc.virtual(VICT))),
    ('alias 8.3', (ALIAS_NOTA, ALIAS_VICT) if HAY_83 else None),
    ('larga (%d caracteres)' % len(LARGO), (LARGO, os.path.dirname(LARGO))),
    ('traversal jaula\\..\\victima', (os.path.join(JAIL, '..', os.path.basename(VICT), 'nota.txt'),
                                     os.path.join(JAIL, '..', os.path.basename(VICT)))),
    ('por una junction desde dentro', (os.path.join(ENLACE, 'nota.txt'), os.path.join(ENLACE, 'sub'))
     if HAY_ENLACE else None),
    ('punto final', (NOTA + '.', VICT + '.')),
    ('espacio final', (NOTA + ' ', VICT + ' ')),
    ('::$DATA', (NOTA + '::$DATA', VICT + '::$DATA')),
    ('prefijo \\\\?\\', ('\\\\?\\' + NOTA, '\\\\?\\' + VICT)),
    ('UNC administrativo', (unc(NOTA), unc(VICT)) if HAY_UNC else None),
]


# ---------------------------------------------------------------- detector

B64 = re.compile(r'[A-Za-z0-9+/]{16,}={0,2}')


def fuga_en(texto, marca):
    """True si el texto trae la marca, tal cual o dentro de un base64."""
    if marca in texto:
        return True
    for m in B64.finditer(texto):
        try:
            if marca.encode() in base64.b64decode(m.group(0) + '=' * (-len(m.group(0)) % 4)):
                return True
        except Exception:
            pass
    return False


# ------------------------------------------------------------------ server

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='jaula-generica', t=60)
try:
    m = srv.request('tools/list')
    ESQUEMA = {t['name']: t.get('inputSchema') or {} for t in ((m or {}).get('result') or {}).get('tools', [])}
    PARES = pares_del_fuente()
    print('  pares del fuente (%d): %s' % (len(PARES), ' '.join('%s.%s' % p for p in PARES)))
    check('J0 pares [RutaDelServidor] del fuente: %d (se esperan 30 o mas)' % len(PARES), len(PARES) >= 30)
    faltan = [p for p in PARES if p[0] not in ESQUEMA or p[1] not in ESQUEMA[p[0]].get('properties', {})]
    check('J0 ...cada par existe en el esquema vivo (tools/list)', not faltan, faltan)
    w = mc.como_json(srv.call('delphi_workspace', {}))
    vigilados = (w.get('server') or {}).get('jailedParams', -1)
    check('J0 ...y el servidor vigila los mismos por RTTI (jailedParams=%s)' % vigilados,
          vigilados == len(PARES), 'fuente=%d servidor=%s' % (len(PARES), vigilados))
    PARES = [p for p in PARES if p not in faltan]
    DE_TOOL = {}
    for tool, param in PARES:
        DE_TOOL.setdefault(tool, set()).add(param)

    def valor_dentro(param, n):
        if param in CARPETAS:
            return JAIL
        if param in DESTINOS:
            return os.path.join(JAIL, 'salida-%d.txt' % n)   # no existe
        return DENTRO

    def args_para(tool, probado=None, valor=None, n=0):
        """Los argumentos de una llamada: el parametro probado con su forma,
        las demas rutas obligatorias DENTRO, y 'x' (o su tipo) en el resto."""
        esq = ESQUEMA[tool]
        args = {}
        for nombre in esq.get('required', []):
            if nombre == probado:
                continue
            if nombre in DE_TOOL.get(tool, ()):
                args[nombre] = valor_dentro(nombre, n)
            else:
                tipo = (esq.get('properties', {}).get(nombre) or {}).get('type', 'string')
                args[nombre] = {'boolean': False, 'integer': 1, 'number': 1,
                                'array': [], 'object': {}}.get(tipo, 'x')
        if probado is not None:
            args[probado] = valor
        return args

    # J1 los controles positivos: lo de dentro se lee, y el detector ve base64
    r = srv.call('delphi_read', args_para('delphi_read', 'path', DENTRO))
    check('J1 control positivo: lo de DENTRO se lee', CONTROL in r and not mc.fallo(r), r[:200])
    msg = srv.call_msg('delphi_fetch', args_para('delphi_fetch', 'path', DENTRO_TXT))
    check('J1 ...y el detector ve un secreto en base64 (delphi_fetch de dentro)',
          fuga_en(json.dumps(msg), CONTROL) and CONTROL not in json.dumps(msg), json.dumps(msg)[:200])
    check('J1 ...la victima existe fuera y tiene su secreto', SECRETO in open(NOTA).read()
          and SECRETO in open(LARGO).read() and len(LARGO) >= 250, LARGO)

    # J2.. cada forma, contra TODOS los pares
    n = 0
    colgado = False
    for k, (nombre, forma) in enumerate(FORMAS, start=2):
        if forma is None:
            print('NOTA: J%d %s sin medir en esta maquina' % (k, nombre))
            continue
        fichero, carpeta = forma
        ofensores = []
        for tool, param in PARES:
            n += 1
            valor = carpeta if param in CARPETAS else fichero
            msg = srv.call_msg(tool, args_para(tool, param, valor, n))
            t = mc.texto(msg)
            crudo = json.dumps(msg) if msg is not None else ''
            res = (msg or {}).get('result') or {}
            # sin respuesta NO es una negativa: mc.fallo la contaba, y un servidor
            # colgado daba la bateria en verde tras 520 x 60 s (r12b); se corta
            if mc.sin_respuesta(t):
                ofensores.append('%s.%s -> SIN RESPUESTA %s' % (tool, param, t[:80]))
                colgado = True
                break
            negada = (res.get('isError') is True) or mc.rechazado(t)
            # el secreto con guiones (los .txt) y como identificador (el .pas y el .dproj)
            if not negada or fuga_en(crudo, SECRETO) or fuga_en(crudo, IDENT):
                ofensores.append('%s.%s -> %s' % (tool, param, t[:120]))
        check('J%d forma %s: %d pares, todos negados y sin fuga' % (k, nombre, len(PARES)),
              not ofensores, ofensores[:6])
        check('J%d ...y la victima intacta' % k, foto(VICT) == ANTES,
              [x for x in set(ANTES) ^ set(foto(VICT))][:6])
        if colgado:
            break   # cada forma esperaria 60 s por llamada a un servidor que no contesta

    # lo de DENTRO sigue como estaba: un origen de dentro con un destino de
    # fuera no se movio ni se reescribio
    despues = foto(JAIL)
    # ...y nada NUEVO dentro (una copia de la victima que entrara y luego fallara
    # no cambiaba ninguna clave de antes; r12b). Lo del servidor (sus temporales y
    # su papelera dentro de la raiz) no cuenta como nuevo.
    nuevo = [x for x in despues if x not in DENTRO_ANTES and
             not x.startswith(('__delphi-temp', '__delphi-patch'))]
    check('J99 los fixtures de dentro siguen intactos, y nada nuevo dentro',
          not nuevo and all(despues.get(k) == v for k, v in DENTRO_ANTES.items()),
          nuevo[:6] + [k for k, v in DENTRO_ANTES.items() if despues.get(k) != v][:6])
finally:
    srv.cierra()
    time.sleep(0.5)
    if HAY_ENLACE:
        mc.borra(ENLACE)   # el enlace como enlace, nunca lo de detras
    mc.borra(BASE)

mc.fin('test_jaula_generica')
