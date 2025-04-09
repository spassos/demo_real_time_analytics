psql -h 10.0.0.2 -U postgres -d datastream_source -p 5432

psql -h 10.0.0.2 -U datastream_user -d datastream_source -p 5432

gcloud projects get-iam-policy platinum-pager-456120-a4 \
  --filter="bindings.members:service-365419052762@gcp-sa-datastream.iam.gserviceaccount.com"
gcloud projects add-iam-policy-binding platinum-pager-456120-a4 \
  --member="serviceAccount:service-365419052762@gcp-sa-datastream.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"


gcloud projects describe platinum-pager-456120-a4 --format="value(projectNumber)"


gcloud compute ssh sql-proxy-vm --zone=us-central1-a --project=platinum-pager-456120-a4

psql -h 34.59.168.111 -U datastream_user -d datastream_source -c "SELECT 1"

SELECT pg_drop_replication_slot('ds_replication_slot_for_pg_to_bq_stream');

# --- PASSO 1: Verifique se estas variáveis estão corretas ---
export PROJECT_ID="platinum-pager-456120-a4"
export REGION="us-central1"
export SERVICE_NAME="data-generator-service"
export DB_USER_VALUE="datastream_user"
export DB_NAME_VALUE="datastream_source"
export INSTANCE_CONNECTION_NAME_VALUE="platinum-pager-456120-a4:us-central1:postgres-instance"
export DB_PASSWORD_SECRET_ID_VALUE="projects/365419052762/secrets/db-password-secret/versions/latest"
export PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format='value(projectNumber)')
export COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# --- PASSO 2: Execute o comando de deploy (de dentro do diretório data_generator) ---
gcloud run deploy ${SERVICE_NAME} \
  --source . \
  --platform=managed \
  --region=${REGION} \
  --allow-unauthenticated \
  --service-account=${COMPUTE_SA} \
  --set-env-vars="DB_USER=${DB_USER_VALUE}" \
  --set-env-vars="DB_NAME=${DB_NAME_VALUE}" \
  --set-env-vars="INSTANCE_CONNECTION_NAME=${INSTANCE_CONNECTION_NAME_VALUE}" \
  --set-env-vars="DB_PASSWORD_SECRET_ID=${DB_PASSWORD_SECRET_ID_VALUE}" \
  --add-cloudsql-instances=${INSTANCE_CONNECTION_NAME_VALUE} \
  --project=${PROJECT_ID}


curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" "https://data-generator-service-365419052762.us-central1.run.app/generate?n=100"