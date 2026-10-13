# 从 logo（PNG）生成各平台的**应用图标**。
#
# 为什么不用现成的包：`flutter_launcher_icons` 要联网下载依赖；
# 这个脚本只依赖 Windows 自带的 .NET（System.Drawing），离线也能跑，而且**可重跑**。
#
# 用法（在仓库根目录）：
#     pwsh -File tool/make_icons.ps1
# 想换图：改下面 $Source 或传参：
#     pwsh -File tool/make_icons.ps1 -Source assets/新logo.png
#
# 生成的东西：
#   - Android：android/app/src/main/res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png
#     （48 / 72 / 96 / 144 / 192，就是各密度下的启动图标）
#   - Windows：windows/runner/resources/app_icon.ico
#     （16 / 32 / 48 / 64 / 128 / 256，**BMP(DIB) 格式**的条目 ——
#      不用 PNG 压缩条目，因为 rc.exe 对 PNG 条目的支持不稳）
#
# 注意：源图最好是**正方形**（正方形以外的会按短边居中裁成正方形）。

param(
  [string]$Source = 'assets/bbb_log.png'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot   # 仓库根（脚本在 tool/ 下）
$srcPath = Join-Path $root $Source
if (-not (Test-Path $srcPath)) { throw "找不到源图：$srcPath" }

$src = [System.Drawing.Image]::FromFile($srcPath)

# 先按短边裁成正方形（图标必须是正方形）
$side = [Math]::Min($src.Width, $src.Height)
$cropX = [int](($src.Width - $side) / 2)
$cropY = [int](($src.Height - $side) / 2)

function New-Square([int]$size) {
  $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $dest = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
    $srcRect = New-Object System.Drawing.Rectangle($cropX, $cropY, $side, $side)
    $g.DrawImage($script:src, $dest, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
  } finally { $g.Dispose() }
  return $bmp
}

function Save-Png($bmp, [string]$path) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
}

# ---------------- Android ----------------
$densities = @{ 'mdpi' = 48; 'hdpi' = 72; 'xhdpi' = 96; 'xxhdpi' = 144; 'xxxhdpi' = 192 }
foreach ($d in $densities.Keys) {
  $size = $densities[$d]
  $bmp = New-Square $size
  $out = Join-Path $root "android/app/src/main/res/mipmap-$d/ic_launcher.png"
  Save-Png $bmp $out
  $bmp.Dispose()
  "Android  $d ($size)  -> $out"
}

# ---------------- Windows .ico ----------------
# 一个 32bpp 的 BMP(DIB) 条目：BITMAPINFOHEADER + 像素(倒序 BGRA) + AND 掩码(全 0)
function Get-IcoEntryBytes($bmp) {
  $w = $bmp.Width
  $h = $bmp.Height
  $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
  $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $stride = $data.Stride
  $bytes = New-Object byte[] ($stride * $h)
  [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
  $bmp.UnlockBits($data)

  $ms = New-Object System.IO.MemoryStream
  $bw = New-Object System.IO.BinaryWriter($ms)

  # BITMAPINFOHEADER
  $bw.Write([uint32]40)          # biSize
  $bw.Write([int32]$w)           # biWidth
  $bw.Write([int32]($h * 2))     # biHeight = XOR + AND
  $bw.Write([uint16]1)           # biPlanes
  $bw.Write([uint16]32)          # biBitCount
  $bw.Write([uint32]0)           # biCompression = BI_RGB
  $bw.Write([uint32]($w * $h * 4))
  $bw.Write([int32]0); $bw.Write([int32]0)
  $bw.Write([uint32]0); $bw.Write([uint32]0)

  # 像素：DIB 是**倒序**（最后一行在前）
  for ($y = $h - 1; $y -ge 0; $y--) {
    $bw.Write($bytes, $y * $stride, $w * 4)
  }

  # AND 掩码：1bpp，每行 4 字节对齐，全 0 = 不透明（透明度靠 32bpp 的 alpha）
  $maskRow = [int]([Math]::Floor(($w + 31) / 32) * 4)
  $mask = New-Object byte[] ($maskRow * $h)
  $bw.Write($mask, 0, $mask.Length)

  $bw.Flush()
  return $ms.ToArray()
}

$icoSizes = @(16, 32, 48, 64, 128, 256)
$entries = @()
foreach ($s in $icoSizes) {
  $bmp = New-Square $s
  $entries += [pscustomobject]@{ Size = $s; Bytes = (Get-IcoEntryBytes $bmp) }
  $bmp.Dispose()
}

$icoPath = Join-Path $root 'windows/runner/resources/app_icon.ico'
$fs = [System.IO.File]::Create($icoPath)
$bw = New-Object System.IO.BinaryWriter($fs)
try {
  # ICONDIR
  $bw.Write([uint16]0)                # reserved
  $bw.Write([uint16]1)                # type = icon
  $bw.Write([uint16]$entries.Count)   # 条目数
  $offset = 6 + 16 * $entries.Count
  foreach ($e in $entries) {
    $bw.Write([byte]($(if ($e.Size -ge 256) { 0 } else { $e.Size })))  # 宽
    $bw.Write([byte]($(if ($e.Size -ge 256) { 0 } else { $e.Size })))  # 高
    $bw.Write([byte]0)                # 调色板数
    $bw.Write([byte]0)                # reserved
    $bw.Write([uint16]1)              # planes
    $bw.Write([uint16]32)             # bpp
    $bw.Write([uint32]$e.Bytes.Length)
    $bw.Write([uint32]$offset)
    $offset += $e.Bytes.Length
  }
  foreach ($e in $entries) { $bw.Write($e.Bytes, 0, $e.Bytes.Length) }
} finally {
  $bw.Dispose(); $fs.Dispose()
}
"Windows  ico ($($icoSizes -join '/'))  -> $icoPath"

$src.Dispose()
"完成。改完图标记得**重新 build**（图标是编进 exe / APK 的，热重载不生效）。"
