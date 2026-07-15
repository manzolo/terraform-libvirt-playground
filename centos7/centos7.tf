terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"

  # To target a remote hypervisor over SSH instead:
  # uri = "qemu+ssh://root@192.168.100.10/system"
}

variable "ssh_public_key_file" {
  description = "SSH public key injected into the VM via cloud-init"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

# VM root disk, backed by the official CentOS 7 cloud image
resource "libvirt_volume" "centos7_qcow2" {
  name   = "centos7.qcow2"
  pool   = "hd_pool" # list storage pools with: virsh pool-list
  source = "https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2"
  # source = "./CentOS-7-x86_64-GenericCloud.qcow2" # use a local copy instead
  format = "qcow2"
}

# Cloud-init seed disk: creates the 'centos' user with your SSH key
resource "libvirt_cloudinit_disk" "centos7_init" {
  name = "centos7-init.iso"
  pool = "hd_pool"
  user_data = templatefile("${path.module}/cloud_init.cfg", {
    ssh_key = trimspace(file(pathexpand(var.ssh_public_key_file)))
  })
}

# KVM domain (the VM itself)
resource "libvirt_domain" "centos7" {
  name   = "centos7"
  memory = 2048
  vcpu   = 2

  cloudinit = libvirt_cloudinit_disk.centos7_init.id

  network_interface {
    network_name   = "default" # list networks with: virsh net-list
    wait_for_lease = true      # block until the VM gets a DHCP lease, so we can output its IP
  }

  disk {
    volume_id = libvirt_volume.centos7_qcow2.id
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

output "vm_ip" {
  description = "IP address leased to the VM on the default network"
  value       = try(libvirt_domain.centos7.network_interface[0].addresses[0], null)
}

output "ssh_command" {
  value = try("ssh centos@${libvirt_domain.centos7.network_interface[0].addresses[0]}", null)
}

