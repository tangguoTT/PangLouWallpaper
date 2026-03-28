#!/usr/bin/env python3
"""
migrate_to_meilisearch.py
把现有 wallpapers.json 迁移到 Meilisearch Cloud

使用方式：
  pip install requests
  python3 migrate_to_meilisearch.py \
      --host  https://your-project.meilisearch.io \
      --key   YOUR_MASTER_KEY \
      --json  https://wallpapers-pl.oss-cn-beijing.aliyuncs.com/wallpapers/wallpapers.json
"""

import argparse
import json
import re
import sys
import time
import urllib.request

import requests   # pip install requests


# ─── 解析旧格式 title ────────────────────────────────────────────

TAG_RE = re.compile(r"\[([^\]]+)\]")

CATEGORY_MAP = {
    "魅力": "魅力", "迷人": "魅力",
    "自制": "自制", "艺术": "自制",
    "安逸": "安逸", "自由": "安逸",
    "科幻": "科幻", "星云": "科幻",
    "动漫": "动漫", "二次元": "动漫",
    "自然": "自然", "风景": "自然",
    "游戏": "游戏", "玩具": "游戏",
}

RESOLUTION_SET = {"1 K", "2 K", "3 K", "4 K", "5 K", "6 K", "7 K",
                  "1K", "2K", "3K", "4K", "5K", "6K", "7K"}

COLOR_SET = {"偏蓝", "偏绿", "偏红", "灰/白", "紫/粉", "暗色", "偏黄", "其他颜色"}


def parse_old_title(raw_title: str) -> dict:
    """从旧格式标题提取结构化字段，返回 dict"""
    tags_found = TAG_RE.findall(raw_title)
    base_name = TAG_RE.sub("", raw_title).strip()
    # 去掉文件扩展名
    base_name = re.sub(r"\.\w{2,4}$", "", base_name).strip()
    # 去掉 【...】 前缀（如 【哲风壁纸】）
    base_name = re.sub(r"^【[^】]*】\s*", "", base_name).strip()

    category = ""
    resolution = ""
    color = ""
    extra_tags = []

    for tag in tags_found:
        tag = tag.strip()
        # 尝试匹配分类
        if not category:
            for k, v in CATEGORY_MAP.items():
                if k in tag:
                    category = v
                    break
        # 分辨率
        if not resolution and tag in RESOLUTION_SET:
            resolution = tag
        # 色系
        if not color and tag in COLOR_SET:
            color = tag
        # 其余标签归入 tags
        if tag not in RESOLUTION_SET and tag not in COLOR_SET and tag not in CATEGORY_MAP:
            extra_tags.append(tag)

    # 从文件名中提取关键词作为额外标签
    name_keywords = re.findall(r"[\u4e00-\u9fff]+", base_name)
    all_tags = list(dict.fromkeys(extra_tags + name_keywords))  # 去重保序

    return {
        "title": base_name if base_name else raw_title,
        "description": "",
        "tags": all_tags[:8],   # 最多 8 个
        "category": category,
        "resolution": resolution,
        "color": color,
    }


# ─── Meilisearch 操作 ────────────────────────────────────────────

def configure_index(host: str, key: str, index: str):
    settings = {
        "searchableAttributes": ["title", "description", "tags"],
        "filterableAttributes": ["category", "resolution", "color", "isVideo"],
        "sortableAttributes": ["uploadedAt"],
        "displayedAttributes": [
            "id", "title", "description", "tags",
            "category", "resolution", "color",
            "isVideo", "fullURL", "uploadedAt"
        ]
    }
    r = requests.patch(
        f"{host}/indexes/{index}/settings",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        json=settings,
        timeout=30
    )
    r.raise_for_status()
    task_uid = r.json().get("taskUid")
    print(f"  ✅ 索引设置已提交 (taskUid={task_uid})")
    wait_for_task(host, key, task_uid)


def add_documents(host: str, key: str, index: str, docs: list):
    r = requests.post(
        f"{host}/indexes/{index}/documents",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        json=docs,
        timeout=60
    )
    r.raise_for_status()
    task_uid = r.json().get("taskUid")
    print(f"  ✅ 文档导入已提交 (taskUid={task_uid}, 共 {len(docs)} 条)")
    wait_for_task(host, key, task_uid)


def wait_for_task(host: str, key: str, task_uid: int, timeout: int = 60):
    headers = {"Authorization": f"Bearer {key}"}
    deadline = time.time() + timeout
    while time.time() < deadline:
        r = requests.get(f"{host}/tasks/{task_uid}", headers=headers, timeout=10)
        status = r.json().get("status", "")
        if status == "succeeded":
            print(f"  ✓ Task {task_uid} 完成")
            return
        if status == "failed":
            print(f"  ✗ Task {task_uid} 失败: {r.json()}")
            sys.exit(1)
        time.sleep(1)
    print(f"  ⚠️ Task {task_uid} 超时，继续...")


# ─── 主流程 ─────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="迁移壁纸数据到 Meilisearch")
    parser.add_argument("--host", required=True, help="Meilisearch 地址，如 https://xxx.meilisearch.io")
    parser.add_argument("--key",  required=True, help="Master Key 或有写权限的 API Key")
    parser.add_argument("--json", required=True, help="wallpapers.json 的 URL 或本地路径")
    parser.add_argument("--index", default="wallpapers", help="索引名（默认 wallpapers）")
    args = parser.parse_args()

    host = args.host.rstrip("/")

    # 1. 读取旧 JSON
    print(f"\n📥 读取数据源: {args.json}")
    if args.json.startswith("http"):
        with urllib.request.urlopen(args.json) as resp:
            raw_items = json.loads(resp.read().decode())
    else:
        with open(args.json, encoding="utf-8") as f:
            raw_items = json.load(f)
    print(f"  共 {len(raw_items)} 条记录")

    # 2. 转换为新格式
    print("\n🔄 转换数据格式...")
    new_docs = []
    for item in raw_items:
        parsed = parse_old_title(item.get("title", ""))
        doc = {
            "id": item["id"],
            "title": parsed["title"],
            "description": parsed["description"],
            "tags": parsed["tags"],
            "category": parsed["category"],
            "resolution": parsed["resolution"],
            "color": parsed["color"],
            "isVideo": item.get("isVideo", False),
            "fullURL": item["fullURL"],
            "uploadedAt": 0,
        }
        new_docs.append(doc)
        print(f"  [{doc['category'] or '—':4}][{doc['resolution'] or '—':3}][{doc['color'] or '—':4}]  {doc['title'][:40]}")

    # 3. 配置索引
    print(f"\n⚙️  配置 Meilisearch 索引 [{args.index}]...")
    configure_index(host, args.key, args.index)

    # 4. 导入文档
    print(f"\n📤 导入文档到 Meilisearch...")
    add_documents(host, args.key, args.index, new_docs)

    print(f"\n🎉 迁移完成！共导入 {len(new_docs)} 条壁纸记录。")
    print("   接下来：")
    print("   1. 在 Secrets.plist 中填写 MeilisearchHost 和 MeilisearchApiKey")
    print("   2. 在 Xcode 中重新编译并运行 App")


if __name__ == "__main__":
    main()
