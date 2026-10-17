unit UOraculo;

{ El oraculo del XML de proyecto (17-oct-2026, David: "teniendo juez, para que
  nos complicamos la vida?"). El juez es MSXML, el que carga el IDE (bds.exe
  lleva xmlrtl370 + msxml6): para cada fichero de proyecto de las carpetas que
  se le dan, cada elemento - en orden de documento - con sus atributos y, si
  es una hoja, su valor, por el juez y por el lector de Lsp.Dproj
  (TramosDeEtiqueta, AtributoDeTramo, ValorDeTramo). Una discrepancia es un
  fallo de uno de los dos; el lector es el del servidor, sin copias. Solo LEE.
  Lo corre tests/test_oraculo_xml.py. Se comparan tal cual: las
  normalizaciones (los saltos de linea en LF, en el texto y en un atributo)
  las hacen el juez y el lector, no el oraculo. El juez carga con
  preserveWhiteSpace: sin el, MSXML recorta el texto de un elemento. }

interface

{ ACrudo: el MUTANTE del oraculo - el lector compara el texto tal cual esta
  escrito, sin decodificar (el de antes del 17-oct-2026): sobre un fichero con
  una entidad o un CDATA tiene que discrepar, o el oraculo no mide nada. }
procedure Corre(const ACarpetas: TArray<string>; ACrudo: Boolean);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Types,
  System.Generics.Collections, System.RegularExpressions, Winapi.ActiveX,
  Xml.XMLIntf, Xml.XMLDoc, Xml.xmldom, Xml.Win.msxmldom,
  Lsp.Dproj, Lsp.Patch;

const
  // los de proyecto y los del IDE que se leen igual: el .sdk de un SDK y las
  // rutas por defecto de uno (bin\*.defaultsdkpaths); un .profile no, que
  // lleva la contrasena del PAServer cifrada y una discrepancia la escribiria
  MASCARAS: array[0..5] of string = ('*.dproj', '*.deployproj', '*.groupproj', '*.optset',
    '*.sdk', '*.defaultsdkpaths');

var
  Crudo: Boolean;

function Saltar(const AFichero: string): Boolean;
begin
  // copias, papelera e historia del IDE: no son proyectos de nadie
  Result := TRegEx.IsMatch(AFichero,
    '\\(__history|__recovery|__delphi-patch|__delphi-temp|backups?|\.git)\\', [roIgnoreCase]);
end;

function Carga(const ABytes: TBytes): IXMLDocument;
var
  S: TBytesStream;
  D: TXMLDocument;
begin
  D := TXMLDocument.Create(nil);
  D.DOMVendor := GetDOMVendor(SMSXML);
  Result := D;
  Result.ParseOptions := [poPreserveWhiteSpace];
  Result.Options := [];
  S := TBytesStream.Create(ABytes);
  try
    Result.LoadFromStream(S);
  finally
    S.Free;
  end;
end;

function EsHoja(const N: IXMLNode): Boolean;
begin
  Result := True;
  for var I := 0 to N.ChildNodes.Count - 1 do
    if N.ChildNodes[I].NodeType = ntElement then
      Exit(False);
end;

{ El texto de una hoja: sus nodos de texto y CDATA, en orden (IXMLNode.Text
  falla si la hoja lleva ademas un comentario). }
function TextoDeHoja(const N: IXMLNode): string;
begin
  Result := '';
  for var I := 0 to N.ChildNodes.Count - 1 do
    if N.ChildNodes[I].NodeType in [ntText, ntCData] then
      Result := Result + N.ChildNodes[I].NodeValue;
end;

procedure Elementos(const N: IXMLNode; AL: TList<IXMLNode>);
begin
  for var I := 0 to N.ChildNodes.Count - 1 do
    if N.ChildNodes[I].NodeType = ntElement then
    begin
      AL.Add(N.ChildNodes[I]);
      Elementos(N.ChildNodes[I], AL);
    end;
end;

{ Lo que dice el juez de un elemento y lo que dice el lector del suyo; '' si
  coinciden. }
function Compara(const AXml: string; const N: IXMLNode; const T: TTramoXml): string;
begin
  Result := '';
  for var I := 0 to N.AttributeNodes.Count - 1 do
  begin
    var A := N.AttributeNodes[I];
    if A.NodeName.StartsWith('xmlns') then
      Continue;
    var Juez := A.Text;
    var Lector := AtributoDeTramo(AXml, T, N.NodeName, A.NodeName);
    if Crudo then
      for var At in AtributosDeTramo(AXml, T) do
        if SameText(At.Nombre, A.NodeName) then
          Lector := Copy(AXml, At.Ini, At.Fin - At.Ini);
    if Juez <> Lector then
      Exit(Format('atributo %s: juez [%s] lector [%s]', [A.NodeName, Juez, Lector]));
  end;
  if EsHoja(N) then
  begin
    var Juez := TextoDeHoja(N);
    var Lector := ValorDeTramo(AXml, T);
    if Crudo then
      Lector := Copy(AXml, T.Ini, T.Fin - T.Ini);
    if Juez <> Lector then
      Exit(Format('valor: juez [%s] lector [%s]', [Copy(Juez, 1, 120), Copy(Lector, 1, 120)]));
  end;
end;

procedure UnFichero(const F: string; var ADiscrepa: Integer);
var
  Doc: IXMLDocument;
  L: TList<IXMLNode>;
  Vistos: TDictionary<string, TArray<TTramoXml>>;
  Cuenta: TDictionary<string, Integer>;
begin
  var Bytes := TFile.ReadAllBytes(F);
  Doc := Carga(Bytes);
  var Enc: string;
  var Xml := TextoDeBytes(Bytes, False, Enc); // EL decodificador del servidor
  L := TList<IXMLNode>.Create;
  Vistos := TDictionary<string, TArray<TTramoXml>>.Create;
  Cuenta := TDictionary<string, Integer>.Create;
  try
    Elementos(Doc.Node, L);
    for var N in L do
    begin
      var Nombre := N.NodeName;
      var Tramos: TArray<TTramoXml>;
      if not Vistos.TryGetValue(LowerCase(Nombre), Tramos) then
      begin
        Tramos := TramosDeEtiqueta(Xml, Nombre, True);
        Vistos.Add(LowerCase(Nombre), Tramos);
      end;
      var K := 0;
      Cuenta.TryGetValue(LowerCase(Nombre), K);
      Cuenta.AddOrSetValue(LowerCase(Nombre), K + 1);
      var Dif: string;
      if K > High(Tramos) then
        Dif := Format('el lector no ve el <%s> numero %d (ve %d)', [Nombre, K + 1, Length(Tramos)])
      else
        Dif := Compara(Xml, N, Tramos[K]);
      if Dif <> '' then
      begin
        Inc(ADiscrepa);
        Writeln('DISCREPA ', F, ' <', Nombre, '> numero ', K + 1, ': ', Dif.Replace(#10, '\n'));
        Exit; // la primera de cada fichero: las demas suelen ser la misma
      end;
    end;
    // y lo que el lector ve de mas (un elemento dentro de un comentario, por ejemplo)
    for var P in Vistos do
    begin
      var K := 0;
      Cuenta.TryGetValue(P.Key, K);
      if Length(P.Value) > K then
      begin
        Inc(ADiscrepa);
        Writeln('DISCREPA ', F, ' <', P.Key, '>: el lector ve ', Length(P.Value), ', el juez ', K);
        Exit;
      end;
    end;
  finally
    Cuenta.Free;
    Vistos.Free;
    L.Free;
  end;
end;

procedure Corre(const ACarpetas: TArray<string>; ACrudo: Boolean);
var
  Ficheros, Leidos, Discrepa: Integer;
begin
  CoInitialize(nil);
  Crudo := ACrudo;
  Ficheros := 0;
  Leidos := 0;
  Discrepa := 0;
  for var C in ACarpetas do
  begin
    if not TDirectory.Exists(C) then
    begin
      Writeln('NO HAY ', C);
      Continue;
    end;
    for var M in MASCARAS do
      for var F in TDirectory.GetFiles(C, M, TSearchOption.soAllDirectories) do
      begin
        if Saltar(F) then
          Continue;
        Inc(Ficheros);
        try
          UnFichero(F, Discrepa);
          Inc(Leidos);
        except
          on E: Exception do
            if not TFile.Exists(F) then
              Dec(Ficheros) // se fue mientras se recorria: no era de nadie
            else
              Writeln('NO LEE ', F, ': ', E.Message.Replace(#13, ' ').Replace(#10, ' '));
        end;
      end;
  end;
  Writeln(Format('RESUMEN ficheros=%d leidos=%d discrepancias=%d', [Ficheros, Leidos, Discrepa]));
end;

end.
