# 3. Networking and storage in libvirt

## The `default` network

Out of the box libvirt provides a NAT network called `default`:

```
VM (192.168.122.x) ──▶ virbr0 bridge (192.168.122.1) ──▶ NAT ──▶ your LAN/internet
```

- The host runs a `dnsmasq` instance on `virbr0` serving **DHCP + DNS** to guests.
- Guests can reach the outside; the outside cannot reach guests (it's NAT).
- The host *can* reach guests directly — that's why `ssh centos@192.168.122.x` works.

Useful commands:

```bash
virsh net-list --all                     # is 'default' active?
virsh net-start default                  # start it
virsh net-dhcp-leases default            # who got which IP
```

### `wait_for_lease` and fixed MACs

In Terraform, `wait_for_lease = true` makes `apply` block until the guest obtains a
DHCP lease, which lets us expose the IP as an output:

```hcl
network_interface {
  network_name   = "default"
  mac            = "52:54:00:26:04:01"  # optional: fixed MAC
  wait_for_lease = true
}

output "vm_ip" {
  value = libvirt_domain.vm.network_interface[0].addresses[0]
}
```

A **fixed MAC** (the `52:54:00` prefix is QEMU's) means dnsmasq will usually hand the
same IP back after every rebuild — handy for muscle-memory SSH. Note that
`wait_for_lease` only makes sense with DHCP: if you configured a static IP inside the
guest, `apply` would hang waiting for a lease that never comes.

## Storage: pools, volumes and overlays

A **pool** is just a managed location for disk images (here: a plain directory);
a **volume** is one disk image inside it.

```bash
virsh pool-list                          # hd_pool should be active
virsh vol-list hd_pool                   # volumes in it
```

`make pool` creates `hd_pool` as a directory pool under
`/var/lib/libvirt/images/hd_pool`.

### Simple volume (centos7 project)

```hcl
resource "libvirt_volume" "root" {
  name   = "centos7.qcow2"
  pool   = "hd_pool"
  source = "https://cloud.centos.org/..."   # downloaded straight into the pool
  format = "qcow2"
}
```

One volume, downloaded and used directly. Destroy the VM → the volume goes with it →
next `apply` downloads the image again.

### Base + copy-on-write overlay (ubuntu2604 project)

```hcl
resource "libvirt_volume" "base" {          # pristine image, read-only in practice
  name   = "ubuntu-26.04-base.qcow2"
  source = "https://cloud-images.ubuntu.com/..."
}

resource "libvirt_volume" "root" {          # the VM's actual disk
  name           = "ubuntu2604.qcow2"
  base_volume_id = libvirt_volume.base.id   # qcow2 backing file
  size           = 20 * 1024 * 1024 * 1024  # grown to 20 GiB
}
```

The overlay starts as a few KB and only stores blocks the VM *changes* — reads of
untouched blocks fall through to the base image. Benefits:

- rebuilding the VM (`destroy` + `apply`) is instant — no re-download;
- multiple VMs can share one base image, each with its own thin overlay;
- `size` grows the virtual disk; cloud-init's `growpart` then expands the
  root filesystem into that extra space at first boot.

This is the same copy-on-write idea used by container image layers.

Next: [4. Troubleshooting](04-troubleshooting.md)
