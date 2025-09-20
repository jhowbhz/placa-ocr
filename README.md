# Placa OCR API

<img width="1535" height="875" alt="{F40DF6EC-CEFD-421C-BC07-5138CD33C638}" src="https://github.com/user-attachments/assets/8b153aac-6cda-4887-8b44-df94d7ee3058" />

API para **detecção e OCR de placas Mercosul**, com suporte opcional de integração à **APIBrasil**.

---

## 1. Configuração de Ambiente

1. Copie o arquivo de exemplo:
```bash
   cp .env-example .env
````

2. Ajuste as variáveis conforme necessário:

| Variável                        | Descrição                                                 | Padrão                       |
| ------------------------------- | --------------------------------------------------------- | ---------------------------- |
| `PLACAOCR_MODEL_PATH`           | Caminho para o peso YOLO (`.pt`)                          | `artifacts/license-plate.pt` |
| `PLACAOCR_CONFIDENCE_THRESHOLD` | Confiança mínima de detecção                              | `0.25`                       |
| `PLACAOCR_DEVICE`               | Dispositivo de execução (`cpu`, `cuda:0`, etc.)           | `cpu`                        |
| `PLACAOCR_IMAGE_SIZE`           | Tamanho da imagem na inferência (None = padrão do modelo) | `640`                        |

### Integração com APIBrasil (opcional)

| Variável                      | Descrição                 | Padrão                                                           |
| ----------------------------- | ------------------------- | ---------------------------------------------------------------- |
| `PLACAOCR_APIBRASIL_BASE_URL` | Endpoint da consulta      | `https://gateway.apibrasil.io/api/v2/vehicles/base/001/consulta` |
| `PLACAOCR_APIBRASIL_TOKEN`    | Token de acesso           | *(vazio)*                                                        |
| `PLACAOCR_APIBRASIL_TIMEOUT`  | Timeout da requisição (s) | `15`                                                             |

---

## 2. Instalação de Dependências e Dataset

Execute o script de inicialização:

```bash
./init.sh
```

O script realiza:

* Criação/reuso do virtualenv em `.venv`;
* Instalação de dependências (`requirements.txt`);
* Download do dataset Artificial Mercosur License Plates (\~1.52 GB);
* Extração e divisão em `train/val/test` (seed 42);
* Geração do YAML em `data/yolo/mercosur-license-plates.yaml`;
* Treino inicial do YOLOv8 (1 epoch por padrão);
* Salvamento do peso em `artifacts/license-plate.pt`;
* Armazenamento dos runs em `artifacts/runs/`.

### Flags úteis

* `./init.sh --skip-training`: prepara sem treinar (mantém pesos);
* `./init.sh --force-download`: rebaixa e reextrai dataset.

### Variáveis de ambiente de treino

| Variável            | Função              | Padrão             |
| ------------------- | ------------------- | ------------------ |
| `TRAIN_EPOCHS`      | Nº de épocas        | `1`                |
| `TRAIN_BATCH`       | Tamanho do batch    | `16`               |
| `BASE_MODEL`        | Modelo YOLO base    | `yolov8n.pt`       |
| `TRAIN_IMAGE_SIZE`  | Resolução de treino | `640`              |
| `MODEL_OUTPUT_NAME` | Nome do peso final  | `license-plate.pt` |

---

## 3. Executando a API

Após configurar o ambiente e treinar/baixar pesos:

```bash
./start.sh --dev   # modo dev (reload ativo)
./start.sh --prod  # modo prod (multiprocess)
```

* API disponível em: [http://0.0.0.0:8000](http://0.0.0.0:8000)
* Swagger: [http://localhost:8000/docs](http://localhost:8000/docs)
* Redoc: [http://localhost:8000/redoc](http://localhost:8000/redoc)

---

## 4. Exemplo de Resposta (REST)

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

---

## 5. Integração com APIBrasil

1. Configure `PLACAOCR_APIBRASIL_TOKEN` e demais variáveis.

2. A API envia:

   * `tipo`
   * `placa` (detectada ou manual via `placa_manual`)
   * `homolog` (modo de homologação)

3. Caso `homolog=true` e **nenhuma placa seja detectada**, será usada `ABC1234` para retorno de exemplo.

4. O payload completo da APIBrasil é anexado em `data[].veiculo.detalhes`.

---

## Resumo

* Treine ou use pesos prontos de YOLO para detecção de placas Mercosul;
* Use `init.sh` para preparar o ambiente/dataset;
* Rode a API com `start.sh`;
* Integre facilmente com APIBrasil para consulta de veículos.

---
