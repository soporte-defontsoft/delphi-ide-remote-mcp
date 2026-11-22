# -*- coding: utf-8 -*-
"""Una ruta que el agente nombra y no existe: TODOS los "no existe" dicen como seguir, con UN texto
(SF_RUTA_NO_EXISTE_SALIDA, Lsp.Texts) - A2 de la 1.29.3, C4/W3 de la 1.29.2.

Medido en el state.db de Hermes (solo lectura, hq_friccion.py): desde la candidata (17-nov 22:48), tras un
WS-008 ("... does not exist: there is no folder and no file with that path.") necesito dos intentos o mas la
mitad de las veces, y tras un LSP-011 (el unico que decia "delphi_list root=<folder> shows what is really there,
and delphi_search finds it by content") casi siempre acerto a la primera. Habia ~25 textos de "no existe", cada
uno con su frase.

  R0 LA regla del catalogo (gramatica PROPIA, declarada aqui: no hay juez que diga que texto nombra una ruta):
     toda constante NOT_FOUND con "<%s> does not exist" / "does not exist: %s" / "not found: %s" lleva la salida
     entera, salvo las EXCEPCIONES de abajo, cada una con su motivo. Una nueva que nazca sin ella falla aqui
  R1 ...y el comprobador sabe fallar: una constante plantada sin la salida sale, una con ella no
  R2-R8 en vivo, una ruta que no existe en search (WS-008), list, edit, edits (EDIT-027), textedit (TEXT-007),
     designer y git (GIT-026): la respuesta trae la salida (ROJOS contra el build sin A2)
  R9 control: delphi_read (LSP-011), que ya la decia, la sigue diciendo igual

Uso:  python tests/test_ruta_no_existe_1293.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

# los "no existe" que NO llevan la salida, y por que (si una deja de serlo, sale de aqui)
EXCEPCIONES = {
    'SR_BUILD_DPROJ_NO_EXISTE_FMT': 'su salida propia: delphi_projects lista los .dproj de las raices',
    'SR_CFG_NO_EXISTE_NO_PUDO_GENERAR_FMT': 'el .deployproj que el servidor intento generar: no lo nombra el agente',
    'SR_CHANGESET_VIRT_MISSING_FMT': 'su salida propia: el orden de las operaciones del mismo lote',
    'SR_CONFIG_DEPLOY_MISSING_FMT': 'su salida propia: delphi_list en la zona de librerias',
    'SR_CONFIG_PATH_MISSING_FMT': 'su salida propia: delphi_list en la zona de librerias',
    'SR_GRUPO_SIN_DPROJ_FMT': 'su salida propia: un proyecto entra en un grupo por su .dproj',
    'SR_JOB_NO_EXISTE_FMT': 'una ruta del DESTINO (lanzador): delphi_list no la ve',
    'SR_PASERVER_NO_PROFILE_FMT': 'un perfil, no una ruta',
    'SR_PROFILE_NO_EXISTE_FMT': 'un perfil, no una ruta',
    'SR_PROJECTS_NO_ROOT_FMT': 'su salida propia: delphi_workspace dice las carpetas reales',
    'SR_RENDER_NO_EXISTE_FMT': 'del renderizador, con la ruta que le da el servidor',
    'SR_STYLES_MISSING_FMT': 'su salida propia: delphi_list pattern=*.style',
    'SR_SYS_METODO_NO_EXISTE_FMT': 'un metodo del protocolo, no una ruta',
    'SR_SYS_RECURSO_NO_EXISTE_FMT': 'un recurso del protocolo, no una ruta',
    'SR_SYS_TOOL_NOT_FOUND_FMT': 'una tool, no una ruta',
    'SR_TEST_CONFIG_FMT': 'una configuracion, no una ruta',
    'SR_VAULT_NOTA_EXISTE_FMT': 'una nota del vault: delphi_list no la ve',
    'SR_VAULT_NOTA_EXISTE_VAULT_APPEND_FMT': 'una nota del vault: delphi_list no la ve',
    'SR_VAULT_NOTA_EXISTE_VAULT_LOCALIZALA_FMT': 'una nota del vault: su salida propia, vault_search',
    'SR_VAULT_PROMPT_NO_EXISTE_FMT': 'un prompt del vault, no una ruta',
    'SR_VAULT_SUBCARPETA_NO_EXISTE_FMT': 'una carpeta del vault: delphi_list no la ve',
}
NO_EXISTE = re.compile(r"%s[^.:']{0,14}does not exist|does not exist: %s|not found: %s")
SALIDA = mc.catalogo()['SF_RUTA_NO_EXISTE_SALIDA'].strip()


def sin_salida(cat):
    return sorted(n for n, t in cat.items()
                  if 'NOT_FOUND]' in t and NO_EXISTE.search(t) and SALIDA not in t and n not in EXCEPCIONES)


faltan = sin_salida(mc.catalogo())
check('R0 todo "no existe" de una ruta lleva la salida, salvo las excepciones declaradas', not faltan, faltan)
sobran = sorted(n for n in EXCEPCIONES if n not in mc.catalogo() or SALIDA in mc.catalogo()[n])
check('R0b ...y ninguna excepcion sobra (ya no existe, o ya lleva la salida)', not sobran, sobran)
PLANTADO = {'SR_A_FMT': '[X-1 NOT_FOUND] %s does not exist.', 'SR_B_FMT': '[X-2 NOT_FOUND] %s does not exist.'
            + ' ' + SALIDA, 'SR_C_FMT': '[X-3 NOT_FOUND] Directory not found: %s'}
check('R1 el comprobador sabe fallar: las plantadas sin la salida salen, la que la lleva no',
      sin_salida(PLANTADO) == ['SR_A_FMT', 'SR_C_FMT'], sin_salida(PLANTADO))

BASE = mc.carpeta('ruta_no_existe_1293')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
NADA = os.path.join(JAIL, 'NoEsta')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='ruta-no-existe-1293', t=120)


def lleva(r):
    return SALIDA in r.replace('\\"', '"') and re.search(r'\[[A-Z]+-\d+ NOT_FOUND\]', r) is not None


try:
    casos = [
        ('R2 delphi_search root que no existe (WS-008)', 'delphi_search', {'root': NADA, 'query': 'x'}),
        ('R3 delphi_list root que no existe', 'delphi_list', {'root': NADA}),
        ('R4 delphi_edit de un .pas que no existe', 'delphi_edit',
         {'path': os.path.join(NADA, 'U.pas'), 'old': 'a', 'new': 'b'}),
        ('R5 delphi_edit edits de un .pas que no existe (EDIT-027)', 'delphi_edit',
         {'path': os.path.join(NADA, 'U.pas'), 'edits': [{'old': 'a', 'new': 'b'}]}),
        ('R6 delphi_textedit de un .txt que no existe (TEXT-007)', 'delphi_textedit',
         {'path': os.path.join(NADA, 'a.txt'), 'old': 'a', 'new': 'b'}),
        ('R7 delphi_designer tree de un .fmx que no existe', 'delphi_designer',
         {'command': 'tree', 'path': os.path.join(NADA, 'F.fmx')}),
        ('R8 delphi_git status de una carpeta que no existe (GIT-026)', 'delphi_git',
         {'command': 'status', 'repo': NADA}),
    ]
    for nombre, tool, args in casos:
        r = s.call(tool, args)
        check(nombre + ': NOT_FOUND con la salida (ROJO sin A2)', lleva(r), r[:400])
    r = s.call('delphi_read', {'path': os.path.join(NADA, 'U.pas')})
    check('R9 control: delphi_read (LSP-011) la sigue diciendo', mc.es(r, 'SR_LSP_NO_FILE_FMT') and lleva(r), r[:400])
finally:
    s.mata()
mc.borra(BASE)
mc.fin('una ruta que no existe dice como seguir 1.29.3 (A2)')
