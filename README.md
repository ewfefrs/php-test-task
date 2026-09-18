# Тестовое задание — PHP-разработчик

Решения трёх задач тестового задания.

| # | Задача | Файлы |
|---|--------|-------|
| 1 | Проверка палиндрома на PHP (UTF-8-safe) + тест-кейсы | [`q1-palindrome/`](q1-palindrome/) |
| 2 | Расписание междугородних автобусов: DDL + SQL для табло, индексы, план | [`q2-bus-schedule/`](q2-bus-schedule/) |
| 3 | Интеграция Битрикс24 ↔ Moodle ↔ Личный кабинет | [`q3-integration/`](q3-integration/README.md) |

## Задача 1 — как запустить

```bash
cd q1-palindrome
php -r "require 'palindrome.php'; var_dump(isPalindrome('А роза упала на лапу Азора'));" # bool(true)
# тесты (нужен PHPUnit):
phpunit PalindromeTest.php
```

## Задача 2 — как запустить

```bash
psql -d busboard -f q2-bus-schedule/schema.sql      # DDL + демо-данные (PostgreSQL 14+)
psql -d busboard -f q2-bus-schedule/board_query.sql # запрос табло + EXPLAIN
```

## Задача 3

Проектное решение в [`q3-integration/README.md`](q3-integration/README.md).
