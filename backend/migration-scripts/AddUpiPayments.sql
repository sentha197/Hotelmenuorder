START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261025094603_AddUpiPayments') THEN
    ALTER TABLE restaurant_settings ADD upi_enabled boolean NOT NULL DEFAULT FALSE;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261025094603_AddUpiPayments') THEN
    ALTER TABLE restaurant_settings ADD upi_id character varying(100) NOT NULL DEFAULT '';
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261025094603_AddUpiPayments') THEN
    ALTER TABLE restaurant_settings ADD upi_payee_name character varying(60) NOT NULL DEFAULT '';
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261025094603_AddUpiPayments') THEN
    ALTER TABLE restaurant_settings ADD upi_qr_image character varying(500) NOT NULL DEFAULT '';
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261025094603_AddUpiPayments') THEN
    ALTER TABLE restaurant_settings ADD upi_verification_mode character varying(20) NOT NULL DEFAULT 'manual';
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261025094603_AddUpiPayments') THEN
    ALTER TABLE payments ADD claimed_at timestamp with time zone;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261025094603_AddUpiPayments') THEN
    CREATE UNIQUE INDEX ix_payments_upi_reference ON payments (reference) WHERE provider = 'UPI direct' and status = 'succeeded';
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261025094603_AddUpiPayments') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261025094603_AddUpiPayments', '10.0.13');
    END IF;
END $EF$;
COMMIT;

