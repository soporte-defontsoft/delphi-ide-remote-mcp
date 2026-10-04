"""ReadOnlyPaths protege su descendencia por nombres largos y alias 8.3."""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('readonly-rutas-83')
CAJA = os.path.join(BASE, 'contenedor-largo')
DEST = os.path.join(BASE, 'destino-real')
os.makedirs(CAJA)
os.makedirs(DEST)
RAIZ = os.path.join(CAJA, 'proyecto-enlace')
check('fixture junction local', mc.junction(RAIZ, DEST))
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
LARGA = mc.larga(CAJA)
CORTA = mc.corta(CAJA)
HAY83 = bool(CORTA and CORTA.lower() != LARGA.lower())
AVISO = mc.catalogo()['SL_GUARD_SOLO_LECTURA_FUERA_FMT'].split('%s')[1]
check('fixture forma larga independiente del TEMP', '~' not in LARGA, LARGA)
if not HAY83:
    print('NOTA: este volumen no da un alias 8.3 distinto; solo forma larga')
try:
    formas = [('larga', LARGA)]
    if HAY83:
        formas.append(('corta', CORTA))
    for etiqueta, proteccion in formas:
        for nombre, raiz in formas:
            # La raiz de este caso es un junction dentro del contenedor.
            jail = os.path.join(raiz, 'proyecto-enlace')
            srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': jail,
                'DELPHI_MCP_READONLY_PATHS': proteccion}), nombre='ro-rutas-83', lee_stderr=True)
            try:
                for acceso, ruta in [('larga', mc.larga(jail)),
                                     ('corta', mc.corta(jail) or jail)]:
                    leaf = 'no-escribir-%s-%s-%s.txt' % (etiqueta, nombre, acceso)
                    path = os.path.join(ruta, leaf)
                    out = srv.call('delphi_textedit', {'path': path,
                        'create': True, 'content': 'no escribir'})
                    check('proteccion %s / raiz %s / acceso %s deniega' % (etiqueta, nombre, acceso),
                          mc.es(out, 'SR_READONLY_PATH_FMT') and
                          not os.path.exists(os.path.join(DEST, leaf)), out)
                check('proteccion %s / raiz %s no dice que esta fuera' % (etiqueta, nombre),
                      not any(AVISO in s for s in srv.errores), srv.errores)
            finally:
                srv.cierra()
                # El baseline rojo puede dejar el fichero: cada caso es independiente.
                for acceso in ('larga', 'corta'):
                    f = os.path.join(DEST, 'no-escribir-%s-%s-%s.txt' % (etiqueta, nombre, acceso))
                    if os.path.exists(f):
                        os.remove(f)
    srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': DEST,
        'DELPHI_MCP_READONLY_PATHS': CAJA}), nombre='ro-fuera-control', lee_stderr=True)
    try:
        check('control: una entrada realmente fuera SI deja aviso',
              any(AVISO in s for s in srv.errores), srv.errores)
        permitido = os.path.join(DEST, 'control-escribible.txt')
        out = srv.call('delphi_textedit', {'path': permitido, 'create': True, 'content': 'control'})
        check('control: sin proteccion que lo contenga SI escribe',
              not mc.fallo(out) and os.path.isfile(permitido), out)
        if os.path.exists(permitido):
            os.remove(permitido)
    finally:
        srv.cierra()
    check('destino intacto tras todas las peticiones', os.listdir(DEST) == [])
finally:
    os.rmdir(RAIZ)
    mc.borra(BASE)
mc.fin('readonly rutas 83')
