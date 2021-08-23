# 1 step
// setup aws provider and ecr
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "3.55.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

resource "aws_ecr_repository" "demo_repo" {
  name = "demorepo"
  image_tag_mutability = "MUTABLE"
}

# # 2 step
# // build app and push to ecr repo
# aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin ecr_url
# docker build -t demorepo .
# docker tag demorepo:latest ecr_url/demorepo:latest
# docker push ecr_url/demorepo:latest
# terraform apply -var="image_tag=1"

# # 3 step
# // setup ecs cluster
resource "aws_ecs_cluster" "demo_cluster" {
  name = "democluster"
}

# # 4 step
# // setup task and iam role for app
resource "aws_ecs_task_definition" "demo_app_task_definition" {
  family = "DemoappTaskDefinition" 
  container_definitions = <<DEFINITION
  [
    {
      "name": "DemoappTaskDefinition",
      "image": "${aws_ecr_repository.demo_repo.repository_url}:${var.image_tag}",      
      "essential": true,
      "portMappings": [
        {
          "containerPort": 3000,
          "hostPort": 3000
        }
      ],
      "memory": 512,
      "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  memory                   = 512
  cpu                      = 256
  execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role_policy.json}"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role = "${aws_iam_role.ecsTaskExecutionRole.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# # 5 step
# // setup load balancer
resource "aws_default_vpc" "default_vpc" {}
resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "eu-west-1a"
}
resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "eu-west-1b"
}
resource "aws_default_subnet" "default_subnet_c" {
  availability_zone = "eu-west-1c"
}
resource "aws_alb" "application_load_balancer" {
  name = "DemoappLoadbalancer" 
  load_balancer_type = "application"
  subnets = [
    "${aws_default_subnet.default_subnet_a.id}",
    "${aws_default_subnet.default_subnet_b.id}",
    "${aws_default_subnet.default_subnet_c.id}"
  ]
  security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
}

resource "aws_security_group" "load_balancer_security_group" {
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0 
    to_port = 0 
    protocol = "-1" 
    cidr_blocks = ["0.0.0.0/0"] 
  }
}

resource "aws_lb_target_group" "target_group" {
  name = "target-group"
  port = 80
  protocol = "HTTP"
  target_type = "ip"
  vpc_id = "${aws_default_vpc.default_vpc.id}" 
  health_check {
    healthy_threshold = "2"
    unhealthy_threshold = "6"
    interval = "30"
    matcher = "200,301,302"
    path = "/"
    protocol = "HTTP"
    timeout = "5"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = "${aws_alb.application_load_balancer.arn}" 
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.target_group.arn}" 
  }
}

# # 6 step
# // setup service
resource "aws_ecs_service" "demoapp_service" {
  depends_on = [
    aws_ecs_cluster.demo_cluster,
    aws_ecs_task_definition.demo_app_task_definition,
    aws_lb_target_group.target_group,
    aws_security_group.load_balancer_security_group,
    aws_security_group.service_security_group,
  ]
  name = "demoapp_service"
  cluster = "${aws_ecs_cluster.demo_cluster.id}"
  task_definition = "${aws_ecs_task_definition.demo_app_task_definition.arn}"
  launch_type = "FARGATE"
  desired_count = 2

  load_balancer {
    target_group_arn = "${aws_lb_target_group.target_group.arn}"
    container_name = "${aws_ecs_task_definition.demo_app_task_definition.family}"
    container_port = 3000
  }

  network_configuration {
    subnets = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}", "${aws_default_subnet.default_subnet_c.id}"]
    assign_public_ip = true
    security_groups = ["${aws_security_group.service_security_group.id}"]
  }
}

resource "aws_security_group" "service_security_group" {
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
