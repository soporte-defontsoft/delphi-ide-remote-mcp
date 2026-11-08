unit FormRender.Partes;

{ EL compositor de un mensaje del lector EN PARTES (FormRenderProtocolo.inc,
  FR_PARTES_SEP), partido por EL formato que lo compuso: SPropertyException de
  System.RTLConsts, en el idioma que cargo ESTE proceso (rtl370.de/.fr/.ja junto
  a rtl370.bpl, por el de Windows: medido el 18-oct-2026, "Fehler beim Lesen von
  EditRight.FontColor"). El servidor lo partia con el ingles, y un lector aleman
  no nombraba nada. Su lector es PartesDeLectura (Lsp.FormRender). Lo usan los
  renderizadores (FormRender.Comun) y el conversor de estilos (DelphiStyleConvert:
  su IGNORED, que el servidor reconstruia con su propio formato, DH6 de la 1.29);
  vivia en FormRender.Comun, que el conversor no puede traer. Sin VCL ni FMX. }

interface

function LecturaEnPartes(const AMensaje: string): string;

implementation

uses
  System.SysUtils,
  System.TypInfo,  // DotSep: el punto de la ruta de una propiedad
  System.RTLConsts,
  System.RegularExpressions;

const
  {$I FormRenderProtocolo.inc}

function LecturaEnPartes(const AMensaje: string): string;
var
  Formato: string;
  Trozos: TArray<string>;
  M: TMatch;
begin
  Result := FR_PARTES_SEP + FR_PARTES_SEP + FR_PARTES_SEP + AMensaje;
  // Format(SPropertyException, [Name, DotSep, PropPath, E.Message]) de
  // TReader.ReadProperty: cuatro %s; con otro especificador (%0:s, %%) no se
  // invierte a mano, y va sin partes
  Formato := SPropertyException;
  Trozos := Formato.Split(['%s']);
  if Length(Trozos) <> 5 then
    Exit;
  for var T in Trozos do
    if T.Contains('%') then
      Exit;
  // el Name no lleva puntos; la ruta (Font.Size) llega hasta lo que separa el
  // motivo, y el motivo es lo demas: uno anidado (una coleccion) es el suyo
  M := TRegEx.Match(AMensaje, '\A' + TRegEx.Escape(Trozos[0]) + '([^.]+)' +
    TRegEx.Escape(Trozos[1] + DotSep + Trozos[2]) + '(.+?)' + TRegEx.Escape(Trozos[3]) + '(.*)' +
    TRegEx.Escape(Trozos[4]) + '\z', [roSingleLine]);
  if not M.Success then
    Exit;
  for var G := 1 to 3 do
    if M.Groups[G].Value.Contains(FR_PARTES_SEP) then
      Exit;
  Result := M.Groups[1].Value + FR_PARTES_SEP + M.Groups[2].Value + FR_PARTES_SEP + M.Groups[3].Value +
    FR_PARTES_SEP + AMensaje;
end;

end.
