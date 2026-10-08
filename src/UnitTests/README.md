# `src/UnitTests/` — the engine's DUnitX suite

`LspUnitTests.dproj` is a DUnitX console runner (born with
`delphi_create kind=project-test` on 2026-09-24) with one fixture per engine
area:

| Fixture | What it pins down |
|---|---|
| `LspTests.Encodings` | The ONE encoding detector of `Lsp.Patch` and its inverses (`Lsp.Codificacion`): UTF-8 with and without BOM, CP1252, UTF-16 LE/BE by BOM, the round trip of every kind, `EncKindOf(EncName(k)) = k`, the BOM lengths, what CP1252 refuses, `Measure` on UTF-16, and the "is this text at all" rule (a NUL byte, never for UTF-16). |
| `LspTests.DesignerBin` | The shape of a designer file (text, raw TPF0, resource-wrapped binary), the RTL round trip text -> binary -> text, accents as `#NNN`, what falls outside ANSI, a damaged binary. |
| `LspTests.Dproj` | The build-hazard scan: a clean project, a build event, the same event ignored on request, an empty event, an `Exec` task that stays a hazard whatever is ignored. |
| `LspTests.GitArgs` | The git argument splitter (`TrocearArgs`, the Windows CRT rules) and its inverse (`EnComillas`): what the gate validates is exactly what git receives. |
| `LspTests.Images` | The captures: the frame token and its inverse, the inline delivery, the reason a screenshot did not happen (`MotivoSinCaptura`). |
| `LspTests.Mensajes` | The message catalog: every tag, the outcome a message declares, `MsgEnvuelve` (a cause that already declares one passes through) and the readers of the result. |
| `LspTests.Pascal` | The Pascal lexer: directives that are real (never inside a comment or a string), and a brace comment with another brace inside. |
| `LspTests.Foto` | The undo of every all-or-nothing write (`TFotoDeFicheros`): it puts back what the operation wrote, never overwrites or deletes what someone else changed afterwards, and deletes a file the operation created. The runner gives itself a jail (its own folder) when nobody gives it one, so the undo is measured wherever it runs. |
| `LspTests.Log` | The bounded line buffer shared by the log on disk and the tray window (`TBuzonDeLineas`): it stops at `LOG_BUF_CAP`, counts what did not fit and says it once, last, when collected; lines that could not be written go back in front of the newer ones. |

It links the engine units from `../Server` (search path) and the vendored MCP
plumbing from `../../vendor`. It does **not** ship. It runs in every regression:
`tests/test_engine_dunitx.py` executes it through `delphi_test run` with the
whole repo as jail, so the tool that runs tests is measured on a real suite each
release. By hand: `delphi_test command=run project=<this .dproj>` (needs
`AllowTests=1` in the workspace), or the IDE.

Adding a fixture: `delphi_create kind=unit` with a `[TestFixture]` class and
`TDUnitX.RegisterTestFixture` in its `initialization`; the battery's minimum
test count only grows.
