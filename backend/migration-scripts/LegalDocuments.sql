START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261107191042_LegalDocuments') THEN
    CREATE TABLE legal_documents (
        id bigint GENERATED ALWAYS AS IDENTITY,
        settings_id integer NOT NULL,
        kind character varying(20) NOT NULL,
        version integer NOT NULL,
        title character varying(120) NOT NULL,
        body character varying(60000) NOT NULL,
        change_summary character varying(300) NOT NULL,
        requires_reacceptance boolean NOT NULL,
        status character varying(20) NOT NULL,
        created_at timestamp with time zone NOT NULL,
        created_by_name character varying(150) NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_name character varying(150) NOT NULL,
        published_at timestamp with time zone,
        published_by_name character varying(150) NOT NULL,
        retired_at timestamp with time zone,
        CONSTRAINT pk_legal_documents PRIMARY KEY (id),
        CONSTRAINT ck_legal_documents_version CHECK (version >= 1),
        CONSTRAINT fk_legal_documents_restaurant_settings_settings_id FOREIGN KEY (settings_id) REFERENCES restaurant_settings (id) ON DELETE CASCADE
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261107191042_LegalDocuments') THEN
    CREATE TABLE legal_acceptances (
        id bigint GENERATED ALWAYS AS IDENTITY,
        settings_id integer NOT NULL,
        guest_session_id uuid NOT NULL,
        table_number integer,
        document_id bigint NOT NULL,
        kind character varying(20) NOT NULL,
        version integer NOT NULL,
        accepted boolean NOT NULL,
        accepted_at timestamp with time zone NOT NULL,
        CONSTRAINT pk_legal_acceptances PRIMARY KEY (id),
        CONSTRAINT fk_legal_acceptances_guest_sessions_guest_session_id FOREIGN KEY (guest_session_id) REFERENCES guest_sessions (id) ON DELETE RESTRICT,
        CONSTRAINT fk_legal_acceptances_legal_documents_document_id FOREIGN KEY (document_id) REFERENCES legal_documents (id) ON DELETE RESTRICT,
        CONSTRAINT fk_legal_acceptances_restaurant_settings_settings_id FOREIGN KEY (settings_id) REFERENCES restaurant_settings (id) ON DELETE CASCADE
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261107191042_LegalDocuments') THEN
    CREATE INDEX ix_legal_acceptances_document_id ON legal_acceptances (document_id);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261107191042_LegalDocuments') THEN
    CREATE UNIQUE INDEX ix_legal_acceptances_guest_session_id_document_id ON legal_acceptances (guest_session_id, document_id);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261107191042_LegalDocuments') THEN
    CREATE INDEX ix_legal_acceptances_settings_id_accepted_at ON legal_acceptances (settings_id, accepted_at);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261107191042_LegalDocuments') THEN
    CREATE UNIQUE INDEX ix_legal_documents_one_published ON legal_documents (settings_id, kind) WHERE status = 'published';
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261107191042_LegalDocuments') THEN
    CREATE UNIQUE INDEX ix_legal_documents_settings_id_kind_version ON legal_documents (settings_id, kind, version);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261107191042_LegalDocuments') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261107191042_LegalDocuments', '10.0.13');
    END IF;
END $EF$;
COMMIT;

