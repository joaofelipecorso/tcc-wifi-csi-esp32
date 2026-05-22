%% EXPERIMENTO_TESTAR - Teste em tempo real
%
% Opcoes:
%   - Testar com modelo de UM experimento especifico
%   - Testar com modelo COMBINADO de todos os ativos
%
% Teste: 2 rodadas x 45s ausencia + 45s presenca
% Gera resultados completos para TCC

clear; clc; close all;

PORTA = "COM5";
BAUD  = 921600;
N_ROD = 2;
DUR   = 45;
ESPERA = 20;
DUR_AM = 3;

PASTA_EXP = 'C:\TCC2\experimentos';
PASTA_COMUM = 'C:\TCC2\matlab\comum';
addpath(PASTA_COMUM);

fprintf('================================================================\n');
fprintf('  TESTE EM TEMPO REAL\n');
fprintf('================================================================\n\n');

%% lista experimentos disponiveis
pastas = dir(fullfile(PASTA_EXP, 'exp_*'));
exps = [];
for i = 1:length(pastas)
    arq = fullfile(PASTA_EXP, pastas(i).name, 'info_exp.mat');
    if ~exist(arq, 'file'), continue; end
    d = load(arq);
    e.nome = pastas(i).name;
    e.pasta = fullfile(PASTA_EXP, pastas(i).name);
    e.numero = d.info_exp.numero;
    e.excluido = d.info_exp.excluido;
    e.n_aus = d.info_exp.n_aus_coleta;
    e.n_pres = d.info_exp.n_pres_coleta;
    e.acuracia = d.info_exp.acuracia_teste;
    exps = [exps, e];
end

if isempty(exps)
    fprintf('Nenhum experimento encontrado.\n');
    return;
end

% mostra
fprintf('Experimentos disponiveis:\n');
ativos = [];
for i = 1:length(exps)
    if exps(i).excluido, st = '[EXCL]'; else, st = ''; ativos = [ativos, i]; end
    fprintf('  %d - exp_%03d (%d aus + %d pres) acc=%.1f%% %s\n', ...
            exps(i).numero, exps(i).numero, exps(i).n_aus, exps(i).n_pres, ...
            100*exps(i).acuracia, st);
end

fprintf('\n  0 - TODOS os ativos combinados (%d experimentos)\n\n', length(ativos));
escolha = input('Qual experimento usar (numero, ou 0 para todos): ');

%% carrega/treina modelo
if escolha == 0
    % COMBINA TODOS OS ATIVOS
    fprintf('\nIncluir amostras de teste no dataset? (s/n): ');
    inc_teste = input('', 's');
    usar_teste = strcmpi(inc_teste, 's');
    
    fprintf('Combinando %d experimentos ativos...\n', length(ativos));
    X = []; y = [];
    for ai = 1:length(ativos)
        e = exps(ativos(ai));
        arq_a = dir(fullfile(e.pasta, 'ausencia', '*.mat'));
        arq_p = dir(fullfile(e.pasta, 'presenca', '*.mat'));
        if usar_teste
            arq_ta = dir(fullfile(e.pasta, 'teste_ausencia', '*.mat'));
            arq_tp = dir(fullfile(e.pasta, 'teste_presenca', '*.mat'));
            arq_a = [arq_a; arq_ta];
            arq_p = [arq_p; arq_tp];
        end
        for j = 1:length(arq_a)
            d = load(fullfile(arq_a(j).folder, arq_a(j).name));
            X = [X; extrair_features_v2(d.amplitudes)];
            y = [y; 0];
        end
        for j = 1:length(arq_p)
            d = load(fullfile(arq_p(j).folder, arq_p(j).name));
            X = [X; extrair_features_v2(d.amplitudes)];
            y = [y; 1];
        end
    end
    fprintf('Dataset combinado: %d amostras (%d aus + %d pres)\n', length(y), sum(y==0), sum(y==1));

    modelo = TreeBagger(50, X, y, 'Method', 'classification', 'MinLeafSize', 5, 'MaxNumSplits', 20);
    
    rng(42);
    cv = cvpartition(y, 'KFold', min(5, length(y)));
    accs = zeros(cv.NumTestSets, 1);
    for f = 1:cv.NumTestSets
        rf = TreeBagger(50, X(training(cv,f),:), y(training(cv,f)), 'Method', 'classification', 'MinLeafSize', 5, 'MaxNumSplits', 20);
        accs(f) = mean(str2double(predict(rf, X(test(cv,f),:))) == y(test(cv,f)));
    end
    fprintf('K-fold combinado: %.1f%%\n', 100*mean(accs));
    
    nome_teste = 'TODOS_COMBINADOS';
    if usar_teste, nome_teste = 'TODOS_COMBINADOS_COM_TESTE'; end
    info_modelo.precisa_normalizar = false;
    info_modelo.tipo = 'combinado';
    info_modelo.acuracia_cv = mean(accs);
else
    % UM EXPERIMENTO ESPECIFICO
    idx = find([exps.numero] == escolha);
    if isempty(idx)
        fprintf('Experimento %d nao encontrado.\n', escolha);
        return;
    end
    e = exps(idx);
    arq_mdl = fullfile(e.pasta, 'modelo.mat');
    if ~exist(arq_mdl, 'file')
        fprintf('Modelo nao encontrado para experimento %d.\n', escolha);
        return;
    end
    d = load(arq_mdl);
    modelo = d.modelo;
    info_modelo = d.info_modelo;
    nome_teste = sprintf('EXP_%03d', escolha);
    fprintf('\nUsando modelo do experimento %d (K-fold: %.1f%%)\n', escolha, 100*info_modelo.acuracia_cv);
end

%% serial
fprintf('\nAbrindo serial...\n');
delete(serialportfind);
s = serialport(PORTA, BAUD, "Timeout", 3);
pause(12); flush(s);

% testa se ESP32 esta vivo
t0 = tic; buf = uint8([]);
while toc(t0) < 2
    if s.NumBytesAvailable > 0, b = read(s, s.NumBytesAvailable, "uint8"); buf = [buf; b(:)]; end
    pause(0.05);
end
[~, nt] = ler_csi_buffer(buf);
fprintf('Taxa CSI: %.0f/s\n', nt/2);
if nt < 10
    fprintf('ERRO: ESP32 sem dados. Resete (tire/ponha USB) e tente novamente.\n');
    delete(s); return;
end
fprintf('Pronto.\n\n');

%% CALIBRACAO
fprintf('Fazer calibracao do ambiente? (s/n): ');
resp_cal = input('', 's');
usar_calibracao = strcmpi(resp_cal, 's');

threshold_padrao = 0.5;
threshold_cal = 0.5;

if usar_calibracao
    fprintf('\n================================================================\n');
    fprintf('  CALIBRACAO - QUARTO VAZIO\n');
    fprintf('================================================================\n');
    fprintf('SAIA do quarto, feche a porta. Quarto deve estar VAZIO.\n');
    for t = 20:-1:1, fprintf('  %d\n', t); pause(1); end
    fprintf('Calibrando (30s)...\n');
    flush(s);

    cal_probs = [];
    tc = tic;
    while toc(tc) < 30
        flush(s); pause(0.1);
        t0 = tic; buf = uint8([]);
        while toc(t0) < DUR_AM
            if s.NumBytesAvailable > 0, b = read(s, s.NumBytesAvailable, "uint8"); buf = [buf; b(:)]; end
            pause(0.05);
        end
        [amp, n] = ler_csi_buffer(buf); if n < 20, continue; end
        feat = extrair_features_v2(amp);
        [~, sc] = predict(modelo, feat); prob_cal = sc(2);
        cal_probs(end+1) = prob_cal;
        fprintf('  cal: %3d fr | prob_vazio=%.2f\n', n, prob_cal);
    end

    if ~isempty(cal_probs)
        cal_media = mean(cal_probs);
        cal_std = std(cal_probs);
        threshold_cal = cal_media + 2 * cal_std;
        threshold_cal = max(threshold_cal, 0.3);  % minimo 0.3
        threshold_cal = min(threshold_cal, 0.8);  % maximo 0.8
        fprintf('\nCalibração concluida:\n');
        fprintf('  Prob vazio media: %.3f (std=%.3f)\n', cal_media, cal_std);
        fprintf('  Threshold calibrado: %.3f (vs padrao 0.500)\n', threshold_cal);
    else
        fprintf('Falha na calibracao - usando threshold padrao.\n');
        usar_calibracao = false;
    end
end

fprintf('\nPressione ENTER para iniciar teste...\n');
input('');

%% TESTE
max_am = 300;
rot = zeros(max_am,1);
prd = zeros(max_am,1); prd_cal = zeros(max_am,1);  % com e sem calibracao
prb = zeros(max_am,1);
rod = zeros(max_am,1); nfr = zeros(max_am,1);
ig = 0; t_ini = tic;

for rodada = 1:N_ROD
    fprintf('\n--- Teste rodada %d/%d ---\n', rodada, N_ROD);

    fprintf('SAIA do quarto!\n');
    for t = ESPERA:-1:1, fprintf('  %d\n', t); pause(1); end
    fprintf('Testando AUSENCIA %ds...\n', DUR);
    flush(s); tc = tic; na = 0;
    while toc(tc) < DUR
        flush(s); pause(0.1);
        t0 = tic; buf = uint8([]);
        while toc(t0) < DUR_AM
            if s.NumBytesAvailable > 0, b = read(s, s.NumBytesAvailable, "uint8"); buf = [buf; b(:)]; end
            pause(0.05);
        end
        [amp, n] = ler_csi_buffer(buf); if n < 20, continue; end
        feat = extrair_features_v2(amp);
        [~, sc] = predict(modelo, feat); prob = sc(2);
        pr = double(prob >= threshold_padrao);
        pr_cal = double(prob >= threshold_cal);
        ig = ig+1; na = na+1;
        rot(ig)=0; prd(ig)=pr; prd_cal(ig)=pr_cal; prb(ig)=prob; rod(ig)=rodada; nfr(ig)=n;
        % mostra ambos
        if pr==0, r1='AUS'; else, r1='PRES'; end
        if pr_cal==0, r2='AUS'; else, r2='PRES'; end
        if pr==0, m1='OK'; else, m1='ERRO'; end
        if pr_cal==0, m2='OK'; else, m2='ERRO'; end
        if usar_calibracao
            fprintf('  %d: %3d fr | p=%.2f | sem_cal:%s(%s) | com_cal:%s(%s)\n', na, n, prob, r1, m1, r2, m2);
        else
            fprintf('  %d: %3d fr | p=%.2f -> %s %s\n', na, n, prob, r1, m1);
        end
    end

    fprintf('VOLTE ao quarto, fique PARADO!\n');
    for t = ESPERA:-1:1, fprintf('  %d\n', t); pause(1); end
    fprintf('Testando PRESENCA %ds...\n', DUR);
    flush(s); tc = tic; np = 0;
    while toc(tc) < DUR
        flush(s); pause(0.1);
        t0 = tic; buf = uint8([]);
        while toc(t0) < DUR_AM
            if s.NumBytesAvailable > 0, b = read(s, s.NumBytesAvailable, "uint8"); buf = [buf; b(:)]; end
            pause(0.05);
        end
        [amp, n] = ler_csi_buffer(buf); if n < 20, continue; end
        feat = extrair_features_v2(amp);
        [~, sc] = predict(modelo, feat); prob = sc(2);
        pr = double(prob >= threshold_padrao);
        pr_cal = double(prob >= threshold_cal);
        ig = ig+1; np = np+1;
        rot(ig)=1; prd(ig)=pr; prd_cal(ig)=pr_cal; prb(ig)=prob; rod(ig)=rodada; nfr(ig)=n;
        if pr==1, r1='PRES'; else, r1='AUS'; end
        if pr_cal==1, r2='PRES'; else, r2='AUS'; end
        if pr==1, m1='OK'; else, m1='ERRO'; end
        if pr_cal==1, m2='OK'; else, m2='ERRO'; end
        if usar_calibracao
            fprintf('  %d: %3d fr | p=%.2f | sem_cal:%s(%s) | com_cal:%s(%s)\n', np, n, prob, r1, m1, r2, m2);
        else
            fprintf('  %d: %3d fr | p=%.2f -> %s %s\n', np, n, prob, r1, m1);
        end
    end
end
delete(s);
tempo = toc(t_ini);

rot = rot(1:ig); prd = prd(1:ig); prd_cal = prd_cal(1:ig); prb = prb(1:ig); rod = rod(1:ig); nfr = nfr(1:ig);

%% RESULTADOS SEM CALIBRACAO
acc = mean(prd == rot);
TP = sum(prd==1&rot==1); TN = sum(prd==0&rot==0);
FP = sum(prd==1&rot==0); FN = sum(prd==0&rot==1);
prec_p = TP/max(TP+FP,1); rec_p = TP/max(TP+FN,1);
f1_p = 2*prec_p*rec_p/max(prec_p+rec_p,0.001);
prec_a = TN/max(TN+FN,1); rec_a = TN/max(TN+FP,1);
f1_a = 2*prec_a*rec_a/max(prec_a+rec_a,0.001);

fprintf('\n================================================================\n');
fprintf('  RESULTADO SEM CALIBRACAO (threshold=%.2f)\n', threshold_padrao);
fprintf('================================================================\n');
fprintf('Tempo: %.1f min | Amostras: %d (%d aus + %d pres)\n', tempo/60, ig, sum(rot==0), sum(rot==1));
fprintf('ACURACIA: %.1f%% (%d/%d)\n', 100*acc, sum(prd==rot), ig);
fprintf('  TN=%d FP=%d FN=%d TP=%d\n', TN, FP, FN, TP);
fprintf('  Presenca: prec=%.2f rec=%.2f F1=%.2f\n', prec_p, rec_p, f1_p);
fprintf('  Ausencia: prec=%.2f rec=%.2f F1=%.2f\n', prec_a, rec_a, f1_a);
for r = 1:N_ROD
    ia = rod==r&rot==0; ip = rod==r&rot==1;
    if sum(ia)>0, fprintf('  R%d Aus: %.1f%%\n', r, 100*mean(prd(ia)==0)); end
    if sum(ip)>0, fprintf('  R%d Pres: %.1f%%\n', r, 100*mean(prd(ip)==1)); end
end

%% RESULTADOS COM CALIBRACAO
if usar_calibracao
    acc_cal = mean(prd_cal == rot);
    TP_c = sum(prd_cal==1&rot==1); TN_c = sum(prd_cal==0&rot==0);
    FP_c = sum(prd_cal==1&rot==0); FN_c = sum(prd_cal==0&rot==1);
    prec_pc = TP_c/max(TP_c+FP_c,1); rec_pc = TP_c/max(TP_c+FN_c,1);
    f1_pc = 2*prec_pc*rec_pc/max(prec_pc+rec_pc,0.001);
    prec_ac = TN_c/max(TN_c+FN_c,1); rec_ac = TN_c/max(TN_c+FP_c,1);
    f1_ac = 2*prec_ac*rec_ac/max(prec_ac+rec_ac,0.001);

    fprintf('\n================================================================\n');
    fprintf('  RESULTADO COM CALIBRACAO (threshold=%.3f)\n', threshold_cal);
    fprintf('================================================================\n');
    fprintf('ACURACIA: %.1f%% (%d/%d)\n', 100*acc_cal, sum(prd_cal==rot), ig);
    fprintf('  TN=%d FP=%d FN=%d TP=%d\n', TN_c, FP_c, FN_c, TP_c);
    fprintf('  Presenca: prec=%.2f rec=%.2f F1=%.2f\n', prec_pc, rec_pc, f1_pc);
    fprintf('  Ausencia: prec=%.2f rec=%.2f F1=%.2f\n', prec_ac, rec_ac, f1_ac);
    for r = 1:N_ROD
        ia = rod==r&rot==0; ip = rod==r&rot==1;
        if sum(ia)>0, fprintf('  R%d Aus: %.1f%%\n', r, 100*mean(prd_cal(ia)==0)); end
        if sum(ip)>0, fprintf('  R%d Pres: %.1f%%\n', r, 100*mean(prd_cal(ip)==1)); end
    end

    fprintf('\n================================================================\n');
    fprintf('  COMPARACAO\n');
    fprintf('================================================================\n');
    fprintf('  %-20s %12s %12s\n', '', 'Sem cal', 'Com cal');
    fprintf('  %-20s %11.1f%% %11.1f%%\n', 'Acuracia', 100*acc, 100*acc_cal);
    fprintf('  %-20s %11.1f%% %11.1f%%\n', 'Aus recall', 100*rec_a, 100*rec_ac);
    fprintf('  %-20s %11.1f%% %11.1f%%\n', 'Pres recall', 100*rec_p, 100*rec_pc);
    fprintf('  %-20s %12.2f %12.2f\n', 'F1 Ausencia', f1_a, f1_ac);
    fprintf('  %-20s %12.2f %12.2f\n', 'F1 Presenca', f1_p, f1_pc);
    fprintf('  %-20s %12.3f %12.3f\n', 'Threshold', threshold_padrao, threshold_cal);

    diff = acc_cal - acc;
    if diff > 0.05
        fprintf('\n  >>> Calibracao MELHOROU em %.1f pontos!\n', 100*diff);
    elseif diff < -0.05
        fprintf('\n  >>> Calibracao PIOROU em %.1f pontos.\n', -100*diff);
    else
        fprintf('\n  >>> Diferenca pequena (%.1f pontos).\n', 100*diff);
    end
end

% salva
resultado.teste_nome = nome_teste;
resultado.acuracia = acc;
resultado.precisao_presenca = prec_p; resultado.recall_presenca = rec_p; resultado.f1_presenca = f1_p;
resultado.precisao_ausencia = prec_a; resultado.recall_ausencia = rec_a; resultado.f1_ausencia = f1_a;
resultado.matriz = [TN FP; FN TP];
resultado.n_total = ig; resultado.rotulos = rot;
resultado.predicoes_sem_cal = prd;
resultado.predicoes_com_cal = prd_cal;
resultado.probabilidades = prb; resultado.rodada = rod; resultado.n_frames = nfr;
resultado.tempo_seg = tempo; resultado.timestamp = datetime('now');
resultado.threshold_padrao = threshold_padrao;
resultado.threshold_calibrado = threshold_cal;
resultado.calibracao_usada = usar_calibracao;
if usar_calibracao
    resultado.calibracao_probs = cal_probs;
    resultado.calibracao_media = cal_media;
    resultado.calibracao_std = cal_std;
    resultado.acuracia_com_cal = acc_cal;
end

nome_arq = sprintf('resultado_teste_%s_%s.mat', nome_teste, datestr(now, 'yyyymmdd_HHMMSS'));
save(fullfile(PASTA_EXP, nome_arq), 'resultado');
fprintf('\nSalvo em: %s\n', nome_arq);

%% grafico
figure('Name', sprintf('Teste %s', nome_teste), 'Position', [50 50 1100 700]);

if usar_calibracao
    subplot(2,2,1);
    bar([TN FP; FN TP]);
    set(gca, 'XTickLabel', {'Real:Aus', 'Real:Pres'});
    legend('Pred:Aus', 'Pred:Pres', 'Location', 'best');
    title(sprintf('SEM calibracao: %.1f%%', 100*acc));
    grid on;

    subplot(2,2,2);
    bar([TN_c FP_c; FN_c TP_c]);
    set(gca, 'XTickLabel', {'Real:Aus', 'Real:Pres'});
    legend('Pred:Aus', 'Pred:Pres', 'Location', 'best');
    title(sprintf('COM calibracao: %.1f%% (thr=%.3f)', 100*acc_cal, threshold_cal));
    grid on;

    subplot(2,1,2);
else
    subplot(2,1,1);
    bar([TN FP; FN TP]);
    set(gca, 'XTickLabel', {'Real:Aus', 'Real:Pres'});
    legend('Pred:Aus', 'Pred:Pres', 'Location', 'best');
    title(sprintf('[%s] Acuracia: %.1f%%', nome_teste, 100*acc));
    grid on;

    subplot(2,1,2);
end

hold on;
for i = 1:ig
    if rot(i)==0, cor=[0.2 0.6 0.2]; else, cor=[0.8 0.2 0.2]; end
    bar(i, prb(i), 'FaceColor', cor, 'EdgeColor', 'none');
end
yline(threshold_padrao, 'k--', 'LineWidth', 1.5);
if usar_calibracao
    yline(threshold_cal, 'b--', 'LineWidth', 1.5);
    legend('', '', 'Threshold 0.5', sprintf('Threshold cal %.3f', threshold_cal));
end
xlabel('Amostra'); ylabel('Prob Presenca');
title('Probabilidades (verde=aus, vermelho=pres)');
ylim([0 1.05]); grid on;
