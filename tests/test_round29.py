# -*- coding: utf-8 -*-
"""Round 29 - firmas MULTILINEA y comentario de documentacion en insert
(campo 18-sep, construyendo el nodo Linux con el propio MCP):

  1) La firma que ocupa VARIAS lineas se escribia TRUNCADA en la clase: solo
     la primera linea. Y como esa linea acaba en ';' (separador de grupos de
     parametros), la comprobacion de cierre la daba por buena y el informe
     anunciaba "las DOS mitades". El compilador contestaba E2029 + E2037 +
     cascada de "identificador no declarado" LEJOS del sitio real.
  2) Un bloque con comentario de documentacion encima -el estilo de la casa-
     se rechazaba entero ("no empieza por una firma de rutina").

Desde v0.95 la firma se lee hasta el ';' que la cierra contando parentesis,
y se admite comentario previo (que va con la implementacion, no a la clase).

Usage:  python tests/test_round29.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

CARPETA = mc.carpeta('round29')
# su propia copia, fuera de la jaula: el compilado no se ejecuta en su sitio
EXE = mc.copia_exe(os.path.join(CARPETA, 'srv'))
DIR = os.path.join(CARPETA, 'jail')
os.makedirs(DIR)

CRLF = '\r\n'
BASE = CRLF.join([
    'unit Round29;', '',
    'interface', '',
    'type',
    '  TCosa = class',
    '  private',
    '    FValor: Integer;',
    '  public',
    '    procedure Existente;',
    '    procedure Preparada(Sender: TObject);',
    '  end;', '',
    'implementation', '',
    'procedure TCosa.Existente;',
    'begin',
    '  FValor := 1;',
    'end;', '',
    'end.', ''])

env = mc.entorno({'DELPHI_MCP_ROOTS': DIR})
srv = mc.Stdio(EXE, env, nombre='r29')
call = srv.call


def fresh(name, content=BASE):
    pas = os.path.join(DIR, name)
    open(pas, 'w', encoding='utf-8', newline='').write(content)
    return pas

def leer(pas):
    return open(pas, encoding='utf-8', newline='').read()

def clase_de(txt):
    """El cuerpo de la clase, donde vive la declaracion."""
    a = txt.index('TCosa = class')
    b = txt.index('  end;', a)
    return txt[a:b]

# ---------------------------------------------------------------- 1. multilinea
pas = fresh('multi.pas')
FIRMA = ('function Llamar(const ADestino, ARuta: string;' + CRLF +
         '  const AArgs: array of string; out ARespuesta: Pointer): Boolean;')
r = call('delphi_edit', {"path": pas, "insert": "metodo", "inclass": "TCosa",
                         "visibility": "public",
                         "code": FIRMA + CRLF + 'begin' + CRLF +
                                 '  Result := False;' + CRLF + 'end;'})
t = leer(pas)
cl = clase_de(t)
check('multilinea: aceptada', not r.startswith('RECHAZADO'), r)
check('multilinea: la clase recibe la firma ENTERA',
      'const AArgs: array of string; out ARespuesta: Pointer): Boolean;' in cl, cl[-300:])
check('multilinea: la declaracion NO queda partida',
      cl.count('function Llamar(') == 1 and 'Boolean;' in cl, cl[-300:])
check('multilinea: implementacion cualificada una sola vez',
      t.count('function TCosa.Llamar(') == 1, t.count('function TCosa.Llamar('))
check('multilinea: la firma cualificada conserva sus dos lineas',
      'function TCosa.Llamar(const ADestino, ARuta: string;' in t and
      'out ARespuesta: Pointer): Boolean;' in t, 'falta una mitad')
check('multilinea: el informe no miente sobre las dos mitades',
      'DOS mitades' in r and 'ARespuesta' in r, r[:200])

# ------------------------------------------------------- 2. comentario encima
pas = fresh('coment.pas')
r = call('delphi_edit', {"path": pas, "insert": "metodo", "inclass": "TCosa",
                         "visibility": "public",
                         "code": '{ Documenta lo que hace, como el estilo de la casa. }' + CRLF +
                                 'procedure Documentada;' + CRLF + 'begin' + CRLF +
                                 '  FValor := 7;' + CRLF + 'end;'})
t = leer(pas)
cl = clase_de(t)
check('comentario: aceptado', not r.startswith('RECHAZADO'), r)
check('comentario: la clase recibe SOLO la firma',
      'procedure Documentada;' in cl and 'Documenta lo que hace' not in cl, cl[-260:])
check('comentario: el comentario viaja con la implementacion',
      '{ Documenta lo que hace, como el estilo de la casa. }' in t and
      'procedure TCosa.Documentada;' in t, 'no esta junto a la implementacion')

# --------------------------------------------- 3. firma sin cerrar: rechazada
pas = fresh('abierta.pas')
r = call('delphi_edit', {"path": pas, "insert": "metodo", "inclass": "TCosa",
                         "visibility": "public",
                         "code": 'procedure SinCerrar(A: Integer' + CRLF +
                                 'begin' + CRLF + '  FValor := A;' + CRLF + 'end;'})
check('sin cerrar: rechazada con motivo claro',
      r.startswith('RECHAZADO') and 'cerrar' in r.lower(), r[:200])
check('sin cerrar: el fichero NO se toca', leer(pas) == BASE, 'fichero modificado')

# ------------------------------------------- 4. una linea sigue funcionando
pas = fresh('simple.pas')
r = call('delphi_edit', {"path": pas, "insert": "metodo", "inclass": "TCosa",
                         "visibility": "public",
                         "code": 'procedure Sencilla;' + CRLF + 'begin' + CRLF +
                                 '  FValor := 2;' + CRLF + 'end;'})
t = leer(pas)
check('una linea: sigue haciendo las dos mitades',
      'procedure Sencilla;' in clase_de(t) and 'procedure TCosa.Sencilla;' in t, r[:200])

# ------------------------- 5. cualificada sigue rechazandose (no se rompio)
pas = fresh('cual.pas')
r = call('delphi_edit', {"path": pas, "insert": "metodo", "inclass": "TCosa",
                         "visibility": "public",
                         "code": 'procedure TCosa.Cualificada;' + CRLF + 'begin' + CRLF +
                                 '  FValor := 3;' + CRLF + 'end;'})
check('cualificada: se sigue rechazando',
      r.startswith('RECHAZADO') and 'CUALIFICADA' in r, r[:160])

# --------------------- 6. rutina-global visible: interface con firma ENTERA
UNIT_G = CRLF.join([
    'unit Round29g;', '', 'interface', '', 'implementation', '', 'end.', ''])
pas = fresh('global.pas', UNIT_G)
r = call('delphi_edit', {"path": pas, "insert": "rutina-global", "visible": True,
                         "code": 'function Sumar(const A: Integer;' + CRLF +
                                 '  const B: Integer): Integer;' + CRLF + 'begin' + CRLF +
                                 '  Result := A + B;' + CRLF + 'end;'})
t = leer(pas)
inter = t[t.index('interface'):t.index('implementation')]
check('global visible: la interface recibe la firma ENTERA',
      'const B: Integer): Integer;' in inter, inter[-200:])

srv.cierra()
mc.fin('round29')
