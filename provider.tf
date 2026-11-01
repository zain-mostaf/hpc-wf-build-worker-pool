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

terraform {
  required_providers {
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = ">= 1.70.0"
    }
    shell = {
      source  = "scottwinkler/shell"
      version = "1.7.10"
    }
  }
}

provider "shell" {
  sensitive_environment = {
    IBMCLOUD_API_KEY = var.ibmcloud_api_key
  }
}

// default provider - used by Schematics
provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
}

// builder provider - used to create resources (we need to set region here due to VPC APIs)
provider "ibm" {
  alias = "builder"
  ibmcloud_api_key = var.ibmcloud_api_key
  region = local.region
}