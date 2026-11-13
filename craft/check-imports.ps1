param([string]$Root)
# craft/check-imports.ps1 — package gate (build 12: libFLAC / libsndfile / libsox imported ogg.dll, which the package did not contain, so the
# MLT sox module silently failed to load). Exit 1 when any import is missing.
# Every .exe/.dll under $Root: imported DLLs that exist neither next to it, in $Root\bin, nor in System32 (api-ms-*/ext-ms-* = API sets).
# Reads import tables only (no DLL is loaded).
$bin = Join-Path $Root "bin"
$sys = Join-Path $env:SystemRoot "System32"
$have = @{}
Get-ChildItem $Root -Recurse -Include *.dll, *.exe -File | ForEach-Object { $have[$_.Name.ToLowerInvariant()] = $true }
function Imports([string]$f) {
    try { $b = [IO.File]::ReadAllBytes($f) } catch { return @() }
    if ($b.Length -lt 0x40 -or $b[0] -ne 0x4D -or $b[1] -ne 0x5A) { return @() }
    $pe = [BitConverter]::ToUInt32($b, 0x3C); if ($pe + 0x100 -gt $b.Length) { return @() }
    $opt = $pe + 24; $magic = [BitConverter]::ToUInt16($b, $opt)
    $dd = if ($magic -eq 0x20B) { $opt + 112 } else { $opt + 96 }
    $impRva = [BitConverter]::ToUInt32($b, $dd + 8); if ($impRva -eq 0) { return @() }
    $nSec = [BitConverter]::ToUInt16($b, $pe + 6); $sec = $opt + [BitConverter]::ToUInt16($b, $pe + 20)
    $secs = for ($i = 0; $i -lt $nSec; $i++) { $s = $sec + 40 * $i; ,@([BitConverter]::ToUInt32($b, $s + 12), [Math]::Max([BitConverter]::ToUInt32($b, $s + 8), [BitConverter]::ToUInt32($b, $s + 16)), [BitConverter]::ToUInt32($b, $s + 20)) }
    function Off($rva) { foreach ($s in $secs) { if ($rva -ge $s[0] -and $rva -lt $s[0] + $s[1]) { return [int]($rva - $s[0] + $s[2]) } }; return -1 }
    $d = Off $impRva; if ($d -lt 0) { return @() }
    $names = @()
    while ($d + 20 -le $b.Length) {
        $nr = [BitConverter]::ToUInt32($b, $d + 12); if ($nr -eq 0) { break }
        $no = Off $nr; if ($no -lt 0) { break }
        $j = $no; while ($j -lt $b.Length -and $b[$j] -ne 0) { $j++ }
        $names += [Text.Encoding]::ASCII.GetString($b, $no, $j - $no)
        $d += 20
    }
    return $names
}
$missing = @{}
Get-ChildItem $Root -Recurse -Include *.dll, *.exe -File | ForEach-Object {
    foreach ($n in (Imports $_.FullName)) {
        $l = $n.ToLowerInvariant()
        if ($l -like 'api-ms-*' -or $l -like 'ext-ms-*') { continue }
        if ($have[$l] -or (Test-Path (Join-Path $sys $n))) { continue }
        if (-not $missing[$n]) { $missing[$n] = @() }
        $missing[$n] += $_.FullName.Substring($Root.Length + 1)
    }
}
foreach ($k in $missing.Keys | Sort-Object) { "{0}  <- {1}" -f $k, (($missing[$k] | Select-Object -First 4) -join ', ') + $(if ($missing[$k].Count -gt 4) { " (+$($missing[$k].Count - 4))" } else { "" }) }
"missing imports: $($missing.Count)"
if ($missing.Count -gt 0) { exit 1 }
exit 0
