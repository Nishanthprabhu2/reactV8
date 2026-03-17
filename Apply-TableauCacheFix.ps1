<#
.SYNOPSIS
    Re-applies custom cache header changes to Tableau Server's httpd.conf.ftl after an upgrade.

.DESCRIPTION
    After every Tableau Server upgrade, httpd.conf.ftl gets overwritten.
    This script backs it up and re-applies the cache fix that removes
    Vary: Cookie from static assets (vqlweb.js, etc.) to fix inconsistent
    browser caching.

    Run from: d:\Program Files\Tableau\Tableau Server\packages\

.NOTES
    STEPS FOR DEVOPS:
    1. Copy this file to: d:\Program Files\Tableau\Tableau Server\packages\
    2. Open PowerShell as Administrator
    3. Run:
         Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
         cd "d:\Program Files\Tableau\Tableau Server\packages"

         # Apply the fix:
         .\Apply-TableauCacheFix.ps1

         # Rollback the fix:
         .\Apply-TableauCacheFix.ps1 -Rollback

         # Preview only (no changes):
         .\Apply-TableauCacheFix.ps1 -DryRun
#>

param(
    [switch]$DryRun,
    [switch]$Rollback
)

$ErrorActionPreference = "Stop"

Write-Host ""
if ($Rollback) {
    Write-Host "=== Tableau Cache Fix — ROLLBACK ===" -ForegroundColor Yellow
}
elseif ($DryRun) {
    Write-Host "=== Tableau Cache Fix — DRY RUN ===" -ForegroundColor Magenta
}
else {
    Write-Host "=== Tableau Cache Fix ===" -ForegroundColor Cyan
}
Write-Host ""

# Find latest templates directory
$templateDir = Get-ChildItem -Path "." -Directory -Filter "templates.*" | Sort-Object Name -Descending | Select-Object -First 1
if (-not $templateDir) { Write-Host "ERROR: No templates.* folder found. Are you in the packages directory?" -ForegroundColor Red; exit 1 }

$ftlFile = Join-Path $templateDir.FullName "httpd.conf.ftl"
if (-not (Test-Path $ftlFile)) { Write-Host "ERROR: httpd.conf.ftl not found in $($templateDir.Name)" -ForegroundColor Red; exit 1 }

Write-Host "Found: $ftlFile" -ForegroundColor Green

# ============================================================
# ROLLBACK MODE
# ============================================================
if ($Rollback) {
    $content = Get-Content $ftlFile -Raw
    if ($content -notmatch "CUSTOM CACHE CHANGES") {
        Write-Host "No CUSTOM CACHE CHANGES found in file. Nothing to rollback." -ForegroundColor Yellow
        exit 0
    }

    Write-Host ""
    Write-Host "BEFORE rollback:" -ForegroundColor Yellow
    $matchCount = ([regex]::Matches($content, "CUSTOM CACHE CHANGES - START")).Count
    Write-Host "  Cache fix blocks found: $matchCount" -ForegroundColor White
    Write-Host "  Vary header:           unset + Accept-Encoding only" -ForegroundColor White
    Write-Host "  Cache-Control:         public, max-age=31536000, immutable" -ForegroundColor White

    if ($DryRun) {
        Write-Host ""
        Write-Host "DRY RUN - Would remove $matchCount CUSTOM CACHE CHANGES blocks." -ForegroundColor Magenta
        exit 0
    }

    # Backup before rollback
    $backup = "$ftlFile.bak_rollback_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $ftlFile $backup -Force
    Write-Host "  Backup: $backup" -ForegroundColor Green

    # Remove the cache blocks (5 lines each: blank + 2 comments + 3 headers)
    $lines = Get-Content $ftlFile
    $newLines = [System.Collections.ArrayList]::new()
    $skipping = $false
    $removedBlocks = 0

    for ($i = 0; $i -lt $lines.Count; $i++) {
        # Skip the blank line before the START comment
        if ($i + 1 -lt $lines.Count -and $lines[$i + 1] -match "CUSTOM CACHE CHANGES - START") {
            # Skip this blank line
            continue
        }
        if ($lines[$i] -match "CUSTOM CACHE CHANGES - START") {
            $skipping = $true
            continue
        }
        if ($lines[$i] -match "CUSTOM CACHE CHANGES - END") {
            $skipping = $false
            $removedBlocks++
            continue
        }
        if ($skipping) { continue }
        $newLines.Add($lines[$i]) | Out-Null
    }

    $newLines | Set-Content $ftlFile

    Write-Host ""
    Write-Host "AFTER rollback:" -ForegroundColor Green
    Write-Host "  Cache fix blocks removed: $removedBlocks" -ForegroundColor White
    Write-Host "  Vary header:              Cookie,Accept-Encoding (Tableau default)" -ForegroundColor White
    Write-Host "  Cache-Control:            max-age=31536000 (Tableau default)" -ForegroundColor White
    Write-Host ""
    Write-Host "File updated. Now deploying..." -ForegroundColor Green

    Write-Host "Running: tsm configuration set -k gateway.timeout -v 7200" -ForegroundColor Yellow
    tsm configuration set -k gateway.timeout -v 7200
    Write-Host "Running: tsm pending-changes apply" -ForegroundColor Yellow
    tsm pending-changes apply

    Write-Host ""
    Write-Host "=== ROLLBACK COMPLETE ===" -ForegroundColor Cyan
    exit 0
}

# ============================================================
# APPLY MODE
# ============================================================

# Check if already applied
$content = Get-Content $ftlFile -Raw
$alreadyApplied = $content -match "CUSTOM CACHE CHANGES"

if ($alreadyApplied) {
    Write-Host "Changes are ALREADY applied. Nothing to do." -ForegroundColor Green
    Write-Host ""
    Write-Host "  To rollback, run: .\Apply-TableauCacheFix.ps1 -Rollback" -ForegroundColor Gray
    exit 0
}

# Record BEFORE state
Write-Host ""
Write-Host "BEFORE:" -ForegroundColor Yellow
Write-Host "  Vary header:     Cookie,Accept-Encoding (Tableau default)" -ForegroundColor White
Write-Host "  Cache-Control:   max-age=31536000 (Tableau default)" -ForegroundColor White
Write-Host "  Cache fix:       Not applied" -ForegroundColor White
Write-Host ""

if ($DryRun) {
    Write-Host "DRY RUN - Would apply 3 cache fix blocks to:" -ForegroundColor Magenta
    Write-Host "  1. VizQL static assets (vqlweb.js, CSS, fonts, etc.)" -ForegroundColor White
    Write-Host "  2. WGServer static assets (portal JS/CSS)" -ForegroundColor White
    Write-Host "  3. Embedding API (tableau.embedding.*.js)" -ForegroundColor White
    Write-Host ""
    Write-Host "AFTER (preview):" -ForegroundColor Green
    Write-Host "  Vary header:     Accept-Encoding (Cookie removed)" -ForegroundColor White
    Write-Host "  Cache-Control:   public, max-age=31536000, immutable" -ForegroundColor White
    Write-Host "  Cache fix:       Applied" -ForegroundColor White
    exit 0
}

# Backup
$backup = "$ftlFile.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item $ftlFile $backup -Force
Write-Host "Backup: $backup" -ForegroundColor Green

# Apply changes
$cacheBlock = @"

    # --- CUSTOM CACHE CHANGES - START ({0}) ---
    Header unset Vary
    Header append Vary Accept-Encoding
    Header set Cache-Control "public, max-age=31536000, immutable"
    # --- CUSTOM CACHE CHANGES - END ---
"@

$lines = Get-Content $ftlFile
$newLines = [System.Collections.ArrayList]::new()
$changes = 0

for ($i = 0; $i -lt $lines.Count; $i++) {
    $newLines.Add($lines[$i]) | Out-Null

    # Change 1: vizqlserver static assets
    if ($lines[$i] -match 'ExpiresDefault.*gateway\.versioned_asset\.expiration_policy' -and
        $i -gt 1 -and $lines[$i - 2] -match 'cursors\|javascripts\|stylesheets\|css\|html\|images\|fonts\|extensions') {
        ($cacheBlock -f "vizqlserver static assets") -split "`n" | ForEach-Object { $newLines.Add($_) | Out-Null }
        $changes++; Write-Host "[Change $changes/3] VizQL static assets - OK" -ForegroundColor Green
    }

    # Change 2: wgserver static assets
    if ($lines[$i] -match 'ExpiresDefault.*gateway\.versioned_asset\.expiration_policy' -and
        $i -gt 1 -and $lines[$i - 2] -match 'images\|desktop\|javascripts\|stylesheets') {
        ($cacheBlock -f "wgserver static assets") -split "`n" | ForEach-Object { $newLines.Add($_) | Out-Null }
        $changes++; Write-Host "[Change $changes/3] WGServer static assets - OK" -ForegroundColor Green
    }

    # Change 3: embedding API
    if ($lines[$i] -match 'Header set Access-Control-Allow-Origin "\*"' -and
        $i -gt 1 -and $lines[$i - 2] -match 'gateway\.embedding_api\.client') {
        ($cacheBlock -f "embedding API") -split "`n" | ForEach-Object { $newLines.Add($_) | Out-Null }
        $changes++; Write-Host "[Change $changes/3] Embedding API - OK" -ForegroundColor Green
    }
}

if ($changes -ne 3) {
    Write-Host "WARNING: Expected 3 changes, applied $changes. Template may have changed." -ForegroundColor Red
    if ($changes -eq 0) { exit 1 }
}

$newLines | Set-Content $ftlFile

# Display AFTER state
Write-Host ""
Write-Host "AFTER:" -ForegroundColor Green
Write-Host "  Vary header:     Accept-Encoding (Cookie removed)" -ForegroundColor White
Write-Host "  Cache-Control:   public, max-age=31536000, immutable" -ForegroundColor White
Write-Host "  Cache fix:       Applied ($changes/3 blocks)" -ForegroundColor White
Write-Host ""

# Summary table
Write-Host "  +-----------------------+---------------------------------+------------------------------------------+" -ForegroundColor Gray
Write-Host "  | Setting               | Previous                        | Current                                  |" -ForegroundColor Gray
Write-Host "  +-----------------------+---------------------------------+------------------------------------------+" -ForegroundColor Gray
Write-Host "  | Vary header           | Cookie,Accept-Encoding          | Accept-Encoding                          |" -ForegroundColor White
Write-Host "  | Cache-Control         | max-age=31536000                | public, max-age=31536000, immutable      |" -ForegroundColor White
Write-Host "  | CUSTOM CACHE CHANGES  | Not present                     | 3 blocks applied                         |" -ForegroundColor White
Write-Host "  +-----------------------+---------------------------------+------------------------------------------+" -ForegroundColor Gray
Write-Host ""

Write-Host "File updated. Now deploying..." -ForegroundColor Green

# Deploy via TSM
Write-Host "Running: tsm configuration set -k gateway.timeout -v 7201" -ForegroundColor Yellow
tsm configuration set -k gateway.timeout -v 7201
Write-Host "Running: tsm pending-changes apply" -ForegroundColor Yellow
tsm pending-changes apply

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  To rollback: .\Apply-TableauCacheFix.ps1 -Rollback" -ForegroundColor Gray
