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
# modules/hammerspace/hammerspace_main.tf
#
# This file contains the main logic for the Hammerspace module. It creates
# all the necessary AWS resources for Anvil and DSX nodes.
# -----------------------------------------------------------------------------

# --- IAM Resources ---

resource "aws_iam_group" "admin_group" {
  count = local.create_iam_admin_group ? 1 : 0
  name  = (
    var.iam_profile_group != ""
      ? var.iam_profile_group
      : "${var.common_config.project_name}-AnvilAdminGroup"
  )
  path  = "/users/"
}

resource "aws_iam_role" "instance_role" {
  count = local.create_profile ? 1 : 0
  name  = "${var.common_config.project_name}-InstanceRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-IAM-Role" })
}

resource "aws_iam_role_policy" "ssh_policy" {
  count = local.create_profile ? 1 : 0
  name  = "IAMAccessSshPolicy"
  role  = aws_iam_role.instance_role[0].id
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Sid      = "1",
      Effect   = "Allow",
      Action   = ["iam:ListSSHPublicKeys", "iam:GetSSHPublicKey", "iam:GetGroup"],
      Resource = compact(["arn:${data.aws_partition.current.partition}:iam::*:user/*", local.effective_iam_admin_group_arn])
    }]
  })
}

resource "aws_iam_role_policy" "ha_instance_policy" {
  count = local.create_profile ? 1 : 0
  name  = "HAInstancePolicy"
  role  = aws_iam_role.instance_role[0].id
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ Sid = "2", Effect = "Allow", Action = ["ec2:DescribeInstances", "ec2:DescribeInstanceAttribute", "ec2:DescribeTags"], Resource = ["*"] }]
  })
}

resource "aws_iam_role_policy" "floating_ip_policy" {
  count = local.create_profile ? 1 : 0
  name  = "FloatingIpPolicy"
  role  = aws_iam_role.instance_role[0].id
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ Sid = "3", Effect = "Allow", Action = ["ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses"], Resource = ["*"] }]
  })
}

resource "aws_iam_role_policy" "anvil_metering_policy" {
  count = local.create_profile ? 1 : 0
  name  = "AnvilMeteringPolicy"
  role  = aws_iam_role.instance_role[0].id
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ Sid = "4", Effect = "Allow", Action = ["aws-marketplace:MeterUsage"], Resource = ["*"] }]
  })
}

resource "aws_iam_instance_profile" "profile" {
  count = local.create_profile ? 1 : 0
  name  = "${var.common_config.project_name}-InstanceProfile"
  role  = aws_iam_role.instance_role[0].name
  tags = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-IAM-Profile" })
}

# --- Security Groups ---

resource "aws_security_group" "anvil_data_sg" {
  count       = local.should_create_any_anvils && var.anvil_security_group_id == "" ? 1 : 0
  name        = "${local.anvil_resource_prefix}-sg"
  description = "Security group for Anvil metadata servers"
  vpc_id      = var.common_config.vpc_id
  tags = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-Anvil-sg" })

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    description = "Egress from Anvil for ANY protocol"
    cidr_blocks = [var.sec_ip_cidr]
  }

  # Rule 1: Allow all ICMP (Ping)
  
  ingress {
    protocol    = "icmp"
    from_port   = -1
    to_port     = -1
    description = "Ingress to Anvil for ICMP protocol"
    cidr_blocks = var.common_config.allowed_source_cidr_blocks
  }

  # Rule 2: Allow all TCP traffic
  
  ingress {
    protocol    = "tcp"
    from_port   = 0
    to_port     = 65535
    cidr_blocks = var.common_config.allowed_source_cidr_blocks
    description = "Allow all TCP traffic from specified sources"
  }

  # Rule 3: Allows traffic from the NLB in the public subnet
  
  ingress {
    description = "Allow inbound from NLB for HA Floating IP"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    # Only allow traffic from the public subnet where the NLB resides
    cidr_blocks = local.create_ha_anvils && var.assign_public_ip && var.public_subnet_id != null ? [data.aws_subnet.public[0].cidr_block] : []
  }
  
  # Rule 4: Allow all UDP traffic
  
  ingress {
    protocol    = "udp"
    from_port   = 0
    to_port     = 65535
    description = "Ingress to Anvil for UCP protocol for all ports"
    cidr_blocks = var.common_config.allowed_source_cidr_blocks
  }
}

resource "aws_security_group" "dsx_sg" {
  count       = var.dsx_count > 0 && var.dsx_security_group_id == "" ? 1 : 0
  name        = "${local.dsx_resource_prefix}-sg"
  description = "Security group for DSX data services nodes"
  vpc_id      = var.common_config.vpc_id
  tags = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-DSX-sg" })

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    description = "Egress from DSX for all protocols and ports"
    cidr_blocks = [var.sec_ip_cidr]
  }

  # Rule 1: Allow all ICMP (Ping)
  
  ingress {
    protocol    = "icmp"
    from_port   = -1
    to_port     = -1
    description = "Ingress to DSX for ICMP"
    cidr_blocks = var.common_config.allowed_source_cidr_blocks
  }

  # Rule 2: Allow all TCP traffic
  
  ingress {
    protocol    = "tcp"
    from_port   = 0
    to_port     = 65535
    description = "Allow all TCP traffic from specified sources"
    cidr_blocks = var.common_config.allowed_source_cidr_blocks
  }

  # Rule 3: Allow all UDP traffic
  
  ingress {
    protocol    = "udp"
    from_port   = 0
    to_port     = 65535
    description = "Allow all UDP traffic from specified sources"
    cidr_blocks = var.common_config.allowed_source_cidr_blocks
  }
}

# --- Anvil Standalone Resources ---

resource "aws_network_interface" "anvil_sa_ni" {
  count           = local.create_standalone_anvil ? 1 : 0
  subnet_id       = var.assign_public_ip && var.public_subnet_id != null ? var.public_subnet_id : var.common_config.subnet_id
  security_groups = local.effective_anvil_sg_id != null ? [local.effective_anvil_sg_id] : []
  tags            = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-Anvil-NI" })
  depends_on      = [aws_security_group.anvil_data_sg]
}

resource "aws_eip" "anvil_sa" {
  count  = local.create_standalone_anvil && var.assign_public_ip ? 1 : 0
  domain = "vpc"
  tags   = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-Anvil-EIP" })
}

resource "aws_eip_association" "anvil_sa" {
  count                = local.create_standalone_anvil && var.assign_public_ip ? 1 : 0
  network_interface_id = aws_network_interface.anvil_sa_ni[0].id
  allocation_id        = aws_eip.anvil_sa[0].id
}

resource "aws_instance" "anvil" {
  count                 = local.create_standalone_anvil ? 1 : 0
  ami                   = var.ami
  instance_type         = local.anvil_instance_type_actual
  availability_zone     = var.common_config.availability_zone
  key_name              = local.provides_key_name ? var.common_config.key_name : null
  iam_instance_profile  = local.effective_instance_profile_ref
  user_data_base64      = base64encode(jsonencode(local.anvil_sa_config_map))
  placement_group       = var.common_config.placement_group_name

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.anvil_sa_ni[0].id
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 200
  }

  capacity_reservation_specification {
    capacity_reservation_target {
      capacity_reservation_id = var.anvil_capacity_reservation_id
    }
  }

  lifecycle {
    precondition {
      condition     = !(var.assign_public_ip && var.public_subnet_id == null)
      error_message = "If 'assign_public_ip' is true for Hammerspace Anvil, 'public_subnet_id' must be provided."
    }
    precondition {
      condition     = var.sa_anvil_destruction == true
      error_message = "The standalone Anvil is protected. To destroy it, set 'sa_anvil_destruction = true'."
    }
    precondition {
      condition	    = local.anvil_instance_type_is_available
      error_message = (
        var.common_config.availability_zone != null
	  ? "ERROR: Instance type ${local.anvil_instance_type_actual} for Hammerspace is not available in AZ ${var.common_config.availability_zone}."
	  : "ERROR: Instance type ${local.anvil_instance_type_actual} for Hammerspace is not available in the selected Availability Zone (unable to determine AZ; please verify subnet/VPC configuration)."
      )
    }
  }

  tags = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-Anvil" })

  depends_on = [
    aws_iam_instance_profile.profile
  ]
}

resource "aws_ebs_volume" "anvil_meta_vol" {
  count             = local.create_standalone_anvil ? 1 : 0
  availability_zone = var.common_config.availability_zone
  size              = var.anvil_meta_disk_size
  type              = var.anvil_meta_disk_type
  iops              = contains(["io1", "io2", "gp3"], var.anvil_meta_disk_type) ? var.anvil_meta_disk_iops : null
  throughput        = var.anvil_meta_disk_type == "gp3" ? var.anvil_meta_disk_throughput : null
  tags              = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-Anvil-MetaVol" })
}

resource "aws_volume_attachment" "anvil_meta_vol_attach" {
  count       = local.create_standalone_anvil ? 1 : 0
  device_name = "/dev/sdb"
  instance_id = aws_instance.anvil[0].id
  volume_id   = aws_ebs_volume.anvil_meta_vol[0].id
}

# --- Anvil HA Resources ---

resource "aws_network_interface" "anvil1_ha_ni" {
  count           = local.create_ha_anvils ? 1 : 0
  subnet_id       = var.common_config.subnet_id
  security_groups = local.effective_anvil_sg_id != null ? [local.effective_anvil_sg_id] : []
  tags            = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-Anvil1-NI" })
  depends_on      = [aws_security_group.anvil_data_sg]
}

resource "aws_eip" "anvil1_ha" {
#  count  = local.create_ha_anvils && var.assign_public_ip ? 1 : 0
  count  = 0
  domain = "vpc"
  tags   = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-Anvil1-EIP" })
}

resource "aws_eip_association" "anvil1_ha" {
#  count                = local.create_ha_anvils && var.assign_public_ip ? 1 : 0
  count                = 0
  network_interface_id = aws_network_interface.anvil1_ha_ni[0].id
  allocation_id        = aws_eip.anvil1_ha[0].id
}

resource "aws_instance" "anvil1" {
  count                 = local.create_ha_anvils ? 1 : 0
  ami                   = var.ami
  instance_type         = local.anvil_instance_type_actual
  availability_zone     = var.common_config.availability_zone
  key_name              = local.provides_key_name ? var.common_config.key_name : null
  iam_instance_profile  = local.effective_instance_profile_ref
  user_data_base64      = base64encode(jsonencode(merge(local.anvil_ha_config_map, { "node_index" = "0" })))
  placement_group       = var.common_config.placement_group_name

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.anvil1_ha_ni[0].id
  }

  root_block_device {
    volume_type		  = "gp3"
    volume_size 	  = 200
    delete_on_termination = true
  }

  capacity_reservation_specification {
    capacity_reservation_target {
      capacity_reservation_id = var.anvil_capacity_reservation_id
    }
  }

  lifecycle {
    precondition {
      condition     = !(var.assign_public_ip && var.public_subnet_id == null)
      error_message = "If 'assign_public_ip' is true for Hammerspace Anvil, 'public_subnet_id' must be provided."
    }
    precondition {
      condition     = length(aws_instance.anvil) == 0
      error_message = "Changing from a 1-node standalone Anvil to a 2-node HA Anvil is a destructive action and is not allowed. Please destroy the old environment first and then create the new HA environment."
    }
    precondition {
      condition	    = local.anvil_instance_type_is_available
      error_message = "ERROR: Instance type ${var.anvil_type} for the Anvil is not available in AZ ${var.common_config.availability_zone}."
    }
  }

  tags = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-Anvil1", Index = "0" })

  depends_on = [
    aws_iam_instance_profile.profile
  ]
}

resource "aws_ebs_volume" "anvil1_meta_vol" {
  count             = local.create_ha_anvils ? 1 : 0
  availability_zone = var.common_config.availability_zone
  size              = var.anvil_meta_disk_size
  type              = var.anvil_meta_disk_type
  iops              = contains(["io1", "io2", "gp3"], var.anvil_meta_disk_type) ? var.anvil_meta_disk_iops : null
  throughput        = var.anvil_meta_disk_type == "gp3" ? var.anvil_meta_disk_throughput : null
  tags              = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-Anvil1-MetaVol" })
}

resource "aws_volume_attachment" "anvil1_meta_vol_attach" {
  count       = local.create_ha_anvils ? 1 : 0
  device_name = "/dev/sdb"
  instance_id = aws_instance.anvil1[0].id
  volume_id   = aws_ebs_volume.anvil1_meta_vol[0].id
}

resource "aws_network_interface" "anvil2_ha_ni" {
  count             = local.create_ha_anvils ? 1 : 0
  subnet_id         = var.common_config.subnet_id
  security_groups   = local.effective_anvil_sg_id != null ? [local.effective_anvil_sg_id] : []
  private_ips_count = 1
  tags              = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-Anvil2-NI" })
  depends_on        = [aws_security_group.anvil_data_sg]
}

resource "aws_eip" "anvil2_ha" {
#  count  = local.create_ha_anvils && var.assign_public_ip ? 1 : 0
  count  = 0
  domain = "vpc"
  tags   = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-Anvil2-EIP" })
}

resource "aws_eip_association" "anvil2_ha" {
#  count                = local.create_ha_anvils && var.assign_public_ip ? 1 : 0
  count                = 0
  network_interface_id = aws_network_interface.anvil2_ha_ni[0].id
  allocation_id        = aws_eip.anvil2_ha[0].id
}

resource "aws_instance" "anvil2" {
  count                 = local.create_ha_anvils ? 1 : 0
  ami                   = var.ami
  instance_type         = local.anvil_instance_type_actual
  availability_zone     = var.common_config.availability_zone
  key_name              = local.provides_key_name ? var.common_config.key_name : null
  iam_instance_profile  = local.effective_instance_profile_ref
  user_data_base64      = base64encode(jsonencode(merge(local.anvil_ha_config_map, { "node_index" = "1" })))
  placement_group       = var.common_config.placement_group_name

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.anvil2_ha_ni[0].id
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size 	  = 200
    delete_on_termination = true
  }

  capacity_reservation_specification {
    capacity_reservation_target {
      capacity_reservation_id = var.anvil_capacity_reservation_id
    }
  }

  lifecycle {
    precondition {
      condition     = !(var.assign_public_ip && var.public_subnet_id == null)
      error_message = "If 'assign_public_ip' is true for Hammerspace Anvil, 'public_subnet_id' must be provided."
    }
    precondition {
      condition     = length(aws_instance.anvil) == 0
      error_message = "Changing from a 1-node standalone Anvil to a 2-node HA Anvil is a destructive action and is not allowed. Please destroy the old environment first and then create the new HA environment."
    }
    precondition {
      condition	    = local.anvil_instance_type_is_available
      error_message = "ERROR: Instance type ${var.anvil_type} for the Anvil is not available in AZ ${var.common_config.availability_zone}."
    }
  }

  tags = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-Anvil2", Index = "1" })

  depends_on = [
    aws_instance.anvil1,
    aws_iam_instance_profile.profile,
  ]
}

resource "aws_ebs_volume" "anvil2_meta_vol" {
  count             = local.create_ha_anvils ? 1 : 0
  availability_zone = length(aws_instance.anvil2) > 0 ? aws_instance.anvil2[0].availability_zone : var.common_config.availability_zone
  size              = var.anvil_meta_disk_size
  type              = var.anvil_meta_disk_type
  iops              = contains(["io1", "io2", "gp3"], var.anvil_meta_disk_type) ? var.anvil_meta_disk_iops : null
  throughput        = var.anvil_meta_disk_type == "gp3" ? var.anvil_meta_disk_throughput : null
  tags              = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-Anvil2-MetaVol" })
}

resource "aws_volume_attachment" "anvil2_meta_vol_attach" {
  count       = local.create_ha_anvils ? 1 : 0
  device_name = "/dev/sdb"
  instance_id = aws_instance.anvil2[0].id
  volume_id   = aws_ebs_volume.anvil2_meta_vol[0].id
}

# --- DSX Data Services Node Resources ---

resource "aws_network_interface" "dsx_ni" {
  count               = var.dsx_count
  subnet_id           = var.assign_public_ip && var.public_subnet_id != null ? var.public_subnet_id : var.common_config.subnet_id
  security_groups     = local.effective_dsx_sg_id != null ? [local.effective_dsx_sg_id] : []
  source_dest_check   = false
  tags                = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-DSX${count.index + 1}-NI" })
  depends_on          = [aws_security_group.dsx_sg]
}

resource "aws_instance" "dsx" {
  count                 = var.dsx_count
  ami                   = var.ami
  instance_type         = local.dsx_instance_type_actual
  availability_zone     = var.common_config.availability_zone
  key_name              = local.provides_key_name ? var.common_config.key_name : null
  iam_instance_profile  = local.effective_instance_profile_ref
  placement_group       = var.common_config.placement_group_name

  user_data_base64 = base64encode(jsonencode({
    cluster = {
      password_auth = false,
      password      = local.effective_anvil_id_for_dsx_password,
      metadata = {
        ips = (local.effective_anvil_ip_for_dsx_metadata != null ? ["${local.effective_anvil_ip_for_dsx_metadata}/20"] : [])
      }
    }
    nodes = merge(
      {
        "0" = {
          hostname    = "${var.common_config.project_name}DSX${count.index + 1}"
          features    = ["storage", "portal"]
          add_volumes = local.dsx_add_volumes_bool
          networks = {
            eth0 = {
              roles = ["data", "mgmt"]
            }
          }
        }
      },
      local.anvil_nodes_map_for_dsx
    )
    aws = local.aws_config_map
  }))

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.dsx_ni[count.index].id
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size 	  = 200
    delete_on_termination = true
  }

  # Define the data volumes inline using a dynamic block.
  # The 'delete_on_termination' arguments defaults to 'true' here

  dynamic "ebs_block_device" {
    for_each = range(var.dsx_ebs_count)
    content {
      device_name	  = "/dev/xvd${local.device_letters[ebs_block_device.key]}"
      volume_type	  = var.dsx_ebs_type
      volume_size	  = var.dsx_ebs_size
      iops		  = var.dsx_ebs_iops
      throughput	  = var.dsx_ebs_throughput
      delete_on_termination = true
    }
  }
  
  capacity_reservation_specification {
    capacity_reservation_target {
      capacity_reservation_id = var.dsx_capacity_reservation_id
    }
  }

  lifecycle {
    precondition {
      condition     = !(var.assign_public_ip && var.public_subnet_id == null)
      error_message = "If 'assign_public_ip' is true for Hammerspace DSX, 'public_subnet_id' must be provided."
    }
    precondition {
      condition	    = local.dsx_instance_type_is_available
      error_message = "ERROR: Instance type ${var.dsx_type} for the DSX is not available in AZ ${var.common_config.availability_zone}."
    }
  }

  tags = merge(local.common_tags,
    { Name = "${var.common_config.project_name}-DSX${count.index + 1}" })

  depends_on = [
    aws_iam_instance_profile.profile
  ]
}

# -----------------------------------------------------------------------------
# Anvil HA Network Load Balancer (Conditional)
# These resources are only created if deploying an HA pair with a public IP.
# -----------------------------------------------------------------------------

# Data source to get the CIDR block of the public subnet for the security group rule.

data "aws_subnet" "public" {
  count = local.create_ha_anvils && var.assign_public_ip && var.public_subnet_id != null ? 1 : 0
  id    = var.public_subnet_id
}

# Create the Network Load Balancer in the public subnet

resource "aws_lb" "anvil_ha" {
  count = local.create_ha_anvils && var.assign_public_ip ? 1 : 0

  name               = "${var.common_config.project_name}-anvil-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [var.public_subnet_id]

  enable_cross_zone_load_balancing = true

  tags = merge(local.common_tags, {
    Name = "${var.common_config.project_name}-anvil-nlb"
  })
}

# Create the Target Group to point to the private floating IP

resource "aws_lb_target_group" "anvil_ha" {
  count = local.create_ha_anvils && var.assign_public_ip ? 1 : 0

  name        = "${var.common_config.project_name}-anvil-floating-ip-tg"
  port        = 443 # Default HTTPS port for the Anvil management UI
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = var.common_config.vpc_id

  health_check {
    protocol = "TCP"
    port     = "traffic-port"
  }

  tags = merge(local.common_tags, {
    Name = "${var.common_config.project_name}-anvil-floating-ip-tg"
  })
}

# Create the Listener to forward traffic

resource "aws_lb_listener" "anvil_ha_https" {
  count = local.create_ha_anvils && var.assign_public_ip ? 1 : 0

  load_balancer_arn = aws_lb.anvil_ha[0].arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.anvil_ha[0].arn
  }
}

# Attach the private floating IP address to the target group

resource "aws_lb_target_group_attachment" "anvil_ha_floating_ip" {
  # Only create this if the floating IP has been determined
  count = local.create_ha_anvils && var.assign_public_ip ? 1 : 0

  target_group_arn = aws_lb_target_group.anvil_ha[0].arn
  target_id        = local.anvil2_ha_ni_secondary_ip
  port             = 443

  # Ensure the target group exists before trying to attach to it
  depends_on = [aws_lb_target_group.anvil_ha]
}
