# -*- coding: utf-8 -*-
"""1.29 (C7): delphi_designer set On<Evento>=<metodo> enlaza un evento a su manejador, por EL juez que comparte con
check-binding (Lsp.DesignerBinding.FalloDeManejador): el primer metodo PUBLICADO de ese nombre en la cadena de la
clase del form (como lo busca el cargador, MethodAddress), de instancia y con la FORMA de la firma del tipo del evento
(hecho F de las tablas: palabra, cuantos parametros, modo de cada uno, array abierto, resultado; los nombres de los
tipos no se juzgan: TKeyEvent de FMX declara WideChar y el IDE escribe Char). nil quita la linea. Hasta la 1.28 set
negaba todo evento (DSGN-088) y el agente escribia la linea a mano; la medida de la demanda, en la fila C7 del vault.

  E1 VCL: OnClick=Boton1Click (publicado, procedure(TObject)) se escribe sin comillas en el bloque del boton.
     ROJO contra 166bea8b (DSGN-088 siempre: 14 de 31 en rojo, todo lo que no es un fixture)
  E2 ...y check-binding dice clean
  E3 un metodo que no existe: DSGN-088 con SF_MANEJADOR_NO_ESTA_FMT, nada escrito
  E4 uno privado: DSGN-088 con SF_MANEJADOR_NO_PUBLICADO_FMT
  E5 uno con otra forma (procedure(TObject; Integer)): DSGN-088 con las dos firmas legibles
  E6 uno de clase: DSGN-088 con SF_MANEJADOR_DE_CLASE_FMT
  E7 un valor que no es un nombre ('Boton1Click' entre comillas): SF_MANEJADOR_NO_ES_NOMBRE_FMT
  E8 otro evento con var (OnKeyPress = procedure(TObject; var Char)): enlazado
  E9 nil quita la linea (removed)
  E10 check-binding: una linea escrita a mano a un manejador con otra forma -> eventsWithOtherSignature.
      ROJO contra c166 (no habia esa lista)
  E11 ...y el lint la dice (DesignerBindingWarnings)
  E12 la clase sigue en una base de OTRA unidad: un metodo que no esta aqui, SF_MANEJADOR_FUERA_FMT
  F1 FMX: OnKeyDown=Edicion1KeyDown con var KeyChar: Char contra el WideChar de TKeyEvent: enlazado (la forma).
     ROJO contra c166
  F2 FMX: uno de OnClick en OnKeyDown: DSGN-088 con la firma del evento (var WideChar). La tabla FMX lee
     tambien editores VCL: con el tipo de evento por su nombre pelado, los dos TKeyEvent eran uno con dos firmas
     y no se juzgaba (generacion 20: por su identidad con la unidad)
  F3 prop de un evento dice la firma de su manejador (signature)

Uso:  python tests/test_set_evento_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('set_evento_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True, con_render=True)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='evento', t=600)


def proyecto(nombre, kind):
    d = os.path.join(JAIL, nombre)
    r = srv.call('delphi_create', {'kind': kind, 'name': 'App', 'dir': d})
    check('fixture: %s (%s)' % (nombre, kind), not mc.fallo(r), r[:200])
    return d


def bytes_de(ruta):
    return open(ruta, 'rb').read()


def dsg(**kw):
    return srv.call('delphi_designer', kw, 300)


def clase_del_form(pas):
    m = re.search(r'\b(T\w+)\s*=\s*class\(TForm\)', mc.lee(pas))
    return m.group(1) if m else '?'


def metodo(pas, codigo, visibilidad='published'):
    r = srv.call('delphi_edit', {'path': pas, 'insert': 'metodo', 'inclass': clase_del_form(pas),
                                 'visibility': visibilidad, 'code': codigo})
    check('fixture: metodo %s (%s)' % (codigo.split('(')[0], visibilidad), not mc.fallo(r), r[:300])


def dice(t, nombre):
    """El motivo del juez (un SF_ sin etiqueta), por su formato."""
    return re.search(mc.patron_de_formato(nombre), t or '', re.S) is not None


def bloque(form, nombre):
    """Las lineas del bloque del componente NOMBRE, hasta su end."""
    lineas = mc.lee(form).splitlines()
    for i, l in enumerate(lineas):
        if re.match(r'\s*object %s:' % nombre, l):
            sangria = len(l) - len(l.lstrip())
            for j in range(i + 1, len(lineas)):
                if lineas[j].strip() == 'end' and len(lineas[j]) - len(lineas[j].lstrip()) == sangria:
                    return lineas[i:j + 1]
    return []


try:
    # ------------------------------------------------------------------ VCL
    V = proyecto('Vcl', 'project-vcl')
    DFM, PAS = os.path.join(V, 'UMain.dfm'), os.path.join(V, 'UMain.pas')
    for clase, nombre in (('TButton', 'Boton1'), ('TEdit', 'Edicion1')):
        r = dsg(command='insert', path=DFM, classname=clase, component=nombre)
        check('fixture: insert %s' % nombre, not mc.fallo(r), r[:200])
    metodo(PAS, 'procedure Boton1Click(Sender: TObject);\nbegin\nend;')
    metodo(PAS, 'procedure Oculto(Sender: TObject);\nbegin\nend;', 'private')
    metodo(PAS, 'procedure OtraForma(Sender: TObject; X: Integer);\nbegin\nend;')
    metodo(PAS, 'class procedure DeClase(Sender: TObject);\nbegin\nend;')
    metodo(PAS, 'procedure Edicion1KeyPress(Sender: TObject; var Key: Char);\nbegin\nend;')

    r = dsg(command='set', path=DFM, component='Boton1', prop='OnClick', value='Boton1Click')
    check('E1 VCL: OnClick=Boton1Click enlazado, sin comillas, en el bloque del boton. ROJO contra c166',
          not mc.fallo(r) and 'OnClick = Boton1Click' in [l.strip() for l in bloque(DFM, 'Boton1')], r[:400])
    r = dsg(command='check-binding', path=DFM)
    check('E2 ...y check-binding dice clean', (mc.como_json(r) or {}).get('clean') is True, r[:600])

    antes = bytes_de(DFM)
    r = dsg(command='set', path=DFM, component='Boton1', prop='OnClick', value='NoExiste')
    check('E3 un metodo que no existe: DSGN-088 (no esta declarado), nada escrito',
          mc.abre(r, 'SR_DESIGNER_SET_EVENTO_FMT') and dice(r, 'SF_MANEJADOR_NO_ESTA_FMT') and
          bytes_de(DFM) == antes, r[:400])
    r = dsg(command='set', path=DFM, component='Boton1', prop='OnClick', value='Oculto')
    check('E4 uno privado: DSGN-088 (no publicado), nada escrito',
          mc.abre(r, 'SR_DESIGNER_SET_EVENTO_FMT') and dice(r, 'SF_MANEJADOR_NO_PUBLICADO_FMT') and
          bytes_de(DFM) == antes, r[:400])
    r = dsg(command='set', path=DFM, component='Boton1', prop='OnClick', value='OtraForma')
    check('E5 uno con otra forma: DSGN-088 con las dos firmas legibles, nada escrito',
          mc.abre(r, 'SR_DESIGNER_SET_EVENTO_FMT') and dice(r, 'SF_MANEJADOR_OTRA_FIRMA_FMT') and
          'procedure(TObject; Integer)' in r and 'procedure(TObject)' in r and bytes_de(DFM) == antes, r[:400])
    r = dsg(command='set', path=DFM, component='Boton1', prop='OnClick', value='DeClase')
    check('E6 uno de clase: DSGN-088 (de clase), nada escrito',
          mc.abre(r, 'SR_DESIGNER_SET_EVENTO_FMT') and dice(r, 'SF_MANEJADOR_DE_CLASE_FMT') and
          bytes_de(DFM) == antes, r[:400])
    r = dsg(command='set', path=DFM, component='Boton1', prop='OnClick', value="'Boton1Click'")
    check('E7 un valor que no es un nombre: DSGN-088 (no es el nombre de un metodo), nada escrito',
          mc.abre(r, 'SR_DESIGNER_SET_EVENTO_FMT') and dice(r, 'SF_MANEJADOR_NO_ES_NOMBRE_FMT') and
          bytes_de(DFM) == antes, r[:400])
    r = dsg(command='set', path=DFM, component='Edicion1', prop='OnKeyPress', value='Edicion1KeyPress')
    check('E8 OnKeyPress (procedure(TObject; var Char)): enlazado',
          not mc.fallo(r) and 'OnKeyPress = Edicion1KeyPress' in [l.strip() for l in bloque(DFM, 'Edicion1')],
          r[:400])
    r = dsg(command='set', path=DFM, component='Boton1', prop='OnClick', value='nil')
    check('E9 nil quita la linea (removed)',
          not mc.fallo(r) and (mc.como_json(r) or {}).get('removed') is True and
          not any(l.strip().startswith('OnClick') for l in bloque(DFM, 'Boton1')), r[:400])

    # a mano, como lo dejaria un agente con delphi_edit: el boton a un manejador de otra forma
    texto = mc.lee(DFM)
    nuevo = re.sub(r'(\r?\n(\s+)object Boton1: TButton\r?\n)', r'\1\2  OnClick = OtraForma\r\n', texto, count=1)
    with open(DFM, 'w', encoding='utf-8-sig' if bytes_de(DFM).startswith(b'\xef\xbb\xbf') else 'utf-8',
              newline='') as f:
        f.write(nuevo)
    check('fixture: la linea a mano', nuevo != texto)
    r = dsg(command='check-binding', path=DFM)
    j = mc.como_json(r) or {}
    otras = j.get('eventsWithOtherSignature') or []
    check('E10 check-binding: eventsWithOtherSignature con el de otra forma, clean false. ROJO contra c166',
          j.get('clean') is False and len(otras) == 1 and 'OtraForma' in otras[0] and
          dice(otras[0], 'SF_DSGN_OTRA_FIRMA_FMT'), r[:800])
    r = dsg(command='lint', path=DFM)
    check('E11 ...y el lint lo dice', 'OtraForma' in r and dice(r, 'SF_MANEJADOR_OTRA_FIRMA_FMT'), r[:800])

    # la clase del form desciende de una base de OTRA unidad (que el .pas no declara)
    O = proyecto('VclHeredado', 'project-vcl')
    ODFM, OPAS = os.path.join(O, 'UMain.dfm'), os.path.join(O, 'UMain.pas')
    r = dsg(command='insert', path=ODFM, classname='TButton', component='Boton1')
    check('fixture: insert en el heredado', not mc.fallo(r), r[:200])
    texto = mc.lee(OPAS)
    nuevo = re.sub(r'= class\(TForm\)', '= class(TBaseDeOtraUnidad)', texto, count=1)
    with open(OPAS, 'w', encoding='utf-8-sig' if bytes_de(OPAS).startswith(b'\xef\xbb\xbf') else 'utf-8',
              newline='') as f:
        f.write(nuevo)
    check('fixture: la base de otra unidad', nuevo != texto)
    r = dsg(command='set', path=ODFM, component='Boton1', prop='OnClick', value='EnLaBase')
    check('E12 la cadena sale a una base de otra unidad: DSGN-088 (no se ve alli)',
          mc.abre(r, 'SR_DESIGNER_SET_EVENTO_FMT') and dice(r, 'SF_MANEJADOR_FUERA_FMT') and
          'TBaseDeOtraUnidad' in r, r[:400])

    # ------------------------------------------------------------------ FMX
    F = proyecto('Fmx', 'project-fmx')
    FMX, FPAS = os.path.join(F, 'UMain.fmx'), os.path.join(F, 'UMain.pas')
    r = dsg(command='insert', path=FMX, classname='TEdit', component='Edicion1')
    check('fixture: insert FMX', not mc.fallo(r), r[:200])
    metodo(FPAS, 'procedure Edicion1KeyDown(Sender: TObject; var Key: Word; var KeyChar: Char; '
                 'Shift: TShiftState);\nbegin\nend;')
    metodo(FPAS, 'procedure Edicion1Click(Sender: TObject);\nbegin\nend;')
    r = dsg(command='set', path=FMX, component='Edicion1', prop='OnKeyDown', value='Edicion1KeyDown')
    check('F1 FMX: OnKeyDown con var KeyChar: Char (TKeyEvent dice WideChar): enlazado. ROJO contra c166',
          not mc.fallo(r) and 'OnKeyDown = Edicion1KeyDown' in [l.strip() for l in bloque(FMX, 'Edicion1')],
          r[:400])
    antes = bytes_de(FMX)
    r = dsg(command='set', path=FMX, component='Edicion1', prop='OnKeyDown', value='Edicion1Click')
    check('F2 FMX: uno de OnClick en OnKeyDown: DSGN-088 con la firma del evento, nada escrito',
          mc.abre(r, 'SR_DESIGNER_SET_EVENTO_FMT') and dice(r, 'SF_MANEJADOR_OTRA_FIRMA_FMT') and
          'var WideChar' in r and bytes_de(FMX) == antes, r[:400])
    r = dsg(command='prop', classname='TEdit', framework='fmx', prop='OnKeyDown')
    check('F3 prop de un evento: la firma de su manejador',
          (mc.como_json(r) or {}).get('signature') == 'procedure(TObject; var Word; var WideChar; TShiftState)',
          r[:400])
finally:
    srv.cierra()
    mc.borra(BASE)

mc.fin('set de un evento 1.29 (C7)')
