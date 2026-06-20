CREATE TABLE users (
    user_id BIGSERIAL PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    email VARCHAR(160) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT chk_users_name_not_empty
        CHECK (trim(name) <> ''),

    CONSTRAINT chk_users_email_not_empty
        CHECK (trim(email) <> ''),

    CONSTRAINT uq_users_email
        UNIQUE (email)
);
