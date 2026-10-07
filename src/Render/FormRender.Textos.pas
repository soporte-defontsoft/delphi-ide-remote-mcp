unit FormRender.Textos;

{ EL catalogo de mensajes de los renderizadores de forms (DelphiFormRenderVcl
  y DelphiFormRenderFmx): lo que llega al agente por ERROR= y WARNING=. No
  enlazan Lsp.Texts (es del servidor y arrastra su logger), asi que tienen el
  suyo, con las mismas reglas que Lsp.Texts y Mld.Textos: una constante por
  mensaje, la etiqueta al PRINCIPIO de su texto (area RENDER; con el
  resultado si es un rechazo), textos en ingles, y todo sale por
  MsgText/MsgFmt. test_catalogo vigila los tres catalogos: un id no se
  repite. Las claves del protocolo (FormRenderProtocolo.inc) no son mensajes
  y no estan aqui; las trazas '#' de --verbose tampoco. }

interface

const
  SR_RENDER_ARG_SIN_VALOR_FMT =
    '[RENDER-001 INVALID_PARAM] %s needs a value.';

  SR_RENDER_ARG_FUERA_FMT =
    '[RENDER-002 INVALID_PARAM] %s: %s is not one of %s.';

  SR_RENDER_ARG_DESCONOCIDO_FMT =
    '[RENDER-003 INVALID_PARAM] Unknown argument: %s.';

  SR_RENDER_FALTA_ARG_FMT =
    '[RENDER-004 INVALID_PARAM] Missing %s.';

  SR_RENDER_NO_EXISTE_FMT =
    '[RENDER-005 NOT_FOUND] %s does not exist.';

  SR_RENDER_ESTADO_FORMA_FMT =
    '[RENDER-006 INVALID_PARAM] --state %s: the shape is ' +
    'Component.Property=Value.';

  SR_RENDER_TIEMPO_FMT =
    '[RENDER-007 DENIED] The render did not finish in %d ms (something in ' +
    'the form waits, or a package hangs while loading): the renderer ends ' +
    'itself.';

  SR_RENDER_SIN_IDE_FMT =
    '[RENDER-008 NOT_FOUND] There is no RAD Studio %s for this user ' +
    '(HKCU\Software\Embarcadero\BDS).';

  SN_RENDER_HEREDA_SIN_PAS_FMT =
    '[RENDER-009] %s is inherited and no .pas next to it says from which ' +
    'class: read on its own.';

  SN_RENDER_ANCESTRO_SIN_FICHERO_FMT =
    '[RENDER-010] The ancestor %s has no form file in the folder: read ' +
    'without it.';

  SR_RENDER_ESTADO_SIN_COMPONENTE_FMT =
    '[RENDER-011 NOT_FOUND] state: there is no component %s.';

  SR_RENDER_ESTADO_NO_PUBLICA_FMT =
    '[RENDER-012 NOT_FOUND] state: %s does not publish %s.';

  SR_RENDER_ESTADO_SIN_REFERIDO_FMT =
    '[RENDER-013 NOT_FOUND] state: there is no component %s to put in %s.';

  SN_RENDER_EXCEPCION_BUCLE_FMT =
    '[RENDER-014] An exception reached the message loop and was recorded ' +
    'instead of shown: %s: %s.';

  SN_RENDER_PINTADA_NO_COPIADA_FMT =
    '[RENDER-015] The real painting could not be copied (%s): printed ' +
    'control by control instead.';

  SN_RENDER_SIN_COMPONENTE_FMT =
    '[RENDER-016] component: there is no %s in %s.';

  SR_RENDER_ESTILO_DESCONOCIDO_FMT =
    '[RENDER-017 INVALID_PARAM] style: %s is neither a file nor a designer ' +
    'platform (%s).';

  SR_RENDER_ESTILO_NO_ABRE_FMT =
    '[RENDER-018 NOT_FOUND] style: %s could not be opened.';

  SR_RENDER_SIN_ESCENA_FMT =
    '[RENDER-019 INTERNAL] The canvas does not accept a scene (%s).';

  // La linea de uso (stderr, con el codigo 2)
  SF_RENDER_USO_FMT =
    '%s --path <dfm|fmx> --out <png> [--state Component.Property=Value]* ' +
    '[--component Name] [--style <file|platform|none>] [--nonvisual on|off] ' +
    '[--packages auto|none|all] [--root auto|form|frame] ' +
    '[--fidelity auto|window|print] [--bds 37.0] [--timeout ms] [--verbose]';

function MsgText(const AMsg: string): string;
function MsgFmt(const AMsg: string; const AArgs: array of const): string;

implementation

uses
  System.SysUtils;

function MsgText(const AMsg: string): string;
begin
  Result := AMsg;
end;

{ Si los argumentos no cuadran con los % del mensaje, el mensaje sin
  formatear con el motivo detras: nunca una excepcion en mitad del render. }
function MsgFmt(const AMsg: string; const AArgs: array of const): string;
begin
  try
    Result := Format(MsgText(AMsg), AArgs);
  except
    on E: Exception do
      Result := MsgText(AMsg) + ' (' + E.Message + ')';
  end;
end;

end.
