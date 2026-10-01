resource "aws_sns_topic" "security" {
  name              = "${var.name}-security-alerts"
  kms_master_key_id = var.kms_key_arn

  tags = merge(var.tags, { Name = "${var.name}-security-alerts" })
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.notification_emails)

  topic_arn = aws_sns_topic.security.arn
  protocol  = "email"
  endpoint  = each.value
}

locals {
  # Keyed by name, so adding a detection is one map entry. Patterns are
  # CloudWatch Logs filter syntax over the CloudTrail event JSON.
  alarms = {
    "unauthorized-api-calls" = {
      description = "An API call was denied. In volume, this is someone probing."
      pattern     = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"
      threshold   = 5
      periods     = 1
    }

    "root-account-usage" = {
      description = "The root user did something. It should never be used for daily work."
      pattern     = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
      threshold   = 1
      periods     = 1
    }

    "console-login-without-mfa" = {
      description = "A console sign-in succeeded without MFA."
      pattern     = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") && ($.responseElements.ConsoleLogin = \"Success\") }"
      threshold   = 1
      periods     = 1
    }

    "iam-policy-changes" = {
      description = "Someone changed IAM policy. Legitimate, but never unnoticed."
      pattern     = "{ ($.eventName = Put*Policy) || ($.eventName = Delete*Policy) || ($.eventName = Attach*Policy) || ($.eventName = Detach*Policy) || ($.eventName = Create*Policy) }"
      threshold   = 1
      periods     = 1
    }

    "cloudtrail-config-changes" = {
      description = "The trail itself was changed, stopped or deleted. This is what covering tracks looks like."
      pattern     = "{ ($.eventName = CreateTrail) || ($.eventName = UpdateTrail) || ($.eventName = DeleteTrail) || ($.eventName = StartLogging) || ($.eventName = StopLogging) }"
      threshold   = 1
      periods     = 1
    }

    "security-group-changes" = {
      description = "A security group rule was authorised or revoked outside Terraform."
      pattern     = "{ ($.eventName = AuthorizeSecurityGroup*) || ($.eventName = RevokeSecurityGroup*) || ($.eventName = CreateSecurityGroup) || ($.eventName = DeleteSecurityGroup) }"
      threshold   = 1
      periods     = 1
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "this" {
  for_each = local.alarms

  name           = "${var.name}-${each.key}"
  log_group_name = var.log_group_name
  pattern        = each.value.pattern

  metric_transformation {
    name      = each.key
    namespace = var.metric_namespace
    value     = "1"

    # Without this the metric has no datapoint when nothing matches and the
    # alarm sits in INSUFFICIENT_DATA rather than OK.
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name        = "${var.name}-${each.key}"
  alarm_description = each.value.description

  namespace   = var.metric_namespace
  metric_name = each.key
  statistic   = "Sum"
  period      = 300

  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = each.value.threshold
  evaluation_periods  = each.value.periods

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.security.arn]
  ok_actions    = [aws_sns_topic.security.arn]

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })

  depends_on = [aws_cloudwatch_log_metric_filter.this]
}
