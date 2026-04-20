#!/bin/bash                                                 
export LC_ALL=C                                             

# --- Configurações Globais ---                             
# Lê as variáveis do arquivo .env
ENV_FILE="$(dirname "$0")/.env"
source "$ENV_FILE"

WEBHOOK_URL="${WEBHOOK_URL}"
MOUNT_POINT="${MOUNT_POINT}"
                                                           
# Variáveis globais para coleta de dados                    
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

# --- Função de Log ---
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo "[✓] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo "[✗] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_section() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

coleta_hd() {
    log_info "Iniciando coleta de dados do disco..."
    if mountpoint -q "$MOUNT_POINT"; then
        log_info "Ponto de montagem $MOUNT_POINT encontrado"
        IS_RO=$(awk -v m="$MOUNT_POINT" '$2==m {print $4}' /proc/mounts | grep -P "(^|,)ro(,|$)")
        HD_USAGE=$(df -h "$MOUNT_POINT" | awk 'NR==2 {print $5}' | sed 's/%//')
        log_info "Uso do disco: ${HD_USAGE}%"
        if [ -n "$IS_RO" ]; then
            HD_STATUS="CRITICAL"
            HD_MSG="Falha de I/O. Modo Somente Leitura ativado."
            log_error "$HD_MSG"
            return
        fi
        if [ "$HD_USAGE" -gt 90 ]; then
            HD_STATUS="WARNING"
            HD_MSG="Espaço crítico atingido."
            log_error "$HD_MSG"
            return
        fi
        HD_STATUS="OK"
        HD_MSG="Operação normal."
        log_success "Disco operando normalmente"
        return
    fi
    HD_STATUS="CRITICAL"
    HD_MSG="Desconexão: O disco não está montado."
    HD_USAGE=0
    log_error "$HD_MSG"
}

coleta_sd() {
    log_info "Iniciando coleta de dados do SD Card (Root)..."
    local sd_mount="/"
    
    local IS_RO=$(awk -v m="$sd_mount" '$2==m {print $4}' /proc/mounts | grep -P "(^|,)ro(,|$)")
    SD_USAGE=$(df -h "$sd_mount" | awk 'NR==2 {print $5}' | sed 's/%//')
    log_info "Uso do SD Card: ${SD_USAGE}%"
    
    if [ -n "$IS_RO" ]; then
        SD_STATUS="CRITICAL"
        SD_MSG="Falha de I/O. Modo Somente Leitura ativado no SD."
        log_error "$SD_MSG"
        return
    fi
    
    if [ "$SD_USAGE" -gt 90 ]; then
        SD_STATUS="WARNING"
        SD_MSG="Espaço crítico atingido no SD Card."
        log_error "$SD_MSG"
        return
    fi
    
    SD_STATUS="OK"
    SD_MSG="Operação normal."
    log_success "SD Card operando normalmente"
}

coleta_memoria() {
    log_info "Iniciando coleta de dados de memória..."
    RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    RAM_USADA=$(free -m | awk '/Mem:/ {print $3}')
    RAM_PCT=$(awk "BEGIN {printf \"%.0f\", ($RAM_USADA/$RAM_
TOTAL)*100}")

    log_info "Memória total: ${RAM_TOTAL}MB"
    log_info "Memória usada: ${RAM_USADA}MB (${RAM_PCT}%)"  
    if [ "$RAM_PCT" -gt 90 ]; then
        log_error "Uso de memória elevado: ${RAM_PCT}%"         
    elif [ "$RAM_PCT" -gt 75 ]; then
        log_info "Uso de memória moderado: ${RAM_PCT}%"
    else                                                            
        log_success "Uso de memória saudável: ${RAM_PCT}%"
    fi                                                                                                                      
    log_success "Coleta de dados de memória finalizada"     
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
    elif (( $(echo "$CPU_TEMP > 60.0" | bc -l) )); then
        log_info "Temperatura moderada: ${CPU_TEMP}°C"
    else
        log_success "Temperatura adequada: ${CPU_TEMP}°C"
    fi

    log_success "Coleta de dados de CPU finalizada"
}

coleta_uptime() {
    log_info "Iniciando coleta de uptime do sistema..."

    UPTIME_FMT=$(awk '{d=int($1/86400); h=int(($1%86400)/3600); m=int(($1%3600)/60); printf "%dd %dh %dm", d, h, m}' /proc/uptime)
    log_info "Uptime do sistema: $UPTIME_FMT"
    log_success "Coleta de uptime finalizada"
}

coleta_containers() {                                           
    log_info "Iniciando coleta de containers Docker..."

    IGNORED_CONTAINERS="lamp|bolao-dev|bolao-prd|ollama"    
    if ! command -v docker &> /dev/null; then
        log_error "Docker não está instalado no sistema"
        CONTAINERS_LIST="[]"
        log_success "Coleta de containers finalizada (Docker não disponível)"
        return
    fi

    if ! docker ps &> /dev/null; then
        log_error "Docker não está em execução ou sem permissão"
        CONTAINERS_LIST="[]"
        log_success "Coleta de containers finalizada (Docker indisponível)"
        return
    fi

    local containers_json=""
    local container_count=0

    while IFS= read -r container_name; do
        [ -z "$container_name" ] && continue
        if echo "$container_name" | grep -E "^($IGNORED_CONTAINERS)$" > /dev/null; then
            skipped_count=$((skipped_count + 1))
            log_info "Ignorando container (na lista de exclusão): $container_name"
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
        local image_name=$(echo "$current_image" | cut -d':' -f1)
        local current_tag=$(echo "$current_image" | cut -d':' -f2)
        [ -z "$current_tag" ] && current_tag="latest"
        log_info "  Verificando atualizações para $image_name..."

        if docker pull "$image_name" > /dev/null 2>&1; then
            local remote_digest=$(docker inspect --format='{.Id}}' "$image_name" 2>/dev/null)
            local current_digest=$(docker inspect --format='{{.Image}}' "$container_name" 2>/dev/null)

            if [ -n "$remote_digest" ] && [ -n "$current_digest" ] && [ "$remote_digest" != "$current_digest" ]; then
                update_available="true"
                log_info "  ✓ Nova versão disponível para $container_name"
            else                                                            
                log_success "  Container atualizado: $container_name"
            fi
        else
            log_error "  Falha ao verificar atualizações para $image_name"
        fi

        containers_json="${containers_json}{\"name\":\"$container_name\",\"image\":\"$current_image\",\"update_available\":$update_available},"

    done <<< "$(docker ps --format '{{.Names}}')"
    if [ -n "$containers_json" ]; then
        CONTAINERS_LIST="[${containers_json%,}]"
    else
        CONTAINERS_LIST="[]"
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
        log_error "Status global: CRITICAL (SD, HD ou memória em estado crítico)"
    elif [ "$HD_STATUS" == "WARNING" ] || [ "$SD_STATUS" == "WARNING" ] || [ "$RAM_PCT" -gt 85 ] || [ "$TEMP_ALTA" -eq 1 ]; then
        GLOBAL_STATUS="WARNING"
        log_error "Status global: WARNING (Alerta em SD, HD, memória ou temperatura)"
    else
        GLOBAL_STATUS="OK"
        log_success "Status global: OK (Sistema saudável)"
    fi

    log_success "Avaliação de status finalizada"
}

gerar_payload_json() {
    log_info "Gerando payload JSON..."

    JSON_DATA=$(jq -n \
      --arg status "$GLOBAL_STATUS" \
      --arg hd_status "$HD_STATUS" \
      --arg hd_msg "$HD_MSG" \
      --arg hd_uso "$HD_USAGE" \
      --arg sd_status "$SD_STATUS" \
      --arg sd_msg "$SD_MSG" \
      --arg sd_uso "$SD_USAGE" \
      --arg r_pct "$RAM_PCT" \
      --arg r_uso "$RAM_USADA" \
      --arg c_load "$CPU_LOAD" \
      --arg c_temp "$CPU_TEMP" \
      --arg sys_up "$UPTIME_FMT" \
      --argjson containers "$CONTAINERS_LIST" \
      '{
         status_global: $status,
         sistema: { uptime: $sys_up },
         sd_card: { status: $sd_status, mensagem: $sd_msg, uso_pct: $sd_uso },
         disco: { status: $hd_status, mensagem: $hd_msg, uso_pct: $hd_uso },
         memoria: { uso_pct: $r_pct, usada_mb: $r_uso },
         cpu: { load_1m: $c_load, temperatura_c: $c_temp },
         containers: $containers
       }')

    if echo "$JSON_DATA" | jq . > /dev/null 2>&1; then
        log_success "JSON gerado com sucesso"
    else
        log_error "Falha na geração do JSON"
    fi
}

enviar_para_n8n() {
    log_info "Enviando dados para o n8n..."
    log_info "Webhook URL: $WEBHOOK_URL"

    local HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$JSON_DATA" \
        "$WEBHOOK_URL")

    if [ "$HTTP_STATUS" -eq 200 ]; then
        log_success "Dados enviados com sucesso para o n8n (HTTP $HTTP_STATUS)"
    else
        log_error "Falha ao enviar para o n8n. Código HTTP: $HTTP_STATUS"
    fi
}

exibir_resumo() {
    log_section "RESUMO DA EXECUÇÃO"
    echo "Status Global: $GLOBAL_STATUS"
    echo "SD: $SD_STATUS (${SD_USAGE}%) - $SD_MSG"
    echo "HD: $HD_STATUS (${HD_USAGE}%) - $HD_MSG"
    echo "Memória: ${RAM_PCT}% (${RAM_USADA}MB/${RAM_TOTAL}MB)"
    echo "CPU: Load ${CPU_LOAD}, Temperatura ${CPU_TEMP}°C"
    echo "Uptime: $UPTIME_FMT"

    local container_count=$(echo "$CONTAINERS_LIST" | jq '. | length' 2>/dev/null || echo "0")
    echo "Containers em execução: $container_count"

    echo ""
    echo "Timestamp final: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="
}

main() {
    log_section "INICIANDO MONITORAMENTO DO SISTEMA"
    log_info "Data/Hora: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "Hostname: $(hostname)"

    coleta_hd
    coleta_sd
    coleta_memoria
    coleta_cpu
    coleta_uptime
    coleta_containers
    avalia_status_global
    gerar_payload_json
    enviar_para_n8n
    exibir_resumo

    log_section "MONITORAMENTO CONCLUÍDO"
}

main
