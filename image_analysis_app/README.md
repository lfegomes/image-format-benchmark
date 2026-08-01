# image_analysis_app

Aplicativo Flutter de benchmark de formato/qualidade/resolução
de imagens. Ver o README na raiz do repositório para o fluxo completo (dataset → servidor → app).

## Requisitos

- Flutter 3.44.7 — mesma versão registrada em
  `lib/benchmark/config/experiment_config.dart`
  (`flutterVersionForRecordKeeping`), usada para identificar a versão do
  Flutter nos resultados exportados. Se atualizar o SDK, atualize também
  essa constante.

## Estrutura

```text
lib/
  main.dart, app.dart   # entrada e navegação
  benchmark/
    config/             # constantes e enums do experimento
    models/                    
    data/                      
    network/            # download sem cache
    decoding/           # decodificação cronometrada
    quality/            # SSIM
    stats/              # estatística e fronteira de Pareto
    runner/             # orquestração das tarefas
  presentation/         # 3 telas: setup, benchmark, results
test/benchmark/           
```

## Rodar o app

```bash
flutter run
```

Na tela de configuração, informe a URL-base do servidor (IPv4 do
computador na mesma rede Wi-Fi, nunca `localhost` no celular), teste a conexão, carregue o manifesto e inicie o experimento.

## Testes e análise estática

```bash
flutter test
flutter analyze
```
