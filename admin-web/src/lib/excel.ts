import { readSheet } from 'read-excel-file/browser';
import writeXlsxFile from 'write-excel-file/browser';
import type { SheetData } from 'write-excel-file/browser';
import { ImportRow, Topic, VocabCatalog, VocabInput } from './types';

const aliases: Record<keyof Omit<VocabInput, 'id' | 'topic_id'>, string[]> = {
  word: ['word', 'vocab', 'tu', 'tu vung', 'từ', 'từ vựng'],
  cefr: ['cefr', 'level', 'cap do', 'cấp độ'],
  ipa: ['ipa', 'pronunciation', 'phien am', 'phiên âm'],
  word_form: ['word_form', 'word form', 'type', 'loai tu', 'loại từ'],
  e_meaning: ['e_meaning', 'english meaning', 'e meaning', 'nghia anh', 'nghĩa anh'],
  ev_meaning: ['ev_meaning', 'english vietnamese meaning', 'ev meaning', 'anh viet', 'anh việt'],
  v_meaning: ['v_meaning', 'vietnamese meaning', 'v meaning', 'nghia viet', 'nghĩa việt'],
  e_example: ['e_example', 'english example', 'example', 'vi du anh', 'ví dụ anh'],
  v_example: ['v_example', 'vietnamese example', 'translation', 'vi du viet', 'ví dụ việt'],
  word_family: ['word_family', 'word family', 'gia dinh tu', 'gia đình từ'],
  synonymous: ['synonymous', 'synonym', 'dong nghia', 'đồng nghĩa'],
  antonym: ['antonym', 'opposite', 'trai nghia', 'trái nghĩa'],
  bonus: ['bonus', 'note', 'ghi chu', 'ghi chú']
};

function normalizeHeader(value: string) {
  return value
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[_-]+/g, ' ')
    .replace(/\s+/g, ' ');
}

function readCell(row: unknown[], headers: string[], field: keyof typeof aliases) {
  const wanted = aliases[field].map(normalizeHeader);
  const index = headers.findIndex((header) => wanted.includes(normalizeHeader(header)));
  const value = index >= 0 ? row[index] : '';
  return value == null ? '' : String(value).trim();
}

export async function parseVocabularyWorkbook(file: File, topicId: string | null): Promise<ImportRow[]> {
  const sheetRows = (await readSheet(file)) as unknown as unknown[][];
  const headers = (sheetRows[0] ?? []).map((cell: unknown) => String(cell ?? ''));
  const rows = sheetRows.slice(1);

  return rows.map((row: unknown[], index: number) => {
    const parsed: ImportRow = {
      rowNumber: index + 2,
      topic_id: topicId,
      word: readCell(row, headers, 'word'),
      cefr: readCell(row, headers, 'cefr'),
      ipa: readCell(row, headers, 'ipa'),
      word_form: readCell(row, headers, 'word_form'),
      e_meaning: readCell(row, headers, 'e_meaning'),
      ev_meaning: readCell(row, headers, 'ev_meaning'),
      v_meaning: readCell(row, headers, 'v_meaning'),
      e_example: readCell(row, headers, 'e_example'),
      v_example: readCell(row, headers, 'v_example'),
      word_family: readCell(row, headers, 'word_family'),
      synonymous: readCell(row, headers, 'synonymous'),
      antonym: readCell(row, headers, 'antonym'),
      bonus: readCell(row, headers, 'bonus')
    };

    if (!parsed.word) parsed.error = 'Thiếu từ vựng';
    return parsed;
  });
}

export async function exportVocabularyWorkbook(topic: Topic, vocabs: VocabCatalog[]) {
  const headers = [
    'word',
    'cefr',
    'ipa',
    'word_form',
    'e_meaning',
    'ev_meaning',
    'v_meaning',
    'e_example',
    'v_example',
    'word_family',
    'synonymous',
    'antonym',
    'bonus'
  ];

  const data = [
    headers.map((header) => ({ value: header, fontWeight: 'bold' })),
    ...vocabs.map((vocab) =>
      [
        vocab.word,
        vocab.cefr,
        vocab.ipa,
        vocab.word_form,
        vocab.e_meaning,
        vocab.ev_meaning,
        vocab.v_meaning,
        vocab.e_example,
        vocab.v_example,
        vocab.word_family,
        vocab.synonymous,
        vocab.antonym,
        vocab.bonus
      ].map((value) => ({ value: value ?? '' }))
    )
  ] as SheetData;

  const file = await writeXlsxFile(data);
  await file.toFile(`omninary-${topic.name.replace(/[^a-z0-9]+/gi, '-').toLowerCase()}.xlsx`);
}
