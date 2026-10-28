START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261028101819_GatewayPayments') THEN
    ALTER TABLE payments ADD expires_at timestamp with time zone;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261028101819_GatewayPayments') THEN
    ALTER TABLE payments ADD provider_payment_id character varying(64);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261028101819_GatewayPayments') THEN
    CREATE INDEX ix_payments_provider_order_id ON payments (provider_order_id) WHERE provider_order_id is not null;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261028101819_GatewayPayments') THEN
    CREATE UNIQUE INDEX ix_payments_provider_provider_payment_id ON payments (provider, provider_payment_id) WHERE provider_payment_id is not null;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261028101819_GatewayPayments') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261028101819_GatewayPayments', '10.0.13');
    END IF;
END $EF$;
COMMIT;

