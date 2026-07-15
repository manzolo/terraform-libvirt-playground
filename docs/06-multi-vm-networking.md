# 6. Multi-VM clusters and custom networks

The [`multivm/`](../multivm/) project builds a 3-node cluster on its own network.
Two new ideas do all the work: a **dedicated libvirt network** and **`for_each`**.

## A network of your own

The single-VM projects share libvirt's stock `default` network. A cluster deserves
its own segment:

```hcl
resource "libvirt_network" "lab" {
  name      = "lab"
  mode      = "nat"                 # like 'default': guests reach out, isolated from your LAN
  domain    = "lab.local"
  addresses = ["10.17.3.0/24"]

  dhcp { enabled = true }
  dns {
    enabled    = true
    local_only = true               # lab.local queries never leave this network
  }
}
```

Behind the scenes libvirt spawns a new bridge and a dedicated dnsmasq for it —
exactly like `default`, but under your control. Other `mode`s worth knowing:
`none` (fully isolated, no NAT — great for testing failure scenarios), `route`
(routed to the LAN without NAT), and bridged setups for VMs that should appear
as first-class citizens on your physical network.

## Static IPs, the DHCP way

There are two ways to give VMs fixed addresses:

1. **Static config inside the guest** (netplan via cloud-init `network_config`) —
   works, but the address lives in the guest, invisible to libvirt, and
   `wait_for_lease` no longer makes sense (there is no lease).
2. **DHCP reservations in the network** — the approach used here. The IP is part of
   the *infrastructure* definition, dnsmasq always hands the same address to the
   node, and DNS registration comes for free:

```hcl
network_interface {
  network_id     = libvirt_network.lab.id
  hostname       = each.key      # dnsmasq registers node1.lab.local
  addresses      = [each.value]  # ...and always leases this IP
  wait_for_lease = true
}
```

Because dnsmasq is also the nodes' DNS server, **every node resolves every other
node by name** — `ping node2` just works. The CI smoke test proves it: the project
exposes a `smoke_check` output that the workflow runs inside node1, pinging all
nodes by hostname.

## Stamping out nodes with `for_each`

The whole cluster layout is one variable:

```hcl
variable "nodes" {
  type = map(string)
  default = {
    node1 = "10.17.3.11"
    node2 = "10.17.3.12"
    node3 = "10.17.3.13"
  }
}
```

Volume, cloud-init disk and domain all iterate over it:

```hcl
resource "libvirt_domain" "node" {
  for_each = var.nodes
  name     = "lab-${each.key}"
  # ...
}
```

Want a 5-node cluster? Add two lines to the map and `terraform apply` creates
exactly the two missing nodes — the others are untouched. Remove a line and only
that node is destroyed. This is the essence of declarative infrastructure:
**you edit the description, Terraform computes the diff.**

`for_each` vs `count`: with `count` nodes are identified by position (`node[0]`,
`node[1]`…), so deleting the first one *renames* all the others and Terraform
rebuilds them. With `for_each` identity is the map key — removing `node2` touches
only `node2`. For anything with a stable identity, prefer `for_each`.

### One base image, N overlays

The nodes share a single downloaded base image; each gets its own thin
copy-on-write overlay ([chapter 3](03-networking-and-storage.md)). Three nodes
cost one download plus three near-empty qcow2 files — this pattern is what makes
multi-VM labs cheap.

## Collection outputs

With `for_each`, outputs naturally become maps:

```hcl
output "vm_ips" {
  value = { for name, d in libvirt_domain.node : name => d.network_interface[0].addresses[0] }
}
```

```
$ terraform output vm_ips
{ node1 = "10.17.3.11", node2 = "10.17.3.12", node3 = "10.17.3.13" }
```

The project also exposes a scalar `ssh_command` (pointing at the first node) so that
generic tooling — `make ssh`, the CI smoke test — works unchanged on a cluster.

## Where to go from here

- Give roles to nodes (a load balancer + web servers) with per-role cloud-init
  templates chosen via a second map.
- Attach a second `network_interface` to build a separate "storage" network —
  VMs can sit on as many networks as you like.
- Point an Ansible inventory at `terraform output -json vm_ips` and configure the
  cluster properly: Terraform builds the machines, Ansible builds what's on them.

Back to the [README](../README.md).
