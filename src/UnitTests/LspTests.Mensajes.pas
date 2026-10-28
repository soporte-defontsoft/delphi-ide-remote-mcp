unit LspTests.Mensajes;

// El lector de las etiquetas de los mensajes del catalogo (Lsp.Texts:
// MsgIds, MsgTag, HasMsg, MsgOutcome, EsMsg, MsgEnvuelve). Una etiqueta es
// [AREA-NNN] o [AREA-NNN RESULTADO] al PRINCIPIO del mensaje (David, 27-sep):
// lo que no tiene esa forma exacta no es una etiqueta, y un mensaje sin
// etiqueta no coincide con nada. Y la cola de una salida en una respuesta
// (Lsp.Listas.ColaDeSalida y FinalDeTexto, V80 de la 1.23.1).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEtiquetasTests = class
  public
    [Test] procedure LosIdsEnOrden;
    [Test] procedure LoQueNoEsEtiqueta;
    [Test] procedure ElMensajePorSuConstante;
    [Test] procedure ElResultadoLoDeclaraLaEtiqueta;
    [Test] procedure ElHelperNoRevienta;
    [Test] procedure LosLectoresDelResultado;
    [Test] procedure ElEnvoltorioRespetaLaCausa;
  end;

  [TestFixture]
  TColaDeSalidaTests = class
  public
    [Test] procedure LasUltimasYLaCuenta;
    [Test] procedure SinFiltroVanLasVacias;
    [Test] procedure ElFiltroSaltaYCambia;
    [Test] procedure LosCaracteresAcotan;
    [Test] procedure UnaLineaEnormeVaSuFinalYSeDice;
    [Test] procedure ElFinalNoParteUnPar;
    [Test]
    procedure ElPrincipioNoParteUnPar;
  end;

implementation

uses
  System.SysUtils,
  Lsp.Listas,
  Lsp.Texts;

const
  // dos mensajes de ejemplo, como estan en el catalogo: la etiqueta DELANTE
  EJ_RECHAZO = '[CFG-007 INVALID_PARAM] "%s" is not a valid Delphi platform.';
  EJ_BUENO = '[EDIT-001] WRITTEN to %s.';
  EJ_SIN = 'A text with no tag.';

procedure TEtiquetasTests.LosIdsEnOrden;
var
  Ids: TArray<string>;
begin
  Ids := MsgIds('[EDIT-001] WRITTEN to A.pas.'#10'[EDIT-040] NOTE: something.'#10 +
    '[WS-003 DENIED] outside.');
  Assert.IsTrue(Length(Ids) = 3, 'tres: ' + IntToStr(Length(Ids)));
  Assert.AreEqual('EDIT-001', Ids[0]);
  Assert.AreEqual('EDIT-040', Ids[1]);
  Assert.AreEqual('WS-003', Ids[2]);
  Assert.IsTrue(Length(MsgIds('')) = 0, 'vacio');
end;

procedure TEtiquetasTests.LoQueNoEsEtiqueta;
begin
  // dos cifras, un area de una letra o de siete, minusculas, un resultado que no
  // existe, un espacio dentro: nada de eso es una etiqueta
  Assert.IsTrue(Length(MsgIds('[CFG-07] [C-007] [ABCDEFG-001] [cfg-007] ' +
    '[CFG-007 BOGUS] [CFG-007  DENIED] [ CFG-007]')) = 0, 'ninguna');
  // un corchete normal de un mensaje tampoco
  Assert.IsTrue(Length(MsgIds('use [Workspace.<name>] and [Server] Port')) = 0, 'secciones');
end;

procedure TEtiquetasTests.ElMensajePorSuConstante;
begin
  Assert.AreEqual('CFG-007', MsgTag(EJ_RECHAZO));
  Assert.AreEqual('EDIT-001', MsgTag(EJ_BUENO));
  Assert.AreEqual('', MsgTag(EJ_SIN));
  Assert.IsTrue(HasMsg(Format(EJ_BUENO, ['A.pas']), EJ_BUENO), 'el suyo');
  Assert.IsFalse(HasMsg(Format(EJ_BUENO, ['A.pas']), EJ_RECHAZO), 'otro');
  // un mensaje SIN etiqueta no coincide con nada, ni consigo mismo
  Assert.IsFalse(HasMsg(EJ_SIN, EJ_SIN), 'sin etiqueta');
end;

procedure TEtiquetasTests.ElResultadoLoDeclaraLaEtiqueta;
begin
  Assert.AreEqual('INVALID_PARAM', MsgOutcome(Format(EJ_RECHAZO, ['Win99'])));
  Assert.AreEqual('', MsgOutcome(Format(EJ_BUENO, ['A.pas'])), 'un resultado bueno no declara nada');
  Assert.AreEqual('', MsgOutcome(EJ_SIN));
  // manda la etiqueta que ABRE el texto: un rechazo anadido detras de una
  // nota o de un resultado bueno no lo convierte en error
  Assert.AreEqual('', MsgOutcome('[EDIT-040] note'#10'[FILE-004 NOT_FOUND] X does not exist.'),
    'una nota delante');
  Assert.AreEqual('NOT_FOUND', MsgOutcome('[FILE-004 NOT_FOUND] X does not exist.'#10 +
    '[EDIT-040] note'#10'[WS-003 DENIED] other'), 'el rechazo delante');
  // el blanco inicial (una nota que se pega detras de otro texto) no cambia nada
  Assert.AreEqual('DENIED', MsgOutcome(#10'  [WS-003 DENIED] outside.'), 'blanco delante');
  // lo que NO empieza por una etiqueta no declara nada, aunque la traiga
  // dentro: un fichero leido que cita etiquetas (27-sep: se tomaba por una
  // negativa y se enmascaraba su contenido, '%s:' salia '%srv0:')
  Assert.AreEqual('', MsgOutcome('Lsp.Texts.pas  encoding=utf8'#10 +
    '12|    ''[CFG-001 DENIED] x.'';'), 'un fichero leido');
  Assert.AreEqual('', MsgOutcome('WRITTEN [CFG-001 DENIED]'), 'una etiqueta en medio');
  // y una respuesta JSON tampoco: la decide su campo error
  Assert.AreEqual('', MsgOutcome('{"hits":["[CFG-001 DENIED]"]}'), 'JSON');
end;

procedure TEtiquetasTests.ElHelperNoRevienta;
var
  S: string;
begin

  Assert.AreEqual(EJ_SIN, MsgText(EJ_SIN));
  Assert.AreEqual('[EDIT-001] WRITTEN to A.pas.', MsgFmt(EJ_BUENO, ['A.pas']));
  // unos argumentos que no cuadran: el mensaje sin formatear y el motivo,
  // nunca una excepcion de conversion en mitad de una tool
  S := MsgFmt(EJ_BUENO, [42]);
  Assert.IsTrue(S.StartsWith(EJ_BUENO), S);
  Assert.IsTrue(MsgIds(S)[0] = 'EDIT-001', 'conserva su etiqueta: ' + S);
  // un mensaje metido dentro de otro por un %s CONSERVA su etiqueta (se
  // reconoce por su id) y no decide nada: habla la que abre el texto
  S := MsgFmt('[CREATE-099] CREATED the unit, but it could NOT be registered: %s',
    ['[CFG-001 NOT_FOUND] the .dpr does not exist.']);
  Assert.IsTrue((Length(MsgIds(S)) = 2) and (MsgIds(S)[0] = 'CREATE-099') and
    (MsgIds(S)[1] = 'CFG-001'), S);
  Assert.AreEqual('', MsgOutcome(S), 'un exito sigue siendolo');
  // y un dato que cita etiquetas llega INTACTO (con la etiqueta al final,
  // MsgFmt las borraba: el eco de un ancla de Lsp.Texts salia mutilado)
  S := MsgFmt('[EDIT-093 DENIED] The anchor is not in the file.'#10'Anchor: |%s|',
    ['x [SYS-006 INTERNAL] y']);
  Assert.IsTrue(S.Contains('|x [SYS-006 INTERNAL] y|'), S);
  Assert.AreEqual('DENIED', MsgOutcome(S));
end;

procedure TEtiquetasTests.LosLectoresDelResultado;
begin
  Assert.IsTrue(EsRechazo(Format(EJ_RECHAZO, ['Win99'])), 'rechazo');
  Assert.IsFalse(EsRechazo(Format(EJ_BUENO, ['A.pas'])), 'un exito no');
  Assert.IsFalse(EsRechazo('[SYS-999 INTERNAL] Error executing tool: x'), 'INTERNAL no es un rechazo');
  Assert.IsTrue(EsFallo('[SYS-999 INTERNAL] Error executing tool: x'), 'pero si un fallo');
  // sin etiqueta delante no hay fallo: la regla vieja (leer RECHAZADO,
  // error:) ya no existe
  Assert.IsFalse(EsFallo('RECHAZADO: no existe X.'), 'la marca vieja no cuenta');
  Assert.IsFalse(EsFallo(EJ_SIN), 'sin etiqueta: exito');
  // un fallo de varias lineas se reconoce: la etiqueta lo abre (con ella al
  // final, un ROLLBACK de varias lineas salia como EXITO)
  Assert.IsTrue(EsFallo('[EDIT-099 DENIED] ROLLBACK: edit 2 of 3 failed.'#10'why...'), 'rollback');
  // EsMsg mira la etiqueta que ABRE el texto: el eco que viene detras no cuenta
  Assert.IsTrue(EsMsg(Format(EJ_BUENO, ['A.pas']) + #10'12| [CFG-007 INVALID_PARAM] x', EJ_BUENO));
  Assert.IsFalse(EsMsg('[CFG-007 INVALID_PARAM] x'#10'echo: [EDIT-001] WRITTEN to A.pas.', EJ_BUENO),
    'un WRITTEN citado en el eco no convierte un rechazo en exito');
  Assert.IsFalse(EsMsg('before [EDIT-001] WRITTEN', EJ_BUENO), 'una etiqueta en medio no abre nada');
end;

procedure TEtiquetasTests.ElEnvoltorioRespetaLaCausa;
const
  ENVOLTORIO = '[SYS-998 INVALID_PARAM] %s';
  INTERNO = '[SYS-997 INTERNAL] %s: %s';
var
  Causa: string;
begin
  // una causa que no es un mensaje con resultado: se envuelve
  Assert.AreEqual('[SYS-998 INVALID_PARAM] the key is missing', MsgEnvuelve(ENVOLTORIO, 'the key is missing'));
  Assert.AreEqual('INVALID_PARAM', MsgOutcome(MsgEnvuelve(ENVOLTORIO, 'the key is missing')));
  // una que YA lo es sale tal cual: envolverla cambiaba su resultado (un
  // <Exec> en delphi_test pasaba de DENIED a INVALID_PARAM)
  Causa := '[BUILD-017 DENIED] the .dproj runs commands in the build';
  Assert.AreEqual(Causa, MsgEnvuelve(ENVOLTORIO, Causa));
  Assert.AreEqual('DENIED', MsgOutcome(MsgEnvuelve(ENVOLTORIO, Causa)));
  // con argumentos propios del envoltorio (clase + mensaje)
  Assert.AreEqual('[SYS-997 INTERNAL] EFoo: broken', MsgEnvuelve(INTERNO, 'broken', ['EFoo', 'broken']));
  Assert.AreEqual(Causa, MsgEnvuelve(INTERNO, Causa, ['ELspSession', Causa]));
end;

{ TColaDeSalidaTests }

function Lineas(ADesde, AHasta: Integer): string;
begin
  Result := '';
  for var I := ADesde to AHasta do
    Result := Result + 'L' + IntToStr(I) + #10;
end;

procedure TColaDeSalidaTests.LasUltimasYLaCuenta;
begin
  var C := ColaDeSalida(Lineas(1, 10), 3);
  Assert.AreEqual('L8'#13#10'L9'#13#10'L10', C.Texto);
  Assert.AreEqual(10, C.Total);
  Assert.AreEqual(3, C.Mostradas);
  Assert.IsTrue(C.Cortada, 'faltan siete');
  // las que caben van todas, sin la fantasma del salto final
  C := ColaDeSalida(Lineas(1, 3), 3);
  Assert.AreEqual('L1'#13#10'L2'#13#10'L3', C.Texto);
  Assert.IsFalse(C.Cortada, 'enteras');
end;

procedure TColaDeSalidaTests.SinFiltroVanLasVacias;
begin
  // la salida que ES la respuesta (logcat, remote-run) va como salio
  var C := ColaDeSalida('a'#13#10#13#10'b  '#13'c', 10);
  Assert.AreEqual('a'#13#10#13#10'b'#13#10'c', C.Texto, 'la vacia va; el blanco final no; el CR suelto es salto');
  Assert.AreEqual(4, C.Total);
end;

procedure TColaDeSalidaTests.ElFiltroSaltaYCambia;
begin
  var C := ColaDeSalida('a'#10#10'x'#10'b', 2,
    function(var ALinea: string): Boolean
    begin
      if ALinea = 'x' then
        ALinea := 'X';
      Result := ALinea <> '';
    end);
  Assert.AreEqual('X'#13#10'b', C.Texto);
  Assert.AreEqual(3, C.Total, 'la vacia no cuenta');
  Assert.IsTrue(C.Cortada);
end;

procedure TColaDeSalidaTests.LosCaracteresAcotan;
var
  S: string;
begin
  S := '';
  for var I := 1 to 200 do
    S := S + StringOfChar('x', 999) + IntToStr(I mod 10) + #10;
  var C := ColaDeSalida(S, LINEAS_DE_SALIDA);
  Assert.IsTrue(Length(C.Texto) <= CARACTERES_DE_COLA, IntToStr(Length(C.Texto)));
  Assert.IsTrue((C.Mostradas > 0) and (C.Mostradas < 200) and C.Cortada, IntToStr(C.Mostradas));
  Assert.IsTrue(C.Texto.EndsWith('x0'), 'la mas nueva al final');
  Assert.IsFalse(C.Texto.StartsWith('...'), 'lineas enteras: ninguna a medias');
end;

procedure TColaDeSalidaTests.UnaLineaEnormeVaSuFinalYSeDice;
begin
  var C := ColaDeSalida('vieja'#10 + StringOfChar('A', 200000) + 'FIN', LINEAS_DE_SALIDA);
  Assert.IsTrue(Length(C.Texto) <= CARACTERES_DE_COLA, IntToStr(Length(C.Texto)));
  Assert.IsTrue(C.Texto.StartsWith('...') and C.Texto.EndsWith('FIN'), Copy(C.Texto, 1, 10));
  Assert.AreEqual(1, C.Mostradas, 'la mas nueva, a medias');
  Assert.IsTrue(C.Cortada, 'y se dice');
  // sola: la cuenta cuadra (1 de 1) y aun asi falta su principio
  C := ColaDeSalida(StringOfChar('A', 200000), LINEAS_DE_SALIDA);
  Assert.IsTrue((C.Total = 1) and (C.Mostradas = 1) and C.Cortada, 'una sola linea cortada');
end;

procedure TColaDeSalidaTests.ElFinalNoParteUnPar;
begin
  Assert.AreEqual('abc', FinalDeTexto('abc', 5), 'cabe: tal cual');
  Assert.AreEqual('...bc', FinalDeTexto('abc', 2));
  // los 3 ultimos empezarian por la segunda mitad del emoji: va sin ella
  Assert.AreEqual('...cd', FinalDeTexto('ab'#$D83D#$DE00'cd', 3));
  Assert.AreEqual('...'#$D83D#$DE00'cd', FinalDeTexto('ab'#$D83D#$DE00'cd', 4));
end;

{ V106 de la 1.23.1: el corte por la cabeza, el gemelo de FinalDeTexto: once
  sitios cortaban a mano sin la guarda y un emoji en el tope dejaba medio
  caracter en la respuesta }
procedure TColaDeSalidaTests.ElPrincipioNoParteUnPar;
begin
  Assert.AreEqual('abc', PrincipioDeTexto('abc', 5), 'cabe: tal cual');
  Assert.AreEqual('ab', PrincipioDeTexto('abc', 2));
  // los 3 primeros acabarian en la primera mitad del emoji: va sin el
  Assert.AreEqual('ab', PrincipioDeTexto('ab'#$D83D#$DE00'cd', 3));
  Assert.AreEqual('ab'#$D83D#$DE00, PrincipioDeTexto('ab'#$D83D#$DE00'cd', 4));
  Assert.AreEqual('', PrincipioDeTexto('abc', 0), 'nada');
  Assert.AreEqual('', PrincipioDeTexto(#$D83D#$DE00'x', 1), 'ni la mitad de uno');
end;

initialization
  TDUnitX.RegisterTestFixture(TEtiquetasTests);
  TDUnitX.RegisterTestFixture(TColaDeSalidaTests);

end.
