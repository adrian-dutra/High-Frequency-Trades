CREATE OR REPLACE FUNCTION trg_prevent_trades_changes_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Trades sao imutaveis e nao podem ser atualizados ou removidos';
END;
$$;
