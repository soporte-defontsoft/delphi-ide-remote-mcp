unit BackgroundSum;

interface

uses
  System.SysUtils;

// Sums 1..ACount on a background thread and hands the total to AOnDone ON THE MAIN THREAD
procedure SumInBackground(const ACount: Integer; const AOnDone: TProc<Int64>);

implementation

uses
  System.Classes;

procedure SumInBackground(const ACount: Integer; const AOnDone: TProc<Int64>);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      I: Integer;
      Total: Int64;
    begin
      Total := 0;
      for I := 1 to ACount do
        Inc(Total, I);
      // never touch the UI from here: Queue runs the procedure on the main thread
      // (and does not wait for it, unlike Synchronize)
      TThread.Queue(nil,
        procedure
        begin
          AOnDone(Total);
        end);
    end).Start;
end;

end.
