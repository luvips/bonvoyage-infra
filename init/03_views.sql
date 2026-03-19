-- ============================================================
--  BON VOYAGE — Views
--  Vistas únicamente
--  PostgreSQL 16
-- ============================================================

/* 
  Objeto: vw_favorite_trips
  1) Qué hace: Esta vista nos sirve para mostrar rápido en la app la lista de viajes que el usuario guardó como favoritos. Trae los datos del viaje junto con la info del destino, además nos calcula de una vez cuántos días dura y cuánto dinero lleva sumado el itinerario.
  2) Requisito técnico cubierto: Con esto cubrimos el punto de "1 view con JOIN de 2+ tablas" (relacionamos trips, destinations, itinerary_days e itinerary_items) y también el punto de "1 view con funciones de agregación" porque implementamos COUNT para los ítems y SUM para agrupar el costo total.
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
    d.name                              AS destination_name,
    d.country                           AS destination_country,
    d.city                              AS destination_city,
    d.image_url                         AS destination_image,
    (t.end_date - t.start_date + 1)     AS total_days,
    COUNT(ii.item_id)                   AS total_items,
    COALESCE(SUM(ii.estimated_cost), 0) AS accumulated_cost
FROM trips t
LEFT JOIN destinations    d   ON d.destination_id = t.destination_id
LEFT JOIN itinerary_days  id_ ON id_.trip_id       = t.trip_id
LEFT JOIN itinerary_items ii  ON ii.day_id          = id_.day_id
                              AND ii.status         <> 'CANCELLED'
WHERE t.is_favorite = TRUE
  AND t.status      <> 'CANCELLED'
GROUP BY
    t.trip_id, t.user_id, t.trip_name, t.start_date, t.end_date,
    t.status, t.total_budget, t.currency, t.confirmed_at,
    t.created_at, t.updated_at,
    d.name, d.country, d.city, d.image_url;


/* 
  Objeto: vw_travel_history
  1) Qué hace: Nos ayuda a armar el historial de los viajes que los usuarios ya completaron. Suma mágicamente todo el gasto que tuvieron y nos deja ver qué calificación general le dieron a ese viaje.
  2) Requisito técnico cubierto: Es nuestra segunda vista con agregaciones y múltiples JOINs. Cumplimos con no anidar consultas sino cruzar user_travel_history con las tablas maestras. Usamos COALESCE porque no sabemos si todos los ítems tenían costo y no queremos errores nulos.
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
    COALESCE(SUM(ii.estimated_cost), 0) AS total_spent,
    d.image_url                          AS destination_image
FROM user_travel_history uth
LEFT JOIN trips           t   ON t.trip_id          = uth.trip_id
LEFT JOIN destinations    d   ON d.destination_id   = t.destination_id
LEFT JOIN itinerary_days  idd ON idd.trip_id         = uth.trip_id
LEFT JOIN itinerary_items ii  ON ii.day_id           = idd.day_id
                              AND ii.status          <> 'CANCELLED'
GROUP BY
    uth.history_id, uth.user_id, uth.trip_id, uth.destination,
    uth.country, uth.travel_date, uth.rating, uth.tags, uth.created_at,
    t.trip_name, t.start_date, t.end_date, t.currency,
    d.image_url;


/* 
  Objeto: vw_wishlist
  1) Qué hace: Es la vista que alimenta la lista de deseos. La creamos para que cuando el usuario vea a dónde quiere ir, de paso el backend le busque cuál es el precio más barato de los vuelos a ese lugar usando una consulta interna.
  2) Requisito técnico cubierto: Cumplimos con la validación de usar subconsultas anidadas en el bloque SELECT metiendo "(SELECT MIN...)". La nombramos con vw_ para seguir la nomenclatura requerida.
*/
CREATE OR REPLACE VIEW vw_wishlist AS
SELECT
    w.wishlist_id,
    w.user_id,
    w.country,
    w.city,
    w.created_at,
    d.destination_id,
    d.image_url         AS destination_image,
    d.latitude,
    d.longitude,
    d.timezone,
    d.currency_code,
    d.popular_months,
    (
        SELECT MIN(fpt.min_price)
        FROM flight_price_trends fpt
        WHERE fpt.destination_id = d.destination_id
    )                   AS min_flight_price
FROM wishlist w
LEFT JOIN destinations d
       ON LOWER(d.country) = LOWER(w.country)
      AND LOWER(d.city)    = LOWER(w.city);


/* 
  Objeto: fn_calcular_horas_planificacion
  1) Qué hace: Intercepta el campo de cuántos segundos pasó el usuario planeando su viaje en la app, lo divide entre 3600 y nos devuelve todo en horas cerradas a 2 decimales para que sea fácil analizar.
  2) Requisito técnico cubierto: Con esta función resolvemos el primer requisito de "1 función escalar usada dentro de un query o view". Retornamos NUMERIC y no pusimos COMMIT ni ROLLBACK porque eso está prohibido en funciones Escalares. La pusimos aquí para que la tabla de abajo (nuestra hipótesis) la pueda usar sin tronar el script.
*/
CREATE OR REPLACE FUNCTION fn_calcular_horas_planificacion(segundos INT)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN ROUND(COALESCE(segundos, 0)::NUMERIC / 3600.0, 2);
END;
$$;


/* 
  Objeto: vw_hipotesis_validacion
  1) Qué hace: Esta es la pieza clave de nuestro proyecto. Reúne a todos los viajes con itinerarios y evalúa si logramos nuestro objetivo de negocio de hacer que los usuarios planeen su viaje en menos de 2.5 horas, etiquetando el viaje.
  2) Requisito técnico cubierto: Cumplimos directamente con el punto que nos exige "1 view diseñada específicamente para medir la métrica de la hipótesis". Implementamos un JOIN robusto de viajes contra sus días e ítems; llamamos adentro a nuestra función fn_calcular_horas_planificacion (cubriendo otro requisito) y por último, pusimos un condicional CASE para soltar 'HIPÓTESIS VALIDADA' de una vez por todas si se logró.
*/
CREATE OR REPLACE VIEW vw_hipotesis_validacion AS
SELECT 
    t.trip_id,
    t.trip_name,
    t.planning_time_seconds,
    fn_calcular_horas_planificacion(t.planning_time_seconds) AS horas_planificacion,
    COUNT(ii.item_id) AS total_items_planificados,
    CASE 
        WHEN fn_calcular_horas_planificacion(t.planning_time_seconds) <= 2.5 THEN 'HIPÓTESIS VALIDADA'
        ELSE 'HIPÓTESIS INVALIDADA'
    END AS resultado_hipotesis
FROM trips t
JOIN itinerary_days id ON t.trip_id = id.trip_id
JOIN itinerary_items ii ON id.day_id = ii.day_id
GROUP BY t.trip_id, t.trip_name, t.planning_time_seconds;