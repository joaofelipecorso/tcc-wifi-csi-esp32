%% MONITORAR_DRIFT - Captura CSI por horas e analisa variacao temporal
%
% Captura continuamente CSI do ESP32 sem ninguem no quarto.
% Registra amplitude, fase, RSSI, variancia - tudo.
% Para: crie um arquivo C:\TCC2\stop.txt
%
% Apos parar, gera:
%   - Graficos de variacao ao longo do tempo
%   - Estatisticas por janela de 5 minutos
%   - Analise de drift (correlacao com tempo)
%   - Tudo salvo em .mat para uso posterior
%
% COMO PARAR: crie o arquivo C:\TCC2\stop.txt (pode ser vazio)
%   No cmd: echo. > C:\TCC2\stop.txt

clear; clc; close all;

%% CONFIGURACAO
PORTA = "COM5";
BAUD  = 921600;
JANELA_SEG = 3;              % duracao de cada captura
INTERVALO_SEG = 10;          % intervalo entre capturas (total = janela + intervalo)
ARQUIVO_STOP = 'C:\TCC2\stop.txt';
ARQUIVO_SAIDA = 'C:\TCC2\drift_monitor.mat';
PASTA_COMUM = 'C:\TCC2\matlab\comum';

addpath(PASTA_COMUM);

% Remove stop file se existir de execucao anterior
if exist(ARQUIVO_STOP, 'file'), delete(ARQUIVO_STOP); end

fprintf('================================================================\n');
fprintf('  MONITORAMENTO DE DRIFT TEMPORAL\n');
fprintf('================================================================\n\n');
fprintf('INSTRUCOES:\n');
fprintf('  1. SAIA do quarto e feche a porta\n');
fprintf('  2. Nao entre no quarto durante o monitoramento\n');
fprintf('  3. Para PARAR: crie o arquivo C:\\TCC2\\stop.txt\n');
fprintf('     (no cmd: echo. > C:\\TCC2\\stop.txt)\n');
fprintf('  4. Deixe rodando por pelo menos 1-2 horas\n\n');
fprintf('Intervalo entre capturas: %d segundos\n', JANELA_SEG + INTERVALO_SEG);
fprintf('Amostras por hora: ~%d\n\n', floor(3600 / (JANELA_SEG + INTERVALO_SEG)));
fprintf('Pressione ENTER e SAIA do quarto...\n');
input('');

% Contagem para sair
for t = 30:-1:1
    fprintf('  Saindo em %d...\n', t);
    pause(1);
end

%% ABRE SERIAL
fprintf('\nAbrindo serial...\n');
delete(serialportfind);
s = serialport(PORTA, BAUD, "Timeout", 3);
pause(12); flush(s);

% Teste
t0 = tic; buf = uint8([]);
while toc(t0) < 2
    if s.NumBytesAvailable > 0
        b = read(s, s.NumBytesAvailable, "uint8");
        buf = [buf; b(:)];
    end
    pause(0.05);
end
[~, nt] = ler_csi_buffer(buf);
fprintf('Taxa CSI: %.0f/s\n', nt/2);
if nt < 10
    fprintf('ERRO: ESP32 sem dados.\n');
    delete(s); return;
end

%% ESTRUTURAS DE DADOS
max_amostras = 10000;  % suficiente para ~28 horas

% Dados por amostra (cada amostra = 3 segundos)
dados.timestamp = NaT(max_amostras, 1);        % horario
dados.minutos = zeros(max_amostras, 1);         % minutos desde inicio
dados.n_frames = zeros(max_amostras, 1);        % frames na amostra

% Amplitude - medias por subportadora
dados.amp_media_global = zeros(max_amostras, 1);       % media de todas subs
dados.amp_std_global = zeros(max_amostras, 1);          % std de todas subs
dados.amp_media_por_sub = zeros(max_amostras, 64);      % media por sub
dados.amp_std_temporal = zeros(max_amostras, 64);        % std temporal por sub

% Fase
dados.fase_media_global = zeros(max_amostras, 1);
dados.fase_std_global = zeros(max_amostras, 1);
dados.fase_media_por_sub = zeros(max_amostras, 64);

% Variabilidade inter-frame
dados.var_inter_frame = zeros(max_amostras, 1);   % MAD medio entre frames
dados.autocorr_media = zeros(max_amostras, 1);    % autocorrelacao lag-1

% Energia total
dados.energia_total = zeros(max_amostras, 1);     % soma de amplitudes

% Features V2 (para ver como mudam)
n_feat = length(extrair_features_v2(rand(100, 64)));
dados.features = zeros(max_amostras, n_feat);

%% LOOP PRINCIPAL
fprintf('\n================================================================\n');
fprintf('  MONITORANDO... (para parar: echo. > C:\\TCC2\\stop.txt)\n');
fprintf('================================================================\n\n');

t_inicio = tic;
n_amostras_coletadas = 0;

while true
    % Verifica stop
    if exist(ARQUIVO_STOP, 'file')
        fprintf('\n>>> Arquivo stop.txt detectado. Finalizando...\n');
        break;
    end
    
    % Verifica limite
    if n_amostras_coletadas >= max_amostras
        fprintf('\n>>> Limite de amostras atingido. Finalizando...\n');
        break;
    end
    
    % Captura
    flush(s); pause(0.1);
    t0 = tic;
    buf = uint8([]);
    while toc(t0) < JANELA_SEG
        if s.NumBytesAvailable > 0
            b = read(s, s.NumBytesAvailable, "uint8");
            buf = [buf; b(:)];
        end
        pause(0.05);
    end
    
    % Parse - extrai real e imag para calcular fase
    texto = char(buf(:)');
    linhas = strsplit(texto, newline);
    
    reais_all = [];
    imags_all = [];
    for k = 1:length(linhas)
        linha = linhas{k};
        if ~contains(linha, 'CSI_DATA'), continue; end
        i1 = strfind(linha, '['); i2 = strfind(linha, ']');
        if isempty(i1) || isempty(i2), continue; end
        conteudo = linha(i1(1)+1:i2(end)-1);
        vals = str2double(strsplit(conteudo, ','));
        vals = vals(~isnan(vals));
        if length(vals) < 128, continue; end
        vals = vals(1:128);
        reais_all = [reais_all; vals(1:2:end)];
        imags_all = [imags_all; vals(2:2:end)];
    end
    
    n_frames = size(reais_all, 1);
    if n_frames < 20
        pause(INTERVALO_SEG);
        continue;
    end
    
    % Calcula amplitude e fase
    amplitudes = sqrt(reais_all.^2 + imags_all.^2);
    fases = atan2(imags_all, reais_all);
    for k = 1:n_frames
        fases(k, :) = unwrap(fases(k, :));
    end
    
    % Tambem pega amplitude via ler_csi_buffer para features
    [amp_buf, ~] = ler_csi_buffer(buf);
    
    n_amostras_coletadas = n_amostras_coletadas + 1;
    idx = n_amostras_coletadas;
    
    tempo_min = toc(t_inicio) / 60;
    
    % Salva dados
    dados.timestamp(idx) = datetime('now');
    dados.minutos(idx) = tempo_min;
    dados.n_frames(idx) = n_frames;
    
    % Amplitude
    dados.amp_media_global(idx) = mean(amplitudes(:));
    dados.amp_std_global(idx) = std(amplitudes(:));
    n_sub = min(64, size(amplitudes, 2));
    dados.amp_media_por_sub(idx, 1:n_sub) = mean(amplitudes, 1);
    dados.amp_std_temporal(idx, 1:n_sub) = std(amplitudes, 0, 1);
    
    % Fase
    dados.fase_media_global(idx) = mean(fases(:));
    dados.fase_std_global(idx) = std(fases(:));
    dados.fase_media_por_sub(idx, 1:n_sub) = mean(fases, 1);
    
    % Variabilidade
    if n_frames > 1
        diffs = diff(amplitudes, 1, 1);
        dados.var_inter_frame(idx) = mean(abs(diffs(:)));
        
        acorrs = zeros(1, n_sub);
        for j = 1:n_sub
            x = amplitudes(:, j);
            if std(x) > 0.01
                c = corrcoef(x(1:end-1), x(2:end));
                acorrs(j) = c(1, 2);
            end
        end
        dados.autocorr_media(idx) = mean(acorrs(~isnan(acorrs)));
    end
    
    % Energia
    dados.energia_total(idx) = sum(amplitudes(:));
    
    % Features V2
    if ~isempty(amp_buf) && size(amp_buf, 1) >= 5
        dados.features(idx, :) = extrair_features_v2(amp_buf);
    end
    
    % Log
    horas = floor(tempo_min / 60);
    mins = floor(mod(tempo_min, 60));
    fprintf('[%02d:%02d:%02d] #%d | %d fr | amp=%.1f+-%.1f | fase=%.2f | var=%.2f | energia=%.0f\n', ...
            horas, mins, floor(mod(tempo_min*60, 60)), ...
            idx, n_frames, ...
            dados.amp_media_global(idx), dados.amp_std_global(idx), ...
            dados.fase_media_global(idx), ...
            dados.var_inter_frame(idx), ...
            dados.energia_total(idx));
    
    % Salva parcial a cada 50 amostras
    if mod(idx, 50) == 0
        dados_parcial = cortar_dados(dados, idx);
        save(ARQUIVO_SAIDA, 'dados_parcial', '-v7.3');
        fprintf('  >>> Salvo parcial (%d amostras, %.1f min)\n', idx, tempo_min);
    end
    
    % Espera intervalo
    pause(INTERVALO_SEG);
end

%% FECHA SERIAL
delete(s);
tempo_total_min = toc(t_inicio) / 60;

%% CORTA DADOS
dados_final = cortar_dados(dados, n_amostras_coletadas);

%% SALVA COMPLETO
save(ARQUIVO_SAIDA, 'dados_final', '-v7.3');
fprintf('\nDados salvos: %s (%d amostras, %.1f minutos)\n', ...
        ARQUIVO_SAIDA, n_amostras_coletadas, tempo_total_min);

%% ================================================================
%  ANALISE AUTOMATICA
%  ================================================================
fprintf('\n================================================================\n');
fprintf('  ANALISE DE DRIFT\n');
fprintf('================================================================\n\n');

n = n_amostras_coletadas;
t_min = dados_final.minutos;

% Correlacao de cada metrica com tempo
metricas = {'amp_media_global', 'amp_std_global', 'fase_media_global', ...
            'fase_std_global', 'var_inter_frame', 'autocorr_media', 'energia_total'};
nomes = {'Amplitude media', 'Amplitude std', 'Fase media', ...
         'Fase std', 'Variabilidade inter-frame', 'Autocorrelacao', 'Energia total'};

fprintf('%-30s %10s %10s %10s %10s %10s\n', ...
        'Metrica', 'Media', 'Std', 'Min', 'Max', 'Corr(t)');
fprintf('%s\n', repmat('-', 1, 80));

corr_com_tempo = zeros(length(metricas), 1);
for m = 1:length(metricas)
    vals = dados_final.(metricas{m});
    mu = mean(vals); sd = std(vals);
    mn = min(vals); mx = max(vals);
    if sd > 0
        c = corrcoef(t_min, vals);
        ct = c(1,2);
    else
        ct = 0;
    end
    corr_com_tempo(m) = ct;
    
    marca = '';
    if abs(ct) > 0.5, marca = ' *** DRIFT!'; 
    elseif abs(ct) > 0.3, marca = ' ** moderado';
    elseif abs(ct) > 0.1, marca = ' * leve'; end
    
    fprintf('%-30s %10.2f %10.2f %10.2f %10.2f %10.3f%s\n', ...
            nomes{m}, mu, sd, mn, mx, ct, marca);
end

% Analise por janela de 5 minutos
fprintf('\n--- Variacao por janela de 5 minutos ---\n');
janela_min = 5;
n_janelas = floor(max(t_min) / janela_min);
if n_janelas > 1
    fprintf('%-10s %12s %12s %12s %12s\n', 'Janela', 'Amp media', 'Amp std', 'Fase media', 'Energia');
    for j = 0:n_janelas-1
        mask = t_min >= j*janela_min & t_min < (j+1)*janela_min;
        if sum(mask) == 0, continue; end
        fprintf('%4d-%4d   %12.2f %12.2f %12.2f %12.0f\n', ...
                j*janela_min, (j+1)*janela_min, ...
                mean(dados_final.amp_media_global(mask)), ...
                mean(dados_final.amp_std_global(mask)), ...
                mean(dados_final.fase_media_global(mask)), ...
                mean(dados_final.energia_total(mask)));
    end
end

% Features: correlacao de cada feature com tempo
fprintf('\n--- Correlacao features V2 com tempo ---\n');
feat = dados_final.features;
feat_corr = zeros(1, size(feat, 2));
for f = 1:size(feat, 2)
    if std(feat(:, f)) > 0
        c = corrcoef(t_min, feat(:, f));
        feat_corr(f) = c(1, 2);
    end
end
fprintf('  Features com |corr| > 0.5: %d de %d\n', sum(abs(feat_corr) > 0.5), length(feat_corr));
fprintf('  Features com |corr| > 0.3: %d de %d\n', sum(abs(feat_corr) > 0.3), length(feat_corr));
fprintf('  Corr media: %.3f, max: %.3f\n', mean(abs(feat_corr)), max(abs(feat_corr)));

% Variacao primeira vs ultima hora
if max(t_min) >= 60
    mask_1h = t_min <= 30;
    mask_ult = t_min >= max(t_min) - 30;
    fprintf('\n--- Primeiros 30 min vs ultimos 30 min ---\n');
    fprintf('%-30s %12s %12s %12s\n', 'Metrica', 'Primeiro', 'Ultimo', 'Variacao %');
    for m = 1:length(metricas)
        vals = dados_final.(metricas{m});
        v1 = mean(vals(mask_1h));
        v2 = mean(vals(mask_ult));
        if abs(v1) > 0.01
            var_pct = 100 * (v2 - v1) / abs(v1);
        else
            var_pct = 0;
        end
        fprintf('%-30s %12.2f %12.2f %11.1f%%\n', nomes{m}, v1, v2, var_pct);
    end
end

%% VEREDICTO
fprintf('\n================================================================\n');
fprintf('  VEREDICTO\n');
fprintf('================================================================\n');

n_drift = sum(abs(corr_com_tempo) > 0.3);
n_drift_forte = sum(abs(corr_com_tempo) > 0.5);

if n_drift_forte >= 2
    fprintf('>>> DRIFT TEMPORAL CONFIRMADO\n');
    fprintf('    %d metricas com correlacao forte com tempo (|r| > 0.5)\n', n_drift_forte);
    fprintf('    O canal WiFi muda significativamente ao longo do tempo\n');
    fprintf('    mesmo sem ninguem no ambiente.\n');
elseif n_drift >= 2
    fprintf('>>> DRIFT TEMPORAL MODERADO\n');
    fprintf('    %d metricas com correlacao moderada com tempo (|r| > 0.3)\n', n_drift);
else
    fprintf('>>> SEM DRIFT SIGNIFICATIVO\n');
    fprintf('    Canal WiFi relativamente estavel durante o periodo.\n');
end

%% GRAFICOS
fprintf('\nGerando graficos...\n');

figure('Name', 'Drift Temporal', 'Position', [50 50 1400 900]);

% 1. Amplitude media ao longo do tempo
subplot(3, 3, 1);
plot(t_min, dados_final.amp_media_global, 'b-', 'LineWidth', 0.5);
xlabel('Tempo (min)'); ylabel('Amplitude media');
title(sprintf('Amplitude media (corr=%.3f)', corr_com_tempo(1)));
grid on;

% 2. Amplitude std ao longo do tempo
subplot(3, 3, 2);
plot(t_min, dados_final.amp_std_global, 'r-', 'LineWidth', 0.5);
xlabel('Tempo (min)'); ylabel('Amplitude std');
title(sprintf('Variabilidade (corr=%.3f)', corr_com_tempo(2)));
grid on;

% 3. Fase media
subplot(3, 3, 3);
plot(t_min, dados_final.fase_media_global, 'g-', 'LineWidth', 0.5);
xlabel('Tempo (min)'); ylabel('Fase media (rad)');
title(sprintf('Fase media (corr=%.3f)', corr_com_tempo(3)));
grid on;

% 4. Energia total
subplot(3, 3, 4);
plot(t_min, dados_final.energia_total, 'm-', 'LineWidth', 0.5);
xlabel('Tempo (min)'); ylabel('Energia');
title(sprintf('Energia total (corr=%.3f)', corr_com_tempo(7)));
grid on;

% 5. Variabilidade inter-frame
subplot(3, 3, 5);
plot(t_min, dados_final.var_inter_frame, 'c-', 'LineWidth', 0.5);
xlabel('Tempo (min)'); ylabel('MAD inter-frame');
title(sprintf('Var inter-frame (corr=%.3f)', corr_com_tempo(5)));
grid on;

% 6. Autocorrelacao
subplot(3, 3, 6);
plot(t_min, dados_final.autocorr_media, 'k-', 'LineWidth', 0.5);
xlabel('Tempo (min)'); ylabel('Autocorr lag-1');
title(sprintf('Autocorrelacao (corr=%.3f)', corr_com_tempo(6)));
grid on;

% 7. Heatmap amplitude por subportadora ao longo do tempo
subplot(3, 3, 7);
n_sub_plot = min(64, size(dados_final.amp_media_por_sub, 2));
imagesc(t_min, 1:n_sub_plot, dados_final.amp_media_por_sub(:, 1:n_sub_plot)');
xlabel('Tempo (min)'); ylabel('Subportadora');
title('Amplitude por subportadora');
colorbar; axis xy;

% 8. Heatmap fase por subportadora
subplot(3, 3, 8);
imagesc(t_min, 1:n_sub_plot, dados_final.fase_media_por_sub(:, 1:n_sub_plot)');
xlabel('Tempo (min)'); ylabel('Subportadora');
title('Fase por subportadora');
colorbar; axis xy;

% 9. Correlacao de cada feature com tempo
subplot(3, 3, 9);
bar(abs(feat_corr));
xlabel('Feature'); ylabel('|Corr com tempo|');
title('Correlacao features vs tempo');
yline(0.3, 'r--'); yline(0.5, 'r-', 'LineWidth', 1.5);
grid on;

% Salva figura
saveas(gcf, fullfile('C:\TCC2', 'drift_graficos.fig'));
saveas(gcf, fullfile('C:\TCC2', 'drift_graficos.png'));
fprintf('Graficos salvos em C:\\TCC2\\drift_graficos.png\n');

% Remove stop file
if exist(ARQUIVO_STOP, 'file'), delete(ARQUIVO_STOP); end

fprintf('\n================================================================\n');
fprintf('  MONITORAMENTO CONCLUIDO\n');
fprintf('  Duracao: %.1f horas (%d amostras)\n', tempo_total_min/60, n_amostras_coletadas);
fprintf('================================================================\n');

%% FUNCAO AUXILIAR
function d = cortar_dados(dados, n)
    d.timestamp = dados.timestamp(1:n);
    d.minutos = dados.minutos(1:n);
    d.n_frames = dados.n_frames(1:n);
    d.amp_media_global = dados.amp_media_global(1:n);
    d.amp_std_global = dados.amp_std_global(1:n);
    d.amp_media_por_sub = dados.amp_media_por_sub(1:n, :);
    d.amp_std_temporal = dados.amp_std_temporal(1:n, :);
    d.fase_media_global = dados.fase_media_global(1:n);
    d.fase_std_global = dados.fase_std_global(1:n);
    d.fase_media_por_sub = dados.fase_media_por_sub(1:n, :);
    d.var_inter_frame = dados.var_inter_frame(1:n);
    d.autocorr_media = dados.autocorr_media(1:n);
    d.energia_total = dados.energia_total(1:n);
    d.features = dados.features(1:n, :);
end
