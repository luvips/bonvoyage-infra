-- ============================================================
--  BON VOYAGE — Indexes
--  Índices únicamente
--  PostgreSQL 16
-- ============================================================

-- USUARIOS
CREATE INDEX IF NOT EXISTS idx_users_email
    ON users(email);

CREATE INDEX IF NOT EXISTS idx_users_active
    ON users(status)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_identities_user
    ON user_identities(user_id);

CREATE INDEX IF NOT EXISTS idx_identities_provider
    ON user_identities(provider, provider_id)
    WHERE provider_id IS NOT NULL;

-- DESTINOS
CREATE INDEX IF NOT EXISTS idx_destinations_country
    ON destinations(country);

CREATE INDEX IF NOT EXISTS idx_destinations_city
    ON destinations(city);

-- WISHLIST
CREATE INDEX IF NOT EXISTS idx_wishlist_user
    ON wishlist(user_id);

-- ETIQUETAS
CREATE INDEX IF NOT EXISTS idx_trip_tags_trip
    ON trip_tags(trip_id);

CREATE INDEX IF NOT EXISTS idx_trip_tags_tag
    ON trip_tags(tag_id);

-- VIAJES
CREATE INDEX IF NOT EXISTS idx_trips_user
    ON trips(user_id);

CREATE INDEX IF NOT EXISTS idx_trips_user_status
    ON trips(user_id, status);

-- Índice parcial: solo viajes favoritos (consulta frecuente del dashboard)
CREATE INDEX IF NOT EXISTS idx_trips_favorites
    ON trips(user_id)
    WHERE is_favorite = TRUE;

-- ITINERARIO
CREATE INDEX IF NOT EXISTS idx_itinerary_days_trip
    ON itinerary_days(trip_id);

CREATE INDEX IF NOT EXISTS idx_itinerary_items_day
    ON itinerary_items(day_id);

CREATE INDEX IF NOT EXISTS idx_itinerary_items_type
    ON itinerary_items(item_type);

-- REFERENCIAS EXTERNAS
CREATE INDEX IF NOT EXISTS idx_place_references_external
    ON place_references(external_id, category);

CREATE INDEX IF NOT EXISTS idx_place_references_category
    ON place_references(category);

CREATE INDEX IF NOT EXISTS idx_flight_references_departure
    ON flight_references(departure_time);

CREATE INDEX IF NOT EXISTS idx_flight_references_route
    ON flight_references(origin_airport, destination_airport);

-- TICKETS
CREATE INDEX IF NOT EXISTS idx_tickets_trip
    ON tickets(trip_id);

CREATE INDEX IF NOT EXISTS idx_tickets_user
    ON tickets(user_id);

-- Índice parcial: tickets con advertencia o excedidos (alertas del dashboard)
CREATE INDEX IF NOT EXISTS idx_tickets_estado_alerta
    ON tickets(budget_status)
    WHERE budget_status IN ('OVER_BUDGET');

-- NOTIFICACIONES
CREATE INDEX IF NOT EXISTS idx_notifications_user
    ON email_notifications(user_id);

-- Índice parcial: solo notificaciones pendientes (worker de envío)
CREATE INDEX IF NOT EXISTS idx_notifications_pending
    ON email_notifications(status, scheduled_for)
    WHERE status = 'PENDING';