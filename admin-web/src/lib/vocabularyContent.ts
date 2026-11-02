import type { VocabInput } from './types';

export const coreVocabularyFields = ['word', 'cefr', 'ipa', 'word_form', 'e_meaning', 'ev_meaning', 'v_meaning', 'e_example', 'v_example'] as const;
export const supplementaryVocabularyFields = ['word_family', 'synonymous', 'antonym', 'collocation', 'formula', 'note', 'bonus'] as const;
const labels: Record<typeof coreVocabularyFields[number], string> = {
  word: 'Từ vựng', cefr: 'Trình độ ngôn ngữ', ipa: 'Phiên âm', word_form: 'Từ loại',
  e_meaning: 'Nghĩa tiếng Anh', ev_meaning: 'Dịch nghĩa tiếng Anh', v_meaning: 'Nghĩa tiếng Việt',
  e_example: 'Ví dụ tiếng Anh', v_example: 'Ví dụ tiếng Việt'
};

export function supplementaryValues(value: string | null | undefined): string[] {
  return (value ?? '').split(';').map((part) => part.trim()).filter(Boolean);
}

export function normalizeSupplementaryText(value: string | null | undefined): string | null {
  return supplementaryValues(value).join('; ') || null;
}

export function vocabularyContentError(input: Pick<VocabInput, typeof coreVocabularyFields[number]> & Partial<VocabInput>): string | null {
  const missing = coreVocabularyFields.filter((field) => typeof input[field] !== 'string' || !input[field].trim() || (field.endsWith('example') && ['...', '…'].includes(input[field].trim())));
  if (missing.length) return `Vui lòng bổ sung: ${missing.map((field) => labels[field]).join(', ')}.`;
  const annotated = [...coreVocabularyFields, ...supplementaryVocabularyFields].filter((field) => /[\r\n]\(Nhận xét ưu tiên [123]:/.test(input[field] ?? ''));
  if (annotated.length) return `Hãy xử lý và xoá nhận xét trong các ô: ${annotated.join(', ')} trước khi nhập.`;
  return null;
}

export function requireVocabularyContent(input: VocabInput): void {
  const error = vocabularyContentError(input);
  if (error) throw new Error(error);
}
