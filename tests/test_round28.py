# -*- coding: utf-8 -*-
"""Round 28 - insert:"metodo" ante un metodo que YA existe (hermes, campo
2026-09-17): la tool escribia las dos mitades a ciegas y una clase con la
declaracion ya preparada acababa con declaracion duplicada o rota (E2254/
E2067). Desde v0.94 mira cada mitad: solo escribe la que falta, y un metodo
entero se rechaza con las dos lineas y el camino (old/new).

Usage:  python tests/test_round28.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

CARPETA = mc.carpeta('round28')
# su propia copia, fuera de la jaula: el compilado no se ejecuta en su sitio
EXE = mc.copia_exe(os.path.join(CARPETA, 'srv'))
DIR = os.path.join(CARPETA, 'jail')
os.makedirs(DIR)

CRLF = '\r\n'
BASE = CRLF.join([
    'unit Round28;', '',
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
srv = mc.Stdio(EXE, env, nombre='r28')
call = srv.call

def fresh(name, content=BASE):
    pas = os.path.join(DIR, name)
    open(pas, 'w', encoding='utf-8', newline='').write(content)
    return pas

def edit(pas, firma, cuerpo, vis='public'):
    return call('delphi_edit', {"path": pas, "insert": "metodo",
                                "inclass": "TCosa", "visibility": vis,
                                "code": firma + CRLF + 'begin' + CRLF + cuerpo + CRLF + 'end;'})

# ---- 1. metodo NUEVO: las dos mitades, como siempre ----
pas = fresh('Caso1.pas')
out = edit(pas, 'procedure Nueva;', '  FValor := 2;')
check('nuevo: las DOS mitades', 'DOS mitades' in out, out[:200])
t = open(pas, encoding='utf-8').read()
check('nuevo: 1 declaracion + 1 implementacion',
      t.count('procedure Nueva;') == 1 and t.count('procedure TCosa.Nueva;') == 1, t[:400])

# ---- 2. declaracion YA preparada (el caso de hermes) ----
pas = fresh('Caso2.pas')
out = edit(pas, 'procedure Preparada(Sender: TObject);', '  FValor := 3;')
check('preparada: lo dice claro',
      'YA declaraba' in out and 'Solo se ha escrito la implementacion' in out, out[:300])
t = open(pas, encoding='utf-8').read()
check('preparada: UNA sola declaracion (no duplica)',
      t.count('procedure Preparada(Sender: TObject);') == 1, t.count('procedure Preparada(Sender: TObject);'))
check('preparada: la implementacion SI se escribio',
      t.count('procedure TCosa.Preparada(Sender: TObject);') == 1, t[:600])

# ---- 3. metodo ENTERO: rechazo con las dos lineas y el camino ----
pas = fresh('Caso3.pas')
out = edit(pas, 'procedure Existente;', '  FValor := 4;')
check('entero: RECHAZADO', out.startswith('RECHAZADO') and 'ya existe ENTERO' in out, out[:250])
check('entero: da las dos lineas y el camino old/new',
      'declaracion en linea' in out and 'old/new' in out, out[:300])
t = open(pas, encoding='utf-8', newline='').read()
check('entero: el fichero NO cambio', t == BASE, len(t))

# ---- 4. implementacion huerfana: fichero incoherente, rechazo honesto ----
HUERFANA = BASE.replace('end.' + CRLF, CRLF.join([
    'procedure TCosa.Huerfana;', 'begin', 'end;', '', 'end.', '']))
pas = fresh('Caso4.pas', HUERFANA)
out = edit(pas, 'procedure Huerfana;', '  FValor := 5;')
check('huerfana: RECHAZADO incoherente',
      out.startswith('RECHAZADO') and 'no la declara' in out, out[:250])

srv.cierra()
mc.fin('round28 (insert metodo idempotente)')
