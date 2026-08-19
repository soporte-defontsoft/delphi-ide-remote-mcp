unit Mcp.Vault.Session;

{ Session-level wiring for the knowledge vault: what the model is told the
  moment it connects, and the invocable /vault prompt.

  Two pieces:

  1. VaultInstructions - the MCP "instructions" field of the initialize
     response. Deliberately SHORT by default: instructions ride along in every
     prompt of every client, so the heavy doctrine stays behind vault_read (no
     path). Here goes only the bootstrap: there is a vault, and this is what to
     do first.

     A vault can REPLACE that text with its own by placing VAULT-INSTRUCTIONS.md
     at its root - that file is the vault's "skill": it can name the projects,
     the language to write in and whatever else that particular vault needs.
     Nothing about any given vault is hardcoded in this server; without the
     file, the generic protocol is used.

  2. TMCPPromptsManager - the MCP prompts capability, exposing a single prompt
     named "vault" that returns the bootstrap content (rules + index). Clients
     surface prompts as user-invocable commands (in Claude Code it shows up as
     /vault), which is handy to reload the index mid-session or to force the
     bootstrap on a client that ignores instructions.

  Both are inert when no vault is configured. }

interface

uses
  System.SysUtils,
  System.JSON,
  System.Rtti,
  MCPServer.Types;

{ The initialize "instructions" text ('' when no vault is configured). }
function VaultInstructions: string;

{ The bootstrap content: the vault's rules + its index, as one document.
  Shared by the /vault prompt and vault_read-with-no-path. }
function VaultBootstrapText: string;

type
  TMCPPromptsManager = class(TInterfacedObject, IMCPCapabilityManager)
  public
    function GetCapabilityName: string;
    function HandlesMethod(const Method: string): Boolean;
    function ExecuteMethod(const Method: string; const Params: TJSONObject): TValue;
  end;

implementation

uses
  System.IOUtils,
  System.Classes,
  Lsp.Guard,
  Lsp.Texts,
  Mcp.Vault.Seed;

const
  INSTRUCTIONS_FILE = 'VAULT-INSTRUCTIONS.md';
  MAX_INSTRUCTIONS = 8000; // instructions ride in every prompt: keep them sane

function VaultBootstrapText: string;
var
  Sb: TStringBuilder;
  Full: string;
begin
  Sb := TStringBuilder.Create;
  try
    for var Boot in ['AGENTS-VAULT.md', 'MEMORY.md'] do
    begin
      Full := TPath.Combine(VaultPath, Boot);
      Sb.AppendLine('===== ' + Boot + ' =====');
      Sb.AppendLine;
      if TFile.Exists(Full) then
        try
          Sb.AppendLine(TFile.ReadAllText(Full, TEncoding.UTF8).TrimRight);
        except
          on E: Exception do
            Sb.AppendLine('(no se pudo leer: ' + E.Message + ')');
        end
      else
        Sb.AppendLine('(este vault no tiene ' + Boot + ')');
      Sb.AppendLine;
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function VaultInstructions: string;
var
  Custom: string;
begin
  Result := '';
  if not VaultConfigured then
    Exit;
  // The vault's own instructions win: this is where a particular vault says
  // what it contains, in which language to write, and which projects it covers.
  Custom := TPath.Combine(VaultPath, INSTRUCTIONS_FILE);
  if TFile.Exists(Custom) then
  begin
    try
      Result := TFile.ReadAllText(Custom, TEncoding.UTF8).Trim;
    except
      Result := '';
    end;
    if Result <> '' then
    begin
      if Length(Result) > MAX_INSTRUCTIONS then
        Result := Copy(Result, 1, MAX_INSTRUCTIONS) + sLineBreak +
          '(...) Continua con vault_read sin path.';
      Exit;
    end;
  end;
  // Fallback: the generic protocol, true of any vault.
  Result := SN_VAULT_INSTRUCTIONS;
end;

{ TMCPPromptsManager }

function TMCPPromptsManager.GetCapabilityName: string;
begin
  Result := 'prompts';
end;

function TMCPPromptsManager.HandlesMethod(const Method: string): Boolean;
begin
  Result := (Method = 'prompts/list') or (Method = 'prompts/get');
end;

function TMCPPromptsManager.ExecuteMethod(const Method: string;
  const Params: TJSONObject): TValue;
var
  Res, Prompt, Msg, Content: TJSONObject;
  Arr: TJSONArray;
  Name: string;
begin
  Res := TJSONObject.Create;
  try
    if Method = 'prompts/list' then
    begin
      Arr := TJSONArray.Create;
      Res.AddPair('prompts', Arr);
      if VaultConfigured then
      begin
        Prompt := TJSONObject.Create;
        Arr.AddElement(Prompt);
        Prompt.AddPair('name', 'vault');
        Prompt.AddPair('title', 'Cargar el vault de conocimiento');
        Prompt.AddPair('description', SD_VAULT_PROMPT);
        Prompt.AddPair('arguments', TJSONArray.Create);
      end;
    end
    else // prompts/get
    begin
      Name := '';
      if Assigned(Params) then
        Params.TryGetValue<string>('name', Name);
      if not SameText(Name, 'vault') then
        raise Exception.CreateFmt('Unknown prompt: %s', [Name]);
      if not VaultConfigured then
        raise Exception.Create('No knowledge vault is configured on this server.');
      Res.AddPair('description', SD_VAULT_PROMPT);
      Arr := TJSONArray.Create;
      Res.AddPair('messages', Arr);
      Msg := TJSONObject.Create;
      Arr.AddElement(Msg);
      Msg.AddPair('role', 'user');
      Content := TJSONObject.Create;
      Msg.AddPair('content', Content);
      Content.AddPair('type', 'text');
      Content.AddPair('text', SN_VAULT_PROMPT_HEADER + sLineBreak + sLineBreak +
        VaultBootstrapText);
    end;
    Result := TValue.From<TJSONObject>(Res);
  except
    Res.Free;
    raise;
  end;
end;

initialization
  // First run: a configured vault path that does not exist yet, or that holds
  // no notes, is seeded with the starter templates - so pointing the setting
  // at a fresh folder on a new machine yields a working vault instead of a
  // dead end. An existing vault is never touched. This runs BEFORE
  // Mcp.Tools.Vault decides whether to register its tools (unit order in the
  // .dpr), and silently: the host logs VaultSeedNote once the logger is up,
  // because in stdio mode stdout is the protocol channel.
  SeedVaultIfEmpty(VaultPath);

end.
