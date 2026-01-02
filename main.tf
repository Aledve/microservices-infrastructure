terraform { 
  cloud { 
    
    organization = "crm-project" 

    workspaces { 
      name = "smart-parking-infrastructure" 
    } 
  } 
}

provider "aws" {
  region = "us-east-1"
}


#---MODULES---
module "vpc_parking" {
  source          = "./modules/vpc"
  vpc_cidr        = var.vpc_cidr
  azs             = var.azs
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
}

module "ecs_sg" {
  source          = "./modules/security_groups"
  vpc_id          = module.vpc_parking.vpc_id
  vpc_cidr        = module.vpc_parking.vpc_cidr
  security_groups = var.security_groups
}

module "alb" {
  source          = "./modules/alb"
  name            = "smart-parking-alb"
  internal        = false
  security_groups = [module.ecs_sg.sg_person_service_id]
  subnets         = module.vpc_crm.public_subnet_ids
}

# --- RULES: Core Services (Identidad) ---
# Se mantienen igual, son necesarios para el Login

module "person_service_alb_rule" {
  source            = "./modules/alb_rule"
  name              = "person-tg"
  port              = 10011
  vpc_id            = module.vpc_crm.vpc_id
  listener_arn      = module.alb.listener_arn
  priority          = 1
  path              = "/personService"
  health_check_path = "/personService"
  health_check_port = "10011"
}

module "role_service_alb_rule" {
  source            = "./modules/alb_rule"
  name              = "role-tg"
  port              = 10094
  vpc_id            = module.vpc_crm.vpc_id
  listener_arn      = module.alb.listener_arn
  priority          = 2
  path              = "/roleService"
  health_check_path = "/roleService"
  health_check_port = "10094"
}

module "user_service_alb_rule" {
  source            = "./modules/alb_rule"
  name              = "user-tg"
  port              = 10021
  vpc_id            = module.vpc_crm.vpc_id
  listener_arn      = module.alb.listener_arn
  priority          = 3
  path              = "/userService"
  health_check_path = "/userService"
  health_check_port = "10021"
}


module "vehicle_service_alb_rule" {
  source             = "./modules/alb_rule"
  name               = "vehicle-tg"
  port               = 10041
  vpc_id             = module.vpc_parking.vpc_id
  listener_arn       = module.alb.listener_arn
  priority           = 4
  path               = "/vehicleService"
  health_check_path  = "/vehicleService"
  health_check_port  = "10041"
}
module "tariff_service_alb_rule" {
  source             = "./modules/alb_rule"
  name               = "tariff-tg"
  port               = 10061
  vpc_id             = module.vpc_parking.vpc_id
  listener_arn       = module.alb.listener_arn
  priority           = 5
  path               = "/tariffService"
  health_check_path  = "/tariffService"
  health_check_port  = "10061"
}

module "session_service_alb_rule" {
  source             = "./modules/alb_rule"
  name               = "session-tg"
  port               = 10081
  vpc_id             = module.vpc_crm.vpc_id
  listener_arn       = module.alb.listener_arn
  priority           = 6
  path               = "/sessionService"
  health_check_path  = "/sessionService"
  health_check_port  = "10081"
}

module "authentication_service_alb_rule" {
  source             = "./modules/alb_rule"
  name               = "authentication-tg"
  port               = 10061
  vpc_id             = module.vpc_crm.vpc_id
  listener_arn       = module.alb.listener_arn
  priority           = 7
  path               = "/authService"
  health_check_path  = "/authService"
  health_check_port  = "10061"
}

module "zone_service_alb_rule" {
  source             = "./modules/alb_rule"
  name               = "zone-tg"
  port               = 10051
  vpc_id             = module.vpc_parking.vpc_id
  listener_arn       = module.alb.listener_arn
  priority           = 8
  path               = "/zoneService"
  health_check_path  = "/zoneService"
  health_check_port  = "10051"
}

module "reservation_service_alb_rule" {
  source             = "./modules/alb_rule"
  name               = "reservation-tg"
  port               = 10071
  vpc_id             = module.vpc_parking.vpc_id
  listener_arn       = module.alb.listener_arn
  priority           = 9
  path               = "/reservationService"
  health_check_path  = "/reservationService"
  health_check_port  = "10071"
}

module "sensor_service_alb_rule" {
  source             = "./modules/alb_rule"
  name               = "sensor-tg"
  port               = 10103
  vpc_id             = module.vpc_parking.vpc_id
  listener_arn       = module.alb.listener_arn
  priority           = 10
  path               = "/sensorService"
  health_check_path  = "/sensorService"
  health_check_port  = "10103"
}

#---API GATEWAY---

module "api_gateway" {
  source  = "./modules/api_gateway"
  name    = "smart-parking-api"
  alb_url = "http://${module.alb.alb_dns_name}"

  routes = [
    "/reservationService",
    "/userService",
    "/personService",
    "/tariffService",
    "/sensorService",
    "/roleService",
    "/sessionService",
    "/vehicleService",
    "/authService",
    "/zoneService"
  ]
}

#--- CLUSTER ECS ---
resource "aws_ecs_cluster" "parking_cluster" {
  name = "smart-parking-cluster"
}

resource "aws_cloudwatch_log_group" "person_service" {
  name              = "/aws/ecs/person-service"
  retention_in_days = 30
}


#person-service
resource "aws_ecs_task_definition" "person" {
  family                   = "person-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name      = "person-service"
    image     = "aledve/person-service:latest"
    essential = true
    portMappings = [
      {
        containerPort = 10011
        hostPort      = 10011
        protocol      = "tcp"
      }
    ]
    log_configuration = {
      log_driver = "awslogs"
      options = {
        awslogs-group         = "/aws/ecs/person-service"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "ecs"
      }
    }
    }]
  )
}

resource "aws_ecs_service" "person_service" {
  name            = "person-service"
  cluster         = aws_ecs_cluster.crm_cluster.id
  task_definition = aws_ecs_task_definition.person.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = module.vpc_crm.public_subnet_ids
    assign_public_ip = true
    security_groups  = [module.ecs_sg.sg_person_service_id]
  }

  load_balancer {
    target_group_arn = module.person_service_alb_rule.target_group_arn
    container_name   = "person-service"
    container_port   = 10011
  }
  depends_on = [module.alb]
}




#role service
resource "aws_ecs_task_definition" "role" {
  family                   = "role-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name      = "role-service"
    image     = "aledve/role-service:latest"
    essential = true
    portMappings = [
      {
        containerPort = 10094
        hostPort      = 10094
        protocol      = "tcp"
      }
    ]
    log_configuration = {
      log_driver = "awslogs"
      options = {
        awslogs-group         = "/ecs/role-service"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "role_service" {
  name            = "role-service"
  cluster         = aws_ecs_cluster.crm_cluster.id
  task_definition = aws_ecs_task_definition.role.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = module.vpc_crm.public_subnet_ids
    assign_public_ip = true
    security_groups  = [module.ecs_sg.sg_role_service_id]
  }

  load_balancer {
    target_group_arn = module.role_service_alb_rule.target_group_arn
    container_name   = "role-service"
    container_port   = 10094
  }

  depends_on = [module.alb]
}

# user-service
resource "aws_ecs_task_definition" "user" {
  family                   = "user-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name      = "user-service"
    image     = "aledve/user-service:latest"
    essential = true
    portMappings = [
      {
        containerPort = 10021
        hostPort      = 10021
        protocol      = "tcp"
      }
    ]
    log_configuration = {
      log_driver = "awslogs"
      options = {
        awslogs-group         = "/ecs/user-service"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "user_service" {
  name            = "user-service"
  cluster         = aws_ecs_cluster.crm_cluster.id
  task_definition = aws_ecs_task_definition.user.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = module.vpc_crm.public_subnet_ids
    assign_public_ip = true
    security_groups  = [module.ecs_sg.sg_user_service_id]
  }

  load_balancer {
    target_group_arn = module.user_service_alb_rule.target_group_arn
    container_name   = "user-service"
    container_port   = 10021
  }

  depends_on = [module.alb]
}

# team-service
resource "aws_ecs_task_definition" "team" {
  family                   = "team-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name      = "team-service"
    image     = "aledve/team-service:latest"
    essential = true
    portMappings = [
      {
        containerPort = 10041
        hostPort      = 10041
        protocol      = "tcp"
      }
    ]
    log_configuration = {
      log_driver = "awslogs"
      options = {
        awslogs-group         = "/ecs/team-service"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "team_service" {
  name            = "team-service"
  cluster         = aws_ecs_cluster.crm_cluster.id
  task_definition = aws_ecs_task_definition.team.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = module.vpc_crm.public_subnet_ids
    assign_public_ip = true
    security_groups  = [module.ecs_sg.sg_team_service_id]
  }

  load_balancer {
    target_group_arn = module.team_service_alb_rule.target_group_arn
    container_name   = "team-service"
    container_port   = 10041
  }

  depends_on = [module.alb]
}

# objective-service
resource "aws_ecs_task_definition" "objective" {
  family                   = "objective-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name      = "objective-service"
    image     = "aledve/objective-service:latest"
    essential = true
    portMappings = [
      {
        containerPort = 10061
        hostPort      = 10061
        protocol      = "tcp"
      }
    ]
    log_configuration = {
      log_driver = "awslogs"
      options = {
        awslogs-group         = "/ecs/objective-service"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "objective_service" {
  name            = "objective-service"
  cluster         = aws_ecs_cluster.crm_cluster.id
  task_definition = aws_ecs_task_definition.objective.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = module.vpc_crm.public_subnet_ids
    assign_public_ip = true
    security_groups  = [module.ecs_sg.sg_objective_service_id]
  }

  load_balancer {
    target_group_arn = module.objective_service_alb_rule.target_group_arn
    container_name   = "objective-service"
    container_port   = 10061
  }

  depends_on = [module.alb]
}

# session-service
resource "aws_ecs_task_definition" "session" {
  family                   = "session-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name      = "session-service"
    image     = "aledve/session-service:latest"
    essential = true
    portMappings = [
      {
        containerPort = 10081
        hostPort      = 10081
        protocol      = "tcp"
      }
    ]
    log_configuration = {
      log_driver = "awslogs"
      options = {
        awslogs-group         = "/aws/ecs/session-service"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "session_service" {
  name            = "session-service"
  cluster         = aws_ecs_cluster.crm_cluster.id
  task_definition = aws_ecs_task_definition.session.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = module.vpc_crm.public_subnet_ids
    assign_public_ip = true
    security_groups  = [module.ecs_sg.sg_session_service_id]
  }

  load_balancer {
    target_group_arn = module.session_service_alb_rule.target_group_arn
    container_name   = "session-service"
    container_port   = 10081
  }

  depends_on = [module.alb]
}

# auth-service
resource "aws_ecs_task_definition" "authentication" {
  family                   = "authentication-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name      = "authentication-service"
    image     = "aledve/authentication-service:latest"
    essential = true
    portMappings = [
      {
        containerPort = 10061
        hostPort      = 10061
        protocol      = "tcp"
      }
    ]
    log_configuration = {
      log_driver = "awslogs"
      options = {
        awslogs-group         = "/ecs/authentication-service"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "authentication_service" {
  name            = "authentication-service"
  cluster         = aws_ecs_cluster.crm_cluster.id
  task_definition = aws_ecs_task_definition.authentication.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = module.vpc_crm.public_subnet_ids
    assign_public_ip = true
    security_groups  = [module.ecs_sg.sg_authentication_service_id]
  }

  load_balancer {
    target_group_arn = module.authentication_service_alb_rule.target_group_arn
    container_name   = "authentication-service"
    container_port   = 10061
  }

  depends_on = [module.alb]
}

# project-service
resource "aws_ecs_task_definition" "project" {
  family                   = "project-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name      = "project-service"
    image     = "aledve/project-service:latest"
    essential = true
    portMappings = [
      {
        containerPort = 10051
        hostPort      = 10051
        protocol      = "tcp"
      }
    ]
    log_configuration = {
      log_driver = "awslogs"
      options = {
        awslogs-group         = "/ecs/project-service"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "project_service" {
  name            = "project-service"
  cluster         = aws_ecs_cluster.crm_cluster.id
  task_definition = aws_ecs_task_definition.project.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = module.vpc_crm.public_subnet_ids
    assign_public_ip = true
    security_groups  = [module.ecs_sg.sg_project_service_id]
  }

  load_balancer {
    target_group_arn = module.project_service_alb_rule.target_group_arn
    container_name   = "project-service"
    container_port   = 10051
  }

  depends_on = [module.alb]
}

# task-service
resource "aws_ecs_task_definition" "task" {
  family                   = "task-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name      = "task-service"
    image     = "aledve/task-service:latest"
    essential = true
    portMappings = [
      {
        containerPort = 10071
        hostPort      = 10071
        protocol      = "tcp"
      }
    ]
    log_configuration = {
      log_driver = "awslogs"
      options = {
        awslogs-group         = "/ecs/task-service"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "task_service" {
  name            = "task-service"
  cluster         = aws_ecs_cluster.crm_cluster.id
  task_definition = aws_ecs_task_definition.task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = module.vpc_crm.public_subnet_ids
    assign_public_ip = true
    security_groups  = [module.ecs_sg.sg_task_service_id]
  }

  load_balancer {
    target_group_arn = module.task_service_alb_rule.target_group_arn
    container_name   = "task-service"
    container_port   = 10071
  }

  depends_on = [module.alb]
}

# forum-service
resource "aws_ecs_task_definition" "forum" {
  family                   = "forum-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name      = "forum-service"
    image     = "aledve/forum-service:latest"
    essential = true
    portMappings = [
      {
        containerPort = 10103
        hostPort      = 10103
        protocol      = "tcp"
      }
    ]
    log_configuration = {
      log_driver = "awslogs"
      options = {
        awslogs-group         = "/aws/ecs/forum-service"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "forum_service" {
  name            = "forum-service"
  cluster         = aws_ecs_cluster.crm_cluster.id
  task_definition = aws_ecs_task_definition.forum.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = module.vpc_crm.public_subnet_ids
    assign_public_ip = true
    security_groups  = [module.ecs_sg.sg_forum_service_id]
  }

  load_balancer {
    target_group_arn = module.forum_service_alb_rule.target_group_arn
    container_name   = "forum-service"
    container_port   = 10103
  }

  depends_on = [module.alb]
}
