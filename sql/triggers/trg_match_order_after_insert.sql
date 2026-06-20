CREATE TRIGGER trg_match_order_after_insert
AFTER INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION trg_match_order_after_insert_fn();
