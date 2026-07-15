# Terraform + libvirt playground
# Run `make help` for a list of targets.
#
# PROJECT selects the subdirectory to operate on (default: centos7):
#   make apply PROJECT=centos7

PROJECT ?= centos7
TF      := terraform -chdir=$(PROJECT)
POOL    ?= hd_pool
POOL_DIR ?= /var/lib/libvirt/images/$(POOL)

.PHONY: help setup pool init fmt validate plan apply destroy ip ssh console viewer clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

setup: ## Install prerequisites (Debian/Ubuntu): KVM/libvirt, Terraform, group, default network + storage pool
	sudo apt-get update
	sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst virt-viewer genisoimage
	@command -v mkisofs >/dev/null 2>&1 || sudo ln -s "$$(command -v genisoimage)" /usr/local/bin/mkisofs
	@command -v terraform >/dev/null 2>&1 || { \
		echo "==> Installing Terraform from the HashiCorp apt repository"; \
		wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg; \
		echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $$(lsb_release -cs) main" \
			| sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null; \
		sudo apt-get update && sudo apt-get install -y terraform; \
	}
	sudo usermod -aG libvirt $$USER
	sudo virsh net-autostart default >/dev/null 2>&1 || true
	sudo virsh net-start default >/dev/null 2>&1 || true
	$(MAKE) pool
	@echo
	@echo "==> Setup complete. Log out and back in (or run 'newgrp libvirt') for group membership to apply."

pool: ## Create the storage pool (POOL, default hd_pool) if it doesn't exist
	@sudo virsh pool-info $(POOL) >/dev/null 2>&1 || { \
		echo "==> Creating storage pool '$(POOL)' at $(POOL_DIR)"; \
		sudo virsh pool-define-as $(POOL) dir --target $(POOL_DIR); \
		sudo virsh pool-build $(POOL); \
		sudo virsh pool-start $(POOL); \
		sudo virsh pool-autostart $(POOL); \
	}
	@sudo virsh pool-info $(POOL)

init: ## terraform init
	$(TF) init

fmt: ## terraform fmt
	$(TF) fmt

validate: init ## terraform validate
	$(TF) validate

plan: init ## terraform plan
	$(TF) plan

apply: init ## Create the VM (terraform apply)
	$(TF) apply

destroy: ## Destroy the VM (terraform destroy)
	$(TF) destroy

ip: ## Print the VM IP address
	@$(TF) output -raw vm_ip

ssh: ## SSH into the VM as 'centos'
	@$$($(TF) output -raw ssh_command)

console: ## Attach to the serial console (exit with Ctrl+])
	virsh -c qemu:///system console $(PROJECT)

viewer: ## Open the SPICE graphical console
	virt-viewer -c qemu:///system $(PROJECT)

clean: ## Remove local Terraform artifacts (providers, state) — does NOT destroy the VM
	rm -rf $(PROJECT)/.terraform $(PROJECT)/terraform.tfstate $(PROJECT)/terraform.tfstate.backup
