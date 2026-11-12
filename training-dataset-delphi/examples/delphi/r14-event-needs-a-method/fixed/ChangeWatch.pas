unit ChangeWatch;

interface

uses
  System.Classes;

type
  // An event such as OnChange (TNotifyEvent) is "procedure(Sender: TObject) of object":
  // it needs a METHOD of an object, not a standalone procedure
  TListWatcher = class
  private
    FChanges: Integer;
  public
    procedure ListChanged(Sender: TObject);
    property Changes: Integer read FChanges;
  end;

procedure WatchList(const AList: TStringList; const AWatcher: TListWatcher);

implementation

procedure TListWatcher.ListChanged(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure WatchList(const AList: TStringList; const AWatcher: TListWatcher);
begin
  AList.OnChange := AWatcher.ListChanged;
end;

end.
