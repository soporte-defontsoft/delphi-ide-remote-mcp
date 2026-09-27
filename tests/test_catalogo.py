# -*- coding: utf-8 -*-
"""El catalogo de mensajes (Lsp.Texts.pas), SIN servidor: la forma de sus
etiquetas. Decision de David (27-sep-2026): cada mensaje lleva al FINAL de su
texto [AREA-NNN] o, si es un rechazo, [AREA-NNN RESULTADO]; las baterias y el
servidor lo reconocen por el id y no por la frase, asi el texto se puede
traducir sin romper nada.

  C0  el comprobador SABE fallar: un catalogo de ejemplo con un fallo de cada
      clase, y los encuentra todos (con 0 etiquetas, el resto pasaria en vacio)
  C1  el patron de las baterias (mcp_cliente.ETIQUETA) es el mismo que el del
      servidor (Lsp.Texts.MSG_TAG_REGEX): un formato, dos lectores vigilados
  C2  todo lo que PARECE una etiqueta lo es (nada de [CFG-07] o [CFG-007 DENEGADO])
  C3  ningun id se repite en el catalogo, y cada mensaje lleva una como mucho
  C4  la etiqueta va al FINAL del mensaje
  C5  un rechazo (SR_) etiquetado declara su resultado; un resultado bueno
      (SK_) o una nota (SN_) no; las descripciones (SD_, SP_) y el log (SL_) no
      llevan etiqueta
Y cuenta lo que falta por etiquetar (no falla por eso mientras se migra).

Usage:  python tests/test_catalogo.py
"""
import os, re
from collections import Counter
import mcp_cliente as mc
from mcp_cliente import check, fin

TEXTS = os.path.join(mc.REPO, 'src', 'Server', 'Lsp.Texts.pas')
src = open(TEXTS, encoding='utf-8-sig').read()


def constantes(t):
    """{NOMBRE: texto} de las constantes de cadena: sus literales juntos, sin
    comentarios. Lo que no es literal (otra constante, #10) se salta o se
    traduce; basta para leer etiquetas."""
    t = re.sub(r'//[^\n]*', '', t)
    t = re.sub(r'\{[^}]*\}', '', t)
    out = {}
    for m in re.finditer(r'^\s{2}([A-Z][A-Z0-9_]+)\s*=\s*(.*?);\s*$', t, re.M | re.S):
        nombre, expr = m.group(1), m.group(2)
        if nombre in out or expr.count("'") == 0:
            continue
        partes = re.findall(r"'((?:[^']|'')*)'|#(\d+)", expr)
        out[nombre] = ''.join(a.replace("''", "'") if a or not b else chr(int(b)) for a, b in partes)
    return out


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
            if not txt.rstrip().endswith(tg.group(0)):
                p['al_medio'].append(nombre)
            pref = nombre[:3]
            if pref == 'SR_' and not tg.group(2):
                p['reglas'].append('%s: un rechazo sin resultado' % nombre)
            if pref in ('SK_', 'SN_') and tg.group(2):
                p['reglas'].append('%s: %s declara %s' % (nombre, pref, tg.group(2)))
            if pref in ('SD_', 'SP_', 'SL_', 'SE_'):
                p['reglas'].append('%s: %s no lleva etiqueta' % (nombre, pref))
    p['repetidas'] = [i for i, n in ids.items() if n > 1]
    return p


# el comprobador SABE fallar: un catalogo de ejemplo con un fallo de cada clase
EJEMPLO = {'SR_A': 'RECHAZADO: a. [CFG-07 DENIED]',             # mal formada
           'SR_B': 'RECHAZADO: b. [CFG-001 DENIED]',
           'SR_C': 'RECHAZADO: c. [CFG-001 DENIED]',            # id repetido
           'SN_D': 'nota [EDIT-001] y [EDIT-002]',              # dos, y la primera en medio
           'SR_E': 'RECHAZADO: e. [CFG-002]',                   # rechazo sin resultado
           'SN_F': 'nota. [EDIT-003 DENIED]',                   # nota que declara
           'SD_G': 'descripcion. [EDIT-004]'}                   # descripcion con etiqueta
e = problemas(EJEMPLO)
check('C0 el comprobador encuentra cada fallo plantado',
      e['malas'] == ['SR_A: [CFG-07 DENIED]'] and e['repetidas'] == ['CFG-001'] and
      e['varias'] == ['SN_D'] and e['al_medio'] == ['SN_D'] and len(e['reglas']) == 3, e)

p = problemas(C)
check('C2 todo lo que parece una etiqueta lo es', not p['malas'], p['malas'][:10])
check('C3 ningun id repetido', not p['repetidas'], p['repetidas'][:10])
check('C3b una etiqueta por mensaje como mucho', not p['varias'], p['varias'][:10])
check('C4 la etiqueta va al FINAL del mensaje', not p['al_medio'], p['al_medio'][:10])
check('C5 rechazos con resultado; notas, buenos, descripciones y log sin el', not p['reglas'], p['reglas'][:10])

# lo que falta, por prefijo: informa, no falla (se migra por areas)
for pref in ('SR_', 'SK_', 'SN_'):
    tot = [n for n in C if n.startswith(pref)]
    con = [n for n in tot if mc.ETIQUETA.search(C[n])]
    print('  info: %s etiquetados %d de %d' % (pref, len(con), len(tot)))
# las llamadas que aun no pasan por Msg/MsgFmt (David: todo mensaje por un
# helper, para poder traducirlo un dia): informa mientras se migra
import glob
NOMBRES = set(n.split('@')[0] for n in C if n[:3] in ('SR_', 'SN_', 'SK_'))
directas = 0
for f in glob.glob(os.path.join(mc.REPO, 'src', 'Server', '*.pas')) + \
        glob.glob(os.path.join(mc.REPO, 'vendor', 'src', '**', '*.pas'), recursive=True) + \
        glob.glob(os.path.join(mc.REPO, 'src', 'DesktopNode', '*.pas')) + \
        glob.glob(os.path.join(mc.REPO, 'src', 'DesktopNode', '*.dpr')) + \
        glob.glob(os.path.join(mc.REPO, 'src', 'RunJob', '*.dpr')):
    if '__' in f or f.endswith(('Lsp.Texts.pas', 'Mld.Textos.pas')):
        continue
    # sin comentarios de ningun tipo: una constante citada en uno no es un uso
    fuente = re.sub(r'\{[^}]*\}|\(\*.*?\*\)', '', open(f, encoding='utf-8-sig', errors='replace').read(),
                    flags=re.S)
    for l in fuente.splitlines():
        if l.strip().startswith('//'):
            continue
        for m in re.finditer(r'(\w+)?\(?\s*\b(S[RNK]_[A-Z0-9_]+)\b', l):
            if m.group(2) in NOMBRES and not re.search(
                    r'\b(MsgText|MsgFmt|HasMsg|MsgTag)\(\s*(\w+,\s*)?%s\b' % m.group(2), l):
                directas += 1
print('  info: usos de una constante del catalogo sin el helper MsgText/MsgFmt: %d' % directas)
fin('catalogo')
