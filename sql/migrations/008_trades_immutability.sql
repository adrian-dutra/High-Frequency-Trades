CREATE OR REPLACE FUNCTION trg_prevent_trades_changes_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Trades sao imutaveis e nao podem ser atualizados ou removidos';
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_trades_update_delete ON trades;

CREATE TRIGGER trg_prevent_trades_update_delete
BEFORE UPDATE OR DELETE ON trades
FOR EACH ROW
EXECUTE FUNCTION trg_prevent_trades_changes_fn();
