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

   // EGO local properties for Jinja templating
   ego_base_port =  try(split("= ", regex("(?:ego_base_port = )\\d{1,}", var.ego_cluster_info))[1], 7869)
   ego_ssl_setup =  try(split("= ", regex("(?:ego_ssl_setup = )\\w{1,}", var.ego_cluster_info))[1], false)
   ego_ssl_port =   try(split("= ", regex("(?:ego_ssl_port = )\\d{1,}", var.ego_cluster_info))[1], 0)
   ego_ssl_cacert = var.ego_ssl_cacert
   ego_top = var.worker_os == "windows" ? "C:\\Program Files\\IBM\\SpectrumComputing" : "/opt/ibm/spectrumcomputing"
   ego_config_override = var.ego_config_override

   post_deployment_tasks = var.post_deployment_tasks
   
   // Cluster domain (used for DNS configuration in worker)
   cluster_domain = var.cluster_domain

   // attribute mapping in EGO_LOCAL_RESOURCES (they must be declared as string over ego.shared file)
   ego_local_resources_appended_line = [
      for key,value in var.worker_attributes : "[resourcemap ${value}*${key}]"
   ]
   // Template data (used by Ansible to deploy Symphony worker) 
   template_data = {
      EGO_TOP = local.ego_top,
      ego_primary_host = var.ego_master_list[0],
      ego_secondary_host = var.ego_master_list[1],
      ego_base_port = local.ego_base_port,
      ego_ssl_setup = local.ego_ssl_setup,
      ego_ssl_port = local.ego_ssl_port,
      ego_additional_properties = local.ego_config_override,
      cluster_domain = local.cluster_domain,
      os_delim = var.worker_os == "windows" ? "\\" : "/",
      copy_ssl_cacert = length(trimspace(local.ego_ssl_cacert)) > 0 ? "true" : "false",
      symphony_password = base64encode("Symphony@123") // FIXME
      symphony_closed_resource = true // FIXME,
      worker_os = var.worker_os
      worker_attributes = join("", local.ego_local_resources_appended_line)
      no_start_symphony_config = var.skip_symphony_config
   }

   // Active Directory Information (Windows only)
   ad_dns_server = try(var.ad_info.ad_dns_server, "")
   ad_domain = try(var.ad_info.ad_domain, "")
   ad_join_user = try(var.ad_info.ad_join_user, "")
   ad_join_password = try(var.ad_info.ad_join_password, "")
}

// ego.conf generation
data "jinja_template" "ego_conf_file" {
   template = "${path.module}/scripts/ansible-playbooks/templates/ego.conf.j2"
   
   context {
      type = "json"
      data = jsonencode(local.template_data)
   }
}

// netsh.txt configuration
data jinja_template "netsh_conf_file" {
   template = "${path.module}/scripts/ansible-playbooks/templates/netsh.txt.j2"
   context {
      type = "json"
      data = jsonencode( {ad_dns_server = local.ad_dns_server})
   }
}

// cloud-init-generation  
locals {

    ego_conf_content = data.jinja_template.ego_conf_file.result

    // Linux post-deployment-playbook.yaml (complete with additional data from parameter)
    linux_post_deployment_tasks = templatefile("${path.module}/scripts/ansible-playbooks/linux-worker-postdeployment.yaml", {
        post_deployment_tasks = join("\n",[for line in split("\n", local.post_deployment_tasks) : "  ${(line)}"])
    })

    // Linux
    cloud_init_linux = var.worker_os == "linux" ? templatefile("${path.module}/scripts/cloud-init/linux-cloud-init.yaml", {
       linux_worker_deployment_content = base64gzip(file("${path.module}/scripts/ansible-playbooks/linux-worker-deployment.yaml")),
       linux_worker_postdeployment_content = base64gzip(local.linux_post_deployment_tasks),
       ego_conf_content = base64gzip(local.ego_conf_content),
       linux_worker_deployment_env_content = base64gzip(jsonencode(local.template_data)),
       cacert_pem_content = base64gzip(local.ego_ssl_cacert)
    }) : ""

    // Windows post deployment powershell function
    windows_post_deployment_tasks = templatefile("${path.module}/scripts/powershell/windows-worker-postdeployment.ps1", {
        post_deployment_tasks = local.post_deployment_tasks
    })
    // Windows
    cloud_init_windows = var.worker_os == "windows" ? templatefile("${path.module}/scripts/cloud-init/windows-cloud-init.yaml", {
       gunzip_content = base64encode(replace(file("${path.module}/scripts/powershell/gunzip.ps1"), "\n", "\r\n")),
       windows_worker_deployment_content = base64gzip(replace(file("${path.module}/scripts/powershell/windows-worker-deployment.ps1"), "\n", "\r\n")),
       windows_worker_postdeployment_content = base64gzip(local.windows_post_deployment_tasks)
       ego_conf_content = base64gzip(replace(local.ego_conf_content, "\n", "\r\n")),
       cacert_pem_content = base64gzip(replace(local.ego_ssl_cacert, "\n", "\r\n")),
       windows_netsh_content = base64encode(data.jinja_template.netsh_conf_file.result)
       deploy_worker_arguments = join(" ",[
            "-MasterList \"${local.template_data.ego_primary_host} ${local.template_data.ego_secondary_host}\"",
            "-ComputerName __COMPUTERNAME__" ,
            "-DNSSuffix \"${local.cluster_domain}\"",
            "-BasePort ${local.template_data.ego_base_port}",
            "-SymphonyPass ${local.template_data.symphony_password}",
            "-ADDNSServer \"${local.ad_dns_server}\"",
            "-DomainName \"${local.ad_domain}\"",
            "-JoinUser \"${local.ad_join_user}\"",
            "-JoinUserPassword \"${base64encode(local.ad_join_password)}\"",
            "-SSLPort ${local.template_data.ego_ssl_setup == "true" ? local.template_data.ego_ssl_port : "NO_SSL"}",
            "-ClosedResource ${local.template_data.symphony_closed_resource}",
            "-NoStartSymphonyConfig ${local.template_data.no_start_symphony_config}"
        ])
    }) : ""

    cloud_init_output = var.worker_os == "linux" ? local.cloud_init_linux : local.cloud_init_windows
}

