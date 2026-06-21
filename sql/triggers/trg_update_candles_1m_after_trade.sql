DROP TRIGGER IF EXISTS trg_update_candles_1m_after_trade ON trades;

CREATE TRIGGER trg_update_candles_1m_after_trade
AFTER INSERT ON trades
FOR EACH ROW
EXECUTE FUNCTION trg_update_candles_1m_after_trade_fn();
