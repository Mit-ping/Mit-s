# Install the actual Setup EXE and verify both installation and shortcut repair.
param(
    [Parameter(Mandatory = $true)][string]$Setup,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
if (-not $env:RUNNER_TEMP) { throw 'This test requires a disposable Windows runner.' }
$setupPath = (Resolve-Path -LiteralPath $Setup).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $output -Force | Out-Null
$installation = Join-Path $env:RUNNER_TEMP ("Mit's VPN installation " + [guid]::NewGuid())
$expected = Join-Path $installation 'MitsVPN.exe'
$shell = New-Object -ComObject WScript.Shell
$links = @()
$process = $null
$report = @{}

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class MitInstalledWindow {
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr window);
}
'@

function Same-WindowsPath([string]$First, [string]$Second) {
    return [StringComparer]::OrdinalIgnoreCase.Equals(
        [IO.Path]::GetFullPath($First).TrimEnd('\'), [IO.Path]::GetFullPath($Second).TrimEnd('\'))
}

function Install-MitsPackage([string]$LogName) {
    $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/LANG=english',
        '/TASKS=desktopicon', "/DIR=`"$installation`"", "/LOG=`"$(Join-Path $output $LogName)`"")
    $installer = Start-Process -FilePath $setupPath -ArgumentList $arguments -Wait -PassThru
    if ($installer.ExitCode -ne 0) { throw "Installer exited with $($installer.ExitCode). See $LogName" }
    if (-not (Test-Path -LiteralPath $expected)) { throw 'Installer did not install MitsVPN.exe' }
    $metadata = (Get-Item -LiteralPath $expected).VersionInfo
    if ($metadata.ProductName -ne 'MitsVPN' -or $metadata.FileDescription -ne "Mit's VPN") {
        throw 'Installed application metadata is incorrect'
    }
}

function Read-ProductLinks {
    $folders = @(
        [Environment]::GetFolderPath('DesktopDirectory'),
        [Environment]::GetFolderPath('CommonDesktopDirectory'),
        [Environment]::GetFolderPath('Programs'),
        [Environment]::GetFolderPath('CommonPrograms')
    ) | Where-Object { $_ } | Select-Object -Unique
    $found = @()
    foreach ($folder in $folders) {
        $path = Join-Path $folder "Mit's VPN.lnk"
        if (Test-Path -LiteralPath $path) {
            $shortcut = $shell.CreateShortcut($path)
            if (-not (Same-WindowsPath $shortcut.TargetPath $expected)) {
                throw "Shortcut points to the wrong executable: $($shortcut.TargetPath)"
            }
            if (-not (Same-WindowsPath $shortcut.WorkingDirectory $installation)) {
                throw "Shortcut has the wrong working directory: $($shortcut.WorkingDirectory)"
            }
            $icon = $shortcut.IconLocation
            $comma = $icon.LastIndexOf(',')
            if ($comma -lt 0 -or $icon.Substring($comma + 1).Trim() -ne '0' -or
                -not (Same-WindowsPath ($icon.Substring(0, $comma).Trim('"')) $expected)) {
                throw "Shortcut uses the wrong icon: $icon"
            }
            $found += $path
        }
    }
    $desktop = @($found | Where-Object { (Split-Path $_ -Parent) -in @(
        [Environment]::GetFolderPath('DesktopDirectory'), [Environment]::GetFolderPath('CommonDesktopDirectory')) })
    $menu = @($found | Where-Object { (Split-Path $_ -Parent) -in @(
        [Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('CommonPrograms')) })
    if ($desktop.Count -lt 1 -or $menu.Count -lt 1) { throw 'Desktop and Start Menu shortcuts are required.' }
    return $found
}

function Assert-InstalledLaunch([string]$LaunchFile) {
    # Deliberately launch outside the installation directory. The shortcut must
    # supply its WorkingDir; the installed application must resolve its assets.
    Start-Process -FilePath $LaunchFile -WorkingDirectory "$env:SystemRoot\System32" | Out-Null
    $running = $null
    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline) {
        $running = Get-Process -Name MitsVPN -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $expected } | Select-Object -First 1
        if ($null -ne $running) {
            $running.Refresh()
            if (-not $running.HasExited -and $running.MainWindowHandle -ne [IntPtr]::Zero -and
                [MitInstalledWindow]::IsWindowVisible($running.MainWindowHandle)) { break }
        }
        Start-Sleep -Milliseconds 500
    }
    if ($null -eq $running -or $running.HasExited -or $running.MainWindowHandle -eq [IntPtr]::Zero -or
        -not [MitInstalledWindow]::IsWindowVisible($running.MainWindowHandle)) {
        throw "Installed application did not show its window when launched through $LaunchFile"
    }
    try {
        Start-Sleep -Seconds 5
        $running.Refresh()
        if ($running.HasExited -or $running.MainWindowTitle -notlike "*Mit's VPN*") {
            throw 'Installed application exited or showed the wrong window title.'
        }
        Write-Host "Installed app opened and remained running: $(Split-Path $LaunchFile -Leaf)"
    } finally {
        if (-not $running.HasExited) { Stop-Process -Id $running.Id -Force; $running.WaitForExit(10000) | Out-Null }
    }
}

try {
    Install-MitsPackage 'installer-fresh.log'
    $links = @(Read-ProductLinks)
    $report.fresh_install = $true
    $report.shortcut_target = 'MitsVPN.exe'
    $report.shortcut_icon = 'MitsVPN.exe,0'
    Assert-InstalledLaunch $expected
    $report.direct_launch = $true
    $desktopLink = $links | Where-Object { (Split-Path $_ -Parent) -in @(
        [Environment]::GetFolderPath('DesktopDirectory'), [Environment]::GetFolderPath('CommonDesktopDirectory')) } |
        Select-Object -First 1
    Assert-InstalledLaunch $desktopLink
    $report.desktop_launch = $true

    # Reproduce the old release's incorrect shortcut, then verify reinstallation
    # repairs its target, working directory and icon without manual user edits.
    foreach ($link in $links) {
        $broken = $shell.CreateShortcut($link)
        $broken.TargetPath = Join-Path $installation 'HiddifyAdmin.exe'
        $broken.IconLocation = "$($broken.TargetPath),0"
        $broken.WorkingDirectory = "$env:SystemRoot\System32"
        $broken.Save()
    }
    Install-MitsPackage 'installer-repair.log'
    $links = @(Read-ProductLinks)
    Assert-InstalledLaunch $desktopLink
    $report.repaired_legacy_shortcut = $true
} finally {
    Get-Process -Name MitsVPN -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $expected } | Stop-Process -Force -ErrorAction SilentlyContinue
    $uninstaller = Get-ChildItem -LiteralPath $installation -Filter 'unins*.exe' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($uninstaller) {
        $uninstall = Start-Process $uninstaller.FullName -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait -PassThru
        if ($uninstall.ExitCode -ne 0) { throw "Uninstaller exited with $($uninstall.ExitCode)" }
        if (Test-Path -LiteralPath $expected) { throw 'Uninstaller left the installed executable behind.' }
        foreach ($link in $links) {
            if (Test-Path -LiteralPath $link) { throw "Uninstaller left a product shortcut: $link" }
        }
        $report.uninstall = $true
    }
    $report | ConvertTo-Json | Set-Content (Join-Path $output 'installer-smoke-report.json') -Encoding utf8
}
Write-Host 'Fresh install, desktop launch, legacy shortcut repair and uninstall all passed.'
