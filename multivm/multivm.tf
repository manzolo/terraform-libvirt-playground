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
  description = "SSH public key injected into every node via cloud-init"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "username" {
  description = "Admin user created by cloud-init on every node"
  type        = string
  default     = "manzolo"
}

# The cluster layout: node name -> static IP on the lab network.
# Add or remove entries and re-apply — Terraform reconciles the rest.
variable "nodes" {
  description = "Map of node name to static IP on the lab network"
  type        = map(string)
  default = {
    node1 = "10.17.3.11"
    node2 = "10.17.3.12"
    node3 = "10.17.3.13"
  }
}

variable "node_vcpu" {
  description = "Virtual CPUs per node"
  type        = number
  default     = 1
}

variable "node_memory_mb" {
  description = "RAM per node in MiB"
  type        = number
  default     = 1024
}

variable "node_disk_gb" {
  description = "Root disk size per node in GiB"
  type        = number
  default     = 10
}

# A dedicated NAT network for the cluster, instead of libvirt's 'default'.
# Its embedded dnsmasq provides DHCP (with static reservations, below) and
# DNS: every node can reach the others by name.
resource "libvirt_network" "lab" {
  name      = "lab"
  mode      = "nat"
  domain    = "lab.local"
  addresses = ["10.17.3.0/24"]
  autostart = true

  dhcp {
    enabled = true
  }

  dns {
    enabled    = true
    local_only = true # queries for lab.local never leave this network
  }
}

# One shared pristine base image...
resource "libvirt_volume" "lab_base" {
  name   = "lab-ubuntu-26.04-base.qcow2"
  pool   = "hd_pool"
  source = "https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img"
  format = "qcow2"
}

# ...and one thin copy-on-write overlay per node.
resource "libvirt_volume" "node_root" {
  for_each = var.nodes

  name           = "lab-${each.key}.qcow2"
  pool           = "hd_pool"
  base_volume_id = libvirt_volume.lab_base.id
  size           = var.node_disk_gb * 1024 * 1024 * 1024
  format         = "qcow2"
}

# One cloud-init seed per node — same template, different hostname.
resource "libvirt_cloudinit_disk" "node_init" {
  for_each = var.nodes

  name = "lab-${each.key}-init.iso"
  pool = "hd_pool"
  user_data = templatefile("${path.module}/cloud_init.cfg", {
    hostname = each.key
    username = var.username
    ssh_key  = trimspace(file(pathexpand(var.ssh_public_key_file)))
  })
}

resource "libvirt_domain" "node" {
  for_each = var.nodes

  name   = "lab-${each.key}"
  memory = var.node_memory_mb
  vcpu   = var.node_vcpu

  cloudinit = libvirt_cloudinit_disk.node_init[each.key].id

  network_interface {
    network_id = libvirt_network.lab.id
    hostname   = each.key     # registered in the network's DNS
    addresses  = [each.value] # static DHCP reservation for this node
    # With a reservation in place the 'lease' is deterministic, but the
    # node still has to boot and DHCP before apply completes:
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.node_root[each.key].id
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}

output "vm_ips" {
  description = "Node name -> IP on the lab network"
  value       = { for name, d in libvirt_domain.node : name => try(d.network_interface[0].addresses[0], null) }
}

# First node (alphabetically) — lets generic tooling ('make ssh', the CI
# smoke test) treat this project like the single-VM ones.
output "ssh_command" {
  value = "ssh ${var.username}@${var.nodes[sort(keys(var.nodes))[0]]}"
}

# Executed inside the first node by the CI smoke test: proves that every
# node resolves and reaches every other node by name over the lab network.
output "smoke_check" {
  value = join(" && ", [for name in sort(keys(var.nodes)) : "ping -c 1 -W 3 ${name}"])
}
