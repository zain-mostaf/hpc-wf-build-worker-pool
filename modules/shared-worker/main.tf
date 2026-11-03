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

    // Odd worker numbers (ex: -0001) use smb_share_paths[0], even numbers (ex: -0002) use smb_share_paths[1].
    // With a single entry every worker uses it; with no entries nothing is mounted.
    smb_share_paths = var.smb_share_paths
    smb_share_by_worker = {
        for ip, name in var.machine_ip_name_mapping : ip => (
            length(local.smb_share_paths) == 0 ? "" :
            replace(local.smb_share_paths[(parseint(regex("\\d+$", name), 10) % 2 == 1 ? 0 : 1) % length(local.smb_share_paths)], "'", "''")
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
    name = "eth0"

    virtual_network_interface {
      // Create the VNI with its target so IBM Cloud can delete it with the VSI.
      name                      = "${each.value}-vni"
      subnet                    = try(data.ibm_is_subnet.subnet_by_name[0].id, local.subnet_id_or_name)
      security_groups           = local.security_groups
      resource_group            = local.resource_group_id
      allow_ip_spoofing         = false
      enable_infrastructure_nat = true
      auto_delete               = true

      primary_ip {
        address     = each.key
        auto_delete = true
        name        = "${each.value}-eth0"
      }
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
