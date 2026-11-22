# СТОИТ — полное обновление: каталоги (раз в неделю) + лента (каждый запуск).
# Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File tools\refresh-all.ps1
# Флаг -Force обновляет и каталоги, и ленту принудительно.

param([switch]$Force)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$OsmPath = Join-Path $Root 'data\osm-places.json'
$WikiPath = Join-Path $Root 'data\wiki-places.json'
$Now = Get-Date

function Test-Stale([string]$Path, [double]$Days) {
  if (-not (Test-Path $Path)) { return $true }
  return ((Get-Date) - (Get-Item $Path).LastWriteTime).TotalDays -ge $Days
}

Write-Host ''
Write-Host 'СТОИТ — обновление данных' -ForegroundColor Green

if ($Force -or (Test-Stale $OsmPath 7)) {
  Write-Host '· обновляю каталог OpenStreetMap' -ForegroundColor DarkGray
  try { & (Join-Path $PSScriptRoot 'import-osm.ps1') -Force:$Force } catch { Write-Host "  ! OSM: $($_.Exception.Message)" -ForegroundColor DarkYellow }
} else {
  Write-Host '· OSM: свежий кэш, пропускаю' -ForegroundColor DarkGray
}

if ($Force -or (Test-Stale $WikiPath 7)) {
  Write-Host '· обновляю каталог Wikidata' -ForegroundColor DarkGray
  try { & (Join-Path $PSScriptRoot 'import-wikidata.ps1') -Force:$Force } catch { Write-Host "  ! Wikidata: $($_.Exception.Message)" -ForegroundColor DarkYellow }
} else {
  Write-Host '· Wikidata: свежий кэш, пропускаю' -ForegroundColor DarkGray
}

try {
  & (Join-Path $PSScriptRoot 'collect.ps1')
} catch {
  Write-Host "  ! лента: $($_.Exception.Message)" -ForegroundColor Red
}
