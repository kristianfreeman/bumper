#!/usr/bin/env python3
"""CHANGELOG.md → website/changelog/index.html (playbumper.com/changelog/).

The release notes testers see in TestFlight, as the site's "What's new".
Unreleased is left out. Run after editing CHANGELOG.md:

    scripts/site-changelog.py
"""
import html
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "CHANGELOG.md"
OUT = ROOT / "website" / "changelog" / "index.html"


def releases(text: str):
    """[(version, [lines])] for each "## x.y.z" section, newest first."""
    out, current = [], None
    for line in text.splitlines():
        m = re.match(r"^## (.+)$", line)
        if m:
            current = (m.group(1).strip(), [])
            out.append(current)
        elif current:
            current[1].append(line)
    return [(v, body) for v, body in out if v.lower() != "unreleased"]


def render(body):
    """Bullets ("- " and their wrapped lines), group labels and paragraphs."""
    parts, items, para = [], [], []

    def flush_items():
        if items:
            parts.append("<ul>\n" + "\n".join(f"<li>{inline(i)}</li>" for i in items) + "\n</ul>")
            items.clear()

    def flush_para():
        if para:
            text = " ".join(para)
            # A short line on its own (no full stop) heads a group: "Home", "The player".
            if len(para) == 1 and len(text) < 40 and not text.endswith("."):
                parts.append(f"<h3>{inline(text)}</h3>")
            else:
                parts.append(f"<p>{inline(text)}</p>")
            para.clear()

    for line in body:
        if line.startswith("- "):
            flush_para()
            items.append(line[2:].strip())
        elif line.startswith("  ") and items:
            items[-1] += " " + line.strip()
        elif line.strip():
            flush_items()
            para.append(line.strip())
        else:
            flush_items()
            flush_para()
    flush_items()
    flush_para()
    return "\n".join(parts)


def inline(text: str) -> str:
    text = html.escape(text, quote=False)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", text)


def main():
    sections = "\n".join(
        f'<section class="release" aria-labelledby="v{v.replace(".", "-")}">\n'
        f'<h2 id="v{v.replace(".", "-")}">{html.escape(v)}</h2>\n{render(body)}\n</section>'
        for v, body in releases(SOURCE.read_text())
    )
    page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>What's new — Bumper</title>
<meta name="description" content="What changed in each Bumper release.">
<link rel="canonical" href="https://playbumper.com/changelog/">
<meta name="theme-color" content="#0B0B0F">
<link rel="icon" type="image/png" sizes="32x32" href="/assets/favicon-32.png">
<link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
<link rel="stylesheet" href="/assets/site.css">
</head>
<body>
<a class="skip" href="#main">Skip to the content</a>
<header class="wrap bar">
<a class="brand" href="/" aria-label="Bumper, home"><img src="/assets/apple-touch-icon.png" alt="" width="34" height="34">Bumper</a>
<nav aria-label="Main"><ul><li><a href="/">Home</a></li><li><a href="/support/">Support</a></li><li><a class="pill" href="https://testflight.apple.com/join/QDpjTEQ2">Get the beta</a></li></ul></nav>
</header>
<main id="main" class="wrap doc">
<h1 class="display">What's new</h1>
<p class="updated">Every Bumper release, newest first. Made from the notes testers see in TestFlight.</p>
{sections}
</main>
<footer>
<div class="wrap">
<div class="fine" style="margin-top: 0">
<p><a href="/">Bumper</a> · <a href="/support/">Support</a> · <a href="/privacy/">Privacy</a> · <a href="https://github.com/kristianfreeman/bumper">Source code</a></p>
<p>Bumper isn't affiliated with or endorsed by the Jellyfin project. © 2026 Kristian Freeman.</p>
</div>
</div>
</footer>
</body>
</html>
"""
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(page)
    print(f"{OUT.relative_to(ROOT)}: {len(releases(SOURCE.read_text()))} releases")


if __name__ == "__main__":
    main()
