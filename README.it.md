# terraform-libvirt-playground

[![CI](https://github.com/manzolo/terraform-libvirt-playground/actions/workflows/ci.yml/badge.svg)](https://github.com/manzolo/terraform-libvirt-playground/actions/workflows/ci.yml)
[![Smoke test (KVM)](https://github.com/manzolo/terraform-libvirt-playground/actions/workflows/smoke-test.yml/badge.svg)](https://github.com/manzolo/terraform-libvirt-playground/actions/workflows/smoke-test.yml)

[🇬🇧 English](README.md) · 🇮🇹 Italiano

Esperimenti Terraform per creare macchine virtuali KVM/QEMU locali tramite il provider
[dmacvicar/libvirt](https://registry.terraform.io/providers/dmacvicar/libvirt/latest) —
infrastructure-as-code sulla propria workstation, senza bisogno di alcun account cloud.

L'obiettivo: descrivere una VM (disco, CPU/RAM, rete, console) in un unico file `.tf` e
lasciare che `terraform apply` faccia tutto ciò che si farebbe a mano con `virt-install` —
scaricare l'immagine cloud, creare il volume nello storage pool, definire e avviare il
dominio libvirt.

## Progetti — un percorso in due tappe

| Cartella | Livello | Descrizione |
|----------|---------|-------------|
| [`centos7/`](centos7/) | base | Tutto ai valori di default: un volume dall'immagine cloud ufficiale, 2 vCPU / 2 GB, DHCP sulla rete `default`, cloud-init minimale (utente + chiave SSH) |
| [`ubuntu2604/`](ubuntu2604/) | avanzato | Ubuntu 26.04 LTS con i parametri personalizzati: disco overlay copy-on-write espanso a 20 GiB, CPU host-passthrough, qemu-guest-agent, MAC fisso, autostart, headless, utente/timezone/pacchetti custom, dimensioni configurabili via variabili |

Il README di ogni progetto spiega le scelte fatte; la [documentazione](#documentazione)
spiega i concetti.

> **Nota:** CentOS 7 è end-of-life dal 30 giugno 2024. Quel progetto resta come
> riferimento minimale — per qualcosa di reale partite da `ubuntu2604/`.

## Documentazione

Percorso guidato ai concetti, in ordine (in inglese):

1. [Terraform + libvirt: come si incastrano i pezzi](docs/01-terraform-libvirt-basics.md) — lo stack, il ciclo di vita, lo state e perché le versioni del provider vanno pinnate
2. [Immagini cloud e cloud-init](docs/02-cloud-init.md) — perché non c'è un installer ISO, la ISO seed NoCloud, anatomia dello user-data, debug
3. [Rete e storage](docs/03-networking-and-storage.md) — la rete NAT `default`, i lease DHCP, pool, volumi e overlay COW
4. [Troubleshooting](docs/04-troubleshooting.md) — ogni errore incontrato davvero costruendo questo repo, con relativa soluzione
5. [CI con GitHub Actions](docs/05-ci-github-actions.md) — lint/validate a ogni push, e vere VM KVM avviate sui runner GitHub

## Avvio rapido

Su Debian/Ubuntu è tutto automatizzato dal [Makefile](Makefile):

```bash
make setup    # una tantum: installa KVM/libvirt + Terraform, abilita la rete
              # default, crea lo storage pool hd_pool, ti aggiunge al gruppo libvirt
make apply    # crea la VM
make ssh      # entra come 'centos'
make destroy  # smonta tutto
```

Tutti i target (vedi `make help`):

| Target | Descrizione |
|--------|-------------|
| `setup` | Installa i prerequisiti e prepara libvirt (rete, storage pool, gruppo) |
| `pool` | Crea solo lo storage pool `hd_pool` se manca |
| `init` / `fmt` / `validate` / `plan` / `apply` / `destroy` | Il ciclo di vita Terraform |
| `ip` | Stampa l'indirizzo IP della VM |
| `ssh` | Entra in SSH nella VM |
| `console` | Console seriale (uscita con `Ctrl+]`) |
| `viewer` | Console grafica SPICE |
| `clean` | Rimuove gli artefatti Terraform locali (**non** distrugge la VM) |

I target operano su `centos7/` di default; per un altro progetto:
`make apply PROJECT=ubuntu2604`.

> Dopo `make setup`, fare logout e login (oppure `newgrp libvirt`) perché
> l'appartenenza al gruppo `libvirt` abbia effetto.

## Prerequisiti (percorso manuale)

Se si preferisce non usare `make setup`:

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.0
- Un ambiente libvirt/KVM funzionante (`qemu-kvm`, `libvirt-daemon-system`, `virsh`)
- `mkisofs` per generare la ISO seed di cloud-init (su Debian/Ubuntu: `apt install
  genisoimage`, poi symlink: `ln -s $(command -v genisoimage) /usr/local/bin/mkisofs`)
- Il proprio utente nel gruppo `libvirt`
- Uno storage pool chiamato `hd_pool` (verificare con `virsh pool-list`; oppure `make pool`)
- La rete libvirt `default` attiva (`virsh net-list`)

## Uso con Terraform puro

```bash
cd centos7
terraform init
terraform plan
terraform apply
```

Di default cloud-init inietta `~/.ssh/id_rsa.pub`; per usare un'altra chiave:

```bash
terraform apply -var ssh_public_key_file=~/.ssh/id_ed25519.pub
```

Connessione alla VM — `apply` attende il lease DHCP e stampa l'IP come output:

```bash
$(terraform output -raw ssh_command)   # SSH
virsh console centos7                  # console seriale (Ctrl+] per uscire)
```

## CI

Due workflow GitHub Actions in [`.github/workflows/`](.github/workflows/):

- **CI** ([`ci.yml`](.github/workflows/ci.yml)) — a ogni push e PR: `terraform fmt -check`,
  poi `terraform validate` e [tflint](https://github.com/terraform-linters/tflint) su ogni
  cartella progetto. Veloce, senza credenziali.
- **Smoke test (KVM)** ([`smoke-test.yml`](.github/workflows/smoke-test.yml)) — solo
  manuale (`workflow_dispatch`). I runner Linux di GitHub espongono `/dev/kvm`, quindi il
  test fa tutto per davvero, un job per progetto via matrix: `make setup` su un runner
  vuoto, `terraform apply`, SSH nella VM appena avviata per verificare cloud-init, poi
  `terraform destroy`.

Entrambi sono analizzati in [docs/05-ci-github-actions.md](docs/05-ci-github-actions.md).

## Note

- Il provider parla con l'hypervisor locale via `uri = "qemu:///system"`. Per gestire un
  host **remoto**: `qemu+ssh://utente@host/system`.
- Le immagini cloud non hanno password di default: il login è gestito da cloud-init, che
  crea l'utente con la chiave SSH pubblica, sudo senza password e auto-espansione della
  partizione root. L'autenticazione a password resta disabilitata.
- I file di state (`terraform.tfstate`) sono volutamente esclusi da git.

## Licenza

MIT
