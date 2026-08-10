[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$EvidencePath,
    [Parameter(Mandatory = $true)][string]$ReviewPath,
    [string]$PluginManifestPath,
    [string]$MarketplacePath
)

$ErrorActionPreference = 'Stop'
$errors = New-Object System.Collections.Generic.List[string]
$requiredGroups = @('scope_uc','flow_rules','screen_fields','api_contracts','interactions','data_model_and_supplementary')

function Read-Json([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label not found: $Path" }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "$Label is invalid JSON: $($_.Exception.Message)" }
}

$evidence = Read-Json $EvidencePath 'Evidence'
$review = Read-Json $ReviewPath 'Review'
$classification = if ($evidence.fast_schema -eq 2 -and $review.fast_schema -eq 2) { 'fast-v2' } else { 'fast-legacy' }
if ($classification -ne 'fast-v2') { $errors.Add('Legacy or missing fast_schema; rerun Maker and Reviewer with fast_schema 2') }

foreach ($group in $requiredGroups) {
    $property = $evidence.evidence_groups.PSObject.Properties[$group]
    if ($null -eq $property -or [string]$property.Value.status -notin @('covered','not_applicable')) {
        $errors.Add("Required evidence group not covered: $group")
    }
}

$requiredSections = @($evidence.output_contract.required_sections | ForEach-Object { [string]$_ })
$coveredSections = @($evidence.coverage.covered_sections | ForEach-Object { [string]$_ })
if ($requiredSections.Count -eq 0) { $errors.Add('Output contract has no required sections') }
foreach ($section in $requiredSections) {
    if ($section -notin $coveredSections) { $errors.Add("Required target section not covered: $section") }
}

$uiDecision = [string]$evidence.ui_risk.decision
if ($uiDecision -notin @('static_pass','playwright_required','not_applicable','blocked_runtime_evidence')) {
    $errors.Add("Invalid UI risk decision: $uiDecision")
} elseif ($uiDecision -eq 'blocked_runtime_evidence') {
    $errors.Add('Material runtime evidence is blocked')
}
if ([string]$evidence.ui_risk.evidence_kind -eq 'simulation' -and [bool]$evidence.ui_risk.runtime_confirmed) {
    $errors.Add('Simulation/Mock evidence cannot be runtime-confirmed')
}

$makerPath = [string]$evidence.staged_document_path
if (-not [System.IO.Path]::IsPathRooted($makerPath)) {
    $makerPath = Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $EvidencePath)) $makerPath
}
if (-not (Test-Path -LiteralPath $makerPath -PathType Leaf)) {
    $errors.Add("Maker artifact not found: $makerPath")
} else {
    $makerHash = (Get-FileHash -LiteralPath $makerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([string]$review.maker_artifact_sha256 -ne $makerHash) { $errors.Add('Reviewer Maker fingerprint is stale') }
}
$evidenceHash = (Get-FileHash -LiteralPath $EvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ([string]$review.evidence_sha256 -ne $evidenceHash) { $errors.Add('Reviewer evidence fingerprint is stale') }

if ([string]$review.verdict -ne 'PASS') { $errors.Add('Reviewer verdict is not PASS') }
if (-not [bool]$review.coverage_complete) { $errors.Add('Reviewer did not confirm coverage') }
if ($null -eq $review.diff_rate -or [double]$review.diff_rate -gt 0.10 -or [double]$review.diff_rate -lt 0) {
    $errors.Add('diff_rate must be between 0 and 0.10')
}

if ($PluginManifestPath -or $MarketplacePath) {
    if (-not $PluginManifestPath -or -not $MarketplacePath) { $errors.Add('Both manifest paths are required for version validation') }
    else {
        $manifest = Read-Json $PluginManifestPath 'Plugin manifest'
        $marketplace = Read-Json $MarketplacePath 'Marketplace manifest'
        $marketVersion = [string]@($marketplace.plugins)[0].version
        if ([string]$manifest.version -ne $marketVersion) { $errors.Add('Plugin manifest and marketplace versions differ') }
    }
}

$valid = ($errors.Count -eq 0)
[ordered]@{
    valid = $valid
    classification = $classification
    delivery_ready = ($valid -and [bool]$review.delivery_ready)
    errors = @($errors)
} | ConvertTo-Json -Depth 5
if (-not $valid) { exit 1 }
