# 🚀 Instalador Inteligente Typebot (Multi-Ambiente)

Este script automatiza a instalação do **Typebot** via Docker, projetado especificamente para **conviver pacificamente** com outras aplicações no mesmo servidor (como Whaticket, Izing, Z-Pro) ou rodar sob gerenciamento de painéis (CloudPanel, Plesk).

> **🛡️ Destaques da Versão:**
> * **Zero Conflito:** Verifica se portas estão ocupadas antes de iniciar.
> * **Multi-Cenário:** Modo para VPS Autônoma/SaaS ou Modo Painel.
> * **Customizável:** Você escolhe a versão do PostgreSQL (13 a 17+).
> * **Seguro:** Defina seu próprio usuário e senha para o Minio (S3).

---

## 📋 Pré-requisitos

* **Sistema Operacional:** Ubuntu 20.04, 22.04 ou 24.04.
* **Domínios:** 3 Subdomínios apontados para o IP do VPS:
  * `typebot.seudominio.com` (Builder)
  * `chat.seudominio.com` (Viewer)
  * `storage.seudominio.com` (Minio S3)
* **SMTP:** Credenciais de e-mail para envio de magic links.

---

## 🛠️ Como Instalar

Acesse seu servidor via SSH (como root) e siga os passos abaixo:

### 1. Atualizar o sistema
```
apt update && apt upgrade -y
apt install git dos2unix -y
````

### 2\. Baixar e Preparar o Script

Crie o arquivo do instalador:

```
nano install_typebot.sh
```

*Cole o conteúdo do script `install_typebot.sh` e salve (CTRL+O, Enter, CTRL+X).*

Dê permissão de execução:

```
chmod +x install_typebot.sh
```

### 3\. Executar

```
./install_typebot.sh
```

Se for necesário converter o script para unix execute o seguinte comando:

```
dos2unix install_typebot.sh
``

-----

## 🧩 O Guia de Instalação (Passo a Passo)

O script fará uma série de perguntas ("Quests") para configurar seu ambiente. Veja como responder:

### 1\. Seleção de Ambiente (A mais importante\!)

O script perguntará: *"Selecione o cenário do seu servidor"*

  * **Opção [1] VPS Limpa OU com SaaS (Whaticket/Izing):**

      * **Escolha se:** Você usa o terminal e já tem (ou vai ter) o Whaticket instalado.
      * **Ação:** O script instalará o Docker, criará configurações **seguras** do Nginx (`typebot_builder`, `typebot_viewer`) que não sobrescrevem as do Whaticket, e gerará o SSL automaticamente.

  * **Opção [2] VPS com Painel (Plesk/CloudPanel):**

      * **Escolha se:** Você gerencia o servidor por uma interface web (CloudPanel, CyberPanel, Plesk).
      * **Ação:** O script sobe **apenas** o Docker. Ele **não** mexe no Nginx para evitar quebrar seu painel.

### 2\. Configuração do Banco de Dados

  * **Versão do Postgres:** O padrão é `16`. Você pode alterar para `14`, `15` ou `17` conforme sua preferência de performance.
  * **Acesso Externo:** Você pode escolher expor o banco para conectar via DBeaver/Navicat. O script pedirá uma porta segura (para não conflitar com a 5432 padrão se já estiver em uso).

### 3\. Segurança do Minio (S3)

  * **Usuário e Senha:** Defina credenciais fortes. O script não usa mais `minioadmin` por padrão.
  * **Nota:** O script configura automaticamente o Typebot para usar essas novas credenciais.

### 4\. Verificação de Portas

Se você tiver o **Whaticket** rodando, a porta `3000` estará ocupada.

  * O script avisará: *"A porta 3000 já está em uso"*.
  * **Solução:** Digite `3005` (ou outra livre). O script ajustará todo o roteamento interno automaticamente.

-----

## 🌐 Pós-Instalação (Apenas para Usuários de Painel)

Se você escolheu a **Opção 2**, configure o Proxy Reverso no seu painel (CloudPanel/Plesk) apontando os domínios para as portas locais:

| Domínio | Destino (Proxy Pass) |
| :--- | :--- |
| **Builder** (`typebot.com`) | `http://127.0.0.1:3000` (ou a porta que escolheu) |
| **Viewer** (`chat.com`) | `http://127.0.0.1:3001` (ou a porta que escolheu) |
| **Storage** (`s3.com`) | `http://127.0.0.1:9000` (ou a porta que escolheu) |

> **⚠️ Importante:** Habilite o suporte a **Websockets** nas configurações do seu Proxy Reverso.

-----

## 🆘 Solução de Problemas

  * **Erro "Port Address already in use":** Se o Docker falhar ao subir, verifique se você não escolheu uma porta que outro serviço iniciou *durante* a instalação. Rode `./install_typebot.sh` novamente e escolha portas diferentes.
  * **Email não chega:** Verifique se o Firewall da VPS permite saída nas portas 465 ou 587.
  * **Banco de Dados:** Se optou por expor o banco, lembre-se de liberar a porta escolhida no Firewall da VPS (UFW ou Painel da Cloud).

-----

**Desenvolvido para flexibilidade e segurança.**
