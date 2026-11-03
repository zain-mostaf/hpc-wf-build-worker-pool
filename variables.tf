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

variable ego_base_port {
    type = number
    default = null
    description = "(Optional) Symphony (EGO) base port used by workers (ex: 7869). If omitted, the value is read from symphony_cluster_info of the HPC Management workspace (default 7869 when not found)."
}

variable ego_ssl_setup {
    type = bool
    default = null
    description = "(Optional) Set false to disable SSL on workers (-SSLPort NO_SSL) or true to enable it. If omitted, the value is read from symphony_cluster_info of the HPC Management workspace."
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

variable smb_share_path {
    type = list(string)
    default = []
    description = "(Optional) List of UNC paths of SMB shares to mount on Windows workers (ex: [\"\\\\\\\\smb-1\\\\share\", \"\\\\\\\\smb-2\\\\share\"]). Workers with an odd number (ex: -0001) use the 1st entry, workers with an even number (ex: -0002) use the 2nd entry. With a single entry, all workers use it. If empty, nothing is mounted."
}

variable smb_drive_letter {
    default = "Z:"
    description = "(Optional) Drive letter used to mount the SMB share on Windows workers."
}

variable "smb_server_names" {
    type        = list(string)
    default     = []
    description = "Optional SMB server computer names in the same order as smb_share_path. Use actual server names, not example names. When supplied, the list must match the share list length."
}

variable smb_user {
    default = ""
    description = "(Optional) SMB account for the global drive mapping. Bare local usernames are qualified with the selected SMB server; explicit DOMAIN\\user and user@domain values are preserved. Required with smb_password when smb_share_path is configured."
}

variable smb_password {
    type = string
    default = ""
    sensitive = true
    description = "(Optional) Password of the SMB user. It is base64-encoded (not encrypted) and stored in the instance user data."
}

variable skip_symphony_config {
    type = bool
    default = false
    description = "(Optional) Set true to skip Symphony config during cloud-init execution. This is useful when you have to detach the infrastructure hand-off from Symphony setup (requirement for production workloads that require Symphony config to be done during weekends). It is currently applicable for Windows worker pools only."
}
