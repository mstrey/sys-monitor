const inputDados = $input.first().json;

function escapeHtml(str) {
    if (!str) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function getTempoFormatado(tempoSegundos) {
    const tempo = Number(tempoSegundos) || 0;
    const minutos = Math.floor(tempo / 60);
    const segundos = tempo % 60;
    return minutos > 0 ? `${minutos}m ${segundos}s` : `${segundos}s`;
}

function getSubject(statusGlobal) {
    let icon = '';
    switch (statusGlobal) {
        case 'OK':
            icon = '🟢';
            break;
        case 'WARNING':
            icon = '🟡';
            break;
        default:
            icon = '🔴';
    }
    return `${icon} Relatório do Servidor: ${statusGlobal}`;
}

function getBadge(updatedNow) {
    let color = '#4caf50'
    let status = '✓ OK';
    if (updatedNow) {
        color = '#ff9800'
        status = '🔄 UPDATE';
    }
    return `<span style="background-color: ${color}; color: white; padding: 2px 8px; border-radius: 12px; font-size: 11px; font-weight: bold;">${status}</span>`;
}

function getLinhaContainer(container) {
    const badge = getBadge(container.updated_now);
    const name = escapeHtml(container.name);
    const image = escapeHtml(container.image);

    return `
    <tr>
      <td style="padding: 8px 0; border-bottom: 1px solid #f0f0f0;"><strong>${name}</strong></td>
      <td style="padding: 8px 0; border-bottom: 1px solid #f0f0f0; text-align: center;">${badge}</td>
      <td style="padding: 8px 0; border-bottom: 1px solid #f0f0f0; font-family: monospace; font-size: 12px;">${image}</td>
    </tr>
  `;
}

function getListaContainers(containers = []) {
    if (containers.length === 0) {
        return '<p style="text-align: center; color: #999; font-style: italic; margin-top: 16px;">Nenhum container Docker em execução</p>';
    }

    const linhasHtml = containers.map(container => getLinhaContainer(container)).join('');

    return `
    <table aria-label="Lista de containers em execução" style="width: 100%; border-collapse: collapse; font-size: 14px;">
      <thead>
        <tr style="background-color: #f8f9fa;">
          <th scope="col" style="padding: 10px; text-align: left; border-bottom: 2px solid #dee2e6;">Container</th>
          <th scope="col" style="padding: 10px; text-align: center; border-bottom: 2px solid #dee2e6;">Status</th>
          <th scope="col" style="padding: 10px; text-align: left; border-bottom: 2px solid #dee2e6;">Imagem</th>
        </tr>
      </thead>
      <tbody>
        ${linhasHtml}
      </tbody>
    </table>
  `;
}

function getBody(data) {
    const tempoFormatado = getTempoFormatado(data.tempo_execucao);
    const containersHtml = getListaContainers(data.containers);
    const style_h3 = "color: #2980b9; margin-bottom: 12px; font-size: 16px; border-bottom: 1px solid #eeeeee; padding-bottom: 6px;"
    const style_row = "display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #f0f0f0; font-size: 14px;"

    return `
  <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; border: 1px solid #e0e0e0; border-radius: 8px; overflow: hidden; color: #333333;">
    <div style="background-color: #2c3e50; color: #ffffff; padding: 20px; text-align: center;">
      <h2 style="margin: 0; font-size: 20px;">Relatório de Saúde da Infraestrutura</h2>
    </div>
    <div style="padding: 24px;">
      
      <div style="background-color: #f8f9fa; padding: 15px; border-radius: 6px; border-left: 4px solid #27ae60; margin-bottom: 24px;">
        <p style="margin: 0 0 8px 0;"><strong>Status Geral:</strong> ${escapeHtml(data.status_global)}</p>
        <p style="margin:0 0 8px 0"><strong>Uptime:</strong> ${escapeHtml(data.sistema?.uptime)}</p>
        <p style="margin: 0;"><strong>Tempo de Execução:</strong> ${tempoFormatado}</p>
      </div>
      
      <h3 style="${style_h3}"><span role="img" aria-label="Cartão SD">💾</span> SDCARD</h3>
      <div aria-label="Informações do SDCARD" style="margin-bottom: 24px;">
        <div style="${style_row}"><strong>Status:</strong> <span>${escapeHtml(data.sd_card?.status)}</span></div>
        <div style="${style_row}"><strong>Detalhe:</strong> <span>${escapeHtml(data.sd_card?.mensagem)}</span></div>
        <div style="${style_row}"><strong>Uso do HD:</strong> <span>${escapeHtml(data.sd_card?.uso_pct)}%</span></div>
      </div>
      
      <h3 style="${style_h3}"><span role="img" aria-label="Disco Rígido">💽</span> HD EXTERNO</h3>
      <div aria-label="Informações do HD Externo" style="margin-bottom: 24px;">
        <div style="${style_row}"><strong>Status:</strong> <span>${escapeHtml(data.disco?.status)}</span></div>
        <div style="${style_row}"><strong>Detalhe:</strong> <span>${escapeHtml(data.disco?.mensagem)}</span></div>
        <div style="${style_row}"><strong>Uso do HD:</strong> <span>${escapeHtml(data.disco?.uso_pct)}%</span></div>
      </div>
      
      <h3 style="${style_h3}"><span role="img" aria-label="Cérebro">🧠</span> MEMÓRIA</h3>
      <div aria-label="Informações de Memória RAM" style="margin-bottom: 24px;">
        <div style="${style_row}"><strong>Uso de RAM:</strong> <span>${escapeHtml(data.memoria?.uso_pct)}%</span></div>
        <div style="${style_row}"><strong>Consumo Absoluto:</strong> <span>${escapeHtml(data.memoria?.usada_mb)} MB</span></div>
      </div>
      
      <h3 style="${style_h3}"><span role="img" aria-label="Engrenagem">⚙️</span> CPU</h3>
      <div aria-label="Informações da CPU" style="margin-bottom: 24px;">
        <div style="${style_row}"><strong>Temperatura:</strong> <span>${escapeHtml(data.cpu?.temperatura_c)} °C</span></div>
        <div style="${style_row}"><strong>Carga (1m):</strong> <span>${escapeHtml(data.cpu?.load_1m)}</span></div>
      </div>
      
      <h3 style="${style_h3}"><span role="img" aria-label="Baleia Docker">🐳</span> CONTAINERS EM EXECUÇÃO</h3>
      ${containersHtml}
      
    </div>
    <div style="background-color: #f4f4f4; padding: 12px; text-align: center; font-size: 11px; color: #888888;">
      Relatório gerado automaticamente pelo sistema de monitoramento via n8n.
    </div>
  </div>
  `;
}

const data = inputDados.body || {};
return [{
    json: {
        ...inputDados,
        html: getBody(data),
        subject: getSubject(data.status_global)
    }
}];