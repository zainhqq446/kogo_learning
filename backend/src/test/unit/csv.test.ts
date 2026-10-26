import '../helpers/test_env.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { escapeCsvCell, toCsv, toCsvRow, UTF8_BOM } from '../../utils/csv.js';

test('csv: plain values are not quoted', () => {
  assert.equal(escapeCsvCell('buku'), 'buku');
  assert.equal(escapeCsvCell(42), '42');
  assert.equal(escapeCsvCell(0.75), '0.75');
  assert.equal(escapeCsvCell(true), 'true');
  assert.equal(escapeCsvCell(false), 'false');
  assert.equal(escapeCsvCell(null), '');
  assert.equal(escapeCsvCell(undefined), '');
  assert.equal(escapeCsvCell(new Date('2026-10-25T01:02:03.000Z')), '2026-10-25T01:02:03.000Z');
  assert.equal(escapeCsvCell(Number.NaN), '');
});

test('csv: quotes, commas and newlines are escaped per RFC 4180', () => {
  assert.equal(escapeCsvCell('TK Pelita, Jakarta'), '"TK Pelita, Jakarta"');
  assert.equal(escapeCsvCell('dia bilang "bola"'), '"dia bilang ""bola"""');
  assert.equal(escapeCsvCell('baris1\nbaris2'), '"baris1\nbaris2"');
  assert.equal(escapeCsvCell('a\r\nb'), '"a\r\nb"');
  assert.equal(escapeCsvCell(' spasi '), '" spasi "');
});

test('csv: formula injection guard prefixes = + - @ (and tab/CR) with a single quote', () => {
  assert.equal(escapeCsvCell('=HYPERLINK("http://evil","klik")'), '"\'=HYPERLINK(""http://evil"",""klik"")"');
  assert.equal(escapeCsvCell('+62812'), "'+62812");
  assert.equal(escapeCsvCell('-1+1'), "'-1+1");
  assert.equal(escapeCsvCell('@SUM(A1)'), "'@SUM(A1)");
  assert.equal(escapeCsvCell('\t=1'), "'\t=1");
  assert.equal(escapeCsvCell('=1,2'), '"\'=1,2"');
  // Angka negatif bertipe number tidak diubah (bukan input pengguna).
  assert.equal(escapeCsvCell(-5), '-5');
  // Karakter di tengah teks aman.
  assert.equal(escapeCsvCell('a=b'), 'a=b');
});

test('csv: formula injection guard also neutralises segments after `;` (semicolon-separator locales)', () => {
  assert.equal(escapeCsvCell('x;=1+1;y'), "x;'=1+1;y");
  assert.equal(escapeCsvCell('a;+62812'), "a;'+62812");
  assert.equal(escapeCsvCell('a;-1+1'), "a;'-1+1");
  assert.equal(escapeCsvCell('a;@SUM(A1)'), "a;'@SUM(A1)");
  assert.equal(escapeCsvCell('a;\t=1'), "a;'\t=1");
  assert.equal(escapeCsvCell('a;=1;=2;+3'), "a;'=1;'=2;'+3");
  // Sel yang diawali pemicu dan memuat segmen berbahaya: keduanya dinetralkan.
  assert.equal(escapeCsvCell('=a;=b'), "'=a;'=b");
  // CR memicu quoting RFC 4180 setelah netralisasi.
  assert.equal(escapeCsvCell('a;\r=1'), '"a;\'\r=1"');
  // Segmen dengan tanda kutip / koma tetap di-escape setelah netralisasi.
  assert.equal(escapeCsvCell('a;=HYPERLINK("http://evil"),b'), '"a;\'=HYPERLINK(""http://evil""),b"');
  // Titik koma biasa dan pemicu di tengah segmen tidak diubah.
  assert.equal(escapeCsvCell('a;b;c'), 'a;b;c');
  assert.equal(escapeCsvCell('a; =1'), 'a; =1');
  assert.equal(escapeCsvCell('a;b=1'), 'a;b=1');
  assert.equal(escapeCsvCell(';'), ';');
  assert.equal(toCsvRow(['ok', 'x;=1+1']), "ok,x;'=1+1");
});

test('csv: document has UTF-8 BOM, header row and CRLF line endings', () => {
  const csv = toCsv<{ name: string; age: number }>(
    [
      { header: 'name', value: (r) => r.name },
      { header: 'age', value: (r) => r.age },
    ],
    [
      { name: 'Ani', age: 5 },
      { name: '=cmd', age: 6 },
    ]
  );
  assert.ok(csv.startsWith(UTF8_BOM));
  assert.equal(csv, `${UTF8_BOM}name,age\r\nAni,5\r\n'=cmd,6\r\n`);
  assert.equal(toCsvRow(['a', null, 'b,c']), 'a,,"b,c"');
});
