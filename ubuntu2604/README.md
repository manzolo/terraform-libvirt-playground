# ubuntu2604

An Ubuntu 26.04 LTS (Resolute Raccoon) KVM virtual machine — the "advanced" project of
this playground. Where [`centos7/`](../centos7/) sticks to defaults, this one
customizes nearly everything, to show where the knobs are.

## Non-default parameters, and why

| Parameter | Value here | Default would be | Why it's interesting |
|-----------|-----------|------------------|----------------------|
| Root disk | COW overlay on a shared base image, grown to **20 GiB** | single volume, image size (~2 GB) | rebuilds are instant (no re-download); `growpart` expands the fs at first boot — see [storage docs](../docs/03-networking-and-storage.md) |
| `cpu { mode = "host-passthrough" }` | host CPU exposed to guest | generic `qemu64` model | full CPU features/flags in the guest, better performance; VM no longer migratable across different CPUs |
| `qemu_agent = true` + `qemu-guest-agent` package | virtio channel host↔guest | none | libvirt can query the guest directly: IP without DHCP-lease guessing, clean shutdown, fs-freeze for snapshots |
| `mac = 52:54:00:26:04:01` | fixed MAC | random | dnsmasq re-issues the same IP across rebuilds |
| `autostart = true` | VM starts with the host | off | typical for "pet" servers |
| Custom admin user (`manzolo`) | via cloud-init `users:` | stock `ubuntu` user | shows users are fully definable in user-data |
| `timezone`, `packages`, `runcmd` | Europe/Rome, htop & co. | untouched image | first-boot provisioning without any config-management tool |
| Headless (no `graphics` block) | serial console only | SPICE display | servers don't need a GPU; `make console` still works (`make viewer` won't) |
| 4 vCPU / 4 GiB RAM via **variables** | `terraform apply -var vcpu=8` | hardcoded | every sizing knob is overridable per-apply |

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_public_key_file` | `~/.ssh/id_rsa.pub` | SSH public key injected via cloud-init |
| `username` | `manzolo` | Admin user created by cloud-init |
| `vm_hostname` | `ubuntu2604` | Hostname (also names the volumes/domain) |
| `vcpu` | `4` | Virtual CPUs |
| `memory_mb` | `4096` | RAM in MiB |
| `disk_size_gb` | `20` | Root disk size in GiB |
| `mac_address` | `52:54:00:26:04:01` | Fixed MAC address |

## Outputs

| Output | Description |
|--------|-------------|
| `vm_ip` | IP address leased on the `default` network |
| `ssh_command` | Ready-to-paste `ssh <username>@<ip>` command |

## Usage

```bash
# via Makefile, from the repo root
make apply PROJECT=ubuntu2604
make ssh PROJECT=ubuntu2604
make destroy PROJECT=ubuntu2604

# or plain Terraform, from this directory
terraform init
terraform apply -var vcpu=8 -var memory_mb=8192   # override anything
$(terraform output -raw ssh_command)
```

First boot takes a bit longer than centos7: `package_update: true` runs a full
`apt update` plus package installs before the VM is "ready".
