# multivm

A 3-node Ubuntu 26.04 cluster on a dedicated libvirt network — the **multi-VM**
project of this playground. The concepts (custom networks, DHCP reservations,
`for_each`) are explained in [docs/06-multi-vm-networking.md](../docs/06-multi-vm-networking.md).

## What it creates

| Resource | Details |
|----------|---------|
| `libvirt_network.lab` | NAT network `10.17.3.0/24`, domain `lab.local`, DHCP + local DNS: nodes reach each other by name |
| `libvirt_volume.lab_base` | One shared Ubuntu 26.04 base image |
| `libvirt_volume.node_root` (×N) | Thin copy-on-write overlay per node, 10 GiB |
| `libvirt_cloudinit_disk.node_init` (×N) | Per-node seed ISO (same template, different hostname) |
| `libvirt_domain.node` (×N) | 1 vCPU / 1 GiB nodes with static DHCP reservations |

The default layout (`var.nodes`):

```
node1 = 10.17.3.11      node2 = 10.17.3.12      node3 = 10.17.3.13
```

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `nodes` | node1..node3, see above | Map name → static IP; **edit this to scale the cluster** |
| `username` | `manzolo` | Admin user on every node |
| `ssh_public_key_file` | `~/.ssh/id_rsa.pub` | SSH public key |
| `node_vcpu` / `node_memory_mb` / `node_disk_gb` | 1 / 1024 / 10 | Per-node sizing |

## Outputs

| Output | Description |
|--------|-------------|
| `vm_ips` | Map node name → IP |
| `ssh_command` | SSH to the first node (keeps `make ssh` and CI generic) |
| `smoke_check` | Command the CI runs inside node1: ping every node by hostname |

## Usage

```bash
# from the repo root
make apply PROJECT=multivm
make ssh PROJECT=multivm          # lands on node1

# from node1, names resolve via the network's DNS:
ping node2
ssh node3.lab.local               # (agent-forward or copy a key first)

# scale to 5 nodes without touching the .tf files:
terraform -chdir=multivm apply \
  -var 'nodes={node1="10.17.3.11",node2="10.17.3.12",node3="10.17.3.13",node4="10.17.3.14",node5="10.17.3.15"}'

make destroy PROJECT=multivm
```

Note: `make console PROJECT=multivm` won't work as-is — domains are named
`lab-node1`… (`virsh console lab-node1`).
