# СТОИТ — поиск цен по официальным сайтам и ссылкам из постов.
# Подключается из collect.ps1. Сам по себе файл ничего не запускает.

$script:PriceCache = @{}
$script:PriceCacheLoaded = $false
$script:PriceCheckedPlaces = 0
$script:PriceCheckedSignals = 0

function Set-DiscoveredField($Object, [string]$Name, $Value) {
  if ($null -eq $Object) { return }
  if ($Object -is [System.Collections.Specialized.OrderedDictionary]) {
    $Object[$Name] = $Value
  } elseif ($null -ne $Object.PSObject.Properties[$Name]) {
    $Object.$Name = $Value
  } else {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
  }
}

function Get-UrlHost([string]$Url) {
  if (-not $Url) { return '' }
  try { return ([Uri]$Url).Host.ToLowerInvariant() } catch { return '' }
}

function Test-SocialUrl([string]$Url) {
  if (-not $Url) { return $true }
  $hostName = Get-UrlHost $Url
  if (-not $hostName) { return $true }
  return ($hostName -match '(^|\.)(instagram\.com|t\.me|telegram\.me|vk\.com|facebook\.com|youtube\.com|youtu\.be|tiktok\.com|twitter\.com|x\.com|ok\.ru|pinterest\.com|threads\.net)$')
}

function Test-PriceSourceUrl([string]$Url) {
  if (-not $Url) { return $false }
  if (Test-SocialUrl $Url) { return $false }
  if ($Url -match '(?i)yandex\.ru/maps|google\.[a-z.]+/maps|2gis\.|news\.google\.com|google\.[a-z.]+/rss') { return $false }
  return $true
}

function ConvertTo-PriceText([string]$Html) {
  if (-not $Html) { return '' }
  $text = $Html
  if ($text.Length -gt 700000) { $text = $text.Substring(0, 700000) }
  $text = [regex]::Replace($text, '(?is)<script[\s\S]*?</script>', ' ')
  $text = [regex]::Replace($text, '(?is)<style[\s\S]*?</style>', ' ')
  $text = [regex]::Replace($text, '(?is)<noscript[\s\S]*?</noscript>', ' ')
  $text = [regex]::Replace($text, '(?is)<br\s*/?>', ' ')
  $text = [regex]::Replace($text, '(?is)</(p|div|li|tr|h[1-6])>', ' ')
  $text = [regex]::Replace($text, '<[^>]+>', ' ')
  $text = [Net.WebUtility]::HtmlDecode($text)
  $text = $text -replace '[\u00A0\u200B\uFEFF]', ' '
  return ($text -replace '\s+', ' ').Trim()
}

function Get-PricePageLinks([string]$Html, [string]$BaseUrl) {
  $links = @()
  if (-not $Html -or -not $BaseUrl) { return @() }
  $baseHost = Get-UrlHost $BaseUrl
  if (-not $baseHost) { return @() }
  foreach ($m in [regex]::Matches($Html, '(?is)<a\b[^>]*href\s*=\s*["'']([^"'']+)["''][^>]*>(.*?)</a>')) {
    $href = [Net.WebUtility]::HtmlDecode($m.Groups[1].Value.Trim())
    $anchor = ConvertTo-PriceText $m.Groups[2].Value
    if (-not $href) { continue }
    if ($href -match '^(#|mailto:|tel:|javascript:)') { continue }
    if ($href -match '(?i)\.(jpg|jpeg|png|gif|svg|webp|zip|rar|docx?)$') { continue }
    $absolute = $href
    try { $absolute = ([Uri]::new([Uri]$BaseUrl, $href)).AbsoluteUri } catch { continue }
    $linkHost = Get-UrlHost $absolute
    if (-not $linkHost) { continue }
    if ($linkHost -ne $baseHost -and -not $linkHost.EndsWith('.' + $baseHost) -and -not $baseHost.EndsWith('.' + $linkHost)) { continue }
    $haystack = ("$absolute $anchor").ToLowerInvariant()
    if ($haystack -notmatch 'билет|цена|цены|тариф|стоимост|прайс|price|ticket|tarif|cost|menu|меню|посещ|купить') { continue }
    if ($links -notcontains $absolute) { $links += $absolute }
    if ($links.Count -ge 4) { break }
  }
  return $links
}

function Get-DiscoveredUnit([string]$Context) {
  $c = $Context.ToLowerInvariant()
  if ($c -match 'средний чек') { return [pscustomobject]@{ Kind = 'average'; Ru = 'средний чек'; En = 'average bill' } }
  if ($c -match 'за игрока|с игрока|человек|персон') { return [pscustomobject]@{ Kind = 'person'; Ru = 'с человека'; En = 'per person' } }
  if ($c -match 'команд') { return [pscustomobject]@{ Kind = 'team'; Ru = 'за команду'; En = 'per team' } }
  if ($c -match 'мин') { return [pscustomobject]@{ Kind = 'hour'; Ru = 'за час'; En = 'per hour' } }
  if ($c -match 'час') { return [pscustomobject]@{ Kind = 'hour'; Ru = 'за час'; En = 'per hour' } }
  if ($c -match 'человек|персон') { return [pscustomobject]@{ Kind = 'person'; Ru = 'с человека'; En = 'per person' } }
  if ($c -match 'сеанс') { return [pscustomobject]@{ Kind = 'session'; Ru = 'за сеанс'; En = 'per session' } }
  if ($c -match 'меню|блюдо') { return [pscustomobject]@{ Kind = 'dish'; Ru = 'за блюдо'; En = 'per dish' } }
  if ($c -match 'билет') { return [pscustomobject]@{ Kind = 'ticket'; Ru = 'за билет'; En = 'per ticket' } }
  if ($c -match 'вход|взросл') { return [pscustomobject]@{ Kind = 'entry'; Ru = 'за вход'; En = 'entry' } }
  return [pscustomobject]@{ Kind = 'visit'; Ru = 'за визит'; En = 'per visit' }
}

function Clean-PriceQuote([string]$Quote) {
  if (-not $Quote) { return '' }
  $s = [regex]::Replace($Quote, '(?i)https?://\S+', ' ')
  $s = [regex]::Replace($s, '(?i)[\w.+-]+@[\w.-]+\.\w+', ' ')
  $s = [regex]::Replace($s, '(?i)\+?\d[\d\s()\-]{7,}\d', ' ')
  $s = $s -replace '\s+', ' '
  $s = $s.Trim(' ', ',', ';', ':', '-', '—')
  $cap = [regex]::Match($s, '[А-ЯЁA-Z]')
  if ($cap.Success -and $cap.Index -gt 0 -and $s.Substring(0, $cap.Index) -notmatch '\d') {
    $s = $s.Substring($cap.Index).Trim()
  }
  if ($s.Length -gt 170) { $s = $s.Substring(0, 167).TrimEnd() + '…' }
  return $s
}

function Get-PriceClause([string]$Text, [int]$Index, [int]$Length) {
  $start = [Math]::Max(0, $Index - 90)
  $end = [Math]::Min($Text.Length, $Index + $Length + 90)
  $chunk = $Text.Substring($start, $end - $start)
  $relative = $Index - $start
  $left = 0
  $right = $chunk.Length
  foreach ($separator in @(';', '•', '|', 'Купить', 'Будни', 'Выходные', 'вместо', 'Телефон', 'Почта', 'E-mail', 'Адрес', 'Забронировать')) {
    $leftText = $chunk.Substring(0, [Math]::Min($relative, $chunk.Length))
    $rightText = $chunk.Substring([Math]::Min($relative, $chunk.Length))
    $i = $leftText.LastIndexOf($separator, [StringComparison]::OrdinalIgnoreCase)
    if ($i -ge 0) { $left = [Math]::Max($left, $i + $separator.Length) }
    $j = $rightText.IndexOf($separator, [StringComparison]::OrdinalIgnoreCase)
    if ($j -ge 0) { $right = [Math]::Min($right, $relative + $j) }
  }
  if ($right -le $left) { return $chunk.Trim() }
  return $chunk.Substring($left, $right - $left).Trim()
}

function Get-PriceCandidates([string]$Text, [string]$PageUrl) {
  if (-not $Text) { return @() }
  $candidates = @()
  $Text = [regex]::Replace($Text, '(?i)от\s+(\d{1,3}(?:[ \u00A0]\d{3})+|\d{1,5})\s+до\s+(\d{1,3}(?:[ \u00A0]\d{3})+|\d{1,5})\s*(₽|руб(?:\.|лей|ля)?)', 'от $1 $3')
  $pattern = '(?<![\d])(\d{1,3}(?:[ \u00A0]\d{3})+|\d{1,5})\s*(?:[-–—]\s*(\d{1,3}(?:[ \u00A0]\d{3})+|\d{1,5}))?\s*(?:₽|руб(?:лей|ля)?\b|руб\.|р\.)'
  foreach ($m in [regex]::Matches($Text, $pattern, 'IgnoreCase')) {
    $raw = $m.Groups[1].Value -replace '[^\d]', ''
    if (-not $raw) { continue }
    $number = [int]$raw
    $hasRange = $m.Groups[2].Success
    $start = [Math]::Max(0, $m.Index - 110)
    $length = [Math]::Min(240, $Text.Length - $start)
    $context = $Text.Substring($start, $length)
    $lower = $context.ToLowerInvariant()
    $nearStart = [Math]::Max(0, $m.Index - 45)
    $nearLength = [Math]::Min(45, $Text.Length - $nearStart)
    $near = $Text.Substring($nearStart, $nearLength).ToLowerInvariant()
    $price = $number
    $perMinute = 0
    if ($number -lt 50) {
      if ($lower -match 'мин' -and $number -ge 1 -and $number -le 100) {
        $price = $number * 60
        $perMinute = $number
      } else {
        continue
      }
    }
    if ($price -gt 30000) { continue }
    if ($lower -match 'залог|депозит|банкет|аренда|доставка|скидк|абонемент|подарочн|сертификат|штраф|страхов|комисси|бронь|предоплат|минимальн|корпорат|свадьб|выпускн|новогодн|дополнительн|за каждого|сопровожд') { continue }
    if ($near -match 'детск|школьн|студенч|льготн|пенсион') { continue }
    if ($lower -notmatch 'взросл|вход|билет|тариф|стоимост|цен[аы]|час|человек|персон|сеанс|прокат|посещ|средний чек|обед|ланч|завтрак|меню|минут|игрока') { continue }
    $unit = Get-DiscoveredUnit $context
    $before = $Text.Substring($start, $m.Index - $start)
    $isFrom = $hasRange -or ($before -match '(?i)\bот\s*$') -or ($context -match '(?i)от\s+\d{2,5}\s*[-–—]')
    $score = 4
    if ($PageUrl -match '(?i)ticket|bilet|price|cena|tarif|стоимост|билет|цена|тариф') { $score += 2 }
    if ($lower -match 'взросл') { $score += 2 }
    if ($lower -match 'вход|билет|тариф|стоимост|цен[аы]|прайс') { $score += 2 }
    if ($lower -match 'средний чек') { $score += 1 }
    if ($lower -match 'официальн|прайс|прейскурант') { $score += 1 }
    if ($perMinute -gt 0) { $score += 2 }
    $rawQuote = Get-PriceClause $Text $m.Index $m.Length
    $currencyCount = ([regex]::Matches($rawQuote, '(?i)₽|руб(?:лей|ля)?\b|руб\.|р\.')).Count
    $quote = Clean-PriceQuote $rawQuote
    $candidates += [pscustomobject]@{
      Price = $price
      IsFrom = [bool]$isFrom
      UnitKind = $unit.Kind
      UnitRu = $unit.Ru
      UnitEn = $unit.En
      Quote = $quote
      CurrencyCount = $currencyCount
      Score = $score
      PageUrl = $PageUrl
      PerMinute = $perMinute
    }
  }
  return @($candidates | Sort-Object @{ Expression = { $_.Score }; Descending = $true }, @{ Expression = { $_.Price }; Descending = $false })
}

function Get-PricePageData([string]$Url) {
  if (-not $Url) { return $null }
  $entry = $script:PriceCache[$Url]
  if ($null -ne $entry) {
    try {
      $age = ($Now - [DateTimeOffset]::Parse([string]$entry.fetchedAt)).TotalDays
      $ok = [bool]$entry.ok
      if (($ok -and $age -lt 7) -or ((-not $ok) -and $age -lt 1)) { return $entry }
    } catch {}
  }
  $html = Get-RemoteText $Url
  if (-not $html) {
    $entry = [pscustomobject]@{ fetchedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz'); ok = $false; candidates = @(); links = @() }
    $script:PriceCache[$Url] = $entry
    return $entry
  }
  $text = ConvertTo-PriceText $html
  $candidates = @(Get-PriceCandidates $text $Url)
  $links = @(Get-PricePageLinks $html $Url)
  $entry = [pscustomobject]@{
    fetchedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
    ok = $true
    candidates = $candidates
    links = $links
  }
  $script:PriceCache[$Url] = $entry
  return $entry
}

function Select-BestPriceCandidate($Candidates, [string]$Category, [int]$MinScore = 6) {
  $list = @($Candidates | Where-Object { $null -ne $_ })
  if (-not $list.Count) { return $null }
  $allowed = @()
  foreach ($c in $list) {
    if ($c.UnitKind -eq 'team') { continue }
    if ($Category -in @('food','coffee')) {
      if ($c.UnitKind -ne 'average') { continue }
    } elseif ($Category -eq 'antikafe') {
      if ($c.UnitKind -notin @('hour','person','visit')) { continue }
    } elseif ($Category -in @('games','active')) {
      if ($c.UnitKind -notin @('hour','person','ticket','entry','visit')) { continue }
    } elseif ($Category -in @('culture','movie','walk')) {
      if ($c.UnitKind -notin @('ticket','entry','session','person')) { continue }
    }
    if ($c.Score -lt $MinScore) { continue }
    $allowed += $c
  }
  if (-not $allowed.Count) { return $null }
  return ($allowed | Sort-Object @{ Expression = { $_.Score }; Descending = $true }, @{ Expression = { $_.Price }; Descending = $false } | Select-Object -First 1)
}

function Test-AutoPriceCandidate($Candidate) {
  if ($null -eq $Candidate) { return $false }
  if ($Candidate.UnitKind -eq 'team') { return $false }
  $quote = [string]$Candidate.Quote
  $currencyCount = if ($null -ne $Candidate.PSObject.Properties['CurrencyCount']) { [int]$Candidate.CurrencyCount } else { ([regex]::Matches($quote, '(?i)₽|руб(?:лей|ля)?\b|руб\.|р\.')).Count }
  if ($currencyCount -gt 1) { return $false }
  if ($quote -match '(?i)вместо|скидк|акци|абонемент|безлимит|полный день|сутки|дополнительн|за каждого|сопровожд') { return $false }
  return $true
}

function Find-PlaceForText([string]$Text, $Places) {
  if (-not $Text) { return $null }
  $normalized = Normalize-MatchName $Text
  if (-not $normalized) { return $null }
  $best = $null
  $bestLength = 0
  foreach ($place in $Places) {
    $name = [string]$place.name.ru
    $full = Normalize-MatchName $name
    $core = Normalize-MatchName (Get-NameCore $name)
    if ($full.Length -ge 6 -and $normalized.Contains($full) -and $full.Length -gt $bestLength) {
      $best = $place
      $bestLength = $full.Length
    }
    if ($core.Length -ge 6 -and $normalized.Contains($core) -and $core.Length -gt $bestLength) {
      $best = $place
      $bestLength = $core.Length
    }
  }
  return $best
}

function Get-TextUrls([string]$Text) {
  $urls = @()
  if (-not $Text) { return @() }
  foreach ($m in [regex]::Matches($Text, 'https?://[^\s<>"'']+')) {
    $url = ($m.Value -replace '[),.;]+$', '').Trim()
    if ($url -and $urls -notcontains $url) { $urls += $url }
  }
  return $urls
}

function Set-DiscoveredPlacePrice($Place, $Candidate, [string]$Origin, [string]$Confidence) {
  Set-DiscoveredField $Place 'price' ([int]$Candidate.Price)
  Set-DiscoveredField $Place 'priceApprox' $false
  Set-DiscoveredField $Place 'priceFrom' ([bool]$Candidate.IsFrom)
  Set-DiscoveredField $Place 'priceUnit' ([ordered]@{ ru = $Candidate.UnitRu; en = $Candidate.UnitEn })
  $noteRu = if ($Origin -eq 'venue-site') {
    'Цена с официального сайта. Проверьте перед выходом.'
  } else {
    'Цена по ссылке из поста. Проверьте перед выходом.'
  }
  $noteEn = if ($Origin -eq 'venue-site') {
    'Price from the venue website. Check before you go.'
  } else {
    'Price from the link in the post. Check before you go.'
  }
  Set-DiscoveredField $Place 'priceNote' ([ordered]@{ ru = $noteRu; en = $noteEn })
  Set-DiscoveredField $Place 'priceSource' ([string]$Candidate.PageUrl)
  Set-DiscoveredField $Place 'priceCheckedAt' ([string]$Candidate.CheckedAt)
  Set-DiscoveredField $Place 'priceConfidence' $Confidence
  Set-DiscoveredField $Place 'priceOrigin' $Origin
  Set-DiscoveredField $Place 'priceQuote' ([string]$Candidate.Quote)
}

function Load-PriceCache([string]$Path) {
  if ($script:PriceCacheLoaded) { return }
  $script:PriceCacheLoaded = $true
  $raw = Read-Json $Path
  if ($null -eq $raw -or $null -eq $raw.pages) { return }
  foreach ($prop in $raw.pages.PSObject.Properties) {
    $script:PriceCache[$prop.Name] = $prop.Value
  }
}

function Save-PriceCache([string]$Path) {
  $pages = [ordered]@{}
  foreach ($key in $script:PriceCache.Keys) { $pages[$key] = $script:PriceCache[$key] }
  Save-Json ([ordered]@{ updatedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz'); pages = $pages }) $Path
}

function Invoke-PriceDiscovery {
  param(
    $Places,
    $Signals,
    $Now,
    [int]$MaxPlaceChecks = 12,
    [int]$MaxSignalChecks = 15,
    [string]$CachePath,
    [string]$ReviewPath,
    [switch]$SkipNetwork
  )
  Load-PriceCache $CachePath
  $script:PriceCheckedPlaces = 0
  $script:PriceCheckedSignals = 0
  $applied = @()
  $review = @()
  $signalMatches = @()

  foreach ($signal in $Signals) {
    $text = ("$($signal.title.ru) $($signal.summary.ru)").Trim()
    $place = Find-PlaceForText $text $Places
    if ($place) {
      Set-DiscoveredField $signal 'placeId' ([string]$place.id)
      $signalMatches += [pscustomobject]@{ Signal = $signal; Place = $place }
    }
    if ($null -ne $signal.price) {
      $discussion = ($text -match '(?i)коммент|обсужд|совету|по словам|в чате|подписчик|тред|форум') -or ([string]$signal.sourceKind -eq 'community')
      $origin = if ($discussion) { 'discussion' } elseif ([string]$signal.sourceKind -eq 'telegram' -or [string]$signal.sourceId -match '^instagram|^ig-') { 'post' } else { 'source-text' }
      Set-DiscoveredField $signal 'priceOrigin' $origin
      Set-DiscoveredField $signal 'priceConfidence' $(if ($discussion) { 'discussion' } elseif ($origin -eq 'post') { 'post' } else { 'source' })
    }
  }

  if (-not $SkipNetwork) {
    # 1. Ссылки, которые прямо есть в постах Telegram/Instagram.
    foreach ($match in $signalMatches) {
      if ($script:PriceCheckedSignals -ge $MaxSignalChecks) { break }
      $signal = $match.Signal
      $place = $match.Place
      $text = ("$($signal.title.ru) $($signal.summary.ru)").Trim()
      $urls = @(Get-TextUrls $text)
      if ($signal.url -and -not (Test-SocialUrl ([string]$signal.url))) { $urls += [string]$signal.url }
      $officialHost = Get-UrlHost ([string]$place.website)
      foreach ($url in @($urls | Select-Object -Unique)) {
        if (-not (Test-PriceSourceUrl $url)) { continue }
        $isOfficial = $officialHost -and ((Get-UrlHost $url) -eq $officialHost -or (Get-UrlHost $url).EndsWith('.' + $officialHost))
        if (-not $isOfficial -and $url -notmatch '(?i)ticket|bilet|price|cena|tarif|menu|меню|билет|цена|тариф') { continue }
        $script:PriceCheckedSignals += 1
        $page = Get-PricePageData $url
        if ($null -eq $page) { continue }
        $best = Select-BestPriceCandidate $page.candidates $place.category -MinScore 8
        if ($null -eq $best) { continue }
        $best | Add-Member -NotePropertyName CheckedAt -NotePropertyValue $Now.ToString('yyyy-MM-ddTHH:mm:sszzz') -Force
        if ($isOfficial -and $best.Score -ge 9 -and (Test-AutoPriceCandidate $best)) {
          $confidence = if ($best.Score -ge 11) { 'verified' } else { 'high' }
          Set-DiscoveredField $signal 'price' ([int]$best.Price)
          Set-DiscoveredField $signal 'priceUnit' ([ordered]@{ ru = $best.UnitRu; en = $best.UnitEn })
          Set-DiscoveredField $signal 'priceSource' ([string]$best.PageUrl)
          Set-DiscoveredField $signal 'priceCheckedAt' ([string]$Now.ToString('yyyy-MM-ddTHH:mm:sszzz'))
          Set-DiscoveredField $signal 'priceQuote' ([string]$best.Quote)
          Set-DiscoveredField $signal 'priceOrigin' 'post-link'
          Set-DiscoveredField $signal 'priceConfidence' $confidence
          $applied += [ordered]@{ kind = 'signal'; id = $signal.id; title = $signal.title.ru; price = $best.Price; source = $best.PageUrl; confidence = $confidence }
          break
        } else {
          $review += [ordered]@{ kind = 'signal'; id = $signal.id; title = $signal.title.ru; price = $best.Price; unit = $best.UnitRu; score = $best.Score; source = $best.PageUrl; quote = $best.Quote }
        }
      }
    }

    # 1b. Прямые ссылки в постах, даже если заведение не нашлось в каталоге.
    foreach ($signal in $Signals) {
      if ($script:PriceCheckedSignals -ge $MaxSignalChecks) { break }
      if ($signal.placeId) { continue }
      $text = ("$($signal.title.ru) $($signal.summary.ru)").Trim()
      $urls = @(Get-TextUrls $text)
      if ($signal.url -and -not (Test-SocialUrl ([string]$signal.url))) { $urls += [string]$signal.url }
      foreach ($url in @($urls | Select-Object -Unique)) {
        if (-not (Test-PriceSourceUrl $url)) { continue }
        if ($url -notmatch '(?i)ticket|bilet|price|cena|tarif|menu|меню|билет|цена|тариф') { continue }
        $script:PriceCheckedSignals += 1
        $page = Get-PricePageData $url
        if ($null -eq $page) { continue }
        $best = Select-BestPriceCandidate $page.candidates $signal.category -MinScore 8
        if ($null -eq $best) { continue }
        $best | Add-Member -NotePropertyName CheckedAt -NotePropertyValue $Now.ToString('yyyy-MM-ddTHH:mm:sszzz') -Force
        if ($best.Score -ge 9 -and (Test-AutoPriceCandidate $best)) {
          Set-DiscoveredField $signal 'price' ([int]$best.Price)
          Set-DiscoveredField $signal 'priceUnit' ([ordered]@{ ru = $best.UnitRu; en = $best.UnitEn })
          Set-DiscoveredField $signal 'priceSource' ([string]$best.PageUrl)
          Set-DiscoveredField $signal 'priceCheckedAt' ([string]$Now.ToString('yyyy-MM-ddTHH:mm:sszzz'))
          Set-DiscoveredField $signal 'priceQuote' ([string]$best.Quote)
          Set-DiscoveredField $signal 'priceOrigin' 'post-link'
          Set-DiscoveredField $signal 'priceConfidence' 'medium'
          $applied += [ordered]@{ kind = 'signal'; id = $signal.id; title = $signal.title.ru; price = $best.Price; source = $best.PageUrl; confidence = 'medium' }
          break
        } else {
          $review += [ordered]@{ kind = 'signal'; id = $signal.id; title = $signal.title.ru; price = $best.Price; unit = $best.UnitRu; score = $best.Score; source = $best.PageUrl; quote = $best.Quote }
        }
      }
    }

    # 2. Официальные сайты заведений без цены. Сначала те, что упомянуты в постах.
    $candidates = @()
    foreach ($place in $Places) {
      if ($null -ne $place.price) { continue }
      if (-not $place.website) { continue }
      if (-not (Test-PriceSourceUrl ([string]$place.website))) { continue }
      if ($place.category -notin @('culture','walk','games','active','antikafe','movie')) { continue }
      $candidates += $place
    }
    $ordered = @()
    foreach ($match in $signalMatches) {
      if ($candidates -contains $match.Place -and $ordered -notcontains $match.Place) { $ordered += $match.Place }
    }
    foreach ($place in $candidates) {
      if ($ordered -notcontains $place) { $ordered += $place }
    }

    foreach ($place in $ordered) {
      if ($script:PriceCheckedPlaces -ge $MaxPlaceChecks) { break }
      $script:PriceCheckedPlaces += 1
      $homePage = Get-PricePageData ([string]$place.website)
      if ($null -eq $homePage) { continue }
      $allCandidates = @($homePage.candidates)
      $homeHost = Get-UrlHost ([string]$place.website)
      foreach ($link in @($homePage.links | Where-Object { (Get-UrlHost $_) -eq $homeHost } | Select-Object -First 2)) {
        $page = Get-PricePageData $link
        if ($null -ne $page) { $allCandidates += $page.candidates }
      }
      $best = Select-BestPriceCandidate $allCandidates $place.category -MinScore 6
      if ($null -eq $best) { continue }
      $best | Add-Member -NotePropertyName CheckedAt -NotePropertyValue $Now.ToString('yyyy-MM-ddTHH:mm:sszzz') -Force
      if ($best.Score -ge 6 -and (Test-AutoPriceCandidate $best)) {
        $confidence = if ($best.Score -ge 10) { 'verified' } else { 'high' }
        Set-DiscoveredPlacePrice $place $best 'venue-site' $confidence
        $applied += [ordered]@{ kind = 'place'; id = $place.id; title = $place.name.ru; price = $best.Price; unit = $best.UnitRu; source = $best.PageUrl; confidence = $confidence }
      } else {
        $review += [ordered]@{ kind = 'place'; id = $place.id; title = $place.name.ru; price = $best.Price; unit = $best.UnitRu; score = $best.Score; source = $best.PageUrl; quote = $best.Quote }
      }
    }
  }

  Save-PriceCache $CachePath
  $reviewObj = [ordered]@{
    updatedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
    checkedPlaces = $script:PriceCheckedPlaces
    checkedSignals = $script:PriceCheckedSignals
    applied = @($applied)
    review = @($review | Select-Object -First 60)
  }
  try { Save-Json $reviewObj $ReviewPath } catch {}
  return [ordered]@{
    checkedPlaces = $script:PriceCheckedPlaces
    checkedSignals = $script:PriceCheckedSignals
    applied = @($applied).Count
    review = @($review).Count
  }
}
