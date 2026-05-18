#!/bin/bash                                                 

TEMPO_EXECUCAO=0
export LC_ALL=C                                             
# Define um PATH completo para garantir que comandos como df, awk e curl funcionem no cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Descobre o diretório real onde este script está salvo e entra nele
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

LOG_FILE="$SCRIPT_DIR/$(date '+%y%m%d-%H%M').log"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo "[✓] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[✗] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_section() {
    {
        echo ""
        echo "=========================================="
        echo "$1"
        echo "=========================================="
    } | tee -a "$LOG_FILE"
}

if [ ! -f .env ]; then
    log_error "Arquivo .env nao encontrado no diretorio $SCRIPT_DIR"
    exit 1
fi

source .env

WEBHOOK_URL="${WEBHOOK_URL}"
MOUNT_POINT="${MOUNT_POINT}"
                                                           
HD_STATUS=""                                              
HD_MSG=""                                                 
HD_USAGE=0                                                
SD_STATUS=""                                              
SD_MSG=""                                                 
SD_USAGE=0                                                
RAM_TOTAL=0                                                 
RAM_USADA=0                                                 
RAM_PCT=0                                                   
CPU_LOAD=""                                                 
CPU_TEMP=""                                                 
UPTIME_FMT=""                                               
CONTAINERS_LIST="[]"
GLOBAL_STATUS="OK"     

coleta_hd() {
    log_info "Iniciando coleta de dados do disco..."
    if grep -qs "$MOUNT_POINT" /proc/mounts; then
        log_info "Ponto de montagem $MOUNT_POINT confirmado em /proc/mounts"
        local MOUNT_OPTS=$(awk -v m="$MOUNT_POINT" '$2==m {print $4}' /proc/mounts)
        HD_USAGE=$(df -h "$MOUNT_POINT" | awk 'NR==2 {print $5}' | sed 's/%//')
        HD_USAGE_ABS=$(df -h "$MOUNT_POINT" | awk 'NR==2 {print $3}')
        
        log_info "Uso do disco: ${HD_USAGE}%"
        
        if [[ "$MOUNT_OPTS" == *"ro"* ]]; then
            HD_STATUS="CRITICAL"
            HD_MSG="Falha de I/O. Modo Somente Leitura ativado."
            log_error "$HD_MSG"
            return
        fi
        
        if [ "$HD_USAGE" -gt 90 ]; then
            HD_STATUS="WARNING"
            HD_MSG="Espaco critico atingido."
            log_error "$HD_MSG"
            return
        fi
        
        HD_STATUS="OK"
        HD_MSG="Operacao normal."
        log_success "Disco operando normalmente"
        return
    fi
    HD_STATUS="CRITICAL"
    HD_MSG="Desconexao: O disco nao esta montado em $MOUNT_POINT."
    HD_USAGE=0
    HD_USAGE_ABS="0"
    log_error "$HD_MSG"
}

coleta_sd() {
    log_info "Iniciando coleta de dados do SD Card (Root)..."
    local sd_mount="/"
    
    local IS_RO=$(awk -v m="$sd_mount" '$2==m {print $4}' /proc/mounts | grep -P "(^|,)ro(,|$)")
    SD_USAGE=$(df -h "$sd_mount" | awk 'NR==2 {print $5}' | sed 's/%//')
    SD_USAGE_ABS=$(df -h "$sd_mount" | awk 'NR==2 {print $3}')
    
    log_info "Uso do SD Card: ${SD_USAGE}%"
    
    if [ -n "$IS_RO" ]; then
        SD_STATUS="CRITICAL"
        SD_MSG="Falha de I/O. Modo Somente Leitura ativado no SD."
        log_error "$SD_MSG"
        return
    fi
    
    if [ "$SD_USAGE" -gt 90 ]; then
        SD_STATUS="WARNING"
        SD_MSG="Espaco critico atingido no SD Card."
        log_error "$SD_MSG"
        return
    fi
    
    SD_STATUS="OK"
    SD_MSG="Operacao normal."
    log_success "SD Card operando normalmente"
}

coleta_memoria() {
    log_info "Iniciando coleta de dados de memoria..."
    RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    RAM_USADA=$(free -m | awk '/Mem:/ {print $3}')
    RAM_PCT=$(awk "BEGIN {printf \"%.0f\", ($RAM_USADA/$RAM_TOTAL)*100}")

    log_info "Memoria total: ${RAM_TOTAL}MB"
    log_info "Memoria usada: ${RAM_USADA}MB (${RAM_PCT}%)"
    if [ "$RAM_PCT" -gt 90 ]; then
        log_error "Uso de memoria elevado: ${RAM_PCT}%"
        return
    fi
    if [ "$RAM_PCT" -gt 75 ]; then
        log_info "Uso de memoria moderado: ${RAM_PCT}%"
        return
    fi
    log_success "Uso de memoria saudavel: ${RAM_PCT}%"
    return
}                                                           

coleta_cpu() {                                                 
    log_info "Iniciando coleta de dados de CPU..."

    CPU_LOAD=$(cat /proc/loadavg | awk '{print $1}')
    log_info "Load average (1min): $CPU_LOAD"

    CPU_TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
    CPU_TEMP=$(awk "BEGIN {printf \"%.1f\", $CPU_TEMP_RAW/1000}")
    log_info "Temperatura da CPU: ${CPU_TEMP}°C"

    if (( $(echo "$CPU_TEMP > 75.0" | bc -l) )); then
        log_error "Temperatura elevada: ${CPU_TEMP}°C"
        return
    fi
    if (( $(echo "$CPU_TEMP > 60.0" | bc -l) )); then
        log_info "Temperatura moderada: ${CPU_TEMP}°C"
        return
    fi
    log_success "Temperatura adequada: ${CPU_TEMP}°C"
    return
}

coleta_uptime() {
    log_info "Iniciando coleta de uptime do sistema..."

    UPTIME_FMT=$(awk '{d=int($1/86400); h=int(($1%86400)/3600); m=int(($1%3600)/60); printf "%dd %dh %dm", d, h, m}' /proc/uptime)
    log_info "Uptime do sistema: $UPTIME_FMT"
    log_success "Coleta de uptime finalizada"
}

coleta_containers() {                                           
    log_info "Iniciando coleta de containers Docker..."

    CONTAINERS_LIST="[]"
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker nao esta instalado no sistema"
        log_success "Coleta de containers finalizada (Docker nao disponivel)"
        return
    fi

    if ! docker ps &> /dev/null; then
        log_error "Docker nao esta em execucao ou sem permissao"
        log_success "Coleta de containers finalizada (Docker indisponivel)"
        return
    fi

    local containers_json=""
    local container_count=0

    while IFS= read -r container_name; do
        [ -z "$container_name" ] && continue
        if echo "$container_name" | grep -E "^($IGNORED_CONTAINERS)$" > /dev/null; then
            skipped_count=$((skipped_count + 1))
            log_info "Ignorando container (na lista de exclusao): $container_name"
            continue
        fi

        container_count=$((container_count + 1))
        log_info "Analisando container: $container_name"

        local current_image=$(docker inspect "$container_name" --format='{{.Config.Image}}' 2>/dev/null)
        if [ -z "$current_image" ]; then
            log_error "  Falha ao obter imagem do container $container_name"
            continue
        fi
        log_info "  Imagem atual: $current_image"
        local update_available="false"
        local updated_now="false" # Nova variável indicadora
        
        local image_name=$(echo "$current_image" | cut -d':' -f1)
        log_info "  Verificando atualizacoes para $image_name..."

        local container_image_id=$(docker inspect "$container_name" --format='{{.Image}}' 2>/dev/null)
        local host_image_id=$(docker inspect "$current_image" --format='{{.Id}}' 2>/dev/null)

        # Captura o momento exato da CRIAÇÃO do container (em segundos)
        local created_at=$(docker inspect "$container_name" --format='{{.Created}}' 2>/dev/null)
        local created_sec=$(date +%s -d "$created_at" 2>/dev/null || echo 0)
        local now_sec=$(date +%s)
        local age_sec=$((now_sec - created_sec))

        log_info "Container Image: ${container_image_id:0:18}... - Host Image: ${host_image_id:0:18}..."

        if [ -n "$host_image_id" ] && [ "$container_image_id" != "$host_image_id" ]; then
            # Existe versão nova baixada, mas o container ainda roda a antiga (algo impediu a recriação)
            update_available="true"
            log_info "  ! Nova versao pendente para $container_name (Requer recriacao manual)"
        elif [ $age_sec -lt 600 ]; then 
            # O container foi recriado nos últimos 10 minutos (exatamente a janela deste script)
            updated_now="true"
            log_success "  ✓ NOVA VERSÃO APLICADA! Container recém-atualizado: $container_name"
        else
            log_success "  Container em conformidade: $container_name"
        fi

containers_json="${containers_json}{\"name\":\"$container_name\",\"image\":\"$current_image\",\"update_available\":$update_available,\"updated_now\":$updated_now},"
    done <<< "$(docker ps --format '{{.Names}}')"

    if [ -n "$containers_json" ]; then
        CONTAINERS_LIST="[${containers_json%,}]"
    fi

    log_info "Total de containers analisados: $container_count"
    log_success "Coleta de containers finalizada"
}

avalia_status_global() {
    log_info "Avaliando status global do sistema..."

    GLOBAL_STATUS="OK"
    local TEMP_ALTA=$(awk "BEGIN {if ($CPU_TEMP > 75.0) print 1; else print 0}")

    if [ "$HD_STATUS" == "CRITICAL" ] || [ "$SD_STATUS" == "CRITICAL" ] || [ "$RAM_PCT" -gt 95 ]; then
        GLOBAL_STATUS="CRITICAL"
        log_error "Status global: CRITICAL (SD, HD ou memoria em estado critico)"
    elif [ "$HD_STATUS" == "WARNING" ] || [ "$SD_STATUS" == "WARNING" ] || [ "$RAM_PCT" -gt 85 ] || [ "$TEMP_ALTA" -eq 1 ]; then
        GLOBAL_STATUS="WARNING"
        log_error "Status global: WARNING (Alerta em SD, HD, memoria ou temperatura)"
    else
        GLOBAL_STATUS="OK"
        log_success "Status global: OK (Sistema saudavel)"
    fi

    log_success "Avaliacao de status finalizada"
}

gerar_payload_json() {
    log_info "Gerando payload JSON..."

    jq -n \
      --arg status "$GLOBAL_STATUS" \
      --arg total_time "$TEMPO_EXECUCAO" \
      --arg hd_status "$HD_STATUS" \
      --arg hd_msg "$HD_MSG" \
      --arg hd_uso "$HD_USAGE" \
      --arg hd_uso_abs "$HD_USAGE_ABS" \
      --arg sd_status "$SD_STATUS" \
      --arg sd_msg "$SD_MSG" \
      --arg sd_uso "$SD_USAGE" \
      --arg sd_uso_abs "$SD_USAGE_ABS" \
      --arg r_pct "$RAM_PCT" \
      --arg r_uso "$RAM_USADA" \
      --arg c_load "$CPU_LOAD" \
      --arg c_temp "$CPU_TEMP" \
      --arg sys_up "$UPTIME_FMT" \
      --argjson containers "$CONTAINERS_LIST" \
      '{
         status_global: $status,
         tempo_execucao: $total_time,
         sistema: { uptime: $sys_up },
         sd_card: { status: $sd_status, mensagem: $sd_msg, uso_pct: $sd_uso, uso_abs: $sd_uso_abs },
         disco: { status: $hd_status, mensagem: $hd_msg, uso_pct: $hd_uso, uso_abs: $hd_uso_abs },
         memoria: { uso_pct: $r_pct, usada_mb: $r_uso },
         cpu: { load_1m: $c_load, temperatura_c: $c_temp },
         containers: $containers
       }' > /tmp/payload.json

    if [ $? -eq 0 ]; then
        log_success "JSON gerado com sucesso em /tmp/payload.json"
    else
        log_error "Falha na geracao do JSON"
    fi
}

enviar_para_n8n() {
    log_info "Enviando dados para o n8n..."
    
    local CLEAN_URL=$(echo "$WEBHOOK_URL" | tr -d '\r' | xargs)
    log_info "URL Sanitizada: $CLEAN_URL"

    local HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        --data-binary "@/tmp/payload.json" \
        "$CLEAN_URL")

    if [ "$HTTP_STATUS" -eq 200 ]; then
        log_success "Dados enviados com sucesso (HTTP $HTTP_STATUS)"
        return 0
    fi
    log_error "Falha no envio. Codigo HTTP: $HTTP_STATUS"
    return 1
}

exibir_resumo() {
    log_section "RESUMO DA EXECUCAO"
    echo "Status Global: $GLOBAL_STATUS"
    echo "SD: $SD_STATUS (${SD_USAGE}%) - $SD_MSG"
    echo "HD: $HD_STATUS (${HD_USAGE}%) - $HD_MSG"
    echo "Memoria: ${RAM_PCT}% (${RAM_USADA}MB/${RAM_TOTAL}MB)"
    echo "CPU: Load ${CPU_LOAD}, Temperatura ${CPU_TEMP}°C"
    echo "Uptime: $UPTIME_FMT"

    local container_count=$(echo "$CONTAINERS_LIST" | jq '. | length' 2>/dev/null || echo "0")
    echo "Containers em execucao: $container_count"

    echo ""
    echo "Timestamp final: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="
}

clean_disk() {
    log_info "Limpando arquivos temporarios..."
    sudo rm -rf /tmp/* /var/tmp/* 2>/dev/null

    log_info "Limpando apt files..."
    sudo apt autoremove -y >/dev/null 2>&1
    sudo apt clean >/dev/null 2>&1
    log_success "Apt limpo!"

    log_info "Limpando docker..."
    docker system prune -f >/dev/null 2>&1
    log_success "Docker limpo!"
}

pull_all_images() {
    log_info "Puxando todas as imagens..."
    
    if [ -z "$HOME_GIT_DIR" ]; then
        log_error "Variavel HOME_GIT_DIR nao esta definida."
        return
    fi

    if [ ! -d "$HOME_GIT_DIR" ]; then
        log_error "Diretorio nao encontrado: $HOME_GIT_DIR"
        return
    fi

    IFS=',' read -r -a excluded_array <<< "${EXCLUDED_DIRS:-}"

    for dir in "$HOME_GIT_DIR"/*/; do
        [ -d "$dir" ] || continue
        
        dir_name=$(basename "$dir")
        
        skip=false
        for exc in "${excluded_array[@]}"; do
            exc="${exc#"${exc%%[![:space:]]*}"}"
            exc="${exc%"${exc##*[![:space:]]}"}"
            
            if [ "$dir_name" = "$exc" ]; then
                skip=true
                break
            fi
        done

        if [ "$skip" = true ]; then
            log_info "Ignorando diretorio: $dir_name (lista de exclusoes)"
            continue
        fi

        log_info "Atualizando containers em: $dir_name"
        if (cd "$dir" && docker compose pull -q && docker compose up -d --remove-orphans); then
            if [[ "$dir_name" == "n8n" ]]; then
                log_info "Aguardando n8n ficar saudável..."
                local attempts=0
                while [ "$(docker inspect --format='{{.State.Health.Status}}' n8n 2>/dev/null)" != "healthy" ]; do
                    sleep 5
                    attempts=$((attempts + 1))
                    if [ $attempts -gt 30 ]; then
                        log_error "Timeout aguardando healthcheck do n8n."
                        break
                    fi
                done
                log_success "n8n está online!"
            fi
            continue
        fi
        log_error "Falha ao atualizar o diretorio $dir_name"
    done
    log_success "Processo de pull de imagens concluido."
}

main() {
    local start_time=$SECONDS
    log_section "INICIANDO MONITORAMENTO DO SISTEMA"
    log_info "Data/Hora: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "Hostname: $(hostname)"

    pull_all_images
    coleta_hd
    coleta_sd
    coleta_memoria
    coleta_cpu
    coleta_uptime
    coleta_containers
    avalia_status_global

    TEMPO_EXECUCAO=$(( SECONDS - start_time ))

    gerar_payload_json
    enviar_para_n8n
    exibir_resumo

    log_section "MONITORAMENTO CONCLUIDO"

    clean_disk
}

main
