# High-Frequency-Trades

HFT Simulator - Order Book de Criptomoedas.

Projeto academico para a disciplina de Laboratorio de Banco de Dados, usando
PostgreSQL 15+ como banco obrigatorio.

## Estrutura inicial

- `docker-compose.yml`: ambiente local com PostgreSQL 15.
- `sql/`: scripts SQL do schema, seeds, funcoes, triggers e views.
- `loader/`: scripts de carga concorrente.
- `docs/`: documentacao de projeto e decisoes.
- `evidence/`: evidencias de execucao, testes e resultados.

## Subir o banco

Crie o arquivo `.env` local a partir do exemplo:

```bash
cp .env.exemple .env
```

Edite `POSTGRES_PASSWORD` no `.env` antes de subir o banco.

```bash
docker compose up -d
```

Verificar se o container esta saudavel:

```bash
docker compose ps
```

Conectar no PostgreSQL pelo `psql` dentro do container:

```bash
docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
```

Parar o ambiente:

```bash
docker compose down
```
