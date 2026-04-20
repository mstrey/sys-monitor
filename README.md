# sys-monitor

Sistema em Bash para monitoramento local de servidores Unix/Linux, integrado via Webhook com o n8n para disparo de alertas e relatórios periódicos por e-mail.

## Detalhes do Projeto

O script `monitoramento.sh` realiza a coleta de diversas métricas essenciais do sistema:
- **Disco Externo (HD/SSD)**: Verifica o uso (alerta \> 90%) e o status de montagem (read-only/desconectado).
- **SD Card (Root)**: Verifica o armazenamento da partição root e falhas de I/O.
- **Memória RAM**: Coleta o consumo e alerta em níveis críticos.
- **Processador (CPU)**: Apura a temperatura térmica e a carga instantânea (Load Average).
- **Uptime**: Registro do tempo de atividade ininterrupto do servidor.
- **Docker Containers**: Analisa a integridade e busca novas atualizações de imagem para os containers ativos (ignorando alguns configuráveis).

Após avaliar as métricas e consolidar o "Status Global" do sistema, o script formata todos os dados em um pacote JSON e faz o envio (via `curl`) para um Webhook gerenciado no [n8n](https://n8n.io/). O n8n intercepta os dados, formata os resultados em e-mail HTML rico e dispara aos administradores.

## Dependências

Para executar adequadamente em seu ambiente, certifique-se de possuir:
- `bash`
- `curl` e `jq` (para gerar e enviar requisições JSON)
- `bc` e `awk` (para cálculos numéricos flutuantes)
- `docker` (opcional: se não estiver em execução ele apenas ignora a listagem)
- Instância do **n8n** rodando internamente ou externamente para receber as atualizações

## Como implantar em um novo ambiente

Siga o passo a passo abaixo para levar o monitoramento ao seu novo servidor:

### 1. Clonar o projeto
```bash
git clone <URL-do-repositorio> sys-monitor
cd sys-monitor
```

### 2. Importar fluxo no n8n automatizado
O repositório já inclui um arquivo de Workflow pré-pronto:
1. Acesse o seu gerenciador de workflows no **n8n**.
2. Clique no menu lateral direito ou vá em opções para "Import from File".
3. Use o arquivo [`n8n-webhook.json`](./n8n-webhook.json) que está no repositório.
4. Ajuste suas Credenciais (SMTP) preenchidas no Node "Send an Email" com remetente (From) e destinatário (To) de sua preferência.
5. Ative o Workflow!
6. Anote a url do webhook gerada pelo n8n.

### 3. Configuração Variáveis de Ambiente
Copie o arquivo de exemplo e insira suas predefinições:
```bash
cp .env.example .env
nano .env
```
Variáveis principais:
* `WEBHOOK_URL="<URL-do-webhook-n8n>"`: Endereço do Webhook do n8n
* `MOUNT_POINT="<caminho-do-disco-montado>"`: O caminho de disco montado que deverá ser analisado pelo script.

### 4. Permissões
Dê a permissão correta e tente iniciar pelo menos uma vez manualmente para validar a saída no terminal.
```bash
chmod +x monitoramento.sh
./monitoramento.sh
```

### 5. Automatizando com Cron
Use o crontab se desejar fazer com que a aplicação rode recorrentemente em seu background, repassando os status nos e-mails.
```bash
crontab -e
```
Exemplo para envio diário:
```cron
0 0 * * * cd /caminho/absoluto/sys-monitor && ./monitoramento.sh >> /var/log/sys-monitor.log 2>&1
```
