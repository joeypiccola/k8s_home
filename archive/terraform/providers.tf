# see .envrc for environment variables
provider "proxmox" {
  ssh {
    agent = true
  }
}
