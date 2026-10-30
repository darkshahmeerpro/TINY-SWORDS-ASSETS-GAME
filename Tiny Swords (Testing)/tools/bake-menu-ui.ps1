Add-Type -AssemblyName System.Drawing

function Get-Ranges($bitmap, [bool]$vertical) {
  $limit = if ($vertical) { $bitmap.Width } else { $bitmap.Height }
  $depth = if ($vertical) { $bitmap.Height } else { $bitmap.Width }
  $ranges = New-Object System.Collections.Generic.List[object]
  $start = -1
  for ($i = 0; $i -lt $limit; $i++) {
    $occupied = $false
    for ($j = 0; $j -lt $depth; $j++) {
      $pixel = if ($vertical) { $bitmap.GetPixel($i, $j) } else { $bitmap.GetPixel($j, $i) }
      if ($pixel.A -gt 8) { $occupied = $true; break }
    }
    if ($occupied -and $start -lt 0) { $start = $i }
    if (-not $occupied -and $start -ge 0) {
      $ranges.Add(@($start, ($i - $start)))
      $start = -1
    }
  }
  if ($start -ge 0) { $ranges.Add(@($start, ($limit - $start))) }
  return $ranges
}

function Bake($inPath, $outPath) {
  $bmp = [Drawing.Bitmap]::FromFile((Resolve-Path $inPath))
  $cols = Get-Ranges $bmp $true
  $rows = Get-Ranges $bmp $false
  $totalW = 0; foreach ($c in $cols) { $totalW += $c[1] }
  $totalH = 0; foreach ($r in $rows) { $totalH += $r[1] }
  $out = New-Object Drawing.Bitmap $totalW, $totalH
  $g = [Drawing.Graphics]::FromImage($out)
  $y = 0
  foreach ($r in $rows) {
    $x = 0
    foreach ($c in $cols) {
      $srcRect = New-Object Drawing.Rectangle $c[0], $r[0], $c[1], $r[1]
      $dstRect = New-Object Drawing.Rectangle $x, $y, $c[1], $r[1]
      $g.DrawImage($bmp, $dstRect, $srcRect, [Drawing.GraphicsUnit]::Pixel)
      $x += $c[1]
    }
    $y += $r[1]
  }
  $g.Dispose(); $bmp.Dispose()
  $out.Save((Join-Path (Get-Location) $outPath)); $out.Dispose()
  $sliceT = $rows[0][1]; $sliceR = $cols[-1][1]; $sliceB = $rows[-1][1]; $sliceL = $cols[0][1]
  Write-Output ("{0} -> {1}x{2}  slice:{3} {4} {5} {6}" -f (Split-Path $inPath -Leaf), $totalW, $totalH, $sliceT, $sliceR, $sliceB, $sliceL)
}

function SliceRibbonRow($inPath, $rowIndex, $outPath) {
  $bmp = [Drawing.Bitmap]::FromFile((Resolve-Path $inPath))
  $cols = Get-Ranges $bmp $true
  $rows = Get-Ranges $bmp $false
  $r = $rows[$rowIndex]
  $totalW = 0; foreach ($c in $cols) { $totalW += $c[1] }
  $out = New-Object Drawing.Bitmap $totalW, $r[1]
  $g = [Drawing.Graphics]::FromImage($out)
  $x = 0
  foreach ($c in $cols) {
    $srcRect = New-Object Drawing.Rectangle $c[0], $r[0], $c[1], $r[1]
    $dstRect = New-Object Drawing.Rectangle $x, 0, $c[1], $r[1]
    $g.DrawImage($bmp, $dstRect, $srcRect, [Drawing.GraphicsUnit]::Pixel)
    $x += $c[1]
  }
  $g.Dispose(); $bmp.Dispose()
  $out.Save((Join-Path (Get-Location) $outPath)); $out.Dispose()
  Write-Output ("ribbon row {0} -> {1}  {2}x{3}  ends:{4}/{5}" -f $rowIndex, $outPath, $totalW, $r[1], $cols[0][1], $cols[-1][1])
}

function SliceSwordRow($inPath, $rowIndex, $outPath) {
  SliceRibbonRow $inPath $rowIndex $outPath
}

Bake 'assets\ui\woodtable.png' 'assets\ui\panel-wood.png'
Bake 'assets\ui\paper.png' 'assets\ui\panel-paper.png'
Bake 'assets\ui\paper-special.png' 'assets\ui\panel-paper-special.png'

$colors = @('teal','red','yellow','purple','grey')
for ($i = 0; $i -lt 5; $i++) {
  SliceRibbonRow 'assets\ui\bigribbons.png' $i ("assets\ui\title-ribbon-$($colors[$i]).png")
  SliceSwordRow 'assets\ui\swords.png' $i ("assets\ui\title-sword-$($colors[$i]).png")
}
