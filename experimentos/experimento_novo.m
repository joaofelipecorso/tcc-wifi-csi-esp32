%% EXPERIMENTO_NOVO - Roda um novo experimento completo
%
% Faz em sequencia sem interrupcao:
%   1. Aquecimento (60s)
%   2. Coleta intercalada (3 rodadas x 45s por classe)
%   3. Treino automatico (seleciona rodadas boas)
%   4. Teste imediato (2 rodadas x 45s por classe)
%
% Salva tudo em C:\TCC2\experimentos\exp_NNN\
% Tempo total: ~12 minutos
%
% Cada experimento eh independente e pode ser combinado depois.

clear; clc; close all;

%% CONFIGURACAO
PORTA = "COM5";
BAUD  = 921600;

N_ROD_COLETA = 3;       % rodadas de coleta
N_ROD_TESTE  = 2;       % rodadas de teste
DUR_CLASSE   = 45;      % segundos por classe
DUR_AMOSTRA  = 3;       % segundos por amostra
ESPERA       = 20;      % segundos transicao

PASTA_EXP = 'C:\TCC2\experimentos';
PASTA_COMUM = 'C:\TCC2\matlab\comum';
addpath(PASTA_COMUM);

if ~exist(PASTA_EXP, 'dir'), mkdir(PASTA_EXP); end

%% determina numero do experimento
pastas = dir(fullfile(PASTA_EXP, 'exp_*'));
nums = [];
for i = 1:length(pastas)
    tok = regexp(pastas(i).name, 'exp_(\d+)', 'tokens');
    if ~isempty(tok), nums(end+1) = str2double(tok{1}{1}); end
end
if isempty(nums), n_exp = 1; else, n_exp = max(nums) + 1; end

pasta_atual = fullfile(PASTA_EXP, sprintf('exp_%03d', n_exp));
pasta_aus = fullfile(pasta_atual, 'ausencia');
pasta_pres = fullfile(pasta_atual, 'presenca');
mkdir(pasta_aus);
mkdir(pasta_pres);

%% estimativas
tempo_est = (60 + N_ROD_COLETA*(DUR_CLASSE*2+ESPERA*2) + 30 + N_ROD_TESTE*(DUR_CLASSE*2+ESPERA*2)) / 60;

fprintf('================================================================\n');
fprintf('  EXPERIMENTO #%d\n', n_exp);
fprintf('================================================================\n');
fprintf('Pasta: %s\n', pasta_atual);
fprintf('Tempo estimado: ~%.0f minutos\n', tempo_est);
fprintf('  Aquecimento: 60s\n');
fprintf('  Coleta: %d rodadas x %ds\n', N_ROD_COLETA, DUR_CLASSE);
fprintf('  Teste: %d rodadas x %ds\n\n', N_ROD_TESTE, DUR_CLASSE);
fprintf('NAO mexa no celular/WiFi durante todo o processo!\n');
fprintf('Pressione ENTER para comecar...\n');
input('');

%% serial
fprintf('Abrindo serial...\n');
delete(serialportfind);
s = serialport(PORTA, BAUD, "Timeout", 3);
pause(12); flush(s);
t0 = tic; buf = uint8([]);
while toc(t0) < 2
    if s.NumBytesAvailable > 0, b = read(s, s.NumBytesAvailable, "uint8"); buf = [buf; b(:)]; end
    pause(0.05);
end
[~, nt] = ler_csi_buffer(buf);
fprintf('Taxa CSI: %.0f/s\n\n', nt/2);
if nt < 10, fprintf('ERRO: sem dados.\n'); delete(s); return; end

%% AQUECIMENTO
fprintf('--- AQUECIMENTO (60s) ---\n');
fprintf('Fique DENTRO do quarto.\n');
for t = 60:-1:1
    if mod(t,10)==0, fprintf('  %d...\n', t); end
    if s.NumBytesAvailable > 0, read(s, s.NumBytesAvailable, "uint8"); end
    pause(1);
end
flush(s);
fprintf('Aquecimento OK.\n\n');

%% COLETA
fprintf('================================================================\n');
fprintf('  COLETA (%d rodadas)\n', N_ROD_COLETA);
fprintf('================================================================\n');

n_aus = 0; n_pres = 0;
for rodada = 1:N_ROD_COLETA
    fprintf('\n--- Rodada %d/%d ---\n', rodada, N_ROD_COLETA);

    % ausencia
    fprintf('SAIA do quarto!\n');
    for t = ESPERA:-1:1, fprintf('  %d\n', t); pause(1); end
    fprintf('Coletando AUSENCIA %ds...\n', DUR_CLASSE);
    flush(s); tc = tic;
    while toc(tc) < DUR_CLASSE
        flush(s); pause(0.1);
        t0 = tic; buf = uint8([]);
        while toc(t0) < DUR_AMOSTRA
            if s.NumBytesAvailable > 0, b = read(s, s.NumBytesAvailable, "uint8"); buf = [buf; b(:)]; end
            pause(0.05);
        end
        [amp, n] = ler_csi_buffer(buf);
        if n < 50, continue; end
        n_aus = n_aus + 1;
        dados.amplitudes = amp;
        dados.info.timestamp = datetime('now');
        dados.info.n_frames = n;
        dados.info.rodada = rodada;
        dados.info.classe = 'ausencia';
        dados.info.experimento = n_exp;
        save(fullfile(pasta_aus, sprintf('aus_r%d_%03d.mat', rodada, n_aus)), '-struct', 'dados');
        fprintf('  aus %d: %d fr\n', n_aus, n);
    end

    % presenca
    fprintf('VOLTE ao quarto, fique PARADO!\n');
    for t = ESPERA:-1:1, fprintf('  %d\n', t); pause(1); end
    fprintf('Coletando PRESENCA %ds...\n', DUR_CLASSE);
    flush(s); tc = tic;
    while toc(tc) < DUR_CLASSE
        flush(s); pause(0.1);
        t0 = tic; buf = uint8([]);
        while toc(t0) < DUR_AMOSTRA
            if s.NumBytesAvailable > 0, b = read(s, s.NumBytesAvailable, "uint8"); buf = [buf; b(:)]; end
            pause(0.05);
        end
        [amp, n] = ler_csi_buffer(buf);
        if n < 50, continue; end
        n_pres = n_pres + 1;
        dados.amplitudes = amp;
        dados.info.timestamp = datetime('now');
        dados.info.n_frames = n;
        dados.info.rodada = rodada;
        dados.info.classe = 'presenca';
        dados.info.experimento = n_exp;
        save(fullfile(pasta_pres, sprintf('pres_r%d_%03d.mat', rodada, n_pres)), '-struct', 'dados');
        fprintf('  pres %d: %d fr\n', n_pres, n);
    end
end
fprintf('\nColeta: %d aus + %d pres\n\n', n_aus, n_pres);

%% TREINO
fprintf('================================================================\n');
fprintf('  TREINO\n');
fprintf('================================================================\n');

arq_a = dir(fullfile(pasta_aus, '*.mat'));
arq_p = dir(fullfile(pasta_pres, '*.mat'));
nf = length(extrair_features_v2(rand(100,64)));
nt_total = length(arq_a) + length(arq_p);
X = zeros(nt_total, nf); y = zeros(nt_total, 1); rods = zeros(nt_total, 1);
idx = 0;
for i = 1:length(arq_a)
    idx = idx+1; d = load(fullfile(arq_a(i).folder, arq_a(i).name));
    X(idx,:) = extrair_features_v2(d.amplitudes); y(idx) = 0; rods(idx) = d.info.rodada;
end
for i = 1:length(arq_p)
    idx = idx+1; d = load(fullfile(arq_p(i).folder, arq_p(i).name));
    X(idx,:) = extrair_features_v2(d.amplitudes); y(idx) = 1; rods(idx) = d.info.rodada;
end

% LORO
rods_u = unique(rods);
acc_loro = zeros(length(rods_u), 1);
for ri = 1:length(rods_u)
    r = rods_u(ri);
    ite = rods==r; itr = rods~=r;
    if sum(ite)<5, continue; end
    rf = TreeBagger(50, X(itr,:), y(itr), 'Method', 'classification', 'MinLeafSize', 5, 'MaxNumSplits', 20);
    acc_loro(ri) = mean(str2double(predict(rf, X(ite,:))) == y(ite));
    fprintf('  Rodada %d LORO: %.1f%%\n', r, 100*acc_loro(ri));
end

rods_boas = rods_u(acc_loro >= 0.70);
if isempty(rods_boas), rods_boas = rods_u; fprintf('  Nenhuma >= 70%%, usando todas.\n'); end
fprintf('Rodadas usadas: [%s]\n', strjoin(string(rods_boas), ','));

ib = ismember(rods, rods_boas);
Xb = X(ib,:); yb = y(ib);
modelo = TreeBagger(50, Xb, yb, 'Method', 'classification', 'MinLeafSize', 5, 'MaxNumSplits', 20);

rng(42);
cv = cvpartition(yb, 'KFold', min(5, length(yb)));
accs = zeros(cv.NumTestSets, 1);
for f = 1:cv.NumTestSets
    rf_cv = TreeBagger(50, Xb(training(cv,f),:), yb(training(cv,f)), 'Method', 'classification', 'MinLeafSize', 5, 'MaxNumSplits', 20);
    accs(f) = mean(str2double(predict(rf_cv, Xb(test(cv,f),:))) == yb(test(cv,f)));
end
acc_cv = mean(accs);
fprintf('K-fold: %.1f%%\n\n', 100*acc_cv);

info_modelo.tipo = 'rf50';
info_modelo.acuracia_cv = acc_cv;
info_modelo.acuracia_loro = mean(acc_loro(acc_loro>0));
info_modelo.n_amostras = sum(ib);
info_modelo.n_aus = sum(yb==0);
info_modelo.n_pres = sum(yb==1);
info_modelo.n_features = nf;
info_modelo.precisa_normalizar = false;
info_modelo.feature_fn = 'extrair_features_v2';
info_modelo.rodadas_usadas = rods_boas;
info_modelo.mu = mean(Xb); info_modelo.sigma = std(Xb);
info_modelo.timestamp = datetime('now');
info_modelo.experimento = n_exp;

save(fullfile(pasta_atual, 'modelo.mat'), 'modelo', 'info_modelo', '-v7.3');

%% TESTE IMEDIATO
fprintf('================================================================\n');
fprintf('  TESTE IMEDIATO (%d rodadas)\n', N_ROD_TESTE);
fprintf('================================================================\n');

% pastas para salvar CSI do teste (reutilizavel como dataset)
pasta_teste_aus = fullfile(pasta_atual, 'teste_ausencia');
pasta_teste_pres = fullfile(pasta_atual, 'teste_presenca');
if ~exist(pasta_teste_aus, 'dir'), mkdir(pasta_teste_aus); end
if ~exist(pasta_teste_pres, 'dir'), mkdir(pasta_teste_pres); end
n_teste_aus = 0; n_teste_pres = 0;

max_am = 300;
rot = zeros(max_am,1); prd = zeros(max_am,1);
prb = zeros(max_am,1); rod_t = zeros(max_am,1); nfr = zeros(max_am,1); ig = 0;

for rodada = 1:N_ROD_TESTE
    fprintf('\n--- Teste %d/%d ---\n', rodada, N_ROD_TESTE);

    fprintf('SAIA do quarto!\n');
    for t = ESPERA:-1:1, fprintf('  %d\n', t); pause(1); end
    fprintf('Testando AUSENCIA %ds...\n', DUR_CLASSE);
    flush(s); tc = tic; na = 0;
    while toc(tc) < DUR_CLASSE
        flush(s); pause(0.1);
        t0 = tic; buf = uint8([]);
        while toc(t0) < DUR_AMOSTRA
            if s.NumBytesAvailable > 0, b = read(s, s.NumBytesAvailable, "uint8"); buf = [buf; b(:)]; end
            pause(0.05);
        end
        [amp, n] = ler_csi_buffer(buf); if n < 20, continue; end
        feat = extrair_features_v2(amp);
        [~, sc] = predict(modelo, feat); prob = sc(2); pr = double(prob >= 0.5);
        ig = ig+1; na = na+1;
        rot(ig)=0; prd(ig)=pr; prb(ig)=prob; rod_t(ig)=rodada; nfr(ig)=n;
        n_teste_aus = n_teste_aus + 1;
        dados_t.amplitudes = amp; dados_t.info.timestamp = datetime('now');
        dados_t.info.n_frames = n; dados_t.info.rodada = rodada;
        dados_t.info.classe = 'ausencia'; dados_t.info.experimento = n_exp;
        dados_t.info.origem = 'teste';
        save(fullfile(pasta_teste_aus, sprintf('taus_r%d_%03d.mat', rodada, n_teste_aus)), '-struct', 'dados_t');
        if pr==0, m='OK'; pl='AUS'; else, m='ERRO'; pl='PRES'; end
        fprintf('  %d: %3d fr | p=%.2f -> %s %s\n', na, n, prob, pl, m);
    end

    fprintf('VOLTE ao quarto, fique PARADO!\n');
    for t = ESPERA:-1:1, fprintf('  %d\n', t); pause(1); end
    fprintf('Testando PRESENCA %ds...\n', DUR_CLASSE);
    flush(s); tc = tic; np = 0;
    while toc(tc) < DUR_CLASSE
        flush(s); pause(0.1);
        t0 = tic; buf = uint8([]);
        while toc(t0) < DUR_AMOSTRA
            if s.NumBytesAvailable > 0, b = read(s, s.NumBytesAvailable, "uint8"); buf = [buf; b(:)]; end
            pause(0.05);
        end
        [amp, n] = ler_csi_buffer(buf); if n < 20, continue; end
        feat = extrair_features_v2(amp);
        [~, sc] = predict(modelo, feat); prob = sc(2); pr = double(prob >= 0.5);
        ig = ig+1; np = np+1;
        rot(ig)=1; prd(ig)=pr; prb(ig)=prob; rod_t(ig)=rodada; nfr(ig)=n;
        n_teste_pres = n_teste_pres + 1;
        dados_t.amplitudes = amp; dados_t.info.timestamp = datetime('now');
        dados_t.info.n_frames = n; dados_t.info.rodada = rodada;
        dados_t.info.classe = 'presenca'; dados_t.info.experimento = n_exp;
        dados_t.info.origem = 'teste';
        save(fullfile(pasta_teste_pres, sprintf('tpres_r%d_%03d.mat', rodada, n_teste_pres)), '-struct', 'dados_t');
        if pr==1, m='OK'; pl='PRES'; else, m='ERRO'; pl='AUS'; end
        fprintf('  %d: %3d fr | p=%.2f -> %s %s\n', np, n, prob, pl, m);
    end
end
delete(s);

rot = rot(1:ig); prd = prd(1:ig); prb = prb(1:ig); rod_t = rod_t(1:ig); nfr = nfr(1:ig);

%% resultados
acc = mean(prd == rot);
TP = sum(prd==1 & rot==1); TN = sum(prd==0 & rot==0);
FP = sum(prd==1 & rot==0); FN = sum(prd==0 & rot==1);
prec_p = TP/max(TP+FP,1); rec_p = TP/max(TP+FN,1);
f1_p = 2*prec_p*rec_p/max(prec_p+rec_p,0.001);
prec_a = TN/max(TN+FN,1); rec_a = TN/max(TN+FP,1);
f1_a = 2*prec_a*rec_a/max(prec_a+rec_a,0.001);

fprintf('\n================================================================\n');
fprintf('  RESULTADO EXPERIMENTO #%d\n', n_exp);
fprintf('================================================================\n');
fprintf('Acuracia: %.1f%% (%d/%d)\n', 100*acc, sum(prd==rot), ig);
fprintf('  TN=%d FP=%d FN=%d TP=%d\n', TN, FP, FN, TP);
fprintf('  Presenca: prec=%.2f rec=%.2f F1=%.2f\n', prec_p, rec_p, f1_p);
fprintf('  Ausencia: prec=%.2f rec=%.2f F1=%.2f\n', prec_a, rec_a, f1_a);
for r = 1:N_ROD_TESTE
    ia = rod_t==r & rot==0; ip = rod_t==r & rot==1;
    fprintf('  R%d: Aus=%.0f%% Pres=%.0f%%\n', r, 100*mean(prd(ia)==0), 100*mean(prd(ip)==1));
end

resultado.acuracia = acc;
resultado.precisao_presenca = prec_p; resultado.recall_presenca = rec_p; resultado.f1_presenca = f1_p;
resultado.precisao_ausencia = prec_a; resultado.recall_ausencia = rec_a; resultado.f1_ausencia = f1_a;
resultado.matriz = [TN FP; FN TP];
resultado.n_total = ig;
resultado.rotulos = rot; resultado.predicoes = prd; resultado.probabilidades = prb;
resultado.rodada = rod_t;
resultado.n_frames = nfr;
resultado.timestamp = datetime('now');

% info do experimento
info_exp.numero = n_exp;
info_exp.timestamp_inicio = datetime('now');
info_exp.n_aus_coleta = n_aus;
info_exp.n_pres_coleta = n_pres;
info_exp.acuracia_teste = acc;
info_exp.excluido = false;
info_exp.notas = '';

save(fullfile(pasta_atual, 'resultado_teste.mat'), 'resultado');
save(fullfile(pasta_atual, 'info_exp.mat'), 'info_exp');

fprintf('\nSalvo em: %s\n', pasta_atual);
fprintf('================================================================\n');
