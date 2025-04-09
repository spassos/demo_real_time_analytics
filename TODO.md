# Terraform Refactoring & Improvement TODO List

Aqui está uma lista de tarefas e sugestões para refatorar e melhorar seu código Terraform atual. Estas são sugestões para serem consideradas e implementadas posteriormente, focando na separação de responsabilidades, melhores práticas e manutenibilidade.

**1. Separação de Módulos/Arquivos:**

*   **[ ] Módulo de Rede (Network):**
    *   Mover recursos `google_compute_network`, `google_compute_subnetwork`, `google_compute_router`, `google_compute_address` (para NAT), `google_compute_router_nat` para um módulo ou arquivo dedicado (e.g., `network.tf` ou `modules/network/`).
    *   Mover recursos `google_compute_firewall` (`allow_datastream_to_sql`, `allow_ssh_to_vm`) para este módulo/arquivo de rede.
    *   Definir outputs claros para este módulo (e.g., `network_id`, `subnetwork_id`, `nat_static_ips`).

*   **[ ] Módulo Cloud SQL (PostgreSQL):**
    *   Mover recursos `google_sql_database_instance`, `google_sql_database`, `google_sql_user`, `time_sleep.wait_postgres_ready` para um módulo ou arquivo dedicado (e.g., `cloudsql.tf` ou `modules/cloudsql/`).
    *   Considerar se as `database_flags` poderiam ser mais parametrizadas via variáveis.
    *   Definir outputs claros (e.g., `instance_connection_name`, `instance_public_ip`, `db_name`, `db_user_name`).

*   **[ ] Módulo VM Proxy:**
    *   Mover o recurso `google_compute_instance.proxy_vm` para um módulo ou arquivo dedicado (e.g., `proxy_vm.tf` ou `modules/proxy_vm/`).
    *   Externalizar o `metadata_startup_script` para um arquivo separado (e.g., `scripts/configure_haproxy.sh`) e referenciá-lo usando `templatefile()` ou similar. Isso melhora a legibilidade e permite testes independentes do script.
    *   Definir outputs (e.g., `proxy_vm_internal_ip`, `proxy_vm_id`).

*   **[ ] Módulo Datastream:**
    *   O arquivo `datastream.tf` já está razoavelmente bem separado.
    *   Considerar se os `time_sleep` (`wait_network_stable_for_datastream`, `wait_after_profiles`) são estritamente necessários ou se as dependências implícitas/explícitas são suficientes. Podem ser removidos ou tornados configuráveis se causarem lentidão desnecessária.
    *   Mover `google_datastream_private_connection` para o módulo de rede ou mantê-lo aqui, dependendo da preferência de organização (parece mais lógico aqui com os outros recursos Datastream).

*   **[ ] Módulo BigQuery:**
    *   O arquivo `bigquery.tf` já é simples e dedicado. Pode ser mantido como está ou transformado em um módulo básico se mais configurações forem adicionadas futuramente.

*   **[ ] Módulo/Arquivo de Setup SQL (Replicação):**
    *   Mover o `null_resource.setup_postgres_replication` para um arquivo dedicado (e.g., `sql_setup.tf`).
    *   **[Importante]** Avaliar alternativas ao `local-exec` para executar os comandos SQL. `local-exec` cria uma dependência da máquina local (presença do `psql`, conectividade de rede, autenticação). Alternativas:
        *   Usar `gcloud sql connect INSTANCE_NAME --user=... --quiet < commands.sql` dentro do `local-exec` (ainda depende do local, mas usa `gcloud`).
        *   Criar um Cloud Run Job ou Cloud Build step que é disparado *após* a criação do SQL para executar a configuração (abordagem mais robusta e desacoplada).
        *   Usar um provedor Terraform específico para PostgreSQL (como `cyrilgdn/postgresql`), embora possa exigir conexão direta.

**2. Melhorias Gerais e Refatoração:**

*   **[ ] Gerenciamento de Segredos:**
    *   Remover a senha do banco (`db_password`) do arquivo `terraform.tfvars`. Utilizar variáveis de ambiente (`TF_VAR_db_password=... terraform apply`), um arquivo `.auto.tfvars` não versionado, ou integrar com o Google Secret Manager (`google_secret_manager_secret_version` data source).

*   **[ ] Validação de Variáveis:**
    *   Adicionar blocos `validation` em `variables.tf` para garantir que CIDRs sejam válidos, nomes sigam padrões, tiers sejam permitidos, etc.

*   **[ ] Nomes e Convenções:**
    *   Revisar nomes de recursos e variáveis para consistência e clareza.

*   **[ ] Habilitação de APIs (`main.tf`):**
    *   Considerar se os recursos `google_project_service` são necessários em cada `apply`. A habilitação de APIs é frequentemente uma tarefa única de setup do projeto. Mantê-los pode causar lentidão ou falhas de permissão (`serviceusage.services.enable`). Avaliar movê-los para um processo/workspace de setup inicial ou gerenciá-los via Console/gcloud/Org Policy.
    *   Revisar os `time_sleep` associados às APIs.

*   **[ ] Permissões IAM (`main.tf`):**
    *   O `google_project_iam_member.datastream_cloudsql_client` está OK em `main.tf` por ser a nível de projeto, mas poderia logicamente residir mais perto dos recursos que o necessitam (Datastream/SQL) se movido para módulos.

*   **[ ] Configuração HAProxy (Script da VM):**
    *   O script em `metadata_startup_script` está fazendo bastante coisa (SELinux, config HAProxy, logs, testes). Como mencionado, externalizar para um arquivo melhora a gestão.
    *   Adicionar tratamento de erro mais robusto dentro do script.

*   **[ ] Revisão de `authorized_networks` no Cloud SQL:**
    *   Confirmar se a inclusão do `var.cloud_nat_cidr` é realmente necessária além do IP estático específico do NAT (`google_compute_address.nat_ip`). Se o NAT *sempre* usa o IP estático, o CIDR mais amplo pode ser redundante e menos seguro.

*   **[ ] Outputs (`outputs.tf`):**
    *   Adicionar outputs úteis que possam ser necessários para outras partes da infraestrutura ou para verificação manual (e.g., IP estático do NAT, IP interno/externo da VM Proxy, `instance_connection_name` para o Cloud Run).

**Prioridade Sugerida (Refatoração):**

1.  Resolver o gerenciamento de segredos (`db_password`).
2.  Separar os recursos em arquivos/módulos lógicos (Rede, SQL, Proxy, Datastream).
3.  Avaliar e refatorar a execução dos comandos SQL (`null_resource`/`local-exec`).
4.  Externalizar o script de startup da VM.
5.  Implementar as demais melhorias (validações, outputs, revisão de sleeps/APIs). 