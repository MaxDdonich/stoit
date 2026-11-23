# СТОИТ — проверка заведений по Яндекс Картам.
# Статус «Больше не работает» и реальный адрес/метро берутся из выдачи Яндекс Карт.
# Подключается из collect.ps1.

function Test-MapsPlaceholder([string]$Value) {
  $v = ([string]$Value).Trim().ToLowerInvariant()
  if (-not $v) { return $true }
  if ($v -match '^(уточните|уточнить|проверьте|check)') { return $true }
  return ($v -eq 'москва' -or $v -eq 'moscow' -or $v -eq 'город москва')
}

function ConvertTo-MapsKey([string]$Value) {
  if (-not $Value) { return '' }
  $s = $Value.ToLowerInvariant() -replace 'ё', 'е'
  $s = [regex]::Replace($s, '[^a-zа-я0-9]+', ' ')
  return ($s -replace '\s+', ' ').Trim()
}

function Test-MapsNameMatch([string]$A, [string]$B) {
  $a = ConvertTo-MapsKey $A
  $b = ConvertTo-MapsKey $B
  if (-not $a -or -not $b) { return $false }
  if ($a -eq $b) { return $true }
  $at = @($a -split ' ' | Where-Object { $_.Length -ge 3 })
  $bt = @($b -split ' ' | Where-Object { $_.Length -ge 3 })
  if ($at.Count -gt 0 -and $bt.Count -gt 0) {
    $common = @($at | Where-Object { $bt -contains $_ }).Count
    if ($common -gt 0) {
      if ($at.Count -le $bt.Count -and $common -eq $at.Count) { return $true }
      if ($bt.Count -lt $at.Count -and $common -eq $bt.Count) { return $true }
    }
  }
  $aFlat = $a -replace ' ', ''
  $bFlat = $b -replace ' ', ''
  if ($aFlat.Length -ge 4 -and $bFlat.Length -ge 4) {
    if ($aFlat.Contains($bFlat) -or $bFlat.Contains($aFlat)) { return $true }
  }
  return $false
}

function Get-GeoDistance([double]$Lat1, [double]$Lon1, [double]$Lat2, [double]$Lon2) {
  if (-not $Lat1 -or -not $Lon1 -or -not $Lat2 -or -not $Lon2) { return 999999 }
  $r = 6371000
  $dLat = ($Lat2 - $Lat1) * [Math]::PI / 180
  $dLon = ($Lon2 - $Lon1) * [Math]::PI / 180
  $a = [Math]::Sin($dLat / 2) * [Math]::Sin($dLat / 2) +
    [Math]::Cos($Lat1 * [Math]::PI / 180) * [Math]::Cos($Lat2 * [Math]::PI / 180) *
    [Math]::Sin($dLon / 2) * [Math]::Sin($dLon / 2)
  return $r * 2 * [Math]::Atan2([Math]::Sqrt($a), [Math]::Sqrt(1 - $a))
}

function Get-MapsItems([string]$Html) {
  if (-not $Html) { return @() }
  $idx = $Html.IndexOf('"items":[{"type":"business"')
  if ($idx -lt 0) { return @() }
  $start = $Html.IndexOf('[', $idx)
  if ($start -lt 0) { return @() }
  $depth = 0
  $end = -1
  $inStr = $false
  $escaped = $false
  for ($i = $start; $i -lt $Html.Length; $i++) {
    $c = $Html[$i]
    if ($inStr) {
      if ($escaped) { $escaped = $false }
      elseif ($c -eq '\') { $escaped = $true }
      elseif ($c -eq '"') { $inStr = $false }
      continue
    }
    if ($c -eq '"') { $inStr = $true; continue }
    if ($c -eq '[' -or $c -eq '{') { $depth++ }
    if ($c -eq ']' -or $c -eq '}') {
      $depth--
      if ($depth -eq 0) { $end = $i; break }
    }
  }
  if ($end -lt 0) { return @() }
  try { return @($Html.Substring($start, $end - $start + 1) | ConvertFrom-Json) } catch { return @() }
}

function Test-MapsDistinctiveName([string]$Value) {
  $key = ConvertTo-MapsKey $Value
  if ($key.Length -lt 4) { return $false }
  $generic = @('кафе', 'бар', 'ресторан', 'кофейня', 'пекарня', 'столовая', 'магазин', 'парк', 'музей', 'театр', 'кинотеатр', 'клуб', 'салон', 'аптека', 'парикмахерская', 'отель', 'гостиница', 'фитнес', 'спортзал', 'центр', 'дом', 'галерея', 'библиотека', 'каток', 'бассейн', 'боулинг', 'квест', 'студия', 'школа', 'выставка', 'площадка')
  $meaningful = @($key -split ' ' | Where-Object { $_.Length -ge 3 -and $generic -notcontains $_ })
  return ($meaningful.Count -ge 1)
}

function Get-YandexPlaceCheck($Place) {
  $name = [string]$Place.name.ru
  if (-not $name) { return $null }
  # «Кафе», «Парк», «Кофейня» — по такому названию нельзя опознать заведение.
  if (-not (Test-MapsDistinctiveName $name)) { return [pscustomobject]@{ status = 'unknown' } }
  $lat = 0.0
  $lon = 0.0
  try { $lat = [double]$Place.lat } catch {}
  try { $lon = [double]$Place.lon } catch {}
  $url = 'https://yandex.ru/maps/?mode=search&text=' + [Uri]::EscapeDataString($name)
  if ($lat -and $lon) {
    $url += '&ll=' + [Uri]::EscapeDataString("$lon,$lat") + '&z=16'
  }
  $html = Get-RemoteText $url
  if (-not $html) { return $null }
  if ($html -match '(?i)smartcaptcha|showcaptcha|Подтвердите, что запросы отправляли вы') {
    return [pscustomobject]@{ status = 'captcha' }
  }
  $items = @(Get-MapsItems $html)
  if ($items.Count -eq 0) { return [pscustomobject]@{ status = 'notfound' } }

  $best = $null
  $bestScore = -1.0
  $bestDistance = 999999
  foreach ($item in $items) {
    $coords = @($item.coordinates)
    $dist = 999999
    if ($coords.Count -eq 2 -and $lat -and $lon) {
      $dist = Get-GeoDistance $lat $lon ([double]$coords[1]) ([double]$coords[0])
    }
    $nameOk = Test-MapsNameMatch $name ([string]$item.title)
    if (-not $nameOk) { continue }
    if ($dist -gt 2000) { continue }
    $score = 1000 - [Math]::Min(999.0, $dist / 10)
    if ($score -gt $bestScore) { $bestScore = $score; $best = $item; $bestDistance = $dist }
  }
  if ($null -eq $best) { return [pscustomobject]@{ status = 'notfound' } }

  $rawStatus = [string]$best.status
  $status = 'unknown'
  if ($rawStatus -match 'closed') { $status = 'closed' }
  elseif ($rawStatus -eq 'open') { $status = 'open' }

  $metroName = ''
  if ($best.metro -and @($best.metro).Count -gt 0) { $metroName = [string]$best.metro[0].name }
  $mapsUrl = ''
  if ($best.id) {
    $mapsUrl = 'https://yandex.ru/maps/org/' + [string]$best.id + '/'
  }
  return [pscustomobject]@{
    status = $status
    rawStatus = $rawStatus
    title = [string]$best.title
    address = [string]$best.fullAddress
    metro = $metroName
    mapsUrl = $mapsUrl
    distance = [int][Math]::Round($bestDistance)
  }
}

function Apply-MapsRecord($Place, $Rec) {
  if ($null -eq $Rec) { return }
  $status = [string]$Rec.status
  if ($status -eq 'closed') {
    Set-PlaceField $Place 'closed' $true
    Set-PlaceField $Place 'closedSource' 'yandex-maps'
    if ($Rec.mapsUrl) { Set-PlaceField $Place 'mapsUrl' ([string]$Rec.mapsUrl) }
    return
  }
  if ($status -eq 'open') {
    Set-PlaceField $Place 'mapsVerified' $true
    if ($Rec.mapsUrl) { Set-PlaceField $Place 'mapsUrl' ([string]$Rec.mapsUrl) }
    $nearby = $true
    try { if ($Rec.distance -and [int]$Rec.distance -gt 400) { $nearby = $false } } catch {}
    if (-not $nearby) { return }
    if ($Rec.address -and (Test-MapsPlaceholder ([string]$Place.address.ru))) {
      $addr = ([string]$Rec.address) -replace '^Москва,\s*', ''
      Set-PlaceField $Place 'address' ([pscustomobject]@{ ru = $addr; en = $addr })
    }
    if ($Rec.metro -and (Test-MapsPlaceholder ([string]$Place.metro.ru))) {
      Set-PlaceField $Place 'metro' ([pscustomobject]@{ ru = [string]$Rec.metro; en = [string]$Rec.metro })
    }
    return
  }
  if ($status -eq 'notfound') {
    $addrPlaceholder = Test-MapsPlaceholder ([string]$Place.address.ru)
    $metroPlaceholder = Test-MapsPlaceholder ([string]$Place.metro.ru)
    $noGallery = (-not $Place.gallery -or @($Place.gallery).Count -eq 0)
    $commercial = @('food', 'coffee', 'shop', 'games', 'antikafe') -contains [string]$Place.category
    if ($commercial -and $addrPlaceholder -and $metroPlaceholder -and -not $Place.website -and -not $Place.image -and -not $Place.commonsCategory -and $noGallery) {
      Set-PlaceField $Place 'closed' $true
      Set-PlaceField $Place 'closedSource' 'yandex-maps'
      Set-PlaceField $Place 'closedReason' 'not-found-on-maps'
    }
  }
}

function Invoke-PlaceVerification {
  param(
    $Places,
    [int]$MaxChecks = 40,
    [string]$StatusPath,
    [switch]$SkipNetwork
  )
  $store = @{}
  $raw = Read-Json $StatusPath
  if ($null -ne $raw -and $null -ne $raw.places) {
    foreach ($prop in $raw.places.PSObject.Properties) { $store[$prop.Name] = $prop.Value }
  }

  foreach ($place in $Places) {
    $sid = [string]$place.id
    if ($store.ContainsKey($sid)) { Apply-MapsRecord $place $store[$sid] }
  }

  $checked = 0
  $closed = 0
  $verified = 0
  if (-not $SkipNetwork) {
    $candidates = @($Places | Where-Object {
      if ($_.closed) { return $false }
      $sid = [string]$_.id
      if (-not $store.ContainsKey($sid)) { return $true }
      $rec = $store[$sid]
      if ([string]$rec.status -eq 'closed') { return $false }
      try { return (($Now - [DateTimeOffset]::Parse([string]$rec.checkedAt)).TotalDays -ge 30) } catch { return $true }
    })
    # Сначала проверяем «пустые» карточки без адреса, сайта и фото.
    $candidates = @($candidates | Sort-Object {
      $score = 0
      if (Test-MapsPlaceholder ([string]$_.address.ru)) { $score += 4 }
      if (-not $_.website) { $score += 2 }
      if (-not $_.gallery -or @($_.gallery).Count -eq 0) { $score += 1 }
      $score
    } -Descending)

    $captchaHits = 0
    foreach ($place in $candidates) {
      if ($checked -ge $MaxChecks) { break }
      $result = Get-YandexPlaceCheck $place
      if ($null -eq $result) { continue }
      if ([string]$result.status -eq 'captcha') {
        $captchaHits += 1
        if ($captchaHits -ge 2) { break }
        Start-Sleep -Seconds 4
        continue
      }
      $captchaHits = 0
      $record = [ordered]@{
        status = [string]$result.status
        title = [string]$result.title
        address = [string]$result.address
        metro = [string]$result.metro
        mapsUrl = [string]$result.mapsUrl
        distance = [int]$result.distance
        checkedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
      }
      $store[[string]$place.id] = $record
      $checked += 1
      if ($record.status -eq 'closed') { $closed += 1 }
      if ($record.status -eq 'open') { $verified += 1 }
      Apply-MapsRecord $place $record
      Start-Sleep -Milliseconds 1200
    }
  }

  $out = [ordered]@{
    updatedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
    places = [ordered]@{}
  }
  foreach ($key in ($store.Keys | Sort-Object)) { $out.places[$key] = $store[$key] }
  try { Save-Json $out $StatusPath } catch {}
  return [ordered]@{ checked = $checked; closed = $closed; verified = $verified; known = $store.Count }
}
