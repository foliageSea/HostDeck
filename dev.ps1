[CmdletBinding()]
param(
    [string]$BackendHost = "127.0.0.1",
    [ValidateRange(1, 65535)]
    [int]$BackendPort = 8080,
    [ValidateRange(1, 300)]
    [int]$StartupTimeoutSeconds = 30
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$backendProcess = $null
$frontendProcess = $null

function Test-TcpPort {
    param(
        [string]$HostName,
        [int]$Port
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $connection = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $connection.AsyncWaitHandle.WaitOne(200)) {
            return $false
        }
        $client.EndConnect($connection)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

function Stop-ProcessTree {
    param([System.Diagnostics.Process]$Process)

    if ($null -eq $Process) {
        return
    }

    try {
        if (-not $Process.HasExited) {
            & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null
        }
    }
    catch {
        # The process may have exited between the checks.
    }
}

function Wait-Backend {
    param([System.Diagnostics.Process]$Process)

    $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            $Process.WaitForExit()
            throw "Backend exited during startup (exit code: $($Process.ExitCode))."
        }
        if (Test-TcpPort -HostName $BackendHost -Port $BackendPort) {
            return
        }
        Start-Sleep -Milliseconds 200
    }

    throw "Backend did not listen on ${BackendHost}:${BackendPort} within $StartupTimeoutSeconds seconds."
}

function Start-Backend {
    if (Test-TcpPort -HostName $BackendHost -Port $BackendPort) {
        throw "Backend port ${BackendHost}:${BackendPort} is already in use."
    }

    Write-Host "Starting backend at http://${BackendHost}:${BackendPort} ..." -ForegroundColor Cyan
    $process = Start-Process `
        -FilePath "fvm" `
        -ArgumentList @("dart", "run", "--enable-experiment=native-assets", "bin/server.dart", "--host", $BackendHost, "--port", $BackendPort) `
        -WorkingDirectory $projectRoot `
        -NoNewWindow `
        -PassThru

    try {
        Wait-Backend -Process $process
        Write-Host "Backend is ready (PID $($process.Id))." -ForegroundColor Green
        return $process
    }
    catch {
        Stop-ProcessTree -Process $process
        throw
    }
}

function Restart-Backend {
    Write-Host "Restarting backend ..." -ForegroundColor Yellow
    Stop-ProcessTree -Process $script:backendProcess
    $script:backendProcess = Start-Backend
}

function Start-Frontend {
    Write-Host "Starting frontend at http://localhost:5178 ..." -ForegroundColor Cyan
    $process = Start-Process `
        -FilePath "pnpm.cmd" `
        -ArgumentList @("--dir", "host-deck-ui", "dev") `
        -WorkingDirectory $projectRoot `
        -WindowStyle Hidden `
        -PassThru
    Write-Host "Frontend started (PID $($process.Id))." -ForegroundColor Green
    return $process
}

try {
    $backendProcess = Start-Backend
    $frontendProcess = Start-Frontend

    Write-Host ""
    Write-Host "Press [r] to restart backend, [q] to quit." -ForegroundColor DarkGray
    :inputLoop while ($true) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "R" { Restart-Backend }
            "Q" { break inputLoop }
        }
    }
}
finally {
    Write-Host "Stopping development services ..." -ForegroundColor Yellow
    Stop-ProcessTree -Process $frontendProcess
    Stop-ProcessTree -Process $backendProcess
}
