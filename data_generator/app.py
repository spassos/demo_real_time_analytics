import os
import random
import logging
from datetime import datetime, timezone

from flask import Flask, request, jsonify
from faker import Faker

from google.cloud.sql.connector import Connector, IPTypes
from google.cloud import secretmanager # Importar cliente Secret Manager
import sqlalchemy
import pg8000

# Configuração de Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
faker = Faker()

# Variáveis de Ambiente para Configuração do Banco
DB_USER = os.environ.get("DB_USER")
DB_NAME = os.environ.get("DB_NAME") # Corrigido nome do banco padrão
INSTANCE_CONNECTION_NAME = os.environ.get("INSTANCE_CONNECTION_NAME")
# Nova variável para o ID do segredo da senha
DB_PASSWORD_SECRET_ID = os.environ.get("DB_PASSWORD_SECRET_ID")

# Número de registros a gerar por chamada (pode ser passado via query param)
DEFAULT_RECORDS = 10

# Cliente Secret Manager
def access_secret_version(secret_version_id):
    """Acessa a payload de uma versão de segredo no Secret Manager."""
    if not secret_version_id:
        logger.error("ID da versão do segredo (DB_PASSWORD_SECRET_ID) não fornecido.")
        return None
    try:
        client = secretmanager.SecretManagerServiceClient()
        response = client.access_secret_version(name=secret_version_id)
        payload = response.payload.data.decode("UTF-8")
        return payload
    except Exception as e:
        logger.error(f"Erro ao acessar o segredo {secret_version_id}: {e}", exc_info=True)
        return None

# Inicializar o conector Cloud SQL
def init_connection_pool() -> sqlalchemy.engine.base.Engine:
    """Inicializa um pool de conexões SQLAlchemy seguro."""
    if not INSTANCE_CONNECTION_NAME:
        raise ValueError("Variável de ambiente INSTANCE_CONNECTION_NAME não definida.")

    # Buscar a senha do Secret Manager
    db_password = access_secret_version(DB_PASSWORD_SECRET_ID)
    if not db_password:
        raise ValueError("Não foi possível obter a senha do banco do Secret Manager.")

    # REMOVIDO: ip_type = IPTypes.PRIVATE # Deixar o conector decidir
    connector = Connector() # Remover ip_type permite auto-detecção ou conexão pública segura

    def getconn() -> pg8000.dbapi.Connection:
        conn = connector.connect(
            INSTANCE_CONNECTION_NAME,
            "pg8000",
            user=DB_USER,
            password=db_password, # Usar senha obtida do Secret Manager
            db=DB_NAME,
        )
        return conn

    pool = sqlalchemy.create_engine(
        "postgresql+pg8000://",
        creator=getconn,
        pool_size=5,
        max_overflow=2,
        pool_timeout=30,  # 30 seconds
        pool_recycle=1800,  # 30 minutes
    )
    return pool

# Inicializa o pool globalmente para reutilização
db_pool = init_connection_pool()

# Definição da tabela (usando SQLAlchemy Core para simplicidade)
metadata = sqlalchemy.MetaData()
maintenance_events_table = sqlalchemy.Table(
    "maintenance_events",
    metadata,
    sqlalchemy.Column("event_id", sqlalchemy.Integer, primary_key=True, autoincrement=True),
    sqlalchemy.Column("aircraft_registration", sqlalchemy.String(20), nullable=False),
    sqlalchemy.Column("event_type", sqlalchemy.String(50), nullable=False),
    sqlalchemy.Column("description", sqlalchemy.Text, nullable=True),
    sqlalchemy.Column("event_timestamp", sqlalchemy.TIMESTAMP(timezone=True), nullable=False),
    sqlalchemy.Column("location", sqlalchemy.String(100), nullable=True),
    # Coluna para simular atualizações (opcional, bom para testar CDC)
    sqlalchemy.Column("last_updated", sqlalchemy.TIMESTAMP(timezone=True), default=datetime.now(timezone.utc), onupdate=datetime.now(timezone.utc))
)

@app.before_request
def create_table_if_not_exists():
    """Cria a tabela antes da primeira requisição se ela não existir."""
    # Este é um ponto simples para garantir a criação. Em produção, use migrações.
    try:
        with db_pool.connect() as conn:
            if not sqlalchemy.inspect(conn).has_table(maintenance_events_table.name):
                logger.info(f"Tabela '{maintenance_events_table.name}' não encontrada. Criando...")
                metadata.create_all(bind=conn)
                logger.info(f"Tabela '{maintenance_events_table.name}' criada com sucesso.")
            else:
                logger.debug(f"Tabela '{maintenance_events_table.name}' já existe.")
    except Exception as e:
        logger.error(f"Erro ao verificar/criar tabela: {e}", exc_info=True)
        # Pode ser um problema temporário de conexão na inicialização,
        # a aplicação pode tentar novamente na próxima requisição.

# --- Endpoints Flask --- #

# Função para gerar dados sintéticos
def generate_fake_event():
    event_types = ["Inspeção A", "Inspeção B", "Reparo Estrutural", "Troca de Componente", "Manutenção Preventiva", "Verificação de Sistema"]
    # Definir pesos para tornar alguns eventos mais comuns que outros
    # Pesos:         [InspA, InspB, RepEst, TrocaComp, ManutPrev, VerifSis]
    event_type_weights = [   30,    25,        5,          10,          20,           10] # Total 100

    locations = ["Hangar Principal", "Pista 09L", "Portão A3", "Centro de Manutenção", "Oficina de Motores"]

    selected_event_type = random.choices(event_types, weights=event_type_weights, k=1)[0]

    return {
        "aircraft_registration": f"PR-{faker.lexify(text='???').upper()}{random.randint(100,999)}",
        "event_type": selected_event_type, # Usar o tipo de evento selecionado com pesos
        "description": faker.sentence(nb_words=10),
        "event_timestamp": faker.date_time_between(start_date="-1y", end_date="now", tzinfo=timezone.utc),
        "location": random.choice(locations),
    }

@app.route("/generate", methods=["POST", "GET"]) # Aceita GET para testes fáceis
def generate_data():
    """Endpoint para gerar e inserir dados sintéticos. Acionado pelo Cloud Scheduler."""
    # Ignora 'n' query param, sempre gera número aleatório de registros
    # num_records = request.args.get("n", default=DEFAULT_RECORDS, type=int)
    # if num_records <= 0:
    #     return jsonify({"error": "Parameter 'n' must be a positive integer."}), 400

    num_records = random.randint(100, 1000) # Gera um número aleatório entre 10 e 1000

    logger.info(f"Recebida solicitação via Scheduler. Gerando {num_records} registros aleatórios.")
    generated_data = [generate_fake_event() for _ in range(num_records)]

    try:
        # Usar um transaction block para inserir todos os registros
        with db_pool.connect() as conn:
            with conn.begin(): # Inicia a transação
                insert_stmt = maintenance_events_table.insert()
                conn.execute(insert_stmt, generated_data)
            logger.info(f"{num_records} registros inseridos com sucesso.")
        return jsonify({"message": f"{num_records} registros gerados e inseridos com sucesso."}), 200
    except sqlalchemy.exc.SQLAlchemyError as e:
        logger.error(f"Erro de banco de dados ao inserir registros: {e}", exc_info=True)
        return jsonify({"error": "Falha ao inserir dados no banco.", "details": str(e)}), 500
    except Exception as e:
        logger.error(f"Erro inesperado: {e}", exc_info=True)
        return jsonify({"error": "Ocorreu um erro inesperado.", "details": str(e)}), 500

# Endpoint de Health Check
@app.route("/_health")
def health_check():
    # Simplesmente retorna OK se a aplicação estiver rodando
    return "OK", 200

if __name__ == "__main__":
    # O Flask Development Server não é recomendado para produção.
    # Use um servidor WSGI como Gunicorn quando implantado.
    # O Cloud Run usa Gunicorn por padrão.
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)), debug=False) # Debug=False para produção 