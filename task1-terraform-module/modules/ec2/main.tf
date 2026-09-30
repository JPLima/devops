# An EC2 instance with the defaults AWS does not give you: encrypted storage,
# IMDSv2 required, and an AMI resolved at plan time instead of hardcoded.

# Hardcoding an AMI id pins the instance to one region and one patch level.
# Filtering by owner and name pattern keeps the configuration portable, and
# the owner filter is what stops a lookalike AMI from matching.
data "aws_ami" "amazon_linux" {
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

resource "aws_instance" "this" {
  #checkov:skip=CKV_AWS_88: Task 1 asks for a public web tier, and the caller decides through associate_public_ip_address. Task 2 is the private-by-default design, where this instance has no public IP and no inbound rules at all.
  ami           = data.aws_ami.amazon_linux.id
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

  # IMDSv2 only. Version 1 answers an unauthenticated GET, which is how a
  # server-side request forgery bug turns into leaked role credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # Dedicated bandwidth to EBS instead of sharing the network interface.
  ebs_optimized = true

  monitoring = true

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    # The AMI data source returns a newer id whenever Amazon publishes one.
    # Without this, an unrelated apply would replace a running instance.
    # Replace deliberately by tainting or by bumping an explicit ami variable.
    ignore_changes = [ami]
  }
}
