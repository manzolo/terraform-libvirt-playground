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

# VM root disk, backed by the official CentOS 7 cloud image
resource "libvirt_volume" "centos7_qcow2" {
  name   = "centos7.qcow2"
  pool   = "hd_pool" # list storage pools with: virsh pool-list
  source = "https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2"
  # source = "./CentOS-7-x86_64-GenericCloud.qcow2" # use a local copy instead
  format = "qcow2"
}

# KVM domain (the VM itself)
resource "libvirt_domain" "centos7" {
  name   = "centos7"
  memory = 2048
  vcpu   = 2

  network_interface {
    network_name = "default" # list networks with: virsh net-list
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

