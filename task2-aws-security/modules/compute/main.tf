# An EC2 instance in a private subnet, with no inbound rules at all.
#
# Administrative access is Session Manager, which works outbound over the VPC
# endpoints. That is the honest answer to "only necessary ports": the number of
# necessary inbound ports is zero. A bastion on port 22 would add a host to
# patch, a key to distribute and revoke, and an audit trail that lives in
# sshd logs rather than CloudTrail.

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

module "security_group" {
  source = "../../../modules/security-group"

  name        = "${var.name}-app"
  description = "Private application instance for ${var.name}"
  vpc_id      = var.vpc_id

  # Empty on purpose. Nothing needs to reach this instance from anywhere.
  ingress_rules = {}

  egress_rules = {
    # To the interface endpoints for SSM, and to the S3 gateway endpoint.
    # Scoped to the VPC CIDR rather than 0.0.0.0/0, so an instance that is
    # compromised cannot call out to an arbitrary address.
    "https-to-vpc-endpoints" = {
      description = "HTTPS to the VPC interface and gateway endpoints"
      ip_protocol = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = var.vpc_cidr_block
    }
  }

  tags = var.tags
}

resource "aws_instance" "this" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  subnet_id              = var.subnet_id
  vpc_security_group_ids = [module.security_group.id]
  iam_instance_profile   = var.instance_profile_name

  # The subnet does not assign one, but say it explicitly. This is the line a
  # reviewer looks for.
  associate_public_ip_address = false

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

  monitoring = true

  # No key_name. There is no SSH, so there is no key pair to leak.

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    ignore_changes = [ami]
  }
}
