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

variable ibmcloud_api_key {
    description = "IBM Cloud API Key to query and provision resources"
}

variable schematics_workspace_id {
    description = "ID of the HPC Management Schematics workspace. It is used to retrieve common information about the cluster (ex: VPC ID, DNS instance, etc)"
}

variable cluster_prefix {
    default = ""
    description = "(Optional) Cluster prefix used to name the workers of this pool (ex: for Windows workers). It does NOT change the Symphony grid manager names, which always come from the HPC Management workspace. If omitted, the cluster prefix from the HPC Management workspace will be used."
}

variable grid_manager_prefix {
    default = "wf-grid-man"
    description = "(Optional) Name part of the Symphony grid managers in the HPC Management workspace. Grid manager hosts are named <parent cluster_prefix>-<grid_manager_prefix>-01, -02, -03 (ex: wdcaz1-wf-grid-man-01)."
}

variable worker_pool_subnet_segmentation {
    type=list(string)
    description = "List of CIDRs to be used for worker IP assignment. It will limit the number of available spots for this worker pool."
}

variable worker_pool_size {
    type=number
    description="Quantity of workers to be provisioned into this worker pool. Maximum allowed is 512 workers."

    validation {
        condition = var.worker_pool_size <= 512
        error_message = "Maximum number of workers allowed per worker pool is 512."
    }
}

variable worker_pool_type {
    default="shared"
    description="Provision workers by using 'shared' VSIs, 'dedicated' hosts or 'baremetal'. Currently only 'shared' is implemented."

    validation {
        condition = var.worker_pool_type == "shared"
        error_message = "Only 'shared' is currently supported."
    }
}

variable worker_pool_os {
    default="linux"
    description="Worker operating system (linux, windows). Defaults to 'linux'. This is used to determine the deployment scripts to be used by automation."

    validation {
        condition = var.worker_pool_os == "windows" || var.worker_pool_os == "linux"
        error_message = "Valid values: 'windows' or 'linux'."
    }

}

variable worker_pool_prefix {
    default=""
    description="(Optional) Worker pool prefix to be added after cluster prefix (cluster prefix is captured from HPC management workspace). If informed, workers will be named by the following convention: <cluster_prefix>-<worker_prefix>-<counter>. If omitted, worker will follow the same naming convention from HPC management workspace (<cluster_prefix>-<(worker/wk)>-<counter>.)"
}
variable worker_pool_start_at_number {
    type=number
    default=1
    description="(Optional) Start counter for workers. This is useful when you want to keep the same cluster/worker prefix across worker pools."
}

variable symphony_subnet_id {
    default=""
    description="(Optional) ID or Name of an existent subnet where this worker pool will land. If omitted, the Symphony worker subnet set in the HPC Management workspace will be used."
}

variable symphony_instance_profile {
    default=""
    description="(Optional) Machine profile to use for this pool. If omitted, the Symphony worker profile used in the HPC Management workspace will be used."
}

variable symphony_instance_image_id {
    default=""
    description="(Optional) Imsge ID to be used by this worker pool. If omitted, the Symphony image ID used by HPC Management workspace will be used."
}

variable symphony_post_deployment_tasks {
    default=""
    description="(Optional) Post-deployment tasks to be executed after Symphony deployment. For Linux, it is a set of Ansible tasks to be included in the linux-worker-postdeployment.yaml file. For Windows, it is a set of Powershell commands that will be inserted in a function in the file windows-worker-postdeployment.ps1."
}

variable ego_ssl_cacert {
    default=""
    description="(Optional) CA Certificate to copy to workers during provisioning. If omitted, the original certificate is untouched."
}

variable worker_attributes {
   type = map(string)
   default = {
   }

   description="(Optional) List of static string attributes to be added to a worker. These attributes must be declared in ego.shared before being used."
}

variable security_groups {
    type = list(string)
    default = []
    description = "(Optional) List of security group names to be added into this worker. If not informed, the list will be imported from the HPC management offering."
}

variable ad_domain {
    default = ""
    description = "(Optional) Active Directory domain used to join Windows workers (ex: wf.ibmcloud). If not informed, the domain declared in HPC Management offering will be used."
}

variable ad_dns_zone {
    default = ""
    description = "(Optional) IBM Cloud DNS zone where the Active Directory servers are registered (ex: common.wf.ibmcloud). It is added to the DNS search suffix list of Windows workers, after the worker pool DNS zone and before the AD domain."
}

variable ad_join_user {
    default = ""
    description = "(Optional) AD User to join the domain. If not informed, the user declared in HPC Management offering will be used."
}

variable ad_join_password {
    default = ""
    description = "(Optional) Password of the AD User to be used. If not informed, the user declared in HPC Management offering will be used. NOTE: if this field is sensitive in HPC Management offering, it must be informed here because sensitive data is not retrieved through Schematics Workspace APIs."
}

variable skip_symphony_config {
    type = bool
    default = false
    description = "(Optional) Set true to skip Symphony config during cloud-init execution. This is useful when you have to detach the infrastructure hand-off from Symphony setup (requirement for production workloads that require Symphony config to be done during weekends). It is currently applicable for Windows worker pools only."
}