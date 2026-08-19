unit Lsp.Discovery;

{ Locates the RAD Studio installation via the Windows registry - no hardcoded
  paths. Checks HKCU first (per-user data also lives there), then HKLM, in
  both 32-bit and 64-bit registry views. Picks the highest installed BDS
  version that actually ships a DelphiLSP.exe. }

interface

type
  TRadStudioInfo = record
    Version: string;   // e.g. '37.0'
    RootDir: string;   // e.g. 'C:\Program Files (x86)\Embarcadero\Studio\37.0\'
    DelphiLspExe: string;
    RsVarsBat: string;
    function Found: Boolean;
  end;

function DiscoverRadStudio: TRadStudioInfo;

{ The IDE's global Library Search Path for a platform ('Win32'/'Win64'),
  raw, with its $() variables unexpanded. This is where INSTALLED COMPONENT
  packages (third-party) register their source/dcu paths - a project using
  them usually does not repeat those paths in its .dproj, so the Config
  Fabricator must merge this list to resolve their symbols. '' if absent. }
function IdeLibrarySearchPath(const AVersion, APlatform: string): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Win.Registry,
  Winapi.Windows;

function TRadStudioInfo.Found: Boolean;
begin
  Result := DelphiLspExe <> '';
end;

function TryRoot(ARootKey: HKEY; AAccess: LongWord; out AInfo: TRadStudioInfo): Boolean;
var
  Reg: TRegistry;
  Keys: TStringList;
  I: Integer;
  Best: Double;
  Ver, RootDir, Exe: string;
  VerNum: Double;
  Fmt: TFormatSettings;
begin
  Result := False;
  AInfo := Default(TRadStudioInfo);
  Best := -1;
  Fmt := TFormatSettings.Invariant;

  Reg := TRegistry.Create(KEY_READ or AAccess);
  Keys := TStringList.Create;
  try
    Reg.RootKey := ARootKey;
    if not Reg.OpenKeyReadOnly('SOFTWARE\Embarcadero\BDS') then
      Exit;
    Reg.GetKeyNames(Keys);
    Reg.CloseKey;

    for I := 0 to Keys.Count - 1 do
    begin
      Ver := Keys[I];
      VerNum := StrToFloatDef(Ver, -1, Fmt);
      if VerNum <= Best then
        Continue;
      if not Reg.OpenKeyReadOnly('SOFTWARE\Embarcadero\BDS\' + Ver) then
        Continue;
      RootDir := Reg.ReadString('RootDir');
      Reg.CloseKey;
      if RootDir = '' then
        Continue;
      Exe := IncludeTrailingPathDelimiter(RootDir) + 'bin\DelphiLSP.exe';
      if FileExists(Exe) then
      begin
        Best := VerNum;
        AInfo.Version := Ver;
        AInfo.RootDir := IncludeTrailingPathDelimiter(RootDir);
        AInfo.DelphiLspExe := Exe;
        AInfo.RsVarsBat := AInfo.RootDir + 'bin\rsvars.bat';
        Result := True;
      end;
    end;
  finally
    Keys.Free;
    Reg.Free;
  end;
end;

function DiscoverRadStudio: TRadStudioInfo;
begin
  // Order matters: user hive first, then machine hive; each in both views.
  if TryRoot(HKEY_CURRENT_USER, 0, Result) then Exit;
  if TryRoot(HKEY_CURRENT_USER, KEY_WOW64_32KEY, Result) then Exit;
  if TryRoot(HKEY_LOCAL_MACHINE, 0, Result) then Exit;
  if TryRoot(HKEY_LOCAL_MACHINE, KEY_WOW64_32KEY, Result) then Exit;
  Result := Default(TRadStudioInfo);
end;

function IdeLibrarySearchPath(const AVersion, APlatform: string): string;
var
  Reg: TRegistry;
begin
  Result := '';
  // Library settings are per-user: HKCU only (both registry views).
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(Format('SOFTWARE\Embarcadero\BDS\%s\Library\%s',
      [AVersion, APlatform])) and Reg.ValueExists('Search Path') then
      Result := Reg.ReadString('Search Path');
  finally
    Reg.Free;
  end;
end;

end.
