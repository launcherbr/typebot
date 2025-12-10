#!/bin/bash

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Verificação de Root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Por favor, execute como root.${NC}"
  exit
fi

# Função para verificar se uma porta está em uso
check_port() {
  local port=$1
  if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
    return 1 # Em uso
  else
    return 0 # Livre
  fi
}

# Função para solicitar porta com verificação
get_free_port() {
    local prompt_text=$1
    local default_port=$2
    local port_var_name=$3
    
    while true; do
        read -p "$prompt_text (Padrão: $default_port): " input_port
        local selected_port=${input_port:-$default_port}
        
        if check_port $selected_port; then
            eval $port_var_name=$selected_port
            break
        else
            echo -e "${RED}A porta $selected_port já está em uso. Escolha outra.${NC}"
        fi
    done
}

echo -e "${GREEN}### Instalador Inteligente Typebot (Customizável) ###${NC}"
echo "-----------------------------------"

# 1. Seleção de Ambiente
echo -e "${YELLOW}Selecione o cenário do seu servidor:${NC}"
echo "1) VPS Limpa OU com SaaS (Whaticket/Izing) -> (Instala Nginx e SSL)"
echo "2) VPS com Painel (Plesk/CloudPanel) -> (Apenas Docker, sem Nginx)"
read -p "Opção [1/2]: " ENV_OPTION

# 2. Configurações de Domínio
echo -e "\n${YELLOW}--- Configurações de Domínio ---${NC}"
read -p "Domínio Typebot (Builder): " TYPEBOT_DOMAIN
read -p "Domínio Chat (Viewer): " CHAT_DOMAIN
read -p "Domínio Storage (Minio): " STORAGE_DOMAIN
read -p "Email do Administrador: " ADMIN_EMAIL

# 3. Configurações de Banco de Dados (PostgreSQL)
echo -e "\n${YELLOW}--- Configurações do PostgreSQL ---${NC}"
read -p "Qual versão do Postgres deseja usar? (Ex: 15, 16, 17) [Padrão: 16]: " POSTGRES_VERSION
POSTGRES_VERSION=${POSTGRES_VERSION:-16}

read -p "Defina a senha para o PostgreSQL: " POSTGRES_PASSWORD
read -p "Deseja expor o banco externamente? (s/n): " EXPOSE_DB

DB_PORT_MAPPING=""
if [[ "$EXPOSE_DB" == "s" || "$EXPOSE_DB" == "S" ]]; then
    get_free_port "Porta externa do PostgreSQL" "5432" "POSTGRES_EXTERNAL_PORT"
    DB_PORT_MAPPING="$POSTGRES_EXTERNAL_PORT:5432"
fi

# 4. Configurações do Minio (Storage)
echo -e "\n${YELLOW}--- Credenciais do Minio (S3) ---${NC}"
read -p "Usuário Admin do Minio (Padrão: minio): " MINIO_ROOT_USER
MINIO_ROOT_USER=${MINIO_ROOT_USER:-minio}

read -p "Senha Admin do Minio (Padrão: minio123): " MINIO_ROOT_PASSWORD
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:-minio123}

# 5. Portas Docker
echo -e "\n${YELLOW}--- Configurações de Porta (Docker) ---${NC}"
get_free_port "Porta Builder" "3000" "TYPEBOT_PORT"
get_free_port "Porta Viewer" "3001" "CHAT_PORT"
get_free_port "Porta Minio API" "9000" "MINIO_PORT"
get_free_port "Porta Minio Console" "9001" "MINIO_CONSOLE_PORT"

# 6. SMTP
echo -e "\n${YELLOW}--- Configurações SMTP ---${NC}"
read -p "Host SMTP: " SMTP_HOST
read -p "Porta SMTP: " SMTP_PORT
read -p "Usuário SMTP: " SMTP_USERNAME
read -p "Senha SMTP: " SMTP_PASSWORD

if [[ "$SMTP_PORT" == "465" ]]; then
  SMTP_SECURE="true"
else
  SMTP_SECURE="false"
fi

# Gera chaves
ENCRYPTION_SECRET=$(openssl rand -base64 24)
echo "$ENCRYPTION_SECRET" > encryption_secret.txt

# Verifica Docker
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Instalando Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
fi

# Criação do docker-compose.yml
cat <<EOF > docker-compose.yml
version: '3.3'
services:
  typebot-db:
    image: postgres:$POSTGRES_VERSION
    restart: always
    volumes:
      - db_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=typebot
      - POSTGRES_PASSWORD=$POSTGRES_PASSWORD
EOF

if [ ! -z "$DB_PORT_MAPPING" ]; then
cat <<EOF >> docker-compose.yml
    ports:
      - "$DB_PORT_MAPPING"
EOF
fi

cat <<EOF >> docker-compose.yml
  typebot-builder:
    image: baptistearno/typebot-builder:latest
    restart: always
    ports:
      - "$TYPEBOT_PORT:3000"
    depends_on:
      - typebot-db
    environment:
      - DATABASE_URL=postgresql://postgres:$POSTGRES_PASSWORD@typebot-db:5432/typebot
      - NEXTAUTH_URL=https://$TYPEBOT_DOMAIN
      - NEXT_PUBLIC_VIEWER_URL=https://$CHAT_DOMAIN
      - NEXTAUTH_URL_INTERNAL=http://localhost:$TYPEBOT_PORT
      - ENCRYPTION_SECRET=$ENCRYPTION_SECRET
      - ADMIN_EMAIL=$ADMIN_EMAIL
      - DISABLE_SIGNUP=false
      - SMTP_HOST=$SMTP_HOST
      - SMTP_PORT=$SMTP_PORT
      - SMTP_SECURE=$SMTP_SECURE
      - SMTP_USERNAME=$SMTP_USERNAME
      - SMTP_PASSWORD=$SMTP_PASSWORD
      - NEXT_PUBLIC_SMTP_FROM='Suporte Typebot' <$ADMIN_EMAIL>
      - S3_ACCESS_KEY=$MINIO_ROOT_USER
      - S3_SECRET_KEY=$MINIO_ROOT_PASSWORD
      - S3_BUCKET=typebot
      - S3_ENDPOINT=https://$STORAGE_DOMAIN
      - S3_FORCE_PATH_STYLE=true 

  typebot-viewer:
    image: baptistearno/typebot-viewer:latest
    restart: always
    ports:
      - "$CHAT_PORT:3000"
    environment:
      - DATABASE_URL=postgresql://postgres:$POSTGRES_PASSWORD@typebot-db:5432/typebot
      - NEXTAUTH_URL=https://$TYPEBOT_DOMAIN
      - NEXT_PUBLIC_VIEWER_URL=https://$CHAT_DOMAIN
      - NEXTAUTH_URL_INTERNAL=http://localhost:$TYPEBOT_PORT
      - ENCRYPTION_SECRET=$ENCRYPTION_SECRET
      - S3_ACCESS_KEY=$MINIO_ROOT_USER
      - S3_SECRET_KEY=$MINIO_ROOT_PASSWORD
      - S3_BUCKET=typebot
      - S3_ENDPOINT=https://$STORAGE_DOMAIN
      - S3_FORCE_PATH_STYLE=true

  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    restart: always
    ports:
      - "$MINIO_PORT:9000"
      - "$MINIO_CONSOLE_PORT:9001"
    environment:
      MINIO_ROOT_USER: $MINIO_ROOT_USER
      MINIO_ROOT_PASSWORD: $MINIO_ROOT_PASSWORD
    volumes:
      - s3_data:/data

  createbuckets:
    image: minio/mc
    depends_on:
      - minio
    entrypoint: >
      /bin/sh -c "
      echo 'Aguardando Minio iniciar...';
      sleep 10;
      /usr/bin/mc config host add minio http://minio:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD;
      /usr/bin/mc mb minio/typebot;
      /usr/bin/mc anonymous set public minio/typebot/public;
      exit 0;
      "

volumes:
  db_data:
  s3_data:
EOF

echo -e "\n${GREEN}Subindo Containers...${NC}"
docker compose up -d || docker-compose up -d

# Configuração Nginx (Se Opção 1)
if [[ "$ENV_OPTION" == "1" ]]; then
    echo -e "\n${YELLOW}Configurando Nginx...${NC}"
    apt update && apt install nginx certbot python3-certbot-nginx -y

    # Builder
    cat <<EOF > /etc/nginx/sites-available/typebot_builder
server {
  listen 80;
  server_name $TYPEBOT_DOMAIN;
  location / {
    proxy_pass http://127.0.0.1:$TYPEBOT_PORT;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_cache_bypass \$http_upgrade;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
}
EOF

    # Viewer
    cat <<EOF > /etc/nginx/sites-available/typebot_viewer
server {
  listen 80;
  server_name $CHAT_DOMAIN;
  location / {
    proxy_pass http://127.0.0.1:$CHAT_PORT;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_cache_bypass \$http_upgrade;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
}
EOF

    # Storage
    cat <<EOF > /etc/nginx/sites-available/typebot_storage
server {
  listen 80;
  server_name $STORAGE_DOMAIN;
  client_max_body_size 100M; 
  location / {
    proxy_pass http://127.0.0.1:$MINIO_PORT;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_cache_bypass \$http_upgrade;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
}
EOF

    ln -sf /etc/nginx/sites-available/typebot_builder /etc/nginx/sites-enabled/
    ln -sf /etc/nginx/sites-available/typebot_viewer /etc/nginx/sites-enabled/
    ln -sf /etc/nginx/sites-available/typebot_storage /etc/nginx/sites-enabled/
    
    nginx -t && systemctl restart nginx
    
    echo -e "\n${YELLOW}Gerando SSL...${NC}"
    certbot --nginx -d $TYPEBOT_DOMAIN -d $CHAT_DOMAIN -d $STORAGE_DOMAIN --non-interactive --agree-tos -m $ADMIN_EMAIL
    
    echo -e "${GREEN}Instalação Completa!${NC}"

elif [[ "$ENV_OPTION" == "2" ]]; then
    echo -e "\n${GREEN}Instalação Docker Completa!${NC}"
    echo "Configure seu Painel (CloudPanel/Plesk) para:"
    echo "$TYPEBOT_DOMAIN -> Porta $TYPEBOT_PORT"
    echo "$CHAT_DOMAIN -> Porta $CHAT_PORT"
    echo "$STORAGE_DOMAIN -> Porta $MINIO_PORT"
fi
