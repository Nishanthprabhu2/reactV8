# Tableau Server Performance Tuning — Recommended Changes

**Date**: February 25, 2026
**Server**: `qatableau.glassbeam.com` (Tableau Server 2023.3)

---

## Current Settings

| Setting | Key | Current Value |
|---------|-----|---------------|
| Query timeout | `vizqlserver.querylimit` | 1800 sec (30 min) |
| Query cache size | `vizqlserver.querycacheinmb` | 384 MB |
| Metadata cache size | `vizqlserver.metadatacacheinmb` | 16 MB |
| Session timeout | `vizqlserver.session.expiry.timeout` | 30 min |
| Cache warm-up | `backgrounder.externalquerycachewarmup.enabled` | false |
| Data refresh mode | `vizqlserver.data_refresh` | null (default) |

---

## Recommended Changes

### 1. Increase Query Cache (384 MB → 1024 MB)

Caches query results in memory so repeat visits to the same dashboard skip database queries.

```powershell
# Check current
tsm configuration get -k vizqlserver.querycacheinmb

# Set to 1024 MB (only if server has 32+ GB RAM)
tsm configuration set -k vizqlserver.querycacheinmb -v 1024
```

### 2. Increase Metadata Cache (16 MB → 64 MB)

Caches table schemas, field info, and data source metadata. 16 MB is small.

```powershell
# Check current
tsm configuration get -k vizqlserver.metadatacacheinmb

# Set to 64 MB
tsm configuration set -k vizqlserver.metadatacacheinmb -v 64
```

### 3. Enable Cache Warm-Up (false → true)

Pre-loads frequently viewed dashboards after server restart so the first user doesn't wait.

```powershell
# Check current
tsm configuration get -k backgrounder.externalquerycachewarmup.enabled

# Enable
tsm configuration set -k backgrounder.externalquerycachewarmup.enabled -v true
```

### 4. Increase Session Timeout (30 → 60 minutes)

Keeps VizQL sessions alive longer. If a user revisits a dashboard within the timeout window, the session is reused instead of creating a new one (faster reload).

```powershell
# Check current
tsm configuration get -k vizqlserver.session.expiry.timeout

# Set to 60 minutes
tsm configuration set -k vizqlserver.session.expiry.timeout -v 60
```

---

## How to Apply

Set all values first, then apply once:

```powershell
tsm configuration set -k vizqlserver.querycacheinmb -v 1024
tsm configuration set -k vizqlserver.metadatacacheinmb -v 64
tsm configuration set -k backgrounder.externalquerycachewarmup.enabled -v true
tsm configuration set -k vizqlserver.session.expiry.timeout -v 60
tsm pending-changes apply
```

---

## How to Rollback

Restore original values:

```powershell
tsm configuration set -k vizqlserver.querycacheinmb -v 384
tsm configuration set -k vizqlserver.metadatacacheinmb -v 16
tsm configuration set -k backgrounder.externalquerycachewarmup.enabled -v false
tsm configuration set -k vizqlserver.session.expiry.timeout -v 30
tsm pending-changes apply
```
