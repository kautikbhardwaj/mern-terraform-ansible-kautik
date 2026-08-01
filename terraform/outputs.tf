output "web_public_ip" {
  description = "Public IP of the web server EC2 instance"
  value       = aws_eip.web.public_ip
}

output "web_private_ip" {
  description = "Private IP of the web server EC2 instance"
  value       = aws_instance.web.private_ip
}

output "db_private_ip" {
  description = "Private IP of the database EC2 instance"
  value       = aws_instance.db.private_ip
}

output "application_url" {
  description = "URL of the deployed MERN application"
  value       = "http://${aws_eip.web.public_ip}"
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "ansible_inventory" {
  description = "Ready-to-use Ansible static inventory"
  value       = <<-EOT
    [web]
    ${aws_eip.web.public_ip} ansible_user=ubuntu

    [db]
    ${aws_instance.db.private_ip} ansible_user=ubuntu

    [db:vars]
    ansible_ssh_common_args='-o ProxyJump=ubuntu@${aws_eip.web.public_ip} -o StrictHostKeyChecking=no'

    [all:vars]
    ansible_ssh_private_key_file=~/.ssh/travelmemory
    web_private_ip=${aws_instance.web.private_ip}
    db_private_ip=${aws_instance.db.private_ip}
    web_public_ip=${aws_eip.web.public_ip}
  EOT
}
