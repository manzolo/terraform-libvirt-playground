# 1. Terraform + libvirt: how the pieces fit together

## The stack

```
┌─────────────────────────────┐
│  your .tf files (desired    │   "I want a VM with 2 CPUs,
│  state, declarative)        │    this disk, this network"
└──────────────┬──────────────┘
               │ terraform plan/apply
┌──────────────▼──────────────┐
│  terraform-provider-libvirt │   translates resources into
│  (dmacvicar/libvirt)        │   libvirt API calls
└──────────────┬──────────────┘
               │ qemu:///system
┌──────────────▼──────────────┐
│  libvirtd                   │   manages domains, networks,
│  (the libvirt daemon)       │   storage pools; same API used
└──────────────┬──────────────┘   by virsh and virt-manager
┌──────────────▼──────────────┐
│  QEMU + KVM                 │   QEMU emulates the machine,
│                             │   KVM accelerates it in-kernel
└─────────────────────────────┘
```

Everything Terraform does here could be done by hand with `virsh` or `virt-manager` —
the value is that the whole VM is **described in versionable text** and can be created,
reproduced and destroyed with one command.

## The Terraform lifecycle

| Command | What it does |
|---------|--------------|
| `terraform init` | Downloads the providers declared in `required_providers` into `.terraform/` and records their exact versions in `.terraform.lock.hcl` |
| `terraform plan` | Compares desired state (`.tf`) with known state (`terraform.tfstate`) and shows what would change |
| `terraform apply` | Executes the plan and updates the state file |
| `terraform destroy` | Removes everything the state says it created |

The **state file** (`terraform.tfstate`) is Terraform's memory: it maps your resource
names to real libvirt object IDs. It's local to your machine, may contain sensitive
values, and is git-ignored in this repo.

## Version pinning: a lesson learned the hard way

This repo pins the provider as:

```hcl
version = "~> 0.7.0"   # >= 0.7.0, < 0.8.0
```

and **not** `~> 0.7` (which means `>= 0.7, < 1.0`). Why it matters: the libvirt
provider **changed its whole resource schema in 0.8** — `libvirt_volume` lost
`source`/`format`, `libvirt_domain` grew a required `type`, and so on. With the loose
constraint, a fresh `terraform init` on a new machine would grab 0.9.x and every
resource in this repo would fail validation, while an old machine with a lock file
would keep working — the classic "works on my machine".

Two defenses, both used here:

1. a **pessimistic constraint** on the minor version (`~> 0.7.0`);
2. the **committed `.terraform.lock.hcl`**, which records the exact version + hashes
   so every `init` — including in CI — resolves identically.

## Reading the provider docs

The provider's resources are documented at
[registry.terraform.io/providers/dmacvicar/libvirt](https://registry.terraform.io/providers/dmacvicar/libvirt/0.7.6/docs)
— pick the version matching the lock file, precisely because of the schema break above.

Next: [2. Cloud images and cloud-init](02-cloud-init.md)
