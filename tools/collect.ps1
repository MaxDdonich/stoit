# СТОИТ — ежедневный сборщик данных.
# Запуск: powershell -ExecutionPolicy Bypass -File tools\collect.ps1
# Флаги: -NoTranslate (быстро, без машинного перевода), -MaxSignals 36

param(
  [switch]$NoTranslate,
  [int]$MaxSignals = 80,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}

$Root        = Split-Path -Parent $PSScriptRoot
$DataDir     = Join-Path $Root 'data'
$CacheDir    = Join-Path $DataDir 'cache'
$ConfigPath  = Join-Path $Root 'config\sources.json'
$SeedPath    = Join-Path $DataDir 'seed.json'
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
    publisher = [string]$s.publisher
    publishedAt = $s.publishedAt
    category = $s.category
    machineTranslated = ($titleEn -ne $titleRu -or $summaryEn -ne $summaryRu)
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
    $c = Get-NameCore ([string]$p.name.ru)
    $dup = $false
    foreach ($k in $knownCores) {
      if ($k.Length -ge 4 -and $c -and ($c -eq $k -or $c.Contains($k))) { $dup = $true; break }
    }
    if ($dup) { continue }
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
    note = [ordered]@{ ru = '© OpenStreetMap contributors, ODbL 1.0. Цены ориентировочные.'; en = '© OpenStreetMap contributors, ODbL 1.0. Prices are approximate.' }
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
    $c = Get-NameCore ([string]$p.name.ru)
    $dup = $false
    foreach ($k in $knownCores) {
      if ($k.Length -ge 4 -and $c -and ($c -eq $k -or $c.Contains($k))) { $dup = $true; break }
    }
    if ($dup) { continue }
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
    note = [ordered]@{ ru = 'Wikidata, CC0. Цены ориентировочные.'; en = 'Wikidata, CC0. Prices are approximate.' }
  }
}

$freshCount = @($finalSignals | Where-Object { ([DateTimeOffset]::Parse($_.publishedAt) -gt $Now.AddDays(-1)) }).Count
$okCount = @($sourceOut | Where-Object { $_.status -eq 'ok' -or $_.status -eq 'cached' }).Count

$nextLocal = $Now.Date.AddHours(9)
while ($nextLocal -lt $Now.DateTime) { $nextLocal = $nextLocal.AddDays(1) }
$next = [DateTimeOffset]::Parse($nextLocal.ToString('yyyy-MM-ddTHH:mm:ss') + '+03:00')

$feed = [ordered]@{
  schema = 9
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
