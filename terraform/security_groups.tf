resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Web server: SSH from admin IP, HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "web_ssh" {
  security_group_id = aws_security_group.web.id
  description       = "SSH from admin IP only"
  cidr_ipv4         = var.my_ip_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "web_http" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP"
  cidr_ipv4         = var.allow_http_from
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "web_https" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS"
  cidr_ipv4         = var.allow_http_from
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "web_all" {
  security_group_id = aws_security_group.web.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Database server: SSH and MongoDB only from the web server SG"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_ssh_from_web" {
  security_group_id            = aws_security_group.db.id
  description                  = "SSH via bastion (web server) only"
  referenced_security_group_id = aws_security_group.web.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "db_mongo_from_web" {
  security_group_id            = aws_security_group.db.id
  description                  = "MongoDB from web server only"
  referenced_security_group_id = aws_security_group.web.id
  from_port                    = 27017
  to_port                      = 27017
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "db_all" {
  security_group_id = aws_security_group.db.id
  description       = "All outbound via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
