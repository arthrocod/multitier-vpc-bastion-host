######################################################################################
# Sample module to deploy a 'data governance' webserver VSI and security group  
# No NACL is defined. As no floating (public) IPs are defined, the Security Group 
# configuration by itself is considered sufficient to protect access to the VSIs. 
# Subnet is created in VPC module.
#
# Redhat Ansible usage is enabled by the addition of VSI tags. All Ansible related VSI 
# tags are prefixed with "ans_group:" followed by the group name.   '
# tags = ["ans_group:datagov"]'  
# Correct specification of tags is essential for operation of the Ansible dynamic inventory
# script used to pass host information to Ansible. The tags here should match the roles
# defined in the site.yml playbook file. 
#######################################################################################


resource "ibm_is_instance" "datagov-server" {
  count   = var.datagov_count
  name    = "${var.unique_id}-datagov-vsi-${count.index + 1}"
  image   = var.ibm_is_image_id
  profile = var.profile

  primary_network_interface {
    subnet          = var.subnet_ids[count.index]
    security_groups = [ibm_is_security_group.datagov.id]
  }

  vpc            = var.ibm_is_vpc_id
  zone           = "${var.ibm_region}-${count.index % 3 + 1}"
  resource_group = var.ibm_is_resource_group_id
  keys           = [var.ibm_is_ssh_key_id]
  user_data      = data.template_cloudinit_config.app_userdata.rendered
  tags           = ["schematics:group:datagov"]
}


##############################################################################
# Private load balancer
# 
##############################################################################


# resource "ibm_is_lb" "webapptier-lb" {
#   name    = "backapptier"
#   type    = "private"
#   subnets = toset(var.subnet_ids)
# resource_group = var.ibm_is_resource_group_id
# }


# resource "ibm_is_lb_listener" "webapptier-lb-listener" {
#   lb           = ibm_is_lb.webapptier-lb.id
#   port         = "80"
#   protocol     = "http"
#   default_pool = element(split("/", ibm_is_lb_pool.webapptier-lb-pool.id), 1)
#   depends_on   = [ibm_is_lb_pool.webapptier-lb-pool]
# }

# resource "ibm_is_lb_pool" "webapptier-lb-pool" {
#   lb                 = ibm_is_lb.webapptier-lb.id
#   name               = "webapptier-lb-pool"
#   protocol           = "http"
#   algorithm          = "round_robin"
#   health_delay       = "5"
#   health_retries     = "2"
#   health_timeout     = "2"
#   health_type        = "http"
#   health_monitor_url = "/"
#   depends_on         = [ibm_is_lb.webapptier-lb]
# }

# resource "ibm_is_lb_pool_member" "webapptier-lb-pool-member-zone1" {
#   count          = var.datagov_count
#   lb             = ibm_is_lb.webapptier-lb.id
#   pool           = element(split("/", ibm_is_lb_pool.webapptier-lb-pool.id), 1)
#   port           = "8080"
#   target_address = ibm_is_instance.datagov-server[count.index].primary_network_interface[0].primary_ipv4_address
#   depends_on     = [ibm_is_lb_pool.webapptier-lb-pool]
# }





# this is the SG applied to the data governance instances
resource "ibm_is_security_group" "datagov" {
  name           = "${var.unique_id}-datagov-sg"
  vpc            = var.ibm_is_vpc_id
  resource_group = var.ibm_is_resource_group_id
}


locals {
  sg_keys = ["direction", "remote", "type", "port_min", "port_max"]


  sg_rules = [
    ["inbound", var.bastion_remote_sg_id, "tcp", 22, 22],
    ["inbound", var.app_backend_sg_id, "tcp", 9300, 9300],
    ["inbound", var.app_frontend_sg_id, "tcp", 9300, 9300],
    ["outbound", var.app_backend_sg_id, "tcp", 27017, 27017],
    ["outbound", "161.26.0.0/24", "tcp", 443, 443],
    ["outbound", "161.26.0.0/24", "tcp", 80, 80],
    ["outbound", "161.26.0.0/24", "udp", 53, 53],
    ["outbound", var.pub_repo_egress_cidr, "tcp", 443, 443],
    ["inbound", "0.0.0.0/0", "tcp", 80, 80]
  ]

  sg_mappedrules = [
    for entry in local.sg_rules :
    merge(zipmap(local.sg_keys, entry))
  ]
}


resource "ibm_is_security_group_rule" "datagov_access" {
  count     = length(local.sg_mappedrules)
  group     = ibm_is_security_group.datagov.id
  direction = (local.sg_mappedrules[count.index]).direction
  remote    = (local.sg_mappedrules[count.index]).remote
  dynamic "tcp" {
    for_each = local.sg_mappedrules[count.index].type == "tcp" ? [
      {
        port_max = local.sg_mappedrules[count.index].port_max
        port_min = local.sg_mappedrules[count.index].port_min
      }
    ] : []
    content {
      port_max = tcp.value.port_max
      port_min = tcp.value.port_min

    }
  }
  dynamic "udp" {
    for_each = local.sg_mappedrules[count.index].type == "udp" ? [
      {
        port_max = local.sg_mappedrules[count.index].port_max
        port_min = local.sg_mappedrules[count.index].port_min
      }
    ] : []
    content {
      port_max = udp.value.port_max
      port_min = udp.value.port_min
    }
  }
  dynamic "icmp" {
    for_each = local.sg_mappedrules[count.index].type == "icmp" ? [
      {
        type = local.sg_mappedrules[count.index].port_max
        code = local.sg_mappedrules[count.index].port_min
      }
    ] : []
    content {
      type = icmp.value.type
      code = icmp.value.code
    }
  }
}




