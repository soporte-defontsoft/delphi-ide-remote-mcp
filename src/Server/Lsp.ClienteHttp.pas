unit Lsp.ClienteHttp;

{ El transporte de delphi_api (1.29): UNA peticion HTTP(S) por THTTPClient
  (WinHTTP) a una API que declara el operador (Lsp.Conexiones), con lo que
  midio la sonda del 6-nov-2026 (SondaApi129):

  - No sigue redirecciones: un 3xx vuelve con su Location y la credencial no
    viaja a otro sitio.
  - No presenta la cuenta del servicio (UseDefaultCredentials, que la RTL
    trae a True: NTLM/Negotiate con la identidad del servidor).
  - El plazo de la conexion es el de la peticion ENTERA, y lo pone el
    servidor (Lsp.ConPlazo): el de WinHTTP, con 2 s, contestaba a los 4
    aislado y, dentro de una tanda, unas veces a los 2,5 y otras nunca
    (medido el 6-nov-2026). Vencido, la peticion se cancela.
  - El certificado: sin pin, el juicio de Windows y nada mas; con pin, SOLO
    el servidor cuya clave publica es ESA. El pin es el estandar (PinDeSpki)
    y sale del certificado REAL de la conexion: el TCertificate de la RTL
    solo trae el modulo RSA (vacio con una clave EC, medido con un
    certificado publico), asi que se lee el handle WinHTTP de la peticion
    (su campo FWRequest, por RTTI) y Windows da el certificado y su
    SubjectPublicKeyInfo (CryptEncodeObject). Con pin, las banderas de "CA
    desconocida, nombre, fecha" van ANTES de enviar: el handshake no falla y
    el evento de validacion salta en SENDING_REQUEST sobre la conexion que
    lleva la peticion; si el pin no casa, la RTL cierra antes de enviar
    (medido: no llega NADA al servidor). Sin ellas, la RTL juzga el
    certificado del handshake fallido y reintenta con otro que ya no vuelve
    a pasar por el evento.
  - Con pin y sin que el evento llegue a saltar (otra RTL), la respuesta no
    se devuelve: falla cerrado. }

interface

uses
  Lsp.Conexiones;

type
  { fhPlazo: no contesto dentro del plazo de la conexion (el del servidor,
    Lsp.ConPlazo); fhInterno: una excepcion que no es de red (ADetalle:
    'Clase: mensaje'). }
  TFalloHttp = (fhNinguno, fhRed, fhCertificado, fhPin, fhPlazo, fhInterno);

  TRespuestaHttp = record
    Estado: Integer;
    TextoDeEstado: string;
    Cabeceras: TArray<TNombreValor>;
    Cuerpo: TArray<Byte>;
    Recortado: Boolean;     // se dejo de leer al pasar de LIMITE_CUERPO_HTTP
    Milisegundos: Int64;
  end;

const
  // lo que se trae de un cuerpo como mucho (lo que cabe en un out=); lo que
  // vuelve en la respuesta de la tool lo recorta ella
  LIMITE_CUERPO_HTTP = 32 * 1024 * 1024;
  // las cabeceras que pone el transporte (WinHTTP y el cliente) y nunca el
  // agente: politica NUESTRA, declarada (no hay juez de "que cabecera puede
  // poner quien pide"); las de la conexion, CabecerasDeLaConexion
  CABECERAS_DEL_TRANSPORTE: array [0 .. 9] of string = ('Host', 'Content-Length', 'Transfer-Encoding',
    'Connection', 'Keep-Alive', 'Upgrade', 'TE', 'Trailer', 'Proxy-Authorization', 'Proxy-Connection');

{ AMetodo a AUrl (ya compuesta) con ACabeceras y ACuerpo (vacio = sin cuerpo)
  por la conexion AConexion (su plazo y su pin). True con ARespuesta; si no,
  AFallo y ADetalle (el texto del cliente, SIN enmascarar: lo enmascara quien
  lo devuelve). APinVisto, el pin del certificado que presento el servidor si
  se llego a ver: lo dice la negativa, para que el operador lo ancle. }
function PeticionHttp(const AConexion: TConexionApi; const AMetodo, AUrl: string;
  const ACabeceras: TArray<TNombreValor>; const ACuerpo: TArray<Byte>; out ARespuesta: TRespuestaHttp;
  out AFallo: TFalloHttp; out ADetalle, APinVisto: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.Rtti, System.Diagnostics,
  System.Net.URLClient, System.Net.HttpClient,
  Winapi.Windows, Winapi.WinHTTP,
  Lsp.ConPlazo; // TrabajoConPlazo: el plazo de WinHTTP no se cumple siempre (medido)

// CryptoAPI: lo justo para el SPKI de un certificado. La RTL no trae su
// unidad (System.Net.HttpClient.Win declara los suyos igual).
type
  CRYPT_INTEGER_BLOB = record
    cbData: DWORD;
    pbData: PByte;
  end;
  CRYPT_ALGORITHM_IDENTIFIER = record
    pszObjId: PAnsiChar;
    Parameters: CRYPT_INTEGER_BLOB;
  end;
  CRYPT_BIT_BLOB = record
    cbData: DWORD;
    pbData: PByte;
    cUnusedBits: DWORD;
  end;
  CERT_PUBLIC_KEY_INFO = record
    Algorithm: CRYPT_ALGORITHM_IDENTIFIER;
    PublicKey: CRYPT_BIT_BLOB;
  end;
  // CERT_INFO hasta SubjectPublicKeyInfo: lo de detras no se lee
  PCERT_INFO = ^CERT_INFO;
  CERT_INFO = record
    dwVersion: DWORD;
    SerialNumber: CRYPT_INTEGER_BLOB;
    SignatureAlgorithm: CRYPT_ALGORITHM_IDENTIFIER;
    Issuer: CRYPT_INTEGER_BLOB;
    NotBefore: TFileTime;
    NotAfter: TFileTime;
    Subject: CRYPT_INTEGER_BLOB;
    SubjectPublicKeyInfo: CERT_PUBLIC_KEY_INFO;
  end;
  PCCERT_CONTEXT = ^CERT_CONTEXT;
  CERT_CONTEXT = record
    dwCertEncodingType: DWORD;
    pbCertEncoded: PByte;
    cbCertEncoded: DWORD;
    pCertInfo: PCERT_INFO;
    hCertStore: Pointer;
  end;

function CryptEncodeObject(dwCertEncodingType: DWORD; lpszStructType: PAnsiChar; pvStructInfo: Pointer;
  pbEncoded: PByte; var pcbEncoded: DWORD): BOOL; stdcall; external 'crypt32.dll';
function CertFreeCertificateContext(pCertContext: PCCERT_CONTEXT): BOOL; stdcall; external 'crypt32.dll';

const
  X509_ASN_ENCODING = 1;
  X509_PUBLIC_KEY_INFO = PAnsiChar(8);
  // el campo privado de TWinHTTPRequest con su handle (System.Net.HttpClient.Win)
  CAMPO_HANDLE_WINHTTP = 'FWRequest';
  // con pin, lo que no juzga Windows: lo juzga el pin
  BANDERAS_DEL_PIN = SECURITY_FLAG_IGNORE_UNKNOWN_CA or SECURITY_FLAG_IGNORE_CERT_WRONG_USAGE or
    SECURITY_FLAG_IGNORE_CERT_CN_INVALID or SECURITY_FLAG_IGNORE_CERT_DATE_INVALID;

{ El handle WinHTTP de una peticion de THTTPClient; nil si esta RTL no lo
  tiene donde se midio. }
function HandleDe(AReq: TObject): HINTERNET;
var
  Ctx: TRttiContext;
  F: TRttiField;
begin
  Result := nil;
  if AReq = nil then
    Exit;
  F := Ctx.GetType(AReq.ClassType).GetField(CAMPO_HANDLE_WINHTTP);
  if F <> nil then
    Result := F.GetValue(AReq).AsType<HINTERNET>;
end;

{ El pin del certificado que presenta el servidor en la peticion AReq; '' si
  no se puede leer. }
function PinDeLaPeticion(AReq: TObject): string;
var
  H: HINTERNET;
  C: PCCERT_CONTEXT;
  Tam, N: DWORD;
  Der: TArray<Byte>;
begin
  Result := '';
  H := HandleDe(AReq);
  if H = nil then
    Exit;
  C := nil;
  Tam := SizeOf(C);
  if not WinHttpQueryOption(H, WINHTTP_OPTION_SERVER_CERT_CONTEXT, C, Tam) or (C = nil) then
    Exit;
  try
    N := 0;
    if not CryptEncodeObject(X509_ASN_ENCODING, X509_PUBLIC_KEY_INFO, @C^.pCertInfo^.SubjectPublicKeyInfo,
      nil, N) or (N = 0) then
      Exit;
    SetLength(Der, N);
    if not CryptEncodeObject(X509_ASN_ENCODING, X509_PUBLIC_KEY_INFO, @C^.pCertInfo^.SubjectPublicKeyInfo,
      @Der[0], N) then
      Exit;
    SetLength(Der, N);
    Result := PinDeSpki(Der);
  finally
    CertFreeCertificateContext(C);
  end;
end;

type
  { Lo que juzga una peticion mientras va: el certificado y el tope. }
  TJuezDePeticion = class
  public
    Pin: string;        // el del operador ('' = el juicio de Windows)
    PinVisto: string;
    Veces: Integer;
    Recortado: Boolean;
    procedure Valida(const Sender: TObject; const ARequest: TURLRequest; const Certificate: TCertificate;
      var Accepted: Boolean);
    procedure Recibe(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean);
  end;

procedure TJuezDePeticion.Valida(const Sender: TObject; const ARequest: TURLRequest;
  const Certificate: TCertificate; var Accepted: Boolean);
begin
  Inc(Veces);
  PinVisto := PinDeLaPeticion(ARequest);
  if Pin <> '' then
    Accepted := (PinVisto <> '') and (PinVisto = Pin)
  else
    // sin pin, Windows: el evento salta tambien cuando el certificado no le
    // vale (la RTL lo pregunta antes de rendirse), y ahi se niega
    Accepted := (Sender as THTTPClient).SecureFailureReasons = [];
end;

procedure TJuezDePeticion.Recibe(const Sender: TObject; AContentLength, AReadCount: Int64;
  var AAbort: Boolean);
begin
  if AReadCount > LIMITE_CUERPO_HTTP then
  begin
    Recortado := True;
    AAbort := True;
  end;
end;

type
  { Una peticion en curso: lo que crea, lo que deja y quien la libera
    (Lsp.ConPlazo: quien la pidio si acaba a tiempo, el hilo si no). }
  TPeticion = class
  public
    Cli: THTTPClient;
    Juez: TJuezDePeticion;
    Req: IHTTPRequest;
    Resp: IHTTPResponse;
    Fuente: TBytesStream;
    Destino: TBytesStream;
    Fallo: TFalloHttp;
    Detalle: string;
    // el plazo vencio: lo que devuelva la RTL despues no vale (una peticion
    // cancelada puede volver como Success, Win: ERROR_WINHTTP_OPERATION_CANCELLED)
    Vencida: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TPeticion.Create;
begin
  inherited Create;
  Juez := TJuezDePeticion.Create;
  Cli := THTTPClient.Create;
  Destino := TBytesStream.Create;
end;

destructor TPeticion.Destroy;
begin
  Req := nil;
  Resp := nil;
  Destino.Free;
  Fuente.Free;
  Cli.Free;
  Juez.Free;
  inherited;
end;

function PeticionHttp(const AConexion: TConexionApi; const AMetodo, AUrl: string;
  const ACabeceras: TArray<TNombreValor>; const ACuerpo: TArray<Byte>; out ARespuesta: TRespuestaHttp;
  out AFallo: TFalloHttp; out ADetalle, APinVisto: string): Boolean;
var
  P: TPeticion;
  Reloj: TStopwatch;
  Banderas: DWORD;
  H: HINTERNET;
  C: TNombreValor;
begin
  Result := False;
  ARespuesta := Default(TRespuestaHttp);
  AFallo := fhNinguno;
  ADetalle := '';
  APinVisto := '';
  P := TPeticion.Create;
  try
    P.Juez.Pin := AConexion.Pin;
    P.Cli.HandleRedirects := False;
    P.Cli.UseDefaultCredentials := False;
    P.Cli.AllowCookies := False;
    P.Cli.AutomaticDecompression := [THTTPCompressionMethod.Any];
    // los de WinHTTP, por si llegan antes; el que vale es el de abajo
    P.Cli.ConnectionTimeout := AConexion.Plazo * 1000;
    P.Cli.SendTimeout := AConexion.Plazo * 1000;
    P.Cli.ResponseTimeout := AConexion.Plazo * 1000;
    P.Cli.OnValidateServerCertificate := P.Juez.Valida;
    P.Cli.OnReceiveData := P.Juez.Recibe;
    try
      P.Req := P.Cli.GetRequest(AMetodo, AUrl);
    except
      on E: ENetException do
      begin
        AFallo := fhRed;
        ADetalle := E.Message;
        P.Free;
        Exit;
      end;
    end;
    for C in ACabeceras do
      P.Req.AddHeader(C.Nombre, C.Valor);
    if Length(ACuerpo) > 0 then
    begin
      P.Fuente := TBytesStream.Create(ACuerpo);
      P.Req.SourceStream := P.Fuente;
    end;
    if AConexion.Pin <> '' then
    begin
      Banderas := BANDERAS_DEL_PIN;
      H := HandleDe(P.Req as TObject);
      if (H = nil) or not WinHttpSetOption(H, WINHTTP_OPTION_SECURITY_FLAGS, @Banderas, SizeOf(Banderas)) then
      begin
        // sin el handle no se puede anclar: no se envia
        AFallo := fhPin;
        P.Free;
        Exit;
      end;
    end;
  except
    P.Free;
    raise;
  end;
  Reloj := TStopwatch.StartNew;
  if not TrabajoConPlazo(
    procedure
    begin
      try
        P.Resp := P.Cli.Execute(P.Req, P.Destino);
      except
        on E: ENetHTTPCertificateException do
        begin
          P.Fallo := fhCertificado;
          P.Detalle := E.Message;
        end;
        on E: ENetException do
        begin
          P.Fallo := fhRed;
          P.Detalle := E.Message;
        end;
        on E: Exception do
        begin
          P.Fallo := fhInterno;
          P.Detalle := E.ClassName + ': ' + E.Message;
        end;
      end;
    end, AConexion.Plazo * 1000,
    // vencido: se anota ANTES de cancelar, y lo que vuelva ya no cuenta
    procedure
    begin
      P.Vencida := True;
      P.Req.Cancel;
    end,
    procedure
    begin
      P.Free;
    end) then
  begin
    AFallo := fhPlazo;
    Exit;
  end;
  try
    ARespuesta.Milisegundos := Reloj.ElapsedMilliseconds;
    APinVisto := P.Juez.PinVisto;
    if P.Vencida then
    begin
      AFallo := fhPlazo;
      Exit;
    end;
    if P.Fallo <> fhNinguno then
    begin
      AFallo := P.Fallo;
      // con pin, un certificado negado es el pin que no casa
      if (AFallo = fhCertificado) and (AConexion.Pin <> '') then
        AFallo := fhPin;
      ADetalle := P.Detalle;
      Exit;
    end;
    // con pin, sin que el evento saltara: no se sabe con quien se hablo
    if (AConexion.Pin <> '') and (P.Juez.Veces = 0) then
    begin
      AFallo := fhPin;
      Exit;
    end;
    ARespuesta.Estado := P.Resp.StatusCode;
    ARespuesta.TextoDeEstado := P.Resp.StatusText;
    for var Cab in P.Resp.Headers do
    begin
      C.Nombre := Cab.Name;
      C.Valor := Cab.Value;
      ARespuesta.Cabeceras := ARespuesta.Cabeceras + [C];
    end;
    ARespuesta.Cuerpo := Copy(P.Destino.Bytes, 0, P.Destino.Size);
    ARespuesta.Recortado := P.Juez.Recortado;
    Result := True;
  finally
    P.Free;
  end;
end;

end.
