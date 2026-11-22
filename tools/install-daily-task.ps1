# Ежедневное обновление данных через Планировщик задач Windows.
# Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File tools\install-daily-task.ps1
# Удаление: ... -Remove

param([switch]$Remove)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$RefreshAll = Join-Path $PSScriptRoot 'refresh-all.ps1'
$TaskName = 'STOIT daily update'

if ($Remove) {
  & schtasks.exe /Delete /TN $TaskName /F 2>$null
  Write-Host 'Задача удалена.'
  exit 0
}

$action = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $RefreshAll + '"'
& schtasks.exe /Create /TN $TaskName /SC DAILY /ST 09:00 /TR $action /F /RL LIMITED
if ($LASTEXITCODE -ne 0) {
  Write-Host 'Не удалось создать задачу. Попробуйте запустить PowerShell от имени администратора.' -ForegroundColor Yellow
  exit 1
}

Write-Host ''
Write-Host 'Готово: данные будут обновляться каждый день в 09:00.' -ForegroundColor Green
Write-Host 'Проверить задачу: schtasks /Query /TN "STOIT daily update"'
Write-Host 'Запустить сейчас: schtasks /Run /TN "STOIT daily update"'
