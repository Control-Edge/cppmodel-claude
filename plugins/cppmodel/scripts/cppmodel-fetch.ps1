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

foreach ($name in @("CPPMODEL_USERNAME", "CPPMODEL_PASSWORD", "CPPMODEL_CLIENT_ID")) {
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
    $Groups = @($Claims.groups) | ForEach-Object { $_.TrimStart("/") }

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
else {
    $Name = UrlEncode $PositionalArgs[0]
    Invoke-CppModelApi "/simulations/$Name" | ConvertTo-Json -Depth 10
}
