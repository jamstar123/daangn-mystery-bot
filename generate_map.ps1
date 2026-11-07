# generate_map.ps1
# 심플한 흑백 손그림 펜 스케치 스타일(문 열리는 반원 호 + 손글씨 단답형 라벨) 약도 생성기
param(
    [string]$OutputPath = "$PSScriptRoot\manuscripts\queue\001_room_map.png"
)

Add-Type -AssemblyName System.Drawing

$w = 520
$h = 500
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
$g.Clear([System.Drawing.Color]::White)

$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$fontFile = "$PSScriptRoot\fonts\NanumPenScript-Regular.ttf"
$pfc.AddFontFile($fontFile)
$fontHand = New-Object System.Drawing.Font($pfc.Families[0], 34, [System.Drawing.FontStyle]::Regular)
$fontHandSm = New-Object System.Drawing.Font($pfc.Families[0], 27, [System.Drawing.FontStyle]::Regular)

$penMain = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(20, 20, 20), 4.2)
$penMain.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$penMain.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$penMain.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round

$penSub = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(30, 30, 30), 3.2)
$penSub.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$penSub.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

$brushBlack = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(20, 20, 20))

function Draw-HandLine($x1, $y1, $x2, $y2, $mxOffset = 2, $myOffset = -2, $pen = $penMain) {
    $mx = ($x1 + $x2) / 2.0 + $mxOffset
    $my = ($y1 + $y2) / 2.0 + $myOffset
    $pts = @(
        (New-Object System.Drawing.PointF($x1, $y1)),
        (New-Object System.Drawing.PointF($mx, $my)),
        (New-Object System.Drawing.PointF($x2, $y2))
    )
    $g.DrawCurve($pen, $pts, 0.35)
}

# 외벽
Draw-HandLine 35 30 35 465 -2 0
Draw-HandLine 32 465 485 467 0 2
Draw-HandLine 482 30 485 468 2 0
Draw-HandLine 35 32 485 30 0 -2

# 우측 상단: 벽 뒤 빈공간
Draw-HandLine 235 32 237 115 1 0
Draw-HandLine 235 115 484 113 0 2
$g.DrawString("벽 뒤 빈공간", $fontHandSm, $brushBlack, 285, 52)

# 옷장(못질) 박스 및 양문 열리는 반원 호
Draw-HandLine 237 115 239 195 -1 0
Draw-HandLine 236 195 484 193 0 2
$g.DrawString("옷장(못질)", $fontHand, $brushBlack, 292, 132)

Draw-HandLine 242 195 245 258 1 0 $penSub
Draw-HandLine 478 193 475 258 -1 0 $penSub
$arcPts1 = @(
    (New-Object System.Drawing.PointF(245, 258)),
    (New-Object System.Drawing.PointF(315, 248)),
    (New-Object System.Drawing.PointF(360, 195))
)
$g.DrawCurve($penSub, $arcPts1, 0.4)
$arcPts2 = @(
    (New-Object System.Drawing.PointF(360, 195)),
    (New-Object System.Drawing.PointF(410, 248)),
    (New-Object System.Drawing.PointF(475, 258))
)
$g.DrawCurve($penSub, $arcPts2, 0.4)

# 큰방/작은방 사이 가벽 및 문 열리는 호
Draw-HandLine 235 32 238 195 1 0
Draw-HandLine 155 198 238 196 0 -1 $penSub
$doorArc = @(
    (New-Object System.Drawing.PointF(155, 198)),
    (New-Object System.Drawing.PointF(172, 255)),
    (New-Object System.Drawing.PointF(236, 278))
)
$g.DrawCurve($penSub, $doorArc, 0.45)
Draw-HandLine 238 282 240 465 -1 0

# 침대
Draw-HandLine 36 285 165 283 0 -2
Draw-HandLine 165 283 168 465 2 0
$g.DrawString("침대", $fontHand, $brushBlack, 68, 350)

# 현관
Draw-HandLine 75 32 77 105 1 0 $penSub
$entArc = @(
    (New-Object System.Drawing.PointF(77, 105)),
    (New-Object System.Drawing.PointF(125, 92)),
    (New-Object System.Drawing.PointF(150, 32))
)
$g.DrawCurve($penSub, $entArc, 0.4)
$g.DrawString("현관", $fontHandSm, $brushBlack, 85, 38)

# 행거 및 작은방
Draw-HandLine 345 315 483 313 0 -1
Draw-HandLine 345 315 348 465 -1 0
$g.DrawString("행거", $fontHand, $brushBlack, 382, 368)
$g.DrawString("작은방", $fontHandSm, $brushBlack, 252, 365)

$bmp.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose(); $pfc.Dispose()
Write-Output "Saved hand-drawn map image to $OutputPath"
