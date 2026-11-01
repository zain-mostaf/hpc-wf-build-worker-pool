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
  workspace_id = var.schematics_workspace_id
}

data "ibm_schematics_workspace" "schematics_workspace" {
  
  workspace_id = local.workspace_id
}

/*
data "ibm_schematics_output" "output" {
  workspace_id = local.workspace_id
  template_id  = data.ibm_schematics_workspace.schematics_workspace.template_id.0
}
*/

data shell_script workspace_output_variables {
    lifecycle_commands {
        read = "/bin/bash getTFOutputs.sh ${local.workspace_id}"
    }
}

// validation of available slots for networking
data shell_script validate_pool_cidr_size {
    lifecycle_commands {
        read = "/usr/bin/python3 validatePoolCIDRSize.py ${length(local.worker_pool_ips)} ${local.worker_pool_size}"
    }
}

locals {

    // New HPC Management offerings outputs all needed data to be consumed by this worker pool.
    // For the old HPC management offerings, the worker pool will look at input variables.
    output = data.shell_script.workspace_output_variables.output

    /**
    * Declared input variables in the HPC Management Schematics workspace
    */
    zone = try(try(local.output.zone, [for input in data.ibm_schematics_workspace.schematics_workspace.template_inputs : input.value if input.name == "zone" ][0]), "")

    // Region: calculated based on zone (needed for ibm builder provider)
    region = "${split("-", local.zone)[0]}-${split("-", local.zone)[1]}"

    // Cluster prefix of the parent HPC Management workspace (used to find the grid managers)
    parent_cluster_prefix = try(try(local.output.cluster_prefix, [for input in data.ibm_schematics_workspace.schematics_workspace.template_inputs : input.value if input.name == "cluster_prefix" ][0]), "")
    // Cluster prefix used to name the workers of this pool (can be overwritten by this workspace)
    cluster_prefix = var.cluster_prefix != "" ? var.cluster_prefix : local.parent_cluster_prefix
    tags = try(try(jsondecode(local.output.tags), jsondecode([for input in data.ibm_schematics_workspace.schematics_workspace.template_inputs : input.value if input.name == "tags" ][0])), [])
    ssh_keys = try(try(local.output.ssh_keys, [for input in data.ibm_schematics_workspace.schematics_workspace.template_inputs : input.value if input.name == "ssh_keys" ][0]), "")

    symphony_cluster_info = try(
    try ( local.output.symphony_cluster_info, 
        try(
              [for input in data.ibm_schematics_workspace.schematics_workspace.template_inputs : input.value if input.name == "symphony_cluster_info" ][0],
              [for input in data.ibm_schematics_workspace.schematics_workspace.template_values_metadata : input.default if input.name == "symphony_cluster_info"][0]
            ),
        ),
    "")

    /*
    * Declared input variables in the HPC Managemeny Schematics workspace that can be overwritten by this workspace
    */
     symphony_compute_instance_profile = try([for input in data.ibm_schematics_workspace.schematics_workspace.template_inputs : input.value if input.name == "symphony_compute_instance_profile" ][0], "")
     symphony_linux_image_name = try(try(local.output.symphony_image_name, [for input in data.ibm_schematics_workspace.schematics_workspace.template_inputs : input.value if input.name == "symphony_image_name" ][0]), "")
     symphony_windows_image_name = try([for input in data.ibm_schematics_workspace.schematics_workspace.template_inputs : input.value if input.name == "windows_image_name" ][0], "")

    // Grid manager host names from the parent HPC Management workspace (<parent_cluster_prefix>-<grid_manager_prefix>-01..03),
    // used to configure ego.conf on workers. They always use the parent prefix, not var.cluster_prefix.
    symphony_master_names = [for i in range(3) : "${local.parent_cluster_prefix}-${var.grid_manager_prefix}-${format("%02d", i+1)}"]

    /*
    *  Output variables coming from HPC Management Schematics workspace (requires commit 7f45c3fa7c0d85e3bb02ccb2afeb8b5fd178046b in citi-hpc-offering to work)
    */
    workload_vpc_id = local.output.workload_vpc_id
    resource_group_id = local.output.resource_group_id
    private_dns_instance_id = local.output.private_dns_instance_id
    private_dns_zone_id = local.output.private_dns_zone_id
    ssh_key_ids = try(jsondecode(local.output.ssh_key_ids), [])

    /*
    *  Output that can be overwritten by this workspace
    */
    symphony_subnet_id = var.symphony_subnet_id != "" ? var.symphony_subnet_id : local.output.symphony_subnet_id
    symphony_worker_security_group = length(var.security_groups) > 0 ? flatten([for sg_name in var.security_groups : [for sg in module.security_groups.security_groups : sg.id if sg.name == sg_name]]) : try(jsondecode(local.output.symphony_worker_security_group), [])

    symphony_instance_profile = var.symphony_instance_profile != "" ? var.symphony_instance_profile : local.symphony_compute_instance_profile
    symphony_instance_image_id = var.symphony_instance_image_id != "" ? var.symphony_instance_image_id : (local.symphony_windows_image_name != "" ? local.symphony_windows_image_name : local.symphony_linux_image_name)


    // Worker pool size, name and IPs
    worker_pool_subnet_segmentation = var.worker_pool_subnet_segmentation
    worker_pool_size = var.worker_pool_size
    worker_pool_prefix = var.worker_pool_prefix
    worker_pool_start_number_at = var.worker_pool_start_at_number
    worker_pool_ips = flatten([for subnet in local.worker_pool_subnet_segmentation : [for index in range(pow(2, 32 - split("/", subnet)[1])) : cidrhost(subnet, index)]])
    worker_pool_name_prefix = local.worker_pool_prefix!="" ? "${local.worker_pool_prefix}" : "worker"
    worker_pool_worker_names = [for i in range(local.worker_pool_size) : "${local.cluster_prefix}-${local.worker_pool_name_prefix}-${format("%04d", i + local.worker_pool_start_number_at)}"]
    worker_pool_ip_name_mapping = {for idx in range(min(local.worker_pool_size, length(local.worker_pool_ips))) : local.worker_pool_ips[idx] => local.worker_pool_worker_names[idx]}

    // Worker pool type
    worker_pool_type = var.worker_pool_type
    // Worker pool OS
    worker_os = var.worker_pool_os

    // Cloud-INIT --> Post deployment tasks
    post_deployment_tasks = var.symphony_post_deployment_tasks

    // SSL Certificates
    ego_ssl_cacert = var.ego_ssl_cacert

    worker_attributes=try(var.worker_attributes, {})

    skip_symphony_config = var.skip_symphony_config
   
}

// Get all resource groups from the region
module security_groups {
    providers = {
        ibm = ibm.builder
    }

    source = "./modules/all-security-groups"
}

// Create DNS records
module dns_records {
    providers = {
        ibm = ibm.builder
    }
    depends_on=[data.shell_script.validate_pool_cidr_size]
    count = local.private_dns_instance_id != "" && local.private_dns_zone_id != "" ? 1 : 0
    source = "./modules/dns-entry"
    ibmcloud_api_key = var.ibmcloud_api_key
    private_dns_instance_id = local.private_dns_instance_id
    private_dns_zone_id = local.private_dns_zone_id
    machine_ip_name_mapping = local.worker_pool_ip_name_mapping
}

// Create cloud-init scripts depending on operating system
module cloud_init_scripts {
    depends_on=[data.shell_script.validate_pool_cidr_size]
    source = "./modules/cloud-init-scripts"
    worker_os=local.worker_os
    cluster_domain=try(module.dns_records[0].domain_name, "")
    ego_cluster_info=local.symphony_cluster_info
    ego_base_port=var.ego_base_port
    ego_ssl_setup=var.ego_ssl_setup
    ego_config_override=""
    post_deployment_tasks=local.post_deployment_tasks
    additional_resource_tag=""
    ego_master_list=local.symphony_master_names
    ego_ssl_cacert=local.ego_ssl_cacert
    smb_share_path=var.smb_share_path
    smb_drive_letter=var.smb_drive_letter
    smb_user=var.smb_user
    smb_password=var.smb_password
    worker_attributes=local.worker_attributes
    skip_symphony_config = local.skip_symphony_config
}

// Create shared workers
module shared_workers {
    providers = {
        ibm = ibm.builder
    }
    depends_on=[data.shell_script.validate_pool_cidr_size]
    source = "./modules/shared-worker"
    count = local.worker_pool_type == "shared" ? 1 : 0
    machine_ip_name_mapping = local.worker_pool_ip_name_mapping
    symphony_image_name = local.symphony_instance_image_id
    symphony_profile = local.symphony_instance_profile
    worker_tags = local.tags
    security_group_ids = local.symphony_worker_security_group
    zone = local.zone
    subnet_id_or_name = local.symphony_subnet_id
    resource_group_id = local.resource_group_id
    ssh_keys = local.ssh_key_ids
    cloud_init_script = module.cloud_init_scripts.cloud_init_output
    vpc_id = local.workload_vpc_id
}
// Create dedicated workers

// Create bare metal workers