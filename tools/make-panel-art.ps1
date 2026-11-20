# Draws the Forest Berry panel pieces (rounded corners, edges, the label tab) as PNGs, in the colors of the
# user's art: plum fill, a bronze rim with a thin warm-gold highlight, a dark inner line. Pieces join exactly
# because they are drawn here from the same numbers. Output: -OutDir (PNG, convert with png2tga.ps1).
param([Parameter(Mandatory)][string]$OutDir, [int]$Scale = 4)
Add-Type -AssemblyName System.Drawing
$S = $Scale                      # drawn at 4x, the converter scales down (smooth edges)
$R = 7 * $S                      # corner radius
$fill = [System.Drawing.Color]::FromArgb(222, 22, 15, 28)
$rim = [System.Drawing.Color]::FromArgb(255, 120, 86, 44)
$hi = [System.Drawing.Color]::FromArgb(255, 214, 172, 96)
$dark = [System.Drawing.Color]::FromArgb(200, 8, 5, 10)
$tabFill = [System.Drawing.Color]::FromArgb(240, 46, 24, 66)
$tabTop = [System.Drawing.Color]::FromArgb(240, 78, 40, 112)

function RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure(); return $p
}
# The whole panel drawn once on a 64x64 (x S) canvas; the pieces are cut from it
$N = 64 * $S
$bmp = New-Object System.Drawing.Bitmap($N, $N, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)
$o = 0.5 * $S
$g.FillPath((New-Object System.Drawing.SolidBrush($fill)), (RoundRect $o $o ($N - 2 * $o) ($N - 2 * $o) $R))
$g.DrawPath((New-Object System.Drawing.Pen($rim, (1.6 * $S))), (RoundRect (0.8 * $S) (0.8 * $S) ($N - 1.6 * $S) ($N - 1.6 * $S) $R))
$g.DrawPath((New-Object System.Drawing.Pen($dark, (1 * $S))), (RoundRect (2.3 * $S) (2.3 * $S) ($N - 4.6 * $S) ($N - 4.6 * $S) ($R - 1.5 * $S)))
# a warm highlight along the top rim only
$clip = New-Object System.Drawing.RectangleF(0, 0, $N, (3 * $S))
$g.SetClip($clip)
$g.DrawPath((New-Object System.Drawing.Pen($hi, (0.8 * $S))), (RoundRect (0.8 * $S) (0.8 * $S) ($N - 1.6 * $S) ($N - 1.6 * $S) $R))
$g.ResetClip()
$g.Dispose()
function Cut($name, $x, $y, $w, $h) {
    $part = $bmp.Clone((New-Object System.Drawing.Rectangle(($x * $S), ($y * $S), ($w * $S), ($h * $S))), $bmp.PixelFormat)
    $part.Save((Join-Path $OutDir "$name.png")); $part.Dispose()
}
Cut "panel_tl" 0 0 16 16; Cut "panel_tr" 48 0 16 16; Cut "panel_bl" 0 48 16 16; Cut "panel_br" 48 48 16 16
Cut "panel_top" 16 0 16 16; Cut "panel_bottom" 16 48 16 16; Cut "panel_left" 0 16 16 16; Cut "panel_right" 48 16 16 16
$bmp.Dispose()

# The label tab: rounded top corners, open at the bottom (it sits on the panel's top edge), 64 x 24 (x S)
$W = 64 * $S; $H = 24 * $S
$t = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($t)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)
$shape = RoundRect $o $o ($W - 2 * $o) ($H + 10 * $S) (6 * $S)
$grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(0, 0, $W, $H)), $tabTop, $tabFill, 90)
$g.FillPath($grad, $shape)
$g.DrawPath((New-Object System.Drawing.Pen($rim, (1.6 * $S))), (RoundRect (0.8 * $S) (0.8 * $S) ($W - 1.6 * $S) ($H + 10 * $S) (6 * $S)))
$g.SetClip((New-Object System.Drawing.RectangleF(0, 0, $W, (3 * $S))))
$g.DrawPath((New-Object System.Drawing.Pen($hi, (0.8 * $S))), (RoundRect (0.8 * $S) (0.8 * $S) ($W - 1.6 * $S) ($H + 10 * $S) (6 * $S)))
$g.ResetClip(); $g.Dispose()
function CutT($name, $x, $w) {
    $part = $t.Clone((New-Object System.Drawing.Rectangle(($x * $S), 0, ($w * $S), $H)), $t.PixelFormat)
    $part.Save((Join-Path $OutDir "$name.png")); $part.Dispose()
}
CutT "label_l" 0 16; CutT "label_m" 24 16; CutT "label_r" 48 16
$t.Dispose()
"done"
