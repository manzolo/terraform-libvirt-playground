# terraform-libvirt-playground

Terraform experiments for provisioning local KVM/QEMU virtual machines through the
[dmacvicar/libvirt](https://registry.terraform.io/providers/dmacvicar/libvirt/latest) provider —
infrastructure-as-code on your own workstation, no cloud account required.

The goal: describe a VM (disk image, CPU/RAM, network, console) in a single `.tf` file and let
`terraform apply` do everything `virt-install` would do by hand — download the cloud image,
create the volume in a storage pool, define and boot the libvirt domain.

## Projects

| Directory | Description |
|-----------|-------------|
| [`centos7/`](centos7/) | A CentOS 7 VM (2 vCPU, 2 GB RAM) built from the official GenericCloud qcow2 image, attached to the `default` libvirt network, with serial console and SPICE graphics |

> **Note:** CentOS 7 reached end-of-life on June 30, 2024. This project is kept as a
> reference/playground — swap the image `source` for a current distro (AlmaLinux, Rocky,
> Ubuntu cloud images) for real use.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.0
- A working libvirt/KVM setup (`qemu-kvm`, `libvirt-daemon-system`, `virsh`)
- Your user in the `libvirt` group (or run against `qemu:///system` with proper polkit rules)
- A storage pool named `hd_pool` (check with `virsh pool-list`; adjust `pool` in the `.tf` file
  to match yours, e.g. `default`)
- The `default` libvirt network active (`virsh net-list`)

## Usage

```bash
cd centos7
terraform init
terraform plan
terraform apply
```

Connect to the VM:

```bash
# Serial console (exit with Ctrl+])
virsh console centos7

# Or via SPICE
virt-viewer centos7
```

Tear everything down:

```bash
terraform destroy
```

## Notes

- The provider talks to the local hypervisor via `uri = "qemu:///system"`. To manage a **remote**
  host, switch the URI to `qemu+ssh://user@host/system` (commented example in the `.tf` file).
- The cloud image ships without a default password. To actually log in you'll want to attach a
  cloud-init disk (`libvirt_cloudinit_disk` resource) with your SSH key — left as the natural
  next experiment for this playground.
- State files (`terraform.tfstate`) are intentionally git-ignored.

## License

MIT
