unit LspTests.Mensajes;

// El lector de las etiquetas de los mensajes del catalogo (Lsp.Texts:
// MsgIds, MsgTag, HasMsg, MsgOutcome, EsMsg, MsgEnvuelve). Una etiqueta es
// [AREA-NNN] o [AREA-NNN RESULTADO] al PRINCIPIO del mensaje (David, 27-sep):
// lo que no tiene esa forma exacta no es una etiqueta, y un mensaje sin
// etiqueta no coincide con nada.

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

implementation

uses
  System.SysUtils,
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

initialization
  TDUnitX.RegisterTestFixture(TEtiquetasTests);

end.
