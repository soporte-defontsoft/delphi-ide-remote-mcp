unit Mld.Dyn;

{ Carga dinamica de librerias del sistema (dlopen/dlsym/dlclose).

  El nodo NO enlaza en compilacion ninguna libreria del escritorio Linux: las
  abre en ejecucion. Tres motivos medidos:
    - compilar no necesita esas librerias en el sysroot ni tocar el SDK;
    - el mismo fuente vale en 13.1 y en 13.2 (migrar = recompilar);
    - si en una maquina falta una libreria, el programa lo DICE con claridad
      en vez de no llegar a arrancar. }

interface

type
  { Una libreria compartida abierta en ejecucion. }
  TLibreria = class
  private
    FHandle: NativeUInt;
    FNombre: string;
    FError: string;
  public
    destructor Destroy; override;
    { Abre por soname, p.ej. 'libdbus-1.so.3'. False deja el motivo en Error. }
    function Abrir(const ANombre: string): Boolean;
    procedure Cerrar;
    { Resuelve un simbolo. False deja el motivo en Error. }
    function Simbolo(const ASimbolo: string; out ADireccion: Pointer): Boolean;
    { Lo mismo, y si falta deja en AMotivo el texto de siempre: que simbolo,
      de que libreria y por que (SF_NODE_FALTA_EN_FMT). Estaba escrito cuatro
      veces (Mld.X11, Mld.DBus, Mld.Eis, Mld.Teclado) y el de Teclado ya
      ponia el nombre de la libreria a mano. }
    function SimboloOMotivo(const ASimbolo: string; out ADireccion: Pointer;
      var AMotivo: string): Boolean;
    function Abierta: Boolean;
    property Nombre: string read FNombre;
    property Error: string read FError;
  end;

implementation

uses
  System.SysUtils,
  Posix.Dlfcn,
  Mld.Textos;

const
  { Linux x86-64: la RTL solo declara estas constantes para Android. }
  RTLD_NOW = 2;

function ErrorDl: string;
var
  P: MarshaledAString;
begin
  P := dlerror;
  if P = nil then
    Result := ''
  else
    Result := string(UTF8String(P));
end;

destructor TLibreria.Destroy;
begin
  Cerrar;
  inherited;
end;

function TLibreria.Abierta: Boolean;
begin
  Result := FHandle <> 0;
end;

function TLibreria.Abrir(const ANombre: string): Boolean;
var
  U: UTF8String;
begin
  Cerrar;
  FNombre := ANombre;
  FError := '';
  U := UTF8String(ANombre);
  dlerror; // descarta cualquier error anterior
  FHandle := dlopen(MarshaledAString(PAnsiChar(U)), RTLD_NOW);
  Result := FHandle <> 0;
  if not Result then
    FError := ErrorDl;
end;

procedure TLibreria.Cerrar;
begin
  if FHandle <> 0 then
  begin
    dlclose(FHandle);
    FHandle := 0;
  end;
end;

function TLibreria.Simbolo(const ASimbolo: string; out ADireccion: Pointer): Boolean;
var
  U: UTF8String;
begin
  ADireccion := nil;
  if FHandle = 0 then
  begin
    FError := MsgText(SF_NODE_LIBRERIA_NO_ABIERTA);
    Exit(False);
  end;
  U := UTF8String(ASimbolo);
  dlerror;
  ADireccion := dlsym(FHandle, MarshaledAString(PAnsiChar(U)));
  Result := ADireccion <> nil;
  if not Result then
    FError := ErrorDl;
end;

function TLibreria.SimboloOMotivo(const ASimbolo: string; out ADireccion: Pointer;
  var AMotivo: string): Boolean;
begin
  Result := Simbolo(ASimbolo, ADireccion);
  if not Result then
    AMotivo := MsgFmt(SF_NODE_FALTA_EN_FMT, [ASimbolo, FNombre, FError]);
end;

end.
