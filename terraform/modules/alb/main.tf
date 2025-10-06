 /*
 # Already installed
 resource "aws_security_group_rule" "alb_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = var.alb_security_group_id
  description       = "Allow HTTPS traffic from anywhere"
}
*/

# ALB
resource "aws_lb" "this" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids
  
  enable_deletion_protection = false

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-alb"
    }
  )
}

# HTTP Listener (redirects to HTTPS)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS Listener with self-signed certificate
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.this.arn
  
  # Accept self-signed certificate
  lifecycle {
    ignore_changes = [certificate_arn]
  }

  default_action {
    type = "fixed-response"
    
    fixed_response {
      content_type = "text/plain"
      message_body = "No default action configured"
      status_code  = "200"
    }
  }
}

# Self-signed certificate for development
resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "example" {
  private_key_pem = tls_private_key.example.private_key_pem
  
  subject {
    common_name  = "${var.project_name}.${var.domain_name}"
    organization = "Development"
  }

  validity_period_hours = 8760 # 1 year
  
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "this" {
  private_key       = tls_private_key.example.private_key_pem
  certificate_body  = tls_self_signed_cert.example.cert_pem
  
  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-selfsigned-cert"
      Environment = var.environment
      Type        = "Self-Signed"
    }
  )
  
  lifecycle {
    create_before_destroy = true
  }
}

# Route53 Record for ALB (only created if hosted_zone_id is provided)
resource "aws_route53_record" "alb" {
  count = var.hosted_zone_id != "" ? 1 : 0
  
  zone_id = var.hosted_zone_id
  name    = "${var.project_name}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
