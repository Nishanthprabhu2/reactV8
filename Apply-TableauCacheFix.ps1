<#
.SYNOPSIS
    Re-applies custom cache header changes to Tableau Server's httpd.conf.ftl after an upgrade.

.DESCRIPTION
    After every Tableau Server upgrade, the httpd.conf.ftl template gets overwritten.
    This script finds the latest template file, backs it up, and re-applies the
    CUSTOM CACHE CHANGES that fix the Vary: Cookie issue causing inconsistent browser caching.

    Changes applied:
    1. VizQL Server static assets (vqlweb.js, etc.) - removes Vary: Cookie, adds immutable
    2. WGServer static assets (portal JS/CSS) - same fix
    3. Embedding API (tableau.embedding.*.js) - same fix

.NOTES
    Run this script as Administrator after every Tableau Server upgrade.
    Script location: Save this next to the Tableau Server packages directory.

    Author: Tableau Cache Fix Automation
    Date: February 2026

  What the script does automatically:

Finds the latest templates.xxxxx directory (handles version number changes after upgrades)
Checks if changes are already applied (won't duplicate)
Creates a timestamped backup (httpd.conf.ftl.bak_20260222_144800)
Applies all 3 cache changes by matching the exact code patterns
Warns you if it couldn't find all 3 patterns (in case Tableau restructured the template)
Optionally triggers tsm pending-changes apply with a 5-second cancel window

# Preview what it will do (no changes made)
.\Apply-TableauCacheFix.ps1 -DryRun

# Apply changes but don't restart gateway yet
.\Apply-TableauCacheFix.ps1 -SkipTSM

# Apply changes AND restart gateway (full automation)
.\Apply-TableauCacheFix.ps1

#>

param(
    [string]$TableauPackagesDir = "d:\Program Files\Tableau\Tableau Server\packages",
    [switch]$DryRun,
    [switch]$SkipTSM
)

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Tableau Server Cache Fix - Post-Upgrade    " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: Find the latest templates directory ---
Write-Host "[1/6] Finding latest templates directory..." -ForegroundColor Yellow

$templateDirs = Get-ChildItem -Path $TableauPackagesDir -Directory -Filter "templates.*" | Sort-Object Name -Descending
if ($templateDirs.Count -eq 0) {
    Write-Error "No templates directory found in $TableauPackagesDir"
    exit 1
}

$latestTemplateDir = $templateDirs[0].FullName
$ftlFile = Join-Path $latestTemplateDir "httpd.conf.ftl"

if (-not (Test-Path $ftlFile)) {
    Write-Error "httpd.conf.ftl not found at: $ftlFile"
    exit 1
}

Write-Host "  Found: $ftlFile" -ForegroundColor Green
Write-Host ""

# --- Step 2: Check if changes are already applied ---
Write-Host "[2/6] Checking if changes are already applied..." -ForegroundColor Yellow

$content = Get-Content $ftlFile -Raw
if ($content -match "CUSTOM CACHE CHANGES") {
    Write-Host "  Changes are ALREADY applied. No action needed." -ForegroundColor Green
    Write-Host ""
    Write-Host "  If you want to re-apply anyway, manually remove the existing" -ForegroundColor Gray
    Write-Host "  CUSTOM CACHE CHANGES blocks first, then re-run this script." -ForegroundColor Gray
    exit 0
}

Write-Host "  Changes not found — will apply now." -ForegroundColor Green
Write-Host ""

# --- Step 3: Create backup ---
Write-Host "[3/6] Creating backup..." -ForegroundColor Yellow

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFile = "$ftlFile.bak_$timestamp"
Copy-Item $ftlFile $backupFile -Force
Write-Host "  Backup saved: $backupFile" -ForegroundColor Green
Write-Host ""

# --- Step 4: Define the 3 changes ---
Write-Host "[4/6] Preparing changes..." -ForegroundColor Yellow

$cacheBlock = @"
    # --- CUSTOM CACHE CHANGES - START ({0}) ---
    Header unset Vary
    Header append Vary Accept-Encoding
    Header set Cache-Control "public, max-age=31536000, immutable"
    # --- CUSTOM CACHE CHANGES - END ---
"@

# Change 1: VizQL Server static assets
# Find: ExpiresDefault line followed by </DirectoryMatch> in the vizqlserver block
$pattern1 = '(    ExpiresDefault "\$\{TSIG\(''gateway\.versioned_asset\.expiration_policy''\)\}")\r?\n(</DirectoryMatch>)\r?\n\r?\n(<DirectoryMatch "\^\$\{PathsGet\(escape_parens\(TSIG\(''gateway\.vizqlserver\.instance\.public''\)\))'
$replace1_block = ($cacheBlock -f "vizqlserver static assets")

# Change 2: WGServer static assets
# Find: ExpiresDefault line followed by </DirectoryMatch> before eloqua block
$pattern2_marker = 'wgserver\.deploy\.dir'

# Change 3: Embedding API
# Find: Access-Control-Allow-Origin line followed by </Directory> before ProxyPassMatch embedding
$pattern3_marker = 'Access-Control-Allow-Origin "\*"'

# --- Apply changes using targeted string replacements ---
$lines = Get-Content $ftlFile
$newLines = [System.Collections.ArrayList]::new()
$changesMade = 0

$i = 0
while ($i -lt $lines.Count) {
    $line = $lines[$i]
    $newLines.Add($line) | Out-Null

    # Change 1: After ExpiresDefault in vizqlserver static assets block
    if ($line -match 'ExpiresDefault.*gateway\.versioned_asset\.expiration_policy' -and
        $i -gt 0 -and $lines[$i-1] -match 'Require all granted' -and
        $i -gt 1 -and $lines[$i-2] -match 'cursors\|javascripts\|stylesheets\|css\|html\|images\|fonts\|extensions') {

        ($cacheBlock -f "vizqlserver static assets") -split "`n" | ForEach-Object { $newLines.Add($_) | Out-Null }
        $changesMade++
        Write-Host "  [Change 1] VizQL Server static assets - APPLIED (line $($i+1))" -ForegroundColor Green
    }

    # Change 2: After ExpiresDefault in wgserver static assets block
    if ($line -match 'ExpiresDefault.*gateway\.versioned_asset\.expiration_policy' -and
        $i -gt 0 -and $lines[$i-1] -match 'Require all granted' -and
        $i -gt 1 -and $lines[$i-2] -match 'images\|desktop\|javascripts\|stylesheets') {

        ($cacheBlock -f "wgserver static assets") -split "`n" | ForEach-Object { $newLines.Add($_) | Out-Null }
        $changesMade++
        Write-Host "  [Change 2] WGServer static assets - APPLIED (line $($i+1))" -ForegroundColor Green
    }

    # Change 3: After Access-Control-Allow-Origin in embedding API block
    if ($line -match 'Header set Access-Control-Allow-Origin "\*"' -and
        $i -gt 0 -and $lines[$i-1] -match 'Require all granted' -and
        $i -gt 1 -and $lines[$i-2] -match 'gateway\.embedding_api\.client') {

        ($cacheBlock -f "embedding API") -split "`n" | ForEach-Object { $newLines.Add($_) | Out-Null }
        $changesMade++
        Write-Host "  [Change 3] Embedding API - APPLIED (line $($i+1))" -ForegroundColor Green
    }

    $i++
}

Write-Host ""

if ($changesMade -ne 3) {
    Write-Host "  WARNING: Expected 3 changes but only applied $changesMade." -ForegroundColor Red
    Write-Host "  The template structure may have changed in this Tableau version." -ForegroundColor Red
    Write-Host "  Review the file manually and check the backup: $backupFile" -ForegroundColor Red

    if ($changesMade -eq 0) {
        Write-Host "  No changes were made. Exiting." -ForegroundColor Red
        exit 1
    }
}

# --- Step 5: Write changes ---
Write-Host "[5/6] Writing changes to file..." -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "  DRY RUN - No changes written to disk." -ForegroundColor Magenta
    Write-Host "  Would have applied $changesMade changes to: $ftlFile" -ForegroundColor Magenta
} else {
    $newLines | Set-Content $ftlFile
    Write-Host "  File updated: $ftlFile" -ForegroundColor Green
    Write-Host "  Total changes: $changesMade" -ForegroundColor Green
}
Write-Host ""

# --- Step 6: Trigger TSM config regeneration ---
Write-Host "[6/6] Deploying changes via TSM..." -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "  DRY RUN - Skipping TSM commands." -ForegroundColor Magenta
} elseif ($SkipTSM) {
    Write-Host "  Skipped (use -SkipTSM:$false to run TSM commands)." -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Run these manually when ready:" -ForegroundColor Gray
    Write-Host "    tsm configuration set -k gateway.timeout -v 7201" -ForegroundColor Gray
    Write-Host "    tsm pending-changes apply" -ForegroundColor Gray
} else {
    Write-Host "  Running: tsm configuration set -k gateway.timeout -v 7201" -ForegroundColor Gray
    & tsm configuration set -k gateway.timeout -v 7201
    Write-Host "  Running: tsm pending-changes apply" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  NOTE: This will restart the gateway. Press Ctrl+C within 5 seconds to cancel." -ForegroundColor Red
    Start-Sleep -Seconds 5
    & tsm pending-changes apply
    Write-Host "  TSM changes applied successfully." -ForegroundColor Green
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Done! Verify by checking vqlweb.js headers" -ForegroundColor Cyan
Write-Host " in Chrome DevTools after loading a dashboard" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
