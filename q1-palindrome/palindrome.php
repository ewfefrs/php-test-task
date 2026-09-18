<?php

declare(strict_types=1);

/**
 * Проверяет, является ли текст палиндромом (читается одинаково слева направо
 * и справа налево).
 *
 * Важное про PHP: строка — это массив БАЙТ, а не символов. strrev() и доступ
 * по индексу $s[$i] работают побайтово и ломают многобайтовый UTF-8 (кириллица,
 * эмодзи). Поэтому сравниваем по код-поинтам через preg_split('//u'), а не
 * через strrev().
 *
 * @param string $text   Входная строка в кодировке UTF-8.
 * @param bool   $strict true  — сравнивать посимвольно как есть (регистр и
 *                               пробелы значимы);
 *                       false — «палиндром-фраза»: игнорируем регистр, пробелы
 *                               и пунктуацию («А роза упала на лапу Азора»).
 */
function isPalindrome(string $text, bool $strict = false): bool
{
    // 1. Единая форма нормализации Unicode. «é» может быть одним код-поинтом
    //    (U+00E9) или парой e + U+0301 — визуально одинаково, побайтово нет.
    //    Приводим к NFC, если доступно расширение intl.
    if (class_exists(\Normalizer::class)) {
        $normalized = \Normalizer::normalize($text, \Normalizer::FORM_C);
        if ($normalized !== false) {
            $text = $normalized;
        }
    }

    // 2. В нестрогом режиме оставляем только буквы и цифры и убираем регистр.
    //    Классы \p{L} (буква) и \p{N} (цифра) с флагом u корректно работают
    //    для кириллицы и любого другого языка.
    if (!$strict) {
        $text = preg_replace('/[^\p{L}\p{N}]/u', '', $text) ?? '';
        $text = mb_strtolower($text, 'UTF-8');
    }

    // 3. Разбиваем строку на массив код-поинтов (символов), а НЕ на байты.
    $chars = preg_split('//u', $text, -1, PREG_SPLIT_NO_EMPTY);
    if ($chars === false) {
        return false;
    }

    // 4. Два указателя навстречу друг другу — O(n) по времени,
    //    без построения полной перевёрнутой копии.
    for ($i = 0, $j = count($chars) - 1; $i < $j; $i++, $j--) {
        if ($chars[$i] !== $chars[$j]) {
            return false;
        }
    }

    return true;
}

/**
 * Пример обёртки для бекенд-эндпоинта.
 *
 * POST /palindrome  { "text": "...", "strict": false }
 *   -> 200 { "is_palindrome": true|false }
 *   -> 400 { "error": "..." }
 *
 * @param array<string,mixed> $body Разобранное тело запроса (например, json_decode).
 * @return array<string,mixed>
 */
function handlePalindromeRequest(array $body): array
{
    if (!isset($body['text']) || !is_string($body['text'])) {
        return ['error' => 'field "text" (string) is required']; // 400 Bad Request
    }

    // Предохранитель от слишком больших тел запроса (защита от DoS).
    if (mb_strlen($body['text']) > 100_000) {
        return ['error' => 'text too long'];
    }

    $strict = (bool)($body['strict'] ?? false);

    return ['is_palindrome' => isPalindrome($body['text'], $strict)];
}
