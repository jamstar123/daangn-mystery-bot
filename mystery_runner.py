#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
mystery_runner.py
부산 괴담·미스터리 카페 전용 자동 발행 워커 (독립 봇)
- manuscripts/queue/ 폴더의 원고(.txt) 및 매칭된 실제 사진(.jpg/.png 또는 URL)을 순서대로 1건씩 발행합니다.
- 발행 완료된 원고와 로컬 이미지 파일은 manuscripts/published/ 폴더로 안전하게 이동합니다.
"""

import argparse
import shutil
import sys
from datetime import datetime
from pathlib import Path

from daangn_cafe import (
    DaangnCafeClient,
    DaangnCafeError,
    EXIT_SUCCESS,
    load_env,
    parse_manuscript_items,
)


def run_next_manuscript(slug: str, board: str, queue_dir: Path, pub_dir: Path, log_dir: Path, prefix: str = "") -> int:
    queue_dir.mkdir(parents=True, exist_ok=True)
    pub_dir.mkdir(parents=True, exist_ok=True)
    log_dir.mkdir(parents=True, exist_ok=True)

    pattern = f"{prefix}*.txt" if prefix else "*.txt"
    candidates = sorted(queue_dir.glob(pattern))
    if not candidates:
        print(f"[대기열 비어 있음] manuscripts/queue 폴더에 발행할 원고({pattern})가 없습니다.")
        return EXIT_SUCCESS

    target_txt = candidates[0]
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{now_str}] 원고 발행 시작: {target_txt.name}")

    client = DaangnCafeClient(slug=slug)
    title, body_items, board_override = parse_manuscript_items(target_txt)
    target_board = board_override or board

    post_url = client.create_post_from_items(
        board=target_board,
        title=title,
        body_items=body_items,
        base_dir=target_txt.parent,
    )

    print(f"[{now_str}] 발행 완료: {post_url}")
    with open(log_dir / "published_urls.log", "a", encoding="utf-8") as lf:
        lf.write(f"[{now_str}] {target_txt.name} -> {post_url}\n")

    # 발행 완료된 원고와 본문에서 참조된 로컬 이미지 파일들을 published 폴더로 이동
    shutil.move(str(target_txt), str(pub_dir / target_txt.name))
    for item_type, item_val in body_items:
        if item_type == "image" and not item_val.startswith(("http://", "https://")):
            img_candidate = (queue_dir / item_val).resolve()
            if img_candidate.exists() and img_candidate.parent == queue_dir.resolve():
                shutil.move(str(img_candidate), str(pub_dir / img_candidate.name))
    for ext in (".jpg", ".jpeg", ".png", ".webp"):
        img_file = target_txt.with_suffix(ext)
        if img_file.exists():
            shutil.move(str(img_file), str(pub_dir / img_file.name))

    return EXIT_SUCCESS


def main() -> int:
    base_dir = Path(__file__).resolve().parent
    load_env(base_dir / ".env")

    parser = argparse.ArgumentParser(description="부산 괴담·미스터리 카페 전용 자동 발행 봇")
    parser.add_argument("--slug", required=True, help="괴담 카페 slug")
    parser.add_argument("--board", default="free", help="기본 게시판 이름 또는 ID")
    parser.add_argument("--prefix", default="", help="원고 파일 접두사 필터 (예: photo_, real_, series_)")
    args = parser.parse_args()

    try:
        return run_next_manuscript(
            slug=args.slug,
            board=args.board,
            queue_dir=base_dir / "manuscripts" / "queue",
            pub_dir=base_dir / "manuscripts" / "published",
            log_dir=base_dir / "logs",
            prefix=args.prefix,
        )
    except DaangnCafeError as e:
        print(str(e), file=sys.stderr)
        return e.exit_code


if __name__ == "__main__":
    sys.exit(main())
