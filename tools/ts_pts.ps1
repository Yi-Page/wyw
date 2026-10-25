param([Parameter(Mandatory=$true)][string[]]$Path)
# 从 MPEG-TS 分片里读出每个流（视频/音频）的第一个与最后一个 PTS（时钟刻度）。
# PTS 单位 1/90000 秒，33 位计数器（约 26.5 小时绕回一次）。

function Read-TsPts([string]$file) {
  $b = [System.IO.File]::ReadAllBytes($file)
  $len = $b.Length
  $info = @{}
  $offset = 0
  while ($offset -lt $len -and $b[$offset] -ne 0x47) { $offset++ }
  while ($offset + 188 -le $len) {
    if ($b[$offset] -ne 0x47) { $offset++; continue }
    $pusi = ($b[$offset + 1] -band 0x40) -ne 0
    $pidV = (($b[$offset + 1] -band 0x1F) -shl 8) -bor $b[$offset + 2]
    $afc = ($b[$offset + 3] -band 0x30) -shr 4
    $p = $offset + 4
    if ($afc -eq 0 -or $afc -eq 2) { $offset += 188; continue }
    if ($afc -eq 3) { $p += 1 + $b[$offset + 4] }
    if ($pusi -and ($p + 14) -lt ($offset + 188) -and
        $b[$p] -eq 0 -and $b[$p + 1] -eq 0 -and $b[$p + 2] -eq 1) {
      $sid = $b[$p + 3]
      $flags = $b[$p + 7]
      if (($flags -band 0x80) -ne 0) {
        $q = $p + 9
        $ticks = ([int64]($b[$q] -band 0x0E) -shl 29) -bor
                 ([int64]$b[$q + 1] -shl 22) -bor
                 ([int64]($b[$q + 2] -band 0xFE) -shl 14) -bor
                 ([int64]$b[$q + 3] -shl 7) -bor
                 ([int64](($b[$q + 4] -band 0xFE) -shr 1))
        if (-not $info.ContainsKey($pidV)) {
          $info[$pidV] = [pscustomobject]@{ pid = $pidV; sid = $sid; first = $ticks; last = $ticks; n = 1 }
        } else {
          $info[$pidV].last = $ticks
          $info[$pidV].n++
        }
      }
    }
    $offset += 188
  }
  return $info.Values
}

foreach ($f in $Path) {
  if (-not (Test-Path $f)) { Write-Output "缺失: $f"; continue }
  $size = (Get-Item $f).Length
  Write-Output ("== {0}  ({1:N0} 字节)" -f (Split-Path $f -Leaf), $size)
  $rows = Read-TsPts $f
  if (-not $rows) { Write-Output '   没解析到 PTS'; continue }
  foreach ($r in ($rows | Sort-Object pid)) {
    $kind = switch ($r.sid) { 0xE0 { '视频' } 0xC0 { '音频' } default { '流 0x{0:X2}' -f $r.sid } }
    $span = ($r.last - $r.first) / 90000.0
    Write-Output ("   PID {0,5} {1,-10} 首 PTS={2,15} ({3,12:N3} 秒)  尾 PTS={4,15} ({5,12:N3} 秒)  跨度 {6:N2} 秒  包数 {7}" -f `
        $r.pid, $kind, $r.first, ($r.first / 90000.0), $r.last, ($r.last / 90000.0), $span, $r.n)
  }
}
