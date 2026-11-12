unit ChangeWatch;

interface

uses
  System.Classes;

var
  Changes: Integer = 0;

procedure WatchList(const AList: TStringList);

implementation

procedure ListChanged(Sender: TObject);
begin
  Inc(Changes);
end;

procedure WatchList(const AList: TStringList);
begin
  AList.OnChange := ListChanged;
end;

end.
