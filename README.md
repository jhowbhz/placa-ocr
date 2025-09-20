# Placa OCR API

API FastAPI para deteccao de placas Mercosul. O repositorio inclui script de inicializacao completa (`init.sh`), utilitarios para subir a API (`start.sh`) e configuracoes prontas para treino utilizando o dataset **Artificial Mercosur License Plates** (CC BY 4.0).

## 1. Visao geral

- Framework principal: FastAPI (Python 3.10+)
- Modelo de deteccao: YOLOv8 (Ultralytics)
- Objetivo: detectar placas padrao Mercosul em imagens, retornando coordenadas normalizadas e confianca.

## 2. Requisitos

- Python 3.10 ou superior (com `venv` habilitado)
- Git Bash, WSL ou outro shell POSIX para executar scripts `.sh` no Windows
- `curl` ou `wget` para baixar o dataset
- Espaco em disco: ~6 GB (dataset compactado + imagens extraidas + artefatos de treino)
- GPU opcional (CUDA) para treinos mais rapidos

## 3. Estrutura do projeto

```
.
|-- app/                  # Codigo FastAPI (routers, services, schemas)
|-- artifacts/            # Pesos YOLO gerados pelo treino (criado pelo init)
|-- data/                 # Dataset preparado para YOLO (criado pelo init)
|-- docs/postman.json     # Colecao Postman para testar a API
|-- init.sh               # Setup completo: dependencias, dataset, treino inicial
|-- start.sh              # Wrapper para executar a API em dev/prod
|-- requirements.txt
`-- .env-example
```

## 4. Configuracao de ambiente

1. Copie o exemplo de variaveis:
   ```bash
   cp .env-example .env
   ```
2. Ajuste `PLACAOCR_MODEL_PATH` para apontar para o peso YOLO desejado quando disponivel.

| Variavel | Descricao | Padrao |
| --- | --- | --- |
| `PLACAOCR_MODEL_PATH` | Caminho para o peso YOLO (`.pt`) utilizado na inferencia | `artifacts/license-plate.pt` |
| `PLACAOCR_CONFIDENCE_THRESHOLD` | Confianca minima para retornar deteccoes | `0.25` |
| `PLACAOCR_DEVICE` | Dispositivo (`cpu`, `cuda:0`, etc.) | `cpu` |
| `PLACAOCR_IMAGE_SIZE` | Tamanho de imagem usado na inferencia (None = default do modelo) | `640` |

**Integração API Brasil (opcional):**

| Variavel | Descricao | Padrao |
| --- | --- | --- |
| `PLACAOCR_APIBRASIL_BASE_URL` | Endpoint do recurso de consulta | `https://gateway.apibrasil.io/api/v2/vehicles/base/001/consulta` |
| `PLACAOCR_APIBRASIL_TOKEN` | Token/Bearer utilizado pela API Brasil | *(vazio)* |
| `PLACAOCR_APIBRASIL_TIMEOUT` | Timeout da chamada em segundos | `15` |

## 5. Instalar dependencias e preparar dataset

Execute o script de inicializacao na raiz do projeto:

```bash
./init.sh
```

O que o script faz:
- cria (ou reutiliza) o virtualenv em `.venv`;
- instala `requirements.txt` com `pip` atualizado;
- baixa o dataset Artificial Mercosur License Plates (~1.52 GB) via `curl` ou `wget`;
- extrai o zip e gera um split `train/val/test` deterministico (seed 42);
- gera o arquivo YAML para o Ultralytics em `data/yolo/mercosur-license-plates.yaml`;
- executa um treino inicial com YOLOv8 (`yolov8n.pt`, 1 epoch por padrao) e salva o melhor peso em `artifacts/license-plate.pt`;
- armazena os runs completos em `artifacts/runs/`.

Flags uteis:
- `./init.sh --skip-training`: prepara tudo exceto o treino (mantem pesos existentes).
- `./init.sh --force-download`: rebaixa e reextrai o dataset (descarta arquivos anteriores).

Variaveis de ambiente para ajuste rapido:

| Variavel | Funcao | Valor padrao |
| --- | --- | --- |
| `TRAIN_EPOCHS` | Numero de epocas no treino inicial | `1` |
| `TRAIN_BATCH` | Tamanho do batch por step | `16` |
| `BASE_MODEL` | Checkpoint YOLO base (qualquer compativel com Ultralytics) | `yolov8n.pt` |
| `TRAIN_IMAGE_SIZE` | Resolucao usada no treino | `640` |
| `MODEL_OUTPUT_NAME` | Nome do arquivo de saida em `artifacts/` | `license-plate.pt` |

> **Observacao:** o dataset possui licenca CC BY 4.0. Consulte [Mendeley Data](https://data.mendeley.com/datasets/nx9xbs4rgx/2) para detalhes.

## 6. Executar a API

Depois que o ambiente estiver configurado e o peso disponivel:

```bash
./start.sh --dev   # uvicorn com reload
./start.sh --prod  # uvicorn multiprocess (sem reload)
```

Por padrao o servidor sobe em `http://0.0.0.0:8000`. A documentacao Swagger fica em `http://localhost:8000/docs` e o Redoc em `http://localhost:8000/redoc`.

## 7. Testar com Postman / REST client

- Importe `docs/postman.json` no Postman.
- Defina a variavel `baseUrl` (padrao `http://localhost:8000`).
- Na requisicao `Detect License Plates` envie:
  - campo `file` com a imagem (`multipart/form-data`),
  - campo `tipo` (ex.: `agregados-basica`),
  - campo `homolog` (`true` para modo sandbox da API Brasil),
  - opcional `placa_manual` caso queira forcar a placa utilizada na consulta externa.

Resposta esperada:

```json
{
  "placa": "ABC1234",
  "data": [
    {
      "resumo": {
        "x_center": 0.51,
        "y_center": 0.63,
        "width": 0.18,
        "height": 0.07,
        "confidence": 0.94
      },
      "veiculo": {
        "marca": "FORD",
        "modelo": "KA 1.0",
        "detalhes": {
          "exemplo": "payload retornado pela API Brasil em modo homolog"
        }
      }
    }
  ]
}
```

## 8. Integracao com API Brasil

- Configure `PLACAOCR_APIBRASIL_TOKEN` (e demais variaveis) para habilitar a chamada.
- A API envia `tipo`, `placa` (derivada da imagem ou do campo `placa_manual`) e `homolog`.
- Se `homolog=true` e nenhuma placa for detectada, o sistema utiliza `ABC1234` para recuperar o payload de exemplo.
- O retorno completo da API Brasil e anexado em `data[].veiculo.detalhes`.

## 9. Desenvolvimento

- Utilize `./start.sh --dev` durante o desenvolvimento; o script carrega variaveis de `ENV_FILE` (padrao `.env`).
- Ajuste o codigo em `app/api/routes.py` e `app/services/detector.py` conforme necessario.
- Para atualizar dependencias, edite `requirements.txt` e rode novamente o `init.sh` ou `pip install -r requirements.txt` dentro do virtualenv.

## 10. Proximos passos sugeridos

- Implementar OCR real para extrair a placa a partir dos recortes retornados pelo detector.
- Executar treinos mais longos (maior `TRAIN_EPOCHS`) e avaliar metricas em `artifacts/runs/`.
- Adicionar testes automatizados para validar o servico de inferencia.
- Incluir monitoramento/logging e pipeline de deploy.
- Criar workflow CI/CD para validar lint/testes automaticamente.
