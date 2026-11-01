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
    private_dns_instance_id = var.private_dns_instance_id
    private_dns_zone_id = var.private_dns_zone_id
    private_dns_ttl = var.private_dns_ttl
    machine_ip_name_mapping = var.machine_ip_name_mapping
    private_dns_ptr_records = true
}


data "ibm_dns_zones" "zones" {
    instance_id = local.private_dns_instance_id
}

locals {
    zone_name = try([for zone in data.ibm_dns_zones.zones.dns_zones : zone.name if zone.zone_id == local.private_dns_zone_id][0], "")
    ptr_records_to_create = (local.zone_name != "" && local.private_dns_ptr_records == true) ? local.machine_ip_name_mapping : {}
}

// Create DNS A records from the received IP/name mapping received
resource "ibm_dns_resource_record" "dns_A_records" {
    for_each = local.machine_ip_name_mapping
    instance_id = local.private_dns_instance_id
    zone_id = local.private_dns_zone_id
    type = "A"
    name = each.value
    rdata = each.key
    ttl = local.private_dns_ttl
}

// Create DNS PTR records (if zone found and private_dns_ptr_records == true)
resource "ibm_dns_resource_record" "dns_PTR_records" {
    depends_on = [ibm_dns_resource_record.dns_A_records]

    for_each = local.ptr_records_to_create
    instance_id = local.private_dns_instance_id
    zone_id = local.private_dns_zone_id
    type = "PTR"
    name = each.key
    rdata = "${each.value}.${local.zone_name}"
    ttl = local.private_dns_ttl
}