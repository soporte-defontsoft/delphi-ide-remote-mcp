# -*- coding: utf-8 -*-
"""Round 27 - vault instructions must not send agents into the governance
wall (defontsito's field report, v0.93).

Report 20260911-232137: vault_create's description said "enlaza la nota
desde el indice que corresponda"; agents read that as MEMORY.md, and the
governance guard refuses every write to MEMORY.md - so the instruction
demanded a move the server always rejects, and the note was left created
but unlinked, with the agent filing a bug about the protocol itself.

Static coherence gate between the two texts: the CREATE instruction must
name the index agents CAN edit (the project's own notes) and forbid the one
they cannot (MEMORY.md, with the human path spelled out), and the
governance refusal must keep offering that same human path.

Usage:  python tests/test_round27.py
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))

P = F = 0


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail)[:300])


texts = open(os.path.join(REPO, 'src', 'Lsp.Texts.pas'),
             encoding='utf-8').read()


def const_body(name):
    # up to a line ENDING in '; - a semicolon inside the string must not cut
    m = re.search(re.escape(name) + r"\s*=\s*(.*?');\s*$", texts, re.S | re.M)
    if not m:
        return ''
    return ' '.join(re.findall(r"'([^']*)'", m.group(1)))


create = const_body('SD_VAULT_CREATE')
gov = const_body('SR_VAULT_GOVERNANCE')

check('SD_VAULT_CREATE existe', create != '')
check('SR_VAULT_GOVERNANCE existe', gov != '')

# the CREATE instruction: point at the editable index, forbid the wall
check('create ya no dice "el indice que corresponda" (la frase ambigua)',
      'el indice que corresponda' not in create, create)
check('create nombra las notas del proyecto como destino de los wikilinks',
      'proyecto' in create and 'context.md' in create, create)
check('create prohibe MEMORY.md explicitamente',
      'MEMORY.md' in create and 'NO' in create, create)
check('create da la via humana (respuesta o delphi_report)',
      'delphi_report' in create and 'persona' in create, create)

# the refusal: same human path, and the note is not lost work
check('governance refusal ofrece la via humana',
      'persona' in gov and 'delphi_report' in gov, gov)
check('governance refusal deja claro que la nota creada vale',
      'vale' in gov, gov)

m = re.search(r"SERVER_VERSION = '(\d+)\.(\d+)", texts)
check('SERVER_VERSION >= 0.93',
      m and (int(m.group(1)), int(m.group(2))) >= (0, 93),
      m.group(0) if m else 'sin SERVER_VERSION')

print('\n== round27 (vault index protocol): %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
