# 4. Troubleshooting

Every problem below was hit **for real** while building this repo (most of them
caught by the [CI smoke test](05-ci-github-actions.md)). Symptoms first, then fix.

## `mkisofs: executable file not found in $PATH`

```
Error: error while starting the creation of CloudInit's ISO image:
exec: "mkisofs": executable file not found in $PATH
```

The provider shells out to `mkisofs` to build the cloud-init seed ISO, and most
distros don't ship it. On Debian/Ubuntu the tool lives in the `genisoimage` package
under a different name, so install it and add a compatibility symlink:

```bash
sudo apt install genisoimage
sudo ln -s "$(command -v genisoimage)" /usr/local/bin/mkisofs
```

`make setup` does this for you.

## `Could not open '...qcow2': Permission denied` when the domain starts

The volume exists, terraform created it fine, but QEMU itself can't open it. Two
usual suspects:

1. **AppArmor/SELinux** — libvirt generates a security profile per domain; custom
   pool paths sometimes aren't covered. Check `dmesg | grep -i denied` or
   `/var/log/audit/`. On a throwaway environment (like a CI runner) you can disable
   the libvirt security driver:

   ```bash
   echo 'security_driver = "none"' | sudo tee -a /etc/libvirt/qemu.conf
   sudo systemctl restart libvirtd
   ```

   **Don't do this on a real host** — fix the AppArmor profile instead.

2. **File ownership** — QEMU runs as `libvirt-qemu`, and a volume created with odd
   permissions may be unreadable. `sudo chown libvirt-qemu:kvm <file>` or check
   `dynamic_ownership` in `qemu.conf`.

## `Unsupported argument` / `Blocks of type "..." are not expected here`

Your `.tf` files are written for provider 0.7.x but `terraform init` fetched 0.8+,
which redesigned the whole schema. See
[the version-pinning section of chapter 1](01-terraform-libvirt-basics.md#version-pinning-a-lesson-learned-the-hard-way).
Fix: pin `version = "~> 0.7.0"` and commit `.terraform.lock.hcl`. If you already
init'ed the wrong version: `rm -rf .terraform .terraform.lock.hcl && terraform init`.

## Permission denied talking to `qemu:///system`

Your user isn't in the `libvirt` group (or the membership hasn't taken effect):

```bash
sudo usermod -aG libvirt $USER
newgrp libvirt        # or log out and back in
```

## `apply` hangs on "Still creating..." for the domain

Almost always `wait_for_lease = true` waiting forever:

- the VM didn't boot (check `virsh list --all`, then `make console`);
- the `default` network is down (`virsh net-list`);
- the guest has no DHCP client on that interface (e.g. you configured a static IP —
  remove `wait_for_lease` in that case).

## SSH: `Permission denied (publickey)`

- Wrong key: did `apply` pick up the right `ssh_public_key_file`? (default
  `~/.ssh/id_rsa.pub`)
- Wrong user: `centos` for the CentOS image, whatever `var.username` says for Ubuntu.
- cloud-init failed silently: `make console`, then `cloud-init status --long`
  ([chapter 2](02-cloud-init.md#debugging-cloud-init)).

## General diagnostic toolbox

```bash
virsh list --all                  # domain states
virsh console <name>              # watch it boot (Ctrl+] to exit)
virsh net-dhcp-leases default     # DHCP leases
virsh vol-list hd_pool            # volumes
journalctl -u libvirtd -e         # daemon logs
TF_LOG=DEBUG terraform apply      # very verbose provider logs
```

Next: [5. CI with GitHub Actions](05-ci-github-actions.md)
