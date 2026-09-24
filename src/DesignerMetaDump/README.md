# `src/DesignerMetaDump/` — generators of the designer tables

Two console programs, `DumpMetaVcl.dproj` and `DumpMetaFmx.dproj`, sharing
`MetaDump.pas`. Each starts with its framework linked in (`{$STRONGLINKTYPES ON}`),
walks the classic RTTI of every component class it knows (classes, published
properties with their kind and type, enum and set members, and the class a
class-typed property really holds at runtime) and writes a Pascal unit with
those tables:

```
DumpMetaVcl.exe ..\Server\Lsp.DesignerMeta.Vcl.pas
DumpMetaFmx.exe ..\Server\Lsp.DesignerMeta.Fmx.pas
```

Those two generated units compile into the server and are what
`delphi_designer info`, `prop` and the lint answer from: the framework
describes itself, the server hardcodes no rules.

They do **not** ship and they run **by hand, once per RAD Studio version**:
when the framework changes (a new release of RAD Studio, or a component set
you want the lint to know), rebuild them, run both, and commit the regenerated
units. They are in the project group only so they keep compiling.
