# Verify that the packaged portable application starts and shows its first frame.
param([Parameter(Mandatory = $true)][string]$Archive)

$ErrorActionPreference = 'Stop'
$destination = Join-Path $env:RUNNER_TEMP ('vpn-smoke-' + [guid]::NewGuid())
$process = $null

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class VpnWindowSmoke {
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr window);
}
'@

try {
    Expand-Archive -LiteralPath $Archive -DestinationPath $destination
    $executables = @(Get-ChildItem $destination -Recurse -Filter Hiddify.exe -File)
    if ($executables.Count -ne 1) { throw 'Expected one Hiddify.exe in portable package' }
    $executable = $executables[0]
    $process = Start-Process -FilePath $executable.FullName -WorkingDirectory $executable.DirectoryName -PassThru
    $deadline = (Get-Date).AddSeconds(45)
    $visible = $false
    while ((Get-Date) -lt $deadline) {
        $process.Refresh()
        if ($process.HasExited) { throw "Application exited before showing its window: $($process.ExitCode)" }
        if ($process.MainWindowHandle -ne [IntPtr]::Zero -and [VpnWindowSmoke]::IsWindowVisible($process.MainWindowHandle)) {
            $visible = $true
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $visible) { throw 'Application did not show a visible window within 45 seconds' }
    Start-Sleep -Seconds 5
    $process.Refresh()
    if ($process.HasExited) { throw "Application exited after showing its window: $($process.ExitCode)" }
    Write-Host 'Portable application displayed a window and remained running.'
}
finally {
    if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    if (Test-Path $destination) { Remove-Item $destination -Recurse -Force }
}
