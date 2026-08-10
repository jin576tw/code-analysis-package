<#
.SYNOPSIS
  Validate the code-analysis-package Claude Code plugin for structural
  consistency and ESP-decoupling.

.DESCRIPTION
  Checks:
   1. .claude-plugin/plugin.json is valid JSON and has a `name`.
   2. .claude-plugin/marketplace.json is valid JSON.
   3. Every agents/*.md has YAML frontmatter with `name` and `description`.
   4. Every skills/<name>/SKILL.md has frontmatter with `name` and `description`.
   5. Every agent `skills:` reference resolves to an existing skill.
   6. No ESP-specific hardcoding leaks outside templates/examples/ and the
      blank profile template.
   6b. Every agent that writes state.json uses the atomic read-modify-write pattern.
   7. Every .kiro/agents/*.json is encoded UTF-8 without BOM (kiro-cli serde_json
      does not tolerate BOMs and fails silently at runtime).
   8. No project-specific hardcoding (checks for ESP/project residue).
  9. verify-report naming and quality gate schema are present; legacy SD-review
    references are fallback-only in active runtime files.

  Exit code 0 = all green; 1 = problems found.

.EXAMPLE
  pwsh ./scripts/validate-plugin.ps1
#>

param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$problems = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Get-Frontmatter([string]$path) {
  $text = Get-Content -Raw -LiteralPath $path
  if ($text -notmatch '(?s)^\uFEFF?---\r?\n(.*?)\r?\n---') { return $null }
  return $Matches[1]
}

Write-Host "== code-analysis-package validation ==" -ForegroundColor Cyan
Write-Host "Root: $Root"

# 1. plugin.json
$pluginJson = Join-Path $Root '.claude-plugin/plugin.json'
if (-not (Test-Path $pluginJson)) {
  $problems.Add("Missing .claude-plugin/plugin.json")
} else {
  try {
    $manifest = Get-Content -Raw $pluginJson | ConvertFrom-Json
    if (-not $manifest.name) { $problems.Add("plugin.json has no 'name'") }
    else { Write-Host "[ok] plugin.json name = $($manifest.name)" -ForegroundColor Green }
  } catch { $problems.Add("plugin.json is not valid JSON: $_") }
}

# 2. marketplace.json
$marketJson = Join-Path $Root '.claude-plugin/marketplace.json'
if (Test-Path $marketJson) {
  try { $marketplace = Get-Content -Raw $marketJson | ConvertFrom-Json
        Write-Host "[ok] marketplace.json is valid JSON" -ForegroundColor Green
        $marketVersion = [string]@($marketplace.plugins)[0].version
        if ($manifest -and [string]$manifest.version -ne $marketVersion) {
          $problems.Add("Version mismatch: plugin.json=$($manifest.version), marketplace.json=$marketVersion")
        } else { Write-Host "[ok] manifest versions synchronized: $marketVersion" -ForegroundColor Green } }
  catch { $problems.Add("marketplace.json is not valid JSON: $_") }
}

# Collect skill names
$skillsDir = Join-Path $Root 'skills'
$skillNames = @{}
if (Test-Path $skillsDir) {
  Get-ChildItem -Directory $skillsDir | ForEach-Object {
    $skillFile = Join-Path $_.FullName 'SKILL.md'
    if (-not (Test-Path $skillFile)) {
      $problems.Add("Skill dir '$($_.Name)' has no SKILL.md")
    } else {
      $fm = Get-Frontmatter $skillFile
      if (-not $fm) { $problems.Add("$($_.Name)/SKILL.md has no frontmatter") }
      else {
        if ($fm -notmatch '(?m)^name:\s*\S') { $problems.Add("$($_.Name)/SKILL.md frontmatter missing name") }
        if ($fm -notmatch '(?m)^description:\s*\S') { $problems.Add("$($_.Name)/SKILL.md frontmatter missing description") }
        if ($fm -match '(?m)^name:\s*(.+?)\s*$') { $skillNames[$Matches[1].Trim()] = $true }
      }
    }
  }
  Write-Host "[ok] skills found: $($skillNames.Keys.Count)" -ForegroundColor Green
}

# 3/5. agents
$agentsDir = Join-Path $Root 'agents'
$agentCount = 0
if (Test-Path $agentsDir) {
  Get-ChildItem -File -Filter *.md $agentsDir | ForEach-Object {
    $agentCount++
    $fm = Get-Frontmatter $_.FullName
    if (-not $fm) { $problems.Add("agents/$($_.Name) has no frontmatter"); return }
    if ($fm -notmatch '(?m)^name:\s*\S') { $problems.Add("agents/$($_.Name) missing name") }
    if ($fm -notmatch '(?m)^description:\s*\S') { $problems.Add("agents/$($_.Name) missing description") }
    if ($fm -match '(?m)^skills:\s*(.+?)\s*$') {
      $refs = $Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
      foreach ($r in $refs) {
        if (-not $skillNames.ContainsKey($r)) {
          $problems.Add("agents/$($_.Name) references unknown skill '$r'")
        }
      }
    }
  }
  Write-Host "[ok] agents found: $agentCount" -ForegroundColor Green
}

# 6b. Atomic-write pattern: agents that update state.json must also read it first
Get-ChildItem -File -Filter *.md $agentsDir | ForEach-Object {
  $content = Get-Content -Raw $_.FullName
  if ($content -match 'state\.json' -and $content -match '(?i)(status\s*=|\.status\b)') {
    if ($content -notmatch '(?i)read whole file|modify in memory') {
      $warnings.Add("agents/$($_.Name) updates state.json but lacks atomic-write instruction (read whole file -> modify in memory -> write back whole)")
    }
  }
}
Write-Host "[ok] atomic-write check done" -ForegroundColor Green

# 7. UTF-8 BOM check for .kiro/agents/*.json
$kiroAgentsDir = Join-Path $Root '.kiro/agents'
if (Test-Path $kiroAgentsDir) {
  $bomBytes = [byte[]](0xEF, 0xBB, 0xBF)
  Get-ChildItem -File -Filter *.json $kiroAgentsDir | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    if ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
      $warnings.Add("UTF-8 BOM detected in .kiro/agents/$($_.Name) — kiro-cli (serde_json) will fail at runtime. Re-save as UTF-8 without BOM.")
    }
  }
  Write-Host "[ok] UTF-8 BOM check done (.kiro/agents/)" -ForegroundColor Green
} else {
  Write-Host "[skip] no .kiro/agents/ directory — UTF-8 BOM check skipped" -ForegroundColor DarkGray
}

# 8. ESP residue (allowed only in templates/examples/ and the blank template tech-stack examples)
$espPattern = 'esp-system|com\.tgl|PremiumConst|reissuebyESP|esp\.job\.'
$hits = Get-ChildItem -Recurse -File $Root -Include *.md,*.json,*.css |
  Where-Object { $_.FullName -notmatch 'templates[\\/]examples' } |
  Select-String -Pattern $espPattern -List
foreach ($h in $hits) {
  $problems.Add("ESP residue in $($h.Path):$($h.LineNumber) -> $($h.Line.Trim())")
}
if (-not $hits) { Write-Host "[ok] no ESP-specific hardcoding outside templates/examples/" -ForegroundColor Green }

# 9. verify-report naming + quality gate schema
$verifyTemplate = Join-Path $Root 'templates/harness/verify-report-template.md'
$oldSdTemplate = Join-Path $Root 'templates/harness/SD-review-template.md'
if (-not (Test-Path $verifyTemplate)) { $problems.Add("Missing templates/harness/verify-report-template.md") }
if (Test-Path $oldSdTemplate) { $problems.Add("Legacy templates/harness/SD-review-template.md should not exist; use verify-report-template.md") }

$qualityAgent = Join-Path $Root 'agents/quality-score.md'
if (-not (Test-Path $qualityAgent)) { $problems.Add("Missing agents/quality-score.md") }

$stateTemplate = Join-Path $Root 'templates/harness/state.json'
if (Test-Path $stateTemplate) {
  $stateText = Get-Content -Raw $stateTemplate
  foreach ($required in @('verify_report_path', 'quality_score', 'score_breakdown', 'score_attempts', 'quality_gate', 'repair_actions', 'gap_report_path')) {
    if ($stateText -notmatch [regex]::Escape($required)) { $problems.Add("state.json missing '$required'") }
  }
  if ($stateText -match 'sd_review_path') { $problems.Add("state.json still uses sd_review_path") }
}

$activeDirs = @('agents', 'commands', 'skills', 'templates') | ForEach-Object { Join-Path $Root $_ } | Where-Object { Test-Path $_ }
$badLegacy = Get-ChildItem -Recurse -File $activeDirs -Include *.md,*.json |
  Where-Object { $_.FullName -notmatch 'CHANGELOG\.md$' } |
  Select-String -Pattern 'SD-review-template|sd_review_path|SD-review\.md' |
  Where-Object {
    $_.Line -match 'SD-review-template|sd_review_path' -or
    ($_.Line -match 'SD-review\.md' -and $_.Line -notmatch '(?i)legacy|fallback')
  }
foreach ($hit in $badLegacy) {
  $problems.Add("Non-fallback SD-review reference in $($hit.Path):$($hit.LineNumber) -> $($hit.Line.Trim())")
}
Write-Host "[ok] verify-report naming / quality schema check done" -ForegroundColor Green

# 10. fast_schema 2 contract surface
$fastRequired = @(
  'skills/fast-analysis/SKILL.md',
  'skills/fast-analysis/references/output-contract.md',
  'agents/fast-analysis-maker.md',
  'agents/fast-analysis-reviewer.md',
  'templates/fast-evidence.template.json',
  'templates/fast-review.template.json',
  'scripts/Get-UiRiskDecision.ps1',
  'scripts/Test-FastAnalysisContract.ps1',
  'scripts/Test-FastContractFixtures.ps1'
)
foreach ($relative in $fastRequired) {
  if (-not (Test-Path -LiteralPath (Join-Path $Root $relative) -PathType Leaf)) {
    $problems.Add("Missing Fast contract file: $relative")
  }
}
foreach ($jsonRelative in @('templates/fast-evidence.template.json','templates/fast-review.template.json')) {
  $jsonPath = Join-Path $Root $jsonRelative
  if (Test-Path -LiteralPath $jsonPath) {
    try {
      $fastJson = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($fastJson.fast_schema -ne 2) { $problems.Add("$jsonRelative must declare fast_schema 2") }
    } catch { $problems.Add("$jsonRelative is invalid JSON: $_") }
  }
}
$startCommand = Join-Path $Root 'commands/start-analysis.md'
if (Test-Path -LiteralPath $startCommand) {
  $startText = Get-Content -LiteralPath $startCommand -Raw -Encoding UTF8
  foreach ($marker in @('fast_schema=2','fast-analysis-maker','fast-analysis-reviewer','diff_rate <= 0.10','fast-legacy')) {
    if (-not $startText.Contains($marker)) { $problems.Add("start-analysis missing Fast contract marker: $marker") }
  }
  if ($startText -match 'Both profiles produce the \*\*same document set') {
    $problems.Add('start-analysis still claims Fast and Full produce the same document set')
  }
}
Write-Host "[ok] fast_schema 2 contract check done" -ForegroundColor Green

# Report
Write-Host ""
if ($warnings.Count) {
  Write-Host "Warnings:" -ForegroundColor Yellow
  $warnings | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Yellow }
}
if ($problems.Count) {
  Write-Host "FAILED ($($problems.Count) problem(s)):" -ForegroundColor Red
  $problems | ForEach-Object { Write-Host "  x $_" -ForegroundColor Red }
  exit 1
}
Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
exit 0
