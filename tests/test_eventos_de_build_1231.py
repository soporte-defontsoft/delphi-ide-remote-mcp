# -*- coding: utf-8 -*-
r"""Los eventos de build (V18 de la 1.23.1): el aviso buildEventsSkipped dice que se salto lo que
se HABRIA ejecutado. El juez son los targets del IDE, no una lista: en la 37.0 (medido)
CodeGear.Common.Targets ejecuta $(PreBuildEvent) y $(PostBuildEvent), $(PreLinkEvent) solo lo
ejecuta CodeGear.Cpp.Targets, y PostLinkEvent y BuildEvent ninguno. La DEFENSA no cambia: un
evento con texto, sea el que sea, se vacia en la orden de msbuild y nunca corre.

  E1 solo un PostLinkEvent con texto: compila y NO dice buildEventsSkipped (ROJA contra 519a945:
     lo decia de un evento que el IDE tampoco habria ejecutado); el evento no corre
  E2 solo un BuildEvent: igual (roja)
  E3 solo un PreLinkEvent (los targets de Delphi no lo ejecutan): igual (roja)
  E4 control: un PreBuildEvent: compila, lo dice y no corre
  E5 control: PostBuildEvent + PostLinkEvent: lo dice (uno de los dos se habria ejecutado)

Uso:  python tests/test_eventos_de_build_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('eventos-build')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='ev', t=600)

try:
    carpeta = os.path.join(BASE, 'fixture')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
    check('fixture creada (delphi_create)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    proyecto = os.path.join(carpeta, 'Fixture.dproj')
    with open(proyecto, encoding='utf-8-sig') as f:
        ORIGINAL = f.read()
    assert '<Import Project=' in ORIGINAL, ORIGINAL[:200]
    marca = os.path.join(carpeta, 'marca.txt')

    def con(eventos):
        """El .dproj del IDE con un grupo de eventos delante del primer Import: cada evento
        escribiria la marca si corriese."""
        grupo = '<PropertyGroup>%s</PropertyGroup>\r\n    ' % ''.join(
            '<%s>cmd /c echo x &gt; "%s"</%s>' % (e, marca, e) for e in eventos)
        i = ORIGINAL.index('<Import Project=')
        with open(proyecto, 'w', encoding='utf-8-sig', newline='') as f:
            f.write(ORIGINAL[:i] + grupo + ORIGINAL[i:])

    for nombre, eventos, avisa in (('E1', ['PostLinkEvent'], False),
                                   ('E2', ['BuildEvent'], False),
                                   ('E3', ['PreLinkEvent'], False),
                                   ('E4', ['PreBuildEvent'], True),
                                   ('E5', ['PostBuildEvent', 'PostLinkEvent'], True)):
        if os.path.exists(marca):
            os.remove(marca)
        con(eventos)
        out = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64', 'config': 'Debug'}, 600)
        j = mc.como_json(out)
        caso = '%s %s' % (nombre, '+'.join(eventos))
        check('%s: compila' % caso, j.get('success') is True, out[:300])
        check('%s: %s buildEventsSkipped' % (caso, 'dice' if avisa else 'NO dice'),
              (j.get('buildEventsSkipped') is True) == avisa, out[:300])
        check('%s: el evento no corre (sin marca)' % caso, not os.path.exists(marca), marca)
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('eventos de build 1.23.1 (V18)')
