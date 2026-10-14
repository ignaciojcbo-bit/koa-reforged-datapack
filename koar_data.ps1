# KOA Reforged data pack builder (koar_data.ps1) - 0.2 (2026-10-09)
# Rebuilds data\patch_0.pak with the game's official tools in modding\
# (pakfileunpacker.exe / pakfilebuilder.exe), adding KOA Reforged's data to
# YOUR game's own files. Nothing from other mods is used.
#
#   build : unpack the original patch_0, add our data to its files, rebuild it
#           with pakfilebuilder -c, check the result, install it.
#   undo  : put the original patch_0.pak back (only if ours is still installed).
#   status: say what's installed.
#
# What "our data" is (data\ folder):
#   koar_items.bin  - the outfit items (Transmog looks): new item records. They
#                     are added to the item records (134225858_ksmt.batch), the
#                     item list (simtype_init.bin) and the file index
#                     (assetinfos.bin), and each gets its two small .bundle files.
#   koar_stacks.txt - stack sizes: record, offset, old value, new value. Each
#                     old value is checked first; a value that differs (a game
#                     update changed it) is left alone and reported.
# Our entries go into the files of the pak you have, so a game update or
# another pak mod's changes are kept (another mod's patch_0 counts as your
# original: install it first, then build).
#
# Safety rules:
#   - The original is identified by its SHA-256. If data\patch_0.pak is neither
#     the original we saved nor the pak we built, the game (or another mod)
#     changed it: that file becomes the new original.
#   - The new pak is built next to the old one and only swapped in after the
#     official unpacker lists every original file plus ours.
#   - If any of our item ids is already taken in your files, nothing is built.
#   - Every step is logged to koar_data_log.txt.
param([Parameter(Mandatory = $true)][ValidateSet("build", "undo", "status")][string]$Mode)

$ErrorActionPreference = "Stop"
$here     = Split-Path -Parent $MyInvocation.MyCommand.Path        # modding\KoarData
$game     = (Resolve-Path (Join-Path $here "..\..")).Path
$tools    = Join-Path $game "modding"
$pak      = Join-Path $game "data\patch_0.pak"
$pak0     = Join-Path $game "data\initial_0.pak"
$backup   = Join-Path $here "patch_0.original.pak"
$state    = Join-Path $here "koar_data_state.txt"
$work     = Join-Path $here "work"
$dataDir  = Join-Path $here "data"
$logF     = Join-Path $here "koar_data_log.txt"
$unpacker = Join-Path $tools "pakfileunpacker.exe"
$builder  = Join-Path $tools "pakfilebuilder.exe"
$KSMT     = "134225858_ksmt.batch"

function Log($s) { Write-Host $s; Add-Content -Path $logF -Value $s }
function Fail($s) { Log ("STOPPED: " + $s); exit 1 }
function Hash($p) { (Get-FileHash -Path $p -Algorithm SHA256).Hash }
function Read-State {
  $st = @{}
  if (Test-Path $state) { foreach ($l in Get-Content $state) { $k, $v = $l -split "=", 2; $st[$k] = $v } }
  return $st
}
function Write-State($st) { Set-Content -Path $state -Value @($st.Keys | ForEach-Object { $_ + "=" + $st[$_] }) }
function List-Pak($p, $out) {
  & $unpacker $p list > $out 2>&1
  return @(Get-Content $out | Where-Object { $_ -ne "" })
}
function U32($b, $o) { return [BitConverter]::ToUInt32($b, [int]$o) }
function W32($ms, $v) { $x = [BitConverter]::GetBytes([uint32]$v); $ms.Write($x, 0, 4) }

# ------------------------------------------------ our data into the unpacked files
# returns the number of files added to the pak
function Add-KoarData($unp) {
  $added = 0
  $d = [System.IO.File]::ReadAllBytes((Join-Path $dataDir "koar_items.bin"))
  $k = U32 $d 0
  $ids = New-Object 'uint32[]' $k; $sizes = New-Object 'uint32[]' $k; $starts = New-Object 'int[]' $k
  $p = 4 + 8 * $k
  for ($i = 0; $i -lt $k; $i++) { $ids[$i] = U32 $d (4 + 8 * $i); $sizes[$i] = U32 $d (8 + 8 * $i); $starts[$i] = $p; $p += $sizes[$i] }
  if ($p -ne $d.Length) { Fail "data\koar_items.bin is damaged." }
  Log ("our items: " + $k)

  # simtype_init.bin: the item list (ids, then the name hash of each; ours are equal)
  $siP = Join-Path $unp "simtype_init.bin"
  if (-not (Test-Path $siP)) {
    & $unpacker $pak0 unpack $unp simtype_init.bin | Out-Null
    if (-not (Test-Path $siP)) { Fail "simtype_init.bin not found in patch_0 or initial_0." }
    $added++
    Log "simtype_init.bin taken from initial_0.pak"
  }
  $si = [System.IO.File]::ReadAllBytes($siP)
  $n = U32 $si 4
  if ($si.Length -ne 8 + 8 * $n) { Fail "simtype_init.bin has an unexpected layout." }
  $taken = New-Object 'System.Collections.Generic.HashSet[uint32]'
  for ($i = 0; $i -lt 2 * $n; $i++) { [void]$taken.Add((U32 $si (8 + 4 * $i))) }
  $clash = @($ids | Where-Object { $taken.Contains($_) })
  if ($clash.Count -gt 0) { Fail ("" + $clash.Count + " of our item ids are already used in your game files (e.g. " + (($clash | Select-Object -First 3) -join ", ") + "). Was patch_0 built by another tool that already added them?") }
  $ms = New-Object System.IO.MemoryStream
  $ms.Write($si, 0, 4); W32 $ms ($n + $k)
  $ms.Write($si, 8, 4 * $n); foreach ($x in $ids) { W32 $ms $x }
  $ms.Write($si, 8 + 4 * $n, 4 * $n); foreach ($x in $ids) { W32 $ms $x }
  [System.IO.File]::WriteAllBytes($siP, $ms.ToArray())

  # the item records batch
  $kP = Join-Path $unp $KSMT
  if (-not (Test-Path $kP)) { Fail ($KSMT + " not found in patch_0.") }
  $KB = [System.IO.File]::ReadAllBytes($kP)
  $kn = U32 $KB 0
  $at = 4 + 8 * $kn; $recIds = New-Object 'System.Collections.Generic.HashSet[uint32]'
  $recSz = @{}
  for ($i = 0; $i -lt $kn; $i++) { $rid = U32 $KB (4 + 8 * $i); [void]$recIds.Add($rid); $recSz[$rid] = $at; $at += U32 $KB (8 + 8 * $i) }
  if ($at -ne $KB.Length) { Fail ($KSMT + " has an unexpected layout.") }
  $clash = @($ids | Where-Object { $recIds.Contains($_) })
  if ($clash.Count -gt 0) { Fail ("item records already present: " + ($clash -join ", ")) }
  $ms = New-Object System.IO.MemoryStream
  W32 $ms ($kn + $k)
  $ms.Write($KB, 4, 8 * $kn)
  $ms.Write($d, 4, 8 * $k)
  $ms.Write($KB, 4 + 8 * $kn, $KB.Length - 4 - 8 * $kn)
  $ms.Write($d, 4 + 8 * $k, $d.Length - 4 - 8 * $k)
  $M = $ms.ToArray()
  # stack sizes: records of the game sit 8*k bytes further on in the new file
  $sp = Join-Path $dataDir "koar_stacks.txt"; $ok = 0; $skip = 0
  if (Test-Path $sp) {
    foreach ($l in Get-Content $sp) {
      if ($l -match '^\s*#' -or $l.Trim() -eq "") { continue }
      $f = $l.Trim() -split '\s+'
      $rid = [uint32]$f[0]
      if (-not $recSz.ContainsKey($rid)) { $skip++; continue }
      $a = $recSz[$rid] + 8 * $k + [int]$f[1]
      if ((U32 $M $a) -ne [uint32]$f[2]) { $skip++; Log ("  stack size left alone (your game has a different value): " + $f[4]); continue }
      [BitConverter]::GetBytes([uint32]$f[3]).CopyTo($M, $a); $ok++
    }
  }
  [System.IO.File]::WriteAllBytes($kP, $M)
  Log ("item records: " + $kn + " + " + $k + "; stack sizes raised: " + $ok + ($(if ($skip) { ", left alone: " + $skip } else { "" })))

  # assetinfos.bin: the file index, sorted by file id. Three entries per item:
  # <id>.simtype_bxml (148), <id>.bundle under 0xF0000000+id and
  # <0x20000000+id>.bundle under 0x20000000+id (156).
  $aP = Join-Path $unp "assetinfos.bin"
  if (-not (Test-Path $aP)) { Fail "assetinfos.bin not found in patch_0." }
  $AI = [System.IO.File]::ReadAllBytes($aP)
  $ac = U32 $AI 0
  $fids = New-Object 'uint32[]' $ac; $fst = New-Object 'int[]' ($ac + 1)
  $p = 8
  for ($i = 0; $i -lt $ac; $i++) { $fids[$i] = U32 $AI $p; $fst[$i] = $p; $p += 6 + $AI[$p + 5] }
  $fst[$ac] = $p
  $new = New-Object 'System.Collections.Generic.List[object]'
  foreach ($x in $ids) {
    $new.Add(@([uint32]$x, 148, ("" + $x + ".simtype_bxml")))
    $new.Add(@([uint32]([uint32]4026531840 -bor $x), 156, ("" + $x + ".bundle")))
    $b2 = [uint32]([uint32]0x20000000 -bor $x)
    $new.Add(@($b2, 156, ("" + $b2 + ".bundle")))
  }
  $sorted = @($new | Sort-Object { [uint32]$_[0] })
  $ms = New-Object System.IO.MemoryStream
  W32 $ms ($ac + $sorted.Count); $ms.Write($AI, 4, 4)
  $from = 0
  foreach ($e in $sorted) {
    $pos = [Array]::BinarySearch($fids, [uint32]$e[0])
    if ($pos -ge 0) { Fail ("file id already in the index: " + $e[0] + " (" + $e[2] + ")") }
    $pos = -bnot $pos
    if ($pos -gt $from) { $ms.Write($AI, $fst[$from], $fst[$pos] - $fst[$from]); $from = $pos }
    W32 $ms $e[0]; $ms.WriteByte([byte]$e[1]); $nb = [System.Text.Encoding]::ASCII.GetBytes($e[2]); $ms.WriteByte([byte]$nb.Length); $ms.Write($nb, 0, $nb.Length)
  }
  $ms.Write($AI, $fst[$from], $AI.Length - $fst[$from])     # remaining entries and the tail
  $AI2 = $ms.ToArray()
  # check: count and order
  $c2 = U32 $AI2 0; $p = 8; $prev = -1
  for ($i = 0; $i -lt $c2; $i++) { $v = [int64](U32 $AI2 $p); if ($v -le $prev) { Fail "file index check failed (order)." }; $prev = $v; $p += 6 + $AI2[$p + 5] }
  if ($AI2.Length - $p -ne $AI.Length - $fst[$ac]) { Fail "file index check failed (size)." }
  [System.IO.File]::WriteAllBytes($aP, $AI2)
  Log ("file index: " + $ac + " + " + $sorted.Count + " entries")

  # bundles: <id>.bundle (2 at 8, male model at 16, female at 20, 4112 at 24)
  # and <0x20000000+id>.bundle (23 fixed bytes)
  $b2b = [byte[]](0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0x45,0xAB,0x1A,0,0,0,0)
  for ($i = 0; $i -lt $k; $i++) {
    $b = New-Object byte[] 30
    [BitConverter]::GetBytes([uint32]2).CopyTo($b, 8)
    [Array]::Copy($d, $starts[$i] + 252, $b, 16, 8)
    [BitConverter]::GetBytes([uint32]4112).CopyTo($b, 24)
    [System.IO.File]::WriteAllBytes((Join-Path $unp ("" + $ids[$i] + ".bundle")), $b)
    [System.IO.File]::WriteAllBytes((Join-Path $unp ("" + ([uint32]0x20000000 -bor $ids[$i]) + ".bundle")), $b2b)
    $added += 2
  }
  return $added
}

Log ("==== koar_data 0.2 " + $Mode + " " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " ====")
if (Get-Process -Name "koa" -ErrorAction SilentlyContinue) { Fail "the game is running. Close it first." }
foreach ($t in @($unpacker, $builder, $pak)) { if (-not (Test-Path $t)) { Fail ("missing: " + $t) } }

$st = Read-State
$cur = Hash $pak
$isOurs = $st.ContainsKey("built_sha") -and $st["built_sha"] -eq $cur
$isOrig = $st.ContainsKey("orig_sha") -and $st["orig_sha"] -eq $cur

if ($Mode -eq "status") {
  if ($isOurs) { Log ("installed: the KOA Reforged data pack (built " + $st["built_at"] + ")") }
  elseif ($isOrig) { Log "installed: the original patch_0.pak" }
  else { Log "installed: a patch_0.pak this tool doesn't know (the game's own, an update, or another mod's)" }
  exit 0
}

if ($Mode -eq "undo") {
  if (-not $isOurs) { Fail "data\patch_0.pak isn't the pak this tool built (the game was updated, or another mod changed it); nothing to undo. Steam's 'Verify integrity of game files' restores the official file." }
  if (-not (Test-Path $backup) -or (Hash $backup) -ne $st["orig_sha"]) { Fail "the saved original is missing or damaged. Use Steam's 'Verify integrity of game files'." }
  Copy-Item $backup $pak -Force
  if ((Hash $pak) -ne $st["orig_sha"]) { Fail "restore check failed. Use Steam's 'Verify integrity of game files'." }
  Log "UNDO DONE: the original patch_0.pak is back."
  exit 0
}

# ---------------------------------------------------------------- build
foreach ($t in @((Join-Path $dataDir "koar_items.bin"))) { if (-not (Test-Path $t)) { Fail ("missing: " + $t) } }
# 1. the original to build from
if ($isOurs) {
  if (-not (Test-Path $backup) -or (Hash $backup) -ne $st["orig_sha"]) { Fail "our pak is installed but the saved original is missing or damaged. Use Steam's 'Verify integrity of game files', then build again." }
  Log "our pak is installed: building again from the saved original"
} else {
  if ($st.ContainsKey("orig_sha") -and -not $isOrig) { Log "data\patch_0.pak changed since the last build (game update or another mod): using it as the new original" }
  Copy-Item $pak $backup -Force
  $st["orig_sha"] = $cur
  $st["orig_size"] = (Get-Item $pak).Length
  Write-State $st
  Log ("saved the original: " + $st["orig_size"] + " bytes, sha256 " + $cur)
}

# 2. unpack it
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
$unp = Join-Path $work "files"
New-Item -ItemType Directory -Path $unp | Out-Null
$origList = List-Pak $backup (Join-Path $work "original_list.txt")
Log ("original lists " + $origList.Count + " files; unpacking...")
& $unpacker $backup unpack $unp | Out-Null
$files = @(Get-ChildItem $unp -File)
Log ("unpacked " + $files.Count + " files")
if ($files.Count -ne $origList.Count) { Fail ("unpacked " + $files.Count + " files but the list has " + $origList.Count + " (duplicate names?)") }

# 3. our data
$added = Add-KoarData $unp
Log ("our data added (" + $added + " new files)")

# 4. rebuild next to the old one
$listFile = Join-Path $work "build_list.txt"
Set-Content -Path $listFile -Value @(Get-ChildItem $unp -File | ForEach-Object { $_.FullName })
$newPak = Join-Path $work "patch_0.new.pak"
Log "building (this takes a while)..."
& $builder -c $listFile $newPak | Out-Null
if (-not (Test-Path $newPak)) { Fail "the builder made no pak." }

# 5. check: the official unpacker lists every original file, plus ours
$newList = List-Pak $newPak (Join-Path $work "new_list.txt")
$missing = @($origList | Where-Object { $newList -notcontains $_ })
Log ("new pak: " + (Get-Item $newPak).Length + " bytes, lists " + $newList.Count + " files, missing " + $missing.Count)
if ($missing.Count -gt 0) { Fail ("the new pak lacks " + $missing.Count + " original files, e.g. " + (($missing | Select-Object -First 3) -join ", ")) }
if ($newList.Count -ne $origList.Count + $added) { Fail "the new pak has an unexpected number of files." }

# 6. install
Copy-Item $newPak $pak -Force
$st["built_sha"] = Hash $pak
$st["built_at"] = (Get-Date -Format "yyyy-MM-dd HH:mm")
Write-State $st
Remove-Item $work -Recurse -Force
Log "BUILD DONE: the KOA Reforged data pack is installed. Undo any time with 3_undo.bat."
