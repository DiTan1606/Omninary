# Omninary Extraordinary v1: adaptive spaced repetition driven by learner data

**Version v2 of the design, 22/10/2026.** Applies Tân's review comments to v1. It builds on the decisions settled with Codex (`AISC26/CodexHistory/00_TOM_TAT_QUYET_DINH.md`) and the listen–write convention from 20/10.

**Principles**
- Every rule is **explainable** (rule-based) and versioned (`algorithm_version = extra_v1`).
- The **server** decides level and review date inside one transaction.
- Ditandnary and Extraordinary share **the same exercise types, the same scoring and the same data**. Ditan only records them; Extra **uses** the data to personalise three things:
  - **content**: the learner chooses which words to study;
  - **timing**: jump a level, level up, or hold the level with a sooner make-up review;
  - **form**: extra practice on weak skills.

## 1. Data loop

```text
Review list (prioritised) → learner picks words
→ Session = 1 question per exercise type for each word (+ Extra reinforcement for weak skills)
→ Every attempt records interaction signals → attempt score + skill evidence
→ Exercise score E (whole process) → mastery score M of the word
→ Extra: decides level + next review date
→ Skill profile updated → decides which exercise types are reinforced next session
```

## 2. Five exercise types (final) and five skills

| # | Exercise type | What the learner does | Main skill observed | Secondary skill | Weight in M |
|---|---|---|---|---|---:|
| 1 | **Listen–write with context** | Hears the word; sees the example sentence with the word blanked; types the word | Sound | Spelling | 0.20 |
| 2 | **Meaning → write** | Sees the English meaning, its Vietnamese translation and the Vietnamese meaning; types the word | Active recall | Spelling | 0.25 |
| 3 | **Meaning → pick the word** | Sees the 3 meanings; picks the right English word out of 4 | Meaning recognition | — | 0.15 |
| 4 | **Sentence scramble** | Puts the shuffled example-sentence tokens back in order (Vietnamese translation shown) | Context | — | 0.20 |
| 5 | **Read the example sentence** | Listens to the model if needed, records, Azure scores it | Sound (reproduce) | — | 0.20 |

All 9 required fields are always present, so **every word has all 5 types**.

**The 5 skills of a word**, each estimated from several exercise types so they can be cross-checked:

| Skill | Meaning | Evidence comes from |
|---|---|---|
| **Meaning** (recognition) | Recognises which word carries the meaning | Meaning → pick |
| **Recall** (active) | Retrieves the word on its own from the meaning | Meaning → write |
| **Spelling** | Writes the word correctly | Meaning → write **and** listen–write |
| **Sound** (phonological form) | Recognises the sound of the word and reproduces it | Listen–write (hear → write) **and** read-aloud (hear → speak) |
| **Context** | Uses the word in a sentence | Sentence scramble |

## 3. Interaction data recorded on every attempt

**Common to all types**
- When the question was shown; time to first interaction (first keystroke or tap) = "thinking time".
- Active time: time spent with the app in the background is excluded and recorded separately as pause count and pause duration.
- Number of submissions, content of each submission, right or wrong.
- Support used, with the time it was opened: hint level, give up, rescue.
- Attempt number of that question within the session.
- Position of the question in the session.
- Number of questions since the learner last saw an answer card for the same word. This tracks exposure: whether the word's answer was already seen earlier in the session.

**Specific to each type**

| Type | Additional signals |
|---|---|
| Listen–write | Autoplay ran; number of replays; speed of each play (1, 0.75, 0.5); time from end of audio to first keystroke; number of deletions; **classification of wrong answers**: *near* (right word, misspelled: edit distance ≤ max(1, length/5)) or *far* (a different word) |
| Meaning → write | Thinking time; deletions; near/far wrong classification; which hints were opened |
| Meaning → pick | Time to choose; **which distractor was picked** (confusion pairs); whether the example hint was opened; whether 2 options were eliminated |
| Sentence scramble | Time to first tap; number of tokens moved; number of removals (undo); **share of tokens in correct position** on a wrong submission; length of the correct prefix |
| Read aloud | Number of times the model was played; number of recordings; overall Azure score + accuracy, fluency, completeness, prosody; **accuracy score of the target word**; time to start recording |

## 4. Attempt score (0–100)

- **Wrong, give up, or opened hint 3 (answer shown)** → **0**.
- **Correct** → `100 − support fees − slowness fee`, minimum 0.
- **Above 50 passes. 50 or less goes to the end of the queue to retry.**

| Support or signal | Applies to | Fee |
|---|---|---:|
| Replay | Listen–write | 1 per play |
| Slow down 0.75× / 0.5× | Listen–write | 5 / 10 (highest level used) |
| Rescue (retype once after a wrong first submission when no support has been used) | Listen–write, meaning → write | 10 |
| Hint 1 | Listen–write: English definition · Meaning → write: example sentence with the word blanked · Pick: example sentence with the word blanked · Scramble: first token placed for you | 50 (listen–write) / 25 (other types) |
| Hint 2 | Listen–write: Vietnamese translation of the definition · Meaning → write: first letter + number of letters · Pick: eliminate 2 wrong options · Scramble: half the sentence placed | 25 more |
| Hint 3 | Show the answer | attempt score = 0 |
| **Slowness** | Every type except read-aloud | `min(15, max(0, (active time / reference time − 1) × 10))` |
| Read aloud | — | Attempt score = Azure score of the sentence; the existing pass threshold still applies |

**Reference time** (fixed in v1; later it can be personalised from each learner's own median):
- Listen–write: 10 s + 0.5 s per letter
- Meaning → write: 12 s + 0.5 s per letter
- Pick: 8 s
- Scramble: 3 s per token

Rationale: retrieval speed is a signal of memory strength (Wilschut et al., 2024). The slowness fee is capped at 15 points so that a slow but correct answer still passes.

## 5. Exercise score in the session: the whole process

```text
L_type = Σ over attempts (100 − attempt score)
E_type = 100 / (1 + L_type / 100)
```

Examples: 100 → 100 · 90 → 90.9 · 50 → 100 gives 66.7 · 50 → 50 → 100 gives 50 · 0 → 0 → 0 → 100 gives 25. With reinforcement questions, every attempt of that type for that word in the session is counted.

## 6. Skill scores: cross-checking across exercise types

Each attempt produces a **skill cost**, assigned according to the cause indicated by the signals:

| Type | Sound | Spelling | Recall | Meaning | Context |
|---|---|---|---|---|---|
| Listen–write | replays + slow-down + meaning hints + **100 × far wrong answers**; hint 3 → 100 | **50 × near wrong answers** | | | |
| Meaning → write | | **50 × near wrong answers** | hints 1–2 (25 each) + **100 × far wrong answers**; give up/hint 3 → 100 | | |
| Pick | | | | 100 × wrong picks + hints (25 each); give up → 100 | |
| Scramble | | | | | wrong submission: `100 × share of misplaced tokens` (minimum 30) + hints (25 each) + excess undos (2 each, max 20); give up → 100 |
| Read aloud | `100 − target-word accuracy` (or the sentence score when not available) for each recording + 1 per model replay | | | | |
| Slowness fee | goes to the main skill of that type | | | | |

`skill score in the session = 100 / (1 + Σ cost / 100)`, computed only for skills that have evidence.

**How skills are compared to find the cause** (the examples from Tân's review):
- Listen–write has **near** wrong answers, and meaning → write has near wrong answers too → **spelling** is weak (it shows up in both types) → reinforce meaning → write.
- Listen–write has **far** wrong answers or needs meaning hints, but meaning → write is correct immediately → spelling and recall are fine and **sound** is weak → reinforce listen–write. If read-aloud also gives a low target-word score, the sound of the word is weak in both directions (hear → write and hear → speak).
- Meaning → write fails (far) but pick is correct → recognises the meaning but **cannot recall** the word → reinforce meaning → write.
- Pick and recall are fine, scramble fails → knows the word but **context** is weak → reinforce sentence scramble.

## 7. Mastery score of a word: M

`M = Σ (weight × E_type) / Σ weights` (weights in section 2). Both Ditan and Extra store M at every review.

## 8. Level and review-date decision (applied by Extra only)

Base schedule: `days(level)` = 0, 1, 3, 7, 15, 30, 60, 120, 240, 365. **Levels only go up or hold; they never go down.**

1. Finishing a session → **level reached** = current level + 1. If the word is in *hold* state, level reached = current level and the attempt count at that level goes up by 1 (4.1 → 4.2).
2. `drop = max(0, previous M − M)`.

| Condition | Decision | Stored level | Next review after |
|---|---|---|---|
| M ≥ 85 and drop ≤ 5 | **Jump a level** | level reached + 1 | `days(level reached + 1)` |
| M < 60, or drop ≥ 20 | **Hold the level, make-up review sooner** | level reached (marked hold) | `max(1, round(days(level reached − 1) × r))` |
| Everything else | **Level up normally** | level reached | `days(level reached)` |

`r = clamp(M/100 − drop/200, 0.15, 0.80)`.

Example: level 3 → 4th review after 7 days, M drops from 80 to 45. The word holds at **level 4 (attempt 1)**, `r = 0.275`, make-up review after **2 days**.

Maximum level is 10 (Super). Ditan always takes "level up normally".

## 9. Personalising form: reinforcement, never removal

- **Base set (Ditan and Extra): every word gets exactly 1 question of each of the 5 types.** Nothing is ever dropped, so no type gets forgotten.
- **Extra adds reinforcement questions** based on the **skill profile**: EWMA (Exponentially Weighted Moving Average), α = 0.5, of the session skill scores.

| Skill score in the profile | Reinforcement |
|---|---|
| < 60 | +2 questions |
| 60 – < 80 | +1 question |
| ≥ 80, or no data yet | 0 |

**Exercise type used to reinforce each skill:**
- Meaning → pick
- Recall → meaning → write
- Spelling → whichever of meaning → write and listen–write has the higher spelling cost
- Sound → whichever of listen–write and read-aloud has the lower E in the profile
- Context → sentence scramble

At most **+3 reinforcement questions per word**. Reinforcement questions go into later rounds, as far as possible from the base question of the same word. Each word shows its **reason**, for example: "Sound is weak (48): +2 listen–write · Spelling 72: +1 meaning → write".

**Question order** (both versions): **interleaved in rounds**.
- Round 1: each word gets one question, then round 2, and so on.
- Words are reshuffled each round, and two questions of the same word are kept at least 2 questions apart where possible.
- The first type asked for each word rotates across sessions: the type that has gone longest without being asked first goes first.

## 10. Personalising content: the review list

The **Review now** screen shows **every word due** (including new words at level 0) with a status label:
- New word
- Due today
- **N days overdue**
- On hold (level 4.2)
- Last M score

Words are **sorted by priority**:

```text
priority = days overdue / max(1, current interval) + (100 − last M)/100 + 0.5 if on hold + 0.3 if new word
```

- **Ditandnary:** must pick **exactly 5 words** (or all of them when fewer than 5 are due). There is a "Pick the 5 highest priority" button. **10 sessions/day**, to fit the experiment schedule.
- **Extraordinary:** picks freely, **from 1 to as many words as wanted**. There are "Pick 5 highest priority" and "Pick all" buttons. No session limit.

## 11. Data storage

- `learning_attempts` (already exists) gains: `attempt_score`, `signals` (jsonb: the section 3 signals), `skill_costs` (jsonb: per-skill costs).
- `learning_word_mastery` (new): one row per word per review:
  - mode, level before / reached / stored, attempt count at the level;
  - E for each type, score for each skill, M and previous M;
  - decision, next review date, reason, `algorithm_version`.
- `learner_word_skill_profiles` (new): EWMA per skill and per type, number of observations, last time seen, last time asked first.
- Everything is computed **on the server** from the attempt data in one transaction, so re-sending does not duplicate (keyed by session id).

## 12. Out of scope for v1 (to do before the final)

- "Report a problem" / "Can't listen right now" and the continuation session for postponed listening questions.
- Personalising the reference time from each learner's own median.
- Calibrating the 85/60/20 thresholds, the M weights and the skill costs with data from the 200-word experiment.
