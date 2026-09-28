#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""The CONTRACT of every tool in docs/TOOLS.md - its live description and its
parameter table - generated from the real tools/list of the exe, between two
markers inside each "### `tool`" section; the prose around them (notes,
history, the Access line) is written by hand and stays. Run it after changing
a tool's contract, and in the release ritual next to gen-capabilities.py:

    python scripts/tools_md.py [ruta-al-DelphiLspMcp.exe]

tests/test_docs_consistency.py falla si a una tool le falta el bloque o si
alguno difiere de lo que renderiza esto. Medido el 28-sep-2026, antes: 35 de
41 descripciones y 127 parametros del TOOLS.md a mano decian otra cosa que el
servidor, 4 parametros faltaban y ninguna bateria lo veia."""
import io, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
DOC = os.path.join(REPO, 'docs', 'TOOLS.md')
MARCA_INI = ('<!-- contract: generated from tools/list by scripts/tools_md.py - '
             'change the server, not this block -->')
MARCA_FIN = '<!-- /contract -->'


def _celda(s):
    """Una celda de tabla Markdown: sin saltos y con la barra escapada."""
    return re.sub(r'\s+', ' ', (s or '')).replace('|', '\\|').strip()


def _tipo(p):
    t = p.get('type', '')
    if isinstance(t, list):
        t = ' / '.join(t)
    return t or 'any'


def render(tool):
    """El bloque de contrato de una tool (tools/list -> Markdown)."""
    schema = tool.get('inputSchema') or {}
    props = schema.get('properties') or {}
    req = schema.get('required') or []
    lines = [MARCA_INI, '', (tool.get('description') or '').replace('\r\n', '\n').strip(), '']
    if props:
        lines += ['| Parameter | Type | Required | Description |', '|---|---|---|---|']
        for name, p in props.items():
            lines.append('| `%s` | %s | %s | %s |' % (
                name, _tipo(p), '**yes**' if name in req else 'optional',
                _celda(p.get('description'))))
    else:
        lines.append('No parameters.')
    lines.append(MARCA_FIN)
    return '\n'.join(lines)


def _seccion(doc, name):
    """La seccion "### `name`" entera, hasta la siguiente cabecera ### o ##."""
    return re.search(r'^### `%s`\n.*?(?=^### |^## |\Z)' % re.escape(name), doc, re.M | re.S)


def bloque_en(doc, name):
    """El bloque de contrato que el doc tiene hoy para la tool, o None."""
    m = _seccion(doc, name)
    if not m:
        return None
    sec = m.group(0)
    i = sec.find(MARCA_INI)
    j = sec.find(MARCA_FIN)
    if i < 0 or j < 0:
        return None
    return sec[i:j + len(MARCA_FIN)]


def actualiza(doc, tools):
    """Sustituye el bloque de cada tool (o lo inserta tras su cabecera si no lo
    tiene). Devuelve (doc nuevo, tools sin seccion)."""
    sin = []
    for t in tools:
        m = _seccion(doc, t['name'])
        if not m:
            sin.append(t['name'])
            continue
        sec = m.group(0)
        nuevo = render(t)
        i = sec.find(MARCA_INI)
        j = sec.find(MARCA_FIN)
        if i >= 0 and j >= 0:
            sec2 = sec[:i] + nuevo + sec[j + len(MARCA_FIN):]
        else:
            cab = '### `%s`\n' % t['name']
            sec2 = cab + '\n' + nuevo + '\n\n' + sec[len(cab):].lstrip('\n')
        doc = doc[:m.start()] + sec2 + doc[m.end():]
    return doc, sin


if __name__ == '__main__':
    sys.path.insert(0, HERE)
    from livetools import tools_list
    version, tools = tools_list(sys.argv[1] if len(sys.argv) > 1 else None)
    doc = io.open(DOC, encoding='utf-8').read()
    nuevo, sin = actualiza(doc, tools)
    if sin:
        print('SIN SECCION en TOOLS.md (su "### `tool`" se escribe a mano):', ', '.join(sin))
    if nuevo != doc:
        io.open(DOC, 'w', encoding='utf-8', newline='\n').write(nuevo)
        print('escrito %s: %d bloques (v%s)' % (DOC, len(tools) - len(sin), version))
    else:
        print('%s ya estaba al dia: %d bloques (v%s)' % (DOC, len(tools), version))
    sys.exit(1 if sin else 0)
