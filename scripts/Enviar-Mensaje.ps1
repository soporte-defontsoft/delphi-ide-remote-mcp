<#
  Deja un mensaje en el buzon de un agente (delphi_messages).

    .\Enviar-Mensaje.ps1 -Agente dsh -Titulo "Reconecta" -Texto "El server se reinicio; sigue con el Deploy."


  El agente lo recibe al final de su siguiente llamada a cualquier tool (la
  linea PENDING MESSAGES) y lo lee con delphi_messages: se entrega una vez y
  se BORRA al leerlo. No hay buzon "para todos": un aviso para todos se deja
  una vez por agente (un mensaje sin -Agente iba a una carpeta que nadie lee).
#>
param(
  [Parameter(Mandatory)][string]$Agente,
  [Parameter(Mandatory)][string]$Titulo,
  [Parameter(Mandatory)][string]$Texto,
  [string]$Servidor = 'C:\Delphi-mcp-Server'
)
$dir = Join-Path (Join-Path $Servidor 'messages') (($Agente -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLower())
New-Item -ItemType Directory -Force $dir | Out-Null
$slug = (($Titulo -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLower())
if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40) }
$file = Join-Path $dir ("{0}-{1}.md" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $slug)
$body = "# $Titulo`r`n`r`n- **Fecha**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n`r`n---`r`n`r`n$Texto`r`n"
[IO.File]::WriteAllText($file, $body, (New-Object Text.UTF8Encoding $false))
Write-Host "Mensaje dejado en $file"
