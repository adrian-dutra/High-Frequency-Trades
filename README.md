# High-Frequency-Trades

HFT Simulator - Order Book de Criptomoedas.

Projeto academico da disciplina de Laboratorio de Banco de Dados. O sistema usa
PostgreSQL 15+ como nucleo da aplicacao para simular uma exchange simples de
criptomoedas: usuarios possuem carteiras, criam ordens de compra e venda, o
banco bloqueia saldo, executa matching, gera trades, audita alteracoes e mantem
candles OHLCV de 1 minuto.

## O que foi implementado

- Schema relacional para usuarios, ativos, mercados, carteiras, ordens, trades,
  movimentacoes de carteira, auditoria de ordens e candles.
- ENUMs para lado da ordem, status da ordem e tipo de movimentacao de carteira.
- Constraints, chaves primarias, chaves estrangeiras, checks e indices do order
  book.
- Procedures para deposito, criacao de ordem e cancelamento.
- Matching automatico por trigger apos inserir ordem.
- Imutabilidade de trades por trigger.
- Atualizacao automatica de candles apos novos trades.
- Views para resumo de mercado, historico de trades e ranking de traders.
- Loader Python hibrido para gerar ordens reais e popular candles historicos em
  massa ate atingir o tamanho alvo do banco.

## Requisitos

- Docker
- Docker Compose
- Python 3.12+
- Arquivo `.env` criado a partir de `.env.exemple`

## Configurar ambiente

Crie o arquivo `.env` local:

```bash
cp .env.exemple .env
```

Edite os valores conforme o seu ambiente. Exemplo:

```env
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=hft_simulator
POSTGRES_USER=hft_user
POSTGRES_PASSWORD=change_me
```

## Subir o PostgreSQL

```bash
docker compose up -d
```

Confira se o container esta de pe:

```bash
docker compose ps
```

O projeto usa o container `hft-postgres`. Para entrar no `psql`:

```bash
docker exec -it hft-postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

## Recriar o banco do zero

Para limpar o schema `public`:

```bash
docker exec -i hft-postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < sql/00_drop.sql
```

Depois aplique todos os scripts SQL organizados:

```bash
bash sql/apply_order.txt
```

O arquivo `sql/apply_order.txt` aplica os objetos na ordem correta:

1. ENUMs
2. tabelas
3. indices
4. seed base
5. procedures
6. functions
7. triggers
8. views

## Validar o banco

Depois de recriar o banco, rode as validacoes principais:

```bash
for f in sql/validation/*.sql; do
  echo "Validando $f"
  docker exec -i hft-postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < "$f"
done
```

## Preparar o Python

Crie e ative o ambiente virtual:

```bash
python -m venv .venv
source .venv/bin/activate
```

Instale as dependencias:

```bash
pip install -r requirements.txt
```

## Rodar o loader

O loader atual fica em `loader/load_data.py` e possui quatro modos:

- `warmup`: garante usuarios, wallets e saldos iniciais altos;
- `real-orders`: cria ordens reais usando `CALL sp_place_order`;
- `bulk-candles`: popula candles historicos em massa usando `COPY`;
- `full`: executa warmup, ordens reais e bulk-candles.

Comando recomendado para carga completa:

```bash
python loader/load_data.py \
  --mode full \
  --target-db-mb 700 \
  --real-orders 5000 \
  --workers 4 \
  --batch-size 1 \
  --candle-markets 80
```

Para um teste pequeno antes da carga final:

```bash
python loader/load_data.py \
  --mode full \
  --target-db-mb 20 \
  --real-orders 200 \
  --workers 4 \
  --batch-size 1 \
  --candle-markets 5
```

Ao final, o loader imprime:

- tamanho atual do banco;
- total de usuarios;
- total de mercados;
- total de ordens;
- total de trades;
- total de candles;
- total de movimentacoes de carteira;
- total de auditorias de ordem;
- tempo total de execucao.

## Conferir tamanho e contagens

```bash
docker exec -it hft-postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

Dentro do `psql`:

```sql
SELECT pg_size_pretty(pg_database_size(current_database()));

SELECT
  (SELECT COUNT(*) FROM users) AS users,
  (SELECT COUNT(*) FROM markets) AS markets,
  (SELECT COUNT(*) FROM orders) AS orders,
  (SELECT COUNT(*) FROM trades) AS trades,
  (SELECT COUNT(*) FROM candles_1m) AS candles,
  (SELECT COUNT(*) FROM wallet_movements) AS wallet_movements,
  (SELECT COUNT(*) FROM order_audit_log) AS order_audit_log;
```

## Parar o banco

```bash
docker compose down
```

Para remover tambem o volume local do PostgreSQL:

```bash
docker compose down -v
```
