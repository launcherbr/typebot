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
            echo -e "${RED}A porta $selected_port já está em uso. Por favor, escolha outra.${NC}"
        fi
    done
}

echo -e "${GREEN}### Instalador Otimizado Typebot ###${NC}"
echo "-----------------------------------"

# 1. Seleção do Tipo de Ambiente
echo -e "${YELLOW}Qual o seu ambiente de instalação?${NC}"
echo "1) VPS Autônoma (Instalar Nginx e Certbot automaticamente)"
echo "2) VPS com Painel (Plesk/CloudPanel/CyberPanel - Apenas Docker)"
read -p "Opção [1/2]: " ENV_OPTION

# 2. Coleta de Informações Básicas
echo -e "\n${YELLOW}--- Configurações de Domínio ---${NC}"
read -p "Domínio para o Typebot (Builder) (ex: typebot.com): " TYPEBOT_DOMAIN
read -p "Domínio para o Chat (Viewer) (ex: chat.typebot.com): " CHAT_DOMAIN
read -p "Domínio para o Storage (Minio) (ex: s3.typebot.com): " STORAGE_DOMAIN
read -p "Email do administrador: " ADMIN_EMAIL

echo -e "\n${YELLOW}--- Configurações de Porta (Docker) ---${NC}"
get_free_port "Porta interna para o Builder" "3000" "TYPEBOT_PORT"
get_free_port "Porta interna para o Viewer" "3001" "CHAT_PORT"
get_free_port "Porta interna para o Minio API" "9000" "MINIO_PORT"
# Minio Console precisa de uma porta separada agora para evitar conflitos
get_free_port "Porta interna para o Minio Console" "9001" "MINIO_CONSOLE_PORT"

echo -e "\n${YELLOW}--- Configurações do Banco de Dados ---${NC}"
read -p "Senha para o PostgreSQL: " POSTGRES_PASSWORD
read -p "Deseja expor a porta do Banco de Dados para acesso externo? (s/n): " EXPOSE_DB

if [[ "$EXPOSE_DB" == "s" || "$EXPOSE_DB" == "S" ]]; then
    get_free_port "Porta externa do PostgreSQL" "5432" "POSTGRES_EXTERNAL_PORT"
    DB_PORT_MAPPING="$POSTGRES_EXTERNAL_PORT:5432"
    echo -e "${GREEN}Banco de dados será acessível na porta $POSTGRES_EXTERNAL_PORT${NC}"
else
    DB_PORT_MAPPING="" # Não mapeia porta, mantém apenas interna no Docker
    echo -e "${GREEN}Banco de dados mantido apenas internamente no Docker.${NC}"
fi

echo -e "\n${YELLOW}--- Configurações SMTP (Email) ---${NC}"
read -p "Host SMTP (ex: smtp.gmail.com): " SMTP_HOST
read -p "Porta SMTP (ex: 465 ou 587): " SMTP_PORT
read -p "Usuário SMTP: " SMTP_USERNAME
read -p "Senha SMTP: " SMTP_PASSWORD

# Define SMTP_SECURE
if [[ "$SMTP_PORT" == "465" ]]; then
  SMTP_SECURE="true"
elif [[ "$SMTP_PORT" == "587" ]]; then
  SMTP_SECURE="false"
else
  SMTP_SECURE="false" # Default fallback
fi

# Gera chaves
ENCRYPTION_SECRET=$(openssl rand -base64 24)
echo "$ENCRYPTION_SECRET" > encryption_secret.txt

# 3. Verifica Instalação do Docker
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker não encontrado. Instalando...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
fi

# 4. Criação do docker-compose.yml
echo -e "\n${GREEN}Gerando docker-compose.yml...${NC}"

cat <<EOF > docker-compose.yml
version: '3.3'
services:
  typebot-db:
    image: postgres:13
    restart: always
    volumes:
      - db_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=typebot
      - POSTGRES_PASSWORD=$POSTGRES_PASSWORD
EOF

# Adiciona porta somente se solicitado
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
      - S3_ACCESS_KEY=minio
      - S3_SECRET_KEY=minio123
      - S3_BUCKET=typebot
      - S3_ENDPOINT=https://$STORAGE_DOMAIN
      # Ajuste para garantir que o container consiga resolver o endpoint internamente se necessário
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
      - S3_ACCESS_KEY=minio
      - S3_SECRET_KEY=minio123
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
      MINIO_ROOT_USER: minio
      MINIO_ROOT_PASSWORD: minio123
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
      /usr/bin/mc config host add minio http://minio:9000 minio minio123;
      /usr/bin/mc mb minio/typebot;
      /usr/bin/mc anonymous set public minio/typebot/public;
      exit 0;
      "

volumes:
  db_data:
  s3_data:
EOF

# Subir containers
echo -e "\n${GREEN}Iniciando Containers Docker...${NC}"
docker compose up -d || docker-compose up -d

# 5. Lógica condicional: Painel vs Autônomo
if [[ "$ENV_OPTION" == "1" ]]; then
    echo -e "\n${GREEN}Configurando Nginx e SSL (Modo Autônomo)...${NC}"
    
    # Instala dependências Nginx/Certbot
    apt update && apt install nginx certbot python3-certbot-nginx -y

    # Configuração Nginx Typebot (Builder)
    cat <<EOF > /etc/nginx/sites-available/typebot
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
  }
}
EOF

    # Configuração Nginx Chat (Viewer)
    cat <<EOF > /etc/nginx/sites-available/chat
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
  }
}
EOF

    # Configuração Nginx Minio (Storage)
    cat <<EOF > /etc/nginx/sites-available/storage
server {
  listen 80;
  server_name $STORAGE_DOMAIN;
  # Habilita uploads maiores para o Minio
  client_max_body_size 100M; 
  location / {
    proxy_pass http://127.0.0.1:$MINIO_PORT;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_cache_bypass \$http_upgrade;
  }
}
EOF

    # Links simbólicos e Reload
    ln -sf /etc/nginx/sites-available/typebot /etc/nginx/sites-enabled/
    ln -sf /etc/nginx/sites-available/chat /etc/nginx/sites-enabled/
    ln -sf /etc/nginx/sites-available/storage /etc/nginx/sites-enabled/
    
    nginx -t && systemctl restart nginx
    
    echo -e "\n${YELLOW}Gerando certificados SSL...${NC}"
    certbot --nginx -d $TYPEBOT_DOMAIN -d $CHAT_DOMAIN -d $STORAGE_DOMAIN --non-interactive --agree-tos -m $ADMIN_EMAIL
    
    echo -e "${GREEN}Instalação Autônoma Concluída!${NC}"

elif [[ "$ENV_OPTION" == "2" ]]; then
    echo -e "\n${GREEN}Containers iniciados!${NC}"
    echo -e "${YELLOW}Atenção: Como você usa um Painel (Plesk/CloudPanel), configure os Proxies Reversos manualmente:${NC}"
    echo "1. Domínio $TYPEBOT_DOMAIN -> http://127.0.0.1:$TYPEBOT_PORT"
    echo "2. Domínio $CHAT_DOMAIN -> http://127.0.0.1:$CHAT_PORT"
    echo "3. Domínio $STORAGE_DOMAIN -> http://127.0.0.1:$MINIO_PORT"
    if [ ! -z "$DB_PORT_MAPPING" ]; then
        echo "4. Banco de Dados externo disponível em: IP_DO_SERVIDOR:$POSTGRES_EXTERNAL_PORT"
    fi
    echo -e "\nNão se esqueça de habilitar o Websocket Support no seu painel."
fi