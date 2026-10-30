START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261029104432_Promotions') THEN
    ALTER TABLE orders ADD discounts jsonb NOT NULL DEFAULT ('[]'::jsonb);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261029104432_Promotions') THEN
    ALTER TABLE order_lines ADD combo_id character varying(40);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261029104432_Promotions') THEN
    ALTER TABLE order_lines ADD combo_items jsonb NOT NULL DEFAULT ('[]'::jsonb);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261029104432_Promotions') THEN
    ALTER TABLE order_lines ADD discount numeric(14,2) NOT NULL DEFAULT 0.0;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261029104432_Promotions') THEN
    ALTER TABLE order_lines ADD discount_label character varying(80);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261029104432_Promotions') THEN
    ALTER TABLE order_lines ADD promotion_id character varying(40);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261029104432_Promotions') THEN
    ALTER TABLE discount_offers ADD ends_on date;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261029104432_Promotions') THEN
    ALTER TABLE discount_offers ADD starts_on date;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261029104432_Promotions') THEN
    ALTER TABLE discount_offers ADD usage_limit integer;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261029104432_Promotions') THEN
    ALTER TABLE discount_offers ADD used_count integer NOT NULL DEFAULT 0;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261029104432_Promotions') THEN
    CREATE TABLE promotions (
        id character varying(40) NOT NULL,
        kind character varying(20) NOT NULL,
        title character varying(60) NOT NULL,
        description character varying(300) NOT NULL,
        image text NOT NULL,
        starts_on date,
        ends_on date,
        is_active boolean NOT NULL,
        usage_limit integer,
        used_count integer NOT NULL,
        sort_order integer NOT NULL,
        discount_type character varying(20) NOT NULL,
        discount_value integer NOT NULL,
        combo_price numeric(14,2),
        created_at timestamp with time zone NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        CONSTRAINT pk_promotions PRIMARY KEY (id),
        CONSTRAINT ck_promotions_discount_value CHECK (discount_value >= 0),
        CONSTRAINT ck_promotions_used_count CHECK (used_count >= 0)
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261029104432_Promotions') THEN
    CREATE TABLE promotion_items (
        promotion_id character varying(40) NOT NULL,
        item_id character varying(60) NOT NULL,
        quantity integer NOT NULL,
        sort_order integer NOT NULL,
        CONSTRAINT pk_promotion_items PRIMARY KEY (promotion_id, item_id),
        CONSTRAINT ck_promotion_items_quantity CHECK (quantity between 1 and 10),
        CONSTRAINT fk_promotion_items_menu_items_item_id FOREIGN KEY (item_id) REFERENCES menu_items (id) ON DELETE RESTRICT,
        CONSTRAINT fk_promotion_items_promotions_promotion_id FOREIGN KEY (promotion_id) REFERENCES promotions (id) ON DELETE CASCADE
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261029104432_Promotions') THEN
    ALTER TABLE discount_offers ADD CONSTRAINT ck_discount_offers_used_count CHECK (used_count >= 0);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261029104432_Promotions') THEN
    CREATE INDEX ix_promotion_items_item_id ON promotion_items (item_id);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261029104432_Promotions') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261029104432_Promotions', '10.0.13');
    END IF;
END $EF$;
COMMIT;

