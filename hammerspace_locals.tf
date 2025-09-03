# Copyright (c) 2025 Hammerspace, Inc
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# -----------------------------------------------------------------------------
# modules/hammerspace/hammerspace_locals.tf
#
# This file contains the local variables and complex logic for the
# Hammerspace module.
# -----------------------------------------------------------------------------

# Make sure the instance type for the Anvil is available in this availability zone

data "aws_ec2_instance_type_offering" "anvil" {
  filter {
    name   = "instance-type"
    values = [var.anvil_type]
  }
  filter {
    name   = "location"
    values = [var.common_config.availability_zone]
  }
  location_type = "availability-zone"
}

# Make sure the instance type for the DSX is available in this availability zone

data "aws_ec2_instance_type_offering" "dsx" {
  filter {
    name   = "instance-type"
    values = [var.dsx_type]
  }
  filter {
    name   = "location"
    values = [var.common_config.availability_zone]
  }
  location_type = "availability-zone"
}

locals {
  # Determine if the instance type for the Anvil and DSX are available
  # These are checked in the main logic for the Hammerspace module

  anvil_instance_type_is_available = length(data.aws_ec2_instance_type_offering.anvil.instance_type) > 0
  dsx_instance_type_is_available = length(data.aws_ec2_instance_type_offering.dsx.instance_type) > 0

  anvil_resource_prefix = "${var.common_config.project_name}-Anvil"
  dsx_resource_prefix = "${var.common_config.project_name}-DSX"

  # --- Anvil Creation Logic based on anvil_count ---

  should_create_any_anvils = var.anvil_count > 0
  create_standalone_anvil  = var.anvil_count == 1
  create_ha_anvils         = var.anvil_count >= 2

  # --- General Conditions ---

  provides_key_name      = var.common_config.key_name != null && var.common_config.key_name != ""
  enable_iam_admin_group = var.iam_user_access == "Enable"
  create_iam_admin_group = local.enable_iam_admin_group && var.common_config.iam_profile_group == ""
  create_profile         = var.common_config.iam_profile_name == ""
  dsx_add_volumes_bool   = local.should_create_any_anvils && var.dsx_add_vols

  # --- Mappings & Derived Values ---

  anvil_instance_type_actual = var.anvil_type
  dsx_instance_type_actual   = var.dsx_type
  common_tags = merge(var.common_config.tags, {
    Project = var.common_config.project_name
  })

  device_letters = [
    "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
    "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"
  ]

  # --- IAM References ---

  effective_iam_admin_group_name = (
    local.create_iam_admin_group
    ? one(aws_iam_group.admin_group[*].name)
    : var.common_config.iam_profile_group
  )
  effective_iam_admin_group_arn = (
    local.create_iam_admin_group
    ? one(aws_iam_group.admin_group[*].arn)
    : (var.common_config.iam_profile_group != ""
      ? "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:group/${var.common_config.iam_profile_group}"
      : null)
  )
  effective_instance_profile_ref = (
    local.create_profile
    ? one(aws_iam_instance_profile.profile[*].name)
    : var.common_config.iam_profile_name
  )

  # --- Security Group Selection Logic ---

  effective_anvil_sg_id = var.anvil_security_group_id != "" ? var.anvil_security_group_id : one(aws_security_group.anvil_data_sg[*].id)
  effective_dsx_sg_id   = var.dsx_security_group_id != "" ? var.dsx_security_group_id : one(aws_security_group.dsx_sg[*].id)

  # --- IP and ID Discovery ---

  anvil2_ha_ni_secondary_ip = (
    local.create_ha_anvils &&
    length(aws_network_interface.anvil2_ha_ni) > 0 &&
    aws_network_interface.anvil2_ha_ni[0].private_ip != null &&
    length(tolist(aws_network_interface.anvil2_ha_ni[0].private_ips)) > 1
    ? ([for ip in tolist(aws_network_interface.anvil2_ha_ni[0].private_ips) : ip if ip != aws_network_interface.anvil2_ha_ni[0].private_ip][0])
    : null
  )

  management_ip_for_url = coalesce(
    # First priority: The floating IP for an HA pair

    local.anvil2_ha_ni_secondary_ip,

    # Second priority: The IP for a standalone anvil. This checks
    # if a public IP should be used.

    local.create_standalone_anvil && length(aws_instance.anvil) > 0 ?
    (var.assign_public_ip ? one(aws_eip.anvil_sa[*].public_ip) : aws_instance.anvil[0].private_ip) : null,

    # Fallback if no Anvil details are available at all.
    
    "N/A - Anvil instance details not available."
  )

  effective_anvil_ip_for_dsx_metadata = coalesce(
    local.anvil2_ha_ni_secondary_ip,
    local.create_standalone_anvil && length(aws_instance.anvil) > 0 ? aws_instance.anvil[0].private_ip : null
  )

  effective_anvil_id_for_dsx_password = coalesce(
    local.create_standalone_anvil && length(aws_instance.anvil) > 0 ? aws_instance.anvil[0].id : null,
    local.create_ha_anvils && length(aws_instance.anvil1) > 0 ? aws_instance.anvil1[0].id : null
  )

  # --- UserData Configuration Maps ---

  aws_config_map = local.enable_iam_admin_group && local.effective_iam_admin_group_name != null ? {
    iam_admin_group = local.effective_iam_admin_group_name
  } : {}

  anvil_sa_config_map = {
    cluster = {
      password_auth = false
    }
    node = {
      hostname = "${var.common_config.project_name}Anvil"
      ha_mode  = "Standalone"
      networks = {
        eth0 = {
          roles = ["data", "mgmt"]
        }
      }
    }
    aws = local.aws_config_map
  }

  anvil_ha_config_map = {
    cluster = {
      password_auth = false
    }
    aws = local.aws_config_map
    nodes = {
      "0" = {
        hostname = "${var.common_config.project_name}Anvil1"
        ha_mode  = "Primary"
        features = ["metadata"]
        networks = {
          eth0 = {
            roles       = ["data", "mgmt", "ha"]
            ips         = length(aws_network_interface.anvil1_ha_ni) > 0 ? ["${aws_network_interface.anvil1_ha_ni[0].private_ip}/24"] : null
            cluster_ips = local.anvil2_ha_ni_secondary_ip != null ? ["${local.anvil2_ha_ni_secondary_ip}/24"] : null
          }
        }
      }
      "1" = {
        hostname = "${var.common_config.project_name}Anvil2"
        ha_mode  = "Secondary"
        features = ["metadata"]
        networks = {
          eth0 = {
            roles       = ["data", "mgmt", "ha"]
            ips         = length(aws_network_interface.anvil2_ha_ni) > 0 ? ["${aws_network_interface.anvil2_ha_ni[0].private_ip}/24"] : null
            cluster_ips = local.anvil2_ha_ni_secondary_ip != null ? ["${local.anvil2_ha_ni_secondary_ip}/24"] : null
          }
        }
      }
    }
  }

  anvil_nodes_map_for_dsx = local.create_standalone_anvil ? {
    "1" = { hostname = "${var.common_config.project_name}Anvil", features = ["metadata"] }
    } : (local.create_ha_anvils ? {
    "1" = { hostname = "${var.common_config.project_name}Anvil1", features = ["metadata"] },
    "2" = { hostname = "${var.common_config.project_name}Anvil2", features = ["metadata"] }
  } : {})
}
