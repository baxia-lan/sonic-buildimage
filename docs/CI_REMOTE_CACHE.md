# Remote Cache Setup for GitHub Actions

## Problem
The kernel build takes ~100 minutes on GitHub Actions (2 vCPU runners).
With remote cache, subsequent builds skip the kernel entirely (cache hit).

## Setup

### 1. Create a GCP Service Account

```bash
# In the yilanji-sandbox-163694 project
gcloud iam service-accounts create sonic-ci-cache \
  --display-name="SONiC CI Cache"

gcloud projects add-iam-policy-binding yilanji-sandbox-163694 \
  --member="serviceAccount:sonic-ci-cache@yilanji-sandbox-163694.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin" \
  --condition="expression=resource.name.startsWith('projects/_/buckets/sonic-bazel-cache'),title=sonic-cache-only"
```

### 2. Generate a Key

```bash
gcloud iam service-accounts keys create /tmp/gcp-key.json \
  --iam-account=sonic-ci-cache@yilanji-sandbox-163694.iam.gserviceaccount.com

# Base64 encode for GitHub secret
base64 -i /tmp/gcp-key.json | tr -d '\n'
```

### 3. Add to GitHub Secrets

Go to: https://github.com/baxia-lan/sonic-buildimage/settings/secrets/actions

Add secret:
- Name: `GCP_SA_KEY`
- Value: (paste the base64-encoded JSON key)

### 4. Verify

Push to `claude` branch. The CI should show:
```
Setup remote cache credentials: completed success
```
And subsequent builds should show "action cache hit" for most targets.

## Expected Speedup

| Step | Without Cache | With Cache |
|------|--------------|------------|
| Kernel | ~100 min | ~2 min |
| Orchagent | ~30 min | ~5 min |
| Service images | ~1 min | ~1 min |
| VS build | ~5 min | ~2 min |
| **Total** | **~140 min** | **~10 min** |
