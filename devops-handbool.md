# Tableau Server Cache Fix — DevOps Runbook

## What This Fixes

Tableau Server sends a `Vary: Cookie` header on static JS/CSS files (`vqlweb.js` = 9.3 MB, etc.).
This causes browsers to re-download all assets whenever session cookies change, instead of using cache.
The fix removes `Vary: Cookie` and adds `Cache-Control: immutable` on versioned static assets.

---

## Files Included

| File | Purpose |
|------|---------|
| `Apply-TableauCacheFix.ps1` | PowerShell script that applies the fix |
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
.\Apply-TableauCacheFix.ps1
```

### Expected Output

```
=== Tableau Cache Fix ===

Found: D:\...\templates.20233.24.0425.1414\httpd.conf.ftl
Backup: D:\...\httpd.conf.ftl.bak_20260224_084025
[Change 1/3] VizQL static assets - OK
[Change 2/3] WGServer static assets - OK
[Change 3/3] Embedding API - OK

File updated. Now deploying...
Running: tsm configuration set -k gateway.timeout -v 7201
Running: tsm pending-changes apply
...
100% - Waiting for services to reconfigure.
Successfully deployed nodes with updated configuration and topology version.

=== DONE ===
```

> **Note:** The `tsm pending-changes apply` step takes ~15 minutes and causes a brief gateway restart.
> Schedule during a maintenance window if possible.

---

## How to Verify the Fix

After the script completes, verify that the changes made it into the generated Apache config:

### Step 1: Find the generated httpd.conf

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

If anything goes wrong after applying the fix:

### Option A: Restore from Backup

The script creates a timestamped backup before making changes (e.g., `httpd.conf.ftl.bak_20260224_084025`).

```powershell
# 1. Find the backup file
cd "d:\Program Files\Tableau\Tableau Server\packages"
dir templates.*\httpd.conf.ftl.bak*

# 2. Copy it back (replace the version number and timestamp with actual values)
Copy-Item "templates.20233.24.0425.1414\httpd.conf.ftl.bak_20260224_084025" `
          "templates.20233.24.0425.1414\httpd.conf.ftl" -Force

# 3. Redeploy
tsm configuration set -k gateway.timeout -v 7200
tsm pending-changes apply
```

### Option B: Manual Revert

1. Open `httpd.conf.ftl` in a text editor (as Administrator)
2. Search for `CUSTOM CACHE CHANGES` — there will be 3 blocks
3. Delete these 5 lines from each block:

```
    # --- CUSTOM CACHE CHANGES - START (...) ---
    Header unset Vary
    Header append Vary Accept-Encoding
    Header set Cache-Control "public, max-age=31536000, immutable"
    # --- CUSTOM CACHE CHANGES - END ---
```

4. Save the file, then redeploy:

```powershell
tsm configuration set -k gateway.timeout -v 7200
tsm pending-changes apply
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Script says "No templates.* folder found" | Make sure you're running from `d:\Program Files\Tableau\Tableau Server\packages\` |
| Script says "Changes are ALREADY applied" | Fix is already in place, no action needed |
| Script says "Expected 3 changes, applied X" | Tableau may have restructured the template in a new version. Apply changes manually using the documentation file |
| Execution policy error | Run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` first |
| Access denied | Run PowerShell as **Administrator** |
| Gateway doesn't restart | Run `tsm restart` manually |
