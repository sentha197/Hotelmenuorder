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

START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261025100214_DishBanner') THEN
    ALTER TABLE menu_items ADD is_featured boolean NOT NULL DEFAULT FALSE;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261025100214_DishBanner') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261025100214_DishBanner', '10.0.13');
    END IF;
END $EF$;
COMMIT;

START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261025111552_StoredImages') THEN
    CREATE TABLE stored_images (
        id uuid NOT NULL,
        content_type character varying(100) NOT NULL,
        source_content_type character varying(100) NOT NULL,
        width integer NOT NULL,
        height integer NOT NULL,
        data bytea NOT NULL,
        created_at timestamp with time zone NOT NULL,
        CONSTRAINT pk_stored_images PRIMARY KEY (id)
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261025111552_StoredImages') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261025111552_StoredImages', '10.0.13');
    END IF;
END $EF$;
COMMIT;

START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261027182035_StoredImageKind') THEN
    ALTER TABLE stored_images ADD kind character varying(20) NOT NULL DEFAULT 'dish';
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261027182035_StoredImageKind') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261027182035_StoredImageKind', '10.0.13');
    END IF;
END $EF$;
COMMIT;

