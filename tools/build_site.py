#!/usr/bin/env python3
"""GitHub Pages용 정적 사이트를 만든다. 외부 패키지 없이 동작한다.

개인정보 처리방침은 앱 번들과 같은 파일(TookTook/Resources/PrivacyPolicy.md)에서 만든다.
문의 이메일도 그 파일의 "- 이메일:" 줄 하나만 원본으로 쓴다.

사용법: python3 tools/build_site.py [출력 폴더, 기본 _site]
"""

import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POLICY = ROOT / "TookTook/Resources/PrivacyPolicy.md"
SITE = ROOT / "site"
ISSUES_URL = "https://github.com/Twentyonestar/tooktook/issues"
EMAIL_PLACEHOLDER = "[문의 이메일을 여기에 적어 주세요]"

PAGES = [
    # (원본, 출력 경로, 제목, 루트까지의 상대 경로)
    (SITE / "index.md", "index.html", "툭툭가계부", "./"),
    (SITE / "support.md", "support/index.html", "지원 · 툭툭가계부", "../"),
    (POLICY, "privacy/index.html", "개인정보 처리방침 · 툭툭가계부", "../"),
]


def contact_email(policy_text):
    match = re.search(r"^- 이메일:\s*(.+)$", policy_text, re.MULTILINE)
    value = match.group(1).strip() if match else ""
    return None if not value or value == EMAIL_PLACEHOLDER else value


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", lambda m: f'<a href="{html.escape(m.group(2))}">{m.group(1)}</a>', text)
    text = re.sub(r"(?<![\"'>=])(https?://[^\s<]+)", r'<a href="\1">\1</a>', text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    return text


def render(markdown):
    """처리방침·지원 문서에 쓰는 형식만 지원한다: #~###, 목록(-, 1.), 문단, **굵게**, [링크](주소)."""
    out, paragraph, list_tag = [], [], None

    def flush_paragraph():
        if paragraph:
            out.append(f"<p>{inline(' '.join(paragraph))}</p>")
            paragraph.clear()

    def close_list():
        nonlocal list_tag
        if list_tag:
            out.append(f"</{list_tag}>")
            list_tag = None

    for raw in markdown.splitlines():
        line = raw.strip()
        heading = re.match(r"^(#{1,3}) (.+)$", line)
        item = re.match(r"^(?:- |(\d+)\. )(.+)$", line)
        if not line:
            flush_paragraph()
            close_list()
        elif heading:
            flush_paragraph()
            close_list()
            level = len(heading.group(1))
            out.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
        elif item:
            flush_paragraph()
            tag = "ol" if item.group(1) else "ul"
            if list_tag != tag:
                close_list()
                out.append(f"<{tag}>")
                list_tag = tag
            out.append(f"<li>{inline(item.group(2))}</li>")
        else:
            close_list()
            paragraph.append(line)
    flush_paragraph()
    close_list()
    return "\n".join(out)


TEMPLATE = """<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
:root {{ --bg: #f5f6f8; --card: #ffffff; --text: #1c1c1e; --muted: #6b6b70; --accent: #0a7aff; --line: #e3e4e8; }}
@media (prefers-color-scheme: dark) {{
  :root {{ --bg: #000000; --card: #1c1c1e; --text: #f2f2f7; --muted: #a1a1a6; --accent: #409cff; --line: #2c2c2e; }}
}}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--bg); color: var(--text); font: 17px/1.65 -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Noto Sans KR", sans-serif; word-break: keep-all; overflow-wrap: anywhere; }}
header, main, footer {{ max-width: 720px; margin: 0 auto; padding: 0 16px; }}
header {{ display: flex; gap: 16px; flex-wrap: wrap; align-items: center; padding-top: 20px; padding-bottom: 8px; }}
header a {{ color: var(--muted); text-decoration: none; font-size: 15px; }}
header a.home {{ color: var(--text); font-weight: 700; margin-right: auto; }}
header a[aria-current] {{ color: var(--accent); }}
main {{ background: var(--card); border-radius: 18px; padding: 8px 24px 24px; margin-top: 8px; }}
h1 {{ font-size: 28px; line-height: 1.3; margin: 24px 0 12px; }}
h2 {{ font-size: 20px; margin: 32px 0 8px; padding-top: 16px; border-top: 1px solid var(--line); }}
h3 {{ font-size: 17px; margin: 24px 0 4px; }}
p, li {{ margin: 8px 0; }}
ul, ol {{ padding-left: 22px; }}
a {{ color: var(--accent); }}
footer {{ color: var(--muted); font-size: 13px; padding-top: 16px; padding-bottom: 40px; }}
@media (max-width: 480px) {{ main {{ padding: 4px 16px 16px; border-radius: 14px; }} h1 {{ font-size: 24px; }} }}
</style>
</head>
<body>
<header>
<a class="home" href="{root}">툭툭가계부</a>
<a href="{root}support/"{support_current}>지원</a>
<a href="{root}privacy/"{privacy_current}>개인정보 처리방침</a>
</header>
<main>
{body}
</main>
<footer>© 2026 툭툭가계부</footer>
</body>
</html>
"""


def build(output):
    policy_text = POLICY.read_text(encoding="utf-8")
    email = contact_email(policy_text)
    contact_lines = [f"- 이메일: [{email}](mailto:{email})" if email else "- 이메일: 준비 중이에요"]
    contact_lines.append(f"- GitHub: {ISSUES_URL}")

    for source, target, title, root in PAGES:
        text = source.read_text(encoding="utf-8")
        text = text.replace("{{CONTACT}}", "\n".join(contact_lines))
        text = text.replace(EMAIL_PLACEHOLDER, "준비 중이에요")
        page = TEMPLATE.format(
            title=html.escape(title),
            root=root,
            body=render(text),
            support_current=' aria-current="page"' if target.startswith("support/") else "",
            privacy_current=' aria-current="page"' if target.startswith("privacy/") else "",
        )
        path = output / target
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(page, encoding="utf-8")
    (output / ".nojekyll").write_text("", encoding="utf-8")

    if email is None:
        print(f"warning: 문의 이메일이 비어 있습니다. {POLICY.relative_to(ROOT)}의 '- 이메일:' 줄을 채워 주세요.")
    print(f"built {len(PAGES)} pages into {output}")


if __name__ == "__main__":
    build(Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "_site").resolve())
