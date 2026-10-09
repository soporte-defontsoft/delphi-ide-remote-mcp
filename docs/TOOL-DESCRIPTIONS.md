# Tool descriptions: what they cost and how they are trimmed

The descriptions of the tools and of their parameters are the contract an agent
reads. They are also the most expensive text this server ships: an MCP client
puts the whole `tools/list` in the model's context at the start of a session,
and the model gets it again on every round of the agent (a model has no memory
between requests). Prompt caching makes the repeats cheaper, but the block keeps
its room in the context window for the whole session - room the agent needs for
code, tool answers and the conversation, and the reason a small local model
fills its window early.

## The budget

`tests/test_docs_tokens.py` (T1) keeps `tools/list` under **100,000
characters** (measured without a vault; the five `vault_*` tools come on top).
Going over it is a decision, not an accident: the battery fails and names the
size. The same battery watches the answers too (one audit line in a clean edit,
the backup path once a day...), because what accumulates round after round is
the conversation, not the fixed block.

## Where the texts live

Every description is a constant in `src/Server/Lsp.Texts.pas`: `SD_...` for a
tool, `SP_...` for a parameter (attached with `[SchemaDescription(SP_...)]`).
`delphi_help command=tool` answers with the same text `tools/list` serves.

One concept, one text. When two tools explain the same thing (the twins
`delphi_edit` / `delphi_textedit` / `delphi_changeset`, the capture tools
`delphi_desktop` / `delphi_adb`), they share the constant, or compose it from a
shared piece (`SP_CAPTURE_OUT_RULE`): two texts of one concept drift, and an
agent reads two different contracts.

## How a description is trimmed (October 2026)

Shorter is only better if the agent still makes the right call. So nothing is
cut by judgement alone: every change is measured against a small model, the
consumer that suffers most from a long list.

1. **The judge.** A small local model behind an OpenAI-compatible API (Qwen3.8
   27B on llama.cpp, the model a real agent of this project uses), spoken to the
   way its usual client speaks to it: the same reasoning effort, the same output
   limit, streaming (without streaming, a request the client abandons keeps
   generating and blocks the next ones), and one request at a time when the
   server has one slot.
2. **No MCP in between.** The tool definition comes from this server's own
   `tools/list` and goes in the `tools` field of a chat request, as a client
   would pass it; the model answers with the call it would make, and nobody
   executes it.
3. **One task per concept.** For each tool, short tasks written the way a user
   would ask ("rename UMain.pas to UPrincipal.pas", "the anchor line appears
   twice - change only the second one"), each with a checker of the call:
   the right command, the right parameters, the right values.
4. **Current text against the trimmed one,** the same tasks, three
   repetitions each. A variant goes in only if it does not lose a task the
   current text wins. When the two differ by a single miss, that task is
   repeated five more times on both texts before deciding: one miss in three
   is noise for a model that samples, and a concept that does not get through
   fails again. When the current text fails too, the description is fixed,
   not trimmed: the failure is a concept that does not reach the model.
5. **What a description promises is checked against the engine.** When the
   model's call looks wrong, the real tool is called with it before deciding:
   the measure, not the reading of the description, says whether it was wrong.
6. **The checker is measured too.** Three times a "failure" was the checker's:
   a method's `end;` counted on the wrong line, a valid `fragment` entry, a
   `push -u origin main`. A failing task is read before it is counted.
7. **Applied as measured.** The texts that won go into `Lsp.Texts.pas`
   unchanged, the server is rebuilt, and a script compares what `tools/list`
   now announces with the measured texts, character by character. Then the
   WHOLE suite before the server is deployed (some batteries check that a
   description still says a given thing), `docs/TOOLS.md`
   (`scripts/tools_md.py`), and the server is used for real.

What usually goes: the same idea explained in the description and again in a
parameter, examples beyond the first, history ("measured on..."), error codes
the agent will read in the refusal anyway. What stays: every rule, every
default, every limit, and any sentence a measured task needed.

What the measures taught:

- **A second model before believing the first.** A compact text that one model
  preferred made another one worse at the same task; the longer text stayed
  for that parameter.
- **Saying the concept beats hinting at it.** "Leading indentation may be
  omitted" did not make the model see that two lines differing only in their
  indentation are the same anchor; "it must be UNIQUE in the whole file, and
  indentation does not count" did.
- **Descriptions lie quietly.** Measuring found a description promising a key
  combination the desktop node could not press on Windows (the node has
  learned the letters since), and three commands of `delphi_paserver` that
  required the project's full .dproj path without saying so.
- **The suite guards concepts the bench did not ask about.** Several
  batteries check that a description still says a given thing. One of them
  caught a concept the trimmed text had dropped and no task measured (`type`
  with x,y costs one start of the desktop node, `tap` + `type` two); it went
  back in. The others had only lost their exact words, and their checks now
  look for the concept as it is written today.
- **The words that carry a concept are measured too, not only cut.**
  `delphi_edit`'s `old` says "indentation does not count", which was not
  exact until 1.18.0 (a line matched when it ENDED with the anchor, so an
  anchor with MORE indentation than the line was refused). Three truer
  phrasings were measured against it, eight times each on the three
  hardest tasks, and every one lost a task: with the plain words the model
  sees that two lines differing only in indentation are one anchor and adds
  `occurrence`; with the careful ones it stops doing so. The plain words
  stayed, and in 1.18.0 the engine was made to do what they say - the old
  rule made `occurrence` count other lines than the model did and a batch
  wrote the wrong one (measured).

## The first pass (October 2026)

| `tools/list`, 37 tools, no vault | 1.13.1 | after |
| --- | --- | --- |
| characters | 99,879 | 89,016 (-10.9%) |
| Qwen3.8 tokens of the same JSON | 24,574 | 22,226 (-9.6%) |

Twenty-four tools were trimmed. The largest cuts: `delphi_desktop` -25%,
`delphi_projects` -23%, `delphi_config` -21%, `delphi_symbols` -17%,
`delphi_create` -17%, `delphi_edit` -15%, `delphi_paserver` -15%. No measured
task was lost, and two tools got better: `delphi_config` (33 of 36 calls right
with its old text, 36 of 36 with the new one) and `delphi_paserver` (the
.dproj path above).

Left as they were, and why:

- `delphi_styles`: the trimmed text lost two tasks (a colour, removing a
  property), confirmed with five more repetitions. The current text stays.
- `delphi_edit`'s `edits` parameter keeps its long text (the second model,
  above).
- The LSP tools (`delphi_definition`, `delphi_hover`, `delphi_completion`,
  `delphi_signature`, `delphi_references`), `delphi_read`, `delphi_help`,
  `delphi_package`, `delphi_diagnostics` and `delphi_installs`: each is under
  1,600 characters, little to win for the cost of measuring them.
  `delphi_textedit` only took the texts it shares with its twins (27
  characters more: one concept, one text).
