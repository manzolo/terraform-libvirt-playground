# terraform-libvirt-playground

[![CI](https://github.com/manzolo/terraform-libvirt-playground/actions/workflows/ci.yml/badge.svg)](https://github.com/manzolo/terraform-libvirt-playground/actions/workflows/ci.yml)
[![Smoke test (KVM)](https://github.com/manzolo/terraform-libvirt-playground/actions/workflows/smoke-test.yml/badge.svg)](https://github.com/manzolo/terraform-libvirt-playground/actions/workflows/smoke-test.yml)

Terraform experiments for provisioning local KVM/QEMU virtual machines through the
[dmacvicar/libvirt](https://registry.terraform.io/providers/dmacvicar/libvirt/latest) provider —
infrastructure-as-code on your own workstation, no cloud account required.

The goal: describe a VM (disk image, CPU/RAM, network, console) in a single `.tf` file and let
`terraform apply` do everything `virt-install` would do by hand — download the cloud image,
create the volume in a storage pool, define and boot the libvirt domain.

## Projects

| Directory | Description |
|-----------|-------------|
| [`centos7/`](centos7/) | A CentOS 7 VM (2 vCPU, 2 GB RAM) built from the official GenericCloud qcow2 image, attached to the `default` libvirt network, with serial console, SPICE graphics and cloud-init provisioning (user + SSH key) |

> **Note:** CentOS 7 reached end-of-life on June 30, 2024. This project is kept as a
> reference/playground — swap the image `source` for a current distro (AlmaLinux, Rocky,
> Ubuntu cloud images) for real use.

## Quick start

On Debian/Ubuntu everything is automated by the [Makefile](Makefile):

```bash
make setup    # one-time: installs KVM/libvirt + Terraform, enables the default
              # network, creates the hd_pool storage pool, adds you to the libvirt group
make apply    # create the VM
make ssh      # log in as 'centos'
make destroy  # tear it down
```

All targets (see `make help`):

| Target | Description |
|--------|-------------|
| `setup` | Install prerequisites and prepare libvirt (network, storage pool, group) |
| `pool` | Create just the `hd_pool` storage pool if missing |
| `init` / `fmt` / `validate` / `plan` / `apply` / `destroy` | The usual Terraform lifecycle |
| `ip` | Print the VM's IP address |
| `ssh` | SSH into the VM |
| `console` | Attach to the serial console (exit with `Ctrl+]`) |
| `viewer` | Open the SPICE graphical console |
| `clean` | Remove local Terraform artifacts (does **not** destroy the VM) |

Targets operate on `centos7/` by default; select another project with
`make apply PROJECT=<dir>`.

> After `make setup`, log out and back in (or run `newgrp libvirt`) so the
> `libvirt` group membership takes effect.

## Prerequisites (manual route)

If you'd rather not use `make setup`:

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.0
- A working libvirt/KVM setup (`qemu-kvm`, `libvirt-daemon-system`, `virsh`)
- Your user in the `libvirt` group (or run against `qemu:///system` with proper polkit rules)
- A storage pool named `hd_pool` (check with `virsh pool-list`; adjust `pool` in the `.tf` file
  to match yours, e.g. `default` — or run `make pool`)
- The `default` libvirt network active (`virsh net-list`)

## Usage with plain Terraform

```bash
cd centos7
terraform init
terraform plan
terraform apply
```

By default cloud-init injects `~/.ssh/id_rsa.pub` for the `centos` user; point it at a
different key with:

```bash
terraform apply -var ssh_public_key_file=~/.ssh/id_ed25519.pub
```

Connect to the VM — `apply` waits for the DHCP lease and prints the IP as an output:

```bash
# SSH (key-based, user 'centos' with passwordless sudo)
$(terraform output -raw ssh_command)

# Serial console (exit with Ctrl+])
virsh console centos7

# Or via SPICE
virt-viewer centos7
```

Tear everything down:

```bash
terraform destroy
```

## CI

Two GitHub Actions workflows live in [`.github/workflows/`](.github/workflows/):

- **CI** ([`ci.yml`](.github/workflows/ci.yml)) — runs on every push and PR: `terraform fmt
  -check`, then `terraform validate` and [tflint](https://github.com/terraform-linters/tflint)
  on every project directory. Fast, no credentials needed.
- **Smoke test (KVM)** ([`smoke-test.yml`](.github/workflows/smoke-test.yml)) — manual trigger
  only (`workflow_dispatch`, run it from the Actions tab or with `gh workflow run
  smoke-test.yml`). GitHub's Linux runners expose `/dev/kvm`, so this does the real thing end
  to end: `make setup` on a blank runner, `terraform apply`, SSH into the freshly booted VM to
  verify cloud-init, then `terraform destroy`. It downloads the ~900 MB cloud image, so expect
  ~10-15 minutes.

## Notes

- The provider talks to the local hypervisor via `uri = "qemu:///system"`. To manage a **remote**
  host, switch the URI to `qemu+ssh://user@host/system` (commented example in the `.tf` file).
- The cloud image ships without a default password, so login is handled by cloud-init: a
  `libvirt_cloudinit_disk` seed ISO ([`cloud_init.cfg`](centos7/cloud_init.cfg)) creates the
  `centos` user with your SSH public key, passwordless sudo and root-partition auto-grow.
  Password authentication stays disabled.
- State files (`terraform.tfstate`) are intentionally git-ignored.

## License

MIT
