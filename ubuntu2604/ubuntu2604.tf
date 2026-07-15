terraform {
  required_version = ">= 1.0"

  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      # ~> 0.7.0 (not ~> 0.7): the provider schema changed completely in 0.8
      version = "~> 0.7.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

variable "ssh_public_key_file" {
  description = "SSH public key injected into the VM via cloud-init"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "username" {
  description = "Admin user created by cloud-init (instead of the stock 'ubuntu' user)"
  type        = string
  default     = "manzolo"
}

variable "vm_hostname" {
  description = "VM hostname"
  type        = string
  default     = "ubuntu2604"
}

variable "vcpu" {
  description = "Number of virtual CPUs"
  type        = number
  default     = 4
}

variable "memory_mb" {
  description = "RAM in MiB"
  type        = number
  default     = 4096
}

variable "disk_size_gb" {
  description = "Root disk size in GiB (the cloud image is grown to this size)"
  type        = number
  default     = 20
}

variable "mac_address" {
  description = "Fixed MAC address, so the VM always gets the same DHCP lease"
  type        = string
  default     = "52:54:00:26:04:01"
}

# Pristine Ubuntu 26.04 LTS (Resolute Raccoon) cloud image, kept as a read-only base
resource "libvirt_volume" "ubuntu2604_base" {
  name   = "ubuntu-26.04-base.qcow2"
  pool   = "hd_pool"
  source = "https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img"
  format = "qcow2"
}

# Copy-on-write overlay used as the actual root disk, grown to disk_size_gb.
# Destroying/recreating the VM never re-downloads the base image.
resource "libvirt_volume" "ubuntu2604_root" {
  name           = "${var.vm_hostname}.qcow2"
  pool           = "hd_pool"
  base_volume_id = libvirt_volume.ubuntu2604_base.id
  size           = var.disk_size_gb * 1024 * 1024 * 1024
  format         = "qcow2"
}

resource "libvirt_cloudinit_disk" "ubuntu2604_init" {
  name = "${var.vm_hostname}-init.iso"
  pool = "hd_pool"
  user_data = templatefile("${path.module}/cloud_init.cfg", {
    hostname = var.vm_hostname
    username = var.username
    ssh_key  = trimspace(file(pathexpand(var.ssh_public_key_file)))
  })
}

resource "libvirt_domain" "ubuntu2604" {
  name      = var.vm_hostname
  memory    = var.memory_mb
  vcpu      = var.vcpu
  autostart = true # start the VM automatically with the host

  # Expose the host CPU model to the guest instead of the generic qemu64 one
  cpu {
    mode = "host-passthrough"
  }

  # Adds the virtio channel for qemu-guest-agent (installed by cloud-init),
  # so libvirt can query the guest directly (IP, fsfreeze, clean shutdown)
  qemu_agent = true

  cloudinit = libvirt_cloudinit_disk.ubuntu2604_init.id

  network_interface {
    network_name   = "default"
    mac            = var.mac_address
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.ubuntu2604_root.id
  }

  # Headless server: serial console only, no SPICE/VNC graphics
  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}

output "vm_ip" {
  description = "IP address leased to the VM on the default network"
  value       = try(libvirt_domain.ubuntu2604.network_interface[0].addresses[0], null)
}

output "ssh_command" {
  value = try("ssh ${var.username}@${libvirt_domain.ubuntu2604.network_interface[0].addresses[0]}", null)
}
