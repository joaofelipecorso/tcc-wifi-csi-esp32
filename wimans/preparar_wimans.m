%% PREPARAR_WIMANS - Converte dataset WiMANS para .mat (sem Python)
%
% Le arquivos .npy de amplitude do WiMANS e converte para um unico .mat
% compativel com o validar_wimans.m
%
% Adaptacoes para simular ESP32:
%   - Seleciona 1 par de antena (TX1-RX1)
%   - Subamostras de ~2800 para 300 frames
%
% AJUSTE O CAMINHO ABAIXO SE NECESSARIO

clear; clc;

%% CONFIGURACAO
PASTA_AMP = 'C:\Users\João Felipe Corso\Documents\TCC2\dataset\wifi_csi\amp';
ARQUIVO_LABELS = 'C:\Users\João Felipe Corso\Documents\TCC2\dataset\binary_presence_2.4GHz.csv';
PASTA_SAIDA = 'C:\TCC2\wimans';

TX_ANT = 1;  % indice antena TX (1-3)
RX_ANT = 1;  % indice antena RX (1-3)
TARGET_FRAMES = 300;

if ~exist(PASTA_SAIDA, 'dir'), mkdir(PASTA_SAIDA); end

fprintf('================================================================\n');
fprintf('  PREPARACAO DATASET WIMANS PARA MATLAB\n');
fprintf('================================================================\n\n');

%% Le labels
fprintf('Carregando labels...\n');
opts = detectImportOptions(ARQUIVO_LABELS);
opts.VariableNamingRule = 'preserve';
T = readtable(ARQUIVO_LABELS, opts);

% Limpa nomes das colunas (remove BOM e espacos)
T.Properties.VariableNames = strtrim(T.Properties.VariableNames);

n_total = height(T);
fprintf('  Total amostras 2.4 GHz: %d\n', n_total);

% Identifica colunas
% Espera: sample_id, environment, num_users, wifi_band, presence
col_id = T{:, 1};       % sample_id
if iscell(col_id), col_id = string(col_id); end
col_env = T{:, 2};      % environment
if iscell(col_env), col_env = string(col_env); end
col_users = T{:, 3};    % num_users
col_pres = T{:, 5};     % presence
if iscell(col_pres), col_pres = string(col_pres); end

n_pres = sum(contains(col_pres, 'presence'));
n_aus = sum(contains(col_pres, 'absence'));
fprintf('  Presenca: %d | Ausencia: %d\n\n', n_pres, n_aus);

%% Processa amostras
fprintf('Processando amostras de %s...\n', PASTA_AMP);
fprintf('(Isso pode demorar alguns minutos)\n\n');

% Pre-aloca
amplitudes = zeros(n_total, TARGET_FRAMES, 30, 'single');
labels = zeros(n_total, 1, 'int32');
environments = zeros(n_total, 1, 'int32');
num_users = zeros(n_total, 1, 'int32');
frames_originais = zeros(n_total, 1, 'int32');
frames_efetivos = zeros(n_total, 1, 'int32');

erros = 0;
processadas = 0;

for i = 1:n_total
    sample_id = strtrim(char(col_id(i)));
    arquivo = fullfile(PASTA_AMP, [sample_id, '.npy']);
    
    if ~exist(arquivo, 'file')
        erros = erros + 1;
        continue;
    end
    
    % Le arquivo .npy
    try
        amp = readNPY_local(arquivo);
    catch
        erros = erros + 1;
        continue;
    end
    
    % amp shape: (T, 3, 3, 30)
    if ndims(amp) ~= 4 || size(amp, 2) ~= 3 || size(amp, 3) ~= 3 || size(amp, 4) ~= 30
        erros = erros + 1;
        continue;
    end
    
    % Seleciona 1 par de antena: (T, 30)
    amp_single = squeeze(amp(:, TX_ANT, RX_ANT, :));
    n_frames_orig = size(amp_single, 1);
    
    % Subamostrar
    if n_frames_orig > TARGET_FRAMES
        indices = round(linspace(1, n_frames_orig, TARGET_FRAMES));
        amp_sub = amp_single(indices, :);
        n_efetivo = TARGET_FRAMES;
    else
        amp_sub = zeros(TARGET_FRAMES, 30, 'single');
        amp_sub(1:n_frames_orig, :) = amp_single;
        n_efetivo = n_frames_orig;
    end
    
    processadas = processadas + 1;
    amplitudes(processadas, :, :) = single(amp_sub);
    
    % Label
    if contains(col_pres(i), 'presence')
        labels(processadas) = 1;
    else
        labels(processadas) = 0;
    end
    
    % Environment
    env = strtrim(char(col_env(i)));
    if contains(env, 'classroom'), environments(processadas) = 1;
    elseif contains(env, 'meeting'), environments(processadas) = 2;
    elseif contains(env, 'empty'), environments(processadas) = 3;
    end
    
    % Num users
    if isnumeric(col_users)
        num_users(processadas) = col_users(i);
    else
        num_users(processadas) = str2double(col_users(i));
    end
    
    frames_originais(processadas) = n_frames_orig;
    frames_efetivos(processadas) = n_efetivo;
    
    if mod(processadas, 500) == 0
        fprintf('  %d/%d processadas...\n', processadas, n_total);
    end
end

% Corta arrays
amplitudes = amplitudes(1:processadas, :, :);
labels = labels(1:processadas);
environments = environments(1:processadas);
num_users = num_users(1:processadas);
frames_originais = frames_originais(1:processadas);
frames_efetivos = frames_efetivos(1:processadas);

fprintf('\n  Processadas: %d | Erros: %d\n', processadas, erros);

%% Resumo
fprintf('\n================================================================\n');
fprintf('  RESUMO\n');
fprintf('================================================================\n');
fprintf('  Amostras: %d\n', processadas);
fprintf('  Ausencia: %d\n', sum(labels == 0));
fprintf('  Presenca: %d\n', sum(labels == 1));
fprintf('  Frames/amostra: %d (subsampled de ~%d)\n', TARGET_FRAMES, round(mean(frames_originais)));
fprintf('  Subportadoras: 30\n');
fprintf('  Antena: TX%d-RX%d\n', TX_ANT, RX_ANT);
fprintf('  Ambientes: classroom(%d) meeting(%d) empty(%d)\n', ...
        sum(environments==1), sum(environments==2), sum(environments==3));

%% Salva
arquivo_saida = fullfile(PASTA_SAIDA, 'wimans_2.4GHz.mat');
fprintf('\nSalvando em %s...\n', arquivo_saida);

n_subcarriers = 30;
target_frames = TARGET_FRAMES;
tx_antenna = TX_ANT;
rx_antenna = RX_ANT;

save(arquivo_saida, 'amplitudes', 'labels', 'environments', 'num_users', ...
     'frames_originais', 'frames_efetivos', 'n_subcarriers', 'target_frames', ...
     'tx_antenna', 'rx_antenna', '-v7.3');

info = dir(arquivo_saida);
fprintf('  Tamanho: %.1f MB\n', info.bytes / 1024 / 1024);
fprintf('\nProximo passo: rodar validar_wimans.m\n');
fprintf('================================================================\n');

%% ================================================================
%  FUNCAO LOCAL: LE ARQUIVO .NPY (formato NumPy)
%  ================================================================
function data = readNPY_local(filename)
    fid = fopen(filename, 'r');
    if fid == -1, error('Nao conseguiu abrir %s', filename); end
    
    % Magic string: \x93NUMPY
    magic = fread(fid, 6, 'uint8');
    if magic(1) ~= 147 || ~isequal(char(magic(2:6)'), 'NUMPY')
        fclose(fid);
        error('Nao eh arquivo .npy valido');
    end
    
    % Versao
    major = fread(fid, 1, 'uint8');
    minor = fread(fid, 1, 'uint8');
    
    % Header length
    if major == 1
        header_len = fread(fid, 1, 'uint16');
    else
        header_len = fread(fid, 1, 'uint32');
    end
    
    % Header (string Python dict)
    header = char(fread(fid, header_len, 'char')');
    
    % Parse dtype
    if contains(header, '''<f4''') || contains(header, 'float32')
        dtype = 'single';
        bytes_per = 4;
    elseif contains(header, '''<f8''') || contains(header, 'float64')
        dtype = 'double';
        bytes_per = 8;
    elseif contains(header, '''<i4''') || contains(header, 'int32')
        dtype = 'int32';
        bytes_per = 4;
    elseif contains(header, '''<i8''') || contains(header, 'int64')
        dtype = 'int64';
        bytes_per = 8;
    else
        dtype = 'single';
        bytes_per = 4;
    end
    
    % Parse shape
    shape_match = regexp(header, '\(([0-9, ]+)\)', 'tokens');
    if ~isempty(shape_match)
        shape_str = shape_match{1}{1};
        shape_str = strrep(shape_str, ' ', '');
        if shape_str(end) == ','
            shape_str = shape_str(1:end-1);
        end
        shape = str2double(strsplit(shape_str, ','));
    else
        fclose(fid);
        error('Nao conseguiu parsear shape do .npy');
    end
    
    % Parse fortran_order
    fortran_order = contains(header, '''fortran_order'': True');
    
    % Le dados
    n_elements = prod(shape);
    raw = fread(fid, n_elements, dtype);
    fclose(fid);
    
    % Reshape (C order = row-major, precisa permutar)
    if ~fortran_order
        % C order: reverse shape for reshape, then permute
        data = reshape(raw, fliplr(shape));
        data = permute(data, length(shape):-1:1);
    else
        data = reshape(raw, shape);
    end
end
