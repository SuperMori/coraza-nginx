# Fedora 44 x86_64 bundle

This directory builds a self-contained Nginx + coraza-nginx + libcoraza +
OWASP CRS bundle for a Fedora 44 x86_64 runtime. It is intentionally separate
from the host's distribution Nginx: a dynamic module must match the Nginx build
signature, and Fedora enables a broad distribution-specific module set.

The public repository contains only generic build inputs and a loopback smoke
configuration. Hostnames, upstream addresses, application exclusions, rate
limits, credentials, and production routing belong in a private deployment
repository.

## Build and test

The same entrypoint is used locally and by GitHub Actions:

```bash
packaging/fedora44/run-ci.sh
```

It performs all compilation in the Fedora image pinned in `versions.env`, then
starts the finished bundle in a fresh Fedora 44 container. The smoke test proves:

- Nginx can load the connector and libcoraza 1.6 bulk-header API;
- a real rule match is observed while `DetectionOnly` still passes the request;
- audit and access logs do not contain the test query value;
- runtime shared libraries resolve; and
- every file matches the bundle's internal `SHA256SUMS`.

The resulting archive is deterministic for a fixed checkout and fixed resolved
RPM set. Fedora package repositories are update streams, so the build manifest
records every builder package; this is traceable but should not be described as
bit-for-bit reproducible across arbitrary future dates.

## CRS update policy

`crs-production-candidate.yml` checks the current production LTS line daily.
It never follows the mutable CRS `main` branch and never updates Fedora hosts in
place. A same-line patch release is downloaded from its immutable release tag,
recorded with a fresh SHA256, built, and smoke-tested before an automation branch
is published. A new LTS line creates a review issue only because it can change
rule behavior and false-positive characteristics.

The production pin in `versions.env` changes only through review. If the
organization permits GitHub Actions to create pull requests, the workflow opens
one; otherwise it creates an issue linking to the tested candidate branch. A
human must still approve a tagged bundle and the separate deployment change.

## Release trust boundary

Pull requests receive read-only GitHub permissions and upload only temporary
workflow artifacts. Pushes to `main` and `bundle-v*` tags add GitHub artifact
attestations. Only a `bundle-v*` tag creates a GitHub Release.

Before deployment, verify both layers:

```bash
sha256sum -c coraza-nginx-*.tar.gz.sha256
gh attestation verify coraza-nginx-*.tar.gz --repo SuperMori/coraza-nginx
```

Deployment should extract the archive into a new versioned directory, update
`/opt/coraza-nginx/current` atomically, and keep the previous directory for
rollback. That deployment logic is deliberately out of scope for this public
fork.
