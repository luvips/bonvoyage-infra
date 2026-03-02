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
        RAISE EXCEPTION 'Fecha final debe ser mayor o igual a la fecha de inicio';
    END IF;

    IF (p_end_date - p_start_date) > 30 THEN
        RAISE EXCEPTION 'Viajes no pueden durar más de 30 días';
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


-- ============================================================
--  FUNCTION 2: Cambiar status del viaje + acciones derivadas
--  Acciones posibles: 'confirm' | 'cancel' | 'complete'
--  Uso: SELECT fn_change_trip_status(trip_id, user_id, 'confirm')
-- ============================================================

CREATE OR REPLACE FUNCTION fn_change_trip_status(
    p_trip_id   UUID,
    p_user_id   UUID,
    p_action    VARCHAR(20)    
)
RETURNS VARCHAR(20)             
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_status    VARCHAR(20);
    v_new_status        VARCHAR(20);
    v_trip_name         VARCHAR(255);
    v_destination       VARCHAR(255);
    v_country           VARCHAR(100);
    v_start_date        DATE;
    v_end_date          DATE;
BEGIN
    SELECT t.status, t.trip_name, t.start_date, t.end_date,
           COALESCE(d.name, 'Destino'), COALESCE(d.country, '')
    INTO v_current_status, v_trip_name, v_start_date, v_end_date,
         v_destination, v_country
    FROM trips t
    LEFT JOIN destinations d ON d.destination_id = t.destination_id
    WHERE t.trip_id = p_trip_id AND t.user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Viaje no encontrado o acceso denegado';
    END IF;

    CASE p_action
        WHEN 'confirm' THEN
            IF v_current_status <> 'draft' THEN
                RAISE EXCEPTION 'solo los viajes en borrador pueden ser confirmados';
            END IF;
            v_new_status := 'confirmed';

        WHEN 'cancel' THEN
            IF v_current_status NOT IN ('draft', 'confirmed') THEN
                RAISE EXCEPTION 'Solo los viajes en borrador o confirmados pueden ser cancelados';
            END IF;
            v_new_status := 'cancelled';

        WHEN 'complete' THEN
            IF v_current_status <> 'confirmed' THEN
                RAISE EXCEPTION 'Solo los viajes confirmados pueden ser completados';
            END IF;
            IF v_end_date > CURRENT_DATE THEN
                RAISE EXCEPTION 'La fecha final del viaje aún no ha pasado';
            END IF;
            v_new_status := 'completed';

        ELSE
            RAISE EXCEPTION 'Acción inválida: %', p_action;
    END CASE;

    UPDATE trips
    SET status       = v_new_status,
        confirmed_at = CASE WHEN v_new_status = 'confirmed' THEN NOW() ELSE confirmed_at END,
        updated_at   = NOW()
    WHERE trip_id = p_trip_id;

    UPDATE email_notifications
    SET status = 'cancelled'
    WHERE related_entity_id = p_trip_id
      AND related_entity_type = 'trip'
      AND status = 'pending';

    IF v_new_status = 'confirmed' THEN
        INSERT INTO email_notifications (
            user_id, notification_type, template_data,
            status, scheduled_for,
            related_entity_type, related_entity_id
        )
        VALUES (
            p_user_id, 'trip_confirmed',
            jsonb_build_object('trip_name', v_trip_name, 'start_date', v_start_date),
            'pending', NOW(),
            'trip', p_trip_id
        );

        INSERT INTO email_notifications (
            user_id, notification_type, template_data,
            status, scheduled_for,
            related_entity_type, related_entity_id
        )
        SELECT
            p_user_id,
            'trip_upcoming',
            jsonb_build_object(
                'trip_name', v_trip_name,
                'days_until', days_before,
                'start_date', v_start_date
            ),
            'pending',
            v_start_date - (days_before || ' days')::INTERVAL,
            'trip',
            p_trip_id
        FROM unnest(ARRAY[30, 7, 1]) AS days_before
        WHERE v_start_date - (days_before || ' days')::INTERVAL > NOW();

    ELSIF v_new_status = 'completed' THEN
        INSERT INTO user_travel_history (
            user_id, trip_id, destination, country, travel_date
        )
        VALUES (
            p_user_id, p_trip_id, v_destination, v_country, v_start_date
        );
    END IF;

    RETURN v_new_status;
END;
$$;