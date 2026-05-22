Sistema de detecção de presença humana utilizando Channel State Information (CSI) de sinais WiFi capturados com ESP32 e classificados por Random Forest.

## Estrutura

```
├── comum/
│   ├── ler_csi_buffer.m          # Parser serial ESP32 → amplitudes CSI
│   └── extrair_features_v2.m     # Extração de 30 features normalizadas
│
├── experimentos/
│   ├── experimento_novo.m        # Coleta + treino + teste (pipeline completo ~12 min)
│   ├── experimento_testar.m      # Teste com calibração adaptativa do threshold
│   └── experimento_gerenciar.m   # Listar e gerenciar experimentos salvos
│
├── diagnostico/
│   └── monitorar_drift.m         # Monitoramento contínuo de drift temporal
│
└── wimans/
    ├── preparar_wimans.m         # Converte dataset WiMANS (.npy → .mat)
    ├── extrair_features_wimans.m # Features adaptadas para 30 subportadoras
    └── validar_wimans.m          # Validação completa no dataset WiMANS
```

## Hardware

- **ESP32 DevKit CH9102X** — Caef Eletronics, antena PCB integrada, 2.4 GHz
- Firmware: `csi_recv_router` — [espressif/esp-csi](https://github.com/espressif/esp-csi)
- Comunicação: COM5, 921600 baud

## Dataset WiMANS
[github.com/huangshk/WiMANS](https://github.com/huangshk/WiMANS) — Imperial College London  
Usado para validação da abordagem metodológica, não comparação direta de hardware.

## Dependências
- MATLAB + Statistics and Machine Learning Toolbox
- ESP-IDF 5.5.3

## Referências
- Yousefi et al. (2017) — *A Survey on Behavior Recognition Using WiFi Channel State Information*
- Huang et al. (2024) — *WiMANS: A Benchmark Dataset for WiFi-based Multi-User Activity Sensing*


