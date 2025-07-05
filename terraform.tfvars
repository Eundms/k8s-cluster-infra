aws_region             = "us-east-1"
key_name               = "vvue2"
cluster_name           = "vvue-k8s-cluster"
my_ip_cidr             = "0.0.0.0/0"  # ← 반드시 본인 공인 IP로 수정할 것

bastion_instance_type  = "t3.micro"
master_instance_type   = "t3.medium"
worker_instance_type   = "t3.medium"
