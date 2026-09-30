# An EC2 instance with the defaults AWS does not give you: encrypted storage,
# IMDSv2 required, no public address unless asked for, and an AMI resolved at
# plan time instead of hardcoded.
#
# One module serves both a public web tier and a private instance reached
# through SSM. The difference is associate_public_ip_address and which subnet
# it lands in, not a second copy of this file.

# Hardcoding an AMI id pins the instance to one region and one patch level.
# Filtering by owner and name pattern keeps the configuration portable, and
# the owner filter is what stops a lookalike AMI from matching.
data "aws_ami" "amazon_linux" {
  count = var.ami_id == null ? 1 : 0

  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami_id = var.ami_id != null ? var.ami_id : data.aws_ami.amazon_linux[0].id
}

resource "aws_instance" "this" {
  #checkov:skip=CKV_AWS_88: The caller decides, and it defaults to false. A public web tier opts in explicitly; the private design leaves it off and reaches the instance through SSM.
  ami           = local.ami_id
  instance_type = var.instance_type

  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  associate_public_ip_address = var.associate_public_ip_address
  iam_instance_profile        = var.iam_instance_profile
  user_data                   = var.user_data

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    kms_key_id            = var.kms_key_arn
    delete_on_termination = true

    tags = merge(var.tags, { Name = "${var.name}-root" })
  }

  # IMDSv2 only, and a hop limit of 1. Version 1 answers an unauthenticated
  # GET, which is how a server-side request forgery bug in an application turns
  # into leaked role credentials. The hop limit stops a container on the host
  # from reaching the metadata service through the bridge.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # Dedicated bandwidth to EBS instead of sharing the network interface.
  ebs_optimized = true

  monitoring = var.detailed_monitoring

  # No key_name. Access is SSM Session Manager, so there is no key pair to
  # distribute, rotate or leak, and every session is a CloudTrail event.

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    # The AMI data source returns a newer id whenever Amazon publishes one.
    # Without this, an unrelated apply would replace a running instance.
    # Replace deliberately by tainting or by setting ami_id.
    ignore_changes = [ami]
  }
}
