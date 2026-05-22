function features = extrair_features_v2(amplitudes)
% EXTRAIR_FEATURES_V2  Extrai features NORMALIZADAS de uma amostra CSI
%
% MUDANCAS vs V1:
%   1. Normalização intra-janela (z-score por frame) - combate drift
%   2. Features relativas (razões) em vez de absolutas
%   3. Usa TODAS as subportadoras válidas, não só 45-53
%   4. Adiciona features de variabilidade temporal
%
% Entrada:
%   amplitudes - matriz [N_frames x 64] de amplitudes CSI
%
% Saída:
%   features - vetor linha 1 x 30
%
% Features (30 total):
%   1-4:   Estatísticas globais normalizadas
%   5-8:   Razões entre grupos de subportadoras
%   9-17:  Std temporal por grupo de subportadoras (9 grupos)
%   18-22: Variabilidade inter-frame (5 métricas)
%   23-27: Percentis da distribuição de amplitudes
%   28-30: Forma da distribuição (skewness, kurtosis, entropy)

    SUBS_ZERADAS = 29:37;  % DC + guard bands
    subs_validas = setdiff(1:64, SUBS_ZERADAS);  % 55 subs úteis

    % grupos de subportadoras (cobertura ampla, não só 45-53)
    GRUPOS = {1:7, 8:14, 15:21, 22:28, 38:44, 45:51, 52:58, 59:64};
    % grupo sensível original mantido como referência
    SUBS_SENSIVEIS = 45:53;

    % --- valida entrada ---
    if isempty(amplitudes) || size(amplitudes, 1) < 5
        features = zeros(1, 30);
        return;
    end

    [n_frames, ~] = size(amplitudes);

    % =====================================================
    % NORMALIZAÇÃO INTRA-JANELA (z-score por frame)
    % Cada frame é normalizado pela sua própria média/std
    % Isso remove dependência de amplitude absoluta do canal
    % =====================================================
    media_frame = mean(amplitudes(:, subs_validas), 2);  % [N x 1]
    std_frame = std(amplitudes(:, subs_validas), 0, 2);  % [N x 1]
    std_frame(std_frame < 0.5) = 0.5;  % evita divisão por zero

    amp_norm = amplitudes;
    for i = 1:n_frames
        amp_norm(i, subs_validas) = (amplitudes(i, subs_validas) - media_frame(i)) / std_frame(i);
    end

    % =====================================================
    % FEATURES GLOBAIS NORMALIZADAS (4)
    % =====================================================
    media_temporal = mean(amp_norm(:, subs_validas), 1);   % 1x55
    std_temporal = std(amp_norm(:, subs_validas), 0, 1);   % 1x55

    f_global = zeros(1, 4);
    f_global(1) = mean(std_temporal);                      % variabilidade média
    f_global(2) = max(std_temporal);                       % variabilidade máxima
    f_global(3) = std(media_temporal);                     % spread entre subs
    f_global(4) = mean(std_frame);                         % nível médio de variação por frame

    % =====================================================
    % RAZÕES ENTRE GRUPOS (4)
    % =====================================================
    grupo_baixo = mean(mean(amplitudes(:, 1:14), 1));
    grupo_medio = mean(mean(amplitudes(:, 38:51), 1));
    grupo_alto = mean(mean(amplitudes(:, 52:64), 1));
    grupo_sens = mean(mean(amplitudes(:, SUBS_SENSIVEIS), 1));

    total = mean(mean(amplitudes(:, subs_validas), 1));
    if total < 0.1, total = 0.1; end

    f_razoes = zeros(1, 4);
    f_razoes(1) = grupo_sens / total;       % razão sensíveis/total
    f_razoes(2) = grupo_baixo / total;      % razão baixas/total
    f_razoes(3) = grupo_alto / total;       % razão altas/total
    if grupo_baixo > 0.1
        f_razoes(4) = grupo_alto / grupo_baixo; % razão altas/baixas
    end

    % =====================================================
    % STD TEMPORAL POR GRUPO NORMALIZADO (9)
    % Cada grupo de subs: quanto varia ao longo do tempo
    % =====================================================
    f_std_grupos = zeros(1, length(GRUPOS) + 1);
    for g = 1:length(GRUPOS)
        subs_g = intersect(GRUPOS{g}, subs_validas);
        if ~isempty(subs_g)
            f_std_grupos(g) = mean(std(amp_norm(:, subs_g), 0, 1));
        end
    end
    % grupo sensível separado
    f_std_grupos(end) = mean(std(amp_norm(:, SUBS_SENSIVEIS), 0, 1));

    % =====================================================
    % VARIABILIDADE INTER-FRAME (5)
    % Quanto o sinal muda entre frames consecutivos
    % =====================================================
    f_var = zeros(1, 5);
    if n_frames > 1
        diffs = diff(amp_norm(:, subs_validas), 1, 1);
        f_var(1) = mean(mean(abs(diffs)));              % MAD médio
        f_var(2) = mean(std(diffs, 0, 1));              % std das diferenças
        f_var(3) = max(mean(abs(diffs), 1));            % sub com mais variação

        % autocorrelação temporal (lag-1) média
        acorr = zeros(1, length(subs_validas));
        for j = 1:length(subs_validas)
            sub = subs_validas(j);
            x = amp_norm(:, sub);
            if std(x) > 0.01
                c = corrcoef(x(1:end-1), x(2:end));
                acorr(j) = c(1, 2);
            end
        end
        f_var(4) = mean(acorr(~isnan(acorr)));         % autocorrelação média
        f_var(5) = std(acorr(~isnan(acorr)));           % spread da autocorrelação
    end

    % =====================================================
    % PERCENTIS DA DISTRIBUIÇÃO (5)
    % =====================================================
    todas_amp = amp_norm(:, subs_validas);
    todas_amp = todas_amp(:);

    f_pct = zeros(1, 5);
    f_pct(1) = prctile(todas_amp, 10);
    f_pct(2) = prctile(todas_amp, 25);
    f_pct(3) = prctile(todas_amp, 50);    % mediana
    f_pct(4) = prctile(todas_amp, 75);
    f_pct(5) = prctile(todas_amp, 90);

    % =====================================================
    % FORMA DA DISTRIBUIÇÃO (3)
    % =====================================================
    f_forma = zeros(1, 3);
    f_forma(1) = skewness(todas_amp);
    f_forma(2) = kurtosis(todas_amp);

    % "entropia" simplificada: número de bins não-vazios normalizado
    [counts, ~] = histcounts(todas_amp, 20);
    counts = counts / sum(counts);
    counts = counts(counts > 0);
    f_forma(3) = -sum(counts .* log2(counts));  % Shannon entropy

    % =====================================================
    % CONCATENA
    % =====================================================
    features = [f_global, f_razoes, f_std_grupos, f_var, f_pct, f_forma];

    % segurança
    features(~isfinite(features)) = 0;
end
