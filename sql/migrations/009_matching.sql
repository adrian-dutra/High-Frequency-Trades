CREATE OR REPLACE FUNCTION fn_match_order(p_order_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_incoming_order orders%ROWTYPE;
    v_passive_order orders%ROWTYPE;
    v_buy_order orders%ROWTYPE;
    v_sell_order orders%ROWTYPE;

    v_base_asset_id INTEGER;
    v_quote_asset_id INTEGER;

    v_trade_id BIGINT;
    v_trade_quantity NUMERIC(28,10);
    v_execution_price NUMERIC(28,10);
    v_paid_amount NUMERIC(28,10);
    v_buy_reserved_delta NUMERIC(28,10);
    v_sell_reserved_delta NUMERIC(28,10);
    v_refund_amount NUMERIC(28,10);

    v_buy_old_status enum_order_status;
    v_sell_old_status enum_order_status;
    v_buy_new_status enum_order_status;
    v_sell_new_status enum_order_status;
    v_buy_old_remaining NUMERIC(28,10);
    v_sell_old_remaining NUMERIC(28,10);
    v_buy_new_remaining NUMERIC(28,10);
    v_sell_new_remaining NUMERIC(28,10);
    v_buy_new_reserved NUMERIC(28,10);
    v_sell_new_reserved NUMERIC(28,10);
    v_buy_event_type VARCHAR(30);
    v_sell_event_type VARCHAR(30);

    v_buyer_base_wallet_id BIGINT;
    v_buyer_quote_wallet_id BIGINT;
    v_seller_base_wallet_id BIGINT;
    v_seller_quote_wallet_id BIGINT;

    v_buyer_base_available NUMERIC(28,10);
    v_buyer_base_locked NUMERIC(28,10);
    v_buyer_quote_available NUMERIC(28,10);
    v_buyer_quote_locked NUMERIC(28,10);
    v_seller_base_available NUMERIC(28,10);
    v_seller_base_locked NUMERIC(28,10);
    v_seller_quote_available NUMERIC(28,10);
    v_seller_quote_locked NUMERIC(28,10);
BEGIN
    SELECT *
    INTO v_incoming_order
    FROM orders
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ordem para matching nao encontrada. order_id=%', p_order_id;
    END IF;

    IF v_incoming_order.status NOT IN ('OPEN', 'PARTIAL') THEN
        RETURN;
    END IF;

    SELECT
        base_asset_id,
        quote_asset_id
    INTO
        v_base_asset_id,
        v_quote_asset_id
    FROM markets
    WHERE market_id = v_incoming_order.market_id
      AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Mercado ativo nao encontrado para matching. market_id=%',
            v_incoming_order.market_id;
    END IF;

    WHILE v_incoming_order.remaining_quantity > 0
      AND v_incoming_order.status IN ('OPEN', 'PARTIAL')
    LOOP
        IF v_incoming_order.side = 'BUY' THEN
            SELECT *
            INTO v_passive_order
            FROM orders
            WHERE market_id = v_incoming_order.market_id
              AND side = 'SELL'
              AND status IN ('OPEN', 'PARTIAL')
              AND price <= v_incoming_order.price
              AND user_id <> v_incoming_order.user_id
            ORDER BY price ASC, created_at ASC, order_id ASC
            FOR UPDATE SKIP LOCKED
            LIMIT 1;
        ELSE
            SELECT *
            INTO v_passive_order
            FROM orders
            WHERE market_id = v_incoming_order.market_id
              AND side = 'BUY'
              AND status IN ('OPEN', 'PARTIAL')
              AND price >= v_incoming_order.price
              AND user_id <> v_incoming_order.user_id
            ORDER BY price DESC, created_at ASC, order_id ASC
            FOR UPDATE SKIP LOCKED
            LIMIT 1;
        END IF;

        IF NOT FOUND THEN
            EXIT;
        END IF;

        IF v_incoming_order.side = 'BUY' THEN
            v_buy_order := v_incoming_order;
            v_sell_order := v_passive_order;
        ELSE
            v_buy_order := v_passive_order;
            v_sell_order := v_incoming_order;
        END IF;

        v_trade_quantity := LEAST(
            v_buy_order.remaining_quantity,
            v_sell_order.remaining_quantity
        );
        v_execution_price := v_passive_order.price;
        v_paid_amount := v_execution_price * v_trade_quantity;
        v_buy_reserved_delta := v_buy_order.price * v_trade_quantity;
        v_sell_reserved_delta := v_trade_quantity;
        v_refund_amount := v_buy_reserved_delta - v_paid_amount;

        IF v_trade_quantity <= 0 THEN
            RAISE EXCEPTION 'Quantidade de trade invalida no matching. order_id=%', p_order_id;
        END IF;

        IF v_refund_amount < 0 THEN
            RAISE EXCEPTION 'Devolucao negativa no matching. buy_order_id=%, refund=%',
                v_buy_order.order_id, v_refund_amount;
        END IF;

        INSERT INTO wallets (
            user_id,
            asset_id,
            available_balance,
            locked_balance
        )
        VALUES
            (v_buy_order.user_id, v_base_asset_id, 0, 0),
            (v_buy_order.user_id, v_quote_asset_id, 0, 0),
            (v_sell_order.user_id, v_base_asset_id, 0, 0),
            (v_sell_order.user_id, v_quote_asset_id, 0, 0)
        ON CONFLICT (user_id, asset_id) DO NOTHING;

        SELECT wallet_id
        INTO v_buyer_base_wallet_id
        FROM wallets
        WHERE user_id = v_buy_order.user_id
          AND asset_id = v_base_asset_id;

        SELECT wallet_id
        INTO v_buyer_quote_wallet_id
        FROM wallets
        WHERE user_id = v_buy_order.user_id
          AND asset_id = v_quote_asset_id;

        SELECT wallet_id
        INTO v_seller_base_wallet_id
        FROM wallets
        WHERE user_id = v_sell_order.user_id
          AND asset_id = v_base_asset_id;

        SELECT wallet_id
        INTO v_seller_quote_wallet_id
        FROM wallets
        WHERE user_id = v_sell_order.user_id
          AND asset_id = v_quote_asset_id;

        PERFORM 1
        FROM wallets
        WHERE wallet_id IN (
            v_buyer_base_wallet_id,
            v_buyer_quote_wallet_id,
            v_seller_base_wallet_id,
            v_seller_quote_wallet_id
        )
        ORDER BY wallet_id
        FOR UPDATE;

        SELECT
            available_balance,
            locked_balance
        INTO
            v_buyer_quote_available,
            v_buyer_quote_locked
        FROM wallets
        WHERE wallet_id = v_buyer_quote_wallet_id;

        SELECT
            available_balance,
            locked_balance
        INTO
            v_seller_base_available,
            v_seller_base_locked
        FROM wallets
        WHERE wallet_id = v_seller_base_wallet_id;

        IF v_buyer_quote_locked < v_buy_reserved_delta THEN
            RAISE EXCEPTION 'Saldo bloqueado insuficiente na carteira quote do comprador. order_id=%, bloqueado=%, necessario=%',
                v_buy_order.order_id, v_buyer_quote_locked, v_buy_reserved_delta;
        END IF;

        IF v_seller_base_locked < v_sell_reserved_delta THEN
            RAISE EXCEPTION 'Saldo bloqueado insuficiente na carteira base do vendedor. order_id=%, bloqueado=%, necessario=%',
                v_sell_order.order_id, v_seller_base_locked, v_sell_reserved_delta;
        END IF;

        INSERT INTO trades (
            market_id,
            buy_order_id,
            sell_order_id,
            buyer_user_id,
            seller_user_id,
            price,
            quantity
        )
        VALUES (
            v_incoming_order.market_id,
            v_buy_order.order_id,
            v_sell_order.order_id,
            v_buy_order.user_id,
            v_sell_order.user_id,
            v_execution_price,
            v_trade_quantity
        )
        RETURNING trade_id INTO v_trade_id;

        UPDATE wallets
        SET
            available_balance = available_balance + v_refund_amount,
            locked_balance = locked_balance - v_buy_reserved_delta,
            updated_at = clock_timestamp()
        WHERE wallet_id = v_buyer_quote_wallet_id
        RETURNING
            available_balance,
            locked_balance
        INTO
            v_buyer_quote_available,
            v_buyer_quote_locked;

        UPDATE wallets
        SET
            available_balance = available_balance + v_trade_quantity,
            updated_at = clock_timestamp()
        WHERE wallet_id = v_buyer_base_wallet_id
        RETURNING
            available_balance,
            locked_balance
        INTO
            v_buyer_base_available,
            v_buyer_base_locked;

        UPDATE wallets
        SET
            locked_balance = locked_balance - v_sell_reserved_delta,
            updated_at = clock_timestamp()
        WHERE wallet_id = v_seller_base_wallet_id
        RETURNING
            available_balance,
            locked_balance
        INTO
            v_seller_base_available,
            v_seller_base_locked;

        UPDATE wallets
        SET
            available_balance = available_balance + v_paid_amount,
            updated_at = clock_timestamp()
        WHERE wallet_id = v_seller_quote_wallet_id
        RETURNING
            available_balance,
            locked_balance
        INTO
            v_seller_quote_available,
            v_seller_quote_locked;

        v_buy_old_status := v_buy_order.status;
        v_sell_old_status := v_sell_order.status;
        v_buy_old_remaining := v_buy_order.remaining_quantity;
        v_sell_old_remaining := v_sell_order.remaining_quantity;

        v_buy_new_remaining := v_buy_order.remaining_quantity - v_trade_quantity;
        v_sell_new_remaining := v_sell_order.remaining_quantity - v_trade_quantity;
        v_buy_new_reserved := v_buy_order.reserved_amount - v_buy_reserved_delta;
        v_sell_new_reserved := v_sell_order.reserved_amount - v_sell_reserved_delta;

        IF v_buy_new_remaining = 0 THEN
            v_buy_new_status := 'FILLED';
            v_buy_new_reserved := GREATEST(v_buy_new_reserved, 0);
            v_buy_event_type := 'ORDER_FILLED';
        ELSE
            v_buy_new_status := 'PARTIAL';
            v_buy_event_type := 'ORDER_PARTIALLY_FILLED';
        END IF;

        IF v_sell_new_remaining = 0 THEN
            v_sell_new_status := 'FILLED';
            v_sell_new_reserved := GREATEST(v_sell_new_reserved, 0);
            v_sell_event_type := 'ORDER_FILLED';
        ELSE
            v_sell_new_status := 'PARTIAL';
            v_sell_event_type := 'ORDER_PARTIALLY_FILLED';
        END IF;

        IF v_buy_new_reserved < 0 OR v_sell_new_reserved < 0 THEN
            RAISE EXCEPTION 'Reserva negativa calculada no matching. buy_reserved=%, sell_reserved=%',
                v_buy_new_reserved, v_sell_new_reserved;
        END IF;

        UPDATE orders
        SET
            remaining_quantity = v_buy_new_remaining,
            reserved_amount = v_buy_new_reserved,
            status = v_buy_new_status,
            updated_at = clock_timestamp()
        WHERE order_id = v_buy_order.order_id;

        UPDATE orders
        SET
            remaining_quantity = v_sell_new_remaining,
            reserved_amount = v_sell_new_reserved,
            status = v_sell_new_status,
            updated_at = clock_timestamp()
        WHERE order_id = v_sell_order.order_id;

        INSERT INTO wallet_movements (
            wallet_id,
            user_id,
            asset_id,
            order_id,
            trade_id,
            movement_type,
            amount,
            available_balance_after,
            locked_balance_after,
            description
        )
        VALUES (
            v_buyer_quote_wallet_id,
            v_buy_order.user_id,
            v_quote_asset_id,
            v_buy_order.order_id,
            v_trade_id,
            'TRADE_DEBIT',
            -v_paid_amount,
            v_buyer_quote_available,
            v_buyer_quote_locked,
            'Debito do comprador em moeda de cotacao pelo trade'
        );

        INSERT INTO wallet_movements (
            wallet_id,
            user_id,
            asset_id,
            order_id,
            trade_id,
            movement_type,
            amount,
            available_balance_after,
            locked_balance_after,
            description
        )
        VALUES (
            v_buyer_base_wallet_id,
            v_buy_order.user_id,
            v_base_asset_id,
            v_buy_order.order_id,
            v_trade_id,
            'TRADE_CREDIT',
            v_trade_quantity,
            v_buyer_base_available,
            v_buyer_base_locked,
            'Credito do comprador em ativo base pelo trade'
        );

        INSERT INTO wallet_movements (
            wallet_id,
            user_id,
            asset_id,
            order_id,
            trade_id,
            movement_type,
            amount,
            available_balance_after,
            locked_balance_after,
            description
        )
        VALUES (
            v_seller_base_wallet_id,
            v_sell_order.user_id,
            v_base_asset_id,
            v_sell_order.order_id,
            v_trade_id,
            'TRADE_DEBIT',
            -v_trade_quantity,
            v_seller_base_available,
            v_seller_base_locked,
            'Debito do vendedor em ativo base pelo trade'
        );

        INSERT INTO wallet_movements (
            wallet_id,
            user_id,
            asset_id,
            order_id,
            trade_id,
            movement_type,
            amount,
            available_balance_after,
            locked_balance_after,
            description
        )
        VALUES (
            v_seller_quote_wallet_id,
            v_sell_order.user_id,
            v_quote_asset_id,
            v_sell_order.order_id,
            v_trade_id,
            'TRADE_CREDIT',
            v_paid_amount,
            v_seller_quote_available,
            v_seller_quote_locked,
            'Credito do vendedor em moeda de cotacao pelo trade'
        );

        IF v_refund_amount > 0 THEN
            INSERT INTO wallet_movements (
                wallet_id,
                user_id,
                asset_id,
                order_id,
                trade_id,
                movement_type,
                amount,
                available_balance_after,
                locked_balance_after,
                description
            )
            VALUES (
                v_buyer_quote_wallet_id,
                v_buy_order.user_id,
                v_quote_asset_id,
                v_buy_order.order_id,
                v_trade_id,
                'ORDER_RELEASE',
                v_refund_amount,
                v_buyer_quote_available,
                v_buyer_quote_locked,
                'Devolucao de diferenca da ordem BUY executada abaixo do preco limite'
            );
        END IF;

        INSERT INTO order_audit_log (
            order_id,
            trade_id,
            old_status,
            new_status,
            old_remaining_quantity,
            new_remaining_quantity,
            event_type,
            reason
        )
        VALUES (
            v_buy_order.order_id,
            v_trade_id,
            v_buy_old_status,
            v_buy_new_status,
            v_buy_old_remaining,
            v_buy_new_remaining,
            v_buy_event_type,
            'Ordem BUY atualizada pelo matching'
        );

        INSERT INTO order_audit_log (
            order_id,
            trade_id,
            old_status,
            new_status,
            old_remaining_quantity,
            new_remaining_quantity,
            event_type,
            reason
        )
        VALUES (
            v_sell_order.order_id,
            v_trade_id,
            v_sell_old_status,
            v_sell_new_status,
            v_sell_old_remaining,
            v_sell_new_remaining,
            v_sell_event_type,
            'Ordem SELL atualizada pelo matching'
        );

        IF v_incoming_order.side = 'BUY' THEN
            v_incoming_order.remaining_quantity := v_buy_new_remaining;
            v_incoming_order.reserved_amount := v_buy_new_reserved;
            v_incoming_order.status := v_buy_new_status;
        ELSE
            v_incoming_order.remaining_quantity := v_sell_new_remaining;
            v_incoming_order.reserved_amount := v_sell_new_reserved;
            v_incoming_order.status := v_sell_new_status;
        END IF;
    END LOOP;

    RETURN;
END;
$$;

DROP TRIGGER IF EXISTS trg_match_order_after_insert ON orders;

CREATE OR REPLACE FUNCTION trg_match_order_after_insert_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_match_order(NEW.order_id);

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_match_order_after_insert
AFTER INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION trg_match_order_after_insert_fn();
