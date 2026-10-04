"""E2E battery for delphi_docs (1.10.0): the RAD Studio help installed with
Delphi - the .chm files the IDE registers in Help\\HtmlHelp1Files, the ones
F1 opens - searched and read by an agent in small pieces.

  D0  the help this machine has is found: whether there is any is decided
      HERE, from the registry and the disk, not by the server (review of
      1.10.0: a DOCS-001 from a regression made the battery green with
      nothing measured)
  D1  tools/list carries delphi_docs, announced read-only; the task table
      of delphi_help names it and delphi_help tool gives it whole
  D2  search: the right page FIRST for real concepts and classes (measured
      2-oct-2026: first in the 37 tried), an inherited member included;
      limit stops at 25 when there are more
  D3  framework=fmx / vcl puts that framework's page first - also where,
      without it, the other one comes first (TScrollBox: the VCL id is
      shorter)
  D4  a class: text, the source note, its ancestors, and related with its
      member lists; a member list reads one member per line
  D5  a long page: first its introduction and its sections; <id>#<section>
      reads that section alone; walking nextOffset covers the whole page,
      nothing lost and nothing repeated - by its text, not only its lengths
      (the last section read alone is inside the chunks put together)
  D6  a topics page: its parent index is the first of related, not text
  D7  a page that only redirects answers as its destination
  D8  a section that is not there: the note says so, and the introduction
      and the sections come instead
  D9  the help text is not rewritten by the drive masker (TPath.Combine)
  D10 refusals: no query, no id, bad command, bad framework, nothing found;
      ids that are not ids (.., a drive, a leading slash, a NUL) are
      INVALID_PARAM - each a page name (.htm), so the rule it names is the
      one that refuses it -, well-formed ones that are not there NOT_FOUND
  D11 a read-only token reads the help
  D12 one search well under 2 s (measured 0.4-0.7 s)
  D13 (review of 1.10.0) a word of the index markup ('object') finds its
      pages, a quoted concept finds them, one result per page, a redirect
      keeps the section asked for
  D14 a workspace with LibraryZone off reads the help too (David,
      2-oct-2026: it asks for no switch - it opens only the help files the
      IDE registers, and LibraryZone=0 keeps the component SOURCES out)
  D15 the section it echoes goes through the drive mask: the help text is
      exempt, what the agent typed is not (a path of this server in it
      would leave with its real letter; a refusal is masked anyway)
  D16 (Hermes, 4-oct-2026) a section named by its title as the text shows
      it (spaces, another case, an anchor that is not its title with '_')
      is found and answers with its anchor; Description of an API page,
      the only title of its level, stops at its first sub-heading and says
      which follow (it ran to the end of the page: See Also, Code Examples)

Guards, not proof (green with their fix removed, measured): D1's read-only
announcement and D11 (a tool missing from the access table reads by
default), and the cut of a long page's introduction at '##' rather than '#'
(no real page tells them apart). The '..' ids of D10 were a guard until
D10 told INVALID_PARAM from NOT_FOUND: measured red in the mutation of
1.10.0. Not measured here: a help registered with an IDE macro other than
$(BDS) - every entry of this machine is an absolute path (21, measured).

Messages are recognised by their catalogue constant, never by their words.
A machine without the help installed has nothing to measure here: the
battery says so (fin with sin_checks) - only when the registry and the disk
agree that there is none (D0).

Usage:  python tests/test_delphi_docs.py [path-to-DelphiLspMcp.exe]
"""
import os, time, winreg
import mcp_cliente as mc
from mcp_cliente import check

TOKEN = 'bateria-docs'
RO_TOKEN = 'bateria-docs-ro'
SIN_ZONA = 'bateria-docs-sin-zona'

base = mc.carpeta('delphi_docs')
exe = mc.copia_exe(base)
port = mc.puerto_libre()
with open(os.path.join(base, 'settings.ini'), 'w') as f:
    # la ayuda no pide interruptor: este workspace tiene la zona de
    # biblioteca encendida y el de SIN_ZONA no, y los dos la leen (D14)
    f.write('[Server]\nBindIP=127.0.0.1\n\n[Workspace.Docs]\nToken=%s\nReadOnlyToken=%s\n'
            'Roots=%s\nLibraryZone=1\n\n[Workspace.SinZona]\nToken=%s\nRoots=%s\n'
            % (TOKEN, RO_TOKEN, base, SIN_ZONA, base))
proc = mc.lanza_http(exe, port, mc.entorno())
cli = mc.Http(port, TOKEN, t=120)
sin_ayuda = ''


def docs(args, c=None):
    return (c or cli).call('delphi_docs', args)


def ids_de(t):
    return [x['id'] for x in mc.como_json(t).get('results', [])]


def prefijo(nombre):
    """El texto fijo de una constante _FMT del catalogo, hasta su primer %."""
    return mc.catalogo()[nombre].split('%')[0]


def ayudas_en_el_disco(version):
    """Los .chm que el IDE de esa version registra (Help\\HtmlHelp1Files, del
    usuario y de la maquina) y estan en el disco, leidos AQUI y no por el
    servidor: si el servidor dice que no hay ayuda y aqui la hay, es un
    fallo, no una maquina sin nada que medir."""
    sub = r'SOFTWARE\Embarcadero\BDS\%s' % version
    raiz_bds, datos = '', []
    for raiz, vista in ((winreg.HKEY_CURRENT_USER, 0),
                        (winreg.HKEY_LOCAL_MACHINE, winreg.KEY_WOW64_32KEY),
                        (winreg.HKEY_LOCAL_MACHINE, winreg.KEY_WOW64_64KEY)):
        try:
            with winreg.OpenKey(raiz, sub, 0, winreg.KEY_READ | vista) as k:
                raiz_bds = raiz_bds or str(winreg.QueryValueEx(k, 'RootDir')[0])
        except OSError:
            pass
        try:
            with winreg.OpenKey(raiz, sub + r'\Help\HtmlHelp1Files', 0, winreg.KEY_READ | vista) as k:
                i = 0
                while True:
                    try:
                        datos.append(str(winreg.EnumValue(k, i)[1]))
                    except OSError:
                        break
                    i += 1
        except OSError:
            pass
    rutas = [d.replace('$(BDS)', raiz_bds.rstrip('\\')) for d in datos]
    return sorted({r.lower() for r in rutas if '$(' not in r and os.path.isfile(r)})


try:
    cli.session('delphi-docs')
    version = mc.como_json(cli.call('delphi_workspace', {})).get('activeDelphi', '')
    en_disco = ayudas_en_el_disco(version) if version else []
    primera = docs({'command': 'search', 'query': 'FormatDateTime'})
    if mc.abre(primera, 'SR_DOCS_SIN_AYUDA_FMT') and not en_disco:
        sin_ayuda = 'esta maquina no tiene la ayuda de RAD Studio instalada (ni en el registro ni en el disco)'
    else:
        # D0
        check('D0 la ayuda que el IDE registra se encuentra (%d en el disco, mirado sin el servidor)'
              % len(en_disco), not mc.abre(primera, 'SR_DOCS_SIN_AYUDA_FMT'), primera[:200])
        # D1
        lista = cli.request('tools/list')
        tools = {x['name']: x for x in ((lista or {}).get('result') or {}).get('tools', [])}
        t = tools.get('delphi_docs', {})
        check('D1 tools/list anuncia delphi_docs, de solo lectura',
              (t.get('annotations') or {}).get('readOnlyHint') is True
              and (t.get('_meta') or {}).get('access') == 'read-only', str(t)[:300])
        t = cli.call('delphi_help', {'command': 'tasks'})
        check('D1 la tabla de delphi_help la cita', mc.abre(t, 'SN_HELP_TASKS') and 'delphi_docs' in t,
              t[:200])
        t = mc.como_json(cli.call('delphi_help', {'command': 'tool', 'name': 'docs'}))
        check('D1 delphi_help tool name=docs la da entera', t.get('tool') == 'delphi_docs'
              and 'id' in (t.get('parameters') or {}).get('properties', {}), str(t)[:200])

        # D2
        CASOS = [
            ('FormatDateTime', 'system:System.SysUtils.FormatDateTime.htm'),
            ('TStringList.Sort', 'system:System.Classes.TStringList.Sort.htm'),
            ('TThread.Synchronize', 'system:System.Classes.TThread.Synchronize.htm'),
            ('TPath.Combine', 'system:System.IOUtils.TPath.Combine.htm'),
            ('TJSONObject', 'system:System.JSON.TJSONObject.htm'),
            ('TFDConnection', 'libraries:FireDAC.Comp.Client.TFDConnection.htm'),
            # un miembro heredado: ExecSQL es de TFDCustomQuery
            ('TFDQuery.ExecSQL', 'libraries:FireDAC.Comp.Client.TFDCustomQuery.ExecSQL.htm'),
            ('FMX.StdCtrls.TButton', 'fmx:FMX.StdCtrls.TButton.htm'),
            ('class helpers', 'topics:Class_and_Record_Helpers_(Delphi).htm'),
            ('anonymous methods', 'topics:Anonymous_Methods_in_Delphi.htm'),
            ('managed records', 'topics:Custom_Managed_Records.htm'),
        ]
        for q, esperado in CASOS:
            got = ids_de(docs({'command': 'search', 'query': q}))
            check('D2 "%s": la pagina buena, la primera' % q, got[:1] == [esperado], got[:3])
        got = ids_de(docs({'command': 'search', 'query': 'for in'}))
        check('D2 "for in": la seccion del bucle, la primera',
              bool(got) and got[0].startswith('topics:Declarations_and_Statements_(Delphi).htm#'),
              got[:3])
        if got:
            # el indice escribe ..._For_statements y la pagina ..._For_Statements
            s = mc.como_json(docs({'id': got[0]}))
            check('D2 ...y ese id lee su seccion, aunque el indice y la pagina no escriban igual el ancla',
                  s.get('text', '').startswith('#') and not mc.es(s.get('note', ''), 'SN_DOCS_SIN_SECCION_FMT'),
                  str(s)[:200])
        got = ids_de(docs({'query': 'TButton', 'limit': 3}))
        check('D2 sin command, con query: busca; limit=3 da 3 como mucho', 0 < len(got) <= 3, got)
        t = docs({'query': 'TButton', 'limit': 100})
        got = ids_de(t)
        check('D2 limit se queda en 25 (habiendo mas)',
              len(got) == 25 and mc.como_json(t).get('total', 0) > 25,
              (len(got), mc.como_json(t).get('total')))

        # D3
        fmx = ids_de(docs({'query': 'TButton', 'framework': 'fmx'}))
        vcl = ids_de(docs({'query': 'TButton', 'framework': 'VCL'}))
        check('D3 framework=fmx: la de FMX primero', fmx[:1] == ['fmx:FMX.StdCtrls.TButton.htm'], fmx[:3])
        check('D3 framework=VCL (sin mirar mayusculas): la de VCL primero',
              vcl[:1] == ['vcl:Vcl.StdCtrls.TButton.htm'], vcl[:3])
        # sin framework, la de VCL va antes que la de FMX (su id es mas corto):
        # aqui el de fmx tiene que hacer algo (con TButton FMX ya iba antes)
        sin = ids_de(docs({'query': 'TScrollBox', 'limit': 5}))
        fmx = ids_de(docs({'query': 'TScrollBox', 'framework': 'fmx', 'limit': 5}))
        check('D3 framework=fmx: la de FMX primero, tambien donde sin el va la de VCL antes',
              fmx[:1] == ['fmx:FMX.Layouts.TScrollBox.htm']
              and sin.index('vcl:Vcl.Forms.TScrollBox.htm') < sin.index('fmx:FMX.Layouts.TScrollBox.htm'),
              (sin, fmx[:2]))

        # D4
        r = mc.como_json(docs({'id': 'vcl:Vcl.StdCtrls.TButton.htm'}))
        texto = r.get('text', '')
        rel = [x['id'] for x in r.get('related', [])]
        check('D4 sin command, con id: lee; la nota dice de donde sale',
              mc.es(r.get('note', ''), 'SN_DOCS_FUENTE_FMT'), r.get('note', '')[:200])
        check('D4 los antepasados de la clase, el mas cercano primero',
              (prefijo('SF_DOCS_ANCESTROS_FMT') + 'Vcl.StdCtrls.TCustomButton') in texto, texto[:200])
        check('D4 related: sus listas de miembros',
              all('vcl:Vcl.StdCtrls.TButton_%s.htm' % k in rel for k in ('Methods', 'Properties', 'Events')),
              rel)
        ev = mc.como_json(docs({'id': 'vcl:Vcl.StdCtrls.TButton_Events.htm'})).get('text', '')
        lineas = [l for l in ev.splitlines() if l.strip()]
        check('D4 una lista de miembros: un miembro por linea, desde la primera',
              bool(lineas) and ' | ' in lineas[0] and any(l.startswith('OnClick |') for l in lineas),
              lineas[:3])

        # D5
        LARGA = 'topics:Declarations_and_Statements_(Delphi).htm'
        r = mc.como_json(docs({'id': LARGA}))
        secciones = r.get('sections', [])
        total = r.get('length', 0)
        check('D5 una pagina larga: primero su entrada, corta, y sus secciones',
              len(secciones) > 10 and 0 < len(r.get('text', '')) < 2000 and r.get('nextOffset'),
              {k: r.get(k) for k in ('length', 'nextOffset')})
        check('D5 la nota dice por donde sigue', mc.es(r.get('note', ''), 'SN_DOCS_SIGUE_FMT'),
              r.get('note', '')[-200:])
        if secciones:
            s = mc.como_json(docs({'id': LARGA + '#' + secciones[0]}))
            check('D5 <id>#<seccion> da esa seccion sola, con su titulo',
                  s.get('text', '').startswith('#') and 0 < s.get('length', 0) < total
                  and 'sections' not in s, str(s)[:200])
        trozos, offset, vueltas = [], 0, 0
        while offset is not None and vueltas < 50:
            p = mc.como_json(docs({'id': LARGA, 'offset': offset}))
            trozos.append((p.get('offset', 0), p.get('text', '')))
            offset = p.get('nextOffset')
            vueltas += 1
        seguidos = all(trozos[k + 1][0] == trozos[k][0] + len(trozos[k][1]) for k in range(len(trozos) - 1))
        check('D5 siguiendo nextOffset se lee la pagina entera, sin perder ni repetir',
              seguidos and sum(len(x[1]) for x in trozos) == total and len(trozos) > 2,
              [(o, len(x)) for o, x in trozos])
        check('D5 ningun trozo pasa de 8.000 caracteres', all(len(x[1]) <= 8000 for x in trozos),
              max(len(x[1]) for x in trozos))
        # ...y por su TEXTO, no solo por sus largos: un Lee que no mirara el
        # offset daba largos y offsets coherentes con el mismo trozo repetido
        if secciones:
            ultima = mc.como_json(docs({'id': LARGA + '#' + secciones[-1]})).get('text', '')
            check('D5 la ultima seccion, leida sola, esta en los trozos juntos (y no en el primero)',
                  bool(ultima) and ultima in ''.join(x[1] for x in trozos) and ultima not in trozos[0][1],
                  ultima[:120])
        p = mc.como_json(docs({'id': LARGA, 'offset': 10 ** 7}))
        check('D5 un offset pasado el final: vacio, sin error', p.get('text') == '' and 'nextOffset' not in p,
              str(p)[:200])

        # D6
        rel = r.get('related', [])
        check('D6 una pagina de temas: su indice padre, el primero de related',
              bool(rel) and rel[0]['id'] == 'topics:Fundamental_Syntactic_Elements_Index.htm', rel[:2])
        check('D6 ...y no en el texto', bool(rel) and rel[0]['title'] not in r.get('text', ''),
              r.get('text', '')[:200])

        # D7
        r = mc.como_json(docs({'id': 'topics:FormatDateTime.htm'}))
        check('D7 la que solo redirige contesta como su destino',
              r.get('id') == 'system:System.SysUtils.FormatDateTime.htm', r.get('id'))

        # D8
        r = mc.como_json(docs({'id': 'topics:Anonymous_Methods_in_Delphi.htm#NoSuchSection'}))
        check('D8 una seccion que no esta: la nota lo dice',
              mc.es(r.get('note', ''), 'SN_DOCS_SIN_SECCION_FMT'), r.get('note', '')[:200])
        check('D8 ...y llegan la entrada y las secciones para elegir',
              len(r.get('sections', [])) > 5 and len(r.get('text', '')) < 2000, str(r)[:200])

        # D9
        r = mc.como_json(docs({'id': 'system:System.IOUtils.TPath.Combine.htm#Examples'}))
        texto = r.get('text', '')
        check('D9 los ejemplos de la ayuda llegan tal cual: sin unidades virtuales',
              "'E:\\somewhere\\'" in texto and "'C:\\there\\file.txt'" in texto
              and "'\\there\\file.txt'" in texto and 'srv' not in texto, texto[:300])

        # D10
        for args, nombre in (({'command': 'search'}, 'SR_DOCS_SIN_CONSULTA'),
                             ({'command': 'read'}, 'SR_DOCS_SIN_ID'),
                             ({'command': 'borra', 'query': 'x'}, 'SR_DOCS_CMD'),
                             ({'query': 'TButton', 'framework': 'clx'}, 'SR_DOCS_FRAMEWORK_FMT'),
                             ({'query': 'zzqqxx inexistente'}, 'SR_DOCS_NADA_FMT')):
            t = docs(args)
            check('D10 %s -> %s' % (args, nombre), mc.abre(t, nombre), t[:160])
        # todos con nombre de pagina (.htm): cada uno lo niega la regla que
        # nombra, no la de la extension
        for malo in ('system:../x.htm', 'system:..\\..\\x.htm', 'system:a/../../x.htm',
                     'system:C:\\Windows\\x.htm', 'C:\\Windows\\x.htm',
                     'system:/System.SysUtils.htm', 'system:index.hhk\x00.htm', 'nada.htm'):
            t = docs({'command': 'read', 'id': malo})
            check('D10 id %r -> no es un id (INVALID_PARAM)' % malo, mc.abre(t, 'SR_DOCS_ID_MAL_FMT'), t[:160])
        for falta in ('nada:X.htm', 'system:NoExiste.htm'):
            t = docs({'command': 'read', 'id': falta})
            check('D10 id %s -> bien formado, no esta (NOT_FOUND)' % falta,
                  mc.abre(t, 'SR_DOCS_NO_PAGINA_FMT'), t[:160])

        # D11
        ro = mc.Http(port, RO_TOKEN, t=120)
        ro.session('delphi-docs-ro')
        got = ids_de(docs({'query': 'FormatDateTime'}, ro))
        check('D11 un token de solo lectura busca', got[:1] == ['system:System.SysUtils.FormatDateTime.htm'], got[:2])
        t = docs({'id': 'system:System.SysUtils.FormatDateTime.htm'}, ro)
        check('D11 ...y lee', not mc.fallo(t) and 'text' in mc.como_json(t), t[:160])

        # D12
        t0 = time.time()
        t = docs({'query': 'TStringList'})
        dt = time.time() - t0
        check('D12 una busqueda que encuentra, muy por debajo de 2 s',
              dt < 2.0 and bool(ids_de(t)), '%.2f s %s' % (dt, t[:100]))

        # D13 (revision de la 1.10.0)
        got = ids_de(docs({'query': 'object', 'limit': 5}))
        check('D13 una palabra de las etiquetas del indice encuentra sus paginas',
              'topics:Object.htm' in got, got)
        got = ids_de(docs({'query': '"class helpers"'}))
        check('D13 un concepto entre comillas, como lo escribe la descripcion',
              got[:1] == ['topics:Class_and_Record_Helpers_(Delphi).htm'], got[:2])
        got = ids_de(docs({'query': 'objects', 'limit': 10}))
        paginas = [g.split('#')[0].lower() for g in got]
        check('D13 una pagina, una vez (sus anclas no ocupan mas puestos)',
              len(paginas) == len(set(paginas)) and len(got) > 3, got)
        r = mc.como_json(docs({'id': 'topics:FormatDateTime.htm#Description'}))
        check('D13 la que redirige conserva la seccion pedida',
              r.get('id') == 'system:System.SysUtils.FormatDateTime.htm#Description'
              and r.get('text', '').startswith('## Description'), str(r)[:200])

        # D14
        sz = mc.Http(port, SIN_ZONA, t=120)
        sz.session('delphi-docs-sin-zona')
        got = ids_de(docs({'query': 'FormatDateTime'}, sz))
        check('D14 un workspace con la zona de biblioteca apagada tambien lee la ayuda',
              got[:1] == ['system:System.SysUtils.FormatDateTime.htm'], got[:2])

        # D15: la carpeta de la bateria esta en una unidad servida (la suya)
        letra = os.path.splitdrive(base)[0][:1].upper()
        r = mc.como_json(docs({'id': 'system:System.SysUtils.FormatDateTime.htm#%s:\\Windows' % letra}))
        check('D15 la seccion que devuelve (id y nota) va con la unidad virtual, no con la letra real',
              str(r.get('id', '')).endswith('srv%s:\\Windows' % letra.lower())
              and '%s:\\Windows' % letra not in str(r.get('id', '')) + str(r.get('note', '')),
              str(r)[:300])

        # D16 (Hermes, 4-oct-2026)
        r = mc.como_json(docs({'id': 'topics:Class_and_Record_Helpers_(Delphi).htm#Helper Syntax'}))
        check('D16 #<titulo como se lee> (con espacios): esa seccion, y el id con su ancla',
              r.get('id') == 'topics:Class_and_Record_Helpers_(Delphi).htm#Helper_Syntax'
              and r.get('text', '').startswith('## Helper Syntax')
              and 'Using Helpers' not in r.get('text', '')
              and not mc.es(r.get('note', ''), 'SN_DOCS_SIN_SECCION_FMT'), str(r)[:300])
        r = mc.como_json(docs({'id': 'system:System.DynamicArray.htm#assigning, comparing and copying dynamic arrays'}))
        check('D16 un ancla que no es su titulo con _ (.2C por la coma), en minusculas',
              r.get('id') == 'system:System.DynamicArray.htm#Assigning.2C_comparing_and_copying_dynamic_arrays'
              and r.get('text', '').startswith('### Assigning, comparing and copying'), str(r)[:300])
        r = mc.como_json(docs({'id': 'system:System.SysUtils.FormatDateTime.htm#Description'}))
        texto = r.get('text', '')
        check('D16 Description de la API acaba en su primer subtitulo y dice los que siguen',
              texto.startswith('## Description') and 'See Also' not in texto and 'Code Examples' not in texto
              and 'nn |' in texto and r.get('subsections') == ['See_Also', 'Code_Examples']
              and mc.es(r.get('note', ''), 'SN_DOCS_SUBSECCIONES'), str(r)[-400:])
        r = mc.como_json(docs({'id': 'system:System.SysUtils.FormatDateTime.htm#See Also'}))
        check('D16 ...y cada una se lee por su titulo',
              r.get('text', '').startswith('### See Also') and 'subsections' not in r, str(r)[:300])
        r = mc.como_json(docs({'id': 'topics:Anonymous_Methods_in_Delphi.htm#Anonymous_Methods_Variable_Binding'}))
        check('D16 una de temas con otras de su nivel lleva dentro las suyas, como antes',
              '### Variable Binding Mechanism' in r.get('text', '') and 'subsections' not in r
              and '## Utility of Anonymous Methods' not in r.get('text', ''), str(r)[:300])
finally:
    proc.kill()

mc.fin('delphi-docs battery', sin_checks=sin_ayuda or None)
