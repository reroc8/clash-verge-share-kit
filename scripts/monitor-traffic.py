"""Connection-ID accounting for clash-monitor.sh; never accesses the network."""

import argparse
import csv
import json
import os


MB = 1048576
CSV_FIELDS = ["timestamp", "process", "upload_delta_mb", "download_delta_mb", "connections", "route"]
ROUTE_LABELS = {"proxy": "代理", "direct": "直连", "unknown": "未知"}
PROXY_TYPES = {
    "shadowsocks", "shadowsocksr", "snell", "socks5", "http", "vmess", "vless",
    "trojan", "hysteria", "hysteria2", "wireguard", "tuic", "ssh", "mieru",
    "anytls", "sudoku", "masque", "trusttunnel", "shadowquic", "openvpn",
    "tailscale", "gostrelay",
}


def load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def save_json(path, value):
    temporary = str(path) + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(value, handle)
    os.replace(temporary, path)


def optional_mapping(path, key):
    try:
        data = load_json(path)
        value = data.get(key) if isinstance(data, dict) else None
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def classify_route(conn, proxies, providers):
    # Mihomo chains[0] is the actual outbound, not the selected group at the end.
    chains = conn.get("chains")
    if not isinstance(chains, list) or not chains or not isinstance(chains[0], str):
        return "unknown"
    name = chains[0]
    provider_chain = conn.get("providerChains") or []
    provider = provider_chain[0] if isinstance(provider_chain, list) and provider_chain else ""
    if provider:
        info = providers.get((provider, name), {})
    else:
        info = proxies.get(name, {})
        if not info and name in ("DIRECT", "COMPATIBLE"):
            return "direct"
    if not isinstance(info, dict):
        return "unknown"
    kind = str(info.get("type", "")).lower()
    if kind in ("direct", "compatible"):
        # A direct adapter with a custom dialer is not proof of a direct path.
        return "unknown" if info.get("dialer-proxy") else "direct"
    return "proxy" if kind in PROXY_TYPES else "unknown"


def sample(snapshot_path, state_path, total_path, log_path, timestamp, proxies_path, providers_path):
    data = load_json(snapshot_path)
    if not isinstance(data, dict) or "connections" not in data:
        raise ValueError("missing connections snapshot")
    connections = data["connections"]
    if connections is None:
        connections = []
    if not isinstance(connections, list):
        raise ValueError("connections must be an array")

    proxies = optional_mapping(proxies_path, "proxies")
    providers = {}
    for provider, value in optional_mapping(providers_path, "providers").items():
        if isinstance(value, dict) and isinstance(value.get("proxies"), list):
            for item in value["proxies"]:
                if isinstance(item, dict) and isinstance(item.get("name"), str):
                    providers[(provider, item["name"])] = item

    first_sample = not os.path.exists(state_path)
    before = {} if first_sample else load_json(state_path)
    current = {}
    aggregated = {}
    for conn in connections:
        if not isinstance(conn, dict) or not isinstance(conn.get("id"), str) or not conn["id"]:
            raise ValueError("connection has no usable id")
        ident = conn["id"]
        if ident in current:
            raise ValueError("duplicate connection id")
        up, down = conn.get("upload"), conn.get("download")
        if any(type(value) is not int or value < 0 for value in (up, down)):
            raise ValueError("invalid connection counters")
        current[ident] = [up, down]
        meta = conn.get("metadata") or {}
        process = (meta.get("processPath") or meta.get("process") or "unknown").replace("\\", "/").split("/")[-1]
        route = classify_route(conn, proxies, providers)
        item = aggregated.setdefault((process, route), [0, 0, 0])
        if first_sample:
            delta_up, delta_down = up, down
        else:
            # New IDs appeared after the baseline; old IDs are diffed individually.
            # A closed connection cannot cancel another connection's increment.
            base_up, base_down = before.get(ident, [0, 0])
            delta_up, delta_down = max(0, up - base_up), max(0, down - base_down)
        item[0] += delta_up
        item[1] += delta_down
        item[2] += 1

    if first_sample:
        save_json(state_path, current)
        print(f"── {timestamp} 基线（历史连接累计，不计入本次） ──")
        rows = sorted(aggregated.items(), key=lambda item: -sum(item[1][:2]))[:8]
        for (name, route), (up, down, count) in rows:
            print(f"  [{ROUTE_LABELS[route]}] {name:<28} ↑{up/MB:9.3f}MB ↓{down/MB:9.3f}MB ({count}连接)")
        return

    totals = load_json(total_path) if os.path.exists(total_path) else {}
    rows = []
    with open(log_path, "a", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        for (name, route), (up, down, count) in aggregated.items():
            if up == 0 and down == 0:
                continue
            writer.writerow([timestamp, name, f"{up/MB:.6f}", f"{down/MB:.6f}", count, route])
            acc = totals.setdefault(route, {}).setdefault(name, [0, 0])
            acc[0] += up
            acc[1] += down
            rows.append((name, route, up, down, count))
    save_json(total_path, totals)
    save_json(state_path, current)

    rows.sort(key=lambda row: -(row[2] + row[3]))
    if rows:
        print(f"── {timestamp} ──")
        for name, route, up, down, count in rows[:8]:
            print(f"  [{ROUTE_LABELS[route]}] {name:<28} ↑{up/MB:+9.3f}MB ↓{down/MB:+9.3f}MB ({count}连接)")


def report(total_path):
    if not os.path.exists(total_path):
        return
    rows = [(name, route, up, down) for route, processes in load_json(total_path).items()
            for name, (up, down) in processes.items()]
    if rows:
        print("════ 本次观测累计 Top10（不含首轮历史量，非机场账单） ════")
    for name, route, up, down in sorted(rows, key=lambda row: -(row[2] + row[3]))[:10]:
        print(f"  [{ROUTE_LABELS[route]}] {name:<28} ↑{up/MB:9.3f}MB ↓{down/MB:9.3f}MB")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    sampler = commands.add_parser("sample")
    for argument in ("snapshot_path", "state_path", "total_path", "log_path", "timestamp", "proxies_path", "providers_path"):
        sampler.add_argument(argument)
    commands.add_parser("report").add_argument("total_path")
    arguments = vars(parser.parse_args())
    command = arguments.pop("command")
    (sample if command == "sample" else report)(**arguments)


if __name__ == "__main__":
    main()
