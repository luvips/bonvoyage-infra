-- ============================================================
--  BON VOYAGE — Schema
--  Tablas únicamente
--  PostgreSQL 16
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
--  MÓDULO DE USUARIOS
-- ============================================================

-- Catálogo de avatares disponibles en la app
CREATE TABLE IF NOT EXISTS avatars (
    avatar_id   SERIAL        PRIMARY KEY,
    name        VARCHAR(50)   NOT NULL UNIQUE,
    image_url   TEXT          NOT NULL,
    is_active   BOOLEAN       NOT NULL DEFAULT TRUE
);

-- Tabla principal de usuarios
CREATE TABLE IF NOT EXISTS users (
    user_id     UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    email       VARCHAR(255)  NOT NULL UNIQUE,
    first_name  VARCHAR(255)  NOT NULL,
    last_name   VARCHAR(255)  NOT NULL,
    avatar_id   INTEGER       REFERENCES avatars(avatar_id) ON DELETE SET NULL,
    role        VARCHAR(20)   NOT NULL DEFAULT 'USER'
                    CHECK (role IN ('USER', 'ADMIN')),
    status      VARCHAR(20)   NOT NULL DEFAULT 'ACTIVE'
                    CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')),
    created_at  TIMESTAMP     NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP     NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMP     DEFAULT NULL   -- soft delete; NULL = activo
);

-- Identidades por proveedor (LOCAL, GOOGLE, APPLE)
-- Relación 1:N: un usuario puede tener varias identidades
CREATE TABLE IF NOT EXISTS user_identities (
    identity_id     UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID          NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    provider        VARCHAR(50)   NOT NULL CHECK (provider IN ('LOCAL', 'GOOGLE', 'APPLE')),
    provider_id     VARCHAR(255),
    password_hash   VARCHAR(255),
    updated_at      TIMESTAMP     NOT NULL DEFAULT NOW(),

    UNIQUE (user_id, provider),
    UNIQUE (provider, provider_id),

    CONSTRAINT chk_local_password
        CHECK (provider <> 'LOCAL' OR password_hash IS NOT NULL),
    CONSTRAINT chk_external_provider_id
        CHECK (provider = 'LOCAL' OR provider_id IS NOT NULL)
);

-- Preferencias personalizadas del usuario (relación 1:1 con users)
-- La opcionalidad (0..1) se justifica: un usuario puede no haber
-- configurado preferencias aún después de registrarse
CREATE TABLE IF NOT EXISTS user_preferences (
    preference_id        UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID         NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    budget_range         JSONB,
    dietary_restrictions JSONB,
    interests            JSONB,
    preferred_currency   VARCHAR(10)  NOT NULL DEFAULT 'USD',
    preferred_language   VARCHAR(5)   NOT NULL DEFAULT 'es',
    email_preferences    JSONB,
    updated_at           TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- Historial de viajes completados por el usuario
CREATE TABLE IF NOT EXISTS user_travel_history (
    history_id  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID          NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    trip_id     UUID,                          -- NULL si el viaje fue importado manualmente
    destination VARCHAR(255)  NOT NULL,
    country     VARCHAR(100)  NOT NULL,
    travel_date DATE,
    rating      SMALLINT      CHECK (rating BETWEEN 1 AND 5),
    tags        JSONB,
    created_at  TIMESTAMP     NOT NULL DEFAULT NOW()
);

-- ============================================================
--  MÓDULO DE DESTINOS
-- ============================================================

CREATE TABLE IF NOT EXISTS destinations (
    destination_id  UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(255)   NOT NULL,
    country         VARCHAR(100)   NOT NULL,
    city            VARCHAR(150)   NOT NULL,
    latitude        NUMERIC(10,7)  NOT NULL,
    longitude       NUMERIC(10,7)  NOT NULL,
    timezone        VARCHAR(60),
    currency_code   VARCHAR(10),
    popular_months  JSONB,
    image_url       TEXT,
    created_at      TIMESTAMP      NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP      NOT NULL DEFAULT NOW()
);

-- Tendencias históricas de precios de vuelos hacia un destino
-- Relación 1:N con destinations
CREATE TABLE IF NOT EXISTS flight_price_trends (
    trend_id             UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    destination_id       UUID           NOT NULL REFERENCES destinations(destination_id) ON DELETE CASCADE,
    origin_airport_code  VARCHAR(10)    NOT NULL,
    month                SMALLINT       NOT NULL CHECK (month BETWEEN 1 AND 12),
    avg_price            NUMERIC(10,2),
    min_price            NUMERIC(10,2),
    currency             VARCHAR(10)    NOT NULL DEFAULT 'USD',
    last_updated         TIMESTAMP      NOT NULL DEFAULT NOW()
);

-- ============================================================
--  MÓDULO DE WISHLIST
-- ============================================================

-- Lista de deseos: destinos que el usuario quiere visitar
-- Relación 1:N con users
CREATE TABLE IF NOT EXISTS wishlist (
    wishlist_id UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID          NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    country     VARCHAR(100)  NOT NULL,
    city        VARCHAR(150)  NOT NULL,
    created_at  TIMESTAMP     NOT NULL DEFAULT NOW(),

    UNIQUE (user_id, country, city)
);

-- ============================================================
--  MÓDULO DE ETIQUETAS (N:N con trips)
--  Tabla puente que implementa la relación muchos-a-muchos:
--  un viaje puede tener muchas etiquetas y una etiqueta
--  puede aplicarse a muchos viajes
-- ============================================================

CREATE TABLE IF NOT EXISTS tags (
    tag_id      SERIAL        PRIMARY KEY,
    name        VARCHAR(50)   NOT NULL UNIQUE,
    category    VARCHAR(30)   NOT NULL DEFAULT 'GENERAL'
                    CHECK (category IN ('TIPO_VIAJE', 'ACTIVIDAD', 'CLIMA', 'PRESUPUESTO', 'GENERAL')),
    is_active   BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMP     NOT NULL DEFAULT NOW()
);

-- ============================================================
--  MÓDULO DE ITINERARIOS
-- ============================================================

-- Viaje principal del usuario
CREATE TABLE IF NOT EXISTS trips (
    trip_id                 UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID           NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    destination_id          UUID           REFERENCES destinations(destination_id) ON DELETE SET NULL,
    trip_name               VARCHAR(255)   NOT NULL,
    start_date              DATE           NOT NULL,
    end_date                DATE           NOT NULL,
    status                  VARCHAR(20)    NOT NULL DEFAULT 'DRAFT'
                                CHECK (status IN ('DRAFT', 'CONFIRMED', 'COMPLETED', 'CANCELLED')),
    total_budget            NUMERIC(12,2),
    currency                VARCHAR(10)    NOT NULL DEFAULT 'USD',
    is_favorite             BOOLEAN        NOT NULL DEFAULT FALSE,
    confirmed_at            TIMESTAMP,
    planning_time_seconds   INTEGER        NOT NULL DEFAULT 0,  -- métrica de hipótesis
    created_at              TIMESTAMP      NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMP      NOT NULL DEFAULT NOW()
);

-- Tabla puente N:N entre trips y tags
-- Un viaje puede tener múltiples etiquetas,
-- una etiqueta puede estar en múltiples viajes
CREATE TABLE IF NOT EXISTS trip_tags (
    trip_id   UUID       NOT NULL REFERENCES trips(trip_id) ON DELETE CASCADE,
    tag_id    INTEGER    NOT NULL REFERENCES tags(tag_id)   ON DELETE CASCADE,
    added_at  TIMESTAMP  NOT NULL DEFAULT NOW(),

    PRIMARY KEY (trip_id, tag_id)
);

-- Días del itinerario, uno por cada fecha del viaje
-- Relación 1:N con trips
CREATE TABLE IF NOT EXISTS itinerary_days (
    day_id      UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id     UUID      NOT NULL REFERENCES trips(trip_id) ON DELETE CASCADE,
    day_date    DATE      NOT NULL,
    day_number  SMALLINT  NOT NULL,
    notes       TEXT,
    created_at  TIMESTAMP NOT NULL DEFAULT NOW(),

    UNIQUE (trip_id, day_number),
    UNIQUE (trip_id, day_date)
);

-- ============================================================
--  MÓDULO DE REFERENCIAS EXTERNAS
-- ============================================================

-- Cache de lugares obtenidos de APIs externas (Google Places, etc.)
CREATE TABLE IF NOT EXISTS place_references (
    reference_id  UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    external_id   VARCHAR(255)   NOT NULL,
    category      VARCHAR(50)    NOT NULL
                      CHECK (category IN ('HOTEL', 'RESTAURANT', 'POI', 'SERVICE')),
    name          VARCHAR(255)   NOT NULL,
    address       TEXT,
    latitude      NUMERIC(10,7),
    longitude     NUMERIC(10,7),
    rating        NUMERIC(3,2),
    extended_data JSONB,
    api_source    VARCHAR(50),
    cached_at     TIMESTAMP      NOT NULL DEFAULT NOW(),

    UNIQUE (external_id, category)
);

-- Cache de vuelos obtenidos de Amadeus / AirScraper
CREATE TABLE IF NOT EXISTS flight_references (
    reference_id         UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    external_flight_id   VARCHAR(255)   NOT NULL UNIQUE,
    airline_code         VARCHAR(10),
    flight_number        VARCHAR(20),
    origin_airport       VARCHAR(10)    NOT NULL,
    destination_airport  VARCHAR(10)    NOT NULL,
    departure_time       TIMESTAMP      NOT NULL,
    arrival_time         TIMESTAMP      NOT NULL,
    price                NUMERIC(10,2),
    currency             VARCHAR(10)    NOT NULL DEFAULT 'USD',
    api_source           VARCHAR(50)    NOT NULL DEFAULT 'amadeus',
    cached_at            TIMESTAMP      NOT NULL DEFAULT NOW(),
    cache_ttl_hours      SMALLINT       NOT NULL DEFAULT 24
);

-- Ítems del itinerario: lugares o vuelos asignados a un día
-- Relación 1:N con itinerary_days
CREATE TABLE IF NOT EXISTS itinerary_items (
    item_id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    day_id               UUID         NOT NULL REFERENCES itinerary_days(day_id) ON DELETE CASCADE,
    item_type            VARCHAR(20)  NOT NULL CHECK (item_type IN ('PLACE', 'FLIGHT')),
    place_reference_id   UUID         REFERENCES place_references(reference_id) ON DELETE SET NULL,
    flight_reference_id  UUID         REFERENCES flight_references(reference_id) ON DELETE SET NULL,
    order_position       SMALLINT     NOT NULL DEFAULT 1,
    start_time           TIME,
    end_time             TIME,
    estimated_cost       NUMERIC(10,2),
    notes                TEXT,
    status               VARCHAR(20)  NOT NULL DEFAULT 'PLANNED'
                             CHECK (status IN ('PLANNED', 'CONFIRMED', 'CANCELLED')),
    created_at           TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP    NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_place_ref
        CHECK (item_type <> 'PLACE'  OR place_reference_id  IS NOT NULL),
    CONSTRAINT chk_flight_ref
        CHECK (item_type <> 'FLIGHT' OR flight_reference_id IS NOT NULL)
);

-- ============================================================
--  MÓDULO DE TICKETS
-- ============================================================

CREATE TABLE IF NOT EXISTS tickets (
    ticket_id           UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id             UUID           NOT NULL UNIQUE
                            REFERENCES trips(trip_id) ON DELETE CASCADE,
    user_id             UUID           NOT NULL
                            REFERENCES users(user_id) ON DELETE CASCADE,

    -- Resumen financiero calculado automáticamente por triggers
    presupuesto_total   NUMERIC(12,2)  NOT NULL DEFAULT 0,
    costo_acumulado     NUMERIC(12,2)  NOT NULL DEFAULT 0,
    balance_disponible  NUMERIC(12,2)  GENERATED ALWAYS AS
                            (presupuesto_total - costo_acumulado) STORED,

    -- Contadores de ítems activos (no cancelados)
    total_lugares       INTEGER        NOT NULL DEFAULT 0,
    total_vuelos        INTEGER        NOT NULL DEFAULT 0,
    total_items         INTEGER        GENERATED ALWAYS AS
                            (total_lugares + total_vuelos) STORED,

    -- Estado derivado del porcentaje de uso del presupuesto
    estado_presupuesto  VARCHAR(20)    NOT NULL DEFAULT 'SIN_DATOS'
                            CHECK (estado_presupuesto IN (
                                'SIN_DATOS',    -- sin presupuesto definido aún
                                'EN_RANGO',     -- costo <= 80% del presupuesto
                                'ADVERTENCIA',  -- costo entre 80% y 100%
                                'EXCEDIDO'      -- costo > presupuesto
                            )),

    -- Auditoría
    created_at          TIMESTAMP      NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP      NOT NULL DEFAULT NOW()
);

-- ============================================================
--  MÓDULO DE NOTIFICACIONES
-- ============================================================

CREATE TABLE IF NOT EXISTS email_notifications (
    notification_id      UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID         NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    notification_type    VARCHAR(40)  NOT NULL
                             CHECK (notification_type IN (
                                 'WELCOME', 'PASSWORD_RESET',
                                 'DRAFT_REMINDER', 'ARCHIVE_WARNING',
                                 'TRIP_UPCOMING', 'TRIP_CONFIRMED'
                             )),
    subject              VARCHAR(255),
    template_data        JSONB,
    status               VARCHAR(20)  NOT NULL DEFAULT 'PENDING'
                             CHECK (status IN ('PENDING', 'SENT', 'FAILED', 'CANCELLED')),
    scheduled_for        TIMESTAMP,
    sent_at              TIMESTAMP,
    retry_count          SMALLINT     NOT NULL DEFAULT 0,
    error_message        TEXT,
    related_entity_type  VARCHAR(30),
    related_entity_id    UUID,
    created_at           TIMESTAMP    NOT NULL DEFAULT NOW()
);