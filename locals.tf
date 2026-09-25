data "aws_caller_identity" "current" {}

locals {
  profile_names_are_valid = alltrue([
    for server in values(var.servers) : contains(keys(var.server_profiles), server.profile)
  ])

  shared_whitelist_by_uuid = {
    for player in var.shared_whitelist : player.uuid => player
  }

  server_whitelists = {
    for server_key, server in var.servers : server_key => values(merge(
      local.shared_whitelist_by_uuid,
      { for player in server.additional_whitelist : player.uuid => player },
    ))
  }

  shared_ops_by_uuid = {
    for player in var.shared_ops : player.uuid => player
  }

  server_ops = {
    for server_key, server in var.servers : server_key => values(merge(
      local.shared_ops_by_uuid,
      { for player in server.additional_ops : player.uuid => player },
    ))
  }

  artifact_bucket_name = "${var.fleet_name}-${data.aws_caller_identity.current.account_id}-artifacts"
}

check "server_profiles_exist" {
  assert {
    condition     = local.profile_names_are_valid
    error_message = "Every server must reference a profile declared in server_profiles."
  }
}
