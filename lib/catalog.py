#!/usr/bin/env python3
"""
AI CLI Helper - Per-Alias Codex Model Catalog Manager
Generates and manages model catalogs for Codex CLI based on active provider/alias endpoints.
"""

import sys
import os
import json
import argparse
import subprocess
import urllib.request
import urllib.error
from typing import List, Dict, Any, Optional

DEFAULT_USER_AGENT = "curl/8.5.0"

# Fallback template if `codex debug models` is unavailable
FALLBACK_TERRA_TEMPLATE = {
    "slug": "gpt-5.6-terra",
    "display_name": "GPT-5.6-Terra",
    "description": "Standard high-performance model for general tasks.",
    "default_reasoning_level": "medium",
    "supported_reasoning_levels": [
        {"effort": "low", "description": "Lower reasoning effort"},
        {"effort": "medium", "description": "Balanced reasoning effort"},
        {"effort": "high", "description": "Higher reasoning effort"}
    ],
    "shell_type": "shell_command",
    "visibility": "list",
    "supported_in_api": True,
    "priority": 1,
    "additional_speed_tiers": [],
    "service_tiers": [],
    "availability_nux": None,
    "upgrade": None,
    "include_skills_usage_instructions": False,
    "include_plugin_usage_instructions": True,
    "include_apps_usage_instructions": True,
    "default_reasoning_summary": "none",
    "support_verbosity": True,
    "default_verbosity": "low",
    "apply_patch_tool_type": "freeform",
    "web_search_tool_type": "text_and_image",
    "supports_parallel_tool_calls": True,
    "supports_image_detail_original": True,
    "context_window": 272000,
    "max_context_window": 272000,
    "comp_hash": "3000",
    "effective_context_window_percent": 95,
    "experimental_supported_tools": [],
    "input_modalities": ["text", "image"],
    "supports_search_tool": True,
    "use_responses_lite": True,
    "tool_mode": "code_mode_only",
    "multi_agent_version": "v2"
}

def get_base_catalog() -> Dict[str, Dict[str, Any]]:
    """Fetch base models catalog from codex binary or return fallback."""
    try:
        res = subprocess.run(
            ["codex", "debug", "models"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if res.returncode == 0 and res.stdout.strip():
            data = json.loads(res.stdout)
            return {m["slug"]: m for m in data.get("models", []) if "slug" in m}
    except Exception:
        pass
    return {"gpt-5.6-terra": FALLBACK_TERRA_TEMPLATE}

def fetch_upstream_models(base_url: str, api_key: Optional[str] = None, timeout: int = 4) -> List[str]:
    """Fetch list of available model IDs from upstream /models endpoint."""
    urls_to_try = []
    clean_url = base_url.rstrip("/")
    if clean_url.endswith("/v1"):
        urls_to_try.append(f"{clean_url}/models")
        urls_to_try.append(f"{clean_url[:-3]}/models")
    else:
        urls_to_try.append(f"{clean_url}/v1/models")
        urls_to_try.append(f"{clean_url}/models")

    headers = {"User-Agent": DEFAULT_USER_AGENT}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    last_error = None
    for endpoint in urls_to_try:
        try:
            req = urllib.request.Request(endpoint, headers=headers)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                if resp.status == 200:
                    data = json.loads(resp.read().decode("utf-8"))
                    models_list = data.get("data", [])
                    ids = [m["id"] for m in models_list if isinstance(m, dict) and "id" in m]
                    if ids:
                        return ids
        except Exception as e:
            last_error = e

    if last_error:
        raise last_error
    return []

def filter_and_sort_models(raw_ids: List[str], default_model: Optional[str] = None) -> List[str]:
    """Filter out non-chat / embedding models and sort sensibly."""
    ignored_keywords = [
        "embedding", "text-embedding", "whisper", "tts-", "dall-e",
        "moderation", "text-search", "bge-", "rerank"
    ]
    chat_models = []
    for mid in raw_ids:
        low = mid.lower()
        if any(ign in low for ign in ignored_keywords):
            continue
        chat_models.append(mid)

    def sort_key(m: str):
        is_default = (m == default_model)
        is_gpt6 = ("gpt-6" in m)
        is_gpt5 = ("gpt-5" in m)
        is_grok = ("grok" in m)
        # Priority rank: default (0), gpt-6 (1), gpt-5 (2), grok (3), others (4)
        rank = 4
        if is_default:
            rank = 0
        elif is_gpt6:
            rank = 1
        elif is_gpt5:
            rank = 2
        elif is_grok:
            rank = 3
        return (rank, m)

    chat_models.sort(key=sort_key)
    return chat_models

def generate_catalog(
    base_url: Optional[str],
    api_key: Optional[str],
    output_path: str,
    default_model: Optional[str] = None,
    explicit_models: Optional[List[str]] = None,
    alias: Optional[str] = None,
    timeout: int = 4
) -> bool:
    """Generate model catalog JSON and save to output_path."""
    if explicit_models:
        model_ids = explicit_models
    else:
        if not base_url:
            print("[ERROR] Base URL is required to fetch models.", file=sys.stderr)
            return False
        try:
            raw_ids = fetch_upstream_models(base_url, api_key, timeout=timeout)
            model_ids = filter_and_sort_models(raw_ids, default_model)
        except Exception as e:
            print(f"[WARN] Failed to fetch upstream models for alias '{alias or 'default'}': {e}", file=sys.stderr)
            return False

    if not model_ids:
        print("[WARN] No compatible chat models discovered.", file=sys.stderr)
        return False

    base_map = get_base_catalog()
    astra_proto = base_map.get("gpt-6-astra") or next(iter(base_map.values()))
    terra_proto = base_map.get("gpt-5.6-terra") or next(iter(base_map.values()))

    catalog_models = []
    for idx, mid in enumerate(model_ids):
        if mid in base_map:
            entry = dict(base_map[mid])
            entry["visibility"] = "hide" if mid.endswith("-review") else "list"
            entry["priority"] = idx + 1
        else:
            is_six = ("6" in mid or "astra" in mid)
            proto = astra_proto if is_six else terra_proto
            entry = dict(proto)
            entry["slug"] = mid
            entry["display_name"] = mid
            entry["description"] = f"{mid} model via AI CLI Helper."
            entry["visibility"] = "hide" if mid.endswith("-review") else "list"
            entry["priority"] = idx + 1
        catalog_models.append(entry)

    # Ensure output directory exists
    out_dir = os.path.dirname(os.path.abspath(output_path))
    os.makedirs(out_dir, exist_ok=True)

    # Atomic write via temporary file
    tmp_path = f"{output_path}.tmp.{os.getpid()}"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump({"models": catalog_models}, f, indent=2, ensure_ascii=False)
    os.replace(tmp_path, output_path)

    visible_count = sum(1 for m in catalog_models if m.get("visibility") == "list")
    print(f"[SUCCESS] Updated model catalog for '{alias or 'default'}': {visible_count} models saved to {output_path}")
    return True

def list_catalog(catalog_path: str):
    """Print readable table of models from catalog file."""
    if not os.path.exists(catalog_path):
        print(f"[ERROR] Catalog file not found: {catalog_path}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(catalog_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        models = data.get("models", [])
        print(f"\n{'PRIORITY':<10} {'SLUG':<26} {'DISPLAY NAME':<24} {'VISIBILITY':<10}")
        print("-" * 72)
        for m in models:
            prio = str(m.get("priority", "-"))
            slug = m.get("slug", "")
            name = m.get("display_name", slug)
            vis = m.get("visibility", "list")
            print(f"{prio:<10} {slug:<26} {name:<24} {vis:<10}")
        print(f"\nTotal: {len(models)} models ({sum(1 for m in models if m.get('visibility') == 'list')} visible)\n")
    except Exception as e:
        print(f"[ERROR] Failed to read catalog file: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Codex Model Catalog Manager")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Generate command
    gen_parser = subparsers.add_parser("generate", help="Generate or refresh catalog JSON")
    gen_parser.add_argument("--base-url", help="Upstream API base URL")
    gen_parser.add_argument("--api-key", help="Upstream API key")
    gen_parser.add_argument("--output", required=True, help="Destination catalog JSON file path")
    gen_parser.add_argument("--default-model", help="Default active model name")
    gen_parser.add_argument("--alias", help="Alias identifier (e.g. codexa)")
    gen_parser.add_argument("--models", help="Comma-separated manual list of models")
    gen_parser.add_argument("--timeout", type=int, default=4, help="Fetch timeout in seconds")

    # List command
    list_parser = subparsers.add_parser("list", help="List models in a catalog JSON file")
    list_parser.add_argument("--catalog", required=True, help="Path to catalog JSON file")

    args = parser.parse_args()

    if args.command == "generate":
        explicit = [m.strip() for m in args.models.split(",") if m.strip()] if args.models else None
        ok = generate_catalog(
            base_url=args.base_url,
            api_key=args.api_key,
            output_path=args.output,
            default_model=args.default_model,
            explicit_models=explicit,
            alias=args.alias,
            timeout=args.timeout
        )
        sys.exit(0 if ok else 1)
    elif args.command == "list":
        list_catalog(args.catalog)

if __name__ == "__main__":
    main()
