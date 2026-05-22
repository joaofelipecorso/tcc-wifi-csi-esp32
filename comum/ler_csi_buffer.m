function [amplitudes, n_frames] = ler_csi_buffer(buffer_bytes)
% LER_CSI_BUFFER  Converte bytes brutos da serial ESP32 em matriz de amplitudes CSI
%
% Entrada:
%   buffer_bytes - vetor uint8 com bytes lidos da serial
%
% Saida:
%   amplitudes   - matriz [N_frames x 64] com amplitudes (sqrt(real^2+imag^2))
%   n_frames     - numero de frames CSI parseados com sucesso
%
% Formato esperado de cada linha CSI:
%   CSI_DATA,id,MAC,RSSI,...,128,"[i,q,i,q,...]"
%
% O firmware oficial csi_recv_router envia 128 bytes (64 pares I/Q) por frame.

    N_SUB = 64;  % 64 subportadoras (HT20)

    % converte bytes para texto e separa em linhas
    texto = char(buffer_bytes(:)');
    linhas = splitlines(string(texto));

    % filtra apenas linhas que contem CSI_DATA
    mask_csi = contains(linhas, "CSI_DATA");
    linhas_csi = linhas(mask_csi);
    n_linhas = length(linhas_csi);

    if n_linhas == 0
        amplitudes = zeros(0, N_SUB);
        n_frames = 0;
        return;
    end

    % pre-aloca matriz com tamanho maximo
    amplitudes = zeros(n_linhas, N_SUB);
    n_frames = 0;

    for i = 1:n_linhas
        linha = char(linhas_csi(i));

        % extrai conteudo entre colchetes [i,q,i,q,...]
        ini = strfind(linha, '[');
        fim = strfind(linha, ']');

        if isempty(ini) || isempty(fim)
            continue;
        end

        ini = ini(1);
        fim = fim(end);

        if fim <= ini + 1
            continue;
        end

        conteudo = linha(ini+1 : fim-1);

        % parseia valores separados por virgula
        valores = str2double(strsplit(conteudo, ','));

        % remove NaN (valores invalidos)
        valores = valores(~isnan(valores));

        % precisa ter pelo menos 128 valores (64 pares I/Q)
        if length(valores) < 2 * N_SUB
            continue;
        end

        % pega exatamente 128 primeiros valores
        valores = valores(1:2*N_SUB);

        % calcula amplitudes: sqrt(real^2 + imag^2)
        real_parts = valores(1:2:end);  % indices impares = real
        imag_parts = valores(2:2:end);  % indices pares = imag
        amp_frame = sqrt(real_parts.^2 + imag_parts.^2);

        n_frames = n_frames + 1;
        amplitudes(n_frames, :) = amp_frame;
    end

    % corta linhas nao usadas
    amplitudes = amplitudes(1:n_frames, :);
end
