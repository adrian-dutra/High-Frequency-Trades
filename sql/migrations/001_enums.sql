CREATE TYPE enum_order_side AS ENUM (
    'BUY',
    'SELL'
);

CREATE TYPE enum_order_status AS ENUM (
    'OPEN',
    'PARTIAL',
    'FILLED',
    'CANCELED'
);

CREATE TYPE enum_wallet_movement_type AS ENUM (
    'DEPOSIT',
    'ORDER_LOCK',
    'ORDER_RELEASE',
    'TRADE_DEBIT',
    'TRADE_CREDIT',
    'CANCEL_RELEASE',
    'ADJUSTMENT'
);
