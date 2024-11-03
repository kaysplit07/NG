- name: 'Terraform Initialize - Load Balancer'
  uses: hashicorp/terraform-github-actions@master
  with:
    tf_actions_version:     latest
    tf_actions_subcommand:  'init'
    tf_actions_working_dir: ${{env.ROOT_PATH}}
    tf_actions_comment:     true
  env:
    TF_VAR_requesttype:         '${{inputs.requesttype}}'
    TF_VAR_location:            '${{inputs.location}}'
    TF_VAR_environment:         '${{inputs.environment}}'
    TF_VAR_purpose:             '${{inputs.purpose}}'
    TF_VAR_purpose_rg:          '${{inputs.purposeRG}}'
    TF_VAR_RGname:              '${{inputs.RGname}}'
    TF_VAR_subnetname:          '${{inputs.subnetname}}'
    TF_VAR_sku_name:            '${{inputs.sku_name}}'
    TF_VAR_private_ip_address:  '${{inputs.private_ip_address}}'
  with:
    # Explicitly define backend configuration for Azure
    backend-config: |
      resource_group_name=test-dev-eus2-testing-rg
      storage_account_name=6425dveus2aristb01
      container_name=terraform-state
      key=dev/load_balancer_project.tfstate
