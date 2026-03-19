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

CREATE INDEX IF NOT EXISTS idx_wishlist_user
    ON wishlist(user_id);

CREATE INDEX IF NOT EXISTS idx_destinations_country
    ON destinations(country);

CREATE INDEX IF NOT EXISTS idx_destinations_city
    ON destinations(city);

CREATE INDEX IF NOT EXISTS idx_trips_user
    ON trips(user_id);

CREATE INDEX IF NOT EXISTS idx_trips_user_status
    ON trips(user_id, status);

CREATE INDEX IF NOT EXISTS idx_trips_favorites
    ON trips(user_id)
    WHERE is_favorite = TRUE;

CREATE INDEX IF NOT EXISTS idx_itinerary_days_trip
    ON itinerary_days(trip_id);

CREATE INDEX IF NOT EXISTS idx_itinerary_items_day
    ON itinerary_items(day_id);

CREATE INDEX IF NOT EXISTS idx_itinerary_items_type
    ON itinerary_items(item_type);

CREATE INDEX IF NOT EXISTS idx_place_references_external
    ON place_references(external_id, category);

CREATE INDEX IF NOT EXISTS idx_place_references_category
    ON place_references(category);

CREATE INDEX IF NOT EXISTS idx_flight_references_departure
    ON flight_references(departure_time);

CREATE INDEX IF NOT EXISTS idx_flight_references_route
    ON flight_references(origin_airport, destination_airport);

CREATE INDEX IF NOT EXISTS idx_notifications_user
    ON email_notifications(user_id);

CREATE INDEX IF NOT EXISTS idx_notifications_pending
    ON email_notifications(status, scheduled_for)
    WHERE status = 'PENDING';