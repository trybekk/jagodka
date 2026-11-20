# Converts a PNG (with alpha) to a 32-bit TGA for WoW: scaled to -Width x -Height (keeps the aspect when one is 0),
# placed top-left on a power-of-two canvas (WoW textures), transparent around. Prints the canvas size so the Lua
# side can crop with SetTexCoord(0, w/W, 0, h/H).
# Usage: powershell -File tools\png2tga.ps1 -In a.png -Out b.tga -Width 128 -Height 0
# Optional -Crop "x,y,w,h": only that part of the PNG (e.g. one piece of a frame painted as a whole).
param([Parameter(Mandatory)][string]$In, [Parameter(Mandatory)][string]$Out, [int]$Width = 0, [int]$Height = 0, [string]$Crop = "")
Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Bitmap]::FromFile((Resolve-Path $In))
if ($Crop -ne "") {
    $c = $Crop.Split(",") | ForEach-Object { [int]$_ }
    $part = $src.Clone((New-Object System.Drawing.Rectangle($c[0], $c[1], $c[2], $c[3])), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $src.Dispose(); $src = $part
}
if ($Width -le 0 -and $Height -le 0) { $Width = $src.Width; $Height = $src.Height }
elseif ($Width -le 0) { $Width = [int][math]::Round($src.Width * $Height / $src.Height) }
elseif ($Height -le 0) { $Height = [int][math]::Round($src.Height * $Width / $src.Width) }
function Pow2([int]$n) { $p = 1; while ($p -lt $n) { $p *= 2 }; return $p }
$W = Pow2 $Width; $H = Pow2 $Height
$bmp = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Transparent)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)))
$g.Dispose(); $src.Dispose()
$rect = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
$data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$bytes = New-Object byte[] ($data.Stride * $H)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
$bmp.UnlockBits($data); $bmp.Dispose()
# TGA header: uncompressed true color, 32 bpp, origin top-left (descriptor 0x28 = 8 alpha bits + top-left)
$hdr = New-Object byte[] 18
$hdr[2] = 2
$hdr[12] = $W -band 0xFF; $hdr[13] = ($W -shr 8) -band 0xFF
$hdr[14] = $H -band 0xFF; $hdr[15] = ($H -shr 8) -band 0xFF
$hdr[16] = 32; $hdr[17] = 0x28
$outPath = [System.IO.Path]::GetFullPath($Out)
$fs = [System.IO.File]::Create($outPath)
$fs.Write($hdr, 0, 18)
# Bitmap memory is BGRA rows top to bottom, the same as the TGA with the top-left origin
for ($y = 0; $y -lt $H; $y++) { $fs.Write($bytes, $y * $data.Stride, $W * 4) }
$fs.Close()
"{0}: {1}x{2} on {3}x{4}" -f [System.IO.Path]::GetFileName($outPath), $Width, $Height, $W, $H
