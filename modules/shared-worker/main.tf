##
# Copyright (C) IBM Inc. - All Rights Reserved
# 
# This source code is protected under international copyright law.  All rights
# reserved and protected by the copyright holders.
# This file is confidential and only available to authorized individuals with the
# permission of the copyright holders.  If you encounter this file and do not have
# permission, please contact the copyright holders and delete this file.
# 
# This software is provided as-is, without warranties of any kind. 
##

locals {
    machine_ip_name_mapping = var.machine_ip_name_mapping
    symphony_image_id = var.symphony_image_name
    symphony_profile = var.symphony_profile
    worker_tags = var.worker_tags
    security_groups = var.security_group_ids
    zone = var.zone
    vpc_id = var.vpc_id
    subnet_id_or_name = var.subnet_id_or_name
    resource_group_id = var.resource_group_id
    ssh_keys = var.ssh_keys
    cloud_init_script = var.cloud_init_script
    tags = var.worker_tags
    boot_volume_size = 100
    region = "${split("-", var.zone)[0]}-${split("-", var.zone)[1]}"

    // Odd worker numbers (ex: -0001) use smb_share_paths[0], even numbers (ex: -0002) use smb_share_paths[1].
    // With a single entry every worker uses it; with no entries nothing is mounted.
    smb_share_paths = var.smb_share_paths
    smb_index_by_worker = {
        for ip, name in local.machine_ip_name_mapping : ip => (
            length(local.smb_share_paths) == 0 ? 0 :
            (parseint(regex("\\d+$", name), 10) % 2 == 1 ? 0 : 1) % length(local.smb_share_paths)
        )
    }
    smb_share_by_worker = {
        for ip, name in var.machine_ip_name_mapping : ip => (
            length(local.smb_share_paths) == 0 ? "" :
            replace(local.smb_share_paths[local.smb_index_by_worker[ip]], "'", "''")
        )
    }
}

data ibm_is_subnet subnet_by_name {
    count = length(regexall("\\w{4}-\\w{8}-\\w{4}-\\w{4}-\\w{4}-\\w{12}", local.subnet_id_or_name)) == 0 ? 1 : 0
    name = local.subnet_id_or_name
}

data ibm_is_image image_by_name {
    count = length(regexall("\\w{4}-\\w{8}-\\w{4}-\\w{4}-\\w{4}-\\w{12}", local.symphony_image_id)) == 0 ? 1 : 0
    name = local.symphony_image_id
}

// Primary VNI (eth0): one per worker, created as its own resource and attached to the instance below.
// IBM Cloud requires auto_delete = false for a VNI that is created unbound (before it is attached to the instance).
// Once the VNI is attached, the shell_script.vni_auto_delete resource below sets auto_delete = true on it, so IBM Cloud
// deletes the VNI together with the VSI (also when the VSI is deleted from the console or CLI). That change is made
// outside the provider, hence ignore_changes on auto_delete (otherwise Terraform would set it back to false).
resource "ibm_is_virtual_network_interface" "primary" {

  for_each = local.machine_ip_name_mapping

  name = "${each.value}-eth0-vni"

  subnet = try(data.ibm_is_subnet.subnet_by_name[0].id, local.subnet_id_or_name)

  security_groups = local.security_groups

  primary_ip {
    address     = each.key
    auto_delete = true
  }

  allow_ip_spoofing         = false
  enable_infrastructure_nat = true
  auto_delete               = false

  resource_group = local.resource_group_id

  tags = local.tags

  lifecycle {
    ignore_changes = [auto_delete]
  }
}

resource "ibm_is_instance" "worker" {
 
  for_each       = local.machine_ip_name_mapping
  name           = each.value
  image          = try(data.ibm_is_image.image_by_name[0].id, local.symphony_image_id)
  profile         = local.symphony_profile
  vpc            = local.vpc_id
  zone           = local.zone
  keys           = local.ssh_keys
  resource_group = local.resource_group_id
  user_data      = replace(replace(local.cloud_init_script, "__COMPUTERNAME__", each.value), "__SMBSHARE__", local.smb_share_by_worker[each.key])

  tags           = concat(local.tags, ["role:symphony-worker"])
  metadata_service {
    enabled = true
  }
  primary_network_attachment {
    name = "${each.value}-eth0-attachment"

    virtual_network_interface {
      id = ibm_is_virtual_network_interface.primary[each.key].id
    }
  }
  
  lifecycle {
      ignore_changes = [ user_data, tags, image ]
  }

 
  boot_volume {
      name = "${each.value}-boot"
      size = local.boot_volume_size
  }
  

}

// Sets auto_delete = true on every VNI once it is attached to its VSI (see the comment on the VNI resource).
// Destroy order: this resource, then the instance, then the VNI. If IBM Cloud has already removed the VNI together with
// the instance, destroying the VNI resource finds it gone.
resource "shell_script" "vni_auto_delete" {

  for_each = local.machine_ip_name_mapping

  lifecycle_commands {
    create = "tr -d '\\r' < '${path.module}/setVniAutoDelete.sh' | /bin/bash -s -- '${local.region}' '${ibm_is_virtual_network_interface.primary[each.key].id}'"
    update = "tr -d '\\r' < '${path.module}/setVniAutoDelete.sh' | /bin/bash -s -- '${local.region}' '${ibm_is_virtual_network_interface.primary[each.key].id}'"
    delete = "true"
  }

  // Run again if the VSI or the VNI is replaced, and only after the VSI exists (the VNI is attached to it).
  environment = {
    INSTANCE_ID = ibm_is_instance.worker[each.key].id
    VNI_ID      = ibm_is_virtual_network_interface.primary[each.key].id
  }
}
