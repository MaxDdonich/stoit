$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$Root = Split-Path -Parent $PSScriptRoot
$Assets = Join-Path $Root 'assets'
New-Item -ItemType Directory -Force -Path $Assets | Out-Null

function New-StoitIcon([int]$Size, [string]$Path, [double]$Scale = 1.0) {
  $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
  $g.Clear([System.Drawing.Color]::FromArgb(9, 9, 12))

  # очень деликатная сетка
  $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(10, 255, 255, 255), [Math]::Max(1, $Size / 512))
  $step = $Size / 10
  for ($x = $step; $x -lt $Size; $x += $step) { $g.DrawLine($pen, $x, 0, $x, $Size) }
  for ($y = $step; $y -lt $Size; $y += $step) { $g.DrawLine($pen, 0, $y, $Size, $y) }
  $pen.Dispose()

  $fontSize = [single]($Size * 0.47 * $Scale)
  $font = New-Object System.Drawing.Font('Segoe UI', $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
  $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(244, 244, 247))
  $violet = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(139, 92, 246))
  $format = [System.Drawing.StringFormat]::GenericTypographic

  $text = 'с'
  $measure = $g.MeasureString($text, $font, 10000, $format)
  $dot = $Size * 0.065 * $Scale
  $gap = $Size * 0.038 * $Scale
  $groupWidth = $measure.Width + $gap + $dot
  $x = ($Size - $groupWidth) / 2
  $y = ($Size - $measure.Height) / 2
  $g.DrawString($text, $font, $white, $x, $y, $format)

  $dotX = $x + $measure.Width + $gap + $dot / 2
  $dotY = $y + $measure.Height * 0.63
  $g.FillEllipse($violet, $dotX - $dot / 2, $dotY - $dot / 2, $dot, $dot)

  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $violet.Dispose(); $white.Dispose(); $font.Dispose(); $g.Dispose(); $bmp.Dispose()
}

New-StoitIcon 512 (Join-Path $Assets 'icon-512.png') 1.0
New-StoitIcon 192 (Join-Path $Assets 'icon-192.png') 1.0
New-StoitIcon 180 (Join-Path $Assets 'icon-180.png') 1.0
New-StoitIcon 512 (Join-Path $Assets 'icon-maskable-512.png') 0.78

Write-Host 'Иконки готовы: assets/icon-192.png, icon-512.png, icon-180.png, icon-maskable-512.png'
