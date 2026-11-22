# СТОИТ — локальный веб-сервер.
# Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File tools\serve.ps1 -Open
# Сайт: http://localhost:8787

param(
  [int]$Port = 8787,
  [switch]$Open,
  [switch]$NoRefresh
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}

$Root       = Split-Path -Parent $PSScriptRoot
$FeedPath   = Join-Path $Root 'data\feed.json'
$RefreshAll = Join-Path $PSScriptRoot 'refresh-all.ps1'
$LogPath    = Join-Path $Root 'data\last-refresh.log'
$script:RefreshJob = $null
$script:LastCheck = [DateTime]::MinValue

function Test-RefreshRunning {
  if ($null -eq $script:RefreshJob) { return $false }
  try {
    $job = Get-Job -Id $script:RefreshJob.Id -ErrorAction Stop
    $script:RefreshJob = $job
    return ($job.State -eq 'Running')
  } catch {
    return $false
  }
}

function Start-Refresh {
  if (Test-RefreshRunning) { return $false }
  try {
    if ($null -ne $script:RefreshJob) {
      Remove-Job -Id $script:RefreshJob.Id -Force -ErrorAction SilentlyContinue
    }
    $script:RefreshJob = Start-Job -Name 'stoit-refresh' -ArgumentList $RefreshAll, $LogPath -ScriptBlock {
      param($refreshPath, $logPath)
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $refreshPath *> $logPath
    }
    Write-Host ("  · обновление запущено в фоне (job {0})" -f $script:RefreshJob.Id) -ForegroundColor DarkGray
    return $true
  } catch {
    Write-Host ("  ! не удалось запустить обновление: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
    return $false
  }
}

function Test-AutoRefresh {
  if ($NoRefresh) { return }
  if ((Test-RefreshRunning)) { return }
  $now = Get-Date
  if (($now - $script:LastCheck).TotalMinutes -lt 10) { return }
  $script:LastCheck = $now
  if (-not (Test-Path $FeedPath)) {
    Start-Refresh
    return
  }
  $age = $now - (Get-Item $FeedPath).LastWriteTime
  if ($age.TotalHours -ge 20) {
    Write-Host '  · данным больше 20 часов — запускаю обновление' -ForegroundColor DarkGray
    Start-Refresh
  }
}

function Get-Mime([string]$Path) {
  switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
    '.html' { return 'text/html; charset=utf-8' }
    '.css'  { return 'text/css; charset=utf-8' }
    '.js'   { return 'application/javascript; charset=utf-8' }
    '.json' { return 'application/json; charset=utf-8' }
    '.webmanifest' { return 'application/manifest+json; charset=utf-8' }
    '.svg'  { return 'image/svg+xml' }
    '.png'  { return 'image/png' }
    '.jpg'  { return 'image/jpeg' }
    '.jpeg' { return 'image/jpeg' }
    '.webp' { return 'image/webp' }
    '.ico'  { return 'image/x-icon' }
    '.txt'  { return 'text/plain; charset=utf-8' }
    '.xml'  { return 'application/xml; charset=utf-8' }
    default { return 'application/octet-stream' }
  }
}

function Send-Response {
  param(
    $Client,
    [int]$Status,
    [string]$ContentType,
    [byte[]]$Bytes,
    [bool]$HeadOnly = $false,
    [string]$Cache = 'no-cache'
  )
  $reason = switch ($Status) {
    200 { 'OK' }
    202 { 'Accepted' }
    204 { 'No Content' }
    302 { 'Found' }
    400 { 'Bad Request' }
    403 { 'Forbidden' }
    404 { 'Not Found' }
    405 { 'Method Not Allowed' }
    500 { 'Internal Server Error' }
    default { 'OK' }
  }
  if ($null -eq $Bytes) { $Bytes = New-Object byte[] 0 }
  $head = "HTTP/1.1 $Status $reason`r`nContent-Type: $ContentType`r`nContent-Length: $($Bytes.Length)`r`nConnection: close`r`nCache-Control: $Cache`r`nX-Content-Type-Options: nosniff`r`n`r`n"
  $stream = $Client.GetStream()
  $headBytes = [Text.Encoding]::ASCII.GetBytes($head)
  $stream.Write($headBytes, 0, $headBytes.Length)
  if (-not $HeadOnly -and $Bytes.Length -gt 0) {
    $stream.Write($Bytes, 0, $Bytes.Length)
  }
  $stream.Flush()
}

function Send-Html {
  param($Client, [int]$Status, [string]$Text, [bool]$HeadOnly)
  $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
  Send-Response -Client $Client -Status $Status -ContentType 'text/html; charset=utf-8' -Bytes $bytes -HeadOnly $HeadOnly
}

function Send-Json {
  param($Client, [int]$Status, $Object, [bool]$HeadOnly, [string]$Cache = 'no-store')
  $json = $Object | ConvertTo-Json -Depth 8 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  Send-Response -Client $Client -Status $Status -ContentType 'application/json; charset=utf-8' -Bytes $bytes -HeadOnly $HeadOnly -Cache $Cache
}

function Resolve-StaticPath([string]$UrlPath) {
  $decoded = [Uri]::UnescapeDataString($UrlPath)
  if ([string]::IsNullOrWhiteSpace($decoded) -or $decoded -eq '/') { $decoded = '/index.html' }
  $rel = $decoded.TrimStart('/') -replace '/', '\'
  $full = [IO.Path]::GetFullPath((Join-Path $Root $rel))
  if (-not $full.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) { return $null }
  if ($full -match '\\tools\\|\\config\\|\\.git\\|\\data\\cache\\|\\data\\translation|\\data\\seed') { return $null }
  if (Test-Path $full -PathType Container) { $full = Join-Path $full 'index.html' }
  if (-not (Test-Path $full -PathType Leaf)) {
    if ([string]::IsNullOrEmpty([IO.Path]::GetExtension($decoded))) {
      $full = Join-Path $Root 'index.html'
    } else {
      return $null
    }
  }
  return $full
}

function Handle-Client($Client) {
  $stream = $Client.GetStream()
  $Client.ReceiveTimeout = 10000
  $Client.SendTimeout = 10000
  $buffer = New-Object byte[] 16384
  $sb = New-Object Text.StringBuilder
  while ($sb.Length -lt 65536) {
    $read = $stream.Read($buffer, 0, $buffer.Length)
    if ($read -le 0) { break }
    [void]$sb.Append([Text.Encoding]::ASCII.GetString($buffer, 0, $read))
    if ($sb.ToString().Contains("`r`n`r`n")) { break }
  }
  $request = $sb.ToString()
  if ([string]::IsNullOrWhiteSpace($request)) { return }
  $firstLine = ($request -split "`r`n")[0]
  $parts = $firstLine -split ' '
  if ($parts.Count -lt 2) { Send-Html $Client 400 '<h1>Bad request</h1>' $false; return }
  $method = $parts[0].ToUpperInvariant()
  $rawPath = ($parts[1] -split '\?')[0]
  $headOnly = ($method -eq 'HEAD')

  if ($method -notin @('GET', 'HEAD', 'POST')) {
    Send-Html $Client 405 '<h1>Method not allowed</h1>' $headOnly
    return
  }

  if ($rawPath -eq '/api/status') {
    Send-Json $Client 200 ([ordered]@{
      server = $true
      refreshing = (Test-RefreshRunning)
      port = $Port
      pid = $PID
      updatedAt = if (Test-Path $FeedPath) { (Get-Item $FeedPath).LastWriteTime.ToString('o') } else { $null }
    }) $headOnly
    return
  }

  if ($rawPath -eq '/api/refresh') {
    if ($method -ne 'POST') {
      Send-Html $Client 405 '<h1>Use POST</h1>' $headOnly
      return
    }
    $started = Start-Refresh
    Send-Json $Client 202 ([ordered]@{ ok = $true; started = $started; refreshing = (Test-RefreshRunning) }) $headOnly
    return
  }

  if ($rawPath -eq '/api/feed') {
    if (-not (Test-Path $FeedPath)) {
      Send-Json $Client 503 ([ordered]@{ error = 'feed not ready' }) $headOnly
      return
    }
    $bytes = [IO.File]::ReadAllBytes($FeedPath)
    Send-Response -Client $Client -Status 200 -ContentType 'application/json; charset=utf-8' -Bytes $bytes -HeadOnly $headOnly -Cache 'no-store'
    return
  }

  if ($rawPath -eq '/health') {
    Send-Response -Client $Client -Status 200 -ContentType 'text/plain; charset=utf-8' -Bytes ([Text.Encoding]::UTF8.GetBytes('ok')) -HeadOnly $headOnly
    return
  }

  $file = Resolve-StaticPath $rawPath
  if ($null -eq $file) {
    Send-Html $Client 404 '<!doctype html><meta charset="utf-8"><title>404</title><body style="background:#09090c;color:#f4f4f7;font-family:Segoe UI,sans-serif;padding:40px"><h1>404</h1><p>Страница не найдена. <a style="color:#c4b5fd" href="/">На главную</a></p></body>' $headOnly
    return
  }

  $bytes = [IO.File]::ReadAllBytes($file)
  $mime = Get-Mime $file
  $name = [IO.Path]::GetFileName($file)
  $cache = if ($mime -match 'text/html|application/json' -or $name -in @('sw.js', 'manifest.webmanifest')) { 'no-cache' } else { 'public, max-age=3600' }
  Send-Response -Client $Client -Status 200 -ContentType $mime -Bytes $bytes -HeadOnly $headOnly -Cache $cache
}

# ---------- старт ----------
if (-not (Test-Path $FeedPath)) {
  Write-Host '  · data/feed.json не найден — запускаю первый сбор, это может занять минуту' -ForegroundColor DarkYellow
  Start-Refresh
} else {
  Test-AutoRefresh
}

try {
  $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
  $listener.Start()
} catch {
  Write-Host ("Не удалось занять порт {0}: {1}" -f $Port, $_.Exception.Message) -ForegroundColor Red
  Write-Host 'Закройте другой экземпляр сервера или запустите с -Port 8788.'
  exit 1
}

$ips = @()
try {
  $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.IPAddress -notmatch '^0\.' } |
    Select-Object -ExpandProperty IPAddress -Unique
} catch {}

Write-Host ''
Write-Host '  СТОИТ — сайт запущен' -ForegroundColor Green
Write-Host ("  На компьютере:  http://localhost:{0}/" -f $Port) -ForegroundColor White
foreach ($ip in $ips) {
  Write-Host ("  На телефоне:    http://{0}:{1}/  (та же Wi-Fi)" -f $ip, $Port) -ForegroundColor DarkGray
}
Write-Host '  Остановить: Ctrl+C' -ForegroundColor DarkGray
Write-Host ''

if ($Open) {
  try { Start-Process ("http://localhost:{0}/" -f $Port) | Out-Null } catch {}
}

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      Handle-Client $client
    } catch {
      Write-Host ("  ! запрос не обработан: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
    } finally {
      try { $client.Close() } catch {}
    }
    Test-AutoRefresh
  }
} finally {
  $listener.Stop()
}
