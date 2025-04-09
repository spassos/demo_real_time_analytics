output "postgres_instance_private_ip" {
  description = "O endereço IP privado da instância Cloud SQL PostgreSQL."
  value       = google_sql_database_instance.postgres_instance.private_ip_address
}

output "postgres_instance_connection_name" {
  description = "O nome da conexão da instância Cloud SQL (útil para Cloud Run com Cloud SQL Proxy)."
  value       = google_sql_database_instance.postgres_instance.connection_name
}

# Adicione outros outputs conforme necessário 

output "vpc_network_id" {
  description = "O ID da rede VPC criada."
  value       = google_compute_network.vpc_network.id
}

output "datastream_stream_name" {
  description = "O nome completo do stream do Datastream criado."
  value       = google_datastream_stream.pg_to_bq_stream.name
} 