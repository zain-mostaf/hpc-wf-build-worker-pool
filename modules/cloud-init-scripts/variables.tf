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

variable worker_os {

}

variable cluster_domain {

}

variable ego_cluster_info {

}

variable ego_config_override {
   default = ""
}

variable post_deployment_tasks {
   default = ""
}

variable additional_resource_tag {

}

variable ad_info {
   type = map(string)
   default = {}
}

variable ego_master_list {
    type = list(string)
}

variable ego_ssl_cacert {
   
}

variable worker_attributes {
   type = map(string)
   default = {
   }
}

variable skip_symphony_config {
   type = bool
   default = false
}

