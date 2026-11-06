# FreeLLMAPI local Windows installer (Docker Desktop)
# Designed for a personal, loopback-only installation with no paid cloud resources.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$previousHostBind = [Environment]::GetEnvironmentVariable('HOST_BIND', 'Process')
$previousPort = [Environment]::GetEnvironmentVariable('PORT', 'Process')

function Assert-ExitCode {
    param([string]$Action)
    if ($LASTEXITCODE -ne 0) {
        throw "$Action failed (exit code $LASTEXITCODE)."
    }
}

Push-Location -Path $repoRoot
try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker is not installed. Install and start Docker Desktop first.'
    }
    & docker compose version
    Assert-ExitCode 'Docker Compose'
    & docker info --format '{{.ServerVersion}}' | Out-Null
    Assert-ExitCode 'Docker engine connection'

    $envPath = Join-Path $repoRoot '.env'
    if (-not (Test-Path -LiteralPath $envPath)) {
        $keyBytes = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $rng.GetBytes($keyBytes)
        }
        finally {
            $rng.Dispose()
        }
        $encryptionKey = -join ($keyBytes | ForEach-Object { $_.ToString('x2') })
        $contents = "ENCRYPTION_KEY=$encryptionKey`nPORT=3001`n"
        [System.IO.File]::WriteAllText($envPath, $contents, [System.Text.Encoding]::ASCII)
        Write-Host 'Created local .env with a random 256-bit encryption key (not committed to Git).'
    }
    else {
        $validKey = Select-String -Path $envPath -Pattern '^\s*ENCRYPTION_KEY=[0-9a-fA-F]{64}\s*$' -Quiet
        if (-not $validKey) {
            throw 'Existing .env lacks a valid 64-character hex ENCRYPTION_KEY. It was NOT overwritten. Review it manually.'
        }
        Write-Host 'Preserving the existing .env and encryption key.'
    }

    # Force loopback-only access regardless of values in inherited environment/.env.
    $env:HOST_BIND = '127.0.0.1'
    $env:PORT = '3001'

    Write-Host 'Pulling the maintained upstream Docker image...'
    & docker compose pull freellmapi
    Assert-ExitCode 'Docker image pull'

    Write-Host 'Starting FreeLLMAPI on localhost:3001 (no Watchtower profile)...'
    & docker compose up -d --no-build freellmapi
    Assert-ExitCode 'Docker Compose startup'

    $ready = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri 'http://127.0.0.1:3001/api/ping' -UseBasicParsing -TimeoutSec 3
            if ($response.StatusCode -eq 200) {
                $ready = $true
                break
            }
        }
        catch {
            # The container may still be starting.
        }
        Start-Sleep -Seconds 2
    }

    & docker compose ps freellmapi
    Assert-ExitCode 'Docker Compose status'
    if (-not $ready) {
        throw 'The API did not become ready. Run: docker compose logs --tail=100 freellmapi'
    }
    Write-Host 'FreeLLMAPI is responding at http://127.0.0.1:3001'
    Write-Host 'Add provider API keys in the local dashboard. NEVER commit .env or API keys.'
}
finally {
    [Environment]::SetEnvironmentVariable('HOST_BIND', $previousHostBind, 'Process')
    [Environment]::SetEnvironmentVariable('PORT', $previousPort, 'Process')
    Pop-Location
}
