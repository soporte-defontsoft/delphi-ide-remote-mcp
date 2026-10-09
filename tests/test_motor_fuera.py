# -*- coding: utf-8 -*-
"""Lo que el MOTOR dice de fuera de las raices (P2 de las puertas, 1.18.0).

DelphiLSP lee por el search path del proyecto lo que ninguna tool deja leer:
medido el 9-oct-2026 contra el motor en crudo, completion daba el nombre Y EL
VALOR de una constante de una unit de fuera, hover su firma y su ruta,
signature la firma entera y definition la ruta; y una variable declarada
DENTRO con un tipo de fuera listaba en `G.` los miembros de fuera en un
fichero que ni usa esa unit (los elementos de completion no dicen de donde
vienen: label, kind, detail, sortText). David: "recortar y negar",
coherente con LSP-014 de references:

  F1-F4  un proyecto cuyo search path apunta FUERA de la raiz: definition,
         hover, completion y signature no sueltan nada de alli (los ajustes
         del motor ya no llevan esa carpeta), y lo dicen (LSP-037)
  F3b    el caso que tumbo el tool a tool: G declarada DENTRO con un tipo de
         fuera, y `G.` en un fichero que NO usa la unit de fuera (los
         elementos de completion no dicen de donde vienen)
  F5     diagnostics lo dice tambien (por eso la unit no se encuentra)
  F6     el MISMO proyecto con un .delphilsp.json del IDE al lado que nombra
         esa carpeta: no se toma (se fabrica el recortado)
  F7     un proyecto cuyo .dpr nombra una unit de fuera con ruta (in '...'):
         definition y hover se niegan por la ubicacion (LSP-038), completion
         y signature por el proyecto (LSP-039)
         y references por la definicion de fuera (LSP-014); F7b, con una
         entrada del .dpr que no se deja juzgar, LSP-039 sigue saltando
  F8     controles, con la zona de biblioteca APAGADA: un simbolo de dentro y
         uno de la RTL siguen contestando (el IDE no es "fuera"); F8b, una unit
         de la Library Path fuera de la instalacion; F8c, kind=declaration de
         una rutina de la RTL (lo que abre el motor, con los lugares del motor);
         F8d, references de esa rutina (el juez de "fuera" es el de LSP-038)

Mutantes: los ajustes sin recortar (F1-F5 rojos), los del IDE tomados
igual (F6), sin la negativa por ubicacion o por proyecto (F7), sin la zona
de biblioteca en los lugares del IDE para leer (F8, hover de Length), AbreEn con
la jaula (F8c), references juzgando con la jaula (F8d: el binario de antes lo
negaba con LSP-014). RoutineIdentCol leyendo por la jaula es GUARDA: con la columna 0
el motor da la misma declaracion (medido con IntToStr y con TStringList.Add).

Uso:  python tests/test_motor_fuera.py [exe]
"""
import os, re, json, time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('motorfuera')
RAIZ = os.path.join(BASE, 'raiz')
FUERA = os.path.join(BASE, 'fuera')        # junto a la raiz, NO dentro
for d in (RAIZ, FUERA):
    os.makedirs(d, exist_ok=True)


def escribe(ruta, texto):
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    with open(ruta, 'w', encoding='ascii', newline='') as f:
        f.write(texto.replace('\n', '\r\n'))


escribe(os.path.join(FUERA, 'UFuera.pas'),
        "unit UFuera;\ninterface\nconst\n  SECRETO_DE_FUERA = 'texto que no deberia salir';\n"
        "function DesdeFuera(A: Integer; const B: string): Integer;\ntype\n  TFuera = class\n"
        "    ValorDeFuera: Integer;\n    procedure MetodoDeFuera(X: Integer);\n  end;\nimplementation\n"
        "function DesdeFuera(A: Integer; const B: string): Integer;\nbegin\n  Result := 42;\nend;\n"
        "procedure TFuera.MetodoDeFuera(X: Integer);\nbegin\nend;\nend.\n")
escribe(os.path.join(FUERA, 'UFuera2.pas'),
        "unit UFuera2;\ninterface\nconst\n  OTRO_SECRETO = 'tampoco deberia salir';\n"
        "function DesdeFuera2(A: Integer): Integer;\nimplementation\n"
        "function DesdeFuera2(A: Integer): Integer;\nbegin\n  Result := A;\nend;\nend.\n")

DPROJ = """<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <ProjectGuid>{%(guid)s}</ProjectGuid>
    <ProjectVersion>20.3</ProjectVersion>
    <FrameworkType>None</FrameworkType>
    <MainSource>%(nombre)s.dpr</MainSource>
    <Base>True</Base>
    <Config Condition="'$(Config)'==''">Debug</Config>
    <Platform Condition="'$(Platform)'==''">Win32</Platform>
    <TargetedPlatforms>1</TargetedPlatforms>
    <AppType>Console</AppType>
  </PropertyGroup>
  <PropertyGroup Condition="'$(Config)'=='Base' or '$(Base)'!=''">
    <Base>true</Base>
  </PropertyGroup>
  <PropertyGroup Condition="'$(Base)'!=''">
    <DCC_UnitSearchPath>%(busqueda)s$(DCC_UnitSearchPath)</DCC_UnitSearchPath>
    <DCC_Namespace>System;Winapi;$(DCC_Namespace)</DCC_Namespace>
  </PropertyGroup>
  <ItemGroup>
    <DelphiCompile Include="$(MainSource)"><MainSource>MainSource</MainSource></DelphiCompile>
    %(refs)s
    <BuildConfiguration Include="Base"><Key>Base</Key></BuildConfiguration>
    <BuildConfiguration Include="Debug"><Key>Cfg_1</Key><CfgParent>Base</CfgParent></BuildConfiguration>
  </ItemGroup>
  <ProjectExtensions>
    <Borland.Personality>Delphi.Personality.12</Borland.Personality>
    <Borland.ProjectType>Application</Borland.ProjectType>
    <BorlandProject><Delphi.Personality><Source><Source Name="MainSource">%(nombre)s.dpr</Source></Source></Delphi.Personality>
    <Platforms><Platform value="Win32">True</Platform></Platforms></BorlandProject>
  </ProjectExtensions>
  <Import Project="$(BDS)\\Bin\\CodeGear.Delphi.Targets" Condition="Exists('$(BDS)\\Bin\\CodeGear.Delphi.Targets')"/>
</Project>
"""
# la linea 9 (0-based 8) llama a DesdeFuera; la 10 empieza a escribir "Des"
UDENTRO = ("unit UDentro;\ninterface\nuses System.SysUtils, UFuera;\nfunction Usa: Integer;\n"
           "implementation\nfunction Usa: Integer;\nbegin\n  Result := Length('x');\n"
           "  Result := DesdeFuera(1, SECRETO_DE_FUERA);\n  Des\nend;\nend.\n")


def proyecto(nombre, guid, busqueda, unidad, texto, dpr_uses, refs):
    p = os.path.join(RAIZ, nombre)
    escribe(os.path.join(p, unidad + '.pas'), texto)
    escribe(os.path.join(p, nombre + '.dpr'),
            "program %s;\n{$APPTYPE CONSOLE}\nuses\n%s;\nbegin\nend.\n" % (nombre, dpr_uses))
    escribe(os.path.join(p, nombre + '.dproj'),
            DPROJ % {'guid': guid, 'nombre': nombre, 'busqueda': busqueda, 'refs': refs})
    return p


P1 = proyecto('Proy', '11111111-2222-3333-4444-555555555501', '..\\..\\fuera;', 'UDentro', UDENTRO,
              "  UDentro in 'UDentro.pas'", '<DCCReference Include="UDentro.pas"/>')
# el mismo, con los ajustes del IDE al lado nombrando la carpeta de fuera
P3 = proyecto('ProyIde', '11111111-2222-3333-4444-555555555503', '..\\..\\fuera;', 'UDentro', UDENTRO,
              "  UDentro in 'UDentro.pas'", '<DCCReference Include="UDentro.pas"/>')
# el .dpr nombra la unit de fuera con ruta; el search path, limpio
UDENTRO2 = ("unit UDentro2;\ninterface\nuses UFuera2;\nfunction Usa2: Integer;\nimplementation\n"
            "function Usa2: Integer;\nbegin\n  Result := DesdeFuera2(1);\n  Des\nend;\nend.\n")
P2 = proyecto('Proy2', '11111111-2222-3333-4444-555555555502', '', 'UDentro2', UDENTRO2,
              "  UFuera2 in '..\\..\\fuera\\UFuera2.pas',\n  UDentro2 in 'UDentro2.pas'",
              '<DCCReference Include="..\\..\\fuera\\UFuera2.pas"/>\n    <DCCReference Include="UDentro2.pas"/>')
# F7b: el mismo, con una entrada del .dpr cuya ruta no se deja juzgar ('|' no vale en
# una ruta): un solo try para toda la lista la vaciaba y LSP-039 no saltaba por
# UFuera2 (revisor de P2a, PA-M1)
UDENTRO4 = UDENTRO2.replace('UDentro2', 'UDentro4').replace('Usa2', 'Usa4')
P4 = proyecto('Proy4', '11111111-2222-3333-4444-555555555504', '', 'UDentro4', UDENTRO4,
              "  UMala in 'a|b.pas',\n  UFuera2 in '..\\..\\fuera\\UFuera2.pas',\n  UDentro4 in 'UDentro4.pas'",
              '<DCCReference Include="..\\..\\fuera\\UFuera2.pas"/>\n    <DCCReference Include="UDentro4.pas"/>')

EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
# la zona de biblioteca APAGADA: la RTL no es de la jaula, y aun asi el motor
# tiene que poder hablar de ella (F8)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': RAIZ, 'DELPHI_MCP_LIBRARY_ZONE': '0'}),
               nombre='motorfuera', t=240)
call = srv.call

cfgs_ide = os.path.join(P3, 'ProyIde.delphilsp.json')


def uri(path):
    return 'file:///' + path.replace('\\', '/').replace(':', '%3A')


def motor(tool, args, tope=180):
    """La llamada, repetida mientras el motor diga que aun indexa (LSP-025)."""
    t0, r = time.time(), ''
    while time.time() - t0 < tope:
        r = call(tool, args, t=120) or ''
        if not mc.tiene(r, 'LSP-025'):
            return r
        time.sleep(3)
    return r


FUGAS = ('UFuera.pas', 'UFuera2.pas', 'texto que no deberia salir', 'tampoco deberia salir',
         'DesdeFuera(A', 'DesdeFuera2(A', 'UFuera.DesdeFuera', 'UFuera2.DesdeFuera2',
         'ValorDeFuera', 'MetodoDeFuera')

# F3b: G declarada DENTRO (UDentroG usa UFuera) y `G.` en UUsaG, que solo usa UDentroG
escribe(os.path.join(P1, 'UDentroG.pas'),
        "unit UDentroG;\ninterface\nuses UFuera;\nvar\n  G: TFuera;\nimplementation\nend.\n")
UG = os.path.join(P1, 'UUsaG.pas')
escribe(UG, "unit UUsaG;\ninterface\nuses UDentroG;\nimplementation\nprocedure P;\nbegin\n  G.\nend;\nend.\n")


def fugas(r):
    return [f for f in FUGAS if f in (r or '')]


try:
    U1 = os.path.join(P1, 'UDentro.pas')
    # F8 primero (calienta el motor): lo de dentro y la RTL contestan
    r = motor('delphi_definition', {'path': U1, 'line': 5, 'character': 10})
    check('F8 definition de un simbolo de DENTRO: contesta con su ruta',
          'UDentro.pas' in r and not mc.tiene(r, 'LSP-038'), r[:300])
    r = motor('delphi_hover', {'path': U1, 'line': 7, 'character': 13})
    check('F8 hover de Length (la RTL, zona de biblioteca APAGADA): contesta su firma',
          'Length' in r and not mc.tiene(r, 'LSP-038'), r[:300])

    r = motor('delphi_definition', {'path': U1, 'line': 8, 'character': 14})
    check('F1 definition de un simbolo de una unit del search path de FUERA: nada de alli, y la nota LSP-037',
          not fugas(r) and mc.tiene(r, 'LSP-037'), (fugas(r), r[:300]))
    r = motor('delphi_hover', {'path': U1, 'line': 8, 'character': 14})
    check('F2 hover: ni su firma ni su ruta', not fugas(r), (fugas(r), r[:300]))
    r = motor('delphi_completion', {'path': U1, 'line': 9, 'character': 5})
    check('F3 completion: ni sus nombres ni el VALOR de su constante',
          not fugas(r) and 'SECRETO_DE_FUERA' not in r and '"DesdeFuera"' not in r, (fugas(r), r[:400]))
    r = motor('delphi_signature', {'path': U1, 'line': 8, 'character': 23})
    check('F4 signature: ni su firma', not fugas(r), (fugas(r), r[:300]))
    r = motor('delphi_completion', {'path': UG, 'line': 6, 'character': 4, 'trigger': '.'})
    check('F3b completion de `G.` (G de dentro, tipo de fuera, el fichero no usa la unit): ni un miembro de fuera',
          not fugas(r), (fugas(r), r[:300]))
    r = call('delphi_diagnostics', {'path': U1}, t=120) or ''
    for _ in range(20):
        if not mc.tiene(r, 'LSP-024') and 'in progress' not in r:
            break
        time.sleep(3)
        r = call('delphi_diagnostics', {'path': U1}, t=120) or ''
    check('F5 diagnostics: dice por que esa unit no se encuentra (LSP-037)',
          mc.tiene(r, 'LSP-037') and not fugas(r), r[:400])

    # F8b: una unit de la Library Search Path FUERA de la instalacion (componentes,
    # GetIt), con la zona APAGADA: el motor puede hablar de ella (ltBiblioteca: la
    # instalacion ya es del IDE y no mide esto). Sus carpetas, las de los ajustes
    # que el servidor fabrico para P1; la instalacion, la de sus fuentes
    cdir = mc.cache_servidor('configs')
    fab = sorted((f for f in os.listdir(cdir) if f.startswith('Proy-')),
                 key=lambda f: os.path.getmtime(os.path.join(cdir, f)))
    st = json.load(open(os.path.join(cdir, fab[-1]), encoding='utf-8-sig'))['settings']
    from urllib.parse import unquote
    rutas = [unquote(u[len('file:///'):]).replace('/', '\\') for u in st['browsingPaths']]
    inst = rutas[0].split('\\source\\')[0] + '\\'
    unidad = ''
    for d in rutas:
        if d.lower().startswith(inst.lower()) or not os.path.isdir(d):
            continue
        pas = sorted(f for f in os.listdir(d) if f.lower().endswith('.pas'))
        if pas:
            unidad = os.path.splitext(pas[0])[0]
            break
    if unidad:
        UB = os.path.join(P1, 'UBib.pas')
        escribe(UB, 'unit UBib;\ninterface\nuses %s;\nimplementation\nend.\n' % unidad)
        r = motor('delphi_definition', {'path': UB, 'line': 2, 'character': 6})
        check('F8b definition de una unit de la Library Search Path fuera de la instalacion (zona APAGADA): contesta',
              (unidad + '.pas').lower() in r.lower() and not mc.tiene(r, 'LSP-038'), (unidad, r[:300]))
    else:
        print('NOTA: F8b no se mide: esta maquina no tiene carpetas de la Library Search Path '
              'fuera de la instalacion')

    # F8c: kind=declaration de una rutina de la RTL (zona APAGADA): la cadena abre el
    # destino en el motor (AbreEn) y lo lee (RoutineIdentCol) con los lugares del
    # MOTOR, no con la jaula - contestaba GUARD-002 (tambien antes de P2) mientras
    # definition daba esa misma ubicacion
    UD = os.path.join(P1, 'UDecl.pas')
    escribe(UD, "unit UDecl;\ninterface\nuses System.SysUtils;\nfunction F: string;\nimplementation\n"
                "function F: string;\nbegin\n  Result := IntToStr(1);\nend;\nend.\n")
    rdef = motor('delphi_definition', {'path': UD, 'line': 7, 'character': 14})
    rdec = motor('delphi_definition', {'path': UD, 'line': 7, 'character': 14, 'kind': 'declaration'})
    # (la respuesta de P1 lleva detras la nota LSP-037: se leen la ruta y la linea
    # del texto, no de un JSON limpio)
    def sitio(r):
        m = re.search(r'"path":"([^"]*)","line":\d+,"line0":(\d+)', r or '')
        return (m.group(1), int(m.group(2))) if m else ('', -1)
    (pdef, ldef), (pdec, ldec) = sitio(rdef), sitio(rdec)
    check('F8c definition kind=declaration de una rutina de la RTL (zona APAGADA): la de la interface, '
          'antes que su cuerpo (no GUARD-002)',
          pdec.endswith('System.SysUtils.pas') and pdec == pdef and 0 <= ldec < ldef,
          (ldef, ldec, rdef[:150], rdec[:300]))
    # F8d: references de esa misma rutina de la RTL (zona APAGADA): sus usos de
    # DENTRO, no LSP-014 ("fuera" es lo que el motor no puede ensenar: el IDE no lo es)
    t0 = time.time()
    while True:
        r = call('delphi_references', {'path': UD, 'line': 7, 'character': 14}, t=120) or ''
        if not (mc.tiene(r, 'LSP-025') or mc.es(r, 'SR_REFS_WARMING_FMT')) or time.time() - t0 > 180:
            break
        time.sleep(3)
    check('F8d references de una rutina de la RTL (zona APAGADA): su uso de dentro, no LSP-014',
          not mc.tiene(r, 'LSP-014') and 'UDecl.pas' in r, r[:300])

    # F6: unos ajustes "del IDE" al lado, que FUNCIONAN y nombran la carpeta de
    # fuera: los que el servidor fabrico para P1 (de su cache), con ese proyecto
    # y esa carpeta anadida. Unos minimos (sin los prefijos ni la RTL) no
    # compilaban nada y F6 pasaba aunque se tomasen (su mutante lo midio)
    ide = json.load(open(os.path.join(cdir, fab[-1]), encoding='utf-8-sig'))
    st = ide['settings']
    st['project'] = uri(os.path.join(P3, 'ProyIde.dpr'))
    st['dccOptions'] = st['dccOptions'].replace('-U"', '-U"%s;' % FUERA, 1)
    st['browsingPaths'] = st['browsingPaths'] + [uri(FUERA)]
    with open(cfgs_ide, 'w', encoding='utf-8') as f:
        json.dump(ide, f)
    U3 = os.path.join(P3, 'UDentro.pas')
    r1 = motor('delphi_hover', {'path': U3, 'line': 8, 'character': 14})
    r2 = motor('delphi_completion', {'path': U3, 'line': 9, 'character': 5})
    check('F6 con un .delphilsp.json del IDE que nombra la carpeta de fuera: no se toma (ni hover ni completion sueltan nada)',
          not fugas(r1) and not fugas(r2) and 'SECRETO_DE_FUERA' not in r2, (fugas(r1), fugas(r2), r1[:200]))

    U2 = os.path.join(P2, 'UDentro2.pas')
    r = motor('delphi_definition', {'path': U2, 'line': 7, 'character': 14})
    check('F7 definition de un simbolo de una unit que el .dpr nombra FUERA: LSP-038, sin su ruta',
          mc.tiene(r, 'LSP-038') and not fugas(r), r[:300])
    r = motor('delphi_hover', {'path': U2, 'line': 7, 'character': 14})
    check('F7 hover: LSP-038', mc.tiene(r, 'LSP-038') and not fugas(r), r[:300])
    r = motor('delphi_completion', {'path': U2, 'line': 8, 'character': 5})
    check('F7 completion: LSP-039 (nombra la unit, que esta en el .dpr del agente)',
          mc.tiene(r, 'LSP-039') and 'UFuera2' in r and not fugas(r), r[:300])
    r = motor('delphi_signature', {'path': U2, 'line': 7, 'character': 24})
    check('F7 signature: LSP-039', mc.tiene(r, 'LSP-039') and not fugas(r), r[:300])
    r = motor('delphi_completion', {'path': os.path.join(P4, 'UDentro4.pas'), 'line': 8, 'character': 5})
    check('F7b completion con una entrada del .dpr que no se deja juzgar: LSP-039 igual (nombra UFuera2)',
          mc.tiene(r, 'LSP-039') and 'UFuera2' in r and not fugas(r), r[:300])
    r = motor('delphi_references', {'path': U2, 'line': 7, 'character': 14})
    # (lo niega LSP-014 antes de leer: la puerta de LoadSourceText, que no dejaria
    # leer el fichero de la definicion, es aqui una GUARDA)
    check('F7 references: LSP-014, sin nada de la unit de fuera', mc.tiene(r, 'LSP-014') and not fugas(r), r[:300])
finally:
    srv.mata()

mc.borra(BASE)
mc.fin('motor fuera')
