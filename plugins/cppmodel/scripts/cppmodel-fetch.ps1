#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$RepoRoot = (& git rev-parse --show-toplevel).Trim()
$EnvFile = Join-Path $RepoRoot ".env"

if (-not (Test-Path $EnvFile)) {
    Write-Error "Missing $EnvFile"
    exit 1
}

$EnvVars = @{}
Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
        $EnvVars[$Matches[1]] = $Matches[2]
    }
}

# Public client every account uses (see api/workspace-api.yaml); .env may override it.
if (-not $EnvVars["CPPMODEL_CLIENT_ID"]) { $EnvVars["CPPMODEL_CLIENT_ID"] = "cppmodel-frontend" }

foreach ($name in @("CPPMODEL_USERNAME", "CPPMODEL_PASSWORD")) {
    if (-not $EnvVars.ContainsKey($name) -or [string]::IsNullOrEmpty($EnvVars[$name])) {
        Write-Error "$name not set in .env"
        exit 1
    }
}

$WorkspaceOverride = $null
$PositionalArgs = @()
$i = 0
while ($i -lt $args.Count) {
    if ($args[$i] -eq "--workspace") {
        $WorkspaceOverride = $args[$i + 1]
        $i += 2
    }
    else {
        $PositionalArgs += $args[$i]
        $i += 1
    }
}

$DiscoveryUrl = "https://auth.cppmodel.com/realms/CppModel/.well-known/openid-configuration"
$Discovery = Invoke-RestMethod -Uri $DiscoveryUrl
$TokenEndpoint = $Discovery.token_endpoint

$TokenResponse = Invoke-RestMethod -Uri $TokenEndpoint -Method Post -Body @{
    grant_type = "password"
    client_id  = $EnvVars["CPPMODEL_CLIENT_ID"]
    username   = $EnvVars["CPPMODEL_USERNAME"]
    password   = $EnvVars["CPPMODEL_PASSWORD"]
}
$AccessToken = $TokenResponse.access_token

function Resolve-Workspace {
    param([string]$Token, [string]$Override)

    if ($Override) {
        return $Override
    }

    $PayloadSegment = $Token.Split(".")[1].Replace("-", "+").Replace("_", "/")
    $PayloadSegment = $PayloadSegment.PadRight($PayloadSegment.Length + ((4 - $PayloadSegment.Length % 4) % 4), [char]'=')
    $PayloadJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($PayloadSegment))
    $Claims = $PayloadJson | ConvertFrom-Json
    # @(...) around the whole pipeline: with one group, ForEach-Object would otherwise yield a bare
    # string and $Groups[0] would be its first character.
    $Groups = @(@($Claims.groups) | ForEach-Object { $_.TrimStart("/") })

    if ($Groups.Count -eq 1) {
        return $Groups[0]
    }
    elseif ($Groups.Count -eq 0) {
        Write-Error "Token has no workspace groups; pass --workspace explicitly."
        exit 1
    }
    else {
        Write-Error "Token belongs to multiple workspaces ($($Groups -join ', ')); pass --workspace to pick one."
        exit 1
    }
}

$Workspace = Resolve-Workspace -Token $AccessToken -Override $WorkspaceOverride
$ApiBase = "https://$Workspace.cppmodel.com/api"

function Invoke-CppModelApi {
    param([string]$Path)
    Invoke-RestMethod -Uri "$ApiBase$Path" -Headers @{ Authorization = "Bearer $AccessToken" }
}

function UrlEncode([string]$Value) {
    [System.Uri]::EscapeDataString($Value)
}

if ($PositionalArgs.Count -eq 0) {
    Invoke-CppModelApi "/simulations?scope=user" | ConvertTo-Json -Depth 10
}
elseif ($PositionalArgs[0] -eq "executions") {
    $Name = UrlEncode $PositionalArgs[1]
    Invoke-CppModelApi "/simulations/$Name/executions" | ConvertTo-Json -Depth 10
}
elseif ($PositionalArgs[0] -eq "execution") {
    $Name = UrlEncode $PositionalArgs[1]
    $ExecutionId = UrlEncode $PositionalArgs[2]
    Invoke-CppModelApi "/simulations/$Name/executions/$ExecutionId" | ConvertTo-Json -Depth 10
}
elseif ($PositionalArgs[0] -eq "inputs") {
    $Name = UrlEncode $PositionalArgs[1]
    ConvertTo-Json -InputObject (Invoke-CppModelApi "/simulations/$Name/inputs") -Depth 10
}
elseif ($PositionalArgs[0] -eq "set-inputs") {
    # Replaces the simulation's whole input/parameter document with the JSON file's contents.
    $File = $PositionalArgs[2]
    if (-not $File -or -not (Test-Path $File)) {
        Write-Error "Usage: set-inputs <simulation name> <inputs.json>"
        exit 1
    }
    $Name = UrlEncode $PositionalArgs[1]
    # Send raw UTF-8 bytes - Windows PowerShell 5.1 would otherwise re-encode a string body.
    $Body = [System.Text.Encoding]::UTF8.GetBytes((Get-Content -Raw -Encoding UTF8 $File))
    Invoke-RestMethod -Uri "$ApiBase/simulations/$Name/inputs" -Method Post -Body $Body `
        -ContentType "application/json; charset=utf-8" -Headers @{ Authorization = "Bearer $AccessToken" } | Out-Null
    Write-Host "Inputs saved for '$($PositionalArgs[1])'"
}
else {
    $Name = UrlEncode $PositionalArgs[0]
    Invoke-CppModelApi "/simulations/$Name" | ConvertTo-Json -Depth 10
}
