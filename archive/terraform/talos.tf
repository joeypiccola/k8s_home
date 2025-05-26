resource "talos_machine_secrets" "this" {
  talos_version = local.talos_version
}

data "talos_client_configuration" "this" {
  cluster_name         = local.talos_cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for node in local.talos_nodes : node.ip]
  endpoints            = [for node in local.talos_nodes : node.ip]
}

# we only need one of these because machine_type is controlplane which is the same for all nodes
data "talos_machine_configuration" "this" {
  cluster_name     = local.talos_cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = local.talos_cluster_endpoint
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = local.talos_version
}

resource "talos_machine_configuration_apply" "talos_nodes" {
  for_each = { for node in local.talos_nodes : node.hostname => node }

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this.machine_configuration
  node                        = each.value.ip
  config_patches              = [templatefile("${path.module}/templates/talos_config.tftpl", {
    hostname = each.value.hostname,
    virtual  = each.value.virtual,
    ip       = each.value.ip,
    image    = format("factory.talos.dev/installer/%s:%s",
      each.value.virtual ? talos_image_factory_schematic.virtual.id : talos_image_factory_schematic.physical.id,
      data.talos_image_factory_extensions_versions.virtual.talos_version # <-- doesn't matter if we pick virtual or physical, same talos_version
    )
  })]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [
    talos_machine_configuration_apply.talos_nodes
  ]
  node                 = "10.0.5.226" # this is the first controlplane node
  client_configuration = talos_machine_secrets.this.client_configuration
}
