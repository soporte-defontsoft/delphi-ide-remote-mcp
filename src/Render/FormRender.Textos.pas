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
    '[RENDER-008 NOT_FOUND] Nobody said where RAD Studio %s is (--bdsroot): ' +
    'inside its container the renderer does not read the registry.';

  SN_RENDER_HEREDA_SIN_PAS_FMT =
    '[RENDER-009] %s is inherited and no .pas next to it says from which ' +
    'class: read on its own.';

  SN_RENDER_ANCESTRO_SIN_FICHERO_FMT =
    '[RENDER-010] The ancestor %s has no form file in the folder: read ' +
    'without it.';

  // dos forms de la carpeta con la misma clase raiz (la copia que deja el
  // Explorador) y el uses del .pas no decide (V120 de la 1.24). %s = la clase,
  // %s = los ficheros, %s = el que se leyo
  SN_RENDER_CLASE_EN_VARIOS_FMT =
    '[RENDER-025] The class %s is the root of several forms of the folder (%s) ' +
    'and the uses of the .pas that names it does not say which: read %s.';

  // ...y si en la carpeta hay forms que el lector del IDE no toma por texto
  // (TestStreamFormat: un UTF-16 o un UTF-32, que el editor del IDE deja
  // guardar y su disenador no reabre; A28 de la 1.23), el ancestro puede ser
  // uno de ellos: "no tiene fichero" era falso. %s = el ancestro, %s = esos
  // ficheros
  SN_RENDER_ANCESTRO_NO_CARGA_FMT =
    '[RENDER-023] The ancestor %s is not among the forms of the folder that ' +
    'the IDE''s form reader loads: it does not take %s for a text form (one ' +
    'saved in UTF-16 or UTF-32, usually; delphi_designer command=to-text ' +
    'turns that into the text the IDE writes). Read without it.';

  SR_RENDER_ESTADO_SIN_COMPONENTE_FMT =
    '[RENDER-011 NOT_FOUND] state: there is no component %s.';

  SR_RENDER_ESTADO_NO_PUBLICA_FMT =
    '[RENDER-012 NOT_FOUND] state: %s does not publish %s.';

  SR_RENDER_ESTADO_SIN_REFERIDO_FMT =
    '[RENDER-013 NOT_FOUND] state: there is no component %s to put in %s.';

  // %s = el valor, %s = la propiedad: un numero de coma flotante que el parser
  // de forms no lee (0,5 con coma) se leia con el locale del usuario, y lo que
  // designer set niega (DSGN-092) se pintaba (V173k de la 1.23.1)
  SR_RENDER_ESTADO_FLOTANTE_FMT =
    '[RENDER-024 INVALID_PARAM] state: %s is not a number as a form writes ' +
    'it, the type of %s (decimal point, never a comma: 0.5).';

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

  SR_RENDER_ESTADO_NO_OBJETO_FMT =
    '[RENDER-020 INVALID_PARAM] state: %s of %s holds a value, not an ' +
    'object: a dotted path cannot go on past it.';

  SR_RENDER_ESTADO_REFERENCIA_FMT =
    '[RENDER-021 INVALID_PARAM] state: %s of %s holds a reference to a ' +
    'component (now %s), not an object of its own: a dotted path does not ' +
    'go through it - give that component''s own Name instead ' +
    '(Component.Property=Value), as the form file does.';

  // La guarda de ventanas (FormRender.Comun): un cuadro que un componente
  // quiso abrir al cargarse (FireDAC con una conexion activa contra una
  // definicion que no existe, 19-oct-2026) no nace y se dice
  SN_RENDER_CUADRO_BLOQUEADO_FMT =
    '[RENDER-022] A component tried to open a dialog (%s "%s") while the ' +
    'form was loading: blocked, nothing reaches the server''s desktop, and ' +
    'its code went on as if the dialog had been accepted. Something in the ' +
    'form runs at design time (a connection set to Connected or a dataset ' +
    'to Active, usually): the IDE would show that dialog when opening it.';

  // Lo que dice STYLE= del StyleBook de la form, y la coletilla de un style=
  // de la peticion: lo que lleva la form ES lo que vera la app. Decia "(1
  // items)" de un StyleBook con un item vacio, y nada con style=: Hermes tomo
  // dos previews con style= por el aspecto del exe (RetoFMX, 17-oct-2026)
  SF_RENDER_ESTILO_PROPIO_FMT =
    'the form''s own StyleBook %s (%d items)';

  SF_RENDER_ESTILO_PROPIO_VACIO_FMT =
    'the form''s own StyleBook %s, EMPTY (%d item(s) with no style in ' +
    'them): the platform default is drawn, and the app runs with it too ' +
    'unless its code loads a style';

  SF_RENDER_ESTILO_SOLO_ESTA_IMAGEN_FMT =
    '%s - for this image only: the form itself carries %s';

  SF_RENDER_LLEVA_ESTILOS_FMT =
    'its StyleBook %s with %d style(s)';

  SF_RENDER_LLEVA_VACIO_FMT =
    'an EMPTY StyleBook %s (unless its code loads a style, the app gets ' +
    'the platform default)';

  SF_RENDER_LLEVA_NADA =
    'no StyleBook (unless its code loads a style, the app gets the ' +
    'platform default)';

  // La linea de uso (stderr, con el codigo 2)
  SF_RENDER_USO_FMT =
    '%s --path <dfm|fmx> --out <png> [--state Component.Property=Value]* ' +
    '[--component Name] [--style <file|platform|none>] [--nonvisual on|off (off)] ' +
    '[--packages auto|none|all] [--root auto|form|frame] ' +
    '[--fidelity auto|window|print] [--bds 37.0] [--bdsroot <dir>] [--knownfile <file>] ' +
    '[--timeout ms] [--verbose] | ' +
    '%s --path <dfm|fmx> --writeback on ' +
    '[--component Name] [--dropped Name] ' +
    '[--packages ...] [--root ...] [--bds] [--bdsroot] [--knownfile] [--timeout ms] | ' +
    '%s --path <dfm|fmx> --convert text|binary --out <file> [--timeout ms] | ' +
    '%s --unreadableclasses';

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
