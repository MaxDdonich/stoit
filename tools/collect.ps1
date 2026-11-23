# СТОИТ — ежедневный сборщик данных.
# Запуск: powershell -ExecutionPolicy Bypass -File tools\collect.ps1
# Флаги: -NoTranslate (быстро, без машинного перевода), -MaxSignals 36

param(
  [switch]$NoTranslate,
  [int]$MaxSignals = 80,
  [switch]$Force,
  [switch]$NoPriceSearch,
  [int]$MaxPriceChecks = 36,
  [int]$MaxSignalPriceChecks = 36,
  [switch]$NoMediaSearch,
  [int]$MaxMediaChecks = 24
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}

$Root        = Split-Path -Parent $PSScriptRoot
$DataDir     = Join-Path $Root 'data'
$CacheDir    = Join-Path $DataDir 'cache'
$ConfigPath  = Join-Path $Root 'config\sources.json'
$SeedPath    = Join-Path $DataDir 'seed.json'
$PricesPath  = Join-Path $DataDir 'prices.json'
$PriceCachePath = Join-Path $DataDir 'price-cache.json'
$PriceReviewPath = Join-Path $DataDir 'price-review.json'
$MediaPath = Join-Path $DataDir 'media.json'
$MediaCachePath = Join-Path $DataDir 'media-cache.json'
$FeedPath    = Join-Path $DataDir 'feed.json'
$TrCachePath = Join-Path $DataDir 'translation-cache.json'
$TrBudgetPath = Join-Path $DataDir 'translation-budget.json'

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'
$MoscowOffset = [TimeSpan]::FromHours(3)
$Now = [DateTimeOffset]::UtcNow.ToOffset($MoscowOffset)

New-Item -ItemType Directory -Force -Path $DataDir, $CacheDir | Out-Null

function Write-Utf8([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}
function Read-Json([string]$Path) {
  if (-not (Test-Path $Path)) { return $null }
  return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json)
}
function Save-Json($Object, [string]$Path) {
  Write-Utf8 $Path ($Object | ConvertTo-Json -Depth 40)
}
function Get-RemoteText([string]$Url) {
  $tmp = [IO.Path]::GetTempFileName()
  try {
    $code = & curl.exe -sS -L --max-time 20 -A $UA -H 'Accept-Language: ru,en;q=0.8' -o $tmp -w '%{http_code}' $Url 2>$null
    $len = 0
    if (Test-Path $tmp) { $len = (Get-Item $tmp).Length }
    if ("$code" -eq '200' -and $len -gt 200) {
      return [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8)
    }
  } catch {
    return $null
  } finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
  return $null
}
function Clean-Text([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
  $s = [Net.WebUtility]::HtmlDecode($Value)
  $s = [regex]::Replace($s, '<script[\s\S]*?</script>', ' ', 'IgnoreCase')
  $s = [regex]::Replace($s, '<style[\s\S]*?</style>', ' ', 'IgnoreCase')
  $s = [regex]::Replace($s, '<br\s*/?>', ' ', 'IgnoreCase')
  $s = [regex]::Replace($s, '</(p|div|li)>', ' ', 'IgnoreCase')
  $s = [regex]::Replace($s, '<[^>]+>', ' ')
  $s = [Net.WebUtility]::HtmlDecode($s)
  $s = $s -replace '[\u00A0\u200B\uFEFF]', ' '
  $s = $s -replace '\s+', ' '
  return $s.Trim()
}
function Clean-SocialText([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
  $s = [Net.WebUtility]::HtmlDecode($Value)
  $s = [regex]::Replace($s, 'https?://\S+', ' ', 'IgnoreCase')
  $s = [regex]::Replace($s, 'www\.\S+', ' ', 'IgnoreCase')
  $s = [regex]::Replace($s, '\S+@\S+\.\S+', ' ', 'IgnoreCase')
  $s = [regex]::Replace($s, '[@#][A-Za-z0-9_.]+', ' ')
  $s = [regex]::Replace($s, '\+?\d[\d\s\-()]{7,}\d', ' ')
  $s = [regex]::Replace($s, '(?i)(где|как)\s+нас\s+найти[^.!?\n]*', ' ')
  $s = [regex]::Replace($s, '(?i)(наш\s+)?адрес[^.!?\n]*', ' ')
  $s = [regex]::Replace($s, '(?i)(контакты|бронь|бронирование|доставка|телеграм|whatsapp|инстаграм|заходите|ждем вас|приходите)[^.!?\n]*', ' ')
  $s = [regex]::Replace($s, '[\u00A0\u200B\uFEFF]', ' ')
  $s = $s -replace '\s+', ' '
  return $s.Trim()
}
function Get-NodeText($Item, [string[]]$Names) {
  foreach ($n in $Names) {
    $node = $Item.SelectSingleNode("./*[local-name()='$n']")
    if ($null -ne $node -and -not [string]::IsNullOrWhiteSpace($node.InnerText)) {
      return $node.InnerText
    }
  }
  return ''
}
function Get-ItemLink($Item) {
  $node = $Item.SelectSingleNode("./*[local-name()='link']")
  if ($null -eq $node) { return '' }
  $href = $node.GetAttribute('href')
  if (-not [string]::IsNullOrWhiteSpace($href)) { return $href.Trim() }
  return $node.InnerText.Trim()
}
function Get-ItemImage($Item, [string]$DescHtml, [string]$Homepage) {
  foreach ($n in @('enclosure','thumbnail','content')) {
    $node = $Item.SelectSingleNode("./*[local-name()='$n']")
    if ($null -ne $node) {
      $u = $node.GetAttribute('url')
      if (-not [string]::IsNullOrWhiteSpace($u)) {
        if ($u -match '^//') { return 'https:' + $u }
        if ($u -match '^https?://') { return $u }
      }
    }
  }
  $m = [regex]::Match($DescHtml, '<img[^>]+src=["'']([^"'']+)["'']', 'IgnoreCase')
  if ($m.Success) {
    $u = [Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
    if ($u -match '^//') { return 'https:' + $u }
    if ($u -match '^https?://') { return $u }
    if ($u.StartsWith('/')) {
      try { return ([Uri]::new([Uri]$Homepage, $u)).AbsoluteUri } catch { return '' }
    }
  }
  return ''
}
function Convert-Money([string]$Value) {
  $clean = $Value -replace '[^\d]', ''
  if (-not $clean) { return $null }
  return [int]$clean
}
function Get-Price([string]$Text) {
  $vals = @()
  foreach ($m in [regex]::Matches($Text, '(\d{1,3}(?:[ \u00A0]\d{3})+|\d{1,5})\s*[–—-]\s*(\d{1,3}(?:[ \u00A0]\d{3})+|\d{1,5})\s*(?:₽|руб)')) {
    $a = Convert-Money $m.Groups[1].Value
    $b = Convert-Money $m.Groups[2].Value
    if ($null -ne $a -and $a -ge 50 -and $a -le 6000) { $vals += $a }
    if ($null -ne $b -and $b -ge 50 -and $b -le 6000) { $vals += $b }
  }
  foreach ($m in [regex]::Matches($Text, '(?<![\d])(\d{1,3}(?:[ \u00A0]\d{3})+|\d{1,5})\s*(?:₽|руб(?:\.|лей|ля)?|р\.)')) {
    $v = Convert-Money $m.Groups[1].Value
    if ($null -ne $v -and $v -ge 50 -and $v -le 6000) { $vals += $v }
  }
  if ($vals.Count -gt 0) { return [int](($vals | Measure-Object -Minimum).Minimum) }
  if ($Text -match 'бесплатн|вход свободн|без оплаты|0\s*₽') { return 0 }
  return $null
}
function Get-PriceUnit([string]$Text) {
  if ($Text -match 'средний чек') { return [ordered]@{ ru = 'средний чек'; en = 'average bill' } }
  if ($Text -match 'обед|ланч') { return [ordered]@{ ru = 'за обед'; en = 'lunch' } }
  if ($Text -match 'завтрак') { return [ordered]@{ ru = 'за завтрак'; en = 'breakfast' } }
  if ($Text -match 'билет') { return [ordered]@{ ru = 'за билет'; en = 'per ticket' } }
  if ($Text -match 'дорожк') { return [ordered]@{ ru = 'за дорожку/час'; en = 'per lane/hour' } }
  if ($Text -match 'с человека|на человека|человека') { return [ordered]@{ ru = 'с человека'; en = 'per person' } }
  if ($Text -match 'час') { return [ordered]@{ ru = 'за час'; en = 'per hour' } }
  if ($Text -match 'вход|посещен') { return [ordered]@{ ru = 'за вход'; en = 'entry' } }
  if ($Text -match 'кофе|напиток') { return [ordered]@{ ru = 'за напиток'; en = 'per drink' } }
  if ($Text -match 'бесплатн|вход свободн') { return [ordered]@{ ru = 'вход'; en = 'entry' } }
  return [ordered]@{ ru = 'за визит'; en = 'per visit' }
}
function Get-Category([string]$Text) {
  if ($Text -match 'кофе|кофейн|капучино|латте') { return 'coffee' }
  if ($Text -match 'кафе|ресторан|бар[ыа]?\b|еда|поесть|пицц|блин|завтрак|ужин|обед|десерт|фуд|кухн|пекарн|бургер|рамен|суши') { return 'food' }
  if ($Text -match 'выставк|музе|театр|спектак|концерт|кино|фильм|лекци|фестивал|галере|опер|балет') { return 'culture' }
  if ($Text -match 'квест|боулинг|батут|настол|антикафе|караоке|плейстейшн|playstation|игров|киберспорт') { return 'games' }
  if ($Text -match 'парк|прогул|экскурс|каток|набереж|сквер|усадьб|ботанич|маршрут') { return 'walk' }
  if ($Text -match 'спорт|йог|танц|залив|сап|велосипед|лыж') { return 'active' }
  return 'event'
}
function Get-NameCore([string]$Name) {
  $s = ([string]$Name).ToLowerInvariant() -replace 'ё', 'е'
  $s = $s -replace '[^\wа-я]+', ' '
  $generic = '^(музей|парк|театр|галерея|центр|искусства|современного|культуры|дом|дворец|усадьба|заповедник|выставочный|зал|детский|научный|исторический|городской|государственный|московский|имени|им|the|museum|park|gallery|art|center|moscow|москва|москвы|москве|москву)$'
  $words = $s -split '\s+' | Where-Object { $_ -and $_ -notmatch $generic }
  return ($words -join ' ').Trim()
}

function Normalize-Key([string]$Text) {
  $s = $Text.ToLowerInvariant() -replace '[^\wа-яё]+', ' '
  $s = $s -replace '\s+', ' '
  if ($s.Length -gt 45) { $s = $s.Substring(0, 45) }
  return $s.Trim()
}

function Set-PlaceField($Place, [string]$Name, $Value) {
  if ($null -ne $Place.PSObject.Properties[$Name]) { $Place.$Name = $Value }
  else { $Place | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
}

function Normalize-MatchName([string]$Text) {
  if (-not $Text) { return '' }
  $s = $Text.ToLowerInvariant() -replace 'ё', 'е'
  $s = $s -replace '[^\wа-я]+', ' '
  return ($s -replace '\s+', ' ').Trim()
}

function Get-PriceOverride($Place) {
  $id = [string]$Place.id
  if ($id -and $script:PriceById.ContainsKey($id)) { return $script:PriceById[$id] }
  foreach ($n in @([string]$Place.name.ru, [string]$Place.name.en)) {
    $key = Normalize-MatchName $n
    if ($key -and $script:PriceByName.ContainsKey($key)) { return $script:PriceByName[$key] }
  }
  return $null
}

function Test-PlaceQuality($Place) {
  $name = ([string]$Place.name.ru).ToLowerInvariant()
  $cat = [string]$Place.category
  if ($name -match 'трансвааль|румянцевск|антирелигиозн|музей в\. и\. ленина|голицынск|дом нащокина|институт русского реалистического искусства|кочерга|good republic|хорошая республика|вольчек') { return $false }
  if ($cat -eq 'culture' -and $name -match 'академ|институт|училище|университет|школ|лицей|гимнази|больниц|поликлиник|госпитал|библиотек|архив') { return $false }
  if ($cat -in @('walk','culture') -and $name -match 'церковь|храм|собор|монастыр|часовн|синагог|мечеть|кладбищ|крематор') { return $false }
  if ($cat -in @('walk','active') -and $name -match 'академ|институт|училище|университет|школ|лицей|гимнази|больниц|поликлиник|госпитал|библиотек|архив|тюрьм|прокуратур|полици|мвд|фсб|фсо|налогов|таможн') { return $false }
  if ($cat -eq 'active' -and $name -match 'военн|арми|флот|авиац|ркка|пограничн|оборон|стадион|арена|мегаспорт|спортивный комплекс|лдс|лск') { return $false }
  return $true
}

. (Join-Path $PSScriptRoot 'price-finder.ps1')
. (Join-Path $PSScriptRoot 'media-finder.ps1')

# ---------- перевод (MyMemory, без ключа, с кэшем и дневным лимитом) ----------
$TrCache = @{}
$cacheObj = Read-Json $TrCachePath
if ($null -ne $cacheObj) {
  foreach ($p in $cacheObj.PSObject.Properties) { $TrCache[$p.Name] = [string]$p.Value }
}
$budgetDate = (Get-Date).ToString('yyyy-MM-dd')
$budgetChars = 0
$budgetObj = Read-Json $TrBudgetPath
if ($null -ne $budgetObj -and "$($budgetObj.date)" -eq $budgetDate) { $budgetChars = [int]$budgetObj.chars }
$newTranslated = 0

function Translate-Text([string]$Text, [string]$From = 'ru', [string]$To = 'en') {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
  if ($NoTranslate) { return $null }
  if ($From -eq 'ru' -and $Text -notmatch '[А-Яа-яЁё]') { return $Text }
  if ($Text.Length -lt 2) { return $Text }
  if ($Text.Length -gt 450) { $Text = $Text.Substring(0, 450) }
  $key = "$From|$To|$Text"
  if ($TrCache.ContainsKey($key)) { return $TrCache[$key] }
  if (($budgetChars + $Text.Length) -gt 4000) { return $null }
  $q = [Uri]::EscapeDataString($Text)
  $url = "https://api.mymemory.translated.net/get?q=$q&langpair=$From|$To"
  $raw = Get-RemoteText $url
  if (-not $raw) { return $null }
  try {
    $obj = $raw | ConvertFrom-Json
    $t = [string]$obj.responseData.translatedText
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    if ($t -match 'MYMEMORY WARNING|QUERY LENGTH LIMIT|PLEASE SELECT TWO') { return $null }
    $t = Clean-Text $t
    $TrCache[$key] = $t
    $script:budgetChars += $Text.Length
    $script:newTranslated += 1
    Start-Sleep -Milliseconds 220
    return $t
  } catch {
    return $null
  }
}

# ---------- сбор источников ----------
$config = Read-Json $ConfigPath
$seed = Read-Json $SeedPath
if ($null -eq $seed) { throw 'Не найден data/seed.json' }

$strong = 'кафе|кофейн|ресторан|бистро|бар[ыа]?\b|выставк|музе[йя]|театр|спектак|концерт|парк|прогул|экскурс|квест|боулинг|каток|фестивал|маркет|ярмарк|лекци|антикафе|настол|игротек|смотров|усадьб|галере|кинотеатр|фуд-холл|фудхолл|пекарн|кондитерск|развлечен|аттракцион|колесо обозрен|зоопарк|планетарий|океанариум|батут|картинг|караоке|куда сходить|где поесть|где выпить|храм|церков|собор|монастыр|архитектур|памятник|мюзикл|оперетт|дом культуры|культурн[а-я]* центр|особняк|достопримечательн|свидан|знакомств|экспозиц|вернисаж|биеннале|лекторий|квиз|стендап|вечеринк|дискотек|выходн|арт-пространств|артплей|винзавод|прокат|завтрак|обед|ужин|еда|поесть|баня|спа|занятия|\bспорт|стретчинг|самбо|дзюдо|плаван|мастер-класс|\bспа\b|спа-'
$negative = 'погиб|умер|авари|пожар|уголов|суд |дтп|мошен|полици|войн|санкц|курс доллара|гороскоп|промокод|розыгрыш|конкурс|подпишись|переходи по ссылке|реклама|жесток|убий|ограб|болезн|вирус|штраф|жалоб|протест|выборы|соболезн|произош|следствен|росгвард|мчс|эвакуир|перекрыт|ограничен движен|пробк|погод|температур|снегопад|гололед|врач|больниц|школ|егэ|огэ|инфляц|рост цен|подорож|нейросет|искусственн интеллект|учены|исследован|смартфон|iphone|apple|gta|сериал|трейлер|бокс-офис|рейтинг фильм|трансляц|смотреть онлайн|кхл|спартак|цска|футбол|хоккей|\bставк|казино|букмекер|прогноз на матч|результат матча|турнирная таблица|госдум|кремл|политик|казани|казань|казанцев|петербург|сочи|екатеринбург|новосибирск|краснодар|крым|беларус|в сша|в америке|в европе|в китае|в германии|во франции|в италии|в израиле|в украине|сербск|альметьев|татарстан|леопард|бикини|овечкин|wildberries|собянин|мэр |главное за день|вице-премьер|премьер-министр|застрелили|отменяет|викторин|активн[а-я]* гражданин|патриотическ|капсульн|коллекц|показ мод|неделя моды|книг|шеф-повар|почему вы должны|партнерств|nike|формула-1|baza|лихорадк|диета|соцсет|опубликовал|жена |бикини|госдум|депутат|сенатор|министр|нью-йорк|нью йорк|сша|лобстер|сайрус|замуж|звезды на открытии|светск|starhit|котики|щенки|пристройство|закроется|закрытие|сорван|эвакуац|pinned|channel created|канал создан|форум|карьерн|распродаж|дарим|где нас найти|как нас найти|наш адрес|ждем вас|заходите к нам|малайз|сингапур|дубай|лондон|берлин|париж|токио|пекин|шанхай|стамбул|анталья|аукцион|благотворит|преми|итоги года|беспилотн|щелков|kuda-spb|\bspb\b|\bспб\b|липецк|сябитова|кто платит|сваха|дорогие подписчики|подписчики|коты-|паркур|единой россии|наградили|карели|сколько стоит первое'

$allSignals = @()
$sourceOut = @()
$seenKeys = @{}
$seenUrls = @{}

foreach ($src in $config.sources) {
  $items = @()
  $status = 'error'
  $usedCache = $false
  $raw = $null
  $cacheFile = Join-Path $CacheDir ($src.id + '.xml')

  # Повторный запуск в течение 6 часов не дёргает источники заново:
  # это спасает от медленных RSS-мостов и лимитов.
  if (-not $Force -and (Test-Path $cacheFile)) {
    $age = $Now - (Get-Item $cacheFile).LastWriteTime
    if ($age.TotalHours -lt 6) {
      $raw = [IO.File]::ReadAllText($cacheFile, [Text.Encoding]::UTF8)
      $status = 'cached'
      $usedCache = $true
    }
  }

  if (-not $raw) {
    foreach ($feed in $src.feeds) {
      $raw = Get-RemoteText $feed
      if ($raw) { break }
    }
  }
  if (-not $raw -and (Test-Path $cacheFile)) {
    $age = $Now - (Get-Item $cacheFile).LastWriteTime
    if ($age.TotalDays -lt 8) {
      $raw = [IO.File]::ReadAllText($cacheFile, [Text.Encoding]::UTF8)
      $status = 'cached'
      $usedCache = $true
    }
  }

  if ($raw) {
    try {
      $doc = New-Object System.Xml.XmlDocument
      $doc.LoadXml($raw)
      $nodes = $doc.SelectNodes('//*[local-name()="item" or local-name()="entry"]')
      foreach ($node in $nodes) {
        $titleRaw = Get-NodeText $node @('title')
        $descRaw  = Get-NodeText $node @('encoded','description','summary','content')
        $link     = Get-ItemLink $node
        $dateRaw  = Get-NodeText $node @('pubDate','published','updated','date')
        $title    = Clean-Text $titleRaw
        $title    = [regex]::Replace($title, '^[^\p{L}\p{N}]+', '').Trim()
        $title    = [regex]::Replace($title, '^\[(?:Photo|GIF|Video|Animated Sticker)\]\s*', '', 'IgnoreCase')
        $title    = [regex]::Replace($title, '^Photo\]\s*', '', 'IgnoreCase')
        $summary  = Clean-Text $descRaw
        $postLinks = @(Get-TextUrls ($descRaw + ' ' + $titleRaw) | Select-Object -First 8)
        $publisher = ''
        if ($src.stripSuffix) {
          $pm = [regex]::Match($title, '\s+-\s+([^-]{2,60})$')
          if ($pm.Success) {
            $publisher = $pm.Groups[1].Value.Trim()
            $title = $title.Substring(0, $pm.Index).Trim()
          }
        }
        if ($src.kind -eq 'social') {
          $clean = Clean-SocialText $summary
          if ($clean.Length -lt 18) { $clean = Clean-SocialText $title }
          if ($clean.Length -lt 18) { continue }
          $sentences = $clean -split '(?<=[.!?])\s+'
          $topic = $sentences | Where-Object { $_.Length -ge 18 -and $_ -match $strong } | Select-Object -First 1
          if (-not $topic) { $topic = $clean }
          $title = [regex]::Replace($topic.Trim(), '^[^\p{L}\p{N}]+', '').Trim()
          $title = $title -replace '\s+Instagram\s*$', ''
          $title = $title.TrimEnd(':', ' ', '-', '—')
          $summary = $clean
        }
        if ($title.Length -gt 140) { $title = $title.Substring(0, 137).TrimEnd() + '…' }
        if ($summary.Length -gt 280) { $summary = $summary.Substring(0, 277).TrimEnd() + '…' }
        $combined = ("$title $summary").ToLowerInvariant()
        $titleLower = $title.ToLowerInvariant()
        if ($title.Length -lt 12) { continue }
        if ($combined -match $negative) { continue }
        if ($src.moscowOnly -and $combined -notmatch 'москв|мск|столиц|арбат|замосквореч|хамовник|пресн|патриарш|сыромятник|кузьминк|коломенск|царицын|сокольник|измайлов|кусков|останкин|воробьев|зарядье|вднх|лубянк|китай-город|бульвар|переулок|набережн|проспект|улиц|метро|район') { continue }

        $key = Normalize-Key $title
        if ($seenKeys.ContainsKey($key)) { continue }
        if ($link -and $seenUrls.ContainsKey($link)) { continue }

        $img = Get-ItemImage $node $descRaw $src.homepage
        if ($img -and $img -notmatch '^https?://') { $img = '' }
        if ($img -match 'logo|placeholder|1x1|pixel|spacer|favicon|avatar') { $img = '' }
        $price = Get-Price $combined
        if ($titleLower -notmatch $strong) { continue }
        $unit = Get-PriceUnit $combined
        if ($null -ne $price -and $price -eq 0) { $unit = [ordered]@{ ru = 'вход'; en = 'entry' } }
        $category = Get-Category $combined

        $pub = $Now
        if ($dateRaw) {
          try { $pub = [DateTimeOffset]::Parse($dateRaw, [Globalization.CultureInfo]::InvariantCulture) } catch { $pub = $Now }
        }
        if ($pub -gt $Now.AddDays(1)) { $pub = $Now }
        $ageDays = ($Now - $pub).TotalDays
        if ($ageDays -gt 21) { continue }

        $score = 3
        if ($null -ne $price) { $score += 2 }
        if ($img) { $score += 1 }
        if ($ageDays -le 2) { $score += 2 } elseif ($ageDays -le 7) { $score += 1 }
        if ($combined -match 'куда сходить|на выходн|бесплатн|вход свободн') { $score += 1 }
        if ($combined -match 'новост|сообщи|рассказа|стало известно|предупред') { $score -= 1 }
        if ($src.kind -eq 'community') { $score += 4 }
        elseif ($src.kind -eq 'social') { $score += 3 }
        elseif ($src.kind -eq 'telegram') { $score += 2 }
        elseif ($src.kind -eq 'media') { $score += 1 }

        $slug = ($link -replace '^https?://', '') -replace '[^\w]+', '-'
        $id = "$($src.id)-$slug"
        if ($id.Length -gt 120) { $id = $id.Substring(0, 120) }

        $items += [ordered]@{
          id = $id
          title = [ordered]@{ ru = $title; en = '' }
          summary = [ordered]@{ ru = $summary; en = '' }
          price = $price
          priceUnit = $unit
          image = $img
          url = $link
          sourceId = $src.id
          sourceName = $src.name
          sourceKind = $src.kind
          links = $postLinks
          publisher = $publisher
          publishedAt = $pub.ToString('yyyy-MM-ddTHH:mm:sszzz')
          category = $category
          score = $score
          machineTranslated = $false
        }
        $seenKeys[$key] = $true
        if ($link) { $seenUrls[$link] = $true }
      }
      if (-not $usedCache) {
        $status = 'ok'
        Write-Utf8 (Join-Path $CacheDir ($src.id + '.xml')) $raw
      }
    } catch {
      Write-Host ("  ! {0}: ошибка разбора — {1}" -f $src.name.ru, $_.Exception.Message) -ForegroundColor DarkYellow
      $status = 'error'
    }
  }

  $sourceOut += [ordered]@{
    id = $src.id
    kind = $src.kind
    name = $src.name
    description = $src.description
    homepage = $src.homepage
    status = $status
    items = $items.Count
    lastSync = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
    note = if ($status -eq 'cached') {
      [ordered]@{ ru = 'Источник недоступен, показаны данные из кэша'; en = 'Source unavailable, showing cached data' }
    } elseif ($status -eq 'error') {
      [ordered]@{ ru = 'Нет ответа — попробуем в следующий раз'; en = 'No response — will retry next time' }
    } elseif ($items.Count -eq 0) {
      [ordered]@{ ru = 'Сегодня нет подходящих материалов'; en = 'Nothing suitable today' }
    } else { $null }
  }
  $allSignals += $items
  $mark = if ($status -eq 'ok') { 'ok' } elseif ($status -eq 'cached') { 'кэш' } else { 'ошибка' }
  Write-Host ("  {0,-34} {1,-7} +{2}" -f $src.name.ru, $mark, $items.Count)
  Start-Sleep -Milliseconds 250
}

# ---------- дедупликация и отбор ----------
$oldFeed = Read-Json $FeedPath
$oldSignals = @()
if ($null -ne $oldFeed -and [int]$oldFeed.schema -ge 9 -and $null -ne $oldFeed.signals) {
  $oldSignals = @($oldFeed.signals | Where-Object {
    try { ([DateTimeOffset]::Parse($_.publishedAt)).UtcDateTime -gt $Now.UtcDateTime.AddDays(-14) } catch { $false }
  })
}

$ranked = @($allSignals) + @($oldSignals)
$ranked = @($ranked | Sort-Object `
  @{ Expression = { if ($null -ne $_.score) { [double]$_.score } elseif ($null -ne $_.price) { 5 } else { 3 } }; Descending = $true }, `
  @{ Expression = { try { [DateTimeOffset]::Parse($_.publishedAt).UtcDateTime } catch { [DateTime]::MinValue } }; Descending = $true })

$merged = @()
$seen = @{}
foreach ($s in $ranked) {
  $k = Normalize-Key ([string]$s.title.ru)
  if ($seen.ContainsKey($k)) { continue }
  $seen[$k] = $true
  $merged += $s
}

$perSource = @{}
$selected = @()
foreach ($s in $merged) {
  $n = 0
  if ($perSource.ContainsKey($s.sourceId)) { $n = $perSource[$s.sourceId] }
  if ($n -ge 10) { continue }
  $perSource[$s.sourceId] = $n + 1
  $selected += $s
  if ($selected.Count -ge $MaxSignals) { break }
}

# ---------- перевод только отобранных ----------
$finalSignals = @()
$idx = 0
foreach ($s in $selected) {
  $titleRu = [string]$s.title.ru
  $titleEn = [string]$s.title.en
  if (-not $titleEn) {
    if ($idx -lt 50) { $titleEn = Translate-Text $titleRu 'ru' 'en' }
    if (-not $titleEn) { $titleEn = $titleRu }
  }
  $summaryRu = [string]$s.summary.ru
  $summaryEn = [string]$s.summary.en
  if (-not $summaryEn -and $summaryRu) {
    if ($idx -lt 8) {
      $summaryEn = Translate-Text $summaryRu 'ru' 'en'
      if (-not $summaryEn) { $summaryEn = $summaryRu }
    } else {
      $summaryEn = $summaryRu
    }
  }
  $unit = $s.priceUnit
  if ($null -eq $unit) { $unit = Get-PriceUnit ("$titleRu $summaryRu".ToLowerInvariant()) }
  $finalSignals += [ordered]@{
    id = $s.id
    title = [ordered]@{ ru = $titleRu; en = $titleEn }
    summary = [ordered]@{ ru = $summaryRu; en = $summaryEn }
    price = $s.price
    priceUnit = $unit
    image = $s.image
    url = $s.url
    sourceId = $s.sourceId
    sourceName = $s.sourceName
    sourceKind = $s.sourceKind
    links = @($s.links)
    publisher = [string]$s.publisher
    publishedAt = $s.publishedAt
    category = $s.category
    machineTranslated = ($titleEn -ne $titleRu -or $summaryEn -ne $summaryRu)
    priceOrigin = $null
    priceConfidence = $null
    priceSource = $null
    priceQuote = $null
    placeId = $null
  }
  $idx += 1
}

# ---------- каталог OpenStreetMap ----------
$osmPath = Join-Path $DataDir 'osm-places.json'
$osmMeta = Read-Json $osmPath
$osmPlaces = @()
$allPlaces = @($seed.places)
if ($null -ne $osmMeta -and $null -ne $osmMeta.places) {
  $knownCores = @()
  foreach ($p in $seed.places) {
    $k = Get-NameCore ([string]$p.name.ru)
    if ($k.Length -ge 3) { $knownCores += $k }
  }
  foreach ($p in $osmMeta.places) {
    if (-not (Test-PlaceQuality $p)) { continue }
    $c = Get-NameCore ([string]$p.name.ru)
    $dup = $false
    foreach ($k in $knownCores) {
      if ($k.Length -ge 4 -and $c.Length -ge 4 -and ($c -eq $k -or $c.Contains($k) -or $k.Contains($c))) { $dup = $true; break }
    }
    if ($dup) { continue }
    $p.price = $null
    $p.priceApprox = $false
    Set-PlaceField $p 'priceFrom' $false
    $p.priceConfidence = 'unknown'
    $p.priceNote = [ordered]@{ ru = 'Цена не указана в открытом источнике — проверьте на сайте заведения.'; en = 'Price is not listed in the public source — check the venue website.' }
    if ([string]$p.fee -eq 'no') {
      $p.price = 0
      $p.priceConfidence = 'osm'
      Set-PlaceField $p 'priceOrigin' 'osm'
      $p.priceNote = [ordered]@{ ru = 'Вход свободный по данным OpenStreetMap; платные услуги уточняйте.'; en = 'Free entry according to OpenStreetMap; check paid extras.' }
      Set-PlaceField $p 'priceSource' 'https://www.openstreetmap.org/'
      Set-PlaceField $p 'priceCheckedAt' ([string]$osmMeta.updatedAt)
    } elseif ([string]$p.charge -match '^\s*(\d{2,5})\s*(?:₽|руб|rub)?\s*$') {
      $p.price = [int]$Matches[1]
      $p.priceConfidence = 'osm'
      Set-PlaceField $p 'priceOrigin' 'osm'
      $p.priceNote = [ordered]@{ ru = 'Цена указана в OpenStreetMap; проверьте перед выходом.'; en = 'Price from OpenStreetMap; check before you go.' }
      Set-PlaceField $p 'priceSource' 'https://www.openstreetmap.org/'
      Set-PlaceField $p 'priceCheckedAt' ([string]$osmMeta.updatedAt)
    }
    $osmPlaces += $p
    $allPlaces += $p
    if ($c.Length -ge 3) { $knownCores += $c }
  }
  $sourceOut += [ordered]@{
    id = 'osm'
    kind = 'catalog'
    name = [ordered]@{ ru = 'OpenStreetMap · каталог'; en = 'OpenStreetMap · catalogue' }
    description = [ordered]@{ ru = 'Кафе, рестораны и развлечения с адресами'; en = 'Cafes, restaurants and fun with addresses' }
    homepage = 'https://www.openstreetmap.org/copyright'
    status = 'ok'
    items = $osmPlaces.Count
    lastSync = [string]$osmMeta.updatedAt
    note = [ordered]@{ ru = '© OpenStreetMap contributors, ODbL 1.0. Цены не выдумываются: если тарифа нет в OSM, указано «цена не указана».'; en = '© OpenStreetMap contributors, ODbL 1.0. Prices are not invented: if OSM has no tariff, the card says the price is not listed.' }
  }
}

$wikiPath = Join-Path $DataDir 'wiki-places.json'
$wikiMeta = Read-Json $wikiPath
$wikiPlaces = @()
if ($null -ne $wikiMeta -and $null -ne $wikiMeta.places) {
  $knownCores = @()
  foreach ($p in $allPlaces) {
    $k = Get-NameCore ([string]$p.name.ru)
    if ($k.Length -ge 3) { $knownCores += $k }
  }
  foreach ($p in $wikiMeta.places) {
    if (-not (Test-PlaceQuality $p)) { continue }
    $c = Get-NameCore ([string]$p.name.ru)
    $dup = $false
    foreach ($k in $knownCores) {
      if ($k.Length -ge 4 -and $c.Length -ge 4 -and ($c -eq $k -or $c.Contains($k) -or $k.Contains($c))) { $dup = $true; break }
    }
    if ($dup) { continue }
    $p.price = $null
    $p.priceApprox = $false
    Set-PlaceField $p 'priceFrom' $false
    $p.priceConfidence = 'unknown'
    $p.priceNote = [ordered]@{ ru = 'Цена не указана в открытом источнике — проверьте на сайте заведения.'; en = 'Price is not listed in the public source — check the venue website.' }
    $wikiPlaces += $p
    $allPlaces += $p
    if ($c.Length -ge 3) { $knownCores += $c }
  }
  $sourceOut += [ordered]@{
    id = 'wikidata'
    kind = 'catalog'
    name = [ordered]@{ ru = 'Wikidata · культура'; en = 'Wikidata · culture' }
    description = [ordered]@{ ru = 'Музеи, театры, парки, галереи и стадионы'; en = 'Museums, theatres, parks, galleries and stadiums' }
    homepage = 'https://www.wikidata.org/'
    status = 'ok'
    items = $wikiPlaces.Count
    lastSync = [string]$wikiMeta.updatedAt
    note = [ordered]@{ ru = 'Wikidata, CC0. Цены не выдумываются: если тарифа нет в источнике, указано «цена не указана».'; en = 'Wikidata, CC0. Prices are not invented: if the source has no tariff, the card says the price is not listed.' }
  }
}

# ---------- описание, качество и «небанальность» ----------
function New-TypeInfo([string]$Key, [string]$Ru, [string]$En) {
  return [pscustomobject]@{ Key = $Key; Ru = $Ru; En = $En }
}

function Get-PlaceTypeInfo($Place) {
  $name = ([string]$Place.name.ru).ToLowerInvariant()
  $amenity = ''; $tourism = ''; $leisure = ''; $sport = ''; $shop = ''; $historic = ''
  if ($Place.PSObject.Properties['osmTags'] -and $null -ne $Place.osmTags) {
    $amenity = [string]$Place.osmTags.amenity
    $tourism = [string]$Place.osmTags.tourism
    $leisure = [string]$Place.osmTags.leisure
    $sport = [string]$Place.osmTags.sport
    $shop = [string]$Place.osmTags.shop
    $historic = [string]$Place.osmTags.historic
  }
  if ($name -match 'flipfly|флипфлай') { return New-TypeInfo 'trampoline' 'Батутный центр' 'A trampoline park' }
  if ($name -match 'cook&run|cook and run|кулинар') { return New-TypeInfo 'cooking' 'Кулинарная студия' 'A cooking studio' }
  if ($name -match 'вейк|wake') { return New-TypeInfo 'wakeboard' 'Вейк-парк' 'A wake park' }
  if ($name -match 'ice skating|skating rink') { return New-TypeInfo 'rink' 'Каток' 'An ice rink' }
  if ($name -match 'бассейн|плаван') { return New-TypeInfo 'pool' 'Бассейн' 'A swimming pool' }
  if ($name -match 'теннис') { return New-TypeInfo 'tennis' 'Теннисный центр' 'A tennis centre' }
  if ($name -match 'баскет|волейбол|футбол|хоккей|стадион|арена|спорткомплекс|спортивный комплекс|манеж|лужники|динамо|dynamo|цска|cska|спартаковец|буревестник|крылатское') { return New-TypeInfo 'sport' 'Спортивный комплекс' 'A sports complex' }
  if ($amenity -eq 'marketplace') { return New-TypeInfo 'market' 'Рынок' 'A market' }
  if ($amenity -eq 'cinema') { return New-TypeInfo 'cinema' 'Кинотеатр' 'A cinema' }
  if ($amenity -eq 'theatre') { return New-TypeInfo 'theatre' 'Театр' 'A theatre' }
  if ($amenity -eq 'arts_centre') { return New-TypeInfo 'arts' 'Культурный центр' 'An arts centre' }
  if ($amenity -eq 'karaoke_box') { return New-TypeInfo 'karaoke' 'Караоке' 'Karaoke' }
  if ($amenity -eq 'cafe') { if ($name -match 'кофей|coffee') { return New-TypeInfo 'coffee' 'Кофейня' 'A coffee shop' }; return New-TypeInfo 'cafe' 'Кафе' 'A cafe' }
  if ($amenity -in @('restaurant','food_court')) { return New-TypeInfo 'restaurant' 'Ресторан' 'A restaurant' }
  if ($amenity -in @('bar','pub')) { return New-TypeInfo 'bar' 'Бар' 'A bar' }
  if ($amenity -in @('fast_food','ice_cream')) { return New-TypeInfo 'fastfood' 'Фастфуд' 'Fast food' }
  if ($tourism -eq 'museum') { return New-TypeInfo 'museum' 'Музей' 'A museum' }
  if ($tourism -eq 'gallery') { return New-TypeInfo 'gallery' 'Галерея' 'A gallery' }
  if ($tourism -eq 'viewpoint') { return New-TypeInfo 'viewpoint' 'Смотровая площадка' 'A viewpoint' }
  if ($tourism -eq 'planetarium') { return New-TypeInfo 'planetarium' 'Планетарий' 'A planetarium' }
  if ($tourism -eq 'aquarium') { return New-TypeInfo 'aquarium' 'Океанариум' 'An aquarium' }
  if ($tourism -eq 'zoo') { return New-TypeInfo 'zoo' 'Зоопарк' 'A zoo' }
  if ($tourism -eq 'attraction') { return New-TypeInfo 'attraction' 'Достопримечательность' 'An attraction' }
  if ($leisure -eq 'bowling_alley') { return New-TypeInfo 'bowling' 'Боулинг' 'Bowling' }
  if ($leisure -eq 'trampoline_park') { return New-TypeInfo 'trampoline' 'Батутный центр' 'A trampoline park' }
  if ($leisure -eq 'escape_game') { return New-TypeInfo 'quest' 'Квест-рум' 'An escape room' }
  if ($leisure -eq 'ice_rink') { return New-TypeInfo 'rink' 'Каток' 'An ice rink' }
  if ($leisure -eq 'water_park') { return New-TypeInfo 'waterpark' 'Аквапарк' 'A water park' }
  if ($leisure -eq 'park') { return New-TypeInfo 'park' 'Парк' 'A park' }
  if ($leisure -eq 'garden') { return New-TypeInfo 'garden' 'Сад' 'A garden' }
  if ($leisure -eq 'climbing') { return New-TypeInfo 'climbing' 'Скалодром' 'A climbing wall' }
  if ($leisure -eq 'sports_centre') { return New-TypeInfo 'sport' 'Спортивный центр' 'A sports centre' }
  if ($sport -eq 'karting') { return New-TypeInfo 'karting' 'Картинг' 'Karting' }
  if ($sport -eq 'laser_tag') { return New-TypeInfo 'lasertag' 'Лазертаг' 'Laser tag' }
  if ($sport -eq 'swimming') { return New-TypeInfo 'pool' 'Бассейн' 'A swimming pool' }
  if ($shop -eq 'books') { return New-TypeInfo 'books' 'Книжный магазин' 'A bookshop' }
  if ($shop -eq 'music') { return New-TypeInfo 'music' 'Магазин винила и музыки' 'A vinyl and music shop' }
  if ($shop -eq 'antiques') { return New-TypeInfo 'antiques' 'Антикварный магазин' 'An antique shop' }
  if ($shop -in @('second_hand','vintage')) { return New-TypeInfo 'vintage' 'Винтажный магазин' 'A vintage shop' }
  if ($shop -eq 'art') { return New-TypeInfo 'art' 'Арт-галерея' 'An art gallery' }
  if ($shop -eq 'board_games') { return New-TypeInfo 'boardgames' 'Клуб настольных игр' 'A board game club' }
  if ($historic -eq 'manor') { return New-TypeInfo 'manor' 'Усадьба' 'A manor' }
  if ($name -match 'колесо обозр') { return New-TypeInfo 'wheel' 'Колесо обозрения' 'A Ferris wheel' }
  if ($name -match 'батут') { return New-TypeInfo 'trampoline' 'Батутный центр' 'A trampoline park' }
  if ($name -match 'боулинг') { return New-TypeInfo 'bowling' 'Боулинг' 'Bowling' }
  if ($name -match 'квест') { return New-TypeInfo 'quest' 'Квест-рум' 'An escape room' }
  if ($name -match 'караоке') { return New-TypeInfo 'karaoke' 'Караоке' 'Karaoke' }
  if ($name -match 'аквапарк|аквакомплекс') { return New-TypeInfo 'waterpark' 'Аквапарк' 'A water park' }
  if ($name -match 'каток|\bлёд\b|\bлед\b') { return New-TypeInfo 'rink' 'Каток' 'An ice rink' }
  if ($name -match 'планетарий') { return New-TypeInfo 'planetarium' 'Планетарий' 'A planetarium' }
  if ($name -match 'океанариум|москвариум') { return New-TypeInfo 'aquarium' 'Океанариум' 'An aquarium' }
  if ($name -match 'зоопарк') { return New-TypeInfo 'zoo' 'Зоопарк' 'A zoo' }
  if ($name -match 'музей') { return New-TypeInfo 'museum' 'Музей' 'A museum' }
  if ($name -match 'галере') { return New-TypeInfo 'gallery' 'Галерея' 'A gallery' }
  if ($name -match 'театр') { return New-TypeInfo 'theatre' 'Театр' 'A theatre' }
  if ($name -match 'кино') { return New-TypeInfo 'cinema' 'Кинотеатр' 'A cinema' }
  if ($name -match 'усадьб|усадеб') { return New-TypeInfo 'manor' 'Усадьба' 'A manor' }
  if ($name -match 'парк') { return New-TypeInfo 'park' 'Парк' 'A park' }
  if ($name -match 'сад') { return New-TypeInfo 'garden' 'Сад' 'A garden' }
  if ($name -match 'набереж|бульвар') { return New-TypeInfo 'walk' 'Прогулка' 'A walk' }
  if ($name -match 'книж') { return New-TypeInfo 'books' 'Книжный магазин' 'A bookshop' }
  if ($name -match 'винил|пластин') { return New-TypeInfo 'music' 'Магазин винила' 'A vinyl shop' }
  if ($name -match 'антиквар') { return New-TypeInfo 'antiques' 'Антикварный магазин' 'An antique shop' }
  if ($name -match 'винтаж') { return New-TypeInfo 'vintage' 'Винтажный магазин' 'A vintage shop' }
  if ($name -match 'рынок') { return New-TypeInfo 'market' 'Рынок' 'A market' }
  if ($name -match 'кофей') { return New-TypeInfo 'coffee' 'Кофейня' 'A coffee shop' }
  if ($name -match 'ресторан') { return New-TypeInfo 'restaurant' 'Ресторан' 'A restaurant' }
  if ($name -match 'антикафе') { return New-TypeInfo 'antikafe' 'Антикафе' 'An anti-cafe' }
  if ($name -match 'скалодром') { return New-TypeInfo 'climbing' 'Скалодром' 'A climbing wall' }
  if ($name -match 'картинг') { return New-TypeInfo 'karting' 'Картинг' 'Karting' }
  if ($name -match 'лазертаг') { return New-TypeInfo 'lasertag' 'Лазертаг' 'Laser tag' }
  if ($name -match '\bvr\b|виар') { return New-TypeInfo 'vr' 'VR-клуб' 'A VR club' }
  $category = [string]$Place.category
  switch ($category) {
    'coffee' { return New-TypeInfo 'coffee' 'Кофейня' 'A coffee shop' }
    'food' { return New-TypeInfo 'cafe' 'Кафе' 'A cafe' }
    'antikafe' { return New-TypeInfo 'antikafe' 'Антикафе' 'An anti-cafe' }
    'movie' { return New-TypeInfo 'cinema' 'Кинотеатр' 'A cinema' }
    'games' { return New-TypeInfo 'activity' 'Игровое место' 'A games venue' }
    'active' { return New-TypeInfo 'activity' 'Активность' 'An activity' }
    'culture' { return New-TypeInfo 'culture' 'Культурное место' 'A cultural place' }
    'walk' { return New-TypeInfo 'walk' 'Прогулка' 'A walk' }
    'shop' { return New-TypeInfo 'shop' 'Магазин' 'A shop' }
    default { return New-TypeInfo 'place' 'Городское место' 'A city place' }
  }
}

$activityRu = @{
  coffee = @('Выпить кофе', 'Взять завтрак или десерт', 'Поработать с ноутбуком', 'Взять напиток с собой')
  cafe = @('Поесть', 'Выпить кофе', 'Взять десерт', 'Посидеть с ноутбуком')
  restaurant = @('Пообедать или поужинать', 'Попробовать кухню', 'Забронировать столик', 'Прийти компанией')
  bar = @('Выпить коктейль', 'Взять закуски', 'Послушать музыку', 'Прийти вечером')
  fastfood = @('Быстро поесть', 'Взять с собой', 'Взять напиток', 'Перекусить')
  market = @('Купить продукты', 'Попробовать фермерскую еду', 'Взять готовую еду', 'Найти подарки')
  museum = @('Посмотреть экспозицию', 'Сходить на выставку', 'Взять экскурсию или аудиогид', 'Провести 1–2 часа')
  gallery = @('Посмотреть выставку', 'Открыть новое имя', 'Сходить на вернисаж', 'Купить искусство')
  theatre = @('Посмотреть спектакль', 'Взять билеты', 'Обсудить постановку', 'Прийти компанией')
  cinema = @('Посмотреть фильм', 'Взять попкорн', 'Выбрать сеанс', 'Прийти на вечерний показ')
  arts = @('Посмотреть выставки', 'Сходить на лекцию или концерт', 'Поработать в пространстве', 'Найти события')
  planetarium = @('Посмотреть сеанс', 'Послушать лекцию', 'Посмотреть в телескоп', 'Взять билет')
  aquarium = @('Посмотреть рыб и морских животных', 'Сходить с детьми', 'Взять экскурсию', 'Провести 1–2 часа')
  zoo = @('Посмотреть животных', 'Сходить с детьми', 'Погулять', 'Взять экскурсию')
  manor = @('Погулять по усадьбе', 'Посмотреть интерьеры', 'Сходить на выставку', 'Сделать фото')
  park = @('Погулять', 'Устроить пикник', 'Покататься на велосипеде', 'Сходить с детьми или собакой')
  garden = @('Погулять', 'Посмотреть растения', 'Сделать фото', 'Отдохнуть')
  viewpoint = @('Посмотреть панораму', 'Сделать фото', 'Встретить закат', 'Выпить кофе рядом')
  square = @('Погулять', 'Посмотреть архитектуру', 'Сделать фото', 'Зайти в кафе рядом')
  antikafe = @('Платить за время', 'Пить кофе и чай', 'Играть в настолки', 'Работать или встречаться')
  bowling = @('Играть на дорожке', 'Взять обувь', 'Заказать напитки и снеки', 'Прийти компанией')
  trampoline = @('Прыгать на батутах', 'Проходить полосу препятствий', 'Тренироваться с инструктором', 'Взять носки')
  quest = @('Проходить квест командой', 'Разгадывать загадки', 'Выбрать сюжет', 'Сделать фото')
  karaoke = @('Петь в отдельной комнате', 'Выбрать песни', 'Заказать напитки', 'Прийти компанией')
  rink = @('Кататься на коньках', 'Взять коньки в прокат', 'Прийти с детьми', 'Согреться в кафе')
  waterpark = @('Кататься с горок', 'Плавать в бассейне', 'Сходить в сауну или термы', 'Отдохнуть с детьми')
  climbing = @('Лазить по трассам', 'Взять инструктаж', 'Арендовать снаряжение', 'Тренироваться')
  karting = @('Проехать заезды', 'Взять шлем', 'Соревноваться с друзьями', 'Посмотреть трассу')
  lasertag = @('Играть командами', 'Выбрать сценарий', 'Взять снаряжение', 'Провести час активно')
  vr = @('Играть в VR', 'Выбрать игру', 'Прийти компанией', 'Попробовать новое')
  cooking = @('Готовить на мастер-классе', 'Попробовать блюда', 'Прийти компанией', 'Записаться заранее')
  wakeboard = @('Кататься на вейкборде', 'Взять снаряжение', 'Пройти инструктаж', 'Отдохнуть у воды')
  tennis = @('Играть в теннис', 'Арендовать корт', 'Взять тренера', 'Прийти компанией')
  sport = @('Тренироваться', 'Взять оборудование', 'Записаться на занятие', 'Прийти компанией')
  pool = @('Плавать', 'Взять дорожку', 'Сходить в сауну', 'Записаться на занятие')
  boardgames = @('Играть в настолки', 'Взять игру напрокат', 'Прийти компанией', 'Спросить правила')
  books = @('Выбрать книги', 'Посмотреть новинки', 'Купить подарок', 'Сходить на встречу')
  music = @('Посмотреть винил', 'Купить пластинку', 'Найти редкое издание', 'Спросить консультацию')
  antiques = @('Посмотреть антиквариат', 'Найти предмет интерьера', 'Купить коллекционное', 'Спросить оценку')
  vintage = @('Выбрать винтаж', 'Найти одежду или аксессуар', 'Купить подарок', 'Поторговаться')
  art = @('Посмотреть искусство', 'Купить работу', 'Сходить на выставку', 'Спросить консультацию')
  shop = @('Посмотреть товары', 'Купить подарок', 'Найти редкое', 'Спросить консультацию')
  attraction = @('Посмотреть главное', 'Сделать фото', 'Взять экскурсию', 'Проверить билеты')
  wheel = @('Пройти круг', 'Посмотреть панораму', 'Сделать фото', 'Взять билет')
  activity = @('Попробовать активность', 'Взять инструктаж', 'Прийти компанией', 'Проверить цену и запись')
  culture = @('Посмотреть экспозицию', 'Сходить на событие', 'Взять билет', 'Проверить часы')
  walk = @('Погулять', 'Сделать фото', 'Отдохнуть', 'Проверить маршрут')
}
$activityEn = @{
  coffee = @('Drink coffee', 'Get breakfast or dessert', 'Work with a laptop', 'Take a drink to go')
  cafe = @('Eat', 'Drink coffee', 'Get dessert', 'Sit with a laptop')
  restaurant = @('Have lunch or dinner', 'Try the cuisine', 'Book a table', 'Come with a group')
  bar = @('Have a cocktail', 'Order snacks', 'Listen to music', 'Come in the evening')
  fastfood = @('Eat quickly', 'Take away', 'Get a drink', 'Grab a snack')
  market = @('Buy groceries', 'Try farm food', 'Get ready food', 'Find gifts')
  museum = @('See the exhibition', 'Visit a temporary show', 'Take a tour or audio guide', 'Spend 1–2 hours')
  gallery = @('See an exhibition', 'Discover a new name', 'Visit an opening', 'Buy art')
  theatre = @('See a play', 'Get tickets', 'Discuss the production', 'Come with a group')
  cinema = @('See a film', 'Get popcorn', 'Choose a screening', 'Come for an evening show')
  arts = @('See exhibitions', 'Attend a talk or concert', 'Work in the space', 'Find events')
  planetarium = @('See a show', 'Attend a talk', 'Look through a telescope', 'Get a ticket')
  aquarium = @('See fish and sea animals', 'Come with kids', 'Take a tour', 'Spend 1–2 hours')
  zoo = @('See animals', 'Come with kids', 'Take a walk', 'Take a tour')
  manor = @('Walk around the estate', 'See the interiors', 'Visit an exhibition', 'Take photos')
  park = @('Take a walk', 'Have a picnic', 'Ride a bike', 'Come with kids or a dog')
  garden = @('Take a walk', 'See the plants', 'Take photos', 'Relax')
  viewpoint = @('See the panorama', 'Take photos', 'Watch the sunset', 'Get coffee nearby')
  square = @('Take a walk', 'See the architecture', 'Take photos', 'Visit a cafe nearby')
  antikafe = @('Pay for time', 'Drink coffee and tea', 'Play board games', 'Work or meet friends')
  bowling = @('Play on a lane', 'Get shoes', 'Order drinks and snacks', 'Come with a group')
  trampoline = @('Jump on trampolines', 'Try the obstacle course', 'Train with an instructor', 'Bring socks')
  quest = @('Play an escape room', 'Solve puzzles', 'Choose a story', 'Take photos')
  karaoke = @('Sing in a private room', 'Choose songs', 'Order drinks', 'Come with a group')
  rink = @('Go ice skating', 'Rent skates', 'Come with kids', 'Warm up at a cafe')
  waterpark = @('Ride the slides', 'Swim in the pool', 'Visit the sauna or thermal area', 'Relax with kids')
  climbing = @('Climb the routes', 'Take a briefing', 'Rent equipment', 'Train')
  karting = @('Drive the karts', 'Get a helmet', 'Compete with friends', 'See the track')
  lasertag = @('Play in teams', 'Choose a scenario', 'Get equipment', 'Spend an active hour')
  vr = @('Play VR', 'Choose a game', 'Come with a group', 'Try something new')
  cooking = @('Cook at a workshop', 'Taste the dishes', 'Come with a group', 'Book in advance')
  wakeboard = @('Ride a wakeboard', 'Get equipment', 'Take a briefing', 'Relax by the water')
  tennis = @('Play tennis', 'Book a court', 'Take a coach', 'Come with a group')
  sport = @('Train', 'Get equipment', 'Book a class', 'Come with a group')
  pool = @('Swim', 'Book a lane', 'Visit the sauna', 'Book a class')
  boardgames = @('Play board games', 'Rent a game', 'Come with a group', 'Ask for rules')
  books = @('Choose books', 'See new releases', 'Buy a gift', 'Attend an event')
  music = @('Browse vinyl', 'Buy a record', 'Find a rare edition', 'Ask for advice')
  antiques = @('Browse antiques', 'Find a piece for the interior', 'Buy a collectible', 'Ask for an appraisal')
  vintage = @('Browse vintage', 'Find clothes or accessories', 'Buy a gift', 'Haggle')
  art = @('See art', 'Buy a piece', 'Visit an exhibition', 'Ask for advice')
  shop = @('Browse the goods', 'Buy a gift', 'Find something rare', 'Ask for advice')
  attraction = @('See the highlight', 'Take photos', 'Take a tour', 'Check tickets')
  wheel = @('Ride a full circle', 'See the panorama', 'Take photos', 'Get a ticket')
  activity = @('Try the activity', 'Take a briefing', 'Come with a group', 'Check the price and booking')
  culture = @('See the exhibition', 'Attend an event', 'Get a ticket', 'Check the hours')
  walk = @('Take a walk', 'Take photos', 'Relax', 'Check the route')
}
function Get-ActivityList([string]$Key) {
  $ru = if ($activityRu.ContainsKey($Key)) { $activityRu[$Key] } else { $activityRu['activity'] }
  $en = if ($activityEn.ContainsKey($Key)) { $activityEn[$Key] } else { $activityEn['activity'] }
  return [pscustomobject]@{ ru = $ru; en = $en }
}

$nicheName = 'музей|галере|мастерск|винил|книжн|антиквар|барахолк|винтаж|рекорд|букинист|лектор|квартирник|скалодром|картинг|лазертаг|настол|антикафе|квест|батут|боулинг|аквапарк|каток|кулинар|вейк'
foreach ($p in $allPlaces) {
  $category = [string]$p.category
  $type = Get-PlaceTypeInfo $p
  Set-PlaceField $p 'what' ([ordered]@{ ru = $type.Ru; en = $type.En })
  Set-PlaceField $p 'placeType' $type.Key
  $activities = Get-ActivityList $type.Key
  if ([string]$p.source.id -ne 'seed') {
    Set-PlaceField $p 'activities' $activities
    Set-PlaceField $p 'whatYouGet' $activities
    Set-PlaceField $p 'hook' ([ordered]@{ ru = "$($type.Ru) в Москве"; en = "$($type.En) in Moscow" })
    $aboutRu = "$($p.name.ru) — $($type.Ru.ToLowerInvariant()) в Москве. Что можно делать: $($activities.ru[0].ToLowerInvariant()), $($activities.ru[1].ToLowerInvariant()), $($activities.ru[2].ToLowerInvariant()). Адрес, цену и часы уточняйте на карте или сайте заведения."
    $aboutEn = "$($p.name.ru) is $($type.En.ToLowerInvariant()) in Moscow. You can $($activities.en[0].ToLowerInvariant()), $($activities.en[1].ToLowerInvariant()), $($activities.en[2].ToLowerInvariant()). Check the address, price and opening hours on the map or venue website."
    Set-PlaceField $p 'about' ([ordered]@{ ru = $aboutRu; en = $aboutEn })
  }
  $tagsRu = @()
  if ($p.tags -and $p.tags.ru) { $tagsRu = @($p.tags.ru) }
  $hidden = ($category -in @('shop', 'games', 'antikafe')) -or ($tagsRu -contains 'небанально') -or (([string]$p.name.ru).ToLowerInvariant() -match $nicheName)
  Set-PlaceField $p 'hiddenGem' ([bool]$hidden)
  $hasCoords = ($null -ne $p.lat -and $null -ne $p.lon)
  $addressText = [string]$p.address.ru
  $hasRealAddress = $addressText -and $addressText -ne 'Москва' -and $addressText -ne 'Moscow'
  $hasSite = -not [string]::IsNullOrWhiteSpace([string]$p.website)
  $verified = ([string]$p.source.id -eq 'seed') -or ($hasCoords -and ($hasRealAddress -or $hasSite))
  Set-PlaceField $p 'verified' ([bool]$verified)
  $sourceId = [string]$p.source.id
  $descSource = switch ($sourceId) { 'seed' { 'редакция' } 'osm' { 'OpenStreetMap' } 'wikidata' { 'Wikidata' } default { 'СТОИТ' } }
  Set-PlaceField $p 'descriptionSource' $descSource
}

# ---------- проверенные цены ----------
$prices = Read-Json $PricesPath
$script:PriceById = @{}
$script:PriceByName = @{}
if ($null -ne $prices -and $null -ne $prices.entries) {
  foreach ($e in @($prices.entries)) {
    if ($null -eq $e) { continue }
    if ($e.id) { $script:PriceById[[string]$e.id] = $e }
    foreach ($n in @($e.names)) {
      $key = Normalize-MatchName ([string]$n)
      if ($key) { $script:PriceByName[$key] = $e }
    }
  }
}
foreach ($p in $allPlaces) {
  $e = Get-PriceOverride $p
  if ($null -ne $e) {
    Set-PlaceField $p 'price' ([int]$e.price)
    Set-PlaceField $p 'priceApprox' $false
    Set-PlaceField $p 'priceFrom' ([bool]$e.isFrom)
    if ($null -ne $e.priceUnit) { Set-PlaceField $p 'priceUnit' $e.priceUnit }
    if ($null -ne $e.priceNote) { Set-PlaceField $p 'priceNote' $e.priceNote }
    Set-PlaceField $p 'priceSource' ([string]$e.source)
    if ([string]::IsNullOrWhiteSpace([string]$p.website) -and $e.source) { Set-PlaceField $p 'website' ([string]$e.source) }
    if ($null -ne $e.sourceLabel) { Set-PlaceField $p 'priceSourceLabel' $e.sourceLabel }
    Set-PlaceField $p 'priceCheckedAt' ([string]$e.checkedAt)
    Set-PlaceField $p 'priceConfidence' ([string]$e.confidence)
    Set-PlaceField $p 'priceOrigin' 'manual'
  } elseif ($null -ne $p.price -and ([string]$p.source.id -eq 'seed')) {
    Set-PlaceField $p 'priceConfidence' 'editorial'
    Set-PlaceField $p 'priceOrigin' 'editorial'
    Set-PlaceField $p 'priceApprox' $true
    Set-PlaceField $p 'priceFrom' $false
  }
}

# ---------- автоматический поиск цен ----------
$discovery = [ordered]@{ checkedPlaces = 0; checkedSignals = 0; applied = 0; review = 0 }
try {
  $discovery = Invoke-PriceDiscovery -Places $allPlaces -Signals $finalSignals -Now $Now `
    -MaxPlaceChecks $MaxPriceChecks -MaxSignalChecks $MaxSignalPriceChecks `
    -CachePath $PriceCachePath -ReviewPath $PriceReviewPath -SkipNetwork:$NoPriceSearch
  if ($discovery.applied -gt 0) {
    Write-Host ("  цены: найдено {0}, на проверку {1}" -f $discovery.applied, $discovery.review) -ForegroundColor Green
  }
} catch {
  Write-Host "  ! Поиск цен: $($_.Exception.Message)" -ForegroundColor DarkYellow
}
$pricedCount = @($allPlaces | Where-Object { $null -ne $_.price }).Count

# ---------- логотипы и фотографии ----------
$media = [ordered]@{ checked = 0; icons = 0; galleries = 0; saved = 0 }
try {
  $media = Invoke-MediaDiscovery -Places $allPlaces -MaxChecks $MaxMediaChecks -MediaPath $MediaPath -CachePath $MediaCachePath -SkipNetwork:$NoMediaSearch
  if ($media.checked -gt 0) {
    Write-Host ("  медиа: проверено {0}, иконок {1}, галерей {2}" -f $media.checked, $media.icons, $media.galleries) -ForegroundColor Green
  }
} catch {
  Write-Host "  ! Медиа: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

$freshCount = @($finalSignals | Where-Object { ([DateTimeOffset]::Parse($_.publishedAt) -gt $Now.AddDays(-1)) }).Count
$okCount = @($sourceOut | Where-Object { $_.status -eq 'ok' -or $_.status -eq 'cached' }).Count

$nextLocal = $Now.Date.AddHours(9)
while ($nextLocal -lt $Now.DateTime) { $nextLocal = $nextLocal.AddDays(1) }
$next = [DateTimeOffset]::Parse($nextLocal.ToString('yyyy-MM-ddTHH:mm:ss') + '+03:00')

$feed = [ordered]@{
  schema = 11
  app = 'STOIT'
  updatedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
  nextUpdate = ([DateTimeOffset]$next).ToString('yyyy-MM-ddTHH:mm:sszzz')
  timezone = 'Europe/Moscow'
  note = [ordered]@{
    ru = 'Цены и наличие мест лучше сверять перед выходом — они собраны из открытых источников и могут меняться. Для каждой карточки указано, за что именно цена.'
    en = 'Prices and availability are best checked before you go — they come from public sources and may change. Each card says exactly what the price covers.'
  }
  stats = [ordered]@{
    places = $allPlaces.Count
    priced = $pricedCount
    priceChecked = $discovery.checkedPlaces + $discovery.checkedSignals
    priceApplied = $discovery.applied
    priceReview = $discovery.review
    mediaChecked = $media.checked
    mediaIcons = $media.icons
    mediaGalleries = $media.galleries
    signals = $finalSignals.Count
    fresh = $freshCount
    sourcesOk = $okCount
    sourcesTotal = @($sourceOut).Count
  }
  sources = $sourceOut
  places = $allPlaces
  signals = $finalSignals
}

Write-Utf8 $FeedPath ($feed | ConvertTo-Json -Depth 40 -Compress)

try {
  Save-Json $TrCache $TrCachePath
  Save-Json ([ordered]@{ date = $budgetDate; chars = $budgetChars }) $TrBudgetPath
} catch {
  Write-Host "  ! Не удалось сохранить кэш переводов: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

Write-Host ''
Write-Host ("Готово: {0} мест, {1} свежих идей, источников в норме {2}/{3}." -f $feed.stats.places, $feed.stats.signals, $okCount, @($sourceOut).Count) -ForegroundColor Green
Write-Host ("Новых переводов: {0}. Файл: data/feed.json" -f $newTranslated) -ForegroundColor DarkGray
