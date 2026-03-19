INSERT INTO avatars (name, image_url) VALUES
    ('aventurero', 'https://api.dicebear.com/7.x/adventurer/svg?seed=aventurero'),
    ('explorador', 'https://api.dicebear.com/7.x/adventurer/svg?seed=explorador'),
    ('viajero',    'https://api.dicebear.com/7.x/adventurer/svg?seed=viajero'),
    ('mochilero',  'https://api.dicebear.com/7.x/adventurer/svg?seed=mochilero'),
    ('turista',    'https://api.dicebear.com/7.x/adventurer/svg?seed=turista')
ON CONFLICT (name) DO NOTHING;

INSERT INTO destinations (name, country, city, latitude, longitude, timezone, currency_code, popular_months, image_url)
VALUES
    ('Tokio',            'Japón',          'Tokio',       35.6762,   139.6503,  'Asia/Tokyo',          'JPY', '[3,4,10,11]',    'https://images.unsplash.com/photo-1540959733332-eab4deabeeaf'),
    ('París',            'Francia',        'París',       48.8566,   2.3522,    'Europe/Paris',        'EUR', '[4,5,6,9,10]',   'https://images.unsplash.com/photo-1499856871958-5b9627545d1a'),
    ('Nueva York',       'Estados Unidos', 'Nueva York',  40.7128,  -74.0060,   'America/New_York',    'USD', '[4,5,6,9,10]',   'https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9'),
    ('Ciudad de México', 'México',         'CDMX',        19.4326,  -99.1332,   'America/Mexico_City', 'MXN', '[10,11,12,1,2]', 'https://images.unsplash.com/photo-1518105779142-d975f22f1b0a'),
    ('Barcelona',        'España',         'Barcelona',   41.3851,   2.1734,    'Europe/Madrid',       'EUR', '[5,6,7,8,9]',    'https://images.unsplash.com/photo-1539037116277-4db20889f2d4'),
    ('Bangkok',          'Tailandia',      'Bangkok',     13.7563,  100.5018,   'Asia/Bangkok',        'THB', '[11,12,1,2,3]',  'https://images.unsplash.com/photo-1508009603885-50cf7c579365'),
    ('Roma',             'Italia',         'Roma',        41.9028,   12.4964,   'Europe/Rome',         'EUR', '[4,5,9,10]',     'https://images.unsplash.com/photo-1552832230-c0197dd311b5'),
    ('Cancún',           'México',         'Cancún',      21.1619,  -86.8515,   'America/Cancun',      'MXN', '[12,1,2,3,4]',   'https://images.unsplash.com/photo-1510097467424-192d713fd8b2')
ON CONFLICT DO NOTHING;

INSERT INTO users (user_id, email, first_name, last_name, avatar_id, role, status)
VALUES
    ('a0000000-0000-0000-0000-000000000001', 'alix@test.com',    'Alix',    'Montesinos', 1, 'ADMIN', 'ACTIVE'),
    ('a0000000-0000-0000-0000-000000000002', 'luvia@test.com',   'Luvia',   'Hidalgo',    2, 'USER',  'ACTIVE'),
    ('a0000000-0000-0000-0000-000000000003', 'rodolfo@test.com', 'Rodolfo', 'Ramirez',    3, 'USER',  'ACTIVE')
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO user_identities (user_id, provider, provider_id, password_hash)
VALUES
    ('a0000000-0000-0000-0000-000000000001', 'LOCAL',  NULL,                    '$2b$12$placeholderHashForTestingOnly1'),
    ('a0000000-0000-0000-0000-000000000002', 'LOCAL',  NULL,                    '$2b$12$placeholderHashForTestingOnly2'),
    ('a0000000-0000-0000-0000-000000000003', 'GOOGLE', 'google_id_rodolfo_123', NULL)
ON CONFLICT (user_id, provider) DO NOTHING;

INSERT INTO user_preferences (user_id, preferred_currency, preferred_language)
VALUES
    ('a0000000-0000-0000-0000-000000000001', 'MXN', 'es'),
    ('a0000000-0000-0000-0000-000000000002', 'MXN', 'es'),
    ('a0000000-0000-0000-0000-000000000003', 'USD', 'es')
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO wishlist (user_id, country, city)
VALUES
    ('a0000000-0000-0000-0000-000000000001', 'Japón',   'Tokio'),
    ('a0000000-0000-0000-0000-000000000001', 'Francia', 'París'),
    ('a0000000-0000-0000-0000-000000000002', 'Italia',  'Roma')
ON CONFLICT (user_id, country, city) DO NOTHING;

INSERT INTO trips (trip_id, user_id, destination_id, trip_name, start_date, end_date, status, total_budget, currency)
SELECT
    'b0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000001',
    destination_id,
    'Aventura en Tokio',
    CURRENT_DATE + 60,
    CURRENT_DATE + 67,
    'DRAFT',
    2000.00,
    'USD'
FROM destinations
WHERE city = 'Tokio'
LIMIT 1
ON CONFLICT (trip_id) DO NOTHING;

INSERT INTO itinerary_days (trip_id, day_date, day_number)
SELECT
    'b0000000-0000-0000-0000-000000000001',
    CURRENT_DATE + 60 + (n - 1),
    n
FROM generate_series(1, 8) AS n
ON CONFLICT (trip_id, day_number) DO NOTHING;

INSERT INTO email_notifications (user_id, notification_type, template_data, status, scheduled_for, related_entity_type, related_entity_id)
VALUES (
    'a0000000-0000-0000-0000-000000000001',
    'WELCOME',
    '{"first_name": "Alix", "email": "alix@test.com"}',
    'SENT',
    NOW(),
    'USER',
    'a0000000-0000-0000-0000-000000000001'
)
ON CONFLICT DO NOTHING;