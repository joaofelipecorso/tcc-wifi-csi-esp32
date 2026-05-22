function features = extrair_features_wimans(amplitudes)
% EXTRAIR_FEATURES_WIMANS  Features normalizadas para dataset WiMANS
%
% Adaptacao do extrair_features_v2 para 30 subportadoras (Intel 5300)
% em vez de 64 (ESP32). Mesma logica de normalizacao intra-janela.
%
% Entrada:
%   amplitudes - matriz [N_frames x 30] de amplitudes CSI
%
% Saida:
%   features - vetor linha 1 x 30

    N_SUB = size(amplitudes, 2);
    subs_validas = 1:N_SUB;  % todas validas no Intel 5300

    % Grupos de subportadoras (adaptado para 30)
    n_grupo = max(3, floor(N_SUB / 6));
    GRUPOS = {};
    for g = 1:6
        ini = (g-1)*5 + 1;
        fim = min(g*5, N_SUB);
        if ini <= N_SUB
            GRUPOS{end+1} = ini:fim;
        end
    end
    SUBS_SENSIVEIS = round(N_SUB*0.6):min(round(N_SUB*0.85), N_SUB);

    if isempty(amplitudes) || size(amplitudes, 1) < 5
        features = zeros(1, 30);
        return;
    end

    [n_frames, ~] = size(amplitudes);

    % NORMALIZACAO INTRA-JANELA
    media_frame = mean(amplitudes(:, subs_validas), 2);
    std_frame = std(amplitudes(:, subs_validas), 0, 2);
    std_frame(std_frame < 0.5) = 0.5;

    amp_norm = amplitudes;
    for i = 1:n_frames
        amp_norm(i, subs_validas) = (amplitudes(i, subs_validas) - media_frame(i)) / std_frame(i);
    end

    % FEATURES GLOBAIS (4)
    media_temporal = mean(amp_norm(:, subs_validas), 1);
    std_temporal = std(amp_norm(:, subs_validas), 0, 1);

    f_global = zeros(1, 4);
    f_global(1) = mean(std_temporal);
    f_global(2) = max(std_temporal);
    f_global(3) = std(media_temporal);
    f_global(4) = mean(std_frame);

    % RAZOES ENTRE GRUPOS (4)
    terco = floor(N_SUB / 3);
    grupo_baixo = mean(mean(amplitudes(:, 1:terco), 1));
    grupo_medio = mean(mean(amplitudes(:, terco+1:2*terco), 1));
    grupo_alto = mean(mean(amplitudes(:, 2*terco+1:end), 1));
    grupo_sens = mean(mean(amplitudes(:, SUBS_SENSIVEIS), 1));
    total = mean(mean(amplitudes(:, subs_validas), 1));
    if total < 0.1, total = 0.1; end

    f_razoes = zeros(1, 4);
    f_razoes(1) = grupo_sens / total;
    f_razoes(2) = grupo_baixo / total;
    f_razoes(3) = grupo_alto / total;
    if grupo_baixo > 0.1
        f_razoes(4) = grupo_alto / grupo_baixo;
    end

    % STD TEMPORAL POR GRUPO (7 = 6 grupos + 1 sensivel)
    n_grupos_real = length(GRUPOS);
    f_std_grupos = zeros(1, n_grupos_real + 1);
    for g = 1:n_grupos_real
        subs_g = GRUPOS{g};
        if ~isempty(subs_g)
            f_std_grupos(g) = mean(std(amp_norm(:, subs_g), 0, 1));
        end
    end
    f_std_grupos(end) = mean(std(amp_norm(:, SUBS_SENSIVEIS), 0, 1));

    % VARIABILIDADE INTER-FRAME (5)
    f_var = zeros(1, 5);
    if n_frames > 1
        diffs = diff(amp_norm(:, subs_validas), 1, 1);
        f_var(1) = mean(mean(abs(diffs)));
        f_var(2) = mean(std(diffs, 0, 1));
        f_var(3) = max(mean(abs(diffs), 1));

        acorr = zeros(1, length(subs_validas));
        for j = 1:length(subs_validas)
            sub = subs_validas(j);
            x = amp_norm(:, sub);
            if std(x) > 0.01
                c = corrcoef(x(1:end-1), x(2:end));
                acorr(j) = c(1, 2);
            end
        end
        f_var(4) = mean(acorr(~isnan(acorr)));
        f_var(5) = std(acorr(~isnan(acorr)));
    end

    % PERCENTIS (5)
    todas_amp = amp_norm(:, subs_validas);
    todas_amp = todas_amp(:);
    f_pct = zeros(1, 5);
    f_pct(1) = prctile(todas_amp, 10);
    f_pct(2) = prctile(todas_amp, 25);
    f_pct(3) = prctile(todas_amp, 50);
    f_pct(4) = prctile(todas_amp, 75);
    f_pct(5) = prctile(todas_amp, 90);

    % FORMA (3)
    f_forma = zeros(1, 3);
    f_forma(1) = skewness(todas_amp);
    f_forma(2) = kurtosis(todas_amp);
    [counts, ~] = histcounts(todas_amp, 20);
    counts = counts / sum(counts);
    counts = counts(counts > 0);
    f_forma(3) = -sum(counts .* log2(counts));

    % CONCATENA (4+4+7+5+5+3 = 28, pad to 30)
    features = [f_global, f_razoes, f_std_grupos, f_var, f_pct, f_forma];
    
    % Pad/trim para 30 features
    if length(features) < 30
        features(end+1:30) = 0;
    elseif length(features) > 30
        features = features(1:30);
    end

    features(~isfinite(features)) = 0;
end
