-- ============================================================================
--  Расписание междугородних автобусов. СУБД: PostgreSQL 14+.
--
--  Модель: расписание хранится как КОНКРЕТНЫЕ отправления по остановкам
--  (подход, близкий к GTFS/stop_times). Благодаря этому запрос табло
--  превращается в диапазонный скан по индексу без сортировки (см. board_query.sql).
-- ============================================================================

DROP TABLE IF EXISTS stop_time, trip, bus, route, stop, city CASCADE;

-- --- СПРАВОЧНИКИ ------------------------------------------------------------

CREATE TABLE city (
    id   SMALLINT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

-- Автостанция/остановка. Именно у остановки стоит электронное табло.
CREATE TABLE stop (
    id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    city_id SMALLINT NOT NULL REFERENCES city(id),
    name    TEXT NOT NULL,
    UNIQUE (city_id, name)
);

-- Маршрут = именованная линия, напр. «Мурманск — Апатиты».
CREATE TABLE route (
    id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,   -- «210», «Э1»
    name TEXT NOT NULL
);

-- Физический автобус (по условию — 20 штук).
CREATE TABLE bus (
    id       SMALLINT PRIMARY KEY,
    plate    TEXT NOT NULL UNIQUE,           -- гос. номер
    capacity SMALLINT NOT NULL CHECK (capacity > 0)
);

-- Рейс (trip) = конкретный выход по маршруту в дату + назначенный автобус.
CREATE TABLE trip (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    route_id     INT      NOT NULL REFERENCES route(id),
    bus_id       SMALLINT NOT NULL REFERENCES bus(id),
    service_date DATE     NOT NULL,
    status       TEXT     NOT NULL DEFAULT 'scheduled'
                 CHECK (status IN ('scheduled', 'cancelled', 'departed'))
);

-- Расписание рейса по остановкам — это и есть данные для табло.
-- departure_at — момент отправления С этой остановки.
CREATE TABLE stop_time (
    trip_id      BIGINT   NOT NULL REFERENCES trip(id) ON DELETE CASCADE,
    stop_id      INT      NOT NULL REFERENCES stop(id),
    stop_seq     SMALLINT NOT NULL,          -- порядок остановки в рейсе (1,2,3,...)
    arrival_at   TIMESTAMPTZ,                -- NULL на начальной остановке
    departure_at TIMESTAMPTZ,                -- NULL на конечной остановке
    platform     TEXT,                       -- номер платформы для табло
    PRIMARY KEY (trip_id, stop_seq)
);

-- Главный индекс под запрос табло: фильтр по остановке + диапазон/порядок по времени.
-- Частичный (WHERE departure_at IS NOT NULL): у конечной остановки departure_at = NULL,
-- на табло отправлений её показывать не нужно.
CREATE INDEX idx_stop_time_board
    ON stop_time (stop_id, departure_at)
    WHERE departure_at IS NOT NULL;

-- Индексы под внешние ключи (для других запросов и каскадов; для самого табло
-- достаточно первичных ключей trip/route/bus).
CREATE INDEX idx_trip_route ON trip (route_id);
CREATE INDEX idx_trip_bus   ON trip (bus_id);
CREATE INDEX idx_stop_city  ON stop (city_id);

-- ============================================================================
--  ДЕМО-ДАННЫЕ (граф маршрутов — иллюстративный, как разрешено в условии).
--  5 городов, по одной автостанции в каждом, 6 маршрутов, 20 автобусов,
--  8 рейсов из Мурманска в ближайшие часы (чтобы табло вернуло строки).
-- ============================================================================

INSERT INTO city (id, name) VALUES
    (1, 'Мурманск'), (2, 'Апатиты'), (3, 'Кандалакша'), (4, 'Кола'), (5, 'Оленегорск');

-- Порядок вставки => stop.id: 1=Мурманск, 2=Апатиты, 3=Кандалакша, 4=Кола, 5=Оленегорск.
INSERT INTO stop (city_id, name) VALUES
    (1, 'Мурманск, автовокзал'),
    (2, 'Апатиты, автостанция'),
    (3, 'Кандалакша, автостанция'),
    (4, 'Кола, автостанция'),
    (5, 'Оленегорск, автостанция');

-- route.id: 1..6
INSERT INTO route (code, name) VALUES
    ('210', 'Мурманск — Апатиты'),
    ('305', 'Мурманск — Кандалакша'),
    ('118', 'Мурманск — Оленегорск'),
    ('402', 'Апатиты — Кандалакша'),
    ('511', 'Мурманск — Кола'),
    ('777', 'Кандалакша — Мурманск');

-- 20 автобусов
INSERT INTO bus (id, plate, capacity)
SELECT g, 'М' || lpad(g::text, 3, '0') || 'ОК51', 45
FROM generate_series(1, 20) AS g;

-- 8 рейсов из Мурманска (stop 1) на сегодня; маршруты 1,2,3,5 стартуют из Мурманска.
INSERT INTO trip (route_id, bus_id, service_date)
SELECT (ARRAY[1, 2, 3, 5])[1 + (g % 4)] AS route_id,
       (1 + g)::smallint                AS bus_id,
       CURRENT_DATE
FROM generate_series(0, 7) AS g;      -- trip.id = 1..8

-- Отправления из Мурманска (seq 1) — каждые 15 минут от «сейчас».
INSERT INTO stop_time (trip_id, stop_id, stop_seq, arrival_at, departure_at, platform)
SELECT t.id,
       1,                                             -- Мурманск
       1,
       NULL,
       now() + make_interval(mins => 10 + 15 * (t.id - 1)),
       'A' || t.id
FROM trip t;

-- Конечные остановки (seq 2) — пункт назначения каждого маршрута.
INSERT INTO stop_time (trip_id, stop_id, stop_seq, arrival_at, departure_at, platform)
SELECT t.id,
       CASE t.route_id WHEN 1 THEN 2   -- 210 -> Апатиты
                       WHEN 2 THEN 3   -- 305 -> Кандалакша
                       WHEN 3 THEN 5   -- 118 -> Оленегорск
                       WHEN 5 THEN 4   -- 511 -> Кола
       END,
       2,
       now() + make_interval(mins => 10 + 15 * (t.id - 1) + 120),  -- +2 часа в пути
       NULL,
       NULL
FROM trip t;

-- Как масштабировать до «следующих 15»: добавить ещё рейсов (trip) с отправлениями
-- из нужной остановки — LIMIT 15 в board_query.sql возьмёт ближайшие по времени.
