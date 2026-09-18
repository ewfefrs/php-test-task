-- ============================================================================
--  ЗАПРОС ЭЛЕКТРОННОГО ТАБЛО
--  «Следующие 15 отправлений с заданной остановки, начиная с текущего момента».
--  Параметр: :stop_id — id остановки, где стоит табло (напр. 1 = Мурманск).
-- ============================================================================

\set stop_id 1

SELECT
    st.departure_at,
    r.code,
    r.name          AS route_name,
    dest.name       AS destination,   -- пункт назначения = конечная остановка рейса
    st.platform,
    b.plate         AS bus
FROM stop_time st
JOIN trip  t ON t.id = st.trip_id AND t.status = 'scheduled'
JOIN route r ON r.id = t.route_id
JOIN bus   b ON b.id = t.bus_id
-- Пункт назначения рейса = остановка с максимальным stop_seq. LATERAL + LIMIT 1
-- берёт её через тот же PRIMARY KEY (trip_id, stop_seq) обратным сканом.
JOIN LATERAL (
    SELECT s.city_id
    FROM stop_time last
    JOIN stop s ON s.id = last.stop_id
    WHERE last.trip_id = st.trip_id
    ORDER BY last.stop_seq DESC
    LIMIT 1
) d ON TRUE
JOIN city dest ON dest.id = d.city_id
WHERE st.stop_id = :stop_id
  AND st.departure_at >= now()
  AND st.departure_at <  now() + interval '24 hours'  -- окно: не читать историю/далёкое будущее
ORDER BY st.departure_at
LIMIT 15;

-- ============================================================================
--  ИНДЕКСЫ (объявлены в schema.sql)
--
--  Ключевой:
--      CREATE INDEX idx_stop_time_board ON stop_time (stop_id, departure_at)
--          WHERE departure_at IS NOT NULL;
--  Порядок колонок важен: сначала равенство (stop_id), затем диапазон и
--  сортировка (departure_at). Тогда индекс одновременно фильтрует по остановке,
--  отсекает прошлое и отдаёт строки уже в нужном порядке — сортировка не нужна.
--
--  Остальное покрыто первичными ключами:
--    - trip(id), route(id), bus(id)      — джойны идут по PK;
--    - stop_time(trip_id, stop_seq) (PK) — обслуживает LATERAL-подзапрос
--      (Index Scan Backward + LIMIT 1, без отдельного индекса).
-- ============================================================================

-- ============================================================================
--  ЧТО ОЖИДАЮ В ПЛАНЕ ВЫПОЛНЕНИЯ (EXPLAIN (ANALYZE, BUFFERS) ...):
--
--  Limit  (rows=15)
--    ->  Nested Loop
--          ->  Index Scan using idx_stop_time_board on stop_time st
--                Index Cond: (stop_id = :stop_id AND departure_at >= now())
--                -- строки уже идут по возрастанию departure_at
--          ->  Index Scan using trip_pkey on trip t   (Filter: status = 'scheduled')
--          ->  Index Scan using route_pkey on route r
--          ->  Index Scan using bus_pkey on bus b
--          ->  Limit
--                ->  Index Scan Backward using stop_time_pkey (LATERAL, dest)
--
--  На что смотрю в первую очередь:
--    * НЕТ узла Sort — порядок обеспечивает индекс. Иначе БД отсортировала бы
--      ВСЕ будущие отправления остановки, прежде чем взять 15.
--    * НЕТ Seq Scan по stop_time.
--    * Index Cond включает ОБА условия (stop_id и departure_at), а не только stop_id.
--    * LIMIT 15 «проваливается» в Nested Loop: читаем ~15 индексных кортежей,
--      а не всю выборку (rows у верхнего Limit = 15).
--
--  Если планировщик вдруг выбрал Seq Scan + Sort — проверяю свежесть статистики
--  (ANALYZE stop_time) и оценку строк (rows). На больших объёмах — секционирование
--  stop_time по service_date (RANGE): окно now()..+24h тогда попадает в 1-2 секции.
-- ============================================================================

-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT ... (тот же запрос, что выше);
