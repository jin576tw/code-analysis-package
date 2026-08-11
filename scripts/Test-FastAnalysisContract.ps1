[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$EvidencePath,
    [Parameter(Mandatory = $true)][string]$ReviewPath,
    [Parameter(Mandatory = $true)][string]$OutputContractPath,
    [string]$PluginManifestPath,
    [string]$MarketplacePath
)

$ErrorActionPreference = 'Stop'
$errors = New-Object System.Collections.Generic.List[string]
$allowedCollectors = @('dependencies','symbols_data','data_model','functions','execution_flow','business_rules','ui_behavior','api_contract','system_design')

function Read-Json([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label not found: $Path" }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "$Label is invalid JSON: $($_.Exception.Message)" }
}

$evidence = Read-Json $EvidencePath 'Evidence'
$review = Read-Json $ReviewPath 'Review'
$contract = Read-Json $OutputContractPath 'Output contract'

$classification = if ($evidence.fast_schema -eq 3 -and $review.fast_schema -eq 3 -and [string]$evidence.artifact_class -eq 'fast-v3') {
    'fast-v3'
} elseif ($evidence.fast_schema -eq 2 -or $review.fast_schema -eq 2) {
    'fast-v2-legacy'
} else {
    'fast-legacy'
}
if ($classification -ne 'fast-v3') { $errors.Add('Legacy or missing Fast schema; rerun Maker and Reviewer with fast_schema 3 and a project output contract') }
if ([string]$review.classification -ne 'fast-v3') { $errors.Add('Reviewer classification is not fast-v3') }

if ($contract.contract_schema -ne 1) { $errors.Add('Output contract must declare contract_schema 1') }
if ([string]::IsNullOrWhiteSpace([string]$contract.contract_id)) { $errors.Add('Output contract has no contract_id') }
$contractHash = (Get-FileHash -LiteralPath $OutputContractPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ([string]$evidence.contract_id -ne [string]$contract.contract_id) { $errors.Add('Evidence contract_id does not match output contract') }
if ([string]$evidence.output_contract_sha256 -ne $contractHash) { $errors.Add('Evidence output-contract fingerprint is stale') }
if ([string]$review.output_contract_sha256 -ne $contractHash) { $errors.Add('Reviewer output-contract fingerprint is stale') }

$targetRelativePath = [string]$contract.target_document.path
if ([string]::IsNullOrWhiteSpace($targetRelativePath) -or [System.IO.Path]::IsPathRooted($targetRelativePath)) {
    $errors.Add('Output contract target_document.path must be a non-empty relative path')
}
if ([string]$evidence.target_document_path -ne $targetRelativePath) { $errors.Add('Evidence target path does not match output contract') }

$requiredSections = @($contract.target_document.required_sections | ForEach-Object { [string]$_ })
$coveredSections = @($evidence.coverage.covered_sections | ForEach-Object { [string]$_ })
if ($requiredSections.Count -eq 0) { $errors.Add('Output contract has no required sections') }
foreach ($section in $requiredSections) {
    if ([string]::IsNullOrWhiteSpace($section) -or $section -notin $coveredSections) {
        $errors.Add("Required target section not covered: $section")
    }
}

$contractRequirements = @($contract.evidence_requirements)
if ($contractRequirements.Count -eq 0) { $errors.Add('Output contract has no evidence requirements') }
$seenRequirementIds = @{}
$requiredCollectors = @{}
foreach ($requirement in $contractRequirements) {
    $id = [string]$requirement.id
    if ([string]::IsNullOrWhiteSpace($id)) { $errors.Add('Output contract contains an evidence requirement without id'); continue }
    if ($seenRequirementIds.ContainsKey($id)) { $errors.Add("Duplicate output-contract evidence requirement: $id") }
    $seenRequirementIds[$id] = $true
    $collectors = @($requirement.collectors | ForEach-Object { [string]$_ })
    if ($collectors.Count -eq 0) { $errors.Add("Evidence requirement has no collectors: $id") }
    foreach ($collector in $collectors) {
        if ($collector -notin $allowedCollectors) { $errors.Add("Unknown core collector '$collector' in requirement: $id") }
        else { $requiredCollectors[$collector] = $true }
    }
    foreach ($section in @($requirement.target_sections | ForEach-Object { [string]$_ })) {
        if ($section -notin $requiredSections) { $errors.Add("Evidence requirement '$id' maps to unknown target section: $section") }
    }

    $record = @($evidence.evidence_requirements | Where-Object { [string]$_.id -eq $id }) | Select-Object -First 1
    if ($null -eq $record) {
        if ([bool]$requirement.required) { $errors.Add("Required evidence missing: $id") }
        continue
    }
    $status = [string]$record.status
    if ($status -eq 'not_applicable') {
        if (-not [bool]$requirement.allowed_not_applicable) { $errors.Add("Evidence cannot be not_applicable: $id") }
        if ([string]::IsNullOrWhiteSpace([string]$record.not_applicable_reason)) { $errors.Add("not_applicable evidence lacks reason: $id") }
    } elseif ($status -eq 'covered') {
        $items = @($record.items)
        if ($items.Count -eq 0) { $errors.Add("Covered evidence has no source items: $id") }
        foreach ($item in $items) {
            if ([string]::IsNullOrWhiteSpace([string]$item.source) -or [string]::IsNullOrWhiteSpace([string]$item.locator)) {
                $errors.Add("Evidence item lacks source or locator: $id")
            }
        }
    } elseif ([bool]$requirement.required) {
        $errors.Add("Required evidence is not covered: $id")
    }
}

foreach ($collector in $requiredCollectors.Keys) {
    $run = @($evidence.collector_runs | Where-Object { [string]$_.collector -eq $collector }) | Select-Object -First 1
    if ($null -eq $run) { $errors.Add("Required core collector was not recorded: $collector"); continue }
    if ([string]$run.status -notin @('complete','not_applicable')) { $errors.Add("Core collector did not complete: $collector") }
    if ([bool]$run.materialized_document) { $errors.Add("Fast core collector materialized a Full document: $collector") }
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

$targetPath = if ([System.IO.Path]::IsPathRooted($targetRelativePath)) { $targetRelativePath } else { Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $EvidencePath)) $targetRelativePath }
if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
    $errors.Add("Target document not found: $targetPath")
} else {
    $targetHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([string]$review.target_document_sha256 -ne $targetHash) { $errors.Add('Reviewer target-document fingerprint is stale') }
}
$evidenceHash = (Get-FileHash -LiteralPath $EvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ([string]$review.evidence_sha256 -ne $evidenceHash) { $errors.Add('Reviewer evidence fingerprint is stale') }

if ([string]$review.verdict -ne 'PASS') { $errors.Add('Reviewer verdict is not PASS') }
if (-not [bool]$review.coverage_complete) { $errors.Add('Reviewer did not confirm coverage') }
if (-not [bool]$review.collectors_verified) { $errors.Add('Reviewer did not verify core collectors') }
if (-not [bool]$review.ui_risk_accepted) { $errors.Add('Reviewer did not accept UI risk') }
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
    contract_id = [string]$contract.contract_id
    delivery_ready = ($valid -and [bool]$review.delivery_ready)
    errors = @($errors)
} | ConvertTo-Json -Depth 5
if (-not $valid) { exit 1 }
