# Use uma imagem base oficial do Python
FROM python:3.10-slim

# Define o diretório de trabalho
WORKDIR /app

# Copia o arquivo de dependências
COPY requirements.txt requirements.txt

# Instala as dependências
# --no-cache-dir: não armazena o cache do pip
# --upgrade pip: garante que o pip está atualizado
# -r requirements.txt: instala a partir do arquivo
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copia o código da aplicação
COPY . .

# Define a variável de ambiente PORT (padrão para Cloud Run)
ENV PORT 8080

# Define o comando para rodar a aplicação usando Gunicorn
# workers = 4: um ponto de partida razoável, ajuste conforme necessário
# threads = 8: número de threads por worker
# timeout = 0: desabilita o timeout do worker (útil para Cloud Run)
# bind=0.0.0.0:$PORT: escuta em todas as interfaces na porta definida
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 app:app 