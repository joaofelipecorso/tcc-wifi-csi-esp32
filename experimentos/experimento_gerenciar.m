%% EXPERIMENTO_GERENCIAR - Lista, exclui e inclui experimentos
%
% Mostra todos os experimentos com seus resultados.
% Permite excluir/incluir experimentos do dataset combinado.

clear; clc;

PASTA_EXP = 'C:\TCC2\experimentos';
PASTA_COMUM = 'C:\TCC2\matlab\comum';
addpath(PASTA_COMUM);

if ~exist(PASTA_EXP, 'dir')
    fprintf('Nenhum experimento encontrado.\n');
    return;
end

pastas = dir(fullfile(PASTA_EXP, 'exp_*'));
if isempty(pastas)
    fprintf('Nenhum experimento encontrado.\n');
    return;
end

fprintf('================================================================\n');
fprintf('  GERENCIADOR DE EXPERIMENTOS\n');
fprintf('================================================================\n\n');

% carrega info de cada experimento
exps = [];
for i = 1:length(pastas)
    pasta = fullfile(PASTA_EXP, pastas(i).name);
    arq_info = fullfile(pasta, 'info_exp.mat');
    arq_result = fullfile(pasta, 'resultado_teste.mat');

    if ~exist(arq_info, 'file'), continue; end

    d = load(arq_info);
    e.nome = pastas(i).name;
    e.pasta = pasta;
    e.numero = d.info_exp.numero;
    e.timestamp = d.info_exp.timestamp_inicio;
    e.n_aus = d.info_exp.n_aus_coleta;
    e.n_pres = d.info_exp.n_pres_coleta;
    e.excluido = d.info_exp.excluido;

    if exist(arq_result, 'file')
        r = load(arq_result);
        e.acuracia = r.resultado.acuracia;
        e.f1_pres = r.resultado.f1_presenca;
        e.f1_aus = r.resultado.f1_ausencia;
    else
        e.acuracia = NaN;
        e.f1_pres = NaN;
        e.f1_aus = NaN;
    end

    exps = [exps, e];
end

if isempty(exps)
    fprintf('Nenhum experimento valido encontrado.\n');
    return;
end

% mostra tabela
fprintf('%-8s %-20s %6s %6s %8s %8s %8s %10s\n', ...
        '#', 'Data/Hora', 'Aus', 'Pres', 'Acc', 'F1_P', 'F1_A', 'Status');
fprintf('%s\n', repmat('-', 1, 80));

for i = 1:length(exps)
    e = exps(i);
    if e.excluido, status = 'EXCLUIDO'; else, status = 'ATIVO'; end
    ts = char(e.timestamp);
    if length(ts) > 19, ts = ts(1:19); end
    fprintf('%-8d %-20s %6d %6d %7.1f%% %8.2f %8.2f %10s\n', ...
            e.numero, ts, e.n_aus, e.n_pres, ...
            100*e.acuracia, e.f1_pres, e.f1_aus, status);
end

n_ativos = sum(~[exps.excluido]);
n_aus_total = sum([exps(~[exps.excluido]).n_aus]);
n_pres_total = sum([exps(~[exps.excluido]).n_pres]);
fprintf('%s\n', repmat('-', 1, 80));
fprintf('Total ativos: %d experimentos | %d aus + %d pres = %d amostras\n\n', ...
        n_ativos, n_aus_total, n_pres_total, n_aus_total + n_pres_total);

%% menu
while true
    fprintf('\nOpcoes:\n');
    fprintf('  1 - Excluir um experimento\n');
    fprintf('  2 - Incluir um experimento (reativar)\n');
    fprintf('  3 - Sair\n');
    op = input('Escolha: ', 's');

    if strcmp(op, '3') || isempty(op)
        break;
    elseif strcmp(op, '1')
        num = input('Numero do experimento para EXCLUIR: ');
        for i = 1:length(exps)
            if exps(i).numero == num
                exps(i).excluido = true;
                d = load(fullfile(exps(i).pasta, 'info_exp.mat'));
                d.info_exp.excluido = true;
                save(fullfile(exps(i).pasta, 'info_exp.mat'), '-struct', 'd');
                fprintf('Experimento %d EXCLUIDO.\n', num);
                break;
            end
        end
    elseif strcmp(op, '2')
        num = input('Numero do experimento para INCLUIR: ');
        for i = 1:length(exps)
            if exps(i).numero == num
                exps(i).excluido = false;
                d = load(fullfile(exps(i).pasta, 'info_exp.mat'));
                d.info_exp.excluido = false;
                save(fullfile(exps(i).pasta, 'info_exp.mat'), '-struct', 'd');
                fprintf('Experimento %d INCLUIDO.\n', num);
                break;
            end
        end
    end
end

fprintf('Pronto.\n');
