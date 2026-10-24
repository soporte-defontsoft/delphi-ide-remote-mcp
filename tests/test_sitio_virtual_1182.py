# -*- coding: utf-8 -*-
"""2ae de la 1.18.2 (re-revision del 2i, medido): una entrada de ReadOnlyPaths
escrita con la unidad VIRTUAL que ven los agentes (srvc:\\...) - el operador
copia lo que le ensena un agente - pasaba por RELATIVA: se pegaba a cada raiz
('<raiz>\\srvc:\\...'), se cargaba, no protegia nada y el aviso del arranque
hablaba de "una entrada fuera de las raices". Ahora el lector de entradas
(EntradaDeSitio) la deja fuera por EL reconocedor de esa forma
(EmpiezaPorUnidadVirtual) y, como toda proteccion que no se carga, su
workspace no admite a nadie hasta que se arregle (fail closed); el aviso lo
dice.

  V1 ReadOnlyPaths=srvc:\\...\\prot: escribir en prot NO pasa (ROJO en
     produccion: se escribia), y es el CIERRE del workspace: tampoco fuera de
     prot (miraba solo que a.txt no estuviera, y pasaba con la sesion caida:
     J7 del revisor de cierre); y lo que contesta lo dice: 403 SYS-034, el
     token es bueno y su workspace esta cerrado - era el 401 de SYS-017,
     "token invalido" (J9 del revisor de cierre, ROJO en produccion)
  V4 control: un token que no es de nadie sigue siendo 401 SYS-017
  V2 el aviso del arranque dice que es la forma virtual
  V3 control: la misma entrada con su letra protege prot y el workspace
     funciona (se escribe fuera de prot, no dentro)

Uso:  python tests/test_sitio_virtual_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('sitio_virtual_1182')


def servidor(nombre, ro):
    srv = os.path.join(BASE, nombre, 'srv')
    exe = mc.copia_exe(srv)
    jail = os.path.join(BASE, nombre, 'jail')
    prot = os.path.join(jail, 'prot')
    os.makedirs(prot)
    token = 'sitiovirtual-%s-0123456789' % nombre
    puerto = mc.puerto_libre()
    with open(os.path.join(srv, 'settings.ini'), 'w') as f:
        f.write('[Server]\nPort=%d\nBindIP=127.0.0.1\n\n[Workspace.W]\nToken=%s\nRoots=%s\nReadOnlyPaths=%s\n'
                % (puerto, token, jail, ro(prot)))
    proc = mc.lanza_http(exe, None, mc.entorno(), espera_en=puerto)
    return srv, jail, prot, token, puerto, proc


def intenta(puerto, token, ruta):
    try:
        op = mc.Http(puerto, token, t=60)
        op.session('ana')
        return op.call('delphi_textedit', {'path': ruta, 'create': True, 'content': 'x'})
    except Exception as e:
        return 'EXCEPCION %s' % e


def log_de(srv):
    t = ''
    for d, _, fs in os.walk(srv):
        for f in fs:
            if f.endswith('.log'):
                t += open(os.path.join(d, f), encoding='utf-8', errors='replace').read()
    return t


srv, jail, prot, token, puerto, proc = servidor('v1', lambda p: 'srv' + p[0].lower() + ':' + p[2:])
try:
    r = intenta(puerto, token, os.path.join(prot, 'a.txt'))
    fuera = intenta(puerto, token, os.path.join(jail, 'b.txt'))
    check('V1 ReadOnlyPaths con la unidad virtual: el workspace se CIERRA (403 SYS-034, que lo dice), ni en prot '
          'ni fuera', not os.path.exists(os.path.join(prot, 'a.txt')) and
          not os.path.exists(os.path.join(jail, 'b.txt')) and
          all('403' in x and 'SYS-034' in x and '[Workspace.W]' in x for x in (r, fuera)), (r[:300], fuera[:300]))
    otro = intenta(puerto, 'no-es-de-nadie-0123456789', os.path.join(jail, 'c.txt'))
    check('V4 control: un token que no es de nadie sigue siendo 401 SYS-017',
          '401' in otro and 'SYS-017' in otro and not mc.es(otro, 'SR_SYS_WORKSPACE_CERRADO_FMT'), otro[:300])
finally:
    proc.kill()
check('V2 el aviso del arranque dice que es la forma virtual de los agentes',
      'VIRTUAL form the agents see' in log_de(srv), log_de(srv)[-600:])

srv, jail, prot, token, puerto, proc = servidor('v3', lambda p: p)
try:
    dentro = intenta(puerto, token, os.path.join(prot, 'a.txt'))
    fuera = intenta(puerto, token, os.path.join(jail, 'b.txt'))
    check('V3 control: con su letra protege prot y el workspace escribe fuera de prot',
          not os.path.exists(os.path.join(prot, 'a.txt')) and os.path.exists(os.path.join(jail, 'b.txt')),
          (dentro[:200], fuera[:200]))
finally:
    proc.kill()

mc.borra(BASE)
mc.fin('ReadOnlyPaths con la unidad virtual 1182 (2ae)')
