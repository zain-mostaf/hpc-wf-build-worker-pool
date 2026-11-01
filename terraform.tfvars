# --- Required ---
# ibmcloud_api_key is deliberately not set here. Set it as an environment variable (TF_VAR_ibmcloud_api_key)
# or as a sensitive variable in the Schematics workspace.
schematics_workspace_id = "<parent-HPC-workspace-id>"

worker_pool_subnet_segmentation = ["<worker-subnet-cidr>"]   # example: ["10.10.20.0/26"]
worker_pool_size                = 10                         # maximum 512

# --- Worker pool ---
worker_pool_type            = "shared"
worker_pool_os              = "windows"
worker_pool_prefix          = ""      # optional. Empty gives <cluster_prefix>-wk-NNNN when ad_domain is set
worker_pool_start_at_number = 1

# --- Naming / grid managers ---
cluster_prefix      = "wdcaz1"        # worker naming. Grid manager naming uses the parent workspace cluster_prefix
grid_manager_prefix = "wf-grid-man"   # gives wdcaz1-wf-grid-man-01, -02, -03

# --- Active Directory / DNS ---
ad_domain        = "wf.ibmcloud"                 # domain the worker joins
ad_dns_zone      = "common.wf.ibmcloud"          # AD DNS zone, added to the search suffix list
ad_join_user     = "administrator@wf.ibmcloud"   # UPN format. Alternative: "WF\\administrator"
ad_join_password = "<administrator-password>"    # better as a sensitive Schematics variable

# --- Symphony ports (omit to read them from the parent workspace symphony_cluster_info) ---
ego_base_port = 7869
ego_ssl_setup = false   # false gives -SSLPort NO_SSL

# --- Optional overrides (empty means use the parent workspace values) ---
symphony_subnet_id             = ""
symphony_instance_profile      = ""
symphony_instance_image_id     = ""   # the Windows image name or ID
security_groups                = []
ego_ssl_cacert                 = ""
symphony_post_deployment_tasks = ""
worker_attributes              = {}
skip_symphony_config           = false
