# -*- coding: utf-8 -*-
r"""Lo que una tool prometia y no hacia (1.22.2; Opus 5.5 en Hermes sobre la 1.22.1, 22/23-oct-2026).

delphi_move dice "What it could not re-point is named" y callaba lo que el build lee por una propiedad del
documento ($(My-Path), que puede ser cualquier cosa y no se re-apunta) o escrito absoluto: tras mover la carpeta,
F2613 sin pista. Ahora MOVE-021 lo nombra, con el valor expandido como lo lee msbuild (el expansor de la puerta).

  M1 un proyecto con My-Path=lib y DCC_UnitSearchPath=$(My-Path): mover lib a lib2 nombra My-Path en MOVE-021
     (ROJO contra la 1.22.1: callaba)
  M1b ...y es lo que rompe: el build da F2613 hasta que set-property My-Path=lib2, y entonces compila
  M2 control: una ruta relativa ESCRITA (lib3) se re-apunta (MOVE-005) y no sale en MOVE-021
  M3 una ruta absoluta del DCC_IncludePath a lo movido: nombrada (ROJO igual)
  M4 control: mover una carpeta Data no nombra el DCC_Namespace (Data.Win no es una ruta que lea el build)
  M5 control: el proyecto entero renombrado en el mismo nivel: su $(Comun)=..\comun sigue llegando, nada que decir
  M6 ...y un nivel mas adentro: $(Comun)=..\comun ya no llega, nombrado (ROJO igual)

delphi_config set-property cambia un valor EN SU SITIO, y uno con $(X) podia quedar encima de la definicion de X:
msbuild lee el .dproj de arriba abajo y lo lee vacio (F2613), sin aviso. Ahora CFG-136 lo dice.
  P1 DCC_UnitSearchPath=lib, luego My-Path=lib (al final), luego DCC_UnitSearchPath=$(My-Path) en su sitio:
     CFG-136 dice que msbuild lee $(My-Path) vacio ahi (ROJO contra la 1.22.1: callaba)
  P1b ...y es verdad: el build da F2613
  P2 control: una propiedad NUEVA con $(My-Path) va al final, debajo de My-Path: sin nota
  P3 remove-property y set-property otra vez (lo que dice la nota): sin nota, y compila

delphi_designer con un frame en linea: preview nombraba un componente del frame por su ruta (Frame11.Edit1, como el
cargador, FindNestedComponent) y get/set no; DSGN-078 no listaba los del frame y mandaba a editarlos en el fichero
del frame, cuando el IDE los cambia en el form, en su bloque inherited.
  F1 get Frame11.Edit1: su bloque inherited (ROJO contra la 1.22.1: DSGN not found)
  F2 set Frame11.Edit1 Text: escrito en su bloque inherited, dentro del inline (ROJO igual)
  F3 un nombre que no esta: DSGN-078 lista Frame11.Edit1 por su ruta y no manda a editarlo en el frame (ROJO)
  F4 control: delete Frame11.Edit1 se niega (es del frame) y el fichero no cambia
  F5 control: Frame11.Nada (no esta en el form) y Button1.Edit1 (Button1 no es un frame): DSGN-078

Menores medidos sobre la 1.22.1 (Opus en Hermes y dos agentes de medida, 23-oct-2026), cada uno ROJO contra ella:
  G1 delphi_git en una carpeta sin repo: GIT-082 NOT_FOUND (decia GIT-036 DENIED)
  R1 delphi_read con fromline pasado el final: READ-010 y "fromline=" (decia EDIT-100 y "from=")
  C1 delphi_create form-vcl sin project: CREATE-036 (decia GUARD-018, "no path given")
  C2 delphi_create kind=project-library: CREATE-011 nombra include (lo omitia)
  D1 un perfil que no existe: PAS-053 es NOT_FOUND (era DENIED)
  B1 BUILD-050 de un %2E%2E escrito: dice tambien como esta ESCRITO (citaba solo el ..)
  B2 un build que compila dice durationMs (no decia cuanto tardo)
  S1 delphi_search con UN fichero por raiz y un pattern que no lo elige: SEARCH-009 (buscaba en el, callando)
  S2 control: con un pattern que SI lo elige, busca
  A1 delphi_adb devices con device (uno permitido): ADB-028 (lo ignoraba en silencio)
  K1 delphi_components con platform y filter: COMP-011 INVALID_PARAM, como las hermanas (contestaba y anadia una nota)
  D2 delphi_definition kind=implementation de un metodo: character0 en el NOMBRE de la cabecera, como declaration
     (ROJO: 0, la columna de "procedure")
  H1 delphi_hover de IntToStr: el enlace del motor como ruta de la casa y linea, no file:///srvc%3A/... (ROJO)
  H1b ...y esa ruta y esa linea las lee delphi_read: es la de IntToStr

Y uno que encontro esta misma noche el primer tester (23-oct-2026): editar un fichero nombrandolo con OTRAS mayusculas
lo renombraba (MoveFileEx deja el nombre que se le da): un delphi_edit de Mcp.Tools.ADB.pas dejo asi el
Mcp.Tools.Adb.pas del repo, y git, que no distingue, no lo ensenaba.
  N1 delphi_edit de UCASO.PAS sobre UCaso.pas: el fichero sigue llamandose UCaso.pas (ROJO contra la 1.22.1)
  N2 ...y delphi_textedit (el mismo escritor) de NOTAS.TXT sobre Notas.txt
  O1 delphi_docs search que cabe en limit: total = los resultados (contaba las candidatas: 5 con 4, ROJO)
  Y1 delphi_symbols de una carpeta: el digest trae 'const X = 1;' en una linea, las constantes con tipo y las
     variables de la interfaz (ROJO: se perdian)

Y uno de seguridad (P4 de la revision de Opus 5.5, medido el 23-oct-2026): el id de un changeset es una CAPACIDAD
(quien lo sabe hace commit o rollback del lote de otro) y su cola salia de Random, un LCG de 32 bits: con UN id
visto se reconstruye el estado y se acierta la cola del siguiente, y status ensena el resto.
  CS1 dos begin seguidos: la cola del segundo NO se predice desde el primero (ROJO contra la 1.22.1: acertaba)

Y GUARD-002 (Hermes, 22-oct: tres negativas hasta dar con la raiz que se lee):
  J1 con una raiz que no existe y otra de solo lectura, una ruta de fuera: GUARD-002 nombra la de solo lectura
     (marcada) y no la que no existe (ROJO: nombraba la que no existe y callaba la de solo lectura)

Y las paginas de un TPageControl (Opus en Hermes, 1.22.1; medido el 23-oct-2026: insert no tenia como anadir una):
  T1 insert de un TTabSheet en un TPageControl: dentro de el, y el form carga en preview (ROJO: DSGN-080)
  T2 control: un TButton en esa pagina
  T3 un TTabSheet en el form: DSGN-168 (ROJO: se insertaba, y su ReadState lo deja sin PageControl)
  T4 set parent= de la pagina al form: DSGN-168, nada movido (ROJO igual)
  T5 la nota de la pagina: sin 10,10 (DSGN-169) y con la ActivePage de su control, que el programa suele poner en
     codigo (ROJO contra r1222f: decia "lands at 10,10")
  T6 control: la nota de un TButton sigue con su 10,10 y sin ActivePage

Uso:  python tests/test_contratos_1222.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('contratos-1222')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)  # preview, y set/insert le preguntan al escritor del IDE
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='c1222', t=600)


def lee(p):
    return open(p, encoding='utf-8-sig', newline='').read()


def planta(dproj, tras, texto):
    """Mete texto en el .dproj detras de la primera linea que contiene tras (como lo dejaria un operador)."""
    dp = lee(dproj)
    i = dp.index(tras)
    j = dp.index('\n', i) + 1
    open(dproj, 'w', encoding='utf-8-sig', newline='').write(dp[:j] + texto + dp[j:])


def nombrado(r, *trozos):
    """La linea de MOVE-021 de la respuesta lleva todos los trozos."""
    for linea in (r or '').replace('\\n', '\n').split('\n'):
        if mc.es(linea, 'SN_REUBICA_NO_LLEGA_FMT'):
            return all(t in linea for t in trozos)
    return False


try:
    app = os.path.join(JAIL, 'app')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'App', 'dir': app})
    check('M0 fixture creada (delphi_create)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    dproj = os.path.join(app, 'App.dproj')
    for sub in ('lib', 'lib3', 'inc', 'Data'):
        os.makedirs(os.path.join(app, sub))
    open(os.path.join(app, 'lib', 'ULib.pas'), 'w', newline='\r\n').write(
        'unit ULib;\ninterface\nfunction Doble(X: Integer): Integer;\nimplementation\n'
        'function Doble(X: Integer): Integer;\nbegin\n  Result := X * 2;\nend;\nend.\n')
    open(os.path.join(app, 'inc', 'comun.inc'), 'w', newline='\r\n').write('// comun\n')
    open(os.path.join(app, 'Data', 'datos.txt'), 'w').write('datos')
    os.makedirs(os.path.join(JAIL, 'comun'))
    planta(dproj, '<DCC_DcuOutput>',
           '        <My-Path>lib</My-Path>\r\n'
           '        <Comun>..\\comun</Comun>\r\n'
           '        <DCC_UnitSearchPath>$(My-Path);lib3;$(Comun);$(DCC_UnitSearchPath)</DCC_UnitSearchPath>\r\n'
           '        <DCC_IncludePath>%s;$(DCC_IncludePath)</DCC_IncludePath>\r\n' % os.path.join(app, 'inc'))
    # el uses a mano: adduses de una unit de la carpeta del proyecto la manda a add-unit (USES-021), y aqui
    # tiene que encontrarse SOLO por el search path
    dpr = os.path.join(app, 'App.dpr')
    t = lee(dpr)
    open(dpr, 'w', encoding='utf-8-sig', newline='').write(t.replace('System.SysUtils;', 'System.SysUtils, ULib;', 1))
    check('M0 ...el .dpr usa ULib, que se encuentra por $(My-Path)', 'ULib;' in lee(dpr), lee(dpr)[:300])
    r = srv.call('delphi_build', {'project': dproj, 'platform': 'Win64'}, 300)
    check('M0 ...y compila antes de mover nada', mc.como_json(r).get('success') is True, r[:400])

    r = srv.call('delphi_move', {'path': os.path.join(app, 'lib'), 'dest': os.path.join(app, 'lib2')})
    check('M1 mover lib a lib2: MOVE-021 nombra el DCC_UnitSearchPath que llega por $(My-Path)',
          not mc.fallo(r) and nombrado(r, 'App.dproj', 'DCC_UnitSearchPath', '$(My-Path)', 'lib2'), r[:900])
    check('M1 ...y la propiedad sigue como estaba: no se reescribe', '<My-Path>lib</My-Path>' in lee(dproj),
          lee(dproj)[:300])
    r = srv.call('delphi_build', {'project': dproj, 'platform': 'Win64'}, 300)
    check('M1b ...es lo que rompe: el build da F2613 por ULib', 'F2613' in r and 'ULib' in r, r[:400])
    r = srv.call('delphi_config', {'project': dproj, 'command': 'set-property', 'name': 'My-Path',
                                   'value': 'lib2'})
    r = srv.call('delphi_build', {'project': dproj, 'platform': 'Win64'}, 300)
    check('M1b ...y con set-property My-Path=lib2 compila', mc.como_json(r).get('success') is True, r[:400])

    r = srv.call('delphi_move', {'path': os.path.join(app, 'lib3'), 'dest': os.path.join(app, 'lib4')})
    check('M2 control: lib3, escrita, se re-apunta (MOVE-005) y MOVE-021 no la nombra',
          mc.es(r, 'SN_REUBICA_FMT') and ';lib4;' in lee(dproj) and not mc.es(r, 'SN_REUBICA_NO_LLEGA_FMT'),
          r[:900])

    r = srv.call('delphi_move', {'path': os.path.join(app, 'inc'), 'dest': os.path.join(app, 'inc2')})
    check('M3 una ruta ABSOLUTA del DCC_IncludePath a lo movido: nombrada en MOVE-021',
          nombrado(r, 'App.dproj', 'DCC_IncludePath', 'inc2'), r[:900])

    r = srv.call('delphi_move', {'path': os.path.join(app, 'Data'), 'dest': os.path.join(app, 'Data2')})
    check('M4 control: mover Data no nombra el DCC_Namespace (no es una ruta que lea el build)',
          not mc.fallo(r) and not mc.es(r, 'SN_REUBICA_NO_LLEGA_FMT'), r[:900])

    app2 = os.path.join(JAIL, 'app2')
    r = srv.call('delphi_move', {'path': app, 'dest': app2})
    check('M5 control: el proyecto renombrado en el MISMO nivel: $(Comun)=..\\comun sigue llegando',
          not mc.fallo(r) and not nombrado(r, '$(Comun)'), r[:900])
    r = srv.call('delphi_move', {'path': app2, 'dest': os.path.join(JAIL, 'sub', 'app2')})
    check('M6 ...y un nivel mas adentro: $(Comun) ya no llega a comun, nombrado',
          nombrado(r, 'App.dproj', 'DCC_UnitSearchPath', '$(Comun)', 'comun'), r[:900])

    pdir = os.path.join(JAIL, 'prop')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Prop', 'dir': pdir})
    check('P0 fixture creada (delphi_create)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    pproj = os.path.join(pdir, 'Prop.dproj')
    os.makedirs(os.path.join(pdir, 'lib'))
    open(os.path.join(pdir, 'lib', 'ULib.pas'), 'w', newline='\r\n').write(
        'unit ULib;\ninterface\nfunction Doble(X: Integer): Integer;\nimplementation\n'
        'function Doble(X: Integer): Integer;\nbegin\n  Result := X * 2;\nend;\nend.\n')
    pdpr = os.path.join(pdir, 'Prop.dpr')
    t = lee(pdpr)
    open(pdpr, 'w', encoding='utf-8-sig', newline='').write(t.replace('System.SysUtils;', 'System.SysUtils, ULib;', 1))

    def pon(nombre, valor):
        return srv.call('delphi_config', {'project': pproj, 'command': 'set-property', 'name': nombre,
                                          'value': valor})

    r1, r2 = pon('DCC_UnitSearchPath', 'lib'), pon('My-Path', 'lib')
    check('P0 ...DCC_UnitSearchPath=lib y despues My-Path=lib', mc.es(r1, 'SN_CFG_PROPERTY_PUESTA_FMT') and
          mc.es(r2, 'SN_CFG_PROPERTY_PUESTA_FMT') and 'EMPTY' not in r1 + r2, (r1[:300], r2[:300]))
    dp = lee(pproj)
    check('P0 ...My-Path queda DEBAJO de DCC_UnitSearchPath', dp.index('<DCC_UnitSearchPath>') < dp.index('<My-Path>'),
          dp[:200])
    r = pon('DCC_UnitSearchPath', '$(My-Path)')
    check('P1 DCC_UnitSearchPath=$(My-Path) en su sitio, encima de My-Path: CFG-136 dice que se lee VACIO',
          mc.es(r, 'SN_CFG_PROPERTY_PUESTA_FMT') and 'reads $(My-Path) EMPTY here' in r, r[:600])
    r = srv.call('delphi_build', {'project': pproj, 'platform': 'Win64'}, 300)
    check('P1b ...y es verdad: el build da F2613 por ULib', 'F2613' in r and 'ULib' in r, r[:400])
    r = pon('Otra', '$(My-Path)\\x')
    check('P2 control: una propiedad NUEVA con $(My-Path) va al final, debajo: sin nota',
          mc.es(r, 'SN_CFG_PROPERTY_PUESTA_FMT') and 'EMPTY' not in r, r[:600])
    rq = srv.call('delphi_config', {'project': pproj, 'command': 'remove-property', 'name': 'DCC_UnitSearchPath'})
    r = pon('DCC_UnitSearchPath', '$(My-Path)')
    check('P3 remove-property y set-property otra vez: sin nota',
          mc.es(rq, 'SN_CFG_PROPERTY_QUITADA_FMT') and mc.es(r, 'SN_CFG_PROPERTY_PUESTA_FMT') and 'EMPTY' not in r,
          (rq[:300], r[:600]))
    r = srv.call('delphi_build', {'project': pproj, 'platform': 'Win64'}, 300)
    check('P3 ...y compila', mc.como_json(r).get('success') is True, r[:400])

    fdir = os.path.join(JAIL, 'frm')
    os.makedirs(fdir)
    open(os.path.join(fdir, 'UFrame1.pas'), 'w', newline='\r\n').write(
        'unit UFrame1;\ninterface\nuses\n  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, System.Classes;\ntype\n'
        '  TFrame1 = class(TFrame)\n    Edit1: TEdit;\n    Label1: TLabel;\n  end;\nimplementation\n'
        '{$R *.dfm}\nend.\n')
    open(os.path.join(fdir, 'UFrame1.dfm'), 'w', newline='\r\n').write(
        'object Frame1: TFrame1\n  Left = 0\n  Top = 0\n  Width = 200\n  Height = 100\n  TabOrder = 0\n'
        '  object Edit1: TEdit\n    Left = 8\n    Top = 8\n    Width = 121\n    Height = 23\n    TabOrder = 0\n'
        "    Text = 'Edit1'\n  end\n  object Label1: TLabel\n    Left = 8\n    Top = 40\n    Width = 34\n    Height = 15\n"
        "    Caption = 'Label1'\n  end\nend\n")
    open(os.path.join(fdir, 'UForm1.pas'), 'w', newline='\r\n').write(
        'unit UForm1;\ninterface\nuses\n  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, System.Classes, UFrame1;\ntype\n'
        '  TForm1 = class(TForm)\n    Frame11: TFrame1;\n    Button1: TButton;\n  end;\nvar\n  Form1: TForm1;\n'
        'implementation\n{$R *.dfm}\nend.\n')
    fdfm = os.path.join(fdir, 'UForm1.dfm')
    open(fdfm, 'w', newline='\r\n').write(
        "object Form1: TForm1\n  Left = 0\n  Top = 0\n  Caption = 'Form1'\n  ClientHeight = 200\n  ClientWidth = 300\n"
        '  inline Frame11: TFrame1\n    Left = 8\n    Top = 8\n    Width = 200\n    Height = 100\n    TabOrder = 0\n'
        "    inherited Edit1: TEdit\n      Text = 'uno'\n    end\n  end\n"
        '  object Button1: TButton\n    Left = 8\n    Top = 120\n    Width = 75\n    Height = 25\n'
        "    Caption = 'Button1'\n    TabOrder = 1\n  end\nend\n")

    def dsg(**kw):
        a = {'path': fdfm}
        a.update(kw)
        return srv.call('delphi_designer', a, 240)

    r = dsg(command='get', component='Frame11.Edit1')
    check('F1 get Frame11.Edit1: su bloque inherited', not mc.fallo(r) and "Text = 'uno'" in r, r[:400])
    r = dsg(command='set', component='Frame11.Edit1', prop='Text', value="'dos'")
    t = lee(fdfm)
    check('F2 set Frame11.Edit1 Text: escrito en su bloque inherited, dentro del inline',
          not mc.fallo(r) and "    inherited Edit1: TEdit\r\n      Text = 'dos'\r\n    end\r\n  end" in t, r[:400] + ' | ' + t[:600])
    r = dsg(command='set', component='Nada', prop='Caption', value="'x'")
    check('F3 un nombre que no esta: DSGN-078 lista Frame11.Edit1 por su ruta y no manda a editarlo alli',
          mc.es(r, 'SR_DESIGNER_COMPONENTE_NO_ESTA_FMT') and 'Frame11.Edit1' in r and 'edit it there' not in r, r[:500])
    antes = open(fdfm, 'rb').read()
    r = dsg(command='delete', component='Frame11.Edit1')
    check('F4 control: delete Frame11.Edit1 se niega (es del frame) y el fichero no cambia',
          mc.es(r, 'SR_DESIGNER_DENTRO_DE_INLINE_FMT') and open(fdfm, 'rb').read() == antes, r[:400])
    r1 = dsg(command='set', component='Frame11.Nada', prop='Caption', value="'x'")
    r2 = dsg(command='set', component='Button1.Edit1', prop='Text', value="'x'")
    check('F5 control: Frame11.Nada y Button1.Edit1 (Button1 no es un frame): DSGN-078, nada escrito',
          mc.es(r1, 'SR_DESIGNER_COMPONENTE_NO_ESTA_FMT') and mc.es(r2, 'SR_DESIGNER_COMPONENTE_NO_ESTA_FMT')
          and open(fdfm, 'rb').read() == antes, (r1[:300], r2[:300]))

    plano = os.path.join(JAIL, 'plano')
    os.makedirs(plano)
    r = srv.call('delphi_git', {'repo': plano, 'command': 'status'})
    check('G1 git en una carpeta sin repo: GIT-082 NOT_FOUND',
          mc.es(r, 'SR_GIT_NO_ES_REPO_FMT') and mc.resultado(r) == 'NOT_FOUND', r[:300])
    cinco = os.path.join(plano, 'UCinco.pas')
    open(cinco, 'w', newline='\r\n').write('unit UCinco;\ninterface\nimplementation\n\nend.\n')
    r = srv.call('delphi_read', {'path': cinco, 'fromline': 9})
    check('R1 read con fromline pasado el final: READ-010 y fromline=9',
          mc.es(r, 'SR_EDIT_DESDE_MAS_ALLA_FINAL_FMT') and '[READ-010' in r and 'fromline=9' in r, r[:300])
    r = srv.call('delphi_create', {'kind': 'form-vcl', 'name': 'UFormSuelto', 'dir': plano})
    check('C1 create form-vcl sin project: CREATE-036 (no un GUARD-018 generico)',
          mc.es(r, 'SR_CREATE_FORM_NEED_PROJECT') and not os.path.exists(os.path.join(plano, 'UFormSuelto.pas')),
          r[:300])
    r = srv.call('delphi_create', {'kind': 'project-library', 'name': 'Lib', 'dir': os.path.join(JAIL, 'lib1')})
    check('C2 create project-library: CREATE-011 nombra include, que tambien va suelto',
          mc.es(r, 'SR_CREATE_PROJECT_KIND') and 'include' in r, r[:400])
    r = srv.call('delphi_build', {'project': pproj, 'target': 'Build', 'profile': 'noexiste'}, 300)
    check('D1 un perfil que no existe: PAS-053 NOT_FOUND', mc.es(r, 'SR_PROFILE_NO_EXISTE_FMT') and
          mc.resultado(r) == 'NOT_FOUND', r[:300])
    r = srv.call('delphi_build', {'project': pproj, 'platform': 'Win64'}, 300)
    j = mc.como_json(r)
    check('B2 un build que compila dice durationMs', j.get('success') is True and
          isinstance(j.get('durationMs'), int) and j.get('durationMs') > 0, r[:300])
    r = pon('DCC_UnitSearchPath', '%2E%2E\\%2E%2E\\%2E%2E\\%2E%2E\\Fuera1222;$(DCC_UnitSearchPath)')
    r = srv.call('delphi_build', {'project': pproj, 'platform': 'Win64'}, 300)
    check('B1 BUILD-050 de un %2E%2E escrito: lo cita tambien como esta escrito',
          mc.es(r, 'SR_BUILD_LECTURA_FUERA_FMT') and 'written in the project as %2E%2E' in r, r[:600])
    r = srv.call('delphi_search', {'root': cinco, 'query': 'unit', 'pattern': '*.md'})
    check('S1 search de UN fichero con un pattern que no lo elige: SEARCH-009, nada buscado',
          mc.es(r, 'SR_SEARCH_PATTERN_CON_FICHERO_FMT') and '"hits"' not in r, r[:300])
    r = srv.call('delphi_search', {'root': cinco, 'query': 'unit', 'pattern': '*.pas'})
    check('S2 control: con un pattern que SI lo elige, busca', '"hits"' in r and not mc.fallo(r), r[:300])
    adb = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_ADB_DEVICES': 'SERIALX'}),
                   nombre='c1222adb', t=120)
    try:
        r = adb.call('delphi_adb', {'command': 'devices', 'device': 'SERIALX'}, 60)
        check('A1 adb devices con un device permitido: ADB-028 (no va con devices)',
              mc.es(r, 'SR_ADB_NO_VA_CON_COMANDO_FMT') and '"device"' in r, r[:300])
    finally:
        adb.cierra()
    r = srv.call('delphi_components', {'platform': 'Win64', 'filter': 'algo'}, 120)
    check('K1 components con platform y filter: COMP-011 INVALID_PARAM y sin contestar a medias',
          mc.es(r, 'SR_COMPONENTS_NO_VA_CON_MODO_FMT') and mc.resultado(r) == 'INVALID_PARAM' and
          '[COMP-002]' not in r, r[:300])

    ldir = os.path.join(JAIL, 'lsp')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Lsp', 'dir': ldir})
    lproj = os.path.join(ldir, 'Lsp.dproj')
    r = srv.call('delphi_create', {'kind': 'unit', 'name': 'UFoo', 'project': lproj, 'content':
        'unit UFoo;\ninterface\nuses System.SysUtils;\ntype\n  TFoo = class\n    procedure Bar;\n  end;\n'
        'implementation\nprocedure TFoo.Bar;\nbegin\n  Writeln(IntToStr(1));\nend;\nprocedure Usa;\n'
        'var F: TFoo;\nbegin\n  F := TFoo.Create;\n  F.Bar;\nend;\nend.\n'})
    ufoo = os.path.join(ldir, 'UFoo.pas')
    check('D0 fixture: UFoo en un proyecto', os.path.exists(ufoo), r[:200])

    def motor(tool, args):
        # el motor indexa al arrancar: "todavia no" (LSP warming) se repite
        for _ in range(6):
            r = srv.call(tool, args, 240)
            if not mc.es(r, 'SR_LSP_WARMING'):
                return r
        return r

    r = motor('delphi_definition', {'path': ufoo, 'line': 16, 'character': 4, 'kind': 'implementation'})
    # la ubicacion, por sus campos de la casa (line0/character0, DecorateLocations)
    check('D2 definition kind=implementation de F.Bar: el cuerpo, con character0 en Bar (15), no 0',
          '"line0":8' in r and '"character0":15' in r, r[:500])
    check('D2b ...y su rango no queda al reves: el end, que el motor da en la 0, tambien en el nombre',
          '"end":{"line":8,"character":15}' in r, r[:500])
    r = motor('delphi_hover', {'path': ufoo, 'line': 10, 'character': 12})
    check('H1 hover de IntToStr: el enlace como ruta de la casa y linea, sin file:///',
          'file:///' not in r and 'System.SysUtils.pas' in r and ', line ' in r, r[:500])
    m = re.search(r'\((srv\w:.*?System\.SysUtils\.pas), line (\d+)\)', r)
    if m:
        rr = srv.call('delphi_read', {'path': m.group(1), 'fromline': int(m.group(2)), 'toline': int(m.group(2))})
    else:
        rr = '(sin ruta en el hover)'
    check('H1b ...y esa ruta y esa linea las lee delphi_read: la de IntToStr', 'IntToStr' in rr, rr[:300])

    open(os.path.join(plano, 'UCaso.pas'), 'w', newline='\r\n').write('unit UCaso;\ninterface\nimplementation\nend.\n')
    # por la forma LARGA: con un trozo 8.3 en la ruta (el TEMP de esta maquina) la entrada la alarga entera con
    # las mayusculas del disco y no se ve; en D:\ (produccion, sin ~) llegaba tal cual y renombraba (medido)
    largo = mc.larga(plano)
    r = srv.call('delphi_edit', {'path': os.path.join(largo, 'UCASO.PAS'), 'old': 'interface',
                                 'new': 'interface\n// uno'})
    check('N1 delphi_edit de UCASO.PAS: escrito, y el fichero sigue llamandose UCaso.pas',
          not mc.fallo(r) and 'UCaso.pas' in os.listdir(plano) and '// uno' in lee(os.path.join(plano, 'UCaso.pas')),
          (r[:200], [n for n in os.listdir(plano) if n.lower() == 'ucaso.pas']))
    open(os.path.join(plano, 'Notas.txt'), 'w', newline='\r\n').write('uno\ndos\n')
    r = srv.call('delphi_textedit', {'path': os.path.join(largo, 'NOTAS.TXT'), 'old': 'dos', 'new': 'tres'})
    check('N2 delphi_textedit de NOTAS.TXT: escrito, y sigue llamandose Notas.txt',
          not mc.fallo(r) and 'Notas.txt' in os.listdir(plano), (r[:200], [n for n in os.listdir(plano)
                                                                         if n.lower() == 'notas.txt']))
    r = srv.call('delphi_docs', {'command': 'search', 'query': 'FormatDateTime', 'limit': 25}, 240)
    j = mc.como_json(r) or {}
    res = j.get('results') or []
    check('O1 docs search que cabe en limit: total = los resultados que salen',
          res and j.get('total') == len(res), (j.get('total'), len(res), r[:300]))
    dig = os.path.join(JAIL, 'dig')
    os.makedirs(dig)
    open(os.path.join(dig, 'UConst2.pas'), 'w', newline='\r\n').write(
        "unit UConst2;\ninterface\nconst MAX_UNO = 1;\nconst\n  TIPADA: Integer = 5;\n"
        "  NOMBRES: array[0..1] of string = ('a', 'b');\nvar\n  GContador: Integer;\nimplementation\nend.\n")
    r = srv.call('delphi_symbols', {'path': dig}, 240)
    check('Y1 digest de carpeta: const de una linea, constantes con tipo y variables',
          all(x in r for x in ('MAX_UNO', 'TIPADA', 'NOMBRES', 'GContador')), r[:600])

    def siguiente_de_random(cola):
        # el Random de Delphi: RandSeed := RandSeed * $08088405 + 1, y Random($10000) son sus 16 bits altos
        paso = lambda s: (s * 0x08088405 + 1) & 0xFFFFFFFF
        a, b = int(cola[:4], 16), int(cola[4:8], 16)
        for bajo in range(0x10000):
            s2 = paso((a << 16) | bajo)
            if (s2 >> 16) == b:
                s3 = paso(s2)
                return '%04X%04X' % (s3 >> 16, paso(s3) >> 16)
        return None

    ids = [mc.id_changeset(srv.call('delphi_changeset', {'command': 'begin'})) for _ in range(2)]
    pred = siguiente_de_random(ids[0].rsplit('-', 1)[-1]) if ids[0] else None
    check('CS1 la cola del id de un changeset no se predice desde el anterior (era un LCG)',
          all(ids) and len(ids[1].rsplit('-', 1)[-1]) == 8 and not ids[1].endswith(pred or 'x'), (ids, pred))
    for i in ids:
        if i:
            srv.call('delphi_changeset', {'command': 'rollback', 'id': i})

    ref = os.path.join(BASE, 'ref')
    os.makedirs(ref)
    no_esta = os.path.join(BASE, 'no-esta')
    jg = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL + ';' + no_esta, 'DELPHI_MCP_READONLY_ROOTS': ref}),
                  nombre='c1222jaula', t=120)
    try:
        r = jg.call('delphi_search', {'root': os.path.join(BASE, 'srv'), 'query': 'x'})
        check('J1 GUARD-002 nombra la raiz de solo lectura (marcada) y no la que no existe',
              mc.es(r, 'SR_JAIL_FMT') and re.search(r'\\ref\\? \(read-only\)', r) is not None and 'no-esta' not in r,
              r[:500])
    finally:
        jg.cierra()

    vdir = os.path.join(JAIL, 'pag')
    r = srv.call('delphi_create', {'kind': 'project-vcl', 'name': 'Pag', 'dir': vdir})
    vdfm = os.path.join(vdir, 'UMain.dfm')
    r = srv.call('delphi_designer', {'command': 'insert', 'path': vdfm, 'classname': 'TPageControl'}, 240)
    check('T0 fixture: un TPageControl en el form', not mc.fallo(r) and 'PageControl1' in lee(vdfm), r[:300])
    r = srv.call('delphi_designer', {'command': 'insert', 'path': vdfm, 'classname': 'TTabSheet',
                                     'parent': 'PageControl1'}, 240)
    t = lee(vdfm)
    # dentro del TPageControl: su bloque es el unico de sangria 2, y la pagina va con la 4, detras de el
    i_pc = t.find('  object PageControl1: TPageControl')
    check('T1 insert de un TTabSheet en el TPageControl: dentro de el',
          not mc.fallo(r) and 0 <= i_pc < t.find('    object TabSheet1: TTabSheet'), r[:400] + ' | ' + t[i_pc:i_pc + 400])
    # su nota: una pagina no guarda posicion (nada de 10,10) y dice cual abre (ActivePage, que se pone en codigo)
    check('T5 la nota de una pagina: sin 10,10 y con la ActivePage de su control',
          mc.es(r, 'SN_DESIGNER_INSERT_SIN_SITIO_NOTE') and 'PageControl1.ActivePage := TabSheet1' in r
          and '10,10' not in r, r[:700])
    r = srv.call('delphi_designer', {'command': 'preview', 'path': vdfm}, 240)
    check('T1 ...y el form carga (preview)', not mc.fallo(r) and 'fidelity' in r, r[:300])
    r = srv.call('delphi_designer', {'command': 'insert', 'path': vdfm, 'classname': 'TButton',
                                     'parent': 'TabSheet1'}, 240)
    check('T2 control: un TButton en la pagina', not mc.fallo(r), r[:300])
    check('T6 control: la de un TButton sigue con su 10,10 y sin ActivePage',
          mc.es(r, 'SN_DESIGNER_INSERT_NOTE') and '10,10' in r and 'ActivePage' not in r, r[:700])
    antes = open(vdfm, 'rb').read()
    r = srv.call('delphi_designer', {'command': 'insert', 'path': vdfm, 'classname': 'TTabSheet'}, 240)
    check('T3 un TTabSheet en el form: DSGN-168 y nada escrito',
          mc.es(r, 'SR_DESIGNER_PAGINA_FMT') and open(vdfm, 'rb').read() == antes, r[:300])
    r = srv.call('delphi_designer', {'command': 'set', 'path': vdfm, 'component': 'TabSheet1',
                                     'parent': 'FormMain'}, 240)
    check('T4 set parent= de la pagina al form: DSGN-168 y nada movido',
          mc.es(r, 'SR_DESIGNER_PAGINA_FMT') and open(vdfm, 'rb').read() == antes, r[:300])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('contratos 1222')
