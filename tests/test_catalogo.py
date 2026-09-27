# -*- coding: utf-8 -*-
"""El catalogo de mensajes (Lsp.Texts.pas), SIN servidor: la forma de sus
etiquetas. Decision de David (27-sep-2026): cada mensaje EMPIEZA por
[AREA-NNN] o, si es un rechazo, [AREA-NNN RESULTADO]; las baterias y el
servidor lo reconocen por el id y no por la frase, asi el texto se puede
traducir sin romper nada.

  C0  el comprobador SABE fallar: un catalogo de ejemplo con un fallo de cada
      clase, y los encuentra todos (con 0 etiquetas, el resto pasaria en vacio)
  C1  el patron de las baterias (mcp_cliente.ETIQUETA) es el mismo que el del
      servidor (Lsp.Texts.MSG_TAG_REGEX): un formato, dos lectores vigilados
  C2  todo lo que PARECE una etiqueta lo es (nada de [CFG-07] o [CFG-007 DENEGADO])
  C3  ningun id se repite en el catalogo, y cada mensaje lleva una como mucho
  C4  la etiqueta ABRE el mensaje
  C4b todo SR_/SK_/SN_ la lleva (antes solo se contaba)
  C5  un rechazo (SR_) etiquetado declara su resultado; un resultado bueno
      (SK_) o una nota (SN_) no; las descripciones (SD_, SP_) y el log (SL_) no
      llevan etiqueta
  C6  un rechazo que dice que FALTA un parametro o que uno no vale declara
      INVALID_PARAM (la regla 11: "corrige la llamada y repite"); la revision
      del 27-sep encontro 70 que decian DENIED ("no insistas")
  C7  el catalogo esta en ingles (palabras que solo son castellano)
  C8  un SR_ no va en un campo JSON que no sea "error": ahi nadie lo lee y
      la respuesta sale como exito (upload, rename, captura: 27-sep)
  C9  todo uso de una constante del catalogo pasa por su helper

Usage:  python tests/test_catalogo.py
"""
import os, re
from collections import Counter
import mcp_cliente as mc
from mcp_cliente import check, fin

TEXTS = os.path.join(mc.REPO, 'src', 'Server', 'Lsp.Texts.pas')
src = open(TEXTS, encoding='utf-8-sig').read()


# un solo lector del catalogo para todas las baterias
constantes = mc.constantes


C = constantes(src)
check('el catalogo se lee: mas de 700 constantes de texto', len(C) > 700, len(C))
# el del nodo y el lanzador (programas del destino, no enlazan Lsp.Texts):
# mismas reglas, y un id no se repite entre los dos catalogos. Sus nombres
# llevan '@nodo' detras para no pisar uno igual del servidor.
MLD = os.path.join(mc.REPO, 'src', 'DesktopNode', 'Mld.Textos.pas')
CN = constantes(open(MLD, encoding='utf-8-sig').read())
check('el catalogo del nodo se lee (Mld.Textos)', len(CN) > 30, len(CN))
C.update({n + '@nodo': t for n, t in CN.items()})

m = re.search(r"MSG_TAG_REGEX\s*=\s*'((?:[^']|'')*)'", src)
check('C1 el patron de las baterias es el del servidor (MSG_TAG_REGEX)',
      m is not None and m.group(1).replace("''", "'") == mc.ETIQUETA.pattern,
      (m.group(1) if m else None, mc.ETIQUETA.pattern))

PARECE = re.compile(r'\[[A-Z]{1,8}-\d+[^\]\n]*\]')
FUERA = {'MSG_TAG_REGEX', 'SL_MSG_UNTAGGED_FMT'}


def problemas(consts):
    """Lo que esta mal en las etiquetas de un catalogo {NOMBRE: texto}."""
    p = {'malas': [], 'repetidas': [], 'varias': [], 'al_medio': [], 'reglas': []}
    ids = Counter()
    for nombre, txt in consts.items():
        if nombre in FUERA:
            continue
        for e in PARECE.finditer(txt):
            if not mc.ETIQUETA.fullmatch(e.group(0)):
                p['malas'].append('%s: %s' % (nombre, e.group(0)))
        tags = list(mc.ETIQUETA.finditer(txt))
        if len(tags) > 1:
            p['varias'].append(nombre)
        for tg in tags:
            ids[tg.group(1)] += 1
            if not txt.lstrip(' \r\n').startswith(tg.group(0) + ' '):
                p['al_medio'].append(nombre)
            pref = nombre[:3]
            if pref == 'SR_' and not tg.group(2):
                p['reglas'].append('%s: un rechazo sin resultado' % nombre)
            if pref in ('SK_', 'SN_') and tg.group(2):
                p['reglas'].append('%s: %s declara %s' % (nombre, pref, tg.group(2)))
            # SF_: un trozo que va dentro de otro mensaje o la plantilla de una
            # linea de un listado (el resto, 27-sep): tampoco lleva etiqueta
            if pref in ('SD_', 'SP_', 'SL_', 'SE_', 'SF_'):
                p['reglas'].append('%s: %s no lleva etiqueta' % (nombre, pref))
    p['repetidas'] = [i for i, n in ids.items() if n > 1]
    return p


# el comprobador SABE fallar: un catalogo de ejemplo con un fallo de cada clase
EJEMPLO = {'SR_A': '[CFG-07 DENIED] a.',             # mal formada
           'SR_B': '[CFG-001 DENIED] b.',
           'SR_C': '[CFG-001 DENIED] c.',            # id repetido
           'SN_D': '[EDIT-001] nota y [EDIT-002]',   # dos, y la segunda en medio
           'SR_E': '[CFG-002] e.',                   # rechazo sin resultado
           'SN_F': '[EDIT-003 DENIED] nota.',        # nota que declara
           'SD_G': '[EDIT-004] descripcion.'}        # descripcion con etiqueta
e = problemas(EJEMPLO)
check('C0 el comprobador encuentra cada fallo plantado',
      e['malas'] == ['SR_A: [CFG-07 DENIED]'] and e['repetidas'] == ['CFG-001'] and
      e['varias'] == ['SN_D'] and e['al_medio'] == ['SN_D'] and len(e['reglas']) == 3, e)

p = problemas(C)
check('C2 todo lo que parece una etiqueta lo es', not p['malas'], p['malas'][:10])
check('C3 ningun id repetido', not p['repetidas'], p['repetidas'][:10])
check('C3b una etiqueta por mensaje como mucho', not p['varias'], p['varias'][:10])
check('C4 la etiqueta ABRE el mensaje', not p['al_medio'], p['al_medio'][:10])
check('C5 rechazos con resultado; notas y buenos sin el; descripciones, log, excepciones y trozos sin '
      'etiqueta', not p['reglas'], p['reglas'][:10])

sin = [n for n in C if n[:3] in ('SR_', 'SK_', 'SN_') and not mc.ETIQUETA.match(C[n].lstrip(' \r\n'))]
check('C4b todo SR_/SK_/SN_ lleva su etiqueta', not sin, sin[:10])

# C6: el resultado de un parametro que falta o no vale
PARAM = re.compile(r'(^Missing "|^"\w+" is missing|\bneeds? "|\bis not a valid\b|^\w+ must be\b|'
                   r'^Command must be)', re.I)
# lo que PARECE un parametro y no lo es: la llamada es buena y la tool no
# hace eso (cambia de rumbo)
NO_ES_PARAM = {'SR_STYLES_VALUE_LINE'}
mal = []
for n, t in C.items():
    cuerpo = re.sub(r'^\s*\[[^\]]+\]\s*', '', t)
    if n.startswith('SR_') and n.split('@')[0] not in NO_ES_PARAM and PARAM.search(cuerpo[:100]) \
            and mc.outcome(t) != 'INVALID_PARAM':
        mal.append('%s %s' % (n, mc.outcome(t)))
check('C6 un parametro que falta o no vale es INVALID_PARAM', not mal, mal[:10])
e6 = [n for n, t in {'SR_X': '[CFG-001 DENIED] Missing "path".'}.items()
      if PARAM.search(re.sub(r'^\s*\[[^\]]+\]\s*', '', t)) and mc.outcome(t) != 'INVALID_PARAM']
check('C6 ...y el comprobador sabe fallar', e6 == ['SR_X'], e6)

# C7: castellano (palabras que en ingles no existen o no salen en un mensaje)
ES = re.compile(r"\b(el|los|las|del|que|una|unas|por|para|con|esta|este|pero|como|donde|hay|puede|"
                r"fichero|carpeta|pude|enviad[oa]|devolvio|simbolos|abierta|sesion|nada|todo|cuando|"
                r"tambien|aqui|antes|despues|linea|lineas|falta|debe|necesita)\b", re.I)
es_ = ['%s: %s' % (n, m.group(0)) for n, t in C.items() for m in ES.finditer(t)]
check('C7 el catalogo esta en ingles', not es_, es_[:10])
import glob
FUENTES = [f for f in glob.glob(os.path.join(mc.REPO, 'src', 'Server', '*.pas')) +
           glob.glob(os.path.join(mc.REPO, 'vendor', 'src', '**', '*.pas'), recursive=True) +
           glob.glob(os.path.join(mc.REPO, 'src', 'DesktopNode', '*.pas')) +
           glob.glob(os.path.join(mc.REPO, 'src', 'DesktopNode', '*.dpr')) +
           glob.glob(os.path.join(mc.REPO, 'src', 'RunJob', '*.dpr'))
           if '__' not in f and not f.endswith(('Lsp.Texts.pas', 'Mld.Textos.pas'))]
LIMPIAS = {f: mc.pascal_sin_comentarios(open(f, encoding='utf-8-sig', errors='replace').read())
           for f in FUENTES}

# C8: un SR_ en un campo JSON que no es "error"
fuera = []
for f, fuente in LIMPIAS.items():
    for m in re.finditer(r"(?:AddPair|PonResultado)\('(\w+)'[^;]*?\b(SR_[A-Z0-9_]+)", fuente):
        if m.group(1) != 'error':
            fuera.append('%s: %s <- %s' % (os.path.basename(f), m.group(1), m.group(2)))
# ...y cualquier campo que se LLAME error sin serlo: el fallo metido en una
# variable no llevaba SR_ en la misma sentencia (la captura sin imagen lo
# hacia). Declarados: screenshotError (un GESTO hecho cuya captura fallo: el
# gesto si se hizo) y rcError (el .rc que brcc32 no compilo: un resultado del
# build, como success=false en delphi_build).
# isError es el campo del PROTOCOLO y firstError el primer error del
# compilador en el resultado de un build (success=false no es un fallo de la
# llamada)
CAMPOS_ERROR_DECLARADOS = {'screenshotError', 'rcError', 'isError', 'firstError'}
for f, fuente in LIMPIAS.items():
    for m in re.finditer(r"(?:AddPair|PonResultado)\('(\w*[Ee]rror)'", fuente):
        if m.group(1) != 'error' and m.group(1) not in CAMPOS_ERROR_DECLARADOS:
            fuera.append('%s: campo %s' % (os.path.basename(f), m.group(1)))
check('C8 un fallo (SR_) solo va en el campo "error" de un JSON', not fuera, fuera[:10])
# C9: todo uso de un mensaje pasa por su helper (David: para poder
# traducirlo un dia; y el helper es quien sabe de etiquetas)
NOMBRES = set(n.split('@')[0] for n in C if n[:3] in ('SR_', 'SN_', 'SK_'))
directas = []
for f, fuente in LIMPIAS.items():
    for l in fuente.splitlines():
        for m in re.finditer(r'\b(S[RNK]_[A-Z0-9_]+)\b', l):
            if m.group(1) in NOMBRES and not re.search(
                    r'\b(MsgText|MsgFmt|MsgEnvuelve|MsgConCausa|HasMsg|EsMsg|MsgTag)\(\s*(\w+,\s*)?%s\b'
                    % m.group(1), l):
                directas.append('%s: %s' % (os.path.basename(f), l.strip()[:120]))
check('C9 todo mensaje sale por su helper (MsgText/MsgFmt/...)', not directas, directas[:10])
fin('catalogo')
