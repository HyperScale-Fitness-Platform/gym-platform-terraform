
resource "aws_db_subnet_group" "this" {
  name       = "${var.service_name}-subnet-group"
  subnet_ids = var.private_subnets
}

resource "aws_security_group" "rds" {
  name   = "${var.service_name}-postgres-sg"
  vpc_id = var.vpc_id

  # Only allow inbound Postgres traffic FROM the EKS node security group
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.service_name}-postgres"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  db_name           = var.db_name

  username = "${var.service_name}_admin"
  password = var.password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  skip_final_snapshot  = true # fine for dev; remove for prod
}