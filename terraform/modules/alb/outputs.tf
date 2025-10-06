output "alb_arn" {
  description = "The ARN of the load balancer"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "The zone ID of the load balancer"
  value       = aws_lb.this.zone_id
}

output "https_listener_arn" {
  description = "The ARN of the HTTPS listener"
  value       = aws_lb_listener.https.arn
}

output "certificate_arn" {
  description = "The ARN of the ACM certificate"
  value       = aws_acm_certificate.this.arn
}

output "dns_name" {
  description = "The DNS name of the ALB"
  value       = var.hosted_zone_id != "" ? aws_route53_record.alb[0].fqdn : aws_lb.this.dns_name
}
