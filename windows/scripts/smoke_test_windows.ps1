# Verify that the packaged portable application starts and shows its first frame.
param([Parameter(Mandatory = $true)][string]$Archive, [string]$Screenshot)

$ErrorActionPreference = 'Stop'
$destination = Join-Path $env:RUNNER_TEMP ('vpn-smoke-' + [guid]::NewGuid())
$process = $null

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class VpnWindowSmoke {
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr window);
    [StructLayout(LayoutKind.Sequential)]
    public struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr window, out Rect rect);
}
'@

try {
    Expand-Archive -LiteralPath $Archive -DestinationPath $destination
    $executables = @(Get-ChildItem $destination -Recurse -Filter MitsVPN.exe -File)
    if ($executables.Count -ne 1) { throw 'Expected one MitsVPN.exe in portable package' }
    $executable = $executables[0]
    if ($executable.Directory.Name -ne 'MitsVPN') { throw 'Unexpected portable package folder' }
    if ($executable.VersionInfo.ProductName -ne 'MitsVPN' -or $executable.VersionInfo.FileDescription -ne "Mit's VPN") {
        throw 'Executable metadata still contains the wrong product identity'
    }
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
    if ($process.MainWindowTitle -notlike "*Mit's VPN*") { throw "Unexpected window title: $($process.MainWindowTitle)" }
    if ($Screenshot) {
        Add-Type -AssemblyName System.Drawing
        $rect = New-Object VpnWindowSmoke+Rect
        if (-not [VpnWindowSmoke]::GetWindowRect($process.MainWindowHandle, [ref]$rect)) { throw 'Cannot capture application window' }
        $bitmap = New-Object System.Drawing.Bitmap(($rect.Right - $rect.Left), ($rect.Bottom - $rect.Top))
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
            $bitmap.Save([IO.Path]::GetFullPath($Screenshot), [System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
    }
    Write-Host 'Portable application displayed a window and remained running.'
}
finally {
    if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    if (Test-Path $destination) { Remove-Item $destination -Recurse -Force }
}
