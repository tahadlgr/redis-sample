resource "aws_appmesh_virtual_node" "default" {
  name      = "redis"
  mesh_name = var.mesh_id

  spec {
    logging {
      access_log {
        file {
          path = "/dev/stdout"
        }
      }
    }

    listener {
      port_mapping {
        port     = local.port
        protocol = "tcp"
      }
    }

    service_discovery {
      dns {
        hostname = aws_elasticache_replication_group.redis.primary_endpoint_address
      }
    }
  }
}

resource "aws_appmesh_virtual_router" "default" {
  name      = "redis"
  mesh_name = var.mesh_id

  spec {
    listener {
      port_mapping {
        port     = local.port
        protocol = "tcp"
      }
    }
  }
}

resource "aws_appmesh_route" "default" {
  name                = "redis-route"
  mesh_name           = var.mesh_id
  virtual_router_name = aws_appmesh_virtual_router.default.name

  spec {
    tcp_route {
      action {
        weighted_target {
          virtual_node = aws_appmesh_virtual_node.default.name
          weight       = 100
        }
      }
    }
  }
}

resource "aws_appmesh_virtual_service" "default" {
  name      = "redis.${var.mesh_zone}"
  mesh_name = var.mesh_id

  spec {
    provider {
      virtual_router {
        virtual_router_name = aws_appmesh_virtual_router.default.name
      }
    }
  }
}

resource "aws_route53_record" "mesh" {
  zone_id = var.mesh_zone_id
  name    = "redis.${var.mesh_zone}"
  type    = "A"
  ttl     = "300"
  records = ["10.10.10.10"]
}
