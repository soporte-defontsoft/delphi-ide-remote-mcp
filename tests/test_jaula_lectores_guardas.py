"""Guardas de los lectores auditados: victima fuera, respuestas y bytes."""
import os
import mcp_cliente as mc
from mcp_cliente import check
BASE = mc.carpeta('jaula-lectores-guardas')
MINE, OUT = [os.path.join(BASE, n) for n in ('mio', 'victima')]
os.makedirs(MINE)
os.makedirs(OUT)
FILES = {
    'JaulaVictima.pas': "unit JaulaVictima;\ninterface\nimplementation\nStyleLookup := 'JaulaVictimaLookup';\nend.\n",
    'JaulaVictima.fmx': "object JaulaVictima: TForm\n StyleLookup = 'JaulaVictimaLookup'\nend\n",
    'copia.txt': 'privado',
    'copia.txt.by': 'JaulaVictimaDueno',
}
for n, t in FILES.items():
    open(os.path.join(OUT, n), 'w').write(t)
before = {n: open(os.path.join(OUT, n), 'rb').read() for n in FILES}
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': MINE}), nombre='jaula-lectores-guardas')
LINK = os.path.join(MINE, 'enlace')
check('fixture junction a victima de fuera', mc.junction(LINK, OUT))
try:
    STYLE = os.path.join(MINE, 'Local.style')
    open(STYLE, 'w').write("object Local: TLayout\n StyleName = 'local'\nend\n")
    r = srv.call('delphi_styles', {'command': 'lint', 'path': STYLE, 'project': MINE})
    check('Styles: filtro previo no muestra nombres de fuera', not mc.fallo(r) and
          not mc.sin_respuesta(r) and 'JaulaVictima' not in r, r)
    DELETE = os.path.join(MINE, 'borrar')
    os.makedirs(DELETE)
    DLINK = os.path.join(DELETE, 'enlace')
    check('fixture junction en carpeta por borrar', mc.junction(DLINK, OUT))
    try:
        r = srv.call('delphi_delete', {'path': DELETE})
        check('delete carpeta no muestra nombres de fuera', not mc.sin_respuesta(r) and
              'JaulaVictima' not in r, r)
    finally:
        if os.path.exists(DLINK):
            os.rmdir(DLINK)
    TRASH = os.path.join(MINE, '__delphi-patch', '20990101', 'deleted', 'carpeta')
    os.makedirs(TRASH)
    TLINK = os.path.join(TRASH, 'enlace')
    check('fixture junction en papelera propia', mc.junction(TLINK, OUT))
    try:
        r = srv.call('delphi_delete', {'path': TRASH, 'purge': True})
        check('purge no lee ni anuncia el dueno de fuera', not mc.sin_respuesta(r) and
              'JaulaVictima' not in r, r)
    finally:
        if os.path.exists(TLINK):
            os.rmdir(TLINK)
    check('victima conserva nombres y bytes', sorted(os.listdir(OUT)) == sorted(FILES) and
          all(open(os.path.join(OUT, n), 'rb').read() == t for n, t in before.items()))
finally:
    srv.cierra()
    os.rmdir(LINK)
mc.fin('jaula lectores guardas')
