Add-Type -AssemblyName System.Drawing

function Get-Ranges($bitmap, [bool]$vertical) {
  $limit = if ($vertical) { $bitmap.Width } else { $bitmap.Height }
  $depth = if ($vertical) { $bitmap.Height } else { $bitmap.Width }
  $ranges = @(); $start = -1
  for ($i = 0; $i -lt $limit; $i++) {
    $occupied = $false
    for ($j = 0; $j -lt $depth; $j++) {
      $pixel = if ($vertical) { $bitmap.GetPixel($i, $j) } else { $bitmap.GetPixel($j, $i) }
      if ($pixel.A -gt 8) { $occupied = $true; break }
    }
    if ($occupied -and $start -lt 0) { $start = $i }
    if (-not $occupied -and $start -ge 0) { $ranges += ,@($start, ($i - $start)); $start = -1 }
  }
  if ($start -ge 0) { $ranges += ,@($start, ($limit - $start)) }
  return ,$ranges
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
  $out.Save($outPath); $out.Dispose()
  $colDesc = ($cols | ForEach-Object { "$($_[0])+$($_[1])" }) -join ' '
  $rowDesc = ($rows | ForEach-Object { "$($_[0])+$($_[1])" }) -join ' '
  Write-Output ("{0}: cols[{1}] rows[{2}] -> {3}x{4}" -f (Split-Path $inPath -Leaf), $colDesc, $rowDesc, $totalW, $totalH)
}

Bake 'assets\ui\banner.png' 'assets\ui\panel.png'
Bake 'assets\ui\bigbluebutton_regular.png' 'assets\ui\btn-blue.png'
Bake 'assets\ui\bigbluebutton_pressed.png' 'assets\ui\btn-blue-pressed.png'
Bake 'assets\ui\bigredbutton_regular.png' 'assets\ui\btn-red.png'
Bake 'assets\ui\bigredbutton_pressed.png' 'assets\ui\btn-red-pressed.png'
Bake 'assets\ui\smallbluesquarebutton_regular.png' 'assets\ui\btn-sq-blue.png'
Bake 'assets\ui\smallbluesquarebutton_pressed.png' 'assets\ui\btn-sq-blue-pressed.png'
Bake 'assets\ui\smallredsquarebutton_regular.png' 'assets\ui\btn-sq-red.png'
Bake 'assets\ui\smallredsquarebutton_pressed.png' 'assets\ui\btn-sq-red-pressed.png'
Bake 'assets\ui\bigbar-base.png' 'assets\ui\bar-base.png'
