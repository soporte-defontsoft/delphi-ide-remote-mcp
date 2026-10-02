unit Lsp.Chm;

{ Lector de los ficheros de ayuda compilados de Windows (.chm, HTML Help 1):
  los que el IDE registra en Help\HtmlHelp1Files y abre con F1. Cada fichero
  de dentro se lee YA DESCOMPRIMIDO por el almacenamiento de Windows
  (itss.dll, el mismo que usa el visor de ayuda): nada se extrae al disco.

  Un TChm se abre, se lee y se cierra en el MISMO hilo (COM): quien guarde
  algo de una ayuda guarda lo leido, nunca el TChm. }

interface

uses
  System.SysUtils;

type
  TChm = class
  private
    FRuta: string;
    FStg: IInterface;   // el IStorage de la raiz del .chm
    FComPropio: Boolean;
  public
    { Abre el .chm; lanza si Windows no puede abrirlo. }
    constructor Create(const ARuta: string);
    destructor Destroy; override;
    { Un fichero del .chm, entero: de la raiz ('index.hhk',
      'System.SysUtils.Format.htm', '#TOPICS') o de una carpeta de dentro
      ('html/x.htm'; sin barra delante). False si no esta o no se deja
      leer (un .chm danado): nunca lanza, una ayuda rota no tumba a las demas. }
    function Lee(const ANombre: string; out ABytes: TArray<Byte>): Boolean;
    { Los nombres de los ficheros de la raiz (sin las subcarpetas); [] si no
      se deja recorrer. }
    function Raiz: TArray<string>;
    property Ruta: string read FRuta;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ActiveX,
  Lsp.Texts;
// (sin System.Win.ComObj: su InitComObj, por InitProc, hace CoInitialize(nil)
// -STA- en el hilo principal al arrancar la bandeja o el servicio (leido en
// la RTL), y solo hacia falta para CreateComObject y OleCheck; revision de
// la 1.10.0)

const
  CLSID_ITStorage: TGUID = '{5D02926A-212E-11D0-9DF9-00A0C922E6EC}';

type
  { La interfaz de itss.dll (itss.h). Solo hasta StgOpenStorage: la tabla de
    metodos tiene que coincidir en orden hasta el ultimo que se llama. }
  IITStorage = interface(IUnknown)
    ['{88CC31DE-27AB-11D0-9DF9-00A0C922E6EC}']
    function StgCreateDocfile(pwcsName: PWideChar; grfMode, reserved: DWORD;
      out ppstgOpen: IStorage): HResult; stdcall;
    function StgCreateDocfileOnILockBytes(plkbyt: ILockBytes; grfMode,
      reserved: DWORD; out ppstgOpen: IStorage): HResult; stdcall;
    function StgIsStorageFile(pwcsName: PWideChar): HResult; stdcall;
    function StgIsStorageILockBytes(plkbyt: ILockBytes): HResult; stdcall;
    function StgOpenStorage(pwcsName: PWideChar; pstgPriority: IStorage;
      grfMode: DWORD; snbExclude: TSNB; reserved: DWORD;
      out ppstgOpen: IStorage): HResult; stdcall;
  end;

constructor TChm.Create(const ARuta: string);
var
  Its: IITStorage;
  Stg: IStorage;
  Hr: HResult;
begin
  inherited Create;
  FRuta := ARuta;
  // COM en ESTE hilo: el de la llamada (S_FALSE = ya estaba, tambien hay
  // que deshacerlo; RPC_E_CHANGED_MODE = ya estaba en otro modo, no es nuestro)
  Hr := CoInitializeEx(nil, COINIT_MULTITHREADED);
  FComPropio := Succeeded(Hr);
  Hr := CoCreateInstance(CLSID_ITStorage, nil, CLSCTX_INPROC_SERVER, IITStorage, Its);
  if Succeeded(Hr) then
    Hr := Its.StgOpenStorage(PWideChar(ARuta), nil,
      STGM_READ or STGM_SHARE_DENY_WRITE, nil, 0, Stg);
  if Failed(Hr) then
    raise Exception.Create(MsgFmt(SE_CHM_NO_ABRE_FMT, [ARuta, Hr]));
  FStg := Stg;
end;

destructor TChm.Destroy;
begin
  FStg := nil;
  if FComPropio then
    CoUninitialize;
  inherited;
end;

function TChm.Lee(const ANombre: string; out ABytes: TArray<Byte>): Boolean;
var
  Stg, Sub: IStorage;
  Stm: IStream;
  Est: TStatStg;
  Leidos: Longint;
  Total: Int64;
  Tramos: TArray<string>;
  K: Integer;
begin
  ABytes := nil;
  // las carpetas de dentro son almacenes: se abren tramo a tramo
  Tramos := ANombre.Replace('\', '/').Split(['/']);
  Stg := IStorage(FStg);
  for K := 0 to High(Tramos) - 1 do
  begin
    if (Tramos[K] = '') or (Tramos[K] = '.') or (Tramos[K] = '..') then
      Exit(False);
    if Failed(Stg.OpenStorage(PWideChar(Tramos[K]), nil,
      STGM_READ or STGM_SHARE_EXCLUSIVE, nil, 0, Sub)) then
      Exit(False);
    Stg := Sub;
  end;
  if (Length(Tramos) = 0) or (Tramos[High(Tramos)] = '') then
    Exit(False);
  Result := Succeeded(Stg.OpenStream(PWideChar(Tramos[High(Tramos)]), nil,
    STGM_READ or STGM_SHARE_EXCLUSIVE, 0, Stm));
  if not Result then
    Exit;
  if Failed(Stm.Stat(Est, STATFLAG_NONAME)) then
    Exit(False);
  SetLength(ABytes, Est.cbSize);
  Total := 0;
  while Total < Length(ABytes) do
  begin
    if Failed(Stm.Read(@ABytes[Total], Length(ABytes) - Total, @Leidos)) then
    begin
      ABytes := nil;
      Exit(False);
    end;
    if Leidos <= 0 then
      Break;
    Inc(Total, Leidos);
  end;
  SetLength(ABytes, Total);
end;

function TChm.Raiz: TArray<string>;
var
  Enum: IEnumStatStg;
  Est: TStatStg;
  N: Longint;
begin
  Result := nil;
  if Failed(IStorage(FStg).EnumElements(0, nil, 0, Enum)) then
    Exit;
  while Enum.Next(1, Est, @N) = S_OK do
    try
      if Est.dwType = STGTY_STREAM then
        Result := Result + [string(Est.pwcsName)];
    finally
      CoTaskMemFree(Est.pwcsName);
    end;
end;

end.
