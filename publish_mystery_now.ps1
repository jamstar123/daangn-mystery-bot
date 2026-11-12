param(
    [Parameter(Mandatory=$true)][string]$Slug,
    [string]$Board = "free",
    [string]$ManuscriptFile = "",
    [string]$Prefix = ""
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = [System.IO.File]::ReadAllLines("$baseDir\.env", [System.Text.Encoding]::UTF8)
$cookie = ($envFile | Where-Object { $_ -match "^DAANGN_COOKIE=" }).Split('=', 2)[1].Trim('"').Trim("'")
if (-not $cookie.Contains("session-token=") -and $cookie.StartsWith("eyJ")) {
    $cookie = "__Secure-authjs.session-token=$cookie"
}

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
foreach ($pair in ($cookie -split ';')) {
    $kv = $pair.Trim().Split('=', 2)
    if ($kv.Count -eq 2) {
        $c = New-Object System.Net.Cookie($kv[0].Trim(), $kv[1].Trim(), "/", "cafe.daangn.com")
        $session.Cookies.Add($c)
    }
}

$queueDir = "$baseDir\manuscripts\queue"
$pubDir = "$baseDir\manuscripts\published"
New-Item -ItemType Directory -Force -Path $pubDir | Out-Null
$referencedImages = @()
if (-not $ManuscriptFile) {
    $filter = if ($Prefix) { "$Prefix*.txt" } else { "*.txt" }
    $first = Get-ChildItem "$queueDir\$filter" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
    if (-not $first) {
        Write-Host "[대기열 비어 있음] 발행할 원고($filter)가 없습니다."
        exit 0
    }
    $ManuscriptFile = $first.FullName
}

$lines = [System.IO.File]::ReadAllLines($ManuscriptFile, [System.Text.Encoding]::UTF8)
$titleLine = $lines[0].Trim()
if (-not $titleLine.StartsWith("제목:")) {
    throw "원고 첫 줄은 '제목: ...' 형식이어야 합니다."
}
$title = $titleLine.Substring(3).Trim()

$boardOverride = ""
foreach ($rawLine in ($lines | Select-Object -Skip 1)) {
    $t = $rawLine.Trim()
    if (-not $t -or $t -eq "## 본문") { continue }
    if ($t.StartsWith("게시판:")) {
        $boardOverride = $t.Substring(4).Trim()
        break
    }
    break
}
$targetBoard = if ($boardOverride) { $boardOverride } else { $Board }

# 카페 페이지에서 게시판 ID 및 최신 액션 ID 조회
$cafeHtmlResp = Invoke-WebRequest -Uri "https://cafe.daangn.com/$Slug" -WebSession $session -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" -UseBasicParsing
$cafeDecoded = [System.Text.Encoding]::UTF8.GetString($cafeHtmlResp.RawContentStream.ToArray()) -replace '\\"', '"' -replace '\\\\', '\'
$catPattern = [regex]'\{\s*"id"\s*:\s*(\d+)\s*,\s*"type"\s*:\s*"([^"]+)"\s*,\s*"category"\s*:\s*"([^"]+)"'
$boards = $catPattern.Matches($cafeDecoded)
$boardCategoryId = 0
if ($targetBoard -match '^\d+$') {
    $boardCategoryId = [int]$targetBoard
} else {
    foreach ($b in $boards) {
        if ($b.Groups[3].Value -match [regex]::Escape($targetBoard) -or $targetBoard -match [regex]::Escape($b.Groups[3].Value)) {
            $boardCategoryId = [int]$b.Groups[1].Value
            break
        }
    }
    if ($boardCategoryId -eq 0) {
        foreach ($b in $boards) {
            if ($b.Groups[2].Value -eq "default") {
                $boardCategoryId = [int]$b.Groups[1].Value
                break
            }
        }
    }
}
if ($boardCategoryId -eq 0 -and $boards.Count -gt 0) {
    $boardCategoryId = [int]$boards[0].Groups[1].Value
}

function Upload-DaangnImage([byte[]]$imgBytes) {
    $mimeType = "image/jpeg"
    $imgActionPayload = '[{"contentType":"image/jpeg","width":1080,"height":720}]'
    $imgHeaders = @{
        "Accept" = "text/x-component"
        "Next-Action" = "405f02288844f7079cb0daafe72ecf1e55f48835a3"
        "Origin" = "https://cafe.daangn.com"
        "Referer" = "https://cafe.daangn.com/$Slug/posts/new"
    }
    $rAction = Invoke-WebRequest -Uri "https://cafe.daangn.com/$Slug/posts/new" `
        -Method Post `
        -WebSession $session `
        -Headers $imgHeaders `
        -ContentType "text/plain;charset=UTF-8" `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($imgActionPayload)) `
        -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" `
        -UseBasicParsing

    $actionText = [System.Text.Encoding]::UTF8.GetString($rAction.RawContentStream.ToArray())
    $uploadUrlMatch = [regex]::Match($actionText, '"uploadUrl"\s*:\s*"([^"]+)"')
    $imageIdMatch = [regex]::Match($actionText, '"image"\s*:\s*\{\s*"id"\s*:\s*"([^"]+)"')
    if (-not $uploadUrlMatch.Success -or -not $imageIdMatch.Success) {
        throw "Failed to parse uploadUrl or imageId from response"
    }
    $uploadUrl = $uploadUrlMatch.Groups[1].Value -replace '\\u0026', '&'
    $imageId = $imageIdMatch.Groups[1].Value

    $putHeaders = @{ "x-amz-meta-id" = $imageId }
    $null = Invoke-WebRequest -Uri $uploadUrl `
        -Method Put `
        -Headers $putHeaders `
        -ContentType $mimeType `
        -Body $imgBytes `
        -UseBasicParsing

    return [string]$imageId
}

$blocks = @()
$msDir = Split-Path -Parent $ManuscriptFile
foreach ($rawLine in ($lines | Select-Object -Skip 1)) {
    $trimmed = $rawLine.Trim()
    if (-not $trimmed -or $trimmed -eq "## 본문" -or $trimmed.StartsWith("게시판:")) {
        continue
    }
    if ($trimmed -match '^\[이미지\s*:\s*([^\]]+)\]$') {
        $imgRef = $Matches[1].Trim()
        if ($imgRef.StartsWith("http")) {
            $imgResp = Invoke-WebRequest -Uri $imgRef -UserAgent "Mozilla/5.0" -UseBasicParsing
            $imgBytes = [byte[]]$imgResp.RawContentStream.ToArray()
        } else {
            $imgPath = Join-Path $msDir $imgRef
            $imgBytes = [System.IO.File]::ReadAllBytes($imgPath)
            $referencedImages += $imgPath
        }
        $upId = Upload-DaangnImage $imgBytes
        $blocks += @{
            id = [guid]::NewGuid().ToString()
            type = "image"
            imageAttribute = @{ imageId = $upId }
        }
        continue
    }
    $blocks += @{
        id = [guid]::NewGuid().ToString()
        type = "paragraph"
        contents = @(
            @{
                id = [guid]::NewGuid().ToString()
                type = "text"
                text = [string]$trimmed
                attributes = @{ bold = $false; italic = $false; underline = $false; strikethrough = $false }
            }
        )
    }
}

$innerObj = @{
    cafeSlug = $Slug
    title = [string]$title.Substring(0, [Math]::Min(48, $title.Length))
    blockContent = @{ blocks = $blocks }
    visibility = "public"
    searchable = $true
    boardCategoryId = [int]$boardCategoryId
}
$innerJson = $innerObj | ConvertTo-Json -Depth 12 -Compress
$createPayload = "[$innerJson]"

$createHeaders = @{
    "Accept" = "text/x-component"
    "Next-Action" = "402f5a7c2fc9904da9e01dae909ef0f2cd05e52ae9"
    "Origin" = "https://cafe.daangn.com"
    "Referer" = "https://cafe.daangn.com/$Slug/posts/new"
}

$rCreate = Invoke-WebRequest -Uri "https://cafe.daangn.com/$Slug/posts/new" `
    -Method Post `
    -WebSession $session `
    -Headers $createHeaders `
    -ContentType "text/plain;charset=UTF-8" `
    -Body ([System.Text.Encoding]::UTF8.GetBytes($createPayload)) `
    -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" `
    -UseBasicParsing

$respText = [System.Text.Encoding]::UTF8.GetString($rCreate.RawContentStream.ToArray())
$slugMatch = [regex]::Match($respText, '"postSlug"\s*:\s*"([^"]+)"')
if ($slugMatch.Success) {
    $finalUrl = "https://cafe.daangn.com/$Slug/posts/" + $slugMatch.Groups[1].Value
} else {
    $redirMatch = [regex]::Match($respText, 'NEXT_REDIRECT;[^;]*;([^;]+);')
    if ($redirMatch.Success) {
        $finalUrl = "https://cafe.daangn.com" + $redirMatch.Groups[1].Value
    } else {
        $finalUrl = "https://cafe.daangn.com/$Slug/posts"
    }
}

Write-Output "SUCCESS_URL: $finalUrl"

if ((Split-Path -Parent $ManuscriptFile) -eq $queueDir) {
    Move-Item -Path $ManuscriptFile -Destination (Join-Path $pubDir (Split-Path -Leaf $ManuscriptFile)) -Force
    foreach ($rp in $referencedImages) {
        if (Test-Path $rp) {
            Move-Item -Path $rp -Destination (Join-Path $pubDir (Split-Path -Leaf $rp)) -Force
        }
    }
}
