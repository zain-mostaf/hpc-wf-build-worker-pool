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

variable machine_ip_name_mapping {
    type=map(string)
}

variable symphony_image_name {

}

variable symphony_profile {

}

variable worker_tags {
    type=list(string)
}

variable security_group_ids {
    type=list(string)
}

variable zone {

}

variable subnet_id_or_name {

}

variable resource_group_id {

}

variable ssh_keys {
    type=list(string)
}

variable cloud_init_script {

}

variable vpc_id {

}