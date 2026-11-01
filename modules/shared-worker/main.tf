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
}

data ibm_is_subnet subnet_by_name {
    count = length(regexall("\\w{4}-\\w{8}-\\w{4}-\\w{4}-\\w{4}-\\w{12}", local.subnet_id_or_name)) == 0 ? 1 : 0
    name = local.subnet_id_or_name
}

data ibm_is_image image_by_name {
    count = length(regexall("\\w{4}-\\w{8}-\\w{4}-\\w{4}-\\w{4}-\\w{12}", local.symphony_image_id)) == 0 ? 1 : 0
    name = local.symphony_image_id
}

// One VNI per worker, created as its own resource and attached to the instance below.
// auto_delete = true so the VNI is deleted together with the instance it is attached to.
resource "ibm_is_virtual_network_interface" "worker" {

  for_each                  = local.machine_ip_name_mapping
  name                      = "${each.value}-vni"
  subnet                    = try(data.ibm_is_subnet.subnet_by_name[0].id, local.subnet_id_or_name)
  security_groups           = local.security_groups
  resource_group            = local.resource_group_id
  allow_ip_spoofing         = false
  enable_infrastructure_nat = true
  auto_delete               = false

  primary_ip {
    address     = each.key
    auto_delete = true
    name        = "${each.value}-eth0"
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
  user_data      = replace(local.cloud_init_script, "__COMPUTERNAME__", each.value)

  tags           = concat(local.tags, ["role:symphony-worker"])
  metadata_service {
    enabled = true
  }
  primary_network_attachment {
    name = "eth0"

    virtual_network_interface {
      id = ibm_is_virtual_network_interface.worker[each.key].id
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
