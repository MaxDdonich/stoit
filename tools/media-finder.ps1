# СТОИТ — поиск логотипов и фотографий на официальных сайтах.
# Подключается из collect.ps1.

$script:MediaCache = @{}
$script:MediaCacheLoaded = $false
$script:MediaChecked = 0

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
    if ($clean.Count -ge 6) { break }
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
    if ($links.Count -ge 3) { break }
  }
  return $links
}

function Get-CommonsGallery([string]$Category, [string]$Name) {
  $params = ''
  if ($Category) {
    $params = 'generator=categorymembers&gcmtitle=' + [Uri]::EscapeDataString("Category:$Category") + '&gcmtype=file&gcmlimit=10'
  } elseif ($Name) {
    $params = 'generator=search&gsrsearch=' + [Uri]::EscapeDataString("$Name Москва") + '&gsrnamespace=6&gsrlimit=8'
  } else {
    return @()
  }
  $url = "https://commons.wikimedia.org/w/api.php?action=query&format=json&prop=imageinfo&iiprop=url%7Cmime&iiurlwidth=1400&$params"
  $raw = Get-RemoteText $url
  if (-not $raw) { return @() }
  try { $doc = $raw | ConvertFrom-Json } catch { return @() }
  if ($null -eq $doc.query -or $null -eq $doc.query.pages) { return @() }
  $photos = @()
  foreach ($prop in $doc.query.pages.PSObject.Properties) {
    $page = $prop.Value
    if (-not $page.imageinfo -or -not $page.imageinfo[0]) { continue }
    $info = $page.imageinfo[0]
    $mime = [string]$info.mime
    if ($mime -notmatch '^image/(jpeg|png|webp)$') { continue }
    $url = [string]$info.thumburl
    if (-not $url) { $url = [string]$info.url }
    if (-not $url) { continue }
    $title = [string]$page.title
    if ($title -match '(?i)logo|icon|map|plan|scheme|coat|flag|qr|diagram|poster|banner|stamp|symbol') { continue }
    if (-not $photos.Contains($url)) { $photos += $url }
    if ($photos.Count -ge 8) { break }
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
    $entry = [pscustomobject]@{ fetchedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz'); ok = $false; icon = ''; gallery = @(); galleryLinks = @() }
    $script:MediaCache[$Url] = $entry
    return $entry
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

function Apply-MediaEntry($Place, $Entry) {
  if ($null -eq $Entry) { return }
  if ($Entry.icon -and (Test-MediaSourceUrl ([string]$Entry.iconSource))) {
    Set-PlaceField $Place 'icon' (([string]$Entry.icon) -replace '^http://', 'https://')
    Set-PlaceField $Place 'iconKind' ([string]$Entry.iconKind)
    Set-PlaceField $Place 'iconSource' ([string]$Entry.iconSource)
  }
  $gallery = @($Entry.gallery | Where-Object { Test-PhotoUrl ([string]$_) } | ForEach-Object { ([string]$_) -replace '^http://', 'https://' })
  if ($gallery.Count -gt 0 -and (Test-MediaSourceUrl ([string]$Entry.gallerySource))) {
    Set-PlaceField $Place 'gallery' $gallery
    Set-PlaceField $Place 'gallerySource' ([string]$Entry.gallerySource)
  }
}

function Invoke-MediaDiscovery {
  param(
    $Places,
    [int]$MaxChecks = 24,
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
  foreach ($place in $Places) {
    $id = [string]$place.id
    if ($store.ContainsKey($id)) { Apply-MediaEntry $place $store[$id] }
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
    foreach ($place in $Places) {
      if ($script:MediaChecked -ge $MaxChecks) { break }
      if (-not $place.website) { continue }
      if (-not (Test-MediaSourceUrl ([string]$place.website))) { continue }
      if ($place.gallery -and @($place.gallery).Count -ge 4) { continue }
      $script:MediaChecked += 1
      $page = Get-MediaPageData ([string]$place.website)
      if ($null -eq $page -or -not $page.ok) { continue }
      $photos = @($page.gallery)
      foreach ($galleryLink in @($page.galleryLinks | Select-Object -First 2)) {
        $subPage = Get-MediaPageData ([string]$galleryLink)
        if ($null -ne $subPage -and $subPage.ok) { $photos += @($subPage.gallery) }
      }
      $galleryLocation = [string]$place.website
      if ($photos.Count -lt 4) {
        $commons = @(Get-CommonsGallery ([string]$place.commonsCategory) ([string]$place.name.ru))
        if ($commons.Count -gt 0) {
          $photos += $commons
          $galleryLocation = 'https://commons.wikimedia.org/'
        }
      }
      $photos = @($photos | Where-Object { Test-PhotoUrl ([string]$_) } | Select-Object -Unique | Select-Object -First 12)
      $entry = [ordered]@{
        icon = [string]$page.icon
        iconKind = if ($page.icon) { 'logo' } else { '' }
        iconSource = if ($page.icon) { [string]$place.website } else { '' }
        gallery = $photos
        gallerySource = if ($photos.Count -gt 0) { $galleryLocation } else { '' }
        updatedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
      }
      if ($entry.icon -or @($entry.gallery).Count -gt 0) {
        $store[[string]$place.id] = $entry
        Apply-MediaEntry $place $entry
      }
    }
  }

  if (-not $SkipNetwork) {
    $commonsChecked = 0
    $commonsPlaces = @($Places | Where-Object {
      $_.commonsCategory -and (-not $_.gallery -or @($_.gallery).Count -lt 3)
    } | Sort-Object { if ($_.gallery) { @($_.gallery).Count } else { 0 } })
    foreach ($place in $commonsPlaces) {
      if ($commonsChecked -ge 8) { break }
      $commonsChecked += 1
      $commons = @(Get-CommonsGallery ([string]$place.commonsCategory) ([string]$place.name.ru))
      Start-Sleep -Milliseconds 650
      if ($commons.Count -eq 0) { continue }
      $existing = if ($store.ContainsKey([string]$place.id)) { $store[[string]$place.id] } else { [ordered]@{} }
      $photos = @($existing.gallery) + @($place.gallery) + $commons
      $photos = @($photos | Where-Object { Test-PhotoUrl ([string]$_) } | Select-Object -Unique | Select-Object -First 12)
      $entry = [ordered]@{
        icon = [string]$existing.icon
        iconKind = [string]$existing.iconKind
        iconSource = [string]$existing.iconSource
        gallery = $photos
        gallerySource = 'https://commons.wikimedia.org/'
        updatedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
      }
      $store[[string]$place.id] = $entry
      Apply-MediaEntry $place $entry
    }
    $script:MediaChecked += $commonsChecked
  }

  $mediaOut = [ordered]@{ updatedAt = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz'); places = $store }
  try { Save-Json $mediaOut $MediaPath } catch {}
  Save-MediaCache $CachePath
  return [ordered]@{ checked = $script:MediaChecked; icons = $icons; galleries = $galleries; saved = $store.Count }
}
