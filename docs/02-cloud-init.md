# 2. Cloud images and cloud-init

## Why no ISO installer?

The traditional way to build a VM is to boot an installer ISO and answer questions.
Cloud providers can't do that at scale, so every major distro also publishes
**cloud images**: pre-installed, minimal qcow2 disks that boot in seconds.

- CentOS: `CentOS-7-x86_64-GenericCloud.qcow2`
- Ubuntu: `ubuntu-26.04-server-cloudimg-amd64.img`

The catch: they ship with **no usable login** — no root password, no default user
password. They expect to be configured on first boot by **cloud-init**.

## How cloud-init finds its configuration

cloud-init probes a list of *datasources* at boot: EC2 metadata, Azure, GCP… and, last,
**NoCloud**: a disk labeled `cidata` containing two files, `user-data` and `meta-data`.

That's exactly what `libvirt_cloudinit_disk` builds — it renders your configuration
into a small ISO (using `mkisofs`) and attaches it as a CD-ROM:

```hcl
resource "libvirt_cloudinit_disk" "init" {
  name      = "vm-init.iso"
  pool      = "hd_pool"
  user_data = templatefile("${path.module}/cloud_init.cfg", { ssh_key = "..." })
}

resource "libvirt_domain" "vm" {
  cloudinit = libvirt_cloudinit_disk.init.id
  # ...
}
```

## Anatomy of our user-data

From [`ubuntu2604/cloud_init.cfg`](../ubuntu2604/cloud_init.cfg) (templated by
Terraform's `templatefile()`, so `${username}` etc. come from variables):

```yaml
#cloud-config                     # this first line is mandatory!
hostname: ${hostname}

users:
  - name: ${username}             # custom admin user (default would be 'ubuntu')
    sudo: ALL=(ALL) NOPASSWD:ALL  # passwordless sudo
    shell: /bin/bash
    ssh_authorized_keys:
      - ${ssh_key}                # your public key, injected by Terraform

ssh_pwauth: false                 # SSH keys only, no passwords
timezone: Europe/Rome

package_update: true              # apt update on first boot...
packages:                         # ...then install extras
  - qemu-guest-agent
  - htop

runcmd:                           # arbitrary commands, run once at the end
  - systemctl enable --now qemu-guest-agent

growpart:
  mode: auto                      # expand the root partition to fill the disk
  devices: ["/"]                  # (the image is ~2 GB, our disk is 20 GB)
```

## Debugging cloud-init

If the VM boots but SSH never works, log in via the serial console
(`make console`) and check:

```bash
cloud-init status --long          # done / running / error
sudo cat /var/log/cloud-init.log  # full trace
sudo cloud-init query userdata    # what user-data did it actually receive?
```

A malformed `#cloud-config` (even a YAML indentation error) fails **silently** —
the VM boots normally, it just skips your configuration.

Next: [3. Networking and storage](03-networking-and-storage.md)
