<?php

declare(strict_types=1);

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/palindrome.php';

/**
 * Тест-кейсы для isPalindrome().
 *
 * Идея подбора кейсов: покрыть (а) базовые случаи и границы (пусто, 1 символ),
 * (б) разницу строгого и нестрогого режимов (регистр, пробелы, пунктуация),
 * (в) главный подводный камень — многобайтовый UTF-8 (кириллица, эмодзи,
 * комбинирующие символы), на котором ломается наивный strrev().
 */
final class PalindromeTest extends TestCase
{
    /**
     * @dataProvider cases
     */
    public function testIsPalindrome(string $text, bool $strict, bool $expected): void
    {
        self::assertSame($expected, isPalindrome($text, $strict));
    }

    /**
     * @return array<string, array{0: string, 1: bool, 2: bool}>
     */
    public static function cases(): array
    {
        return [
            // --- базовые случаи и границы ---
            'пустая строка = палиндром'    => ['', false, true],
            'один символ'                  => ['x', false, true],
            'простой палиндром'            => ['level', false, true],
            'не палиндром'                 => ['hello', false, false],

            // --- регистр и пробелы (нестрогий режим) ---
            'регистр игнорируется'         => ['LeveL', false, true],
            'фраза с пробелами'            => ['А роза упала на лапу Азора', false, true],
            'фраза с пунктуацией'          => ['A man, a plan, a canal: Panama', false, true],
            'только цифры'                 => ['12321', false, true],
            'буквы и цифры'                => ['1a2a1', false, true],

            // --- строгий режим ---
            'строгий: пробел значим'       => ['ab a', true, false],
            'строгий: регистр значим'      => ['Aa', true, false],
            'строгий: чистый палиндром'    => ['aba', true, true],

            // --- Unicode / многобайтовость (главные подводные камни) ---
            'кириллица'                    => ['шалаш', false, true],
            'кириллица не палиндром'       => ['привет', false, false],
            'combining-акцент не крашит'   => ["e\u{0301}ve", false, false],
            'эмодзи-палиндром'             => ['😀a😀', false, true],
        ];
    }
}
