# -*- coding: utf-8 -*-
"""Lo que es una copia muerta y un artefacto, en UNA casa (A10 de la 1.23).

Las copias muertas del IDE (__history, __recovery) se reconocian a mano en
tres sitios con tres formas: la puerta de escribir (GUARD-005), la segunda
barrera de delphi_edit (EDIT-033, el mismo hecho con otro codigo, y la
papelera, EDIT-065 frente a GUARD-004: medido que no se alcanzan, la puerta
de la jaula va antes tambien en una tanda; la barrera se queda, preguntando
lo mismo) y el buscador de las fuentes de una unit que falta (FuentesBajo),
que ademas se saltaba toda carpeta cuya ruta
llevase '\\backup' - una gramatica propia, sin juez: el IDE no escribe
carpetas "backup", y casaba con \\BackupService\\ - y juzgaba los artefactos
por la ruta ABSOLUTA, asi que una raiz que cuelga de una carpeta Release no
daba ninguna candidata (la regla de SkipBajoLaRaiz, M1 de la 1.18.2, que aqui
no estaba).

  C1  (control) la unit de una carpeta vendor de la raiz tiene su carpeta
      como candidata (BUILD-042)
  C2  ...y la de una carpeta \\BackupService\\ tambien: no es una copia
  C3  ...y la de una raiz que cuelga de una carpeta Release tambien: lo que
      es un artefacto se juzga bajo la raiz
  C4  (guarda) una TANDA de delphi_edit sobre un fuente de __history:
      GUARD-005, el mismo codigo que una edicion suelta, y nada escrito
  C5  (guarda) ...sobre una copia de la papelera: GUARD-004
  C6  (guarda) la edicion suelta sobre __history: GUARD-005
  C7  (guarda, V112 de la 1.23.1) crear POR una union de la raiz a la carpeta
      del dia de la papelera: GUARD-004 y nada en ella (la guarda miraba solo
      el texto, y el fichero quedaba plantado donde restore lo traeria)
  C8  ...y editar una copia por esa union: GUARD-004 y nada escrito

Usage:  python tests/test_copias_y_artefactos_1230.py [path-to-DelphiLspMcp.exe]
"""
import os, json, glob
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('copias_1230')
JAIL = os.path.join(BASE, 'jail')
# una segunda raiz que cuelga de una carpeta llamada Release
REL = os.path.join(BASE, 'Release', 'jail2')
for d in (JAIL, REL):
    os.makedirs(d)


def unidad(nombre):
    return ('unit %s;\n\ninterface\n\nfunction Dame: Integer;\n\nimplementation\n\n'
            'function Dame: Integer;\nbegin\n  Result := 1;\nend;\n\nend.\n' % nombre)


def escribe(p, texto):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'w', encoding='utf-8', newline='\r\n').write(texto)


escribe(os.path.join(JAIL, 'vendor', 'UVendorC.pas'), unidad('UVendorC'))
escribe(os.path.join(JAIL, 'BackupService', 'UBackupC.pas'), unidad('UBackupC'))
escribe(os.path.join(REL, 'vendor', 'UReleaseC.pas'), unidad('UReleaseC'))

EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL + ';' + REL}), nombre='copias_1230', t=300)


def candidatas(dproj, unit):
    """Las carpetas candidatas de la unit que falta (BUILD-042), por su nombre, y el texto del build."""
    r = srv.call('delphi_build', {'project': dproj, 'platform': 'Win64', 'config': 'Debug'}, t=300)
    j = mc.como_json(r)
    m = next((x for x in (j.get('missingUnits') or []) if x.get('unit') == unit), {})
    return [os.path.basename(mc.real(d).rstrip('\\')) for d in m.get('sourceFolders', [])], r


try:
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'PCopias', 'dir': os.path.join(JAIL, 'P')})
    dprs = glob.glob(os.path.join(JAIL, 'P', '**', 'PCopias.dpr'), recursive=True)
    check('C1 (preparacion) el proyecto de consola nace', bool(dprs), r[:300])
    if dprs:
        DPR = dprs[0]
        DPROJ = DPR[:-4] + '.dproj'
        DPR_0 = open(DPR, encoding='utf-8-sig').read()
        # ------------------------------------------------------------------ C1-C3
        # una unit que falta por build: F2613 para el compilador en la primera
        for unit, carpeta, que in (
                ('UVendorC', 'vendor', 'C1 (control) la unit de una carpeta vendor de la raiz: su carpeta es candidata'),
                ('UBackupC', 'BackupService', 'C2 ...y la de una carpeta \\BackupService\\ tambien: no es una copia'),
                ('UReleaseC', 'vendor', 'C3 ...y la de una raiz que cuelga de una carpeta Release tambien: el '
                                        'artefacto se juzga bajo la raiz')):
            open(DPR, 'w', encoding='utf-8').write(DPR_0.replace('uses', 'uses\n  %s,' % unit, 1))
            cs, r = candidatas(DPROJ, unit)
            check(que, carpeta in cs, (cs, r[:300]))
        open(DPR, 'w', encoding='utf-8').write(DPR_0)

        # ------------------------------------------------------------------ C4-C6
        HIST = os.path.join(os.path.dirname(DPR), '__history', 'UHist.pas')
        escribe(HIST, unidad('UHist'))
        PAPEL = os.path.join(os.path.dirname(DPR), mc.PAPELERA, '20261023', 'UPapel.pas')
        escribe(PAPEL, unidad('UPapel'))
        tanda = json.dumps([{'old': 'function Dame: Integer;', 'new': 'function Dame: Integer; // x', 'occurrence': 1}])
        for p, msg, que in ((HIST, 'SR_GUARD_DEAD_IDE', 'C4 (guarda) una TANDA sobre un fuente de __history: '
                                                         'GUARD-005 y nada escrito'),
                            (PAPEL, 'SR_GUARD_DEAD_TRASH', 'C5 (guarda) ...sobre una copia de la papelera: '
                                                           'GUARD-004 y nada escrito')):
            antes = open(p, 'rb').read()
            r = srv.call('delphi_edit', {'path': p, 'edits': json.loads(tanda)})
            check(que, mc.abre(r, msg) and open(p, 'rb').read() == antes, r[:300])
        antes = open(HIST, 'rb').read()
        r = srv.call('delphi_edit', {'path': HIST, 'old': 'unit UHist;', 'new': 'unit UHist; // x'})
        check('C6 (guarda) la edicion suelta sobre __history: GUARD-005',
              mc.abre(r, 'SR_GUARD_DEAD_IDE') and open(HIST, 'rb').read() == antes, r[:300])

        # ------------------------------------------------------------------ C7-C8
        LNK = os.path.join(JAIL, 'lnk-papelera')
        check('C7 (preparacion) la union de la raiz a la carpeta del dia de la papelera',
              mc.junction(LNK, os.path.dirname(PAPEL)), LNK)
        try:
            r = srv.call('delphi_textedit', {'path': os.path.join(LNK, 'plantado.txt'), 'create': True,
                                             'content': 'x'})
            check('C7 (guarda) crear POR la union en la papelera: GUARD-004 y nada en ella',
                  mc.abre(r, 'SR_GUARD_DEAD_TRASH') and
                  not os.path.exists(os.path.join(os.path.dirname(PAPEL), 'plantado.txt')), r[:300])
            antes = open(PAPEL, 'rb').read()
            r = srv.call('delphi_edit', {'path': os.path.join(LNK, 'UPapel.pas'), 'old': 'unit UPapel;',
                                         'new': 'unit UPapel; // x'})
            check('C8 (guarda) editar una copia POR la union: GUARD-004 y nada escrito',
                  mc.abre(r, 'SR_GUARD_DEAD_TRASH') and open(PAPEL, 'rb').read() == antes, r[:300])
        finally:
            if os.path.isdir(LNK):
                os.rmdir(LNK)  # quita el ENLACE, no lo de detras
finally:
    srv.cierra()

mc.fin('copias y artefactos 1.23.0 battery')
