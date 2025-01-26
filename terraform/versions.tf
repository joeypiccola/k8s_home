terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.69.1"
    }
    talos = {
      source = "siderolabs/talos"
      version = "0.7.0"
    }
  }
  required_version = "~> 1.10.5"
}
