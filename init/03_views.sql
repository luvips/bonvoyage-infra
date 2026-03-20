-- ============================================================
--  BON VOYAGE — Views
--  Vistas únicamente
--  PostgreSQL 16
-- ============================================================

-- ------------------------------------------------------------
--  VIEW 1: Viajes favoritos del usuario
--  Requisito: VIEW con JOIN de 4 tablas + agregación (COUNT, SUM)
--  Uso: SELECT * FROM vw_favorite_trips WHERE user_id = $1
-- ------------------------------------------------------------

/*
  Qué hace: Muestra los viajes marcados como favoritos junto con
  los datos del destino. Calcula de una vez cuántos ítems tiene
  y cuánto dinero lleva acumulado en el itinerario.
*/
CREATE OR REPLACE VIEW vw_favorite_trips AS
SELECT
    t.trip_id,
    t.user_id,
    t.trip_name,
    t.start_date,
    t.end_date,
    t.status,
    t.total_budget,
    t.currency,
    t.confirmed_at,
    t.created_at,
    t.updated_at,
    d.name                               AS destination_name,
    d.country                            AS destination_country,
    d.city                               AS destination_city,
    d.image_url                          AS destination_image,
    (t.end_date - t.start_date + 1)      AS total_days,
    COUNT(ii.item_id)                    AS total_items,
    COALESCE(SUM(ii.estimated_cost), 0)  AS accumulated_cost
FROM trips t
LEFT JOIN destinations    d   ON d.destination_id = t.destination_id
LEFT JOIN itinerary_days  id_ ON id_.trip_id       = t.trip_id
LEFT JOIN itinerary_items ii  ON ii.day_id         = id_.day_id
                              AND ii.status        <> 'CANCELLED'
WHERE t.is_favorite = TRUE
  AND t.status      <> 'CANCELLED'
GROUP BY
    t.trip_id, t.user_id, t.trip_name, t.start_date, t.end_date,
    t.status, t.total_budget, t.currency, t.confirmed_at,
    t.created_at, t.updated_at,
    d.name, d.country, d.city, d.image_url;


-- ------------------------------------------------------------
--  VIEW 2: Historial de viajes completados
--  Requisito: VIEW con agregación (SUM) y múltiples JOINs
--  Uso: SELECT * FROM vw_travel_history WHERE user_id = $1
-- ------------------------------------------------------------

/*
  Qué hace: Construye el historial de viajes completados por el
  usuario, sumando el gasto total de cada uno. Une user_travel_history
  con las tablas maestras de viajes y destinos.
*/
CREATE OR REPLACE VIEW vw_travel_history AS
SELECT
    uth.history_id,
    uth.user_id,
    uth.trip_id,
    uth.destination,
    uth.country,
    uth.travel_date,
    uth.rating,
    uth.tags,
    uth.created_at,
    t.trip_name,
    t.start_date,
    t.end_date,
    t.currency,
    COALESCE(SUM(ii.estimated_cost), 0)  AS total_spent,
    d.image_url                          AS destination_image
FROM user_travel_history uth
LEFT JOIN trips           t   ON t.trip_id        = uth.trip_id
LEFT JOIN destinations    d   ON d.destination_id = t.destination_id
LEFT JOIN itinerary_days  idd ON idd.trip_id      = uth.trip_id
LEFT JOIN itinerary_items ii  ON ii.day_id        = idd.day_id
                              AND ii.status       <> 'CANCELLED'
GROUP BY
    uth.history_id, uth.user_id, uth.trip_id, uth.destination,
    uth.country, uth.travel_date, uth.rating, uth.tags, uth.created_at,
    t.trip_name, t.start_date, t.end_date, t.currency, d.image_url;


-- ------------------------------------------------------------
--  VIEW 3: Wishlist extendida con precio mínimo de vuelos
--  Requisito: subconsulta anidada en SELECT
--  Uso: SELECT * FROM vw_wishlist WHERE user_id = $1
-- ------------------------------------------------------------

/*
  Qué hace: Alimenta la pantalla de lista de deseos. Para cada
  destino en wishlist, calcula en línea el precio mínimo de vuelo
  disponible usando una subconsulta correlacionada en el SELECT.
*/
CREATE OR REPLACE VIEW vw_wishlist AS
SELECT
    w.wishlist_id,
    w.user_id,
    w.country,
    w.city,
    w.created_at,
    d.destination_id,
    d.image_url       AS destination_image,
    d.latitude,
    d.longitude,
    d.timezone,
    d.currency_code,
    d.popular_months,
    (
        SELECT MIN(fpt.min_price)
        FROM flight_price_trends fpt
        WHERE fpt.destination_id = d.destination_id
    )                 AS min_flight_price
FROM wishlist w
LEFT JOIN destinations d
       ON LOWER(d.country) = LOWER(w.country)
      AND LOWER(d.city)    = LOWER(w.city);


-- ------------------------------------------------------------
--  VIEW 4: Validación de hipótesis de negocio
--  Requisito: VIEW diseñada específicamente para medir la
--  métrica de la hipótesis (Sección 4, criterio c)
--  Uso: SELECT * FROM vw_hipotesis_validacion
-- ------------------------------------------------------------

/*
  Hipótesis: "Si los usuarios pueden planear su viaje completo
  desde la app, entonces el tiempo promedio de planificación
  será menor a 2.5 horas."

  Qué hace: Reúne todos los viajes con itinerarios y evalúa si
  logramos la meta. Llama a fn_calcular_horas_planificacion para
  convertir segundos a horas con 2 decimales, y usa CASE para
  emitir el veredicto directamente.
*/
CREATE OR REPLACE VIEW vw_hipotesis_validacion AS
SELECT
    t.trip_id,
    t.user_id,
    t.trip_name,
    t.status,
    t.planning_time_seconds,
    fn_calcular_horas_planificacion(t.planning_time_seconds)  AS horas_planificacion,
    COUNT(ii.item_id)                                         AS total_items_planificados,
    CASE
        WHEN fn_calcular_horas_planificacion(t.planning_time_seconds) <= 2.5
            THEN 'HIPÓTESIS VALIDADA'
        ELSE
            'HIPÓTESIS INVALIDADA'
    END AS resultado_hipotesis
FROM trips t
JOIN itinerary_days  id_ ON id_.trip_id = t.trip_id
JOIN itinerary_items ii  ON ii.day_id   = id_.day_id
WHERE t.planning_time_seconds > 0
GROUP BY t.trip_id, t.user_id, t.trip_name, t.status, t.planning_time_seconds;