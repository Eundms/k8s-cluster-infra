output "bastion_public_ip" {
  description = "Bastion EC2 Public IP"
  value       = aws_eip.bastion_eip.public_ip
}

output "master_private_ip" {
  description = "Kubernetes Master Node Private IP"
  value       = aws_instance.master.private_ip
}

output "worker_private_ips" {
  value = [for w in aws_instance.worker : w.private_ip]
}

