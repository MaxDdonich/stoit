# СТОИТ — импорт мест из OpenStreetMap.
# Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File tools\import-osm.ps1
# Флаг -Force игнорирует недельный кэш запросов.

param([switch]$Force)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}

$Root      = Split-Path -Parent $PSScriptRoot
$DataDir   = Join-Path $Root 'data'
$CacheDir  = Join-Path $DataDir 'cache'
$OutPath   = Join-Path $DataDir 'osm-places.json'
$SeedPath  = Join-Path $DataDir 'seed.json'
$UA        = 'STOIT/1.0 (Moscow city guide; open data import)'
$Now       = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(3))
$Endpoints = @('https://overpass-api.de/api/interpreter')

New-Item -ItemType Directory -Force -Path $DataDir, $CacheDir | Out-Null

function Read-Json([string]$Path) {
  if (-not (Test-Path $Path)) { return $null }
  return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json)
}
function Write-Json($Object, [string]$Path) {
  [IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
}
function Tag($Tags, [string]$Key) {
  if ($null -eq $Tags) { return '' }
  $p = $Tags.PSObject.Properties[$Key]
  if ($null -ne $p -and $null -ne $p.Value) { return [string]$p.Value }
  return ''
}

$queries = @(
  @{ name = 'cafes';     cat = 'coffee'; limit = 240; q = '[out:json][timeout:70];(nwr["amenity"="cafe"]["name"](55.57,37.35,55.92,37.95););out center tags 240;' },
  @{ name = 'restaurants'; cat = 'food'; limit = 160; q = '[out:json][timeout:70];(nwr["amenity"="restaurant"]["name"](55.57,37.35,55.92,37.95););out center tags 160;' },
  @{ name = 'fastfood';  cat = 'food';  limit = 100; q = '[out:json][timeout:70];(nwr["amenity"="fast_food"]["name"](55.57,37.35,55.92,37.95);nwr["amenity"="food_court"]["name"](55.57,37.35,55.92,37.95);nwr["amenity"="ice_cream"]["name"](55.57,37.35,55.92,37.95););out center tags 100;' },
  @{ name = 'bars';      cat = 'food';  limit = 80;  q = '[out:json][timeout:70];(nwr["amenity"="bar"]["name"](55.57,37.35,55.92,37.95);nwr["amenity"="pub"]["name"](55.57,37.35,55.92,37.95););out center tags 80;' },
  @{ name = 'active';    cat = 'active'; limit = 200; q = '[out:json][timeout:70];(nwr["leisure"="bowling_alley"]["name"](55.57,37.35,55.92,37.95);nwr["leisure"="trampoline_park"]["name"](55.57,37.35,55.92,37.95);nwr["leisure"="escape_game"]["name"](55.57,37.35,55.92,37.95);nwr["shop"="board_games"]["name"](55.57,37.35,55.92,37.95);nwr["amenity"="karaoke_box"]["name"](55.57,37.35,55.92,37.95);nwr["leisure"="ice_rink"]["name"](55.57,37.35,55.92,37.95);nwr["leisure"="water_park"]["name"](55.57,37.35,55.92,37.95););out center tags 200;' }
)

function Get-Overpass([string]$Name, [string]$Query) {
  $cache = Join-Path $CacheDir ("osm-" + $Name + ".json")
  if (-not $Force -and (Test-Path $cache)) {
    $age = $Now - (Get-Item $cache).LastWriteTime
    if ($age.TotalDays -lt 7) {
      Write-Host ("  {0,-9} кэш" -f $Name) -ForegroundColor DarkGray
      return [IO.File]::ReadAllText($cache, [Text.Encoding]::UTF8)
    }
  }
  foreach ($endpoint in $Endpoints) {
    for ($try = 1; $try -le 4; $try++) {
      $tmp = [IO.Path]::GetTempFileName()
      try {
        $code = & curl.exe -sS -G --max-time 120 -A $UA -H 'Accept: application/json' --data-urlencode "data=$Query" -o $tmp -w '%{http_code}' $endpoint 2>$null
        $len = 0
        if (Test-Path $tmp) { $len = (Get-Item $tmp).Length }
        if ("$code" -eq '200' -and $len -gt 100) {
          $text = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8)
          [IO.File]::WriteAllText($cache, $text, (New-Object Text.UTF8Encoding($false)))
          Write-Host ("  {0,-9} ok, {1} КБ" -f $Name, [Math]::Round($len / 1024)) -ForegroundColor Green
          return $text
        }
        Write-Host ("  {0,-9} попытка {1}: HTTP {2}" -f $Name, $try, $code) -ForegroundColor DarkYellow
      } catch {
        Write-Host ("  {0,-9} попытка {1}: соединение сброшено" -f $Name, $try) -ForegroundColor DarkYellow
      } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
      }
      Start-Sleep -Seconds (5 * $try)
    }
  }
  if (Test-Path $cache) {
    Write-Host ("  {0,-9} беру старый кэш" -f $Name) -ForegroundColor DarkYellow
    return [IO.File]::ReadAllText($cache, [Text.Encoding]::UTF8)
  }
  return $null
}

$seedNames = @{}
$seed = Read-Json $SeedPath
if ($null -ne $seed) {
  foreach ($p in $seed.places) {
    $n = ([string]$p.name.ru).ToLowerInvariant() -replace '[^\wа-яё]+', ' '
    $seedNames[$n.Trim()] = $true
  }
}

function Get-Category($Batch, $Tags, [string]$Name) {
  $text = ("$Name " + (Tag $Tags 'description') + ' ' + (Tag $Tags 'cuisine')).ToLowerInvariant()
  if ($text -match 'антикафе|anti[- ]?cafe|циферблат|кочерга|тайм[- ]?кафе|time cafe') { return 'antikafe' }
  if ($Batch.cat -eq 'coffee') { return 'coffee' }
  if ($Batch.cat -eq 'food') { return 'food' }
  if ($Batch.cat -eq 'active') {
    if ($text -match 'квест|quest|escape|боулинг|bowling|настол|board game|караоке|karaoke') { return 'games' }
    return 'active'
  }
  return $Batch.cat
}

$units = @{
  coffee = @{ ru = 'средний чек'; en = 'average bill' };
  food = @{ ru = 'средний чек'; en = 'average bill' };
  antikafe = @{ ru = 'за первый час'; en = 'first hour' };
  culture = @{ ru = 'за вход'; en = 'entry' };
  walk = @{ ru = 'вход'; en = 'entry' };
  games = @{ ru = 'за визит'; en = 'per visit' };
  active = @{ ru = 'за час'; en = 'per hour' };
  movie = @{ ru = 'за билет'; en = 'per ticket' }
}
$companies = @{
  coffee = @{ ru = '1–3 человека'; en = '1–3 people' };
  food = @{ ru = '2–4 человека'; en = '2–4 people' };
  antikafe = @{ ru = '2–6 человек'; en = '2–6 people' };
  culture = @{ ru = '1–4 человека'; en = '1–4 people' };
  walk = @{ ru = 'Любая компания'; en = 'Any group' };
  games = @{ ru = '2–6 человек'; en = '2–6 people' };
  active = @{ ru = '2–6 человек'; en = '2–6 people' };
  movie = @{ ru = '1–4 человека'; en = '1–4 people' }
}
$tagRu = @{
  coffee = @('кофе', 'свидание'); food = @('поесть', 'с друзьями');
  antikafe = @('настолки', 'с друзьями', 'дождь'); culture = @('культура', 'свидание', 'дождь');
  walk = @('гулять', 'на улице', 'бесплатно'); games = @('с друзьями', 'на компанию', 'дождь');
  active = @('активность', 'с друзьями'); movie = @('кино', 'дождь', 'свидание')
}
$tagEn = @{
  coffee = @('coffee', 'date'); food = @('eat', 'with friends');
  antikafe = @('board games', 'with friends', 'rainy day'); culture = @('culture', 'date', 'rainy day');
  walk = @('walk', 'outdoors', 'free'); games = @('with friends', 'for a group', 'rainy day');
  active = @('active', 'with friends'); movie = @('cinema', 'rainy day', 'date')
}
$getRu = @{
  coffee = @('Кофе и десерт', 'Можно зайти на 20–30 минут', 'Есть шанс найти свободный столик');
  food = @('Сытый обед или ужин', 'Подходит для встречи с друзьями', 'Порции и цену уточните на месте');
  antikafe = @('Время и напитки', 'Настольные игры и диваны', 'Можно прийти компанией');
  culture = @('Билет или вход', 'Постоянная экспозиция', 'Фото и впечатления');
  walk = @('Свободный вход', 'Маршрут на 1–3 часа', 'Хорошо в любую погоду, кроме совсем плохой');
  games = @('Час игры или дорожка', 'Компания и азарт', 'Снэки и напитки рядом');
  active = @('Час активности', 'Инструктаж и снаряжение', 'Хорошо для компании');
  movie = @('Билет в кино', 'Большой экран и звук', 'Попкорн и напитки рядом')
}
$getEn = @{
  coffee = @('Coffee and dessert', 'Easy 20–30 minute stop', 'A chance of a free table');
  food = @('A proper lunch or dinner', 'Good for meeting friends', 'Check portions and prices on site');
  antikafe = @('Time and drinks', 'Board games and sofas', 'Bring a group');
  culture = @('A ticket or entry', 'Permanent exhibition', 'Photos and impressions');
  walk = @('Free entry', 'A 1–3 hour route', 'Good in most weather');
  games = @('An hour of play or a lane', 'Company and competition', 'Snacks and drinks nearby');
  active = @('An hour of activity', 'Briefing and equipment', 'Great for a group');
  movie = @('A cinema ticket', 'Big screen and sound', 'Popcorn and drinks nearby')
}
$hooksRu = @{
  coffee = 'Кофейня в районе {0}'; food = 'Место поесть в районе {0}';
  antikafe = 'Антикафе в районе {0}'; culture = 'Культурное место в районе {0}';
  walk = 'Прогулка в районе {0}'; games = 'Игры и развлечения в районе {0}';
  active = 'Активность в районе {0}'; movie = 'Кино в районе {0}'
}
$hooksEn = @{
  coffee = 'A coffee spot in {0}'; food = 'A place to eat in {0}';
  antikafe = 'An anti-cafe in {0}'; culture = 'A cultural spot in {0}';
  walk = 'A walk in {0}'; games = 'Games and fun in {0}';
  active = 'Something active in {0}'; movie = 'Cinema in {0}'
}

$all = @()
$seen = @{}
$counts = @{}

foreach ($batch in $queries) {
  $raw = Get-Overpass $batch.name $batch.q
  if (-not $raw) { continue }
  try {
    $doc = $raw | ConvertFrom-Json
  } catch {
    Write-Host ("  ! {0}: не разобрал JSON" -f $batch.name) -ForegroundColor DarkYellow
    continue
  }
  foreach ($el in $doc.elements) {
    if ($null -eq $el.tags) { continue }
    $name = Tag $el.tags 'name:ru'
    if (-not $name) { $name = Tag $el.tags 'name' }
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    if ($name.Length -lt 3) { continue }
    $nameKey = $name.ToLowerInvariant() -replace '[^\wа-яё]+', ' '
    $nameKey = $nameKey.Trim()
    if ($seedNames.ContainsKey($nameKey)) { continue }

    $street = Tag $el.tags 'addr:street'
    $house = Tag $el.tags 'addr:housenumber'
    $address = if ($street -and $house) { "$street, $house" } elseif ($street) { $street } else { 'Москва' }
    $district = Tag $el.tags 'addr:district'
    if (-not $district) { $district = Tag $el.tags 'addr:suburb' }
    if (-not $district) { $district = Tag $el.tags 'addr:city_district' }
    if (-not $district) { $district = 'Москва' }

    $category = Get-Category $batch $el.tags $name
    $key = $nameKey + '|' + ($address.ToLowerInvariant() -replace '\s+', ' ')
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true

    $description = Tag $el.tags 'description:ru'
    if (-not $description) { $description = Tag $el.tags 'description' }
    $hours = Tag $el.tags 'opening_hours'
    if (-not $hours) { $hours = 'Уточните на месте' }
    $website = Tag $el.tags 'website'
    if (-not $website) { $website = Tag $el.tags 'contact:website' }
    if (-not $website) { $website = Tag $el.tags 'url' }
    $fee = Tag $el.tags 'fee'
    $charge = Tag $el.tags 'charge'
    $price = $null
    $approx = $false
    $priceNoteRu = 'Цена не указана в открытом источнике — проверьте на сайте заведения.'
    $priceNoteEn = 'Price is not listed in the public source — check the venue website.'
    if ($fee -eq 'no') {
      $price = 0
      $priceNoteRu = 'Вход свободный по данным OpenStreetMap; платные услуги уточняйте.'
      $priceNoteEn = 'Free entry according to OpenStreetMap; check paid extras.'
    } elseif ($charge -match '^\s*(\d{2,5})\s*(?:₽|руб|rub)?\s*$') {
      $price = [int]$Matches[1]
      $priceNoteRu = 'Цена указана в OpenStreetMap; проверьте перед выходом.'
      $priceNoteEn = 'Price from OpenStreetMap; check before you go.'
    }
    $hookRu = [string]::Format($hooksRu[$category], $district)
    $hookEn = [string]::Format($hooksEn[$category], $district)
    $aboutRu = if ($description) { "$description $name находится по адресу: $address. Цену нужно уточнить на месте или на сайте." } else { "$name — $($hooksRu[$category].ToLowerInvariant()). Адрес: $address. Это карточка из OpenStreetMap: цену и часы работы нужно уточнить перед выходом." }
    $aboutEn = if ($description) { "$description $name is at $address. Check the price on site or on location." } else { "$name is $($hooksEn[$category].ToLowerInvariant()). Address: $address. This card comes from OpenStreetMap: check the price and opening hours before you go." }

    $lat = $el.lat
    $lon = $el.lon
    if ($null -eq $lat -and $null -ne $el.center) { $lat = $el.center.lat; $lon = $el.center.lon }

    $all += [ordered]@{
      id = "osm-$($el.type)-$($el.id)"
      name = [ordered]@{ ru = $name; en = $name }
      category = $category
      emoji = switch ($category) { 'coffee' {'☕️'} 'food' {'🍲'} 'antikafe' {'🛋'} 'culture' {'🖼'} 'walk' {'🌳'} 'games' {'🎮'} 'active' {'🎳'} 'movie' {'🎬'} default {'✨'} }
      price = $price
      priceApprox = $approx
      priceFrom = $false
      priceUnit = $units[$category]
      priceNote = [ordered]@{
        ru = $priceNoteRu
        en = $priceNoteEn
      }
      website = $website
      fee = $fee
      charge = $charge
      rating = $null
      district = [ordered]@{ ru = $district; en = $district }
      metro = [ordered]@{ ru = 'Уточните на карте'; en = 'Check the map' }
      address = [ordered]@{ ru = $address; en = $address }
      hours = [ordered]@{ ru = $hours; en = $hours }
      company = $companies[$category]
      indoor = ($category -ne 'walk')
      badge = $null
      hook = [ordered]@{ ru = $hookRu; en = $hookEn }
      about = [ordered]@{ ru = $aboutRu; en = $aboutEn }
      whatYouGet = [ordered]@{ ru = $getRu[$category]; en = $getEn[$category] }
      tip = [ordered]@{ ru = 'Перед выходом проверьте стоимость и часы работы на сайте заведения.'; en = 'Check the cost and opening hours on the venue website before you go.' }
      deal = $null
      tags = [ordered]@{ ru = $tagRu[$category]; en = $tagEn[$category] }
      mapQuery = "$name, Москва"
      lat = $lat
      lon = $lon
      source = [ordered]@{ id = 'osm'; name = [ordered]@{ ru = 'OpenStreetMap'; en = 'OpenStreetMap' } }
      priceConfidence = if ($null -eq $price) { 'unknown' } else { 'osm' }
      priceSource = if ($null -eq $price) { '' } else { 'https://www.openstreetmap.org/' }
    }
    if (-not $counts.ContainsKey($category)) { $counts[$category] = 0 }
    $counts[$category] += 1
  }
}

# Квоты по категориям, чтобы не отдать всё одним кафе.
$quotas = @{ coffee = 140; food = 260; antikafe = 40; games = 70; active = 70 }
$selected = @()
foreach ($cat in $quotas.Keys) {
  $pool = @($all | Where-Object { $_.category -eq $cat })
  if ($pool.Count -gt $quotas[$cat]) { $pool = @($pool | Get-Random -Count $quotas[$cat]) }
  $selected += $pool
}

$selected = @($selected | Sort-Object { $_.category }, { $_.name.ru })
$result = [ordered]@{
  updatedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
  attribution = '© OpenStreetMap contributors, ODbL 1.0'
  total = $selected.Count
  byCategory = $counts
  places = $selected
}
Write-Json $result $OutPath

Write-Host ''
Write-Host ("Готово: {0} мест из OSM. Файл: data/osm-places.json" -f $selected.Count) -ForegroundColor Green
$selected | Group-Object category | Sort-Object Name | ForEach-Object { "  {0,-10} {1}" -f $_.Name, $_.Count }
