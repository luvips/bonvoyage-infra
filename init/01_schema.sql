CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. Tablas independientes (sin llaves foráneas)
CREATE TABLE IF NOT EXISTS avatars (
  avatar_id SERIAL PRIMARY KEY,
  name VARCHAR NOT NULL UNIQUE,
  image_url TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS destinations (
  destination_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR NOT NULL,
  country VARCHAR NOT NULL,
  city VARCHAR NOT NULL,
  latitude NUMERIC NOT NULL,
  longitude NUMERIC NOT NULL,
  timezone VARCHAR,
  currency_code VARCHAR,
  popular_months JSONB,
  image_url TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT now(),
  updated_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS place_references (
  reference_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  external_id VARCHAR NOT NULL,
  category VARCHAR NOT NULL CHECK (category IN ('HOTEL', 'RESTAURANT', 'POI', 'SERVICE')),
  name VARCHAR NOT NULL,
  address TEXT,
  latitude NUMERIC,
  longitude NUMERIC,
  rating NUMERIC,
  extended_data JSONB,
  api_source VARCHAR,
  cached_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS flight_references (
  reference_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  external_flight_id VARCHAR NOT NULL UNIQUE,
  airline_code VARCHAR,
  flight_number VARCHAR,
  origin_airport VARCHAR NOT NULL,
  destination_airport VARCHAR NOT NULL,
  departure_time TIMESTAMP NOT NULL,
  arrival_time TIMESTAMP NOT NULL,
  price NUMERIC,
  currency VARCHAR DEFAULT 'USD',
  api_source VARCHAR DEFAULT 'amadeus',
  cached_at TIMESTAMP NOT NULL DEFAULT now(),
  cache_ttl_hours SMALLINT DEFAULT 24
);

-- 2. Tablas base (dependen de las independientes)
CREATE TABLE IF NOT EXISTS users (
  user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR NOT NULL UNIQUE,
  first_name VARCHAR NOT NULL,
  last_name VARCHAR NOT NULL,
  avatar_id INT REFERENCES avatars(avatar_id),
  role VARCHAR NOT NULL DEFAULT 'USER' CHECK (role IN ('USER', 'ADMIN')),
  status VARCHAR NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')),
  created_at TIMESTAMP NOT NULL DEFAULT now(),
  updated_at TIMESTAMP NOT NULL DEFAULT now(),
  deleted_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS trips (
  trip_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(user_id),
  destination_id UUID REFERENCES destinations(destination_id),
  trip_name VARCHAR NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  status VARCHAR NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'CONFIRMED', 'COMPLETED', 'CANCELLED')),
  total_budget NUMERIC,
  currency VARCHAR DEFAULT 'USD',
  is_favorite BOOLEAN NOT NULL DEFAULT false,
  confirmed_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT now(),
  updated_at TIMESTAMP NOT NULL DEFAULT now(),
  planning_time_seconds INT DEFAULT 0
);

-- Parche de evolución de esquema: Si la tabla ya existía, IF NOT EXISTS omite el bloque anterior.
-- Esta línea fuerza la inserción de la nueva columna para evitar errores en las vistas.
ALTER TABLE trips ADD COLUMN IF NOT EXISTS planning_time_seconds INT DEFAULT 0;

-- 3. Tablas dependientes de usuarios o viajes
CREATE TABLE IF NOT EXISTS user_identities (
  identity_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(user_id),
  provider VARCHAR NOT NULL CHECK (provider IN ('LOCAL', 'GOOGLE', 'APPLE')),
  provider_id VARCHAR,
  password_hash VARCHAR,
  updated_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_preferences (
  preference_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES users(user_id),
  budget_range JSONB,
  dietary_restrictions JSONB,
  interests JSONB,
  preferred_currency VARCHAR DEFAULT 'USD',
  preferred_language VARCHAR DEFAULT 'es',
  email_preferences JSONB,
  updated_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_travel_history (
  history_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(user_id),
  trip_id UUID,
  destination VARCHAR NOT NULL,
  country VARCHAR NOT NULL,
  travel_date DATE,
  rating SMALLINT CHECK (rating >= 1 AND rating <= 5),
  tags JSONB,
  created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS wishlist (
  wishlist_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(user_id),
  country VARCHAR NOT NULL,
  city VARCHAR NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS email_notifications (
  notification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(user_id),
  notification_type VARCHAR NOT NULL CHECK (notification_type IN ('WELCOME', 'PASSWORD_RESET', 'DRAFT_REMINDER', 'ARCHIVE_WARNING', 'TRIP_UPCOMING', 'TRIP_CONFIRMED')),
  subject VARCHAR,
  template_data JSONB,
  status VARCHAR NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'SENT', 'FAILED', 'CANCELLED')),
  scheduled_for TIMESTAMP,
  sent_at TIMESTAMP,
  retry_count SMALLINT DEFAULT 0,
  error_message TEXT,
  related_entity_type VARCHAR,
  related_entity_id UUID,
  created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS flight_price_trends (
  trend_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  destination_id UUID NOT NULL REFERENCES destinations(destination_id),
  origin_airport_code VARCHAR NOT NULL,
  month SMALLINT NOT NULL CHECK (month >= 1 AND month <= 12),
  avg_price NUMERIC,
  min_price NUMERIC,
  currency VARCHAR DEFAULT 'USD',
  last_updated TIMESTAMP NOT NULL DEFAULT now()
);

-- 4. Tablas del itinerario (dependencias más profundas)
CREATE TABLE IF NOT EXISTS itinerary_days (
  day_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id UUID NOT NULL REFERENCES trips(trip_id),
  day_date DATE NOT NULL,
  day_number SMALLINT NOT NULL,
  notes TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS itinerary_items (
  item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  day_id UUID NOT NULL REFERENCES itinerary_days(day_id),
  item_type VARCHAR NOT NULL CHECK (item_type IN ('PLACE', 'FLIGHT')),
  place_reference_id UUID REFERENCES place_references(reference_id),
  flight_reference_id UUID REFERENCES flight_references(reference_id),
  order_position SMALLINT NOT NULL DEFAULT 1,
  start_time TIME,
  end_time TIME,
  estimated_cost NUMERIC,
  notes TEXT,
  status VARCHAR NOT NULL DEFAULT 'PLANNED' CHECK (status IN ('PLANNED', 'CONFIRMED', 'CANCELLED')),
  created_at TIMESTAMP NOT NULL DEFAULT now(),
  updated_at TIMESTAMP NOT NULL DEFAULT now()
);