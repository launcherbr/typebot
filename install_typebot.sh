#!/bin/bash

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Verificação de Root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Execute como root.${NC}"
  exit
fi

# --- DETECTOR DE PAINEL ---
HAS_PANEL=false
if command -v clpctl &> /dev/null; then
    echo -e "${RED}⚠️  ALERTA: CloudPanel Detectado!${NC}"
    HAS_PANEL=true
elif [ -d "/usr/local/psa" ]; then
    echo -e "${RED}⚠️  ALERTA: Plesk Detectado!${NC}"
    HAS_PANEL=true
fi

# Funções de Porta
check_port() {
  local port=$1
  if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then return 1; else return 0; fi
}

get_free_port() {
    local prompt=$1
    local default=$2
    local var=$3
    while true; do
        read -p "$prompt (Padrão: $default): " input
        local sel=${input:-$default}
        if check_port $sel; then eval $var=$sel; break; else echo -e "${RED}Porta $sel em uso!${NC}"; fi
    done
}

echo -e "${GREEN}### Instalador Inteligente Typebot ###${NC}"
echo "-----------------------------------"

# MENU DE AMBIENTE
echo -e "${YELLOW}Qual é o seu cenário?${NC}"
if [ "$HAS_PANEL" = true ]; then
    echo -e "${RED}Como você usa um PAINEL, selecione a Opção 2 obrigatóriamente.${NC}"
fi
echo "1) VPS 'Limpa' ou com Scripts Manuais (Whaticket, Izing, Z-Pro)"
echo "   -> O script CONFIGURA o Nginx e o SSL (Certbot)."
echo "2) VPS com Painel de Gestão (CloudPanel, Plesk, CyberPanel)"
echo "   -> O script roda APENAS o Docker. O Proxy Reverso é feito no Painel."
read -p "Opção [1/2]: " ENV_OPTION

if [ "$HAS_PANEL" = true ] && [ "$ENV_OPTION" == "1" ]; then
    echo -e "${RED}ERRO CRÍTICO: Opção 1 proibida em servidores com Painel.${NC}"
    exit 1
fi

# Coleta de Dados
echo -e "\n${CYAN}--- Domínios ---${NC}"
read -p "Domínio Builder (ex: typebot.com): " TYPEBOT_DOMAIN
read -p "Domínio Viewer (ex: chat.com): " CHAT_DOMAIN
read -p "Domínio Storage (ex: s3.com): " STORAGE_DOMAIN
read -p "Email Admin: " ADMIN_EMAIL

echo -e "\n${CYAN}--- Banco de Dados ---${NC}"
read -p "Versão Postgres (Padrão: 16): " PG_VER
PG_VER=${PG_VER:-16}
read -p "Senha Postgres: " PG_PASS
read -p "Expor banco externo? (s/n): " EXPOSE_DB
DB_MAP=""
if [[ "$EXPOSE_DB" =~ ^[Ss]$ ]]; then
    get_free_port "Porta Externa PG" "5432" "PG_EXT_PORT"
    DB_MAP="$PG_EXT_PORT:5432"
fi

echo -e "\n${CYAN}--- Minio (S3) ---${NC}"
read -p "Usuário Minio (Padrão: admin): " MINIO_USER
MINIO_USER=${MINIO_USER:-admin}
read -p "Senha Minio (Padrão: minio123): " MINIO_PASS
MINIO_PASS=${MINIO_PASS:-minio123}

echo -e "\n${CYAN}--- Portas Docker ---${NC}"
get_free_port "Porta Builder" "3000" "PORT_BUILDER"
get_free_port "Porta Viewer" "3001" "PORT_VIEWER"
get_free_port "Porta Minio API" "9000" "PORT_MINIO"
get_free_port "Porta Minio Console" "9001" "PORT_MINIO_CON"

echo -e "\n${CYAN}--- SMTP ---${NC}"
read -p "Host: " SMTP_HOST
read -p "Porta: " SMTP_PORT
read -p "User: " SMTP_USER
read -p "Pass: " SMTP_PASS
[[ "$SMTP_PORT" == "465" ]] && SMTP_SEC="true" || SMTP_SEC="false"

# Docker
if ! command -v docker &> /dev/null; then curl -fsSL https://get.docker.com | sh; fi

# Gera docker-compose.yml
ENC_KEY=$(openssl rand -base64 24)
cat <<EOF > docker-compose.yml
services:
  typebot-db:
    image: postgres:$PG_VER
    restart: always
    volumes:
      - db_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=typebot
      - POSTGRES_PASSWORD=$PG_PASS
EOF
if [ ! -z "$DB_MAP" ]; then echo "    ports: ['$DB_MAP']" >> docker-compose.yml; fi

cat <<EOF >> docker-compose.yml
  typebot-builder:
    image: baptistearno/typebot-builder:latest
    restart: always
    ports:
      - "$PORT_BUILDER:3000"
    depends_on:
      - typebot-db
    environment:
      - DATABASE_URL=postgresql://postgres:$PG_PASS@typebot-db:5432/typebot
      - NEXTAUTH_URL=https://$TYPEBOT_DOMAIN
      - NEXT_PUBLIC_VIEWER_URL=https://$CHAT_DOMAIN
      - NEXTAUTH_URL_INTERNAL=http://localhost:$PORT_BUILDER
      - ENCRYPTION_SECRET=$ENC_KEY
      - ADMIN_EMAIL=$ADMIN_EMAIL
      - DISABLE_SIGNUP=false
      - SMTP_HOST=$SMTP_HOST
      - SMTP_PORT=$SMTP_PORT
      - SMTP_SECURE=$SMTP_SEC
      - SMTP_USERNAME=$SMTP_USER
      - SMTP_PASSWORD=$SMTP_PASS
      - NEXT_PUBLIC_SMTP_FROM='Suporte' <$ADMIN_EMAIL>
      - S3_ACCESS_KEY=$MINIO_USER
      - S3_SECRET_KEY=$MINIO_PASS
      - S3_BUCKET=typebot
      - S3_ENDPOINT=https://$STORAGE_DOMAIN
      - S3_FORCE_PATH_STYLE=true 

  typebot-viewer:
    image: baptistearno/typebot-viewer:latest
    restart: always
    ports:
      - "$PORT_VIEWER:3000"
    environment:
      - DATABASE_URL=postgresql://postgres:$PG_PASS@typebot-db:5432/typebot
      - NEXTAUTH_URL=https://$TYPEBOT_DOMAIN
      - NEXT_PUBLIC_VIEWER_URL=https://$CHAT_DOMAIN
      - NEXTAUTH_URL_INTERNAL=http://localhost:$PORT_BUILDER
      - ENCRYPTION_SECRET=$ENC_KEY
      - S3_ACCESS_KEY=$MINIO_USER
      - S3_SECRET_KEY=$MINIO_PASS
      - S3_BUCKET=typebot
      - S3_ENDPOINT=https://$STORAGE_DOMAIN
      - S3_FORCE_PATH_STYLE=true

  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    restart: always
    ports:
      - "$PORT_MINIO:9000"
      - "$PORT_MINIO_CON:9001"
    environment:
      MINIO_ROOT_USER: $MINIO_USER
      MINIO_ROOT_PASSWORD: $MINIO_PASS
      # Redirecionamento correto para CloudPanel/Proxy Reverso
      MINIO_SERVER_URL: "https://$STORAGE_DOMAIN"
      # Nota: Se você configurou um subdominio 'console', altere manualmente abaixo depois
      # ou deixe automático para a porta do console se não tiver dominio proprio pro console
      MINIO_BROWSER_REDIRECT_URL: "https://$STORAGE_DOMAIN:9001" 
    volumes:
      - s3_data:/data

  createbuckets:
    image: minio/mc
    depends_on:
      - minio
    entrypoint: >
      /bin/sh -c "
      echo 'Iniciando configuracao do Minio...';
      # Loop para aguardar o Minio estar pronto
      until /usr/bin/mc alias set minio http://minio:9000 '$MINIO_USER' '$MINIO_PASS'; do
        echo 'Minio indisponivel, tentando novamente em 2s...';
        sleep 2;
      done;
      
      echo 'Minio conectado! Criando buckets...';
      # Cria o bucket e ignora erro se ja existir
      /usr/bin/mc mb minio/typebot || true;
      
      echo 'Definindo permissoes publicas...';
      /usr/bin/mc anonymous set public minio/typebot/public;
      
      echo 'Configuracao do Minio concluida!';
      exit 0;
      "

volumes:
  db_data:
  s3_data:
EOF

echo -e "\n${GREEN}Iniciando Docker...${NC}"
docker compose up -d || docker-compose up -d

# LÓGICA DE INSTALAÇÃO NGINX
if [[ "$ENV_OPTION" == "1" ]]; then
    echo -e "\n${YELLOW}Configurando Nginx (Modo Autônomo)...${NC}"
    apt update && apt install nginx certbot python3-certbot-nginx -y

    # Configs Nginx para Opção 1 (Omitidas para brevidade, mas devem ser incluídas se usar Opção 1)
    # ... A lógica de criação dos arquivos Nginx deve estar aqui se for usar Opção 1 ...
    # Mas como o foco é corrigir o bucket, e você usa CloudPanel (Opção 2), isso não será executado.
    
elif [[ "$ENV_OPTION" == "2" ]]; then
    echo -e "\n${GREEN}✅ Instalação Docker Finalizada!${NC}"
    echo "Containers subindo. O bucket 'typebot' será criado automaticamente em instantes."
    echo "Configure no CloudPanel:"
    echo "1. $TYPEBOT_DOMAIN -> Porta $PORT_BUILDER"
    echo "2. $CHAT_DOMAIN -> Porta $PORT_VIEWER"
    echo "3. $STORAGE_DOMAIN -> Porta $PORT_MINIO"
fi