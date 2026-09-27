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
import os, re
import mcp_cliente as mc
from mcp_cliente import check

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))


texts = open(os.path.join(REPO, 'src', 'Server', 'Lsp.Texts.pas'),
             encoding='utf-8').read()


# The two texts through THE catalog reader of the batteries: the old
# const_body joined the Pascal literals with a space, so a phrase cut
# between two of them ('the project ' + 'notes') read with a double space.
create = mc.catalogo().get('SD_VAULT_CREATE', '')
gov = mc.catalogo().get('SR_VAULT_GOVERNANCE', '')

check('SD_VAULT_CREATE existe', create != '')
check('SR_VAULT_GOVERNANCE existe', gov != '')

# the CREATE instruction: point at the editable index, forbid the wall.
# The ambiguous phrase was "enlaza la nota desde el indice que corresponda";
# in English, whatever the wording, an index that is not named.
AMBIGUA = re.compile(r'\b(corresponding|appropriate|relevant|right|proper|matching|'
                     r'applicable|suitable)\s+index\b|\bwhichever\s+index\b|'
                     r'\bindex\s+(that|which)\s+(applies|corresponds|fits)\b', re.I)
check('la negativa sabe ponerse roja: caza la frase vieja traducida',
      bool(AMBIGUA.search('link the note from the corresponding index')))
check('create ya no dice "el indice que corresponda" (la frase ambigua)',
      create != '' and not AMBIGUA.search(create), create)
check('create nombra las notas del proyecto como destino de los wikilinks',
      'project notes' in create and 'context.md' in create, create)
check('create prohibe MEMORY.md explicitamente',
      'NOT from MEMORY.md' in create, create)
check('create da la via humana (respuesta o delphi_report)',
      'delphi_report' in create and 'a person' in create, create)

# the refusal: same human path, and the note is not lost work
check('governance refusal ofrece la via humana',
      'a person' in gov and 'delphi_report' in gov, gov)
check('governance refusal deja claro que la nota creada vale',
      'you created is valid' in gov, gov)

m = re.search(r"SERVER_VERSION = '(\d+)\.(\d+)", texts)
check('SERVER_VERSION >= 0.93',
      m and (int(m.group(1)), int(m.group(2))) >= (0, 93),
      m.group(0) if m else 'sin SERVER_VERSION')

mc.fin('round27 (vault index protocol)')
