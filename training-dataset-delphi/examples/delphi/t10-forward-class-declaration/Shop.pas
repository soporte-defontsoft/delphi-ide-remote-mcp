unit Shop;

interface

uses
  System.Generics.Collections;

type
  TCustomer = class; // forward declaration: completed below, in this same type section

  TOrder = class
  private
    FCustomer: TCustomer;
  public
    constructor Create(const ACustomer: TCustomer);
    property Customer: TCustomer read FCustomer;
  end;

  TCustomer = class
  private
    FName: string;
    FOrders: TObjectList<TOrder>;
  public
    constructor Create(const AName: string);
    destructor Destroy; override;
    function AddOrder: TOrder;
    property Name: string read FName;
    property Orders: TObjectList<TOrder> read FOrders;
  end;

implementation

constructor TOrder.Create(const ACustomer: TCustomer);
begin
  inherited Create;
  FCustomer := ACustomer;
end;

constructor TCustomer.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  FOrders := TObjectList<TOrder>.Create(True); // owns its orders
end;

destructor TCustomer.Destroy;
begin
  FOrders.Free;
  inherited Destroy;
end;

function TCustomer.AddOrder: TOrder;
begin
  Result := TOrder.Create(Self);
  FOrders.Add(Result);
end;

end.
