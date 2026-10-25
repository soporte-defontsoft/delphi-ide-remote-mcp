# -*- coding: utf-8 -*-
"""Lo que escriben el conversor y brcc32 en delphi_styles build (1.18.2, 2s).

build convierte cada .style de texto a <n>.bin.style y compila el .rc a .res
con procesos EXTERNOS. La puerta solo miraba la CARPETA y cada proceso abria
su fichero de salida el mismo (TFileStream fmCreate, brcc32 -fo): lo que la
jaula dice de ESE fichero no lo preguntaba nadie. Ahora escriben en un
temporal del servidor y el derivado lo coloca EL escritor de un producto
(Lsp.Patch.ColocaProducto: la puerta en el momento de escribir, la copia
sellada de lo que habia y el renombre), y antes de lanzar nada se pregunta
por TODOS los destinos, por los .style que lee el conversor y por el .rc: una
negativa no deja nada a medias. La carpeta tiene DOS estilos: lo que se
convertiria antes de la negativa es el otro.

  S1  una entrada de ReadOnlyPaths que nombra Bat.bin.style: GUARD-012 ANTES de
      convertir nada (Otro.bin.style no nace), Bat.bin.style intacto y sin .res
  S2  ...que nombra el .res: GUARD-012 antes de convertir (ningun .bin.style nace)
  S3  el .bin.style es un HARDLINK de un fichero de FUERA de las raices: desde
      la 1.21.1, GUARD-041/042 ANTES de convertir (colocar copia antes lo que
      habia, y copiarlo era leer el de fuera), la victima intacta y sus
      bytes fuera de la papelera; hasta la 1.21.0 se sustituia y la copia
      sellada se los llevaba
  S4  ...y el .res, igual
  S5  un .bin.style con el atributo +R: su negativa (SYS-029), no un error del
      conversor
  S6  lo que habia en un derivado de UN nombre se puede recuperar: la copia
      sellada en la papelera
  S7  nada del proceso se queda: ni temporales en la carpeta de estilos ni la
      carpeta de la llamada en la temporal del servidor
  S8  un .style que es un enlace a uno de FUERA: la puerta de leer antes de que
      el conversor lo lea (sin el privilegio de crear un enlace de fichero, NOTA)
  S9  un .bin.style que es una CARPETA: LSP-016 antes de convertir (salia SYS-028
      tras cinco reintentos, con el otro ya colocado; revisor del 2s)
  S10 un .rc que nombra un fichero de fuera: STYLE-023 antes de convertir (se
      preguntaba despues, con los .bin.style ya colocados; revisor del 2s)
  S11 un servidor MAS HONDO que la jaula y un estilo de nombre largo que su
      destino admite: convierte (la temporal con el nombre del estilo no lo
      cabia, y el error ensenaba la casa por dentro; revisor del 2s)
  S12 un estilo que no convierte: tampoco queda nada en la temporal
  S13 una linea DISCARDABLE a la CASA del servidor: desde el 3c del censo de
      jueces (1.20.2) la ve la SEGUNDA barrera (EL lector del .rc, LeeRc, por
      tokens): STYLE-023 y ningun .res; antes la gramatica no la veia y la
      paraba solo el contenedor (2al)
  S14 ...y una macro #define a la casa del servidor: la lectura no sigue el
      preprocesador, pero lo que nombra una directiva si lo juzga (H1 de la
      1.20.2): STYLE-023 y ningun .res
  H1  un #define a un fichero world-readable del SO (C:/Windows, que el
      AppContainer concede): la segunda barrera lo niega y el .res no lo lleva
  S15 el CONTENEDOR solo (S13/S14/S16 los para ya la barrera): un absoluto a
      un fichero de la PROPIA carpeta de estilos pasa la barrera, y brcc32, que
      solo ve la copia de la etapa, no lo abre
  S16 un '..' que desde la jaula se queda dentro y desde la ETAPA (la copia de
      la carpeta en la casa del servidor) sube - a la casa, y a un fichero
      world-readable del SO (etc\\hosts, que el AppContainer concede y entraba:
      medido) -: STYLE-052, todo dentro de la carpeta de estilos (CHAPUZA
      TEMPORAL de la 1.20.2, David 18-oct, hasta el token LPAC de la 1.22)

Uso:  python tests/test_estilos_derivados_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import ctypes, glob, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('estilos_derivados_1182')
VICTIMA = mc.carpeta('estilos_derivados_1182-victima')  # FUERA de la raiz
JAIL = os.path.join(BASE, 'jail')
STY = os.path.join(JAIL, 'Styles')
os.makedirs(STY)
SRVDIR = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRVDIR, con_conversor=True)

STYLE = """object TStyleContainer
  object TStyleDescription
    StyleName = 'Description'
    Title = 'Derivados'
    Version = '1.0'
  end
  object TLayout
    StyleName = 'cardstyle'
    Size.Width = 100.000000000000000000
    object TRectangle
      StyleName = 'background'
      Fill.Color = xFFFFFFFF
    end
  end
end
"""
SRC = os.path.join(STY, 'Bat.style')
BIN = os.path.join(STY, 'Bat.bin.style')
RC = os.path.join(STY, 'Bat.Estilos.rc')
RES = os.path.join(STY, 'Bat.Estilos.res')
open(SRC, 'w', encoding='utf-8', newline='\n').write(STYLE)
OTRO_BIN = os.path.join(STY, 'Otro.bin.style')
open(os.path.join(STY, 'Otro.style'), 'w', encoding='utf-8', newline='\n').write(STYLE)
open(RC, 'w', encoding='utf-8').write('BAT RCDATA "Bat.bin.style"\n')
VIEJO = b'NO SOY UN ESTILO: lo que habia'


def bytes_de(p):
    return open(p, 'rb').read() if os.path.exists(p) else None


def limpia():
    for p in (BIN, RES, OTRO_BIN):
        mc.solo_lectura_quita(p)
        if os.path.lexists(p):
            os.remove(p)


def build(srv):
    return srv.call('delphi_styles', {'path': STY, 'command': 'build'})


def arranca(solo=''):
    env = {'DELPHI_MCP_ROOTS': JAIL}
    if solo:
        env['DELPHI_MCP_READONLY_PATHS'] = solo
    return mc.Stdio(EXE, mc.entorno(env), nombre='estilos', t=120)


def hardlink(enlace, original):
    return bool(ctypes.windll.kernel32.CreateHardLinkW(enlace, original, None))


# --------------------------- S1/S2: ReadOnlyPaths nombra un derivado
for clave, ro in (('S1', BIN), ('S2', RES)):
    limpia()
    open(ro, 'wb').write(VIEJO)
    srv = arranca(ro)
    try:
        r = build(srv)
        otros = [p for p in (BIN, RES, OTRO_BIN) if p != ro]
        check('%s ReadOnlyPaths nombra %s: GUARD-012 antes de convertir, el fichero intacto y nada mas nace'
              % (clave, os.path.basename(ro)),
              mc.abre(r, 'SR_READONLY_PATH_FMT') and bytes_de(ro) == VIEJO and
              not [p for p in otros if os.path.exists(p)],
              (r[:300], bytes_de(ro)[:20] if bytes_de(ro) else None, [p for p in otros if os.path.exists(p)]))
    finally:
        srv.cierra()

# --------------------------- S3/S4: un hardlink a una victima de fuera
srv = arranca()
try:
    for clave, derivado in (('S3', BIN), ('S4', RES)):
        limpia()
        victima = os.path.join(VICTIMA, clave + '.dat')
        open(victima, 'wb').write(VIEJO)
        if not hardlink(derivado, victima):
            check('%s el hardlink de la prueba se crea' % clave, False, ctypes.GetLastError())
            continue
        r = build(srv)
        otros = [p for p in (BIN, RES, OTRO_BIN) if p != derivado and os.path.exists(p)]
        check('%s %s es un hardlink de un fichero de fuera: GUARD-041/042 antes de convertir, la victima '
              'intacta y nada nace' % (clave, os.path.basename(derivado)),
              (mc.abre(r, 'SR_JAIL_ENLACE_DURO_FMT') or mc.abre(r, 'SR_JAIL_ENLACE_DURO_SIN_NOMBRES_FMT')) and
              bytes_de(victima) == VIEJO and not otros, (r[:300], bytes_de(victima)[:20], otros))
        copias = glob.glob(os.path.join(STY, mc.PAPELERA, '**', os.path.basename(derivado) + '*'), recursive=True)
        check('%s los bytes de la victima no entran en la papelera' % clave,
              not any(bytes_de(c) == VIEJO for c in copias), copias)
        os.remove(derivado)
        os.remove(victima)

    # --------------------------- S6: lo que habia en un derivado de UN nombre, recuperable
    limpia()
    open(BIN, 'wb').write(VIEJO)
    r = build(srv)
    copias = glob.glob(os.path.join(STY, mc.PAPELERA, '**', 'Bat.bin.style*'), recursive=True)
    check('S6 lo que habia en Bat.bin.style (un nombre) queda en la papelera, sellado, y el derivado es nuevo',
          mc.como_json(r).get('ok') is True and (bytes_de(BIN) or b'').startswith(b'FMX_STYLE') and
          any(bytes_de(c) == VIEJO for c in copias), (r[:300], copias))

    # --------------------------- S5: el +R
    limpia()
    open(BIN, 'wb').write(VIEJO)
    with mc.solo_lectura(BIN):
        r = build(srv)
        check('S5 un .bin.style con +R: SYS-029 antes de convertir (no un error del conversor) y el fichero intacto',
              mc.abre(r, 'SR_SOLO_LECTURA_ATRIBUTO_FMT') and bytes_de(BIN) == VIEJO and
              not os.path.exists(OTRO_BIN), r[:300])

    # --------------------------- S9: el destino es una carpeta
    limpia()
    os.makedirs(BIN)
    r = build(srv)
    check('S9 un .bin.style que es una CARPETA: LSP-016 antes de convertir, y el otro no nace',
          mc.abre(r, 'SR_LSP_IS_FOLDER_FMT') and os.path.isdir(BIN) and not os.path.exists(OTRO_BIN), r[:300])
    os.rmdir(BIN)

    # --------------------------- S10: un .rc que nombra un fichero de fuera
    limpia()
    FUERA_RC = os.path.join(VICTIMA, 'secreto.txt')
    open(FUERA_RC, 'w').write('secreto')
    open(RC, 'w', encoding='utf-8').write('BAT RCDATA "%s"\n' % FUERA_RC)
    r = build(srv)
    check('S10 un .rc que nombra un fichero de fuera: STYLE-023 antes de convertir, y ningun derivado nace',
          mc.abre(r, 'SR_STYLES_RC_OUTSIDE_FMT') and not [p for p in (BIN, RES, OTRO_BIN) if os.path.exists(p)],
          r[:300])
    open(RC, 'w', encoding='utf-8').write('BAT RCDATA "Bat.bin.style"\n')

    # ---------- S13/S14: el .rc que SE SALTA la gramatica (2al): brcc32 en el
    # AppContainer no alcanza lo SENSIBLE. La victima, en la CASA del servidor
    # (SRVDIR, donde vive settings.ini con el token): el contenedor no la lee
    SECRETO = os.path.join(SRVDIR, 'secreto_casa.txt')
    open(SECRETO, 'w').write('SECRETO-2AL ' + 'x' * 40)
    for clave, linea in (('S13 una linea DISCARDABLE', 'X RCDATA DISCARDABLE "%s"' % SECRETO),
                         ('S14 una macro #define', '#define F "%s"\nX RCDATA F' % SECRETO)):
        limpia()
        open(RC, 'w', encoding='utf-8').write(linea + '\n')
        r = build(srv)
        fuga = os.path.exists(RES) and b'SECRETO-2AL' in open(RES, 'rb').read()
        # S13 (lista con bandera) la para la segunda barrera; S14 (#define) ya no
        # es lista y la para antes el juez de lista blanca (V54): sin fuga en el .res
        check('%s a la CASA del servidor: negado y el .res NO la lleva' % clave,
              (mc.abre(r, 'SR_STYLES_RC_OUTSIDE_FMT') or mc.abre(r, 'SR_STYLES_RC_NO_LISTA_FMT')) and not fuga,
              (r[:200], fuga))
    os.remove(SECRETO)
    # H1 (residuo del 2al): un fichero que el SO concede a TODOS LOS PAQUETES DE
    # APLICACIONES (C:\Windows) el AppContainer SI lo lee -> por un #define
    # entraba en el .res. David 18-oct: la segunda barrera mira tambien lo que
    # nombra una directiva (opcion a); lo que componga una macro, el token LPAC
    # (1.21)
    PUBLICO = os.path.join(os.environ.get('WINDIR', r'C:\Windows'), 'System32', 'drivers', 'etc', 'hosts')
    if os.path.exists(PUBLICO) and os.path.getsize(PUBLICO) > 40:
        marca = open(PUBLICO, 'rb').read()
        limpia()
        open(RC, 'w', encoding='utf-8').write('#define F "%s"\nX RCDATA DISCARDABLE F\n' % PUBLICO)
        r = build(srv)
        entra = os.path.exists(RES) and marca in open(RES, 'rb').read()  # su contenido REAL en el .res
        check('H1 un #define a un fichero world-readable del SO (etc\\hosts): la segunda barrera lo niega '
              'negado y el .res NO lo lleva',
              (mc.abre(r, 'SR_STYLES_RC_OUTSIDE_FMT') or mc.abre(r, 'SR_STYLES_RC_NO_LISTA_FMT')) and not entra,
              (r[:200], entra))

    # S15: el CONTENEDOR, solo: un absoluto a un fichero de la PROPIA carpeta -
    # la barrera lo deja (esta dentro) y brcc32, que solo ve la copia de la
    # etapa, no abre el real: confinado no llega ni a lo que el agente lee
    limpia()
    open(RC, 'w', encoding='utf-8').write('X RCDATA "%s"\n' % SRC)
    r = build(srv)
    check('S15 el contenedor: un absoluto a un fichero de la propia carpeta pasa la barrera y brcc32 '
          'confinado no lo abre (solo ve la copia de la etapa)',
          not mc.abre(r, 'SR_STYLES_RC_OUTSIDE_FMT') and not mc.abre(r, 'SR_STYLES_RC_FUERA_DE_CARPETA_FMT') and
          mc.como_json(r).get('ok') is False and 'annot open' in r, r[:300])

    # S16: un '..' que DESDE LA JAULA se queda dentro y desde la ETAPA (la copia
    # de la carpeta en <casa>\<temporal>\styles-rc-X) sube: a la casa, y a un
    # fichero world-readable del SO contando lo hondo que esta la etapa (el
    # contenedor lo concedia y entraba, medido). CHAPUZA TEMPORAL hasta LPAC
    def carpeta_honda(hondo):
        sty = os.path.join(JAIL, *(['h%d' % i for i in range(hondo)] + ['Styles']))
        os.makedirs(sty)
        open(os.path.join(sty, 'Bat.style'), 'w', encoding='utf-8', newline='\n').write(STYLE)
        return sty, os.path.join(sty, 'Bat.Estilos.rc'), os.path.join(sty, 'Bat.Estilos.res')
    HONDA, RC_H, RES_H = carpeta_honda(1)
    open(SECRETO, 'w').write('SECRETO-2AL ' + 'x' * 40)
    open(RC_H, 'w', encoding='utf-8').write('X RCDATA "..\\..\\%s"\n' % os.path.basename(SECRETO))
    r = srv.call('delphi_styles', {'path': HONDA, 'command': 'build'})
    fuga = os.path.exists(RES_H) and b'SECRETO-2AL' in open(RES_H, 'rb').read()
    check('S16 un .. que desde la etapa sube a la CASA: STYLE-052 (fuera de la carpeta de estilos) y el .res '
          'NO la lleva', mc.abre(r, 'SR_STYLES_RC_FUERA_DE_CARPETA_FMT') and not fuga, (r[:300], fuga))
    os.remove(SECRETO)
    PROF = len(os.path.splitdrive(SRVDIR)[1].strip('\\').split('\\')) + 2  # <SRVDIR>\<temporal>\styles-rc-X
    if os.path.exists(PUBLICO) and os.path.splitdrive(SRVDIR)[0].lower() == os.path.splitdrive(PUBLICO)[0].lower():
        HONDA, RC_H, RES_H = carpeta_honda(PROF)
        open(RC_H, 'w', encoding='utf-8').write('X RCDATA "%s%s"\n' % ('..\\' * PROF, os.path.splitdrive(PUBLICO)[1].lstrip('\\')))
        r = srv.call('delphi_styles', {'path': HONDA, 'command': 'build'})
        entra = os.path.exists(RES_H) and open(PUBLICO, 'rb').read() in open(RES_H, 'rb').read()
        check('S16 un .. que desde la etapa llega a un fichero world-readable del SO (etc\\hosts): STYLE-052 y el '
              '.res NO lo lleva', mc.abre(r, 'SR_STYLES_RC_FUERA_DE_CARPETA_FMT') and not entra, (r[:300], entra))
    else:
        print('NOTA S16 (hosts) no se mide: la casa del servidor y %s no estan en la misma unidad' % PUBLICO)
    open(RC, 'w', encoding='utf-8').write('BAT RCDATA "Bat.bin.style"\n')
    open(RC, 'w', encoding='utf-8').write('BAT RCDATA "Bat.bin.style"\n')

    # --------------------------- control y S7
    limpia()
    r = build(srv)
    j = mc.como_json(r)
    check('S0 el control: build convierte y compila el .rc',
          j.get('ok') is True and (bytes_de(BIN) or b'').startswith(b'FMX_STYLE') and os.path.exists(RES), r[:300])
    restos = [f for f in os.listdir(STY) if f.endswith(mc.TEMPORAL_SUSTITUCION_EXT)]
    # la temporal del servidor (la de su exe): ni el derivado ni la carpeta de la llamada
    temporal = glob.glob(os.path.join(SRVDIR, mc.TEMPORALES, '**', '*'), recursive=True)
    check('S7 nada del proceso se queda: ni temporales en la carpeta ni en la temporal del servidor',
          not restos and not [p for p in temporal if p.lower().endswith(('.bin.style', '.res')) or
                              os.path.basename(p).startswith('__tmp-')], (restos, temporal))

    # --------------------------- S8: el .style que se lee, por la puerta de leer
    FUERA = os.path.join(VICTIMA, 'Fuera.style')
    open(FUERA, 'w', encoding='utf-8', newline='\n').write(STYLE)
    ENLACE = os.path.join(STY, 'Fuera.style')
    try:
        os.symlink(FUERA, ENLACE)
        hay_enlace = True
    except OSError:
        hay_enlace = False
    if hay_enlace:
        r = build(srv)
        check('S8 un .style enlazado a uno de fuera: la puerta de leer lo niega y su binario no nace',
              mc.rechazado(r) and not os.path.exists(os.path.join(STY, 'Fuera.bin.style')), r[:300])
        os.remove(ENLACE)  # el enlace, no lo de detras
    else:
        print('NOTA S8 no se mide: esta cuenta no puede crear un enlace de FICHERO (privilegio o modo '
              'desarrollador); lo cierra ReadPathDenied en DerivadosDenegados (Mcp.Tools.Styles)')

    # --------------------------- S12: un estilo que no convierte, y la temporal
    ROTOS = os.path.join(JAIL, 'Rotos')
    os.makedirs(ROTOS)
    open(os.path.join(ROTOS, 'Roto.style'), 'w', encoding='utf-8').write('object TStyleContainer\n  esto no\n')
    r = srv.call('delphi_styles', {'path': ROTOS, 'command': 'build'})
    temporal = glob.glob(os.path.join(SRVDIR, mc.TEMPORALES, '**', '*'), recursive=True)
    check('S12 un estilo que no convierte es un fallo, y en la temporal del servidor no queda la carpeta de la llamada',
          mc.como_json(r).get('ok') is False and
          not [p for p in temporal if os.path.basename(p).startswith('__tmp-')], (r[:300], temporal))
finally:
    srv.cierra()

# --------------------------- S11: el servidor mas hondo que la jaula
LARGOS = os.path.join(JAIL, 'Largos')
os.makedirs(LARGOS)
# el destino, en el limite que admite el escritor atomico (232); la temporal con
# el nombre del estilo pasaria de 259 con el servidor 40 mas hondo que la carpeta
# (medido en la forma LARGA, como lo mide el escritor: %TEMP% llega en 8.3)
TRONCO = 'e' * (232 - len(mc.larga(LARGOS)) - 1 - len('.bin.style'))
open(os.path.join(LARGOS, TRONCO + '.style'), 'w', encoding='utf-8', newline='\n').write(STYLE)
HONDO = os.path.join(BASE, 'srvhondo')
HONDO = os.path.join(HONDO, 'h' * max(1, len(mc.larga(LARGOS)) + 40 - len(mc.larga(BASE)) - len('srvhondo') - 2))
srv = mc.Stdio(mc.copia_exe(HONDO, con_conversor=True), mc.entorno({'DELPHI_MCP_ROOTS': JAIL}),
               nombre='estilos', t=120)
try:
    r = srv.call('delphi_styles', {'path': LARGOS, 'command': 'build'})
    check('S11 un servidor mas hondo que la jaula y un nombre largo que su destino admite: convierte, sin la casa '
          'en la respuesta', mc.como_json(r).get('ok') is True and '<server' not in r and
          os.path.isfile(os.path.join(LARGOS, TRONCO + '.bin.style')), (len(HONDO), r[:400]))
finally:
    srv.cierra()

limpia()
mc.borra(BASE)
mc.borra(VICTIMA)
mc.fin('derivados de delphi_styles build 1182')
