# 5. CI with GitHub Actions — including real VMs

Two workflows live in [`.github/workflows/`](../.github/workflows/).

## Workflow 1: lint & validate (`ci.yml`)

Runs on every push and PR. No credentials, no hypervisor — purely static:

1. `terraform fmt -check -recursive` — formatting is canonical, so this is objective;
2. for **every directory containing `.tf` files** (discovered with `find`, so new
   projects are covered automatically):
   - `terraform init -backend=false` — downloads the provider (respecting the lock
     file) without touching any state;
   - `terraform validate` — schema-level check of every resource;
   - `tflint` — linting beyond validation (unused declarations, missing
     `required_version`, deprecated syntax…).

This tier is what most Terraform repos should have at minimum: it proves the code is
well-formed, not that it works.

## Workflow 2: the KVM smoke test (`smoke-test.yml`)

The interesting one. GitHub's `ubuntu-latest` runners expose **`/dev/kvm`** — they are
VMs with nested virtualization enabled — so we can boot *real* VMs in CI:

```
blank runner
  └─ make setup            # the same target a user runs: installs libvirt,
  │                        # terraform, creates pool + network
  └─ terraform apply       # downloads the cloud image, boots the VM
  └─ ssh into the VM       # proves DHCP, cloud-init, users, keys, sudo all work
  └─ terraform destroy     # clean teardown (runs even on failure: `if: always()`)
```

Design choices worth copying:

- **`workflow_dispatch` only** — it downloads cloud images on every run; you don't
  want that on every push. Trigger it from the Actions tab or with
  `gh workflow run smoke-test.yml`.
- **It dogfoods `make setup`** — CI is the only environment that runs the install
  target from scratch every time, so regressions in the docs/tooling surface here
  first. Two real bugs (missing `mkisofs`, AppArmor denial) were found exactly
  this way — see [chapter 4](04-troubleshooting.md).
- **A matrix runs every project** (`centos7`, `ubuntu2604`, `multivm`) as independent jobs.
- **The SSH check is generic**: it takes user@host from the project's `ssh_command`
  output, so projects with different usernames need no workflow changes. Projects can
  additionally declare a `smoke_check` output — a command the workflow runs inside the
  VM (multivm uses it to ping every node by hostname).
- **Retry loop for SSH** — the VM needs time to boot and run cloud-init; the job
  polls up to 30×10s instead of sleeping a fixed amount.
- **`timeout-minutes`** as a safety net: a hung `wait_for_lease` would otherwise
  burn the runner for 6 hours.

In practice a full centos7 run takes **~90 seconds** on GitHub's runners (the
Azure-hosted runners download the 900 MB image in a few seconds).

## Why bother with the smoke test?

`terraform validate` happily accepts a configuration that can never boot: wrong pool
name, image URL 404, broken cloud-init YAML (remember: cloud-init fails *silently*),
missing host packages. The only way to know the repo actually works end-to-end is to
run it end-to-end — and doing that on a disposable runner is exactly what CI is for.

Next: [6. Multi-VM clusters and custom networks](06-multi-vm-networking.md)
