# СТОИТ — поиск логотипов и фотографий на официальных сайтах.
# Подключается из collect.ps1.

$script:MediaCache = @{}
$script:MediaCacheLoaded = $false
$script:MediaChecked = 0
$script:SiteFilters = $null

# Взрослый контент и парковка домена — такие сайты не показываем как сайт заведения.
$script:AdultPattern = '(?i)(?<![а-яёa-z])(эскорт|интим|проститут|секс[- ]услуг|досуг\s+девушек|девушки\s+по\s+вызову|escort|porn)(?![а-яёa-z])'
$script:ParkedPattern = '(?i)домен\s+прода|продаётся\s+домен|parked\s+domain|domain\s+for\s+sale|buy\s+this\s+domain|срок\s+регистрации\s+домена\s+(истёк|закончил)'
$script:GamblingPattern = '(?i)казино|casino|parimatch|букмекер|ставки\s+на\s+спорт|1xbet|vulkan|joycasino|слоты|бездепозитн|промокод'
$script:PiratePattern = '(?i)смотреть\s+фильмы\s+онлайн|скачать\s+фильм|фильмы\s+онлайн\s+бесплатно'
$script:DeadSitePattern = '(?i)сайт\s+закрыт|сайт\s+не\s+работает|домен\s+не\s+активен|domain\s+expired|account\s+suspended'
$script:ClosedPattern = '(?i)(временно\s+закрыт[а-яё]*|закрыт[а-яё]*\s+на\s+(ремонт|реконструкц)[а-яё]*|закрыт[а-яё]*\s+на\s+ремонтно|временно\s+не\s+работает|temporarily\s+closed)'
# Если рядом закрыт зал, каток, выставка или ресторан — это не значит, что закрыто всё место.
$script:SubObjectPattern = '(?i)зал|павильон|выставк|экспозиц|каток|башн|смотров|флигел|корпус|этаж|киоск|касс|ресторан|кафе|магазин|площадк|маршрут|участок|набережн|вход|сеанс|лекци|концерт|библиотек|зон[аы]|гараж|парковк'
# Слова, которые есть в названии почти любого места и ничего не доказывают.
$script:GenericNameTokens = @('музей', 'музеи', 'театр', 'парк', 'кинотеатр', 'центр', 'дом', 'усадьба', 'галерея', 'библиотека', 'москва', 'московский', 'московская', 'государственный')

function Get-SiteFilters {
  if ($null -ne $script:SiteFilters) { return $script:SiteFilters }
  $rootDir = if ($Root) { [string]$Root } else { Split-Path -Parent $PSScriptRoot }
  $path = Join-Path $rootDir 'config/site-filters.json'
  $raw = $null
  try { if (Test-Path $path) { $raw = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json } } catch {}
  $blocked = @()
  $closed = @()
  if ($null -ne $raw) {
    foreach ($item in @($raw.blockedHosts)) {
      if ($null -eq $item) { continue }
      $hostName = if ($item -is [string]) { [string]$item } else { [string]$item.host }
      if ($hostName) { $blocked += ($hostName.ToLowerInvariant() -replace '^www\.', '') }
    }
    foreach ($item in @($raw.closedPlaceIds)) { if ($item) { $closed += [string]$item } }
  }
  $script:SiteFilters = [pscustomobject]@{ BlockedHosts = $blocked; ClosedPlaceIds = $closed }
  return $script:SiteFilters
}

function Test-BlockedHost([string]$Url) {
  if (-not $Url) { return $false }
  $hostName = Get-UrlHost $Url
  if (-not $hostName) { return $false }
  $hostName = $hostName -replace '^www\.', ''
  $filters = Get-SiteFilters
  foreach ($blocked in $filters.BlockedHosts) {
    if ($hostName -eq $blocked -or $hostName.EndsWith('.' + $blocked)) { return $true }
  }
  return $false
}

function Test-ClosedContext([string]$Context, [string]$PlaceName) {
  if (-not $Context) { return $false }
  if ($Context -match '(?i)будет|планиру|с\s+\d{1,2}\s+(январ|феврал|март|апрел|ма[йя]|июн|июл|август|сентябр|октябр|ноябр|декабр)') { return $false }
  if ($Context -match $script:SubObjectPattern) { return $false }
  $lower = $Context.ToLowerInvariant()
  foreach ($token in @($PlaceName.ToLowerInvariant() -split '[^a-zа-яё0-9]+')) {
    if ($token.Length -lt 4) { continue }
    if ($script:GenericNameTokens -contains $token) { continue }
    if ($lower.Contains($token)) { return $true }
  }
  return $false
}

function Resolve-MediaUrl([string]$BaseUrl, [string]$Value) {
  if (-not $Value) { return '' }
  $value = [Net.WebUtility]::HtmlDecode($Value.Trim())
  if ($value -match '^(data:|javascript:|mailto:|tel:)') { return '' }
  if ($value.StartsWith('//')) { return 'https:' + $value }
  try {
    $absolute = ([Uri]::new([Uri]$BaseUrl, $value)).AbsoluteUri
    return ($absolute -replace '^http://', 'https://')
  } catch { return '' }
}

function Test-MediaSourceUrl([string]$Url) {
  if (-not $Url) { return $false }
  if (Test-SocialUrl $Url) { return $false }
  $hostName = Get-UrlHost $Url
  if (-not $hostName) { return $false }
  return ($hostName -notmatch '(^|\.)(afisha\.ru|yandex\.[a-z.]+|kudago\.com|tripadvisor\.[a-z.]+|2gis\.[a-z.]+|google\.[a-z.]+|restoclub\.ru|timeout\.ru|zoon\.ru|otzovik\.com|tinkoff\.ru|sberbank\.ru)$')
}

function Test-PhotoUrl([string]$Url) {
  if (-not $Url) { return $false }
  if ($Url -match '(?i)\.svg(\?|$)') { return $false }
  if ($Url -match '(?i)logo|favicon|sprite|pixel|tracking|placeholder|avatar|qr-|qrcode|barcode|/20x/|resize/20x|tovar|product|catalog|goods|hobbygames/video|/video/|/news/|/blog/|/article/|teg-') { return $false }
  if ($Url -match '(?i)(?:^|[^0-9])(\d{2,3})x(\d{2,3})(?:[^0-9]|$)') {
    $w = [int]$Matches[1]
    $h = [int]$Matches[2]
    if ($w -lt 300 -or $h -lt 300) { return $false }
  }
  if ($Url -match '(?i)\.(jpg|jpeg|png|webp|avif)(\?|$)') { return $true }
  if ($Url -match '(?i)(format|fm)=(jpg|jpeg|png|webp|avif)') { return $true }
  return $false
}

function Get-MediaIcon([string]$Html, [string]$BaseUrl) {
  $icons = @()
  foreach ($tag in [regex]::Matches($Html, '(?is)<link\b[^>]*>')) {
    $value = $tag.Value
    $relMatch = [regex]::Match($value, '(?is)rel\s*=\s*["'']([^"'']+)["'']')
    if (-not $relMatch.Success) { continue }
    $rel = $relMatch.Groups[1].Value.ToLowerInvariant()
    if ($rel -notmatch 'icon') { continue }
    $hrefMatch = [regex]::Match($value, '(?is)href\s*=\s*["'']([^"'']+)["'']')
    if (-not $hrefMatch.Success) { continue }
    $url = Resolve-MediaUrl $BaseUrl $hrefMatch.Groups[1].Value
    if (-not $url) { continue }
    $score = 0
    $sizes = [regex]::Match($value, '(?is)sizes\s*=\s*["''](\d+)x(\d+)["'']')
    if ($sizes.Success) { $score = [int]$sizes.Groups[1].Value }
    if ($rel -match 'apple') { $score += 1000 }
    $icons += [pscustomobject]@{ Url = $url; Score = $score }
  }
  $logos = @()
  foreach ($tag in [regex]::Matches($Html, '(?is)<img\b[^>]*>')) {
    $value = $tag.Value
    $srcMatch = [regex]::Match($value, '(?is)src\s*=\s*["'']([^"'']+)["'']')
    if (-not $srcMatch.Success) { continue }
    $meta = ($value + ' ' + $srcMatch.Groups[1].Value).ToLowerInvariant()
    if ($meta -notmatch 'logo|brand|site-logo|header-logo') { continue }
    $url = Resolve-MediaUrl $BaseUrl $srcMatch.Groups[1].Value
    if ($url) { $logos += [pscustomobject]@{ Url = $url; Score = 500 } }
  }
  $jsonLogo = [regex]::Match($Html, '(?is)"logo"\s*:\s*"([^"]+)"')
  if ($jsonLogo.Success) {
    $url = Resolve-MediaUrl $BaseUrl $jsonLogo.Groups[1].Value
    if ($url) { $logos += [pscustomobject]@{ Url = $url; Score = 700 } }
  }
  $all = @($icons + $logos | Sort-Object Score -Descending)
  if ($all.Count) { return $all[0].Url }
  return ''
}

function Get-MediaGallery([string]$Html, [string]$BaseUrl) {
  $urls = @()
  foreach ($pattern in @(
    '(?is)<meta[^>]+(?:property|name)\s*=\s*["''](?:og:image|twitter:image)["''][^>]+content\s*=\s*["'']([^"'']+)["'']',
    '(?is)<meta[^>]+content\s*=\s*["'']([^"'']+)["''][^>]+(?:property|name)\s*=\s*["''](?:og:image|twitter:image)["'']'
  )) {
    foreach ($m in [regex]::Matches($Html, $pattern)) {
      $url = Resolve-MediaUrl $BaseUrl $m.Groups[1].Value
      if (Test-PhotoUrl $url) { $urls += $url }
    }
  }
  foreach ($m in [regex]::Matches($Html, '(?is)"image"\s*:\s*"([^"]+)"')) {
    $url = Resolve-MediaUrl $BaseUrl $m.Groups[1].Value
    if (Test-PhotoUrl $url) { $urls += $url }
  }
  foreach ($m in [regex]::Matches($Html, '(?is)"image"\s*:\s*\[\s*"([^"]+)"')) {
    $url = Resolve-MediaUrl $BaseUrl $m.Groups[1].Value
    if (Test-PhotoUrl $url) { $urls += $url }
  }
  foreach ($tag in [regex]::Matches($Html, '(?is)<img\b[^>]*>')) {
    $value = $tag.Value
    $srcMatch = [regex]::Match($value, '(?is)src\s*=\s*["'']([^"'']+)["'']')
    if (-not $srcMatch.Success) { continue }
    $meta = ($value + ' ' + $srcMatch.Groups[1].Value).ToLowerInvariant()
    if ($meta -match 'logo|icon|avatar|sprite|pixel|tracking|placeholder|favicon|banner|marker|map') { continue }
    $width = [regex]::Match($value, '(?is)width\s*=\s*["'']?(\d+)')
    $height = [regex]::Match($value, '(?is)height\s*=\s*["'']?(\d+)')
    if ($width.Success -and [int]$width.Groups[1].Value -lt 300) { continue }
    if ($height.Success -and [int]$height.Groups[1].Value -lt 300) { continue }
    $url = Resolve-MediaUrl $BaseUrl $srcMatch.Groups[1].Value
    if (Test-PhotoUrl $url) { $urls += $url }
  }
  $clean = @()
  foreach ($url in $urls) {
    if ($url -and $clean -notcontains $url) { $clean += $url }
    if ($clean.Count -ge 12) { break }
  }
  return $clean
}

function Get-MediaGalleryLinks([string]$Html, [string]$BaseUrl) {
  $links = @()
  if (-not $Html -or -not $BaseUrl) { return @() }
  $baseHost = Get-UrlHost $BaseUrl
  foreach ($m in [regex]::Matches($Html, '(?is)<a\b[^>]*href\s*=\s*["'']([^"'']+)["''][^>]*>(.*?)</a>')) {
    $href = [Net.WebUtility]::HtmlDecode($m.Groups[1].Value.Trim())
    $anchor = ConvertTo-PriceText $m.Groups[2].Value
    if ($href -match '^(#|mailto:|tel:|javascript:)') { continue }
    $absolute = ''
    try { $absolute = ([Uri]::new([Uri]$BaseUrl, $href)).AbsoluteUri } catch { continue }
    if ((Get-UrlHost $absolute) -ne $baseHost) { continue }
    $haystack = ("$absolute $anchor").ToLowerInvariant()
    if ($haystack -notmatch 'галере|фотогалере|фото|интерьер|gallery|photo') { continue }
    if ($haystack -match 'logo|icon|avatar|qr') { continue }
    if ($links -notcontains $absolute) { $links += $absolute }
    if ($links.Count -ge 4) { break }
  }
  return $links
}

function Get-CommonsGallery([string]$Category, [string]$Name, [int]$Limit = 12) {
  $sources = @()
  if ($Category) {
    $sources += [pscustomobject]@{
      Params = 'generator=categorymembers&gcmtitle=' + [Uri]::EscapeDataString("Category:$Category") + '&gcmtype=file&gcmlimit=24'
      IsSearch = $false
    }
  }
  if ($Name) {
    $sources += [pscustomobject]@{
      Params = 'generator=search&gsrsearch=' + [Uri]::EscapeDataString("$Name Москва") + '&gsrnamespace=6&gsrlimit=12'
      IsSearch = $true
    }
  }
  if ($sources.Count -eq 0) { return @() }

  $photos = @()
  $seen = @{}
  foreach ($source in $sources) {
    if ($photos.Count -ge $Limit) { break }
    # Если категория уже дала достаточно обзорных снимков, поиск по названию не нужен.
    if ($source.IsSearch -and $photos.Count -ge 6) { break }
    $url = "https://commons.wikimedia.org/w/api.php?action=query&format=json&prop=imageinfo&iiprop=url%7Cmime&iiurlwidth=1600&$($source.Params)"
    $raw = Get-RemoteText $url
    if (-not $raw) { continue }
    try { $doc = $raw | ConvertFrom-Json } catch { continue }
    if ($null -eq $doc.query -or $null -eq $doc.query.pages) { continue }
    foreach ($prop in $doc.query.pages.PSObject.Properties) {
      $page = $prop.Value
      if (-not $page.imageinfo -or -not $page.imageinfo[0]) { continue }
      $info = $page.imageinfo[0]
      $mime = [string]$info.mime
      if ($mime -notmatch '^image/(jpeg|png|webp)$') { continue }
      $photoUrl = [string]$info.thumburl
      if (-not $photoUrl) { $photoUrl = [string]$info.url }
      if (-not $photoUrl) { continue }
      $title = [string]$page.title
      if ($title -match '(?i)logo|icon|map|plan|scheme|coat|flag|qr|diagram|poster|banner|stamp|symbol|signature|grave|могил|портрет|portrait') { continue }
      $key = ([Uri]$photoUrl).Segments[-1]
      $key = [Uri]::UnescapeDataString($key) -replace '^\d+px-', ''
      if ($seen.ContainsKey($key)) { continue }
      $seen[$key] = $true
      $photos += $photoUrl
      if ($photos.Count -ge $Limit) { break }
    }
    Start-Sleep -Milliseconds 350
  }
  return $photos
}

function Get-CommonsGeoGallery([double]$Lat, [double]$Lon, [int]$Radius = 180, [int]$Limit = 12) {
  if (-not $Lat -or -not $Lon) { return @() }
  $url = "https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=geosearch&ggscoord=$Lat%7C$Lon&ggsradius=$Radius&ggsnamespace=6&ggslimit=20&prop=imageinfo&iiprop=url%7Cmime&iiurlwidth=1600"
  $raw = Get-RemoteText $url
  if (-not $raw) { return @() }
  try { $doc = $raw | ConvertFrom-Json } catch { return @() }
  if ($null -eq $doc.query -or $null -eq $doc.query.pages) { return @() }
  $photos = @()
  $seen = @{}
  foreach ($prop in $doc.query.pages.PSObject.Properties) {
    $page = $prop.Value
    if (-not $page.imageinfo -or -not $page.imageinfo[0]) { continue }
    $info = $page.imageinfo[0]
    if ([string]$info.mime -notmatch '^image/(jpeg|png|webp)$') { continue }
    $photoUrl = [string]$info.thumburl
    if (-not $photoUrl) { $photoUrl = [string]$info.url }
    if (-not $photoUrl) { continue }
    $title = [string]$page.title
    if ($title -match '(?i)logo|icon|map|plan|scheme|coat|flag|qr|diagram|poster|banner|stamp|symbol|signature|grave|могил|портрет|portrait') { continue }
    $key = [Uri]::UnescapeDataString(([Uri]$photoUrl).Segments[-1]) -replace '^\d+px-', ''
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    $photos += $photoUrl
    if ($photos.Count -ge $Limit) { break }
  }
  return $photos
}

function Get-MediaPageData([string]$Url) {
  if (-not $Url) { return $null }
  $entry = $script:MediaCache[$Url]
  if ($null -ne $entry) {
    try {
      $age = ($Now - [DateTimeOffset]::Parse([string]$entry.fetchedAt)).TotalDays
      if (($entry.ok -and $age -lt 7) -or ((-not $entry.ok) -and $age -lt 1)) { return $entry }
    } catch {}
  }
  $html = Get-RemoteText $Url
  if (-not $html) {
    $entry = [pscustomobject]@{ fetchedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz'); ok = $false; icon = ''; gallery = @(); galleryLinks = @(); adult = $false; spamReason = ''; closedContexts = @() }
    $script:MediaCache[$Url] = $entry
    return $entry
  }
  $text = ConvertTo-PriceText $html
  $titleMatch = [regex]::Match($html, '(?is)<title[^>]*>(.*?)</title>')
  $title = if ($titleMatch.Success) { ConvertTo-PriceText $titleMatch.Groups[1].Value } else { '' }
  $descMatch = [regex]::Match($html, '(?is)<meta[^>]+name\s*=\s*["'']description["''][^>]+content\s*=\s*["'']([^"'']*)["'']')
  $description = if ($descMatch.Success) { [Net.WebUtility]::HtmlDecode($descMatch.Groups[1].Value) } else { '' }
  $pageText = "$title $description $text"
  $head = "$title $description"
  $adult = ($head -match $script:AdultPattern) -or ($pageText -match $script:AdultPattern)
  $spamReason = ''
  if ($adult) { $spamReason = 'adult-website' }
  elseif ($head -match $script:GamblingPattern) { $spamReason = 'gambling-website' }
  elseif ($head -match $script:PiratePattern) { $spamReason = 'pirate-website' }
  elseif ($pageText -match $script:ParkedPattern) { $spamReason = 'parked-domain' }
  elseif ($head -match $script:DeadSitePattern) { $spamReason = 'dead-site' }
  $closedContexts = @()
  foreach ($m in [regex]::Matches($pageText, $script:ClosedPattern)) {
    $start = [Math]::Max(0, $m.Index - 90)
    $len = [Math]::Min(220, $pageText.Length - $start)
    $closedContexts += $pageText.Substring($start, $len)
    if ($closedContexts.Count -ge 3) { break }
  }
  $icon = Get-MediaIcon $html $Url
  $gallery = @(Get-MediaGallery $html $Url)
  $galleryLinks = @(Get-MediaGalleryLinks $html $Url)
  $entry = [pscustomobject]@{
    fetchedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
    ok = $true
    icon = $icon
    gallery = $gallery
    galleryLinks = $galleryLinks
    adult = [bool]$adult
    spamReason = $spamReason
    closedContexts = @($closedContexts)
  }
  $script:MediaCache[$Url] = $entry
  return $entry
}

function Load-MediaStore([string]$Path) {
  $raw = Read-Json $Path
  $store = @{}
  if ($null -ne $raw -and $null -ne $raw.places) {
    foreach ($prop in $raw.places.PSObject.Properties) { $store[$prop.Name] = $prop.Value }
  }
  return $store
}

function Load-MediaCache([string]$Path) {
  if ($script:MediaCacheLoaded) { return }
  $script:MediaCacheLoaded = $true
  $raw = Read-Json $Path
  if ($null -eq $raw -or $null -eq $raw.pages) { return }
  foreach ($prop in $raw.pages.PSObject.Properties) { $script:MediaCache[$prop.Name] = $prop.Value }
}

function Save-MediaCache([string]$Path) {
  $pages = [ordered]@{}
  foreach ($key in $script:MediaCache.Keys) { $pages[$key] = $script:MediaCache[$key] }
  Save-Json ([ordered]@{ updatedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz'); pages = $pages }) $Path
}

function Clear-BlockedWebsite($Place, [string]$Reason, [string]$BadHost) {
  Set-PlaceField $Place 'websiteChecked' $true
  Set-PlaceField $Place 'websiteBlocked' $true
  if ($Reason) { Set-PlaceField $Place 'blockedReason' $Reason }
  Set-PlaceField $Place 'website' ''
  Set-PlaceField $Place 'icon' ''
  Set-PlaceField $Place 'iconKind' ''
  Set-PlaceField $Place 'iconSource' ''
  Set-PlaceField $Place 'iconFallback' ''
  Set-PlaceField $Place 'iconFallback2' ''
  Set-PlaceField $Place 'iconFallback3' ''
  Set-PlaceField $Place 'gallery' @()
  Set-PlaceField $Place 'gallerySource' ''
  if ($BadHost -and $Place.priceSource -and ((Get-UrlHost ([string]$Place.priceSource)) -eq $BadHost)) {
    Set-PlaceField $Place 'price' $null
    Set-PlaceField $Place 'priceSource' ''
    Set-PlaceField $Place 'priceConfidence' 'unknown'
  }
}

function Apply-MediaEntry($Place, $Entry) {
  if ($null -eq $Entry) { return }
  if ($Entry.websiteBlocked) {
    Clear-BlockedWebsite $Place ([string]$Entry.blockedReason) ([string]$Entry.blockedHost)
    return
  }
  if ($Entry.closedPlace) {
    Set-PlaceField $Place 'closed' $true
    Set-PlaceField $Place 'websiteChecked' $true
    return
  }
  if ($Entry.fetchFailed) { return }
  if ($Entry.icon -and (Test-MediaSourceUrl ([string]$Entry.iconSource)) -and -not (Test-BlockedHost ([string]$Entry.icon))) {
    Set-PlaceField $Place 'icon' (([string]$Entry.icon) -replace '^http://', 'https://')
    Set-PlaceField $Place 'iconKind' ([string]$Entry.iconKind)
    Set-PlaceField $Place 'iconSource' ([string]$Entry.iconSource)
  }
  $gallery = @($Entry.gallery | Where-Object { (Test-PhotoUrl ([string]$_)) -and -not (Test-BlockedHost ([string]$_)) } | ForEach-Object { ([string]$_) -replace '^http://', 'https://' })
  if ($gallery.Count -gt 0 -and (Test-MediaSourceUrl ([string]$Entry.gallerySource))) {
    Set-PlaceField $Place 'gallery' $gallery
    Set-PlaceField $Place 'gallerySource' ([string]$Entry.gallerySource)
  }
  if ($Entry.websiteChecked) { Set-PlaceField $Place 'websiteChecked' $true }
}

function Invoke-MediaDiscovery {
  param(
    $Places,
    [int]$MaxChecks = 24,
    [int]$MaxGalleryTopUps = 24,
    [string]$MediaPath,
    [string]$CachePath,
    [switch]$SkipNetwork
  )
  Load-MediaCache $CachePath
  $store = Load-MediaStore $MediaPath
  $script:MediaChecked = 0
  $icons = 0
  $galleries = 0

  # Сначала применяем уже найденное и данные Wikidata/OSM.
  $filters = Get-SiteFilters
  foreach ($place in $Places) {
    $id = [string]$place.id
    $hoursText = [string]$place.hours.ru
    if ($hoursText -match '^\s*(closed|закрыто)\s*$' -or ([string]$place.name.ru) -match '(?i)временно\s+закрыт|temporarily\s+closed') {
      Set-PlaceField $place 'closed' $true
    }
    if ($store.ContainsKey($id)) { Apply-MediaEntry $place $store[$id] }
    if ($filters.ClosedPlaceIds -contains $id) { Set-PlaceField $place 'closed' $true }
    if ($place.website -and (Test-BlockedHost ([string]$place.website))) {
      Clear-BlockedWebsite $place 'listed-block' (Get-UrlHost ([string]$place.website))
    }
    if (-not $place.icon -and $place.logo) {
      Set-PlaceField $place 'icon' ([string]$place.logo)
      Set-PlaceField $place 'iconKind' 'logo'
      Set-PlaceField $place 'iconSource' 'https://www.wikidata.org/'
    }
    if ((-not $place.gallery -or @($place.gallery).Count -eq 0) -and $place.image) {
      Set-PlaceField $place 'gallery' @([string]$place.image)
      Set-PlaceField $place 'gallerySource' 'https://www.wikidata.org/'
    }
    if ($place.website -and (Test-MediaSourceUrl ([string]$place.website))) {
      $hostName = Get-UrlHost ([string]$place.website)
      if ($hostName) {
        $rootIcon = "https://$hostName/apple-touch-icon.png"
        $favicon = "https://$hostName/favicon.ico"
        $googleIcon = "https://www.google.com/s2/favicons?sz=128&domain=$hostName"
        Set-PlaceField $place 'iconFallback' $rootIcon
        Set-PlaceField $place 'iconFallback2' $favicon
        Set-PlaceField $place 'iconFallback3' $googleIcon
        if (-not $place.icon) {
          Set-PlaceField $place 'icon' $rootIcon
          Set-PlaceField $place 'iconKind' 'favicon'
          Set-PlaceField $place 'iconSource' ([string]$place.website)
        }
      }
    }
    if ($place.icon) { $icons += 1 }
    if ($place.gallery -and @($place.gallery).Count -gt 0) { $galleries += 1 }
  }

  if (-not $SkipNetwork) {
    $candidates = @($Places | Where-Object {
      $sid = [string]$_.id
      $recentFailure = $false
      if ($store.ContainsKey($sid) -and $store[$sid].fetchFailed) {
        try {
          $age = ($Now - [DateTimeOffset]::Parse([string]$store[$sid].updatedAt)).TotalDays
          if ($age -lt 7) { $recentFailure = $true }
        } catch {}
      }
      (-not $recentFailure) -and $_.website -and (Test-MediaSourceUrl ([string]$_.website)) -and
      -not ($_.websiteChecked -and $_.gallery -and @($_.gallery).Count -ge 4)
    })
    $candidates = @($candidates | Sort-Object {
      $sid = [string]$_.id
      if ($store.ContainsKey($sid) -and $store[$sid].updatedAt) { [string]$store[$sid].updatedAt } else { '' }
    })
    foreach ($place in $candidates) {
      if ($script:MediaChecked -ge $MaxChecks) { break }
      $script:MediaChecked += 1
      $page = Get-MediaPageData ([string]$place.website)
      if ($null -eq $page -or -not $page.ok) {
        $store[[string]$place.id] = [ordered]@{
          fetchFailed = $true
          updatedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
        }
        continue
      }
      $spamReason = [string]$page.spamReason
      if (-not $spamReason -and $page.adult) { $spamReason = 'adult-website' }
      if (-not $spamReason -and $page.parked) { $spamReason = 'parked-domain' }
      if ($spamReason) {
        $badHost = Get-UrlHost ([string]$place.website)
        Clear-BlockedWebsite $place $spamReason $badHost
        $store[[string]$place.id] = [ordered]@{
          websiteBlocked = $true
          blockedReason = $spamReason
          blockedHost = [string]$badHost
          websiteChecked = $true
          icon = ''
          iconKind = ''
          iconSource = ''
          gallery = @()
          gallerySource = ''
          updatedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
        }
        continue
      }
      $closedHit = $false
      foreach ($closedContext in @($page.closedContexts)) {
        if (Test-ClosedContext ([string]$closedContext) ([string]$place.name.ru)) { $closedHit = $true; break }
      }
      if ($closedHit) {
        Set-PlaceField $place 'websiteChecked' $true
        Set-PlaceField $place 'closed' $true
        $closedEntry = if ($store.ContainsKey([string]$place.id)) { $store[[string]$place.id] } else { [ordered]@{} }
        $closedEntry.closedPlace = $true
        $closedEntry.websiteChecked = $true
        $closedEntry.updatedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
        $store[[string]$place.id] = $closedEntry
        continue
      }
      $photos = @($page.gallery)
      foreach ($galleryLink in @($page.galleryLinks | Select-Object -First 3)) {
        $subPage = Get-MediaPageData ([string]$galleryLink)
        if ($null -ne $subPage -and $subPage.ok -and -not $subPage.adult -and -not $subPage.spamReason) { $photos += @($subPage.gallery) }
      }
      $galleryLocation = [string]$place.website
      if ($photos.Count -lt 6) {
        $commons = @(Get-CommonsGallery ([string]$place.commonsCategory) ([string]$place.name.ru))
        if ($commons.Count -gt 0) {
          $photos += $commons
          if (@($page.gallery).Count -eq 0) { $galleryLocation = 'https://commons.wikimedia.org/' }
        }
      }
      $photos = @($photos | Where-Object { Test-PhotoUrl ([string]$_) } | Select-Object -Unique | Select-Object -First 12)
      $entry = [ordered]@{
        icon = [string]$page.icon
        iconKind = if ($page.icon) { 'logo' } else { '' }
        iconSource = if ($page.icon) { [string]$place.website } else { '' }
        gallery = $photos
        gallerySource = if ($photos.Count -gt 0) { $galleryLocation } else { '' }
        websiteChecked = $true
        updatedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
      }
      if ($entry.icon -or @($entry.gallery).Count -gt 0) {
        $store[[string]$place.id] = $entry
        Apply-MediaEntry $place $entry
      }
    }
  }

  if (-not $SkipNetwork) {
    $target = 6
    $topUpPlaces = @($Places | Where-Object {
      (-not $_.gallery -or @($_.gallery).Count -lt $target) -and
      ($_.commonsCategory -or $_.image -or ($_.lat -and $_.lon -and $_.category -in @('walk', 'culture', 'active', 'movie')))
    } | Sort-Object { if ($_.gallery) { @($_.gallery).Count } else { 0 } })
    $topUpChecked = 0
    foreach ($place in $topUpPlaces) {
      if ($topUpChecked -ge $MaxGalleryTopUps) { break }
      $topUpChecked += 1
      $commons = @(Get-CommonsGallery ([string]$place.commonsCategory) ([string]$place.name.ru))
      Start-Sleep -Milliseconds 400
      if ($commons.Count -lt $target -and $place.lat -and $place.lon -and $place.category -in @('walk', 'culture', 'active', 'movie')) {
        $geo = @(Get-CommonsGeoGallery ([double]$place.lat) ([double]$place.lon) 200)
        Start-Sleep -Milliseconds 350
        $commons += $geo
      }
      if ($commons.Count -eq 0) { continue }
      $existing = if ($store.ContainsKey([string]$place.id)) { $store[[string]$place.id] } else { [ordered]@{} }
      $photos = @($existing.gallery) + @($place.gallery) + $commons
      $photos = @($photos | Where-Object { Test-PhotoUrl ([string]$_) } | Select-Object -Unique | Select-Object -First 12)
      $entry = [ordered]@{
        icon = [string]$existing.icon
        iconKind = [string]$existing.iconKind
        iconSource = [string]$existing.iconSource
        gallery = $photos
        gallerySource = if ($existing.gallerySource) { [string]$existing.gallerySource } else { 'https://commons.wikimedia.org/' }
        updatedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
      }
      $store[[string]$place.id] = $entry
      Apply-MediaEntry $place $entry
    }
    $script:MediaChecked += $topUpChecked
  }

  $mediaOut = [ordered]@{ updatedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz'); places = $store }
  try { Save-Json $mediaOut $MediaPath } catch {}
  Save-MediaCache $CachePath
  return [ordered]@{ checked = $script:MediaChecked; icons = $icons; galleries = $galleries; saved = $store.Count }
}
