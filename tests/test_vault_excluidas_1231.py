# -*- coding: utf-8 -*-
r"""Lo que el vault no sirve, por trozos de la ruta (V127 de la 1.23.1).

VaultExcluded escondia ".bak" como SUBCADENA en cualquier sitio y backups\ a cualquier
profundidad, cuando las copias del servidor solo viven en <vault>\backups (VaultBackup, por
BACKUP_SUB) y una copia .bak lleva ".bak" como trozo del nombre (progress.md.bak-20260605 en el
vault de David; notas.bak.md en test_vault). Una nota legitima quedaba oculta a read y a search.

  E1 x.bakery.md se lee (ROJA contra b2b7024: VAULT-012)
  E2 projects/nas/backups/estrategia.md se lee (ROJA: VAULT-012)
  E3 vault_search de los nombres los lista a los dos (ROJA)
  E4 (guarda) backups/ de la RAIZ sigue excluido: VAULT-012, y search no lo lista
  E5 (guarda) una copia .bak sigue excluida: notas.bak.md, viejo.bak/nota.md, a.bak1.md
  E6 (guarda) los metadatos, a cualquier profundidad: .git, .obsidian (raiz) y .claude, .trash
     dentro de una carpeta

Uso:  python tests/test_vault_excluidas_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('vault-excluidas')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
VAULT = os.path.join(BASE, 'vault')
WORK = os.path.join(BASE, 'work')
os.makedirs(WORK)


def w(rel, texto):
    p = os.path.join(VAULT, rel.replace('/', os.sep))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'wb') as f:
        f.write(texto.encode('utf-8'))


w('AGENTS-VAULT.md', '# Reglas\n')
w('MEMORY.md', '# MEMORY\n')
w('x.bakery.md', '# Panaderia\n\nmarcaE1\n')
w('projects/nas/backups/estrategia.md', '# Estrategia de copias\n\nmarcaE2\n')
w('backups/mcp/vieja/secreto.md', '# Copia del servidor\n\nmarcaE4\n')
w('notas.bak.md', '# Copia rancia\n\nmarcaE5\n')
w('viejo.bak/nota.md', '# Carpeta copia\n\nmarcaE5\n')
w('a.bak1.md', '# Copia numerada\n\nmarcaE5\n')
w('.git/x.md', '# git\n\nmarcaE6\n')
w('.obsidian/x.md', '# obsidian\n\nmarcaE6\n')
w('projects/p/.claude/x.md', '# claude\n\nmarcaE6\n')
w('projects/p/.trash/x.md', '# trash\n\nmarcaE6\n')

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': WORK, 'DELPHI_MCP_VAULT_PATH': VAULT,
                                'DELPHI_MCP_VAULT_READONLY': '1'}), nombre='vault-excluidas', t=120)


def lee(rel):
    return srv.call('vault_read', {'path': rel})


def excluida(r):
    return mc.rechazado(r) and mc.es(r, 'SR_VAULT_ESTA_CARPETA_EXCLUIDA_BACKUPS_FMT')


try:
    r = lee('x.bakery.md')
    check('E1 x.bakery.md se lee: no es una copia .bak', 'marcaE1' in r and not mc.rechazado(r), r[:200])
    r = lee('projects/nas/backups/estrategia.md')
    check('E2 una carpeta backups que no es la de la raiz se lee', 'marcaE2' in r and not mc.rechazado(r), r[:200])
    def nombres(q):
        # target=files busca con mascara, no con subcadena
        return srv.call('vault_search', {'pattern': '*%s*' % q, 'target': 'files'})
    r = nombres('bakery') + nombres('estrategia')
    check('E3 vault_search de los nombres lista a los dos', 'x.bakery.md' in r and 'estrategia.md' in r, r[:600])
    contenido = srv.call('vault_search', {'pattern': 'marcaE', 'target': 'content'})
    check('E3 ...y el de contenido tambien', 'marcaE1' in contenido and 'marcaE2' in contenido, contenido[:600])

    check('E4 backups/ de la raiz sigue excluido', excluida(lee('backups/mcp/vieja/secreto.md')))
    r = nombres('secreto')
    check('E4 ...y search no lo lista', 'secreto.md' not in r and 'marcaE4' not in contenido, (r[:300], contenido[:300]))
    for rel in ('notas.bak.md', 'viejo.bak/nota.md', 'a.bak1.md'):
        check('E5 una copia .bak sigue excluida: %s' % rel, excluida(lee(rel)))
    r = nombres('notas') + nombres('bak1')
    check('E5 ...y search no las lista', 'marcaE5' not in contenido and 'notas.bak.md' not in r and
          'a.bak1.md' not in r, (r[:300], contenido[:400]))
    for rel in ('.git/x.md', '.obsidian/x.md', 'projects/p/.claude/x.md', 'projects/p/.trash/x.md'):
        check('E6 los metadatos, a cualquier profundidad: %s' % rel, excluida(lee(rel)))
    check('E6 ...y search no los lista', 'marcaE6' not in contenido, contenido[:400])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('vault: lo excluido por trozos de la ruta 1.23.1 (V127)')
