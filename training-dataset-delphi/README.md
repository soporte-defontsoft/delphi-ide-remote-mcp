# Delphi fine-tuning dataset

An extra of this repository, and a cousin of the server. The **Delphi IDE Remote MCP** server gives an AI agent the
tools to work on Delphi code: read it, edit it, build it, test it, run it. This dataset is meant to make the **model
itself** fail less at Delphi. Together they are one environment for programming in Delphi with AI: the server catches
the mistakes, and the dataset teaches the model to make fewer of them.

> **Status: v3, 53 examples** (46 Delphi, 7 Python), every one verified by its judge. v1 fixed the format and the
> method; v2 added FireMonkey hit-testing; v3 is driven by a measurement: a small model was asked every question
> without the answer, its code went through the same judges, and what it got wrong became new examples (see
> [What a small model gets wrong](#what-a-small-model-gets-wrong-measured)). It grows from here, with the server.
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
`family`, `language`, `framework`, `teaches` (what the example is for) and `judge` (what verified it).

## Layout, and how to rebuild it

```
examples/<language>/<id>/
  example.md           front matter + "## system" (optional), "## user", "## assistant";
                       {{code:<file>}} inserts the file the judges compiled, {{text:<file>}} a compiler message
  *.pas, given/, answer/, broken/, fixed/   the code
  dcc.txt              repair examples: the compiler's own messages
  check.py             Python examples: the judge
verify/                the Delphi judges (RAD Studio 13)
  DatasetSpecTest      compiles every RTL answer unit and runs its checks (PASS/FAIL lines, exit code = failures)
  DatasetFmxSpecTest   the same for the FireMonkey answers: it builds control trees in memory and asks
                       FireMonkey itself which control gets a click (IControl.ObjectAtPoint)
  DatasetPinTest       DUnitX: the tests of the examples that are written with DUnitX
  DatasetBrokenProbe   takes one broken unit at a time, to read the compiler's messages - from a short path:
                       dcc cuts the "file(line)" prefix of a message at 128 characters, line number included
tools/build_dataset.py the ONE writer of the JSONL: it composes it from examples/ and checks every example
```

To rebuild the JSONL and run the Python judges: `python -I tools/build_dataset.py --python`. The Delphi judges need
RAD Studio: build and run `verify/DatasetSpecTest`, `verify/DatasetFmxSpecTest` and `verify/DatasetPinTest`.

## What a small model gets wrong (measured)

Before v3, a small local model (a 3-bit quantized Qwen) was asked every question of v1 and v2 - the user message
alone, without the answer and without tools - and its code went through the same judges. Two conditions: the bare
model, and the same model inside an agent with a persistent memory. Of 32 questions, each got 21 or 22 right. What
failed, by pattern:

| Pattern | Seen |
|---|---|
| A type used without the unit it lives in (`TStringList` without System.Classes, `TComparer` without System.Generics.Defaults, `TLabel` without FMX.StdCtrls, `TNotifyEvent`, `TPointF`, `TCursor`...) | the most frequent, in both |
| Invented names: units `FMX.Rect` and `FMX.Rectangle`, type `TFillType`, function `ChangeExt`, `System.SysUtils.WriteLn`, `TList<T>.Sort` given a function | in both |
| A unit without `implementation` (and the first error misleads) | once |
| Two writers of one format kept, with a reader tolerant of both | the bare model, twice |
| No tests pinning the callers before changing a shared helper | both, every time |
| FireMonkey's hit test re-implemented by hand instead of asked (`ObjectAtPoint`) - it crashed outside a form | both |
| `DayOfWeek` (Sunday = 1) read with ISO numbers | once |

What both already knew - `nn` and `mm`, character codes outside the quotes, `Copy` from 1, a signature in two
places, reusing the helper in front of them - stays, at a lower priority. v3 adds 21 examples aimed at the failures.
The repair examples reproduce the PATTERN of each failure in new code: no output of the model is in the dataset.
One pass is noisy (an item failed in one condition and not in the other), so the baseline for a trained model has to
be several passes.

## Training and measuring

- Train it as a **separable adapter**: load it when working on Delphi; without it, the base model is untouched
  (llama.cpp, for example, takes it with `--lora`).
- Train gently: a low rank and few epochs.
- **Measure before and after**, on an evaluation set that is never trained on:
  - Delphi: compiles on the first attempt, invented APIs, twins written;
  - another language (a standard Python benchmark, for example): it must not drop. What already worked is measured
    too.

## What is not in it

- No RAD Studio sources or documentation: the examples compile against the RTL, they do not copy it.
- No code from this repository or from private projects.
- No paths, user names or machine addresses. The repository's checks (`tests/test_docs_static.py`) run over every
  versioned file, this folder included.

## License

MIT, like the rest of the repository (see [LICENSE](../LICENSE)). An example is only added when the terms of the
model that generated it allow it.
