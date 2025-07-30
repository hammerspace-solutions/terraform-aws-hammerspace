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
# modules/hammerspace/hammerspace_outputs.tf
#
# This file defines the outputs for the Hammerspace module.
# -----------------------------------------------------------------------------

output "management_ip" {
  description = "Management IP address for the Hammerspace cluster."
  value       = local.management_ip_for_url
}

output "management_url" {
  description = "Management URL for the Hammerspace cluster."
  value       = local.management_ip_for_url != "N/A - Anvil instance details not available." ? "https://${local.management_ip_for_url}" : "N/A"
}

output "anvil_instances" {
  description = "Details of deployed Anvil instances."
  sensitive   = true
  value = local.create_standalone_anvil && length(aws_instance.anvil) > 0 ? [
    {
      type                       = "standalone"
      id                         = one(aws_instance.anvil[*].id)
      arn			 = one(aws_instance.anvil[*].arn)
      private_ip                 = one(aws_instance.anvil[*].private_ip)
      public_ip                  = var.assign_public_ip ? one(aws_eip.anvil_sa[*].public_ip) : null
      key_name                   = one(aws_instance.anvil[*].key_name)
      iam_profile                = one(aws_instance.anvil[*].iam_instance_profile)
      placement_group            = one(aws_instance.anvil[*].placement_group)
      all_private_ips_on_eni_set = toset([])
      floating_ip_candidate      = null
    }
  ] : (local.create_ha_anvils ? [
    { # Anvil1
      type                       = "ha_node1"
      id                         = one(aws_instance.anvil1[*].id)
      arn			 = one(aws_instance.anvil[*].arn)
      private_ip                 = one(aws_instance.anvil1[*].private_ip)
      public_ip                  = var.assign_public_ip ? one(aws_eip.anvil1_ha[*].public_ip) : null
      key_name                   = one(aws_instance.anvil1[*].key_name)
      iam_profile                = one(aws_instance.anvil1[*].iam_instance_profile)
      placement_group            = one(aws_instance.anvil1[*].placement_group)
      all_private_ips_on_eni_set = toset([])
      floating_ip_candidate      = null
    },
    { # Anvil2
      type                       = "ha_node2"
      id                         = one(aws_instance.anvil2[*].id)
      arn			 = one(aws_instance.anvil[*].arn)
      private_ip                 = one(aws_instance.anvil2[*].private_ip)
      public_ip                  = var.assign_public_ip ? one(aws_eip.anvil2_ha[*].public_ip) : null
      key_name                   = one(aws_instance.anvil2[*].key_name)
      iam_profile                = one(aws_instance.anvil2[*].iam_instance_profile)
      placement_group            = one(aws_instance.anvil2[*].placement_group)
      all_private_ips_on_eni_set = length(aws_network_interface.anvil2_ha_ni) > 0 ? aws_network_interface.anvil2_ha_ni[0].private_ips : toset([])
      floating_ip_candidate      = local.anvil2_ha_ni_secondary_ip
    }
  ] : [])
}

output "dsx_instances" {
  description = "Details of deployed DSX instances."
  sensitive   = false
  value = [
    for i, inst in aws_instance.dsx : {
      index           = i + 1
      id              = inst.id
      arn	      = inst.arn
      private_ip      = inst.private_ip
      public_ip       = inst.public_ip
      key_name        = inst.key_name
      iam_profile     = inst.iam_instance_profile
      placement_group = inst.placement_group
    }
  ]
}

output "dsx_private_ips" {
  description = "A list of the private IP addresses of the deployed DSX instances."
  value       = [for inst in aws_instance.dsx : inst.private_ip]
}

output "primary_management_anvil_instance_id" {
  description = "Instance ID of the primary Anvil node (Anvil for Standalone, Anvil1 for HA)."
  value = coalesce(
    local.create_standalone_anvil && length(aws_instance.anvil) > 0 ? one(aws_instance.anvil[*].id) : null,
    local.create_ha_anvils && length(aws_instance.anvil1) > 0 ? one(aws_instance.anvil1[*].id) : null,
    null
  )
}

output "anvil_standalone_userdata_rendered" {
  description = "Rendered UserData for the Standalone Anvil instance (if created)."
  value       = jsonencode(local.anvil_sa_config_map)
  sensitive   = true
}

output "anvil_ha_node1_userdata_rendered" {
  description = "Rendered UserData for Anvil HA Node 1 (if created)."
  value       = jsonencode(merge(local.anvil_ha_config_map, { "node_index" = "0" }))
  sensitive   = true
}

output "anvil_ha_node2_userdata_rendered" {
  description = "Rendered UserData for Anvil HA Node 2 (if created)."
  value       = jsonencode(merge(local.anvil_ha_config_map, { "node_index" = "1" }))
  sensitive   = true
}

# modules/hammerspace/hammerspace_outputs.tf

output "anvil_ha_load_balancer_dns_name" {
  description = "The public DNS name of the Network Load Balancer for the Anvil HA pair."
  value       = local.create_ha_anvils && var.assign_public_ip ? one(aws_lb.anvil_ha[*].dns_name) : "N/A - Not created."
}
