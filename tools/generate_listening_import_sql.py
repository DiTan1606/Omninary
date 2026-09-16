from __future__ import annotations

import argparse
import csv
import re
import subprocess
from pathlib import Path


def sql_quote(value: str | None) -> str:
    if value is None:
        return "null"
    return "'" + value.replace("'", "''") + "'"


def audio_duration_seconds(path: Path) -> float | None:
    if not path.exists():
        return None

    result = subprocess.run(
        ["afinfo", str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    match = re.search(r"estimated duration: ([0-9.]+) sec", result.stdout)
    return round(float(match.group(1)), 3) if match else None


def word_count(text: str) -> int:
    return len(re.findall(r"[A-Za-z]+(?:['’][A-Za-z]+)?", text))


def build_sql(
    manifest_path: Path,
    audio_dir: Path | None,
    lesson_slug: str,
    series_slug: str,
    series_title: str,
    series_vi_title: str,
    audio_prefix: str,
    vi_title: str,
    output_path: Path,
    publish: bool,
    reset_progress: bool,
) -> None:
    rows = list(csv.DictReader(manifest_path.open(encoding="utf-8")))
    if not rows:
        raise ValueError(f"No rows found in {manifest_path}")

    base_dir = manifest_path.parent
    duration_audio_dir = audio_dir or base_dir
    first = rows[0]
    source_id = first["lesson_id"]
    title = first["title"]
    cefr = first["cefr"]
    is_published = "true" if publish else "false"
    progress_reset_sql = ""
    if reset_progress:
        progress_reset_sql = f"""
-- The lesson transcript changed. Existing attempts and scores no longer match
-- the expected answers, so reset only this lesson's listening progress.
delete from public.user_listening_progress
where segment_id in (
  select id
  from public.listening_segments
  where lesson_id = (
    select id
    from public.listening_lessons
    where slug = {sql_quote(lesson_slug)}
  )
);

update public.user_listening_lessons
set
  is_in_learning = false,
  completed_at = null,
  latest_score = 0,
  best_score = 0
where lesson_id = (
  select id
  from public.listening_lessons
  where slug = {sql_quote(lesson_slug)}
);
"""

    values: list[str] = []
    for row in rows:
        audio_file = Path(row["audio_file"])
        audio_path = f"{audio_prefix.rstrip('/')}/{audio_file.name}"
        local_audio_path = duration_audio_dir / audio_file.name if audio_dir else base_dir / audio_file
        duration = audio_duration_seconds(local_audio_path)
        duration_sql = "null" if duration is None else f"{duration:.3f}"
        values.append(
            "("
            + ", ".join(
                [
                    row["index"],
                    sql_quote(row["english"]),
                    sql_quote(row["vietnamese"]),
                    sql_quote(row["ipa"]),
                    sql_quote(audio_path),
                    duration_sql,
                    str(word_count(row["english"])),
                ]
            )
            + ")"
        )

    sql = f"""-- Import listening lesson: {title}
-- Listening series: {series_title}
-- Generated from {manifest_path}
-- Expected storage bucket: listening-audio
-- Expected object prefix: {audio_prefix.rstrip('/')}

begin;

with upsert_series as (
  insert into public.listening_series (
    slug,
    title,
    vi_title,
    is_published
  )
  values (
    {sql_quote(series_slug)},
    {sql_quote(series_title)},
    {sql_quote(series_vi_title)},
    {is_published}
  )
  on conflict (slug) do update
  set
    title = excluded.title,
    vi_title = excluded.vi_title,
    is_published = excluded.is_published
  returning id
),
upsert_lesson as (
  insert into public.listening_lessons (
    series_id,
    slug,
    source_id,
    title,
    vi_title,
    cefr,
    description,
    is_published
  )
  values (
    (select id from upsert_series),
    {sql_quote(lesson_slug)},
    {sql_quote(source_id)},
    {sql_quote(title)},
    {sql_quote(vi_title)},
    {sql_quote(cefr)},
    {sql_quote('Listening dictation lesson generated from Omninary source material.')},
    {is_published}
  )
  on conflict (slug) do update
  set
    series_id = excluded.series_id,
    source_id = excluded.source_id,
    title = excluded.title,
    vi_title = excluded.vi_title,
    cefr = excluded.cefr,
    description = excluded.description,
    is_published = excluded.is_published
  returning id
),
segment_data (
  order_index,
  english_text,
  vietnamese_text,
  ipa,
  audio_path,
  duration_seconds,
  word_count
) as (
  values
    {',\n    '.join(values)}
)
insert into public.listening_segments (
  lesson_id,
  order_index,
  english_text,
  vietnamese_text,
  ipa,
  audio_path,
  duration_seconds,
  word_count
)
select
  upsert_lesson.id,
  segment_data.order_index,
  segment_data.english_text,
  segment_data.vietnamese_text,
  segment_data.ipa,
  segment_data.audio_path,
  segment_data.duration_seconds,
  segment_data.word_count
from upsert_lesson, segment_data
on conflict (lesson_id, order_index) do update
set
  english_text = excluded.english_text,
  vietnamese_text = excluded.vietnamese_text,
  ipa = excluded.ipa,
  audio_path = excluded.audio_path,
  duration_seconds = excluded.duration_seconds,
  word_count = excluded.word_count;

{progress_reset_sql}

commit;

select
  l.slug,
  l.title,
  l.cefr,
  l.is_published,
  count(s.id) as segment_count
from public.listening_lessons l
left join public.listening_segments s on s.lesson_id = l.id
where l.slug = {sql_quote(lesson_slug)}
group by l.id;

select
  order_index,
  english_text,
  audio_path,
  duration_seconds,
  word_count
from public.listening_segments
where lesson_id = (
  select id
  from public.listening_lessons
  where slug = {sql_quote(lesson_slug)}
)
order by order_index;
"""

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(sql, encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument(
        "--audio-dir",
        type=Path,
        help="Optional directory containing replacement audio files with the manifest basenames.",
    )
    parser.add_argument("--lesson-slug", required=True)
    parser.add_argument("--series-slug", required=True)
    parser.add_argument("--series-title", required=True)
    parser.add_argument("--series-vi-title", required=True)
    parser.add_argument("--audio-prefix", required=True)
    parser.add_argument("--vi-title", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--draft", action="store_true")
    parser.add_argument(
        "--reset-progress",
        action="store_true",
        help="Clear existing progress for this lesson after its expected text changes.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    build_sql(
        manifest_path=args.manifest,
        audio_dir=args.audio_dir,
        lesson_slug=args.lesson_slug,
        series_slug=args.series_slug,
        series_title=args.series_title,
        series_vi_title=args.series_vi_title,
        audio_prefix=args.audio_prefix,
        vi_title=args.vi_title,
        output_path=args.output,
        publish=not args.draft,
        reset_progress=args.reset_progress,
    )
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
