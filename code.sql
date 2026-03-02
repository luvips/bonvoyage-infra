-- ============================================================
--  FUNCTION 1: Crear viaje + generar días automáticamente
--  Uso: SELECT fn_create_trip(...)
--  Retorna el trip_id del viaje creado
-- ============================================================

CREATE OR REPLACE FUNCTION fn_create_trip(
    p_user_id           UUID,
    p_trip_name         VARCHAR(255),
    p_destination_id    UUID,
    p_start_date        DATE,
    p_end_date          DATE,
    p_total_budget      DECIMAL(12,2) DEFAULT NULL,
    p_currency          VARCHAR(10)   DEFAULT 'USD'
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_trip_id   UUID;
    v_day_date  DATE;
    v_day_num   SMALLINT := 1;
BEGIN
    IF p_end_date < p_start_date THEN
        RAISE EXCEPTION 'end_date must be >= start_date';
    END IF;

    IF (p_end_date - p_start_date) > 30 THEN
        RAISE EXCEPTION 'Trip cannot exceed 30 days';
    END IF;

    INSERT INTO trips (
        user_id, destination_id, trip_name,
        start_date, end_date,
        total_budget, currency,
        status
    )
    VALUES (
        p_user_id, p_destination_id, p_trip_name,
        p_start_date, p_end_date,
        p_total_budget, p_currency,
        'draft'
    )
    RETURNING trip_id INTO v_trip_id;

    v_day_date := p_start_date;
    WHILE v_day_date <= p_end_date LOOP
        INSERT INTO itinerary_days (trip_id, day_date, day_number)
        VALUES (v_trip_id, v_day_date, v_day_num);

        v_day_date := v_day_date + INTERVAL '1 day';
        v_day_num  := v_day_num + 1;
    END LOOP;

   
    INSERT INTO email_notifications (
        user_id, notification_type, template_data,
        status, scheduled_for,
        related_entity_type, related_entity_id
    )
    VALUES (
        p_user_id,
        'draft_reminder',
        jsonb_build_object('trip_id', v_trip_id, 'trip_name', p_trip_name),
        'pending',
        NOW() + INTERVAL '23 days',
        'trip',
        v_trip_id
    );

    RETURN v_trip_id;
END;
$$;

