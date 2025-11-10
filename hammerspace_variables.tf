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
# modules/hammerspace/hammerspace_variables.tf
#
# This file defines all the input variables for the Hammerspace module.
# -----------------------------------------------------------------------------

variable "common_config" {
  description = "A map containing common configuration values like region, VPC, subnet, etc."
  type = object({
    region               = string
    availability_zone    = string
    vpc_id               = string
    subnet_id            = string
    key_name             = string
    tags                 = map(string)
    project_name         = string
    ssh_keys_dir         = string
    placement_group_name = string
    allowed_source_cidr_blocks = list(string)
  })
}

variable "iam_profile_name" {
  description = "The IAM profile to use for roles and permissions"
  type	      = string
  default     = null
}

variable "iam_profile_group" {
  description = "The IAM group name"
  type       = string
  default     = ""
}

variable "assign_public_ip" {
  description = "Assign a public IP to the Anvil"
  type	      = bool
  default     = false
}

variable "public_subnet_id" {
  description = "The ID of the public subnet where instances requiring a public IP will be launched. Required if assign_public_ip is true."
  type        = string
  default     = null
}

variable "anvil_capacity_reservation_id" {
  description = "The ID of the On-Demand Capacity Reservation to target for Anvil nodes."
  type        = string
  default     = null
}

variable "dsx_capacity_reservation_id" {
  description = "The ID of the On-Demand Capacity Reservation to target for DSX nodes."
  type        = string
  default     = null
}

# --- Hammerspace-specific variables (these remain) ---

variable "ami" {
  description = "AMI ID to use for Hammerspace Anvil and DSX instances."
  type        = string
}

variable "iam_user_access" {
  description = "Enable admin access for users in the specified IAM group ('Enable' or 'Disable')."
  type        = string
  default     = "Disable"
  validation {
    condition     = contains(["Enable", "Disable"], var.iam_user_access)
    error_message = "Allowed values for iam_user_access are 'Enable' or 'Disable'."
  }
}

variable "anvil_security_group_id" {
  description = "Optional: The ID of an existing security group to use for the Anvil nodes. If provided, the module will not create a new one."
  type        = string
  default     = ""
}

variable "dsx_security_group_id" {
  description = "Optional: The ID of an existing security group to use for the DSX nodes. If provided, the module will not create a new one."
  type        = string
  default     = ""
}

variable "anvil_count" {
  description = "Number of Anvil instances to deploy. 0 = no Anvils; 1 = Standalone; 2+ = HA (2-node)."
  type        = number
  default     = 1
}

variable "sa_anvil_destruction" {
  description = "Set to true to allow the standalone Anvil to be destroyed. This is a safety mechanism to prevent accidental destruction."
  type        = bool
  default     = false
}

variable "anvil_type" {
  description = "EC2 instance type for Anvil metadata servers (e.g., 'm5zn.12xlarge')."
  type        = string
}

variable "dsx_type" {
  description = "EC2 instance type for DSX data services nodes (e.g., 'm5.xlarge')."
  type        = string
}

variable "dsx_count" {
  description = "Number of DSX instances to create (0-8)."
  type        = number
  default     = 1
}

variable "anvil_meta_disk_size" {
  description = "Anvil Metadata Disk Size in GB."
  type        = number
  default     = 1000
}

variable "anvil_meta_disk_type" {
  description = "Anvil Metadata Disk type (e.g., 'gp2', 'gp3', 'io1', 'io2')."
  type        = string
  default     = "gp3"
}

variable "anvil_meta_disk_iops" {
  description = "IOPS for Anvil metadata disk (required for io1/io2, optional for gp3)."
  type        = number
  default     = null
}

variable "anvil_meta_disk_throughput" {
  description = "Throughput in MiB/s for Anvil metadata disk (relevant for gp3)."
  type        = number
  default     = null
}

variable "dsx_ebs_size" {
  description = "Size of each EBS Data volume per DSX instance in GB."
  type        = number
  default     = 200
}

variable "dsx_ebs_type" {
  description = "Type of each EBS Data volume for DSX (e.g., 'gp2', 'gp3', 'io1', 'io2')."
  type        = string
  default     = "gp3"
}

variable "dsx_ebs_iops" {
  description = "IOPS for each EBS Data volume for DSX (required for io1/io2, optional for gp3)."
  type        = number
  default     = null
}

variable "dsx_ebs_throughput" {
  description = "Throughput in MiB/s for each EBS Data volume for DSX (relevant for gp3)."
  type        = number
  default     = null
}

variable "dsx_ebs_count" {
  description = "Number of data EBS volumes to attach to each DSX instance."
  type        = number
  default     = 1
  validation {
    condition     = var.dsx_ebs_count >= 0
    error_message = "The number of data EBS volumes per DSX instance must be non-negative."
  }
  validation {
    condition     = var.dsx_count == 0 || var.dsx_ebs_count >= 1
    error_message = "If dsx_count is greater than 0, dsx_ebs_count must be at least 1."
  }
}

variable "dsx_add_vols" {
  description = "Add non-boot EBS volumes as Hammerspace storage volumes."
  type        = bool
  default     = true
}

variable "sec_ip_cidr" {
  description = "Permitted IP/CIDR for Security Group Ingress. Use '0.0.0.0/0' for open access (not recommended for production)."
  type        = string
  default     = "0.0.0.0/0"
  validation {
    condition     = can(regex("^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/(?:3[0-2]|[12]?[0-9]?)$", var.sec_ip_cidr))
    error_message = "Security IP CIDR must be a valid CIDR block."
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
