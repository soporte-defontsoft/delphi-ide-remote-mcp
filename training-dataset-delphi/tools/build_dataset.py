"""Compose the dataset (data/delphi-fine-tuning.jsonl) from examples/<language>/<id>/example.md.

This script is the ONE writer of the dataset format; any chat-format loader is its reader.

    python -I tools/build_dataset.py           compose the JSONL (and check every example)
    python -I tools/build_dataset.py --python  also run the check.py of every Python example

example.md = a front matter (id, family, language, framework, teaches, judge, and optionally
must_contain / once) and the sections "## system" (optional), "## user", "## assistant".
In a section, {{code:<file>}} inserts that file as a fenced block (delphi or python by its
extension) and {{text:<file>}} as a plain fenced block - the code in the dataset is ALWAYS the
file that the judges compiled and ran, never a copy pasted by hand.

The Delphi judges are the projects in verify/ (they need RAD Studio, so they are not run here):
DatasetSpecTest (compiles every RTL answer unit and runs its checks), DatasetFmxSpecTest (the same for
the FireMonkey answers; hit-testing is asked of FireMonkey itself), DatasetPinTest (DUnitX, for the
examples written with DUnitX) and DatasetBrokenProbe (gives the compiler messages of the repair examples).
"""
import json
import os
import re
import subprocess
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
EXAMPLES = os.path.join(ROOT, "examples")
OUT = os.path.join(ROOT, "data", "delphi-fine-tuning.jsonl")

FENCE = {".pas": "delphi", ".dpr": "delphi", ".inc": "delphi", ".py": "python"}
FAMILIES = {"task", "repair", "landscape", "every-place"}
LANGUAGES = {"delphi", "python"}
FRAMEWORKS = {"delphi": {"rtl", "vcl", "fmx"}, "python": {"none"}}
REQUIRED = ("id", "family", "language", "framework", "teaches", "judge")
PLACEHOLDER = re.compile(r"\{\{(code|text):([^}]+)\}\}")
SECTION = re.compile(r"^## (system|user|assistant)\s*$")


def fail(where, why):
    raise SystemExit(f"{where}: {why}")


def read_text(path):
    with open(path, encoding="utf-8-sig") as f:
        return f.read().replace("\r\n", "\n")


def parse(path):
    text = read_text(path)
    m = re.match(r"---\n(.*?)\n---\n(.*)", text, re.S)
    if not m:
        fail(path, "no front matter")
    meta = {}
    for line in m.group(1).split("\n"):
        if line.strip():
            key, sep, value = line.partition(":")
            if not sep:
                fail(path, f"front matter line without ':': {line!r}")
            meta[key.strip()] = value.strip()
    sections, current = {}, None
    for line in m.group(2).split("\n"):
        h = SECTION.match(line)
        if h:
            current = h.group(1)
            if current in sections:
                fail(path, f"section {current} twice")
            sections[current] = []
        elif current:
            sections[current].append(line)
        elif line.strip():
            fail(path, f"text before the first section: {line!r}")
    return meta, {k: "\n".join(v).strip() for k, v in sections.items()}


def expand(text, folder, where):
    def repl(m):
        kind, rel = m.group(1), m.group(2).strip()
        path = os.path.join(folder, rel)
        if not os.path.isfile(path):
            fail(where, f"{{{{{kind}:{rel}}}}} - no such file")
        body = read_text(path).rstrip("\n")
        lang = FENCE.get(os.path.splitext(rel)[1].lower(), "") if kind == "code" else ""
        return f"```{lang}\n{body}\n```"
    return PLACEHOLDER.sub(repl, text)


def example_dirs():
    for language in sorted(os.listdir(EXAMPLES)):
        base = os.path.join(EXAMPLES, language)
        if os.path.isdir(base):
            for name in sorted(os.listdir(base)):
                folder = os.path.join(base, name)
                if os.path.isfile(os.path.join(folder, "example.md")):
                    yield language, name, folder


def build(run_python):
    lines, seen, counts = [], set(), {}
    for language, name, folder in example_dirs():
        where = os.path.relpath(os.path.join(folder, "example.md"), ROOT)
        meta, sections = parse(os.path.join(folder, "example.md"))
        for key in REQUIRED:
            if not meta.get(key):
                fail(where, f"front matter needs {key}")
        if meta["id"] != name:
            fail(where, f"id {meta['id']!r} is not the folder name {name!r}")
        if meta["id"] in seen:
            fail(where, "id used twice")
        seen.add(meta["id"])
        if meta["language"] != language:
            fail(where, f"language {meta['language']!r} but the example lives under {language}/")
        if meta["family"] not in FAMILIES:
            fail(where, f"family must be one of {sorted(FAMILIES)}")
        if meta["framework"] not in FRAMEWORKS.get(language, set()):
            fail(where, f"framework must be one of {sorted(FRAMEWORKS[language])}")
        if "user" not in sections or "assistant" not in sections:
            fail(where, "needs a ## user and a ## assistant section")

        messages = []
        for role in ("system", "user", "assistant"):
            if role in sections:
                messages.append({"role": role, "content": expand(sections[role], folder, where)})
        answer = messages[-1]["content"]

        # the two declared checks of the "programming well" families (no judge measures them yet)
        if meta.get("must_contain") and meta["must_contain"] not in answer:
            fail(where, f"the answer does not contain {meta['must_contain']!r}")
        if meta.get("once") and answer.count(meta["once"]) != 1:
            fail(where, f"{meta['once']!r} appears {answer.count(meta['once'])} times in the answer, not once")
        # VCL and FireMonkey are never mixed in one example
        if meta["framework"] == "fmx" and re.search(r"\bVcl\.|\bVCL\b", answer):
            fail(where, "a FireMonkey example names the VCL")
        if meta["framework"] == "vcl" and re.search(r"\bFMX\.|\bFireMonkey\b", answer):
            fail(where, "a VCL example names FireMonkey")

        if run_python and language == "python":
            check = os.path.join(folder, "check.py")
            if not os.path.isfile(check):
                fail(where, "a Python example needs its check.py")
            r = subprocess.run([sys.executable, "-I", check], cwd=folder, capture_output=True, text=True)
            if r.returncode != 0:
                fail(where, f"check.py failed:\n{r.stdout}{r.stderr}")

        lines.append(json.dumps({
            "messages": messages,
            "meta": {k: meta[k] for k in REQUIRED},
        }, ensure_ascii=False))
        key = (language, meta["family"])
        counts[key] = counts.get(key, 0) + 1

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    total = len(lines)
    print(f"{total} examples -> {os.path.relpath(OUT, ROOT)}")
    for (language, family), n in sorted(counts.items()):
        print(f"  {language:7} {family:12} {n}")
    other = sum(n for (language, _), n in counts.items() if language != "delphi")
    print(f"  not Delphi: {other} of {total} ({100 * other // max(total, 1)} %)")


if __name__ == "__main__":
    build(run_python="--python" in sys.argv[1:])
