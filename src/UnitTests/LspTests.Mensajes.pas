unit LspTests.Mensajes;

// El lector de las etiquetas de los mensajes del catalogo (Lsp.Texts:
// MsgIds, MsgTag, HasMsg, MsgOutcome). Una etiqueta es [AREA-NNN] o
// [AREA-NNN RESULTADO] al final del mensaje (decision de David, 27-sep-2026):
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
  end;

implementation

uses
  System.SysUtils,
  Lsp.Texts;

const
  // dos mensajes de ejemplo, como estaran en el catalogo
  EJ_RECHAZO = 'RECHAZADO: "%s" no es una plataforma Delphi valida. [CFG-007 INVALID_PARAM]';
  EJ_BUENO = 'ESCRITO en %s. [EDIT-001]';
  EJ_SIN = 'Un mensaje que aun no lleva etiqueta.';

procedure TEtiquetasTests.LosIdsEnOrden;
var
  Ids: TArray<string>;
begin
  Ids := MsgIds('ESCRITO en A.pas. [EDIT-001]'#10'OJO: algo. [EDIT-040]'#10 +
    'RECHAZADO: fuera. [WS-003 DENIED]');
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
  Assert.IsTrue(Length(MsgIds('usa [Workspace.<nombre>] y [Server] Port')) = 0, 'secciones');
end;

procedure TEtiquetasTests.ElMensajePorSuConstante;
begin
  Assert.AreEqual('CFG-007', MsgTag(EJ_RECHAZO));
  Assert.AreEqual('EDIT-001', MsgTag(EJ_BUENO));
  Assert.AreEqual('', MsgTag(EJ_SIN));
  Assert.IsTrue(HasMsg(Format(EJ_BUENO, ['A.pas']), EJ_BUENO), 'el suyo');
  Assert.IsFalse(HasMsg(Format(EJ_BUENO, ['A.pas']), EJ_RECHAZO), 'otro');
  // un mensaje SIN etiqueta no coincide con nada, ni consigo mismo: nadie puede
  // guiarse por un mensaje que aun no se ha migrado creyendo que si
  Assert.IsFalse(HasMsg(EJ_SIN, EJ_SIN), 'sin etiqueta');
end;

procedure TEtiquetasTests.ElResultadoLoDeclaraLaEtiqueta;
begin
  Assert.AreEqual('INVALID_PARAM', MsgOutcome(Format(EJ_RECHAZO, ['Win99'])));
  Assert.AreEqual('', MsgOutcome(Format(EJ_BUENO, ['A.pas'])), 'un resultado bueno no declara nada');
  Assert.AreEqual('', MsgOutcome(EJ_SIN));
  // manda la PRIMERA etiqueta, la del mensaje que abre la respuesta: un
  // rechazo anadido detras de una nota o de un resultado bueno no la
  // convierte en error (la regla de siempre miraba como EMPIEZA el texto)
  Assert.AreEqual('', MsgOutcome('nota [EDIT-040]'#10'RECHAZADO: no existe X. [FILE-004 NOT_FOUND]'),
    'una nota delante');
  Assert.AreEqual('NOT_FOUND', MsgOutcome('RECHAZADO: no existe X. [FILE-004 NOT_FOUND]'#10 +
    'nota [EDIT-040]'#10'y otro [WS-003 DENIED]'), 'el rechazo delante');
  // lo que viene DETRAS de la primera linea no declara nada: un fichero leido
  // que cita una etiqueta no convierte la lectura en error (27-sep)
  Assert.AreEqual('', MsgOutcome('Lsp.Texts.pas  encoding=utf8'#10 +
    '12|    ''RECHAZADO: x. [CFG-001 DENIED]'';'), 'un fichero leido');
  // y una respuesta JSON tampoco: la decide su campo error
  Assert.AreEqual('', MsgOutcome('{"hits":["[CFG-001 DENIED]"]}'), 'JSON');
end;

procedure TEtiquetasTests.ElHelperNoRevienta;
var
  S: string;
begin
  // hoy el texto tal cual; con traducciones, por el id
  Assert.AreEqual(EJ_SIN, MsgText(EJ_SIN));
  Assert.AreEqual('ESCRITO en A.pas. [EDIT-001]', MsgFmt(EJ_BUENO, ['A.pas']));
  // unos argumentos que no cuadran: el mensaje sin formatear y el motivo,
  // nunca una excepcion de conversion en mitad de una tool
  S := MsgFmt(EJ_BUENO, [42]);
  Assert.IsTrue(S.StartsWith(EJ_BUENO), S);
  Assert.IsTrue(MsgIds(S)[0] = 'EDIT-001', 'conserva su etiqueta: ' + S);
  // un mensaje metido dentro de otro por un %s pierde su etiqueta: habla el de
  // fuera (si no, el DENIED de dentro decidiria el resultado de un exito)
  S := MsgFmt('CREADA la unit, pero NO se pudo registrar: %s [CREATE-099]',
    ['RECHAZADO: el .dpr no existe. [CFG-001 NOT_FOUND]']);
  Assert.IsTrue((Length(MsgIds(S)) = 1) and (MsgIds(S)[0] = 'CREATE-099'), S);
  Assert.AreEqual('', MsgOutcome(S), 'un exito sigue siendolo');
  Assert.IsTrue(S.Contains('RECHAZADO: el .dpr no existe.'), 'el texto de dentro se queda: ' + S);
end;

procedure TEtiquetasTests.LosLectoresDelResultado;
begin
  // por la etiqueta: la PRIMERA del mensaje
  Assert.AreEqual('INVALID_PARAM', ResultadoDe(Format(EJ_RECHAZO, ['Win99'])));
  Assert.AreEqual('', ResultadoDe(Format(EJ_BUENO, ['A.pas'])), 'un exito no declara nada');
  Assert.IsTrue(EsRechazo(Format(EJ_RECHAZO, ['Win99'])), 'rechazo');
  Assert.IsFalse(EsRechazo('Error executing tool: x [SYS-999 INTERNAL]'), 'INTERNAL no es un rechazo');
  Assert.IsTrue(EsFallo('Error executing tool: x [SYS-999 INTERNAL]'), 'pero si un fallo');
  // sin etiqueta, la regla vieja (mientras quede algun mensaje sin ella)
  Assert.AreEqual('NOT_FOUND', ResultadoDe('RECHAZADO: no existe X.'));
  Assert.AreEqual('INVALID_PARAM', ResultadoDe('error: falta "path"'));
  Assert.IsFalse(EsFallo('ESCRITO en A.pas'), 'sin etiqueta y sin marca: exito');
  // un rechazo aun SIN etiqueta con una nota etiquetada detras sigue siendo
  // un rechazo (la puerta del 27-sep: la tanda se aplicaba en vez de deshacerse)
  Assert.IsTrue(EsFallo('RECHAZADO: el ancla no esta.'#10'la mas parecida es la 3 [EDIT-099]'), 'rechazo + nota');
  // EsMsg mira la PRIMERA etiqueta: el eco que viene detras no cuenta
  Assert.IsTrue(EsMsg(Format(EJ_BUENO, ['A.pas']) + #10'12| RECHAZADO [CFG-007 INVALID_PARAM]', EJ_BUENO));
  Assert.IsFalse(EsMsg('RECHAZADO: x [CFG-007 INVALID_PARAM]'#10'eco: ESCRITO en A.pas. [EDIT-001]', EJ_BUENO),
    'un ESCRITO citado en el eco no convierte un rechazo en exito');
end;

initialization
  TDUnitX.RegisterTestFixture(TEtiquetasTests);

end.
