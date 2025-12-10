# 🚀 Instalador Otimizado Typebot (Multi-Ambiente)

Este script automatiza a instalação do **Typebot** utilizando Docker e Docker Compose. Ele foi projetado para ser **flexível**, permitindo a instalação tanto em servidores "limpos" quanto em servidores que já possuem outras aplicações rodando (como Whaticket, Izing, Z-Pro) ou gerenciadores de painel (CloudPanel, Plesk, CyberPanel).

> **⚠️ AVISO:** Se você for instalar no mesmo servidor de um SaaS (Whaticket/Izing/Z-Pro), tenha cuidado com as portas. Este script possui um **verificador de portas**, mas recomenda-se backup do servidor antes de executar.

---

## 📋 Requisitos

* **Sistema Operacional:** Ubuntu 20.04, 22.04 ou 24.04.
* **Domínios:** 3 Subdomínios apontados para o IP do VPS (ex: `bot.seu.com`, `chat.seu.com`, `s3.seu.com`).
* **SMTP:** Credenciais de email para envio de magic links/notificações.
* **Acesso Root:** Acesso SSH ao servidor.

---

## ⚙️ Funcionalidades do Script

1.  **Detecção de Ambiente:**
    * **Modo Autônomo:** Instala Nginx, Certbot (SSL) e configura tudo automaticamente. (Ideal para VPS nova).
    * **Modo Painel/Coexistência:** Instala apenas o Docker e os Containers. Não mexe no Nginx do sistema. (Ideal para CloudPanel, Plesk ou servidores com Whaticket já rodando).
2.  **Verificador de Portas:** Evita conflitos! Se a porta `3000` (padrão) estiver em uso pelo Whaticket, o script avisa e pede outra (ex: `3005`).
3.  **Banco de Dados Flexível:** Opção de expor o PostgreSQL para acesso externo (DBeaver/Navicat) ou manter fechado para segurança.
4.  **Minio Console Separado:** Configura porta distinta para o Console do Minio para evitar erros de API.

---

## 🛠️ Como Instalar

Acesse seu servidor via SSH e execute os comandos abaixo sequencialmente.

### 1. Atualizar o sistema e instalar dependências básicas
```
sudo apt update && sudo apt upgrade -y
sudo apt install git dos2unix -y
````

### 2\. Baixar o instalador

Clone o repositório (altere o link abaixo se você hospedou em seu git, ou crie o arquivo manualmente):

```
# Exemplo se for criar o arquivo manualmente:
nano install_typebot.sh
# (Cole o conteúdo do script e salve com Ctrl+X, Y)
```

### 3\. Permissões e Execução

Torne o script executável e rode:

```
chmod +x install_typebot.sh
./install_typebot.sh
```

-----

## 🧩 Durante a Instalação (Passo a Passo)

O script fará perguntas interativas. Veja como responder dependendo do seu caso:

### Caso A: VPS Limpa (Somente Typebot)

  * **Pergunta:** "Qual o seu ambiente?"
  * **Resposta:** Escolha **Opção 1 (VPS Autônoma)**.
  * **O que acontece:** O script instala o Docker, sobe o Typebot, instala o Nginx e gera o SSL (HTTPS) automaticamente.

### Caso B: Servidor com Whaticket, Izing, Z-Pro ou Painel (Plesk/CloudPanel)

  * **Pergunta:** "Qual o seu ambiente?"
  * **Resposta:** Escolha **Opção 2 (VPS com Painel/Docker Apenas)**.
  * **Importante:**
      * Quando o script pedir as portas (`3000`, `3001`, etc.), **verifique se não conflita com seu SaaS**.
      * O script verificará automaticamente. Se a `3000` estiver ocupada pelo Whaticket, defina `3005` (exemplo) para o Typebot Builder.
  * **O que acontece:** O script sobe apenas os containers Docker. **Ele NÃO mexe no Nginx do servidor** para não derrubar seu Whaticket.

-----

## 🌐 Pós-Instalação (Apenas para Caso B)

Se você escolheu a **Opção 2** (Servidor Compartilhado/Painel), você precisará configurar o Proxy Reverso manualmente no seu gerenciador (Nginx Proxy Manager, CloudPanel, Plesk ou arquivo conf do Nginx).

Utilize as portas que você definiu durante a instalação. Exemplo padrão:

| Serviço | Domínio Exemplo | Destino (Proxy Pass) |
| :--- | :--- | :--- |
| **Builder** | `bot.seu.com` | `http://127.0.0.1:3000` (ou a porta escolhida) |
| **Viewer** | `chat.seu.com` | `http://127.0.0.1:3001` (ou a porta escolhida) |
| **Minio (S3)** | `s3.seu.com` | `http://127.0.0.1:9000` (ou a porta escolhida) |

> **Nota:** Lembre-se de ativar o suporte a **WebSockets** nas configurações do seu Proxy Reverso.

-----

## 🆘 Solução de Problemas

  * **Erro de Porta em Uso:** O script avisará "Porta X já está em uso". Simplesmente digite um número diferente (ex: troque 3000 por 3005, 3001 por 3006).
  * **Email não chega:** Verifique se as portas 465 ou 587 estão liberadas no Firewall da VPS.
  * **Erro 502 Bad Gateway:** Verifique se os containers estão rodando com `docker ps -a` e se o Proxy Reverso aponta para a porta correta.

-----

**Desenvolvido para facilitar a gestão de múltiplos ambientes.**
