# Tableau Server Cache Fix — DevOps Runbook

## What This Fixes

Tableau Server sends a `Vary: Cookie` header on static JS/CSS files (`vqlweb.js` = 9.3 MB, etc.).
This causes browsers to re-download all assets whenever session cookies change, instead of using cache.
The fix removes `Vary: Cookie` and adds `Cache-Control: immutable` on versioned static assets.

---

## Files Included

| File | Purpose |
|------|---------|
| `Apply-TableauCacheFix.ps1` | PowerShell script that applies/rollbacks the fix |
| `Tableau_Cache_Fix_Documentation.md` | Detailed technical documentation |

---

## When to Run

- **After every Tableau Server upgrade** (the upgrade overwrites the config template)
- Safe to run multiple times (script checks if changes already exist and skips if so)

---

## How to Apply the Fix

### Step 1: Copy the Script

Copy `Apply-TableauCacheFix.ps1` to:

```
d:\Program Files\Tableau\Tableau Server\packages\
```

### Step 2: Open PowerShell as Administrator

Right-click PowerShell → **Run as administrator**

### Step 3: Allow Script Execution

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### Step 4: Navigate to the Packages Directory

```powershell
cd "d:\Program Files\Tableau\Tableau Server\packages"
```

### Step 5: Run the Script

```powershell
# Preview changes first (no modifications made):
.\Apply-TableauCacheFix.ps1 -DryRun

# Apply the fix:
.\Apply-TableauCacheFix.ps1
```

### Expected Output

```
=== Tableau Cache Fix ===

Found: D:\...\templates.20233.24.0425.1414\httpd.conf.ftl

BEFORE:
  Vary header:     Cookie,Accept-Encoding (Tableau default)
  Cache-Control:   max-age=31536000 (Tableau default)
  Cache fix:       Not applied

Backup: D:\...\httpd.conf.ftl.bak_20260224_084025
[Change 1/3] VizQL static assets - OK
[Change 2/3] WGServer static assets - OK
[Change 3/3] Embedding API - OK

AFTER:
  Vary header:     Accept-Encoding (Cookie removed)
  Cache-Control:   public, max-age=31536000, immutable
  Cache fix:       Applied (3/3 blocks)

  +-----------------------+---------------------------------+------------------------------------------+
  | Setting               | Previous                        | Current                                  |
  +-----------------------+---------------------------------+------------------------------------------+
  | Vary header           | Cookie,Accept-Encoding          | Accept-Encoding                          |
  | Cache-Control         | max-age=31536000                | public, max-age=31536000, immutable      |
  | CUSTOM CACHE CHANGES  | Not present                     | 3 blocks applied                         |
  +-----------------------+---------------------------------+------------------------------------------+

File updated. Now deploying...
Running: tsm configuration set -k gateway.timeout -v 7201
Running: tsm pending-changes apply
...
100% - Waiting for services to reconfigure.
Successfully deployed nodes with updated configuration and topology version.

=== DONE ===

  To rollback: .\Apply-TableauCacheFix.ps1 -Rollback
```

> **Note:** The `tsm pending-changes apply` step takes ~15 minutes and causes a brief gateway restart.
> Schedule during a maintenance window if possible.

---

## How to Verify the Fix

After the script completes, verify that the changes made it into the generated Apache config:

### Step 1: Search for the changes

```powershell
cd "d:\Program Files\Tableau\Tableau Server\packages"
dir templates.*\httpd.conf.ftl | Select-String "CUSTOM CACHE CHANGES"
```

You should see **6 matches** (2 comment lines × 3 blocks):

```
httpd.conf.ftl:  # --- CUSTOM CACHE CHANGES - START (vizqlserver static assets) ---
httpd.conf.ftl:  # --- CUSTOM CACHE CHANGES - END ---
httpd.conf.ftl:  # --- CUSTOM CACHE CHANGES - START (wgserver static assets) ---
httpd.conf.ftl:  # --- CUSTOM CACHE CHANGES - END ---
httpd.conf.ftl:  # --- CUSTOM CACHE CHANGES - START (embedding API) ---
httpd.conf.ftl:  # --- CUSTOM CACHE CHANGES - END ---
```

### Step 2: Confirm all 3 blocks are present

Each block should contain these 3 lines between the START and END comments:

```apache
Header unset Vary
Header append Vary Accept-Encoding
Header set Cache-Control "public, max-age=31536000, immutable"
```

If you see all 6 matches and the `tsm pending-changes apply` completed successfully, the fix is active.

---

## How to Rollback

### Option A: Use the Script (Recommended)

The script has a built-in rollback mode that automatically removes all cache fix blocks and redeploys:

```powershell
cd "d:\Program Files\Tableau\Tableau Server\packages"
.\Apply-TableauCacheFix.ps1 -Rollback
```

Expected output:

```
=== Tableau Cache Fix — ROLLBACK ===

Found: D:\...\templates.20233.24.0425.1414\httpd.conf.ftl

BEFORE rollback:
  Cache fix blocks found: 3
  Vary header:           unset + Accept-Encoding only
  Cache-Control:         public, max-age=31536000, immutable
  Backup: D:\...\httpd.conf.ftl.bak_rollback_20260317_083100

AFTER rollback:
  Cache fix blocks removed: 3
  Vary header:              Cookie,Accept-Encoding (Tableau default)
  Cache-Control:            max-age=31536000 (Tableau default)

File updated. Now deploying...
Running: tsm configuration set -k gateway.timeout -v 7200
Running: tsm pending-changes apply
...

=== ROLLBACK COMPLETE ===
```

### Option B: Restore from Backup

The script creates a timestamped backup before every change. To restore manually:

```powershell
# 1. Find the backup file
cd "d:\Program Files\Tableau\Tableau Server\packages"
dir templates.*\httpd.conf.ftl.bak*

# 2. Copy it back (replace version number and timestamp with actual values)
Copy-Item "templates.20233.24.0425.1414\httpd.conf.ftl.bak_20260224_084025" `
          "templates.20233.24.0425.1414\httpd.conf.ftl" -Force

# 3. Redeploy
tsm configuration set -k gateway.timeout -v 7200
tsm pending-changes apply
```

---

## Script Modes — Quick Reference

| Command | What It Does |
|---------|-------------|
| `.\Apply-TableauCacheFix.ps1` | Apply the cache fix + deploy |
| `.\Apply-TableauCacheFix.ps1 -DryRun` | Preview changes only, no modifications |
| `.\Apply-TableauCacheFix.ps1 -Rollback` | Remove the fix + deploy (restore Tableau defaults) |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Script says "No templates.* folder found" | Make sure you're running from `d:\Program Files\Tableau\Tableau Server\packages\` |
| Script says "Changes are ALREADY applied" | Fix is already in place, no action needed |
| Script says "No CUSTOM CACHE CHANGES found" (on rollback) | Fix hasn't been applied, nothing to rollback |
| Script says "Expected 3 changes, applied X" | Tableau may have restructured the template in a new version. Apply changes manually using the documentation file |
| Execution policy error | Run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` first |
| Access denied | Run PowerShell as **Administrator** |
| Gateway doesn't restart | Run `tsm restart` manually |
| `tsm pending-changes apply` says "Canceling job to avoid restarting server" | Run `tsm pending-changes apply --ignore-prompt` instead |
