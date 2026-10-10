"""从 X 推文页面的 MHTML 快照中提取推文与回复。

背景：X 的回复/会话没有可用的公开接口（详见 references/source-playbook.md），
但让人在浏览器里「另存为 MHTML」后本地解析是可行的。本脚本处理 Chrome/Blink
存下来的 mhtml。

用法:
    python parse_x_mhtml.py <mhtml路径> <输出目录>

输出:
    x_snapshot.html  解码后的页面 HTML（便于人工核查）
    x_tweets.json    结构化结果
    x_tweets.md      可读汇总（每条：作者 / 时间 / status / 正文）

实现要点（换平台或换站点时需要重新确认）:
    1. MHTML 的 HTML 部分是 quoted-printable，用 email 模块 get_payload(decode=True) 解码。
    2. 推文节点是 article[data-testid="tweet"]，正文是 div[data-testid="tweetText"]。
    3. 作者 handle 在 div[data-testid="User-Name"] 内 a 的 href，是**完整 URL**
       （https://x.com/<handle>），不是 /<handle>——按相对路径匹配会全部取空。
    4. 浏览器装了沉浸式翻译等扩展时，页面会带译文节点，先删掉 class 含
       immersive-translate 的元素，避免原文与译文混在一起。
    5. 快照只包含保存时已渲染到 DOM 的推文，且会掺入推广/广告条目；不是完整会话，
       统计与结论都要标注覆盖范围。

已知限制：X 的 DOM 不保留「回复给谁」的标示，因此无法自动还原回复关系；
需要判断某条是否在回应谁时，只能按内容与顺序人工推断，并在结论里标明是推断。
"""
import json
import re
import sys
from email import policy
from email.parser import BytesParser
from pathlib import Path

import lxml.html

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HANDLE_RE = re.compile(r"^https?://(?:x|twitter)\.com/([^/]+)$")
STATUS_RE = re.compile(r"/status/(\d+)")


def extract_html_part(path: Path) -> str:
    """取出 MHTML 中的 text/html 部分并解码为文本。"""
    with path.open("rb") as fh:
        msg = BytesParser(policy=policy.default).parse(fh)
    for part in msg.walk():
        if part.get_content_type() == "text/html":
            payload = part.get_payload(decode=True)
            if payload:
                charset = part.get_content_charset() or "utf-8"
                return payload.decode(charset, errors="replace")
    raise SystemExit("未找到 text/html 部分")


def strip_translation(tree) -> int:
    """移除翻译扩展注入的节点，只保留原文。返回移除数量。"""
    removed = 0
    for el in tree.xpath('//*[contains(@class,"immersive-translate")]'):
        parent = el.getparent()
        if parent is not None:
            parent.remove(el)
            removed += 1
    return removed


def text_of(node) -> str:
    """节点可见文本，压缩空白。"""
    return re.sub(r"\s+", " ", "".join(node.itertext())).strip()


def parse_articles(tree):
    """按 DOM 顺序提取每条推文的作者、状态号、时间与正文。"""
    rows = []
    for idx, art in enumerate(tree.xpath('//article[@data-testid="tweet"]'), 1):
        handle = ""
        for href in art.xpath('.//div[@data-testid="User-Name"]//a/@href'):
            m = HANDLE_RE.match(href.strip())
            if m:
                handle = m.group(1)
                break

        status = ""
        for href in art.xpath(".//a/@href"):
            m = STATUS_RE.search(href)
            if m:
                status = m.group(1)
                break

        body = " | ".join(text_of(n) for n in art.xpath('.//div[@data-testid="tweetText"]'))
        times = art.xpath(".//time/@datetime")

        rows.append(
            {
                "idx": idx,
                "handle": handle,
                "status": status,
                "time": times[0] if times else "",
                "text": body,
            }
        )
    return rows


def main() -> None:
    src = Path(sys.argv[1])
    outdir = Path(sys.argv[2])
    outdir.mkdir(parents=True, exist_ok=True)

    doc = extract_html_part(src)
    (outdir / "x_snapshot.html").write_text(doc, encoding="utf-8")

    tree = lxml.html.fromstring(doc)
    removed = strip_translation(tree)
    rows = parse_articles(tree)

    (outdir / "x_tweets.json").write_text(
        json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    lines = [
        "# X 推文快照提取结果",
        "",
        f"- 来源: {src.name}",
        f"- 移除翻译节点: {removed}",
        f"- 推文条数: {len(rows)}（仅含保存时已渲染到 DOM 的部分，可能掺入推广条目）",
        "",
    ]
    for r in rows:
        lines += [
            f"## [{r['idx']}] @{r['handle'] or '未知'}",
            "",
            f"- 时间: {r['time']}",
            f"- status: {r['status']}",
            "",
            r["text"] or "（无正文）",
            "",
        ]
    (outdir / "x_tweets.md").write_text("\n".join(lines), encoding="utf-8")

    print(f"推文条数: {len(rows)}")
    print(f"输出: {outdir / 'x_tweets.md'}")


if __name__ == "__main__":
    main()
