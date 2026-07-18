# Word handoff mechanics

Loaded by `../SKILL.md` when a settled `.md` draft converts to `.docx`.
The operating rules (markdown-first, one-directional handoff) live in
SKILL.md; this file is the conversion mechanics.

Convert with a reference doc when the venue dictates formatting. Grant
applications usually mandate margins and a minimum font size (ACCESS, for
example, requires 1-inch margins and 11pt or larger), and pandoc's
default docx honors neither reliably. Build a reference doc once and
reuse it:

```
pandoc --print-default-data-file reference.docx > reference.docx
# set 1-inch margins (w:pgMar 1440) and the body font in reference.docx, then:
pandoc -o paper.docx --reference-doc=reference.docx paper.md
```

Pandoc's md-to-docx conversion also leaves artifacts worth a cleanup
pass: thematic breaks (`---`) can render as a stray `/` line, and bullet
lists sometimes collapse to inline `- ` markers inside one paragraph.
Open the converted docx and fix these before handing it over.
