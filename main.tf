terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.59.0"
    }
  }
}

provider "aws" {
  region  = "eu-west-2"
  profile = "wp"

  default_tags {
    tags = {
      Environment = "dev"
      Owner       = "krasavin"
    }
  }
}

resource "aws_vpc" "custom-vpc" {
  cidr_block           = "10.0.0.0/24"
  enable_dns_hostnames = true

  tags = {
    Name = "MyVPC"
  }
}

resource "aws_subnet" "subnet_1" {
  vpc_id            = aws_vpc.custom-vpc.id
  cidr_block        = "10.0.0.0/25"
  availability_zone = "eu-west-2a"

  tags = {
    Name = "eu-west-2a"
  }
}

resource "aws_subnet" "subnet_2" {
  vpc_id            = aws_vpc.custom-vpc.id
  cidr_block        = "10.0.0.128/25"
  availability_zone = "eu-west-2b"

  tags = {
    Name = "eu-west-2b"
  }
}

resource "aws_internet_gateway" "custom-ig" {
  vpc_id = aws_vpc.custom-vpc.id

  tags = {
    Name = "custom-ig"
  }
  depends_on = [aws_vpc.custom-vpc]
}

resource "aws_route_table" "rt-custom" {
  vpc_id = aws_vpc.custom-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.custom-ig.id
  }

  tags = {
    Name = "rt-custom"
  }
}

resource "aws_route_table_association" "rt_ass_for_subnet1" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.rt-custom.id
}

resource "aws_route_table_association" "rt_ass_for_subnet2" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.rt-custom.id
}

resource "aws_efs_mount_target" "eu-west-2a" {
  file_system_id  = aws_efs_file_system.custom-efs.id
  subnet_id       = aws_subnet.subnet_1.id
  security_groups = [aws_security_group.sg_for_efs.id]
  depends_on      = [aws_efs_file_system.custom-efs, aws_security_group.sg_for_efs]
}

resource "aws_efs_mount_target" "eu-west-2b" {
  file_system_id  = aws_efs_file_system.custom-efs.id
  subnet_id       = aws_subnet.subnet_2.id
  security_groups = [aws_security_group.sg_for_efs.id]
  depends_on      = [aws_efs_file_system.custom-efs, aws_security_group.sg_for_efs]
}

resource "aws_efs_file_system" "custom-efs" {
  encrypted = true
  tags = {
    Name = "MyEFS"
  }
}

resource "aws_security_group" "sg_for_ec2" {
  name        = "sg_for_ec2"
  description = "Allow 22, 443, 80 port inbound traffic"
  vpc_id      = aws_vpc.custom-vpc.id

  ingress {
    description = "SSH access from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "TLS access from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP access from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "sg_for_rds" {
  name        = "SG_for_RDS"
  description = "Allow access to RDS"
  vpc_id      = aws_vpc.custom-vpc.id

  ingress {
    description     = "access to RDS"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_for_ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  depends_on = [aws_security_group.sg_for_ec2]
}

resource "aws_security_group" "sg_for_efs" {
  name        = "sg_for_efs"
  description = "Allow access to EFS"
  vpc_id      = aws_vpc.custom-vpc.id

  ingress {
    description     = "access to EFS from EC2"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_for_ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  depends_on = [aws_security_group.sg_for_ec2]
}

resource "aws_security_group" "sg_for_elb" {
  name        = "SG_for_ELB"
  description = "Allow HTTP access to ELB"
  vpc_id      = aws_vpc.custom-vpc.id

  ingress {
    description = "Access the 80 port from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_for_ec2.id]
  }
  depends_on = [aws_security_group.sg_for_ec2]
}

resource "aws_db_subnet_group" "custom_db_subnet_group" {
  name       = "main"
  subnet_ids = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
}

resource "aws_db_instance" "mysql_instance" {
  identifier                      = "mysql"
  engine                          = "mysql"
  engine_version                  = "8.0.23"
  instance_class                  = "db.t2.micro"
  db_subnet_group_name            = aws_db_subnet_group.custom_db_subnet_group.name
  enabled_cloudwatch_logs_exports = ["general", "error"]
  name                            = var.dbname_for_db_rds
  username                        = var.username_for_db_rds
  password                        = var.password_for_db_rds
  allocated_storage               = 20
  max_allocated_storage           = 0
  backup_retention_period         = 7
  backup_window                   = "04:00-04:30"
  maintenance_window              = "Sun:23:00-Sun:23:30"
  storage_type                    = "gp2"
  vpc_security_group_ids          = [aws_security_group.sg_for_rds.id]
  skip_final_snapshot             = true
  multi_az                        = true
  depends_on                      = [aws_security_group.sg_for_rds, aws_db_subnet_group.custom_db_subnet_group]
}

resource "aws_instance" "wp_1" {
  ami                         = "ami-0dbec48abfe298cab"
  instance_type               = "t2.micro"
  key_name                    = "london_ec2"
  subnet_id                   = aws_subnet.subnet_1.id
  security_groups             = [aws_security_group.sg_for_ec2.id]
  associate_public_ip_address = true
  user_data                   = <<EOF
#!/bin/bash
sudo yum update -y
sudo amazon-linux-extras install -y php7.2
sudo yum install -y httpd php-mysqlnd
sudo systemctl start httpd
sudo systemctl enable httpd
mkdir -p /var/www/html
sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/AllowOverride None/AllowOverride all/' /etc/httpd/conf/httpd.conf
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_file_system.custom-efs.dns_name}:/ /var/www/html
mkdir wp-cli
cd wp-cli
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp
sudo yum -install mysql
cd ~
mkdir wordpress
cd wordpress
wp core download
wp core config --dbhost=${aws_db_instance.mysql_instance.endpoint} --dbname=${var.dbname_for_db_rds} --dbuser=${var.username_for_db_rds} --dbpass=${var.password_for_db_rds}
chmod 644 wp-config.php
sudo mv ./* /var/www/html/
cd ..
rm -r wordpress/
rm -r .wp-cli/
sudo systemctl restart httpd
EOF

  tags = {
    Name = "host-WP-1"
  }

  depends_on = [aws_security_group.sg_for_ec2, aws_db_instance.mysql_instance, aws_efs_mount_target.eu-west-2a]
}

resource "aws_instance" "wp_2" {
  ami                         = "ami-0dbec48abfe298cab"
  instance_type               = "t2.micro"
  key_name                    = "london_ec2"
  subnet_id                   = aws_subnet.subnet_2.id
  security_groups             = [aws_security_group.sg_for_ec2.id]
  associate_public_ip_address = true
  user_data                   = <<EOF
#!/bin/bash
sudo yum update -y
sudo amazon-linux-extras install -y php7.2
sudo yum install -y httpd php-mysqlnd
sudo systemctl start httpd
sudo systemctl enable httpd
mkdir -p /var/www/html
sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/AllowOverride None/AllowOverride all/' /etc/httpd/conf/httpd.conf
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_file_system.custom-efs.dns_name}:/ /var/www/html
mkdir wp-cli
cd wp-cli
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp
sudo yum -install mysql
sudo systemctl restart httpd
EOF

  tags = {
    Name = "host-WP-2"
  }

  depends_on = [aws_security_group.sg_for_ec2, aws_db_instance.mysql_instance, aws_efs_mount_target.eu-west-2b]
}

resource "aws_elb" "custom_elb" {
  name            = "custom-elb"
  security_groups = [aws_security_group.sg_for_elb.id]
  subnets         = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    target              = "TCP:80"
    interval            = 20
  }

  instances = [aws_instance.wp_1.id, aws_instance.wp_2.id]

  cross_zone_load_balancing = true
  idle_timeout              = 60
  depends_on                = [aws_security_group.sg_for_elb, aws_instance.wp_1, aws_instance.wp_2]
}
