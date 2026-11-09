param([Parameter(Mandatory)][string]$CoreDirectory, [string]$OutputDirectory = 'out/service-check')
$ErrorActionPreference = 'Stop'
$CoreDirectory = (Resolve-Path $CoreDirectory).Path
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$OutputDirectory = (Resolve-Path $OutputDirectory).Path
$cli = Join-Path $CoreDirectory 'HiddifyCli.exe'
$serviceName = 'HiddifyAdminBG'
$owner = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$report = [ordered]@{ service_installed = $false; secret_acl = $false; engine_started = $false; proxy_traffic = $false; tun_created = $false; tun_traffic = $false }
$origin = $null
try {
    & $cli admin_bgservice install $owner 2>&1 | Out-File (Join-Path $OutputDirectory 'install.log')
    $service = Get-Service $serviceName
    $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(25))
    $report.service_installed = $true
    $secretPath = Join-Path $env:PROGRAMDATA 'Hiddify/AdminBgService/control.secret'
    $acl = Get-Acl $secretPath
    $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
    $sids = @($rules | ForEach-Object { $_.IdentityReference.Value })
    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)) {
        if ($sid -notin $sids) { throw "Missing expected ACL SID: $sid" }
    }
    if (-not $acl.AreAccessRulesProtected) { throw 'Secret ACL must disable inherited access' }
    $report.secret_acl = $true
    # Only a reserved benchmark prefix is routed through TUN; runner access stays intact.
    $origin = Start-Job -ScriptBlock {
        function Read-Headers($stream) {
            $header = ''
            while (-not $header.EndsWith("`r`n`r`n")) {
                $value = $stream.ReadByte()
                if ($value -lt 0) { throw 'Client closed' }
                $header += [char]$value
                if ($header.Length -gt 8192) { throw 'Header too large' }
            }
            return $header
        }
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 18320)
        $listener.Start()
        try {
            while ($true) {
                $client = $listener.AcceptTcpClient()
                $client.ReceiveTimeout = 3000
                try {
                    $stream = $client.GetStream()
                    $header = Read-Headers $stream
                    if ($header.StartsWith('CONNECT ')) {
                        $bytes = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 Connection Established`r`n`r`n")
                        $stream.Write($bytes, 0, $bytes.Length)
                        $null = Read-Headers $stream
                    }
                    $bytes = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Length: 14`r`nConnection: close`r`n`r`nmits-vpn-check")
                    $stream.Write($bytes, 0, $bytes.Length)
                } catch {} finally { $client.Dispose() }
            }
        } finally { $listener.Stop() }
    }
    $ready = $false
    for ($i = 0; $i -lt 50; $i++) {
        if (Get-NetTCPConnection -LocalPort 18320 -State Listen -ErrorAction SilentlyContinue) { $ready = $true; break }
        Start-Sleep -Milliseconds 200
    }
    if (-not $ready) { throw 'Local test proxy did not start' }
    $config = @{
        log = @{ level = 'debug' }
        inbounds = @(
            @{ type = 'mixed'; tag = 'test-proxy'; listen = '127.0.0.1'; listen_port = 18318 },
            @{ type = 'tun'; tag = 'test-tun'; interface_name = 'MitsVpnTest'; address = @('172.29.255.1/30'); auto_route = $true; strict_route = $false; route_address = @('198.18.0.0/15'); stack = 'gvisor' }
        )
        outbounds = @(@{ type = 'http'; tag = 'test-upstream'; server = '127.0.0.1'; server_port = 18320 })
        route = @{ auto_detect_interface = $true; final = 'test-upstream' }
    }
    $request = @{
        configContent = ($config | ConvertTo-Json -Depth 20 -Compress)
        configName = 'Windows service regression'; ownerPid = $PID
        settingsJSON = (@{ 'enable-full-config' = $true; 'enable-tun' = $true; 'enable-clash-api' = $false; 'enable-ntp' = $false } | ConvertTo-Json -Compress)
    }
    $requestPath = Join-Path $OutputDirectory 'test-request.json'
    $request | ConvertTo-Json -Depth 20 | Set-Content $requestPath -Encoding utf8NoBOM
    & $cli admin_bgservice connect $requestPath 2>&1 | Out-File (Join-Path $OutputDirectory 'connect.log')
    $adapter = Get-NetAdapter -IncludeHidden | Where-Object Name -eq 'MitsVpnTest'
    if (-not $adapter) { throw 'The background core did not create the TUN adapter' }
    $report.engine_started = $true
    $report.tun_created = $true
    $response = & curl.exe --silent --show-error --fail --max-time 15 --noproxy '' --proxy socks5h://127.0.0.1:18318 http://198.18.0.1:18319/
    if ($LASTEXITCODE -ne 0 -or $response -ne 'mits-vpn-check') { throw 'Traffic through the background service failed' }
    $report.proxy_traffic = $true
    $response = & curl.exe --silent --show-error --fail --max-time 15 --noproxy '*' http://198.18.0.1:18319/
    if ($LASTEXITCODE -ne 0 -or $response -ne 'mits-vpn-check') { throw 'Traffic through TUN failed' }
    $report.tun_traffic = $true
} finally {
    if ($origin) { Stop-Job $origin -ErrorAction SilentlyContinue; Remove-Job $origin -Force -ErrorAction SilentlyContinue }
    & $cli admin_bgservice disconnect 2>&1 | Out-File (Join-Path $OutputDirectory 'disconnect.log')
    & $cli admin_bgservice uninstall 2>&1 | Out-File (Join-Path $OutputDirectory 'uninstall.log')
    $report | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'result.json')
}
