# check-links.ps1 -- verify every relative markdown link and every docs.json navigation entry
# resolves to a real file in this docs repo. Pure ASCII. Read-only.
#
# Usage:
#   powershell -NoProfile -File tools/probes/check-links.ps1
#   powershell -NoProfile -File tools/probes/check-links.ps1 -RepoRoot C:\path\to\clover-doc
#
# Exit code: 0 = all links resolve, 1 = at least one dangling target.

param(
    [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$root = (Resolve-Path -LiteralPath $RepoRoot).Path

$script:checked = 0
$script:problems = New-Object System.Collections.ArrayList

function Test-Target([string]$BaseDir, [string]$Target, [string]$Where) {
    $script:checked++
    $path = $Target.Split('#')[0]
    if ($path -eq '') { return $true }               # pure anchor
    if ($path -match '^[a-zA-Z][a-zA-Z0-9+.-]*:') { return $true }  # scheme (http:, mailto:, ...)
    if ($path.StartsWith('/')) {
        $abs = Join-Path $root $path.TrimStart('/')
    }
    else {
        $abs = Join-Path $BaseDir $path
    }
    $abs = $abs.Replace('/', '\')
    if (Test-Path -LiteralPath $abs) { return $true }
    if (Test-Path -LiteralPath ($abs + '.md')) { return $true }
    [void]$script:problems.Add(("FAIL dangling target: {0} -> {1}" -f $Where, $Target))
    return $false
}

# ---- 1. relative markdown links inside every .md page ----
$mdFiles = Get-ChildItem -LiteralPath $root -Recurse -Filter '*.md' -File |
    Where-Object { $_.FullName -notmatch '\\(node_modules|\.mintlify|\.ai-tmp|\.git)\\' }

foreach ($f in $mdFiles) {
    $rel = $f.FullName.Substring($root.Length).TrimStart('\')
    $lines = [System.IO.File]::ReadAllLines($f.FullName)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($m in [regex]::Matches($lines[$i], '\]\(([^)\s]+)\)')) {
            $t = $m.Groups[1].Value
            if ($t -notmatch '\.md(#|$)') { continue }   # page links only; images / anchors skipped
            [void](Test-Target -BaseDir $f.DirectoryName -Target $t -Where ("{0}:{1}" -f $rel, ($i + 1)))
        }
    }
}

# ---- 2. docs.json navigation entries (pages ids / internal hrefs) ----
$docsJson = Join-Path $root 'docs.json'
if (-not (Test-Path -LiteralPath $docsJson)) {
    [void]$script:problems.Add('FAIL docs.json not found')
}
else {
    $cfg = Get-Content -LiteralPath $docsJson -Raw -Encoding UTF8 | ConvertFrom-Json

    # Recursively walk the whole navigation tree: every string inside a `pages` array is a page id,
    # every `href` starting with "/" is an in-site link. Everything else is traversed opaquely so
    # that `tabs` / `groups` / nested page groups are all reached.
    function Walk-Node($node, [bool]$inPages) {
        if ($null -eq $node) { return }
        if ($node -is [string]) {
            if ($inPages) {
                [void](Test-Target -BaseDir $root -Target ($node + '.md') -Where 'docs.json:pages')
            }
            return
        }
        if ($node -is [System.Collections.IEnumerable]) {
            foreach ($child in $node) { Walk-Node $child $inPages }
            return
        }
        foreach ($prop in $node.PSObject.Properties) {
            if ($prop.Name -eq 'pages') { Walk-Node $prop.Value $true }
            elseif ($prop.Name -eq 'href') {
                $h = [string]$prop.Value
                if ($h.StartsWith('/')) { [void](Test-Target -BaseDir $root -Target ($h + '.md') -Where 'docs.json:href') }
            }
            else { Walk-Node $prop.Value $false }
        }
    }
    Walk-Node $cfg.navigation $false
}

foreach ($p in $script:problems) { Write-Output $p }
Write-Output ("checked={0} dangling={1}" -f $script:checked, $script:problems.Count)
if ($script:problems.Count -gt 0) { Write-Output 'RESULT=FAIL'; exit 1 }
Write-Output 'RESULT=OK'
exit 0
