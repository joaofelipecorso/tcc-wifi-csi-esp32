%% VALIDAR_WIMANS - Valida abordagem RF no dataset WiMANS
%
% Carrega dataset WiMANS convertido, aplica mesma abordagem de ML
% (Random Forest + features normalizadas), treina e testa.
%
% Gera resultados completos: acuracia, matriz de confusao, F1,
% analise por ambiente, analise por numero de usuarios.
%
% PRE-REQUISITO: rodar preparar_wimans.py antes (converte .npy para .mat)

clear; clc; close all;

%% CONFIGURACAO
PASTA_WIMANS = 'C:\TCC2\wimans';
ARQUIVO_MAT = fullfile(PASTA_WIMANS, 'wimans_2.4GHz.mat');

fprintf('================================================================\n');
fprintf('  VALIDACAO COM DATASET WIMANS\n');
fprintf('================================================================\n\n');

if ~exist(ARQUIVO_MAT, 'file')
    error(['Arquivo nao encontrado: %s\n' ...
           'Rode preparar_wimans.py primeiro para converter o dataset.'], ARQUIVO_MAT);
end

%% CARREGA DATASET
fprintf('Carregando dataset WiMANS...\n');
data = load(ARQUIVO_MAT);

amplitudes = data.amplitudes;      % (N, 300, 30)
labels = double(data.labels(:));   % (N,) 0=aus, 1=pres
environments = double(data.environments(:));  % 1=classroom, 2=meeting, 3=empty
num_users = double(data.num_users(:));

n_amostras = size(amplitudes, 1);
n_frames = size(amplitudes, 2);
n_subs = size(amplitudes, 3);

n_aus = sum(labels == 0);
n_pres = sum(labels == 1);

fprintf('  Amostras: %d (%d ausencia + %d presenca)\n', n_amostras, n_aus, n_pres);
fprintf('  Frames por amostra: %d\n', n_frames);
fprintf('  Subportadoras: %d\n', n_subs);
fprintf('  Ambientes: classroom(%d), meeting(%d), empty(%d)\n', ...
        sum(environments==1), sum(environments==2), sum(environments==3));
fprintf('  Usuarios: ');
for u = 0:5
    fprintf('%d(%d) ', u, sum(num_users==u));
end
fprintf('\n\n');

%% EXTRAI FEATURES
fprintf('Extraindo features (pode demorar alguns minutos)...\n');

% Teste com primeira amostra para saber tamanho
amp_teste = squeeze(amplitudes(1, :, :));
feat_teste = extrair_features_wimans(amp_teste);
n_features = length(feat_teste);

X = zeros(n_amostras, n_features);
for i = 1:n_amostras
    amp = squeeze(amplitudes(i, :, :));
    X(i, :) = extrair_features_wimans(amp);
    if mod(i, 1000) == 0
        fprintf('  %d/%d...\n', i, n_amostras);
    end
end
fprintf('  Concluido: %d amostras x %d features\n\n', n_amostras, n_features);

y = labels;

%% ================================================================
%  TESTE 1: DATASET COMPLETO (todos ambientes juntos)
%  ================================================================
fprintf('================================================================\n');
fprintf('  TESTE 1: DATASET COMPLETO\n');
fprintf('================================================================\n\n');

% Balancear dataset (ausencia tem muito menos amostras)
idx_aus = find(y == 0);
idx_pres = find(y == 1);

% Subsample presenca para balancear (ou usar tudo)
% Para ser justo, usamos todas as ausencias e mesmo numero de presencas
rng(42);
if length(idx_pres) > length(idx_aus) * 3
    % Limita presenca a 3x ausencia para nao desbalancear demais
    idx_pres_sub = idx_pres(randperm(length(idx_pres), length(idx_aus) * 3));
    idx_bal = [idx_aus; idx_pres_sub];
else
    idx_bal = [idx_aus; idx_pres];
end
idx_bal = idx_bal(randperm(length(idx_bal)));

X_bal = X(idx_bal, :);
y_bal = y(idx_bal);
fprintf('Dataset balanceado: %d amostras (%d aus + %d pres)\n\n', ...
        length(y_bal), sum(y_bal==0), sum(y_bal==1));

% Split 80/20
rng(42);
n_treino = floor(0.8 * length(y_bal));
idx_shuffle = randperm(length(y_bal));
idx_tr = idx_shuffle(1:n_treino);
idx_te = idx_shuffle(n_treino+1:end);

X_tr = X_bal(idx_tr, :); y_tr = y_bal(idx_tr);
X_te = X_bal(idx_te, :); y_te = y_bal(idx_te);

fprintf('Treino: %d (%d aus + %d pres)\n', length(y_tr), sum(y_tr==0), sum(y_tr==1));
fprintf('Teste:  %d (%d aus + %d pres)\n\n', length(y_te), sum(y_te==0), sum(y_te==1));

% Treina RF
fprintf('Treinando Random Forest...\n');
modelo = TreeBagger(50, X_tr, y_tr, 'Method', 'classification', ...
                    'MinLeafSize', 5, 'MaxNumSplits', 20);
yp = str2double(predict(modelo, X_te));
acc = mean(yp == y_te);

TP = sum(yp==1 & y_te==1); TN = sum(yp==0 & y_te==0);
FP = sum(yp==1 & y_te==0); FN = sum(yp==0 & y_te==1);
prec_p = TP/max(TP+FP,1); rec_p = TP/max(TP+FN,1);
f1_p = 2*prec_p*rec_p/max(prec_p+rec_p,0.001);
prec_a = TN/max(TN+FN,1); rec_a = TN/max(TN+FP,1);
f1_a = 2*prec_a*rec_a/max(prec_a+rec_a,0.001);

fprintf('\nRESULTADO - DATASET COMPLETO:\n');
fprintf('  Acuracia: %.1f%% (%d/%d)\n', 100*acc, sum(yp==y_te), length(y_te));
fprintf('  Matriz: TN=%d FP=%d FN=%d TP=%d\n', TN, FP, FN, TP);
fprintf('  Presenca: prec=%.2f rec=%.2f F1=%.2f\n', prec_p, rec_p, f1_p);
fprintf('  Ausencia: prec=%.2f rec=%.2f F1=%.2f\n\n', prec_a, rec_a, f1_a);

% K-fold
fprintf('K-fold 5-fold...\n');
cv = cvpartition(y_bal, 'KFold', 5);
accs_cv = zeros(5, 1);
for fold = 1:5
    rf = TreeBagger(50, X_bal(training(cv,fold),:), y_bal(training(cv,fold)), ...
                    'Method', 'classification', 'MinLeafSize', 5, 'MaxNumSplits', 20);
    yp_cv = str2double(predict(rf, X_bal(test(cv,fold),:)));
    accs_cv(fold) = mean(yp_cv == y_bal(test(cv,fold)));
end
fprintf('  K-fold: %.1f%% +/- %.1f%%\n\n', 100*mean(accs_cv), 100*std(accs_cv));

%% ================================================================
%  TESTE 2: POR AMBIENTE (cross-environment)
%  ================================================================
fprintf('================================================================\n');
fprintf('  TESTE 2: POR AMBIENTE\n');
fprintf('================================================================\n\n');

env_names = {'classroom', 'meeting_room', 'empty_room'};
env_ids = [1, 2, 3];

% Treina em cada ambiente, testa no mesmo
fprintf('--- Treino e teste no MESMO ambiente ---\n');
for e = 1:3
    mask = environments(idx_bal) == env_ids(e);
    if sum(mask) < 20, continue; end
    Xe = X_bal(mask, :); ye = y_bal(mask);
    n_tr_e = floor(0.8 * length(ye));
    rng(42);
    idx_s = randperm(length(ye));
    Xtr_e = Xe(idx_s(1:n_tr_e), :); ytr_e = ye(idx_s(1:n_tr_e));
    Xte_e = Xe(idx_s(n_tr_e+1:end), :); yte_e = ye(idx_s(n_tr_e+1:end));
    rf_e = TreeBagger(50, Xtr_e, ytr_e, 'Method', 'classification', 'MinLeafSize', 5, 'MaxNumSplits', 20);
    yp_e = str2double(predict(rf_e, Xte_e));
    acc_e = mean(yp_e == yte_e);
    fprintf('  %s: %.1f%% (%d amostras)\n', env_names{e}, 100*acc_e, length(ye));
end

% Cross-environment: treina em 2, testa em 1
fprintf('\n--- Cross-environment (treina 2, testa 1) ---\n');
for e_test = 1:3
    e_train = setdiff(1:3, e_test);
    mask_tr = ismember(environments(idx_bal), env_ids(e_train));
    mask_te = environments(idx_bal) == env_ids(e_test);
    if sum(mask_te) < 10, continue; end
    
    rf_cross = TreeBagger(50, X_bal(mask_tr,:), y_bal(mask_tr), ...
                          'Method', 'classification', 'MinLeafSize', 5, 'MaxNumSplits', 20);
    yp_cross = str2double(predict(rf_cross, X_bal(mask_te,:)));
    acc_cross = mean(yp_cross == y_bal(mask_te));
    fprintf('  Treina [%s+%s] -> Testa [%s]: %.1f%%\n', ...
            env_names{e_train(1)}, env_names{e_train(2)}, env_names{e_test}, 100*acc_cross);
end

%% ================================================================
%  TESTE 3: POR NUMERO DE USUARIOS
%  ================================================================
fprintf('\n================================================================\n');
fprintf('  TESTE 3: ACURACIA POR NUMERO DE USUARIOS\n');
fprintf('================================================================\n\n');

% Treina com todos, testa separado por num_users
modelo_full = TreeBagger(50, X_tr, y_tr, 'Method', 'classification', ...
                         'MinLeafSize', 5, 'MaxNumSplits', 20);

fprintf('%-12s %8s %8s %8s\n', 'Num Users', 'N', 'Acertos', 'Acuracia');
for u = 0:5
    mask_u = num_users(idx_bal(idx_te)) == u;
    if sum(mask_u) == 0, continue; end
    yp_u = yp(mask_u);
    yt_u = y_te(mask_u);
    acc_u = mean(yp_u == yt_u);
    fprintf('%-12d %8d %8d %7.1f%%\n', u, sum(mask_u), sum(yp_u==yt_u), 100*acc_u);
end

%% ================================================================
%  SALVA RESULTADOS
%  ================================================================
resultado_wimans.acuracia_geral = acc;
resultado_wimans.acuracia_kfold = mean(accs_cv);
resultado_wimans.kfold_std = std(accs_cv);
resultado_wimans.precisao_presenca = prec_p;
resultado_wimans.recall_presenca = rec_p;
resultado_wimans.f1_presenca = f1_p;
resultado_wimans.precisao_ausencia = prec_a;
resultado_wimans.recall_ausencia = rec_a;
resultado_wimans.f1_ausencia = f1_a;
resultado_wimans.matriz = [TN FP; FN TP];
resultado_wimans.n_treino = length(y_tr);
resultado_wimans.n_teste = length(y_te);
resultado_wimans.n_features = n_features;
resultado_wimans.timestamp = datetime('now');
resultado_wimans.predicoes = yp;
resultado_wimans.rotulos = y_te;

save(fullfile(PASTA_WIMANS, 'resultado_wimans.mat'), 'resultado_wimans', 'modelo');
fprintf('\nResultados salvos em %s\n', fullfile(PASTA_WIMANS, 'resultado_wimans.mat'));

%% ================================================================
%  GRAFICOS
%  ================================================================
figure('Name', 'Validacao WiMANS', 'Position', [50 50 1100 700]);

subplot(2, 2, 1);
bar([TN FP; FN TP]);
set(gca, 'XTickLabel', {'Real: Ausencia', 'Real: Presenca'});
legend('Pred: Ausencia', 'Pred: Presenca', 'Location', 'best');
title(sprintf('WiMANS - Acuracia: %.1f%%', 100*acc));
grid on;

subplot(2, 2, 2);
bar(100*accs_cv);
xlabel('Fold'); ylabel('Acuracia (%)');
title(sprintf('K-fold 5-fold: %.1f%% +/- %.1f%%', 100*mean(accs_cv), 100*std(accs_cv)));
ylim([0 105]); grid on;

subplot(2, 2, 3);
% Acuracia por numero de usuarios
acc_por_u = zeros(6, 1);
n_por_u = zeros(6, 1);
for u = 0:5
    mask_u = num_users(idx_bal(idx_te)) == u;
    if sum(mask_u) > 0
        acc_por_u(u+1) = mean(yp(mask_u) == y_te(mask_u));
        n_por_u(u+1) = sum(mask_u);
    end
end
bar(0:5, 100*acc_por_u);
xlabel('Numero de usuarios'); ylabel('Acuracia (%)');
title('Acuracia por numero de usuarios');
ylim([0 105]); grid on;

subplot(2, 2, 4);
% Histograma de probabilidades
[~, scores] = predict(modelo, X_te);
probs = scores(:, 2);
hold on;
histogram(probs(y_te==0), 20, 'FaceColor', [0.2 0.6 0.2], 'FaceAlpha', 0.6);
histogram(probs(y_te==1), 20, 'FaceColor', [0.8 0.2 0.2], 'FaceAlpha', 0.6);
xline(0.5, 'k--', 'LineWidth', 1.5);
xlabel('Probabilidade de presenca');
ylabel('Frequencia');
legend('Ausencia', 'Presenca', 'Threshold');
title('Distribuicao de probabilidades');
grid on;

fprintf('\n================================================================\n');
fprintf('  VALIDACAO WIMANS CONCLUIDA\n');
fprintf('================================================================\n');
