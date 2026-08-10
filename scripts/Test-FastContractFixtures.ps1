[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$tempBase = [System.IO.Path]::GetTempPath().TrimEnd('\')
$testRoot = Join-Path $tempBase ('fast-contract-' + [Guid]::NewGuid().ToString('N'))
$resolvedRoot = [System.IO.Path]::GetFullPath($testRoot)
$safePrefix = [System.IO.Path]::GetFullPath($tempBase).TrimEnd('\') + '\'
if (-not $resolvedRoot.StartsWith($safePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture root' }
New-Item -ItemType Directory -Path $resolvedRoot -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$validator = Join-Path $Root 'scripts\Test-FastAnalysisContract.ps1'
$classifier = Join-Path $Root 'scripts\Get-UiRiskDecision.ps1'

function Write-Json([string]$Path, $Value) {
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 12), $utf8)
}
function Invoke-Contract([string]$Evidence, [string]$Review, [string]$Plugin, [string]$Market) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validator -EvidencePath $Evidence -ReviewPath $Review -PluginManifestPath $Plugin -MarketplacePath $Market 2>&1
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}
function Copy-Object($Value) {
    return ($Value | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
}

try {
    $makerPath = Join-Path $resolvedRoot 'FAST-SA.md'
    [System.IO.File]::WriteAllText($makerPath, '# Integrated target document', $utf8)
    $evidencePath = Join-Path $resolvedRoot 'evidence.json'
    $reviewPath = Join-Path $resolvedRoot 'review.json'
    $pluginPath = Join-Path $resolvedRoot 'plugin.json'
    $marketPath = Join-Path $resolvedRoot 'marketplace.json'
    Write-Json $pluginPath ([ordered]@{ version = '0.11.0' })
    Write-Json $marketPath ([ordered]@{ plugins = @([ordered]@{ version = '0.11.0' }) })

    $groups = [ordered]@{}
    foreach ($group in @('scope_uc','flow_rules','screen_fields','api_contracts','interactions','data_model_and_supplementary')) {
        $groups[$group] = [ordered]@{ status = 'covered'; items = @([ordered]@{ source = 'src/example'; locator = 'L1' }) }
    }
    $baseEvidence = [ordered]@{
        fast_schema = 2; analysis_profile = 'fast'; artifact_class = 'fast-v2'; run_id = 'fixture'
        staged_document_path = 'FAST-SA.md'; delivery_ready = $false
        output_contract = [ordered]@{ required_sections = @('scope','flow','ui','api','sequence','data'); document_role = 'integrated-target-analysis' }
        coverage = [ordered]@{ covered_sections = @('scope','flow','ui','api','sequence','data') }
        ui_risk = [ordered]@{ decision = 'static_pass'; signals = @(); evidence_kind = 'static'; runtime_confirmed = $false }
        evidence_groups = $groups
    }
    Write-Json $evidencePath $baseEvidence
    $baseReview = [ordered]@{
        fast_schema = 2; classification = 'fast-v2'; verdict = 'PASS'
        maker_artifact_sha256 = (Get-FileHash -LiteralPath $makerPath -Algorithm SHA256).Hash.ToLowerInvariant()
        evidence_sha256 = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
        reviewed_at = [DateTime]::UtcNow.ToString('o'); review_round = 1; diff_rate = 0.05
        coverage_complete = $true; ui_risk_accepted = $true; findings = @(); delivery_ready = $true
    }
    Write-Json $reviewPath $baseReview
    $valid = Invoke-Contract $evidencePath $reviewPath $pluginPath $marketPath
    if ($valid.ExitCode -ne 0) { throw "Valid contract rejected: $($valid.Output)" }

    $missing = Copy-Object $baseEvidence; $missing.coverage = [ordered]@{ covered_sections = @('scope','flow') }
    Write-Json $evidencePath $missing; $baseReview.evidence_sha256 = (Get-FileHash $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant(); Write-Json $reviewPath $baseReview
    if ((Invoke-Contract $evidencePath $reviewPath $pluginPath $marketPath).ExitCode -eq 0) { throw 'Missing SA coverage was accepted' }

    Write-Json $evidencePath $baseEvidence; $baseReview.evidence_sha256 = (Get-FileHash $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant(); $baseReview.diff_rate = 0.11; Write-Json $reviewPath $baseReview
    if ((Invoke-Contract $evidencePath $reviewPath $pluginPath $marketPath).ExitCode -eq 0) { throw 'diff_rate > 0.10 was accepted' }

    $baseReview.diff_rate = 0.05; $baseReview.maker_artifact_sha256 = ('0' * 64); Write-Json $reviewPath $baseReview
    if ((Invoke-Contract $evidencePath $reviewPath $pluginPath $marketPath).ExitCode -eq 0) { throw 'Stale reviewer fingerprint was accepted' }

    $legacy = Copy-Object $baseEvidence; $legacy.fast_schema = 1; Write-Json $evidencePath $legacy
    $baseReview.fast_schema = 1; $baseReview.maker_artifact_sha256 = (Get-FileHash $makerPath -Algorithm SHA256).Hash.ToLowerInvariant(); $baseReview.evidence_sha256 = (Get-FileHash $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant(); Write-Json $reviewPath $baseReview
    if ((Invoke-Contract $evidencePath $reviewPath $pluginPath $marketPath).ExitCode -eq 0) { throw 'Legacy fast schema was delivery-ready' }

    Write-Json $marketPath ([ordered]@{ plugins = @([ordered]@{ version = '0.10.9' }) })
    if ((Invoke-Contract $evidencePath $reviewPath $pluginPath $marketPath).ExitCode -eq 0) { throw 'Version mismatch was accepted' }

    $server = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $classifier -EntryType ui -SourceText '<form method="post">server rendered</form>' -EvidenceKind static | ConvertFrom-Json
    if ($server.decision -ne 'static_pass') { throw 'Server-rendered UI did not static-pass' }
    foreach ($signalText in @('<script src="a.js"></script>','fetch("/api")','Content-Disposition: attachment','position: sticky')) {
        $risk = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $classifier -EntryType ui -SourceText $signalText -RuntimeAvailable -EvidenceKind live | ConvertFrom-Json
        if ($risk.decision -ne 'playwright_required') { throw "Risk signal did not require Playwright: $signalText" }
    }
    $blocked = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $classifier -EntryType ui -SourceText 'runtime-only dialog' -CriticalRuntime -EvidenceKind none | ConvertFrom-Json
    if ($blocked.decision -ne 'blocked_runtime_evidence') { throw 'Missing critical runtime environment was not blocked' }
    $mock = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $classifier -EntryType ui -SourceText 'ajax' -RuntimeAvailable -EvidenceKind simulation | ConvertFrom-Json
    if ($mock.runtime_confirmed -or -not $mock.simulation_only) { throw 'Mock was treated as runtime-confirmed' }

    [ordered]@{
        valid_evidence_and_pass = 'pass'; missing_coverage = 'rejected'; diff_rate_gt_010 = 'rejected'
        stale_fingerprint = 'rejected'; legacy_schema = 'not-delivery-ready'; version_mismatch = 'rejected'
        ui_server_static = 'static_pass'; ui_risks = 'playwright_required'; runtime_missing = 'blocked'; mock = 'simulation-only'
    } | ConvertTo-Json
} finally {
    if (Test-Path -LiteralPath $resolvedRoot) { Remove-Item -LiteralPath $resolvedRoot -Recurse -Force }
}
