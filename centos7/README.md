# centos7

A CentOS 7 KVM virtual machine defined entirely in Terraform via the
[dmacvicar/libvirt](https://registry.terraform.io/providers/dmacvicar/libvirt/latest) provider.

This is the **basics** project of the playground: everything stays at defaults, so the
`.tf` file reads top-to-bottom as an introduction. Concepts are explained in the
[docs](../docs/01-terraform-libvirt-basics.md); the knobs-turned counterpart is
[`ubuntu2604/`](../ubuntu2604/).

> CentOS 7 is EOL since June 2024 — this is a playground/reference. Swap the image `source`
> for AlmaLinux, Rocky or an Ubuntu cloud image for real use.

## What it creates

| Resource | Details |
|----------|---------|
| `libvirt_volume.centos7_qcow2` | Root disk in the `hd_pool` storage pool, backed by the official CentOS 7 GenericCloud qcow2 image |
| `libvirt_cloudinit_disk.centos7_init` | Seed ISO built from [`cloud_init.cfg`](cloud_init.cfg): user `centos`, your SSH public key, passwordless sudo, rootfs auto-grow, password auth disabled |
| `libvirt_domain.centos7` | The VM: 2 vCPU, 2 GB RAM, `default` network (waits for DHCP lease), serial console, SPICE graphics |

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ssh_public_key_file` | `~/.ssh/id_rsa.pub` | SSH public key injected via cloud-init |

## Outputs

| Output | Description |
|--------|-------------|
| `vm_ip` | IP address leased on the `default` network |
| `ssh_command` | Ready-to-paste `ssh centos@<ip>` command |

## Usage

From the repository root, via the [Makefile](../Makefile):

```bash
make setup    # one-time: install KVM/libvirt + Terraform, create the storage pool
make apply    # create the VM
make ssh      # log in
make destroy  # tear it down
```

Or plain Terraform from this directory:

```bash
terraform init
terraform apply                                   # uses ~/.ssh/id_rsa.pub
terraform apply -var ssh_public_key_file=~/.ssh/id_ed25519.pub
$(terraform output -raw ssh_command)
terraform destroy
```
