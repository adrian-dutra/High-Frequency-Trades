# High-Frequency-Trades

HFT Simulator - Order Book de Criptomoedas.

Projeto academico para a disciplina de Laboratorio de Banco de Dados, usando
PostgreSQL 15+ como banco obrigatorio.

## Requisitos

- Docker
- Docker Compose
- Arquivo `.env` criado a partir de `.env.exemple`

## Configurar ambiente

Crie o arquivo `.env` local:

```bash
cp .env.exemple .env
```

Edite o valor de `POSTGRES_PASSWORD` no `.env` antes de subir o banco.

Exemplo esperado:

```env
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=hft_simulator
POSTGRES_USER=hft_user
POSTGRES_PASSWORD=change_me
```

## Subir o banco

```bash
docker compose up -d
```

Verifique se o container esta saudavel:

```bash
docker compose ps
```

Entrar no `psql` dentro do container:

```bash
docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
```

## Aplicar os scripts SQL organizados

Os scripts SQL estao organizados por tipo em `sql/`:

```text
sql/enums/
sql/tables/
sql/indexes/
sql/seed/
sql/procedures/
sql/functions/
sql/triggers/
sql/validation/
```

Para criar a estrutura principal em um banco vazio, aplique os arquivos nesta ordem:

```bash
for f in \
  sql/enums/*.sql \
  sql/tables/*.sql \
  sql/indexes/*.sql \
  sql/seed/*.sql \
  sql/procedures/*.sql \
  sql/functions/*.sql \
  sql/triggers/*.sql
do
  echo "Aplicando $f"
  docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < "$f"
done
```

## Validar a seed base

Depois de aplicar os scripts SQL, rode:

```bash
docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < sql/validation/006_seed_base_validation.sql
```

Essa validacao confere:

- total de assets;
- total de markets;
- total de usuarios;
- total de wallets;
- total de movimentacoes iniciais;
- carteiras duplicadas;
- saldos negativos;
- wallets sem deposito inicial;
- soma de saldo disponivel por asset.

## Parar o banco

```bash
docker compose down
```

Para remover tambem o volume local do PostgreSQL:

```bash
docker compose down -v
```
