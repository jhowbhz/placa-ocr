# Placa OCR API
<img width="1624" height="868" alt="{C9194544-F3E1-4EB8-8FF6-EA1AA7A85BF3}" src="https://github.com/user-attachments/assets/26f36790-f47b-4417-97e4-097f4ef3cbcd" />

API FastAPI para deteccao de placas Mercosul. O repositorio inclui script de inicializacao completa (`init.sh`), utilitarios para subir a API (`start.sh`) e configuracoes prontas para treino utilizando o dataset **Artificial Mercosur License Plates** (CC BY 4.0).

## 1. Configuracao de ambiente

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

**Integração APIBrasil (opcional):**

| Variavel | Descricao | Padrao |
| --- | --- | --- |
| `PLACAOCR_APIBRASIL_BASE_URL` | Endpoint do recurso de consulta | `https://gateway.apibrasil.io/api/v2/vehicles/base/001/consulta` |
| `PLACAOCR_APIBRASIL_TOKEN` | Token/Bearer utilizado pela APIBrasil | *(vazio)* |
| `PLACAOCR_APIBRASIL_TIMEOUT` | Timeout da chamada em segundos | `15` |

## 2. Instalar dependencias e preparar dataset

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

## 3. Executar a API

Depois que o ambiente estiver configurado e o peso disponivel:

```bash
./start.sh --dev   # uvicorn com reload
./start.sh --prod  # uvicorn multiprocess (sem reload)
```

Por padrao o servidor sobe em `http://0.0.0.0:8000`. A documentacao Swagger fica em `http://localhost:8000/docs` e o Redoc em `http://localhost:8000/redoc`.

## 4. REST client

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
          "exemplo": "payload retornado pela APIBrasil em modo homolog"
        }
      }
    }
  ]
}
```

## 5. Integracao com APIBrasil

- Configure `PLACAOCR_APIBRASIL_TOKEN` (e demais variaveis) para habilitar a chamada.
- A API envia `tipo`, `placa` (derivada da imagem ou do campo `placa_manual`) e `homolog`.
- Se `homolog=true` e nenhuma placa for detectada, o sistema utiliza `ABC1234` para recuperar o payload de exemplo.
- O retorno completo da APIBrasil e anexado em `data[].veiculo.detalhes`.