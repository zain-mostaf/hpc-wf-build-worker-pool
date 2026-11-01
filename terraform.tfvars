# --- Required ---
# ibmcloud_api_key is deliberately not set here. Set it as an environment variable (TF_VAR_ibmcloud_api_key)
# or as a sensitive variable in the Schematics workspace.
schematics_workspace_id = "<parent-HPC-workspace-id>"

worker_pool_subnet_segmentation = ["<worker-subnet-cidr>"]   # example: ["10.10.20.0/26"]
worker_pool_size                = 10                         # maximum 512

# --- Worker pool ---
worker_pool_type            = "shared"
worker_pool_os              = "windows"
worker_pool_prefix          = "wk"    # optional. Gives <cluster_prefix>-wk-NNNN (empty gives <cluster_prefix>-worker-NNNN)
worker_pool_start_at_number = 1

# --- Naming / grid managers ---
cluster_prefix      = "wdc1wf"        # worker naming only (gives wdc1wf-wk-0001). Grid managers use the parent workspace cluster_prefix (wdcaz1)
grid_manager_prefix = "wf-grid-man"   # gives wdcaz1-wf-grid-man-01, -02, -03

# --- Symphony ports (omit to read them from the parent workspace symphony_cluster_info) ---
ego_base_port = 7869
ego_ssl_setup = false   # false gives -SSLPort NO_SSL

# --- SMB share mounted on Windows workers (net use Z: \\server\share /user:<user> <password>) ---
smb_share_path   = "\\\\<server>\\<share>"   # leave empty to skip mounting
smb_drive_letter = "Z:"
smb_user         = "<smb-user>"
smb_password     = "<smb-password>"          # better as a sensitive Schematics variable

# --- Optional overrides (empty means use the parent workspace values) ---
symphony_subnet_id             = ""
symphony_instance_profile      = ""
symphony_instance_image_id     = ""   # the Windows image name or ID
security_groups                = []
ego_ssl_cacert                 = <<-EOT
-----BEGIN CERTIFICATE-----
<paste the content of cacert.pem here, all certificates in the file>
-----END CERTIFICATE-----
EOT
symphony_post_deployment_tasks = ""
worker_attributes              = {}
skip_symphony_config           = false
