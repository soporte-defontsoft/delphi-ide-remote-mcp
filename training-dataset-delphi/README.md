# Delphi fine-tuning dataset

An extra of this repository, and a cousin of the server. The **Delphi IDE Remote MCP** server gives an AI agent the
tools to work on Delphi code: read it, edit it, build it, test it, run it. This dataset is meant to make the **model
itself** fail less at Delphi. Together they are one environment for programming in Delphi with AI: the server catches
the mistakes, and the dataset teaches the model to make fewer of them.

> **Status: v6, 92 examples** (80 Delphi, 12 Python), every one verified by its judge. v1 fixed the format and the
> method; v2 added FireMonkey hit-testing; v3 and v4 are driven by a measurement: a small model was asked every
> question without the answer, its code went through the same judges, and what it got wrong became new examples (see
> [What a small model gets wrong](#what-a-small-model-gets-wrong-measured)). v4 adds locale-safe numbers, Currency,
> dynamic arrays, encodings, threads, FireDAC memory tables and "never silence an error". v5 works by patterns: each
> failure that repeats becomes several examples with variations (other units, other domains, RTL and FireMonkey,
> Delphi and Python), so that the adapter learns the rule and not the phrase. v6 follows the failures of v5: more
> FireMonkey names, escaping by hand (HTML, SQL, CSV), Floor against Trunc, and the second writer again. It grows from
> here. Apart from it, 20 [held-out questions](#held-out-questions-never-trained-on) vary the same patterns in new
> code, to measure whether a model trained on the examples learned the rule or the example.
>
> **No model has been trained with it yet.** We are building it as an extra; training a model with it and measuring
> the result is on the [roadmap](../docs/ROADMAP.md#next), for later.

## Why

**Small models know Delphi poorly.** Object Pascal is a small share of the public code models learn from. They mix
Delphi up with Free Pascal and Lazarus, invent APIs and properties, and fall into the same traps again and again.
Some measured ones:

- `FormatDateTime`: `nn` is always minutes; `mm` is the **month** unless it follows an hour specifier (`mm:ss` gives
  the month and the seconds).
- FireMonkey controls have `Text`, not `Caption`.
- `'#$2714'` inside quotes is six literal characters, not the glyph: Delphi has no escape sequences, and the code
  point goes outside the quotes (`'Sent ' + #$2714`).
- A routine asked for as a *global* procedure gets declared inside a class, or the other way round.
- A method's signature is changed in the `interface` section and not in the `implementation` one.

**Knowing how to write code is not knowing how to program.** A model can write code that compiles and still:

- write a twin of a function that already exists, two screens up;
- fix the one place it is looking at and leave the other copies of the same rule broken;
- change code for a cause that nobody measured.

The dataset teaches both: Delphi that compiles **and** the habits of programming well.

## What it is for

- Training a **LoRA** (or another fine-tune) so that a model writes correct Delphi and programs well.
- It is **tool-agnostic**. It teaches Delphi and programming, **not** how to use this server or any other tool. How to
  use a tool is learned at run time from the tool's own description, which changes from version to version; baked
  into a model's weights, it would go stale.
- A model trained with it keeps using its tools as usual (a compiler, tests, this server). The adapter only reduces
  the number of mistakes those tools have to catch.

## How the examples are made

- **Every example is new**, written for the dataset, with neutral names. No code is copied from RAD Studio's sources
  or documentation, from this repository or from any private project: they are the teachers and the judges, not the
  content.
- **Every example is verified by a real judge** before it is added, never by a model's opinion:
  - the Delphi compiler, with its version and target platform recorded;
  - tests, when the behaviour asked for can be tested;
  - the IDE's own parser, for form files (`.dfm` / `.fmx`).
- **Failed attempts are kept** as repair examples: broken code plus the compiler's message, and the fix.

## Example families

1. **task** - a task and its correct code. Judge: the compiler, and tests that run it.
2. **repair** - broken code plus the compiler's own messages, and the fix. Judge: the compiler gives exactly those
   messages for the broken code, and the fixed code compiles (and runs its tests).
3. **landscape** - look before you write: the code already has a helper, and the right answer calls it instead of
   writing a twin; or the third copy of something becomes one helper. Judge: tests, plus a declared check on the
   answer (`must_contain` / `once`).
4. **every-place** - one rule in several places with a bug in one of them: the right answer fixes the rule where it
   should live, so every place is fixed. Judge: tests on every place, plus `once`.

The landscape and every-place families also come in other languages (see below).

## Rules every example follows

- **It says it is Delphi.** "Delphi (RAD Studio 13)" in the system message or in the task, or a Delphi context (a
  `.pas` unit, existing code), and the place varies from example to example. The adapter learns "when the context is
  Delphi, do this", not "always answer in Pascal", and it learns to tell Delphi from Free Pascal.
- **10-30 % of the examples are not Delphi.** The programming rules are not Delphi's: look before you write; two
  copies make a helper with parameters; one function composes a format and its inverse reads it; measure the cause
  before changing code; what already worked is measured too. Teaching them in other languages (Python, TypeScript...)
  protects those languages and makes the rule general.
- **VCL and FireMonkey are never mixed.** Each example declares its framework (`rtl`, `vcl` or `fmx`; `none` outside
  Delphi) and its answer only speaks of that one: a FireMonkey answer never names the VCL, nor the other way round
  (the build script refuses it).
- **Conventions of a particular team or project are not in it.** They belong in that project's own instructions.

## Format

[`data/delphi-fine-tuning.jsonl`](data/delphi-fine-tuning.jsonl): one example per line, in the chat (`messages`)
format that common LoRA tools load directly (Unsloth, Axolotl, LLaMA-Factory), plus a `meta` object with `id`,
`family`, `language`, `framework`, `teaches` (what the example is for), `judge` (what verified it) and `student`
(how a small model did on the question: `bare` and `agent`, one pass judged by hand; `base3`, the three passes of the
baseline - see below. Weight the examples it failed higher). The held-out questions,
[`eval/delphi-heldout.jsonl`](eval/delphi-heldout.jsonl), come in the same format with one more field, `varies`.

## Layout, and how to rebuild it

```
examples/<language>/<id>/
  example.md           front matter + "## system" (optional), "## user", "## assistant";
                       {{code:<file>}} inserts the file the judges compiled, {{text:<file>}} a compiler message
  *.pas, given/, answer/, broken/, fixed/   the code
  dcc.txt              repair examples: the compiler's own messages
  check.py             Python examples: the judge
verify/                the Delphi judges (RAD Studio 13)
  DatasetSpecTest      compiles every RTL answer unit and runs its checks (PASS/FAIL lines, exit code = failures);
                       the SQL example runs against SQLite in memory, through FireDAC
  DatasetFmxSpecTest   the same for the FireMonkey answers: it builds control trees in memory and asks
                       FireMonkey itself which control gets a click (IControl.ObjectAtPoint). It leaves with
                       ExitProcess once its verdict is written: controls that live without an application end
                       FireMonkey's own unit finalization, now and then, in an access violation (measured, cause
                       not found) - after the checks, outside the examples' code
  DatasetPinTest       DUnitX: the tests of the examples that are written with DUnitX
  DatasetBrokenProbe   takes one broken unit at a time, to read the compiler's messages - from a short path:
                       dcc cuts the "file(line)" prefix of a message at 128 characters, line number included
  HeldoutSpecTest      the judges of the held-out questions, RTL and FireMonkey
  HeldoutFmxSpecTest
  SpecChecks.pas       what every judge shares: one PASS/FAIL line per check and the verdict as the exit code;
  FmxSpecChecks.pas    FireMonkey's own hit test, and how a FireMonkey judge leaves
eval/heldout/<language>/<id>/  the held-out questions, in the same layout - NEVER trained on
eval/delphi-heldout.jsonl  the held-out questions composed: the same format, plus meta.varies
eval/student-baseline.tsv  how a small model answered each question, training or held-out (one pass by hand, and
                       the three passes of the baseline), read into meta.student
tools/build_dataset.py the ONE writer of both JSONL files: it composes them from examples/ and eval/heldout/, and
                       checks every example
```

To rebuild the JSONL and run the Python judges: `python -I tools/build_dataset.py --python`. The Delphi judges need
RAD Studio: build and run `verify/DatasetSpecTest`, `verify/DatasetFmxSpecTest` and `verify/DatasetPinTest` (and
`verify/HeldoutSpecTest` and `verify/HeldoutFmxSpecTest` for the held-out questions).

## What a small model gets wrong (measured)

A small local model (a 3-bit quantized Qwen) was asked every question - the user message alone, without the answer
and without tools - and its code went through the same judges, one pass per version judged by hand (the baseline
below repeats it three times, automatically). Of the 67 questions of v1-v4 the bare model got 41
right, 3 partial (right result, but written by hand where the RTL already had it) and 23 wrong; of the 15 of v5, 7
right, 4 partial and 4 wrong; of the 10 of v6, 4 right and 6 wrong. The questions of v1 and v2 were also asked to
the same model inside an agent with a
persistent memory: 21 of 32 right, like the bare model. Every example carries its result in `meta.student`
(`eval/student-baseline.tsv`). What failed, by pattern:

| Pattern | Seen |
|---|---|
| A type used without the unit it lives in, or with the wrong one (`TStringList`, `TComponent`, `TNotifyEvent`, `TThread` without System.Classes; `TComparer` without System.Generics.Defaults; `TProc`, `IntToStr` without System.SysUtils; `TBrushKind` without FMX.Graphics; `TMemo` looked for in FMX.Controls, `TVertScrollBox` in FMX.ScrollBox; `TPointF`, `TCursor`, `TLabel`...) | by far the most frequent - every FireMonkey answer of v3 failed on it, both of v5, and three of the four of v6 |
| Invented names: units `FMX.Rect`, `FMX.Rectangle`, `FMX.Switch`, `FMX.Tabs`, `Data.DBCtrls`; types `TFillType` and `TAlign` (FireMonkey's is `TAlignLayout` - kept even with the compiler's message in front of it); members of `TBase64Encoding`; function `ChangeExt`; the .NET name `TopDirectoryOnly`; `System.SysUtils.WriteLn`; `TList<T>.Sort` given a function | in both conditions |
| Two writers of one format kept, with a reader tolerant of both | the bare model, 4 times out of 4 in v1-v4; when the bug report points at the READER, 3 times out of 3 in v5-v6 (Delphi and Python), and once more the format was copied into the second writer instead of calling the first. Asked to ADD a third use, it called the writer both times |
| A shared helper changed without pinning its callers - the change broke them both | once (the tests caught it); in v5 the change kept them, but it pinned none of them |
| Written by hand what the RTL already has: the leap-year rule, the days of a month, an ISO 8601 parser, rounding (`Trunc(x * 100 + 0.5)`), the centre of a rectangle, JSON by concatenation - with no escaping, or escaping a short list that leaves other control characters raw -, HTML escaped by hand (the order fixed, the double quote left), FireMonkey's hit test (it crashed outside a form) | repeatedly |
| A test of its own that states what its code does not do (`-0.125` gives `-0.13`; the code gives `-0.12`) | once |
| A unit without `implementation` (and the first error misleads) | once |
| `DayOfWeek` (Sunday = 1) read with ISO numbers | once |

What it already knew - `nn` and `mm`, character codes outside the quotes, `Copy` from 1, a signature in two places,
`div`, `Currency` for money, the invariant format settings, copying a dynamic array, catching only the expected
exception, reusing the helper in front of it, SQL parameters, `Floor` for negative values, the `csv` module - stays, at a lower priority. v3 and v4 were aimed at the failures. The
repair examples reproduce the PATTERN of each failure in new code: no output of the model is in the dataset.
Three cautions. One pass is noisy: the baseline below moves by up to six questions from one pass to the next. Up to
v4 the questions asked for ONE code block, so a model could not show tests written next to the change - the "tests
before the change" examples are judged on the change alone (in the baseline it may add its tests in a second block;
the judge still runs ours). And up to v4 each question was headed by the example's id, which names the lesson
(`r20-field-types-need-data-db`); from v5 the headers are neutral (`Q01`, `Q02`...). Measured with the baseline, that
hint gave no visible advantage: the hinted pass falls inside the range of the neutral ones.

### The baseline: three passes, before any training

All 92 questions were asked three more times to the bare model, under neutral headers, in batches of 12, with fixed
sampling (temperature 0.6, top_p 0.95, top_k 20). Every answer was judged automatically by the same judges, through
this repository's own MCP server: the student's unit takes the place of ours in a copy of the dataset, `delphi_test`
builds that judge and runs it in its container, and ours goes back; a Python answer runs the same `check.py`. The
verdict is about behaviour. `partial` = right behaviour, but a declared check missed (`must_contain` / `once`: the RTL
or the one writer not used). A `fact` check that calls the student's code and asks more than the question did (the
hours of a day, fractions of a second) is not counted.

| Pass | Right | Partial | Wrong | Does not compile | Names the judge could not call |
|---|---|---|---|---|---|
| 1 | 43 | 8 | 13 | 26 | 2 |
| 2 | 46 | 8 | 11 | 27 | 0 |
| 3 | 49 | 12 | 10 | 19 | 2 |

Per question: right in all three passes 34, in none 35, sometimes 23. Right, by framework: FireMonkey 39 %, Python
47 %, RTL 53 %; by family: repair 68 %, task 51 %, landscape 49 %, every-place 13 %. The 67 questions of v1-v4, which
had been asked once with the hint in the header (41 right), gave 32, 36 and 42 right here. Each example carries its
three verdicts in `meta.student.base3`.

## Held-out questions (never trained on)

[`eval/delphi-heldout.jsonl`](eval/delphi-heldout.jsonl) holds 20 questions in the same format, **never to be
trained on**. After training, the dataset's own questions say what the adapter took from its examples; these say
whether it learned the rules. Each one varies the pattern of some examples in new code (another unit, another type,
another domain) and names those examples in `meta.varies`:

- an invented FireMonkey unit (`FMX.CheckBox`), `alClient` in a FireMonkey unit, `TSpinBox` and its unit, a
  rectangle with no border, a badge that takes the button's clicks;
- `TInterlocked` without `System.SyncObjs`, `TComparer` without `System.Generics.Defaults`;
- `mm` in a lap time, `Copy` from the end of a string, `case` on a string, `Round` on a half;
- the ISO week, a month added at the end of a month, an extension changed (`TPath.ChangeExtension` does not exist in
  Delphi: measured);
- a normalizer the unit already has, a rule copied three times, a second writer of a lot code, in Delphi and in
  Python.

One of them (`varies: none`) is a control: something no example teaches (operators on a record), to see whether an
adapter takes away what the model already knew. They live in a tree of their own (`eval/heldout/`), judged by
`verify/HeldoutSpecTest` and `verify/HeldoutFmxSpecTest`, and the same writer composes them into a file of their own,
so a training run that loads `data/` never sees them.

Their baseline is the same three passes as above, with the same model, sampling and verdicts:

| Pass | Right | Partial | Wrong | Does not compile |
|---|---|---|---|---|
| 1 | 8 | 3 | 2 | 7 |
| 2 | 11 | 2 | 3 | 4 |
| 3 | 10 | 4 | 2 | 4 |

Per question: right in all three passes 7, in none 8, sometimes 5. That is the level of the dataset's own questions
(40-55 % right here, 47-53 % there). By framework, FireMonkey 40 %, Python 50 % and RTL 51 %; by family, task 62 %,
landscape 60 %, repair 41 % and every-place 0 of 9. What failed is what the examples teach:

- invented FireMonkey names (a unit `FMX.Shapes`, a property `HitClick`, `Caption` on a check box);
- types without their unit (`TAlphaColor`, `TBrushKind`, `TFmxObject`, `TArray`, `TInterlocked`);
- the ISO week, an extension and a month added by hand;
- the copied rule fixed in one copy only, three passes out of three;
- the second writers kept, with the reader taught both shapes, in Delphi and in Python.

The control was right every time. After training, a gain here is what the dataset is for, and a drop on the control is
what it must not do. Each question carries its three verdicts in `meta.student.base3`.

A judge of these questions runs from a short path: dcc cuts the "file(line)" prefix of its messages at 128
characters, and a message cut that way can get lost. A student's compile error would then read as a name the judge
could not call - measured on the first count of this baseline, which put nine compile errors there.

## Training and measuring

- Train it as a **separable adapter**: load it when working on Delphi; without it, the base model is untouched
  (llama.cpp, for example, takes it with `--lora`).
- Train gently: a low rank and few epochs.
- **The baseline above is the "before" on the dataset's own questions**: after training, the same three passes -
  neutral headers, the same sampling, the same judges - show what the adapter took from its own examples. That is a
  ceiling, not the result: it trained on them. A gain smaller than the spread between passes (about six questions) is
  noise.
- **Measure before and after**, with the same judges, on questions that are never trained on (the
  [held-out questions](#held-out-questions-never-trained-on)), several passes each:
  - compiles on the first attempt, and how many rounds of compiler errors it takes to get there;
  - invented units and APIs (unknown-unit and undeclared-identifier errors on names that do not exist);
  - the existing primitive found or a twin written (the `must_contain` / `once` checks of the landscape and
    every-place families);
  - another language (a standard Python benchmark, for example): it must not drop. What already worked is measured
    too.
- **For a model working as an agent**, the number that matters most: how many corrective tool calls a task needs
  (calls refused, builds that fail) before and after the adapter. Compiling at the first attempt may rise a little
  while those calls drop a lot - and that is the real gain.
- **Grow it from real failures, not to a size.** The loop is: a small model answers the questions, a repeatable
  failure becomes a pattern, the pattern becomes examples - with variations (other domains, other units, RTL and
  FireMonkey), so that the adapter learns the rule and not the phrase - and every example passes a real judge.

## What is not in it

- No RAD Studio sources or documentation: the examples compile against the RTL, they do not copy it.
- No code from this repository or from private projects.
- No paths, user names or machine addresses. The repository's checks (`tests/test_docs_static.py`) run over every
  versioned file, this folder included.

## License

MIT, like the rest of the repository (see [LICENSE](../LICENSE)). An example is only added when the terms of the
model that generated it allow it.
