############################################
# Interface Endpoints
############################################

output "interface_endpoint_ids" {

  description = "Map of interface endpoint IDs."

  value = {
    for name, endpoint in aws_vpc_endpoint.interface :
    name => endpoint.id
  }

}

############################################
# S3 Gateway Endpoint
############################################

output "s3_gateway_endpoint_id" {

  description = "S3 Gateway Endpoint ID."

  value = aws_vpc_endpoint.s3.id

}