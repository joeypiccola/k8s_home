locals {
  talhelper_working_dir = "../talos"

  vmware_config = {
    folder = var.vsphere_folder
    node_hardware_config = {
      worker = {
        memory = 16384
        num_cpus = 4
        disk_size = 50
        longhorn_disk_size = 100
      }
      controlplane = {
        memory = 16384
        num_cpus = 4
        disk_size = 50
        longhorn_disk_size = 100
      }
    }
  }

  talhelper_clusterconfig_path  = "${local.talhelper_working_dir}/clusterconfig"
  talhelper_clusterconfig_files = fileset(local.talhelper_clusterconfig_path, "${local.talhelper_clusterName}-*")
  talhelper_talenv_file         = file("${local.talhelper_working_dir}/talenv.yaml")
  talhelper_clusterName         = yamldecode(local.talhelper_talenv_file)["clusterName"]
  talhelper_talosVersion        = yamldecode(local.talhelper_talenv_file)["talosVersion"]
  # this is an image factory url generated with https://factory.talos.dev/ (includes iscsi-tools and vmtoolsd-guest-agent). used Cloud Server/vmware as Hardware Type
  talos_ovf_url                 = "https://factory.talos.dev/image/dfd1ac9abdf529ca644694b17af0ce1a2ae23a5cccdff39439aa7f0774901e90/${local.talhelper_talosVersion}/vmware-amd64.ova"
  # talos_ovf_url                 = "https://github.com/siderolabs/talos/releases/download/${local.talhelper_talosVersion}/vmware-amd64.ova"

  talos_nodes = {
    for node in local.talhelper_clusterconfig_files:
      split(".yaml", "${node}")[0] => { # <-- only splitting here so our keys are node names and not node file names
        "hostname"     = yamldecode(file("${local.talhelper_clusterconfig_path}/${node}"))["machine"]["network"]["hostname"]
        "type"         = yamldecode(file("${local.talhelper_clusterconfig_path}/${node}"))["machine"]["type"]
        "talos_config" = base64encode(file("${local.talhelper_clusterconfig_path}/${node}"))
    }
  }
}

resource "vsphere_virtual_machine" "talos_nodes" {
  for_each = local.talos_nodes

  name                       = each.value.hostname
  resource_pool_id           = data.vsphere_compute_cluster.cluster.resource_pool_id
  host_system_id             = data.vsphere_host.host.id
  datastore_id               = data.vsphere_datastore.datastore.id
  datacenter_id              = data.vsphere_datacenter.datacenter.id
  folder                     = local.vmware_config.folder
  wait_for_guest_net_timeout = -1 # don't wait for guest since talos doesn't have vmtools
  num_cpus                   = local.vmware_config.node_hardware_config[each.value.type].num_cpus
  memory                     = local.vmware_config.node_hardware_config[each.value.type].memory
  # hardware_version           = 17

  ovf_deploy {
    remote_ovf_url = local.talos_ovf_url
  }

  # Disk for os
  disk {
    label = "disk0"
    size  = local.vmware_config.node_hardware_config[each.value.type].disk_size
  }

  # Disk for ceph
  disk {
    label       = "disk1"
    size        = local.vmware_config.node_hardware_config[each.value.type].longhorn_disk_size
    unit_number = 1
  }

  # VM networking
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = "vmxnet3"
  }

  # for vsphere-kubernetes integration
  enable_disk_uuid = "true"

  # sets the talos configuration
  extra_config = {
    "guestinfo.talos.config" = each.value.talos_config
  }

  lifecycle {
    ignore_changes = [
      disk[0].io_share_count,
      disk[0].thin_provisioned,
      disk[1].io_share_count,
      disk[1].thin_provisioned
    ]
  }
}
