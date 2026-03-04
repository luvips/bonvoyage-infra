-- ============================================================
--  BON VOYAGE — Schema v2
--  PostgreSQL
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
--  MÓDULO DE USUARIOS
-- ============================================================

-- Catálogo de avatares predeterminados
CREATE TABLE avatars (
    avatar_id   SERIAL PRIMARY KEY,
    name        VARCHAR(50)  NOT NULL UNIQUE,
    image_url   TEXT         NOT NULL,
    is_active   BOOLEAN      NOT NULL DEFAULT TRUE
);

-- Información de perfil
CREATE TABLE users (
    user_id     UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    email       VARCHAR(255) NOT NULL UNIQUE,
    first_name  VARCHAR(255) NOT NULL,
    last_name   VARCHAR(255) NOT NULL,
    avatar_id   INTEGER      REFERENCES avatars(avatar_id) ON DELETE SET NULL,
    role        VARCHAR(20)  NOT NULL DEFAULT 'USER'
                    CHECK (role IN ('USER', 'ADMIN')),
    status      VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE'
                    CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')),
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMP    DEFAULT NULL    
);

-- Métodos de autenticación (LOCAL, GOOGLE, APPLE…)
CREATE TABLE user_identities (
    identity_id     UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID         NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    provider        VARCHAR(50)  NOT NULL CHECK (provider IN ('LOCAL', 'GOOGLE', 'APPLE')),
    provider_id     VARCHAR(255),            
    password_hash   VARCHAR(255),            
    updated_at      TIMESTAMP    NOT NULL DEFAULT NOW(),

    UNIQUE (user_id, provider),
    UNIQUE (provider, provider_id),

    CONSTRAINT chk_local_password
        CHECK (provider <> 'LOCAL' OR password_hash IS NOT NULL),
    CONSTRAINT chk_external_provider_id
        CHECK (provider = 'LOCAL' OR provider_id IS NOT NULL)
);

-- Preferencias del usuario
CREATE TABLE user_preferences (
    preference_id        UUID   PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID   NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    budget_range         JSONB,        
    dietary_restrictions JSONB,          
    interests            JSONB,         
    preferred_currency   VARCHAR(10) DEFAULT 'USD',
    preferred_language   VARCHAR(5)  DEFAULT 'es',
    email_preferences    JSONB,         

    UNIQUE (user_id)
);

-- Historial de viajes completados
CREATE TABLE user_travel_history (
    history_id    UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID      NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    trip_id       UUID,                  
    destination   VARCHAR(255) NOT NULL,
    country       VARCHAR(100) NOT NULL,
    travel_date   DATE,
    rating        SMALLINT  CHECK (rating BETWEEN 1 AND 5),
    tags          JSONB,                
    created_at    TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ============================================================
--  MÓDULO DE WISHLIST
-- ============================================================

CREATE TABLE wishlist (
    wishlist_id UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID      NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    country     VARCHAR(100) NOT NULL,
    city        VARCHAR(150) NOT NULL,
    created_at  TIMESTAMP NOT NULL DEFAULT NOW(),

    UNIQUE (user_id, country, city)
);

-- ============================================================
--  MÓDULO DE DESTINOS
-- ============================================================

CREATE TABLE destinations (
    destination_id  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(255)  NOT NULL,
    country         VARCHAR(100)  NOT NULL,
    city            VARCHAR(150)  NOT NULL,
    latitude        DECIMAL(10,7) NOT NULL,
    longitude       DECIMAL(10,7) NOT NULL,
    timezone        VARCHAR(60),
    currency_code   VARCHAR(10),
    popular_months  JSONB,                    
    image_url       TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE flight_price_trends (
    trend_id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    destination_id      UUID          NOT NULL REFERENCES destinations(destination_id) ON DELETE CASCADE,
    origin_airport_code VARCHAR(10)   NOT NULL,
    month               SMALLINT      NOT NULL CHECK (month BETWEEN 1 AND 12),
    avg_price           DECIMAL(10,2),
    min_price           DECIMAL(10,2),
    currency            VARCHAR(10)   DEFAULT 'USD',
    last_updated        TIMESTAMP     NOT NULL DEFAULT NOW()
);

-- ============================================================
--  MÓDULO DE REFERENCIAS EXTERNAS
-- ============================================================

-- Tabla unificada para lugares: HOTEL, RESTAURANT, POI, SERVICE
CREATE TABLE place_references (
    reference_id    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    external_id     VARCHAR(255)  NOT NULL,
    category        VARCHAR(50)   NOT NULL
                        CHECK (category IN ('HOTEL', 'RESTAURANT', 'POI', 'SERVICE')),
    name            VARCHAR(255)  NOT NULL,
    address         TEXT,
    latitude        DECIMAL(10,7),
    longitude       DECIMAL(10,7),
    rating          DECIMAL(3,2),
    extended_data   JSONB,
    api_source      VARCHAR(50),             
    cached_at       TIMESTAMP NOT NULL DEFAULT NOW(),

    UNIQUE (external_id, category)
);

-- Vuelos se mantienen separados por su complejidad logística
CREATE TABLE flight_references (
    reference_id        UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    external_flight_id  VARCHAR(255)  NOT NULL UNIQUE,
    airline_code        VARCHAR(10),
    flight_number       VARCHAR(20),
    origin_airport      VARCHAR(10)   NOT NULL,
    destination_airport VARCHAR(10)   NOT NULL,
    departure_time      TIMESTAMP     NOT NULL,
    arrival_time        TIMESTAMP     NOT NULL,
    price               DECIMAL(10,2),
    currency            VARCHAR(10)   DEFAULT 'USD',
    api_source          VARCHAR(50)   DEFAULT 'amadeus',
    cached_at           TIMESTAMP     NOT NULL DEFAULT NOW(),
    cache_ttl_hours     SMALLINT      DEFAULT 24
);

-- ============================================================
--  MÓDULO DE ITINERARIOS
-- ============================================================

CREATE TABLE trips (
    trip_id         UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID          NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    destination_id  UUID          REFERENCES destinations(destination_id),
    trip_name       VARCHAR(255)  NOT NULL,
    start_date      DATE          NOT NULL,
    end_date        DATE          NOT NULL,
    status          VARCHAR(20)   NOT NULL DEFAULT 'DRAFT'
                        CHECK (status IN ('DRAFT', 'CONFIRMED', 'COMPLETED', 'CANCELLED')),
    total_budget    DECIMAL(12,2),
    currency        VARCHAR(10)   DEFAULT 'USD',
    is_favorite     BOOLEAN       NOT NULL DEFAULT FALSE,
    confirmed_at    TIMESTAMP,
    created_at      TIMESTAMP     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP     NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_dates    CHECK (end_date >= start_date),
    CONSTRAINT chk_max_days CHECK ((end_date - start_date) <= 30)
);

CREATE TABLE itinerary_days (
    day_id      UUID     PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id     UUID     NOT NULL REFERENCES trips(trip_id) ON DELETE CASCADE,
    day_date    DATE     NOT NULL,
    day_number  SMALLINT NOT NULL,
    notes       TEXT,
    created_at  TIMESTAMP NOT NULL DEFAULT NOW(),

    UNIQUE (trip_id, day_number),
    UNIQUE (trip_id, day_date)
);

CREATE TABLE itinerary_items (
    item_id             UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    day_id              UUID      NOT NULL REFERENCES itinerary_days(day_id) ON DELETE CASCADE,

    -- Dos tipos: lugar (hotel/restaurant/poi/service) o vuelo
    item_type           VARCHAR(20) NOT NULL CHECK (item_type IN ('PLACE', 'FLIGHT')),

    -- FK opcional según tipo
    place_reference_id  UUID      REFERENCES place_references(reference_id),
    flight_reference_id UUID      REFERENCES flight_references(reference_id),

    order_position      SMALLINT  NOT NULL DEFAULT 1,
    start_time          TIME,
    end_time            TIME,
    estimated_cost      DECIMAL(10,2),
    notes               TEXT,
    status              VARCHAR(20) NOT NULL DEFAULT 'PLANNED'
                            CHECK (status IN ('PLANNED', 'CONFIRMED', 'CANCELLED')),
    created_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP NOT NULL DEFAULT NOW(),

    -- Exactamente una referencia debe estar presente según el tipo
    CONSTRAINT chk_place_ref
        CHECK (item_type <> 'PLACE'  OR place_reference_id  IS NOT NULL),
    CONSTRAINT chk_flight_ref
        CHECK (item_type <> 'FLIGHT' OR flight_reference_id IS NOT NULL)
);

-- ============================================================
--  MÓDULO DE NOTIFICACIONES
-- ============================================================

CREATE TABLE email_notifications (
    notification_id     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID        NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    notification_type   VARCHAR(40) NOT NULL
                            CHECK (notification_type IN (
                                'WELCOME', 'PASSWORD_RESET',
                                'DRAFT_REMINDER', 'ARCHIVE_WARNING',
                                'TRIP_UPCOMING', 'TRIP_CONFIRMED'
                            )),
    subject             VARCHAR(255),
    template_data       JSONB,
    status              VARCHAR(20) NOT NULL DEFAULT 'PENDING'
                            CHECK (status IN ('PENDING','SENT','FAILED','CANCELLED')),
    scheduled_for       TIMESTAMP,
    sent_at             TIMESTAMP,
    retry_count         SMALLINT    DEFAULT 0,
    error_message       TEXT,
    related_entity_type VARCHAR(30),    -- 'TRIP' | 'USER'
    related_entity_id   UUID,
    created_at          TIMESTAMP NOT NULL DEFAULT NOW()
);