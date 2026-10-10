# -*- coding: utf-8 -*-
"""El organizador de listas de ficheros (1.15.0).

Una lista de ficheros en una respuesta va agrupada por carpeta: la carpeta UNA
vez, completa y con su unidad virtual, y debajo cada fichero por su nombre
(Lsp.Listas.TListaDeFicheros). La ruta repetida en cada entrada era el 42% de
una pagina de delphi_list, el 80% del modo dirs y el 30% de delphi_projects
(medido con el tokenizador de Qwen3.8 el 6-oct-2026); y un modelo pequeno
compone la ruta de la forma agrupada igual de bien (45/45 contra 44/45).
David: "centralizamos un organizador de respuestas para files y siempre lo
usamos" y "si paginamos, las siguientes paginas deben empezar indicando la
ruta otra vez".

  L1  delphi_list: folders = [{dir, files = [{name, size, modified}]}], cada
      carpeta UNA vez en la pagina (su ruta sale una sola vez en el texto) y
      ninguna entrada lleva ruta
  L2  ...el dir es la ruta COMPLETA con su unidad virtual: la de disco al
      deshacerla, ninguna letra real en el texto y ninguna doble mascara
  L3  una pagina se sostiene sola: la que empieza a mitad de una carpeta la
      vuelve a nombrar; recorrer las paginas da los 60 sin repetir
  L4  dirs=true: la carpeta una vez y sus subcarpetas por su nombre
  L5  __pycache__ es compilado (el de Python): el modo ficheros lo esconde y
      lo cuenta como compilacion, igual que el modo dirs; nombrado como root,
      se lista (en vivo el 6-oct-2026: pattern=* lo ensenaba entero)
  L6  delphi_search: folders > files > hits; los aciertos sin ruta y con sus
      dos numeraciones; los 60 y en sus ficheros de disco
  L7  delphi_projects: una carpeta con un .dproj y un .groupproj sale
      agrupada una vez, sin 'project' ni 'dir' por entrada (recorria por
      MASCARA y le llegaban desordenados; un paseo desde el 8.3 de la 1.18.0);
      y el repositorio git UNA vez arriba (repos = [{dir, branch}]), no repo
      y branch en cada proyecto
  L8  ...y una pagina que empieza a mitad de una carpeta (en su .groupproj)
      vuelve a nombrarla
  L9  vault_search por paginas, como su hermana delphi_search: cortaba en el
      maximo con un "(limit reached)" y lo de detras no se alcanzaba; ahora
      dice de cuantos, desde donde y la pagina siguiente, y recorrerla llega
      a todos (contenido y nombres)
  L10 __history y __recovery (las copias muertas del IDE) no salen en list
      (ficheros y dirs) ni en search, y se CUENTAN como compilacion; y
      escribir dentro se niega (GUARD-005). Ninguna bateria lo miraba (David,
      6-oct-2026: "filtramos los __history y __recovery del IDE?")

Lo de references, rename_symbol, symbols de carpeta, test discover, styles,
paserver y definition lo miden sus baterias (leen con mc.ficheros y
mc.aciertos); el sufijo [ruta del .dproj] de cada linea del build, test_round8.

Usage:  python tests/test_listas_1150.py [path-to-DelphiLspMcp.exe]
"""
import os, re, json
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('listas_1150')
JAIL = os.path.join(BASE, 'jail')
ARBOL = os.path.join(JAIL, 'Arbol')
A = os.path.join(ARBOL, 'A')
B = os.path.join(ARBOL, 'B')
C = os.path.join(ARBOL, 'C')
PYC = os.path.join(C, '__pycache__')
PROYS = os.path.join(JAIL, 'Proys')
# C\sub: el control en positivo del modo dirs (una negativa sobre una lista
# vacia no mide nada; revisor de baterias de la 1.15.0)
for d in (A, B, PYC, os.path.join(C, 'sub'), os.path.join(PROYS, 'A'), os.path.join(PROYS, 'B')):
    os.makedirs(d)
for carpeta, letra in ((A, 'A'), (B, 'B')):
    for i in range(30):
        with open(os.path.join(carpeta, 'U%s%02d.pas' % (letra, i)), 'w') as f:
            f.write('unit U%s%02d;\ninterface\nimplementation\n// marca listas\nend.\n' % (letra, i))
with open(os.path.join(C, 'c.py'), 'w') as f:
    f.write('x = 1\n')
with open(os.path.join(PYC, 'c.cpython-314.pyc'), 'wb') as f:
    f.write(b'\x00' * 16)
XML = '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"></Project>\n'
for rel in ('A\\Uno.dproj', 'A\\Grupo.groupproj', 'B\\Dos.dproj'):
    with open(os.path.join(PROYS, rel), 'w') as f:
        f.write(XML)
# L10: una carpeta con su unit viva y las copias del IDE al lado
HIST = os.path.join(JAIL, 'Hist')
for rel in ('UVivo.pas', '__history\\UVivo.pas.~1~', '__history\\UViejo.pas', '__recovery\\UVivo.pas'):
    os.makedirs(os.path.dirname(os.path.join(HIST, rel)), exist_ok=True)
    with open(os.path.join(HIST, rel), 'w') as f:
        f.write('unit UVivo;\ninterface\nimplementation\n// marca hist\nend.\n')
os.makedirs(os.path.join(HIST, 'Vivo'))  # el control en positivo de L10 dirs
# L7: Proys es un repositorio (el servidor lee .git\HEAD, no lanza git)
os.makedirs(os.path.join(PROYS, '.git'))
with open(os.path.join(PROYS, '.git', 'HEAD'), 'w') as f:
    f.write('ref: refs/heads/rama-l7\n')

# L9: un vault de 30 notas, FUERA de la jaula (dentro, las tools de ficheros
# no lo ensenan)
VAULT = os.path.join(BASE, 'vault')
os.makedirs(os.path.join(VAULT, 'notas'))
for i in range(30):
    with open(os.path.join(VAULT, 'notas', 'n%02d.md' % i), 'w', encoding='utf-8') as f:
        f.write('# Nota %d\n\nmarca del vault\n' % i)

EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_VAULT_PATH': VAULT,
                                'DELPHI_MCP_VAULT_READONLY': '1'}),
               nombre='listas_1150', respaldo_json=True)
cat = mc.catalogo()


def llama(tool, args):
    return srv.call(tool, args)


def misma(virtual_dir, disco):
    """El dir de la respuesta es ESA carpeta de disco (las dos largas: la base
    de las baterias puede venir en 8.3)."""
    return os.path.normcase(mc.larga(mc.real(virtual_dir))) == os.path.normcase(mc.larga(disco))


def dirs_de(j, campo='folders'):
    return [g.get('dir') for g in j.get(campo) or []]


def veces(raw, ruta):
    """Cuantas veces sale una ruta en el texto de la respuesta (en JSON)."""
    return raw.count(json.dumps(ruta)[1:-1])


try:
    # ---------------------------------------------------------------- L1/L2
    raw = llama('delphi_list', {'root': ARBOL})
    j = mc.como_json(raw)
    gs = j.get('folders') or []
    check('L1 delphi_list: dos carpetas (A y B), 30 ficheros cada una, total 60',
          j.get('total') == 60 and len(gs) == 2 and [len(g.get('files', [])) for g in gs] == [30, 30],
          raw[:300])
    check('L1 ...cada carpeta UNA vez: su ruta sale una sola vez en todo el texto',
          len(gs) == 2 and all(veces(raw, g['dir']) == 1 for g in gs), [veces(raw, g.get('dir', '')) for g in gs])
    entradas = [e for g in gs for e in g.get('files', [])]
    check('L1 ...y ninguna entrada lleva ruta: name, size y modified',
          bool(entradas) and all(set(e) == {'name', 'size', 'modified'} for e in entradas),
          entradas[:2])
    check('L2 el dir es la ruta COMPLETA de la carpeta, con su unidad virtual',
          len(gs) == 2 and all(g['dir'].lower().startswith('srv') for g in gs)
          and misma(gs[0]['dir'], A) and misma(gs[1]['dir'], B), dirs_de(j))
    low = re.sub('srv[a-z]:', '', raw.lower())
    check('L2 ...ninguna letra REAL en el texto y ninguna doble mascara',
          not re.findall(r'(?<![a-z])[a-z]:\\', low) and 'srvsrv' not in raw.lower(), raw[:300])
    disco = sorted(os.path.normcase(os.path.join(c, n)) for c in (A, B) for n in os.listdir(c))
    check('L2 ...y carpeta + nombre son los 60 ficheros de disco',
          sorted(os.path.normcase(mc.larga(mc.real(e['path']))) for e in mc.ficheros(j))
          == sorted(os.path.normcase(mc.larga(p)) for p in disco), len(mc.ficheros(j)))

    # ------------------------------------------------------------------- L3
    p2 = mc.como_json(llama('delphi_list', {'root': ARBOL, 'maxresults': 20, 'offset': 20}))
    g2 = p2.get('folders') or []
    check('L3 la pagina que empieza a mitad de A vuelve a nombrar A: 10 de A y 10 de B',
          len(g2) == 2 and misma(g2[0]['dir'], A) and misma(g2[1]['dir'], B)
          and [len(g['files']) for g in g2] == [10, 10] and g2[0]['files'][0]['name'] == 'UA20.pas',
          [(g.get('dir'), len(g.get('files', []))) for g in g2])
    vistos, ofs, paginas, repetidas = [], 0, 0, False
    while paginas < 10:
        pg = mc.como_json(llama('delphi_list', {'root': ARBOL, 'maxresults': 20, 'offset': ofs}))
        paginas += 1
        repetidas = repetidas or len(dirs_de(pg)) != len(set(dirs_de(pg)))
        vistos += [e['path'] for e in mc.ficheros(pg)]
        if not pg.get('hasMore'):
            break
        ofs = pg['nextOffset']
    check('L3 ...recorrer las paginas de 20 da los 60 sin repetir, y ninguna repite carpeta',
          paginas == 3 and len(vistos) == 60 and len(set(vistos)) == 60 and not repetidas,
          (paginas, len(vistos), len(set(vistos)), repetidas))

    # ------------------------------------------------------------------- L4
    jd = mc.como_json(llama('delphi_list', {'root': ARBOL, 'dirs': True}))
    gd = jd.get('folders') or []
    check('L4 dirs=true: la carpeta una vez y sus subcarpetas por su nombre',
          len(gd) == 1 and misma(gd[0]['dir'], ARBOL) and gd[0].get('dirs') == ['A', 'B', 'C'],
          jd)

    # ------------------------------------------------------------------- L5
    jc = mc.como_json(llama('delphi_list', {'root': C, 'pattern': '*'}))
    check('L5 __pycache__ en el modo ficheros: no sale, y se cuenta como compilacion',
          [e['name'] for e in mc.ficheros(jc)] == ['c.py'] and jc.get('hiddenBuildArtifacts') == 1,
          jc)
    jcd = mc.como_json(llama('delphi_list', {'root': C, 'dirs': True}))
    check('L5 ...y el modo dirs lo cuenta en el MISMO cajon (y ensena la de al lado)',
          [e['name'] for e in mc.ficheros(jcd, hijos='dirs')] == ['sub'] and jcd.get('hiddenBuildArtifacts') == 1
          and 'hiddenToolFolders' not in jcd, jcd)
    jm = mc.como_json(llama('delphi_list', {'root': C, 'pattern': '*.pyc'}))
    check('L5 ...una mascara que solo casa con lo escondido: lo cuenta (LIST-003) y NO dice que no caso',
          jm.get('total') == 0 and jm.get('hiddenBuildArtifacts') == 1
          and not mc.es(jm.get('maskNote', ''), 'SN_LIST_MASK_NO_MATCH_FMT'), jm)
    jp = mc.como_json(llama('delphi_list', {'root': PYC, 'pattern': '*'}))
    check('L5 ...nombrado como root, se lista',
          [e['name'] for e in mc.ficheros(jp)] == ['c.cpython-314.pyc'], jp)

    # ------------------------------------------------------------------- L6
    raw = llama('delphi_search', {'root': ARBOL, 'query': 'marca listas', 'maxresults': 100})
    js = mc.como_json(raw)
    gs = js.get('folders') or []
    hits = [h for g in gs for f in g.get('files', []) for h in f.get('hits', [])]
    check('L6 delphi_search: folders > files > hits, cada carpeta y cada fichero una vez',
          js.get('total') == 60 and len(gs) == 2
          and all(veces(raw, g['dir']) == 1 for g in gs)
          and all(len({f['name'] for f in g['files']}) == len(g['files']) == 30 for g in gs),
          raw[:300])
    check('L6 ...los aciertos sin ruta, con line, line0, character0 y text',
          len(hits) == 60 and all(set(h) == {'line', 'line0', 'character0', 'text'} for h in hits)
          and all(h['line'] == 4 and h['line0'] == 3 and h['character0'] == 3 for h in hits), hits[:2])
    # delphi_search es una tool de ECO: su texto no pasa por el filtro de
    # salida, asi que el dir lo enmascara el organizador o nadie (en list y
    # projects lo tapa ademas el filtro; medido con el mutante, 6-oct-2026)
    low = re.sub('srv[a-z]:', '', raw.lower())
    check('L6 ...el dir de search sale con su unidad virtual, sin letra real (lo enmascara el organizador)',
          len(gs) == 2 and all(g['dir'].lower().startswith('srv') for g in gs)
          and not re.findall(r'(?<![a-z])[a-z]:\\', low), dirs_de(js))
    ac = mc.aciertos(js)
    check('L6 ...y carpeta + fichero de cada acierto es un fichero de disco que lo contiene',
          len(ac) == 60 and all('marca listas' in open(mc.larga(mc.real(a['path']))).read() for a in ac),
          ac[:2])

    # ---------------------------------------------------------------- L7/L8
    jpr = mc.como_json(llama('delphi_projects', {'root': PROYS}))
    gp = jpr.get('projects') or []  # la lista conserva su nombre (solo files y dirs pasan a folders)
    check('L7 delphi_projects: la carpeta del .dproj y del .groupproj UNA vez, aunque le lleguen desordenados',
          len(gp) == 2 and misma(gp[0]['dir'], os.path.join(PROYS, 'A')) and misma(gp[1]['dir'], os.path.join(PROYS, 'B'))
          and [f['name'] for f in gp[0]['files']] == ['Uno.dproj', 'Grupo.groupproj']
          and [f['name'] for f in gp[1]['files']] == ['Dos.dproj'],
          [(g.get('dir'), [f.get('name') for f in g.get('files', [])]) for g in gp])
    check('L7 ...cada proyecto con su kind y sin project ni dir',
          all('kind' in f and not {'project', 'dir', 'path'} & set(f) for g in gp for f in g.get('files', [])),
          gp)
    repos = jpr.get('repos') or []
    check('L7 ...el repositorio UNA vez arriba (repos), con su rama; ni repo ni branch en cada proyecto',
          len(repos) == 1 and misma(repos[0]['dir'], PROYS) and repos[0].get('branch') == 'rama-l7'
          and bool(gp) and not any({'repo', 'branch'} & set(f) for g in gp for f in g.get('files', [])),
          (repos, gp))
    # (un paseo: Uno.dproj, Grupo.groupproj, Dos.dproj - el .groupproj es el 2o)
    jp3 = mc.como_json(llama('delphi_projects', {'root': PROYS, 'maxresults': 1, 'offset': 1}))
    g3 = jp3.get('projects') or []
    check('L8 ...la pagina que empieza en el .groupproj vuelve a nombrar su carpeta',
          len(g3) == 1 and misma(g3[0]['dir'], os.path.join(PROYS, 'A'))
          and [f['name'] for f in g3[0]['files']] == ['Grupo.groupproj'], jp3)

    # ------------------------------------------------------------------- L9
    # la pagina siguiente, leida con el texto del catalogo (no con la frase)
    SIGUIENTE = re.compile(re.escape(cat['SF_VAULT_SIGUIENTE_FMT']).replace('%d', r'(\d+)'))

    def lineas(t):
        return [l for l in t.split('\n\n', 1)[-1].splitlines() if l.strip()] if '\n\n' in t else []

    t1 = llama('vault_search', {'target': 'content', 'pattern': 'marca del vault', 'maxresults': 20})
    check('L9 vault_search por paginas: 20 de 30 desde 0, y dice la pagina siguiente (offset=20)',
          mc.abre(t1, 'SN_VAULT_RESULTADOS_FMT') and len(lineas(t1)) == 20
          and cat['SF_VAULT_PAGINA_FMT'] % (30, 0) in t1 and cat['SF_VAULT_SIGUIENTE_FMT'] % 20 in t1,
          t1[:300])
    t2 = llama('vault_search', {'target': 'content', 'pattern': 'marca del vault', 'maxresults': 20, 'offset': 20})
    check('L9 ...la siguiente: las 10 que faltan, desde 20 y sin otra pagina',
          len(lineas(t2)) == 10 and cat['SF_VAULT_PAGINA_FMT'] % (30, 20) in t2
          and not SIGUIENTE.search(t2) and not set(lineas(t1)) & set(lineas(t2)),
          t2[:300])
    t3 = llama('vault_search', {'target': 'content', 'pattern': 'marca del vault'})
    check('L9 ...si cabe en una pagina, ni de cuantos ni siguiente: las 30',
          len(lineas(t3)) == 30 and 'offset=' not in t3.split('\n', 1)[0], t3[:200])
    vistas, ofs, paginas = [], 0, 0
    while paginas < 10:
        tn = llama('vault_search', {'target': 'files', 'pattern': '*.md', 'maxresults': 7, 'offset': ofs})
        paginas += 1
        vistas += lineas(tn)
        m = SIGUIENTE.search(tn)
        if not m:
            break
        ofs = int(m.group(1))
    check('L9 ...por nombres igual: paginas de 7 llegan a las 30 notas sin repetir',
          paginas == 5 and len(vistas) == 30 and len(set(vistas)) == 30, (paginas, len(vistas)))

    # ------------------------------------------------------------------ L10
    jh = mc.como_json(llama('delphi_list', {'root': HIST, 'pattern': '*'}))
    check('L10 list: solo la unit viva; las 3 copias de __history y __recovery, contadas como compilacion',
          [e['name'] for e in mc.ficheros(jh)] == ['UVivo.pas'] and jh.get('hiddenBuildArtifacts') == 3, jh)
    jhd = mc.como_json(llama('delphi_list', {'root': HIST, 'dirs': True}))
    check('L10 ...dirs=true: ninguna de las dos, y las dos contadas (y la viva de al lado, si)',
          [e['name'] for e in mc.ficheros(jhd, hijos='dirs')] == ['Vivo'] and jhd.get('hiddenBuildArtifacts') == 2, jhd)
    jhs = mc.como_json(llama('delphi_search', {'root': HIST, 'query': 'marca hist'}))
    check('L10 ...search: el acierto de la viva y no el de las copias (contadas; la .~1~ no es Delphi)',
          [a['path'].lower().endswith('\\hist\\uvivo.pas') for a in mc.aciertos(jhs)] == [True]
          and jhs.get('hiddenBuildArtifacts') == 2, jhs)
    rw = llama('delphi_textedit', {'path': os.path.join(HIST, '__recovery', 'nota.txt'),
                                   'create': True, 'content': 'x'})
    check('L10 ...y escribir dentro se niega (GUARD-005)',
          mc.abre(rw, 'SR_GUARD_DEAD_IDE') and not os.path.exists(os.path.join(HIST, '__recovery', 'nota.txt')),
          rw[:200])
finally:
    srv.cierra()

mc.fin('listas 1.15.0 battery')
