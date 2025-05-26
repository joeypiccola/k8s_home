locals {
  talos_version          = "v1.9.1"
  talos_cluster_name     = "talos-dev"
  talos_cluster_endpoint = "https://talos-dev.k8s.piccola.us:6443"
  virtual_talos_nodes    = [ for node in local.talos_nodes : node if node.virtual ]
  physical_talos_nodes   = [ for node in local.talos_nodes : node if node.virtual == false ]
  console_logging        = "" # "e88202574e1c65f86d35d171ab7f08eddbe6c8e78cb45b9cb0470d6b0c394876"
  talos_nodes            = [
    # {
    #   hostname = "control-dev-1.k8s.piccola.us"
    #   ip       = "10.0.5.226"
    #   vm_id    = 201
    #   virtual  = true
    # },
    # {
    #   hostname = "control-dev-2.k8s.piccola.us"
    #   ip       = "10.0.5.227"
    #   vm_id    = 202
    #   virtual  = true
    # },
    # {
    #   hostname = "control-dev-3.k8s.piccola.us"
    #   ip       = "10.0.5.228"
    #   vm_id    = 203
    #   virtual  = true
    # }
  ]
}

data "talos_image_factory_extensions_versions" "virtual" {
  talos_version = local.talos_version
  filters = {
    names = [
      "iscsi-tools",
      "qemu-guest-agent"
    ]
  }
}

data "talos_image_factory_extensions_versions" "physical" {
  talos_version = local.talos_version
  filters = {
    names = [
      "iscsi-tools",
      "i915"
    ]
  }
}

resource "talos_image_factory_schematic" "virtual" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = data.talos_image_factory_extensions_versions.virtual.extensions_info.*.name
        }
      }
    }
  )
}

resource "talos_image_factory_schematic" "physical" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = data.talos_image_factory_extensions_versions.physical.extensions_info.*.name
        }
      }
    }
  )
}

resource "proxmox_virtual_environment_download_file" "talos_image" {
  content_type = "iso"
  datastore_id = "isos"
  node_name    = "pve"
  url          = format("https://factory.talos.dev/image/%s/%s/nocloud-amd64.iso",
    talos_image_factory_schematic.virtual.id,
    data.talos_image_factory_extensions_versions.virtual.talos_version
  )
}

resource "proxmox_virtual_environment_vm" "talos_nodes" {
  for_each = { for node in local.virtual_talos_nodes : node.hostname => node }

  name            = each.value.hostname
  node_name       = "pve"
  scsi_hardware   = "virtio-scsi-single"
  stop_on_destroy = true
  tags            = sort(["terraform", "linux", "kubernetes", "talos"])
  vm_id           = each.value.vm_id

  agent {
    enabled = true
  }
  cpu {
    cores = 4
    type  = "x86-64-v2-AES"
  }
  memory {
    dedicated = 16384
    floating  = 16384
  }
  disk {
    datastore_id = "local-nvme"
    file_id      = proxmox_virtual_environment_download_file.talos_image.id
    interface    = "scsi0"
    size         = 40
    iothread     = true
    ssd          = true
    discard      = "on"
    file_format  = "raw"
  }
  disk {
    datastore_id = "local-nvme"
    interface    = "scsi1"
    size         = 100
    iothread     = true
    ssd          = true
    discard      = "on"
    file_format  = "raw"
  }
  efi_disk {
    datastore_id = "local-nvme"
    file_format  = "raw"
    type         = "4m"
  }
  network_device {
    bridge      = "vmbr1"
    firewall    = true
    mac_address = format("6A:6F:65:79:70:0%s", substr(each.value.vm_id, 2, 1)) # j:o:e:y:p:x
    model       = "virtio"
    vlan_id     = "5"
  }
  operating_system {
    type = "l26"
  }
}
