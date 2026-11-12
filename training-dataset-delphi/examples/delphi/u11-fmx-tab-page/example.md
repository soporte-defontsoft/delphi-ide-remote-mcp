---
id: u11-fmx-tab-page
family: task
language: delphi
framework: fmx
teaches: TTabControl and TTabItem live in FMX.TabControl; TTabControl.Add creates the page, owned by the tab control
judge: dcc64 37.0 Win64 + run (verify/DatasetFmxSpecTest: u11 - the page, its title, its owner and its parent; the units read from the class)
---

## user
In a Delphi FireMonkey app, write `AddPage(const ATabs: TTabControl; const ATitle: string): TTabItem`: it adds a page with that title to a tab control and returns it.

## assistant
`TTabControl` and `TTabItem` both live in `FMX.TabControl`. The tab control creates its own pages: `ATabs.Add` returns a new `TTabItem`, owned by the tab control (it is freed with it) and placed in the control's content. The title goes in `Text`.

{{code:TabPages.pas}}
