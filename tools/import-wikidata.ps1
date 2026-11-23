# СТОИТ — импорт культурных мест и прогулок из Wikidata.
# Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File tools\import-wikidata.ps1

param([switch]$Force)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}

$Root = Split-Path -Parent $PSScriptRoot
$DataDir = Join-Path $Root 'data'
$CacheDir = Join-Path $DataDir 'cache'
$OutPath = Join-Path $DataDir 'wiki-places.json'
$SeedPath = Join-Path $DataDir 'seed.json'
$UA = 'STOIT/1.0 (Moscow city guide; open data import)'
$Now = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(3))

New-Item -ItemType Directory -Force -Path $DataDir, $CacheDir | Out-Null

function Read-Json([string]$Path) {
  if (-not (Test-Path $Path)) { return $null }
  return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json)
}
function Write-Json($Object, [string]$Path) {
  [IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
}
function Get-Wikidata([string]$Name, [string]$Query) {
  $cache = Join-Path $CacheDir ("wd-" + $Name + ".json")
  if (-not $Force -and (Test-Path $cache)) {
    $age = $Now - (Get-Item $cache).LastWriteTime
    if ($age.TotalDays -lt 7) { return [IO.File]::ReadAllText($cache, [Text.Encoding]::UTF8) }
  }
  $url = 'https://query.wikidata.org/sparql?format=json&query=' + [Uri]::EscapeDataString($Query)
  for ($try = 1; $try -le 3; $try++) {
    $tmp = [IO.Path]::GetTempFileName()
    try {
      $code = & curl.exe -sS -L --max-time 60 -A $UA -H 'Accept: application/sparql-results+json' -o $tmp -w '%{http_code}' $url 2>$null
      $len = 0
      if (Test-Path $tmp) { $len = (Get-Item $tmp).Length }
      if ("$code" -eq '200' -and $len -gt 100) {
        $text = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8)
        [IO.File]::WriteAllText($cache, $text, (New-Object Text.UTF8Encoding($false)))
        Write-Host ("  {0,-14} ok" -f $Name) -ForegroundColor Green
        return $text
      }
      Write-Host ("  {0,-14} HTTP {1}" -f $Name, $code) -ForegroundColor DarkYellow
    } catch {
      Write-Host ("  {0,-14} соединение сброшено" -f $Name) -ForegroundColor DarkYellow
    } finally {
      Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds (3 * $try)
  }
  if (Test-Path $cache) { return [IO.File]::ReadAllText($cache, [Text.Encoding]::UTF8) }
  return $null
}

$classes = @(
  @{ q = 'Q33506';  cat = 'culture'; limit = 180; name = 'museums' },
  @{ q = 'Q22698';  cat = 'walk';    limit = 150; name = 'parks' },
  @{ q = 'Q2431196'; cat = 'culture'; limit = 120; name = 'theatres' },
  @{ q = 'Q1007870'; cat = 'culture'; limit = 100; name = 'galleries' },
  @{ q = 'Q41253';  cat = 'movie';   limit = 70;  name = 'cinema' },
  @{ q = 'Q43501';  cat = 'walk';    limit = 30;  name = 'zoo' },
  @{ q = 'Q19707';  cat = 'walk';    limit = 30;  name = 'aquariums' },
  @{ q = 'Q194195'; cat = 'active';  limit = 40;  name = 'amusement' },
  @{ q = 'Q167346'; cat = 'walk';    limit = 40;  name = 'gardens' },
  @{ q = 'Q879050'; cat = 'culture'; limit = 80;  name = 'manors' },
  @{ q = 'Q483110'; cat = 'active';  limit = 50;  name = 'stadiums' },
  @{ q = 'Q192151'; cat = 'active';  limit = 50;  name = 'ice-rinks' },
  @{ q = 'Q1076486'; cat = 'active'; limit = 40; name = 'pools' },
  @{ q = 'Q14664';  cat = 'games';   limit = 40;  name = 'bowling' },
  @{ q = 'Q1161568'; cat = 'games';  limit = 40;  name = 'quests' }
)

$seedNames = @{}
$seed = Read-Json $SeedPath
if ($null -ne $seed) {
  foreach ($p in $seed.places) {
    $n = ([string]$p.name.ru).ToLowerInvariant() -replace '[^\wа-яё]+', ' '
    $seedNames[$n.Trim()] = $true
  }
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
  coffee = @{ ru = '1–3 человека'; en = '1–3 people' }; food = @{ ru = '2–4 человека'; en = '2–4 people' };
  culture = @{ ru = '1–4 человека'; en = '1–4 people' }; walk = @{ ru = 'Любая компания'; en = 'Any group' };
  games = @{ ru = '2–6 человек'; en = '2–6 people' }; active = @{ ru = '2–6 человек'; en = '2–6 people' };
  movie = @{ ru = '1–4 человека'; en = '1–4 people' }
}
$tagRu = @{
  coffee = @('кофе', 'свидание'); food = @('поесть', 'с друзьями'); antikafe = @('настолки', 'с друзьями', 'дождь');
  culture = @('культура', 'свидание', 'дождь'); walk = @('гулять', 'на улице', 'бесплатно');
  games = @('с друзьями', 'на компанию', 'дождь'); active = @('активность', 'с друзьями'); movie = @('кино', 'дождь', 'свидание')
}
$tagEn = @{
  coffee = @('coffee', 'date'); food = @('eat', 'with friends'); antikafe = @('board games', 'with friends', 'rainy day');
  culture = @('culture', 'date', 'rainy day'); walk = @('walk', 'outdoors', 'free');
  games = @('with friends', 'for a group', 'rainy day'); active = @('active', 'with friends'); movie = @('cinema', 'rainy day', 'date')
}
$getRu = @{
  culture = @('Билет или свободный вход', 'Постоянная экспозиция', 'Фото и впечатления');
  walk = @('Свободный вход', 'Маршрут на 1–3 часа', 'Хорошо в любую погоду');
  active = @('Час активности', 'Снаряжение и инструктаж', 'Хорошо для компании');
  games = @('Час игры', 'Компания и азарт', 'Снэки рядом');
  movie = @('Билет в кино', 'Большой экран', 'Попкорн рядом')
}
$getEn = @{
  culture = @('A ticket or free entry', 'Permanent exhibition', 'Photos and impressions');
  walk = @('Free entry', 'A 1–3 hour route', 'Good in most weather');
  active = @('An hour of activity', 'Equipment and briefing', 'Great for a group');
  games = @('An hour of play', 'Company and competition', 'Snacks nearby');
  movie = @('A cinema ticket', 'Big screen', 'Popcorn nearby')
}
$hooksRu = @{ culture = 'Культурное место в Москве'; walk = 'Прогулка по Москве'; active = 'Активность в Москве'; games = 'Игры в Москве'; movie = 'Кино в Москве' }
$hooksEn = @{ culture = 'A cultural place in Moscow'; walk = 'A Moscow walk'; active = 'Something active in Moscow'; games = 'Games in Moscow'; movie = 'Cinema in Moscow' }
$whatRu = @{ culture = 'Музей, галерея или театр'; walk = 'Парк или прогулочное место'; active = 'Активность'; games = 'Игровое место'; movie = 'Кинотеатр'; shop = 'Книжный, виниловый или винтажный магазин' }
$whatEn = @{ culture = 'A museum, gallery or theatre'; walk = 'A park or walking spot'; active = 'An activity'; games = 'A games venue'; movie = 'A cinema'; shop = 'A book, vinyl or vintage shop' }

$all = @()
$seen = @{}
foreach ($class in $classes) {
  $query = @"
SELECT ?item ?itemLabel ?coord ?image ?logo ?site WHERE {
  ?item wdt:P31/wdt:P279* wd:$($class.q) .
  ?item wdt:P131 wd:Q649 .
  ?item wdt:P625 ?coord .
  OPTIONAL { ?item wdt:P18 ?image . }
  OPTIONAL { ?item wdt:P154 ?logo . }
  OPTIONAL { ?item wdt:P856 ?site . }
  OPTIONAL { ?item wdt:P576 ?dissolved . }
  FILTER(!BOUND(?dissolved))
  SERVICE wikibase:label { bd:serviceParam wikibase:language "ru,en". }
} LIMIT $($class.limit)
"@
  $raw = Get-Wikidata $class.name $query
  if (-not $raw) { continue }
  try { $doc = $raw | ConvertFrom-Json } catch { continue }
  foreach ($row in $doc.results.bindings) {
    $label = [string]$row.itemLabel.value
    if ([string]::IsNullOrWhiteSpace($label)) { continue }
    if ($label -match '^Q\d+$') { continue }
    $qid = ([string]$row.item.value -split '/')[-1]
    if ($seen.ContainsKey($qid)) { continue }
    $seen[$qid] = $true
    $nameKey = $label.ToLowerInvariant() -replace '[^\wа-яё]+', ' '
    if ($seedNames.ContainsKey($nameKey.Trim())) { continue }
    $category = $class.cat
    $coord = [string]$row.coord.value
    $lat = $null; $lon = $null
    $m = [regex]::Match($coord, 'Point\(([-\d.]+)\s+([-\d.]+)\)')
    if ($m.Success) { $lon = [double]$m.Groups[1].Value; $lat = [double]$m.Groups[2].Value }
    $image = ''
    if ($null -ne $row.image) { $image = ([string]$row.image.value) -replace '^http://', 'https://' }
    $logo = ''
    if ($null -ne $row.logo) { $logo = ([string]$row.logo.value) -replace '^http://', 'https://' }
    $website = ''
    if ($null -ne $row.site) { $website = ([string]$row.site.value) -replace '^http://', 'https://' }
    $price = $null
    $approx = $false
    $district = 'Москва'
    $all += [ordered]@{
      id = "wd-$qid"
      name = [ordered]@{ ru = $label; en = $label }
      category = $category
      emoji = switch ($category) { 'culture' {'🖼'} 'walk' {'🌳'} 'active' {'🎳'} 'games' {'🎮'} 'movie' {'🎬'} default {'✨'} }
      price = $price
      priceApprox = $approx
      priceFrom = $false
      priceUnit = $units[$category]
      priceNote = [ordered]@{
        ru = 'Цена не указана в открытом источнике — проверьте на сайте заведения.'
        en = 'Price is not listed in the public source — check the venue website.'
      }
      rating = $null
      district = [ordered]@{ ru = $district; en = 'Moscow' }
      metro = [ordered]@{ ru = 'Уточните на карте'; en = 'Check the map' }
      address = [ordered]@{ ru = 'Москва'; en = 'Moscow' }
      hours = [ordered]@{ ru = 'Уточните на месте'; en = 'Check on site' }
      company = $companies[$category]
      indoor = ($category -ne 'walk')
      badge = $null
      hook = [ordered]@{ ru = $hooksRu[$category]; en = $hooksEn[$category] }
      what = [ordered]@{ ru = $whatRu[$category]; en = $whatEn[$category] }
      about = [ordered]@{
        ru = "$label — $($whatRu[$category].ToLowerInvariant()) в Москве. Карточка собрана из Wikidata и OpenStreetMap: адрес, цену и часы работы лучше уточнить перед выходом."
        en = "$label is $($whatEn[$category].ToLowerInvariant()) in Moscow. This card comes from Wikidata and OpenStreetMap: check the address, price and opening hours before you go."
      }
      hiddenGem = ($category -eq 'games')
      whatYouGet = [ordered]@{ ru = $getRu[$category]; en = $getEn[$category] }
      tip = [ordered]@{ ru = 'Проверьте цену и часы работы перед выходом.'; en = 'Check the price and opening hours before you go.' }
      deal = $null
      tags = [ordered]@{ ru = $tagRu[$category]; en = $tagEn[$category] }
      mapQuery = "$label, Москва"
      lat = $lat
      lon = $lon
      image = $image
      logo = $logo
      website = $website
      source = [ordered]@{ id = 'wikidata'; name = [ordered]@{ ru = 'Wikidata'; en = 'Wikidata' } }
      priceConfidence = 'unknown'
    }
  }
}

$quotas = @{ culture = 220; walk = 160; active = 100; games = 40; movie = 60 }
$selected = @()
foreach ($cat in $quotas.Keys) {
  $pool = @($all | Where-Object { $_.category -eq $cat })
  if ($pool.Count -gt $quotas[$cat]) { $pool = @($pool | Get-Random -Count $quotas[$cat]) }
  $selected += $pool
}
$selected = @($selected | Sort-Object { $_.category }, { $_.name.ru })
$result = [ordered]@{
  updatedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
  attribution = 'Wikidata, CC0; © OpenStreetMap contributors, ODbL 1.0'
  total = $selected.Count
  places = $selected
}
Write-Json $result $OutPath
Write-Host ''
Write-Host ("Готово: {0} мест из Wikidata. Файл: data/wiki-places.json" -f $selected.Count) -ForegroundColor Green
$selected | Group-Object category | Sort-Object Name | ForEach-Object { "  {0,-10} {1}" -f $_.Name, $_.Count }
