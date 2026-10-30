START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261030092116_WifiRestriction') THEN
    ALTER TABLE restaurant_settings ADD wifi_restrict_takeaway boolean NOT NULL DEFAULT FALSE;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261030092116_WifiRestriction') THEN
    ALTER TABLE restaurant_settings ADD wifi_restriction_enabled boolean NOT NULL DEFAULT FALSE;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261030092116_WifiRestriction') THEN
    ALTER TABLE restaurant_settings ADD wifi_ssid character varying(32) NOT NULL DEFAULT '';
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261030092116_WifiRestriction') THEN
    CREATE TABLE authorized_networks (
        id bigint GENERATED ALWAYS AS IDENTITY,
        settings_id integer NOT NULL,
        value character varying(253) NOT NULL,
        label character varying(60) NOT NULL,
        created_at timestamp with time zone NOT NULL,
        created_by_name character varying(150) NOT NULL,
        CONSTRAINT pk_authorized_networks PRIMARY KEY (id),
        CONSTRAINT fk_authorized_networks_restaurant_settings_settings_id FOREIGN KEY (settings_id) REFERENCES restaurant_settings (id) ON DELETE CASCADE
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261030092116_WifiRestriction') THEN
    CREATE TABLE guest_sessions (
        id uuid NOT NULL,
        settings_id integer NOT NULL,
        table_number integer,
        status character varying(20) NOT NULL,
        created_at timestamp with time zone NOT NULL,
        expires_at timestamp with time zone NOT NULL,
        verified_at timestamp with time zone,
        status_changed_at timestamp with time zone NOT NULL,
        CONSTRAINT pk_guest_sessions PRIMARY KEY (id),
        CONSTRAINT fk_guest_sessions_restaurant_settings_settings_id FOREIGN KEY (settings_id) REFERENCES restaurant_settings (id) ON DELETE CASCADE,
        CONSTRAINT fk_guest_sessions_restaurant_tables_table_number FOREIGN KEY (table_number) REFERENCES restaurant_tables (number) ON DELETE SET NULL
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261030092116_WifiRestriction') THEN
    CREATE UNIQUE INDEX ix_authorized_networks_settings_id_value ON authorized_networks (settings_id, value);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261030092116_WifiRestriction') THEN
    CREATE INDEX ix_guest_sessions_expires_at ON guest_sessions (expires_at);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261030092116_WifiRestriction') THEN
    CREATE INDEX ix_guest_sessions_settings_id ON guest_sessions (settings_id);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261030092116_WifiRestriction') THEN
    CREATE INDEX ix_guest_sessions_table_number_status ON guest_sessions (table_number, status);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261030092116_WifiRestriction') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261030092116_WifiRestriction', '10.0.13');
    END IF;
END $EF$;
COMMIT;

