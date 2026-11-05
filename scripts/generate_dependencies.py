#!/usr/bin/env python3
"""
generate_dependencies.py
Dynamically inspects Package.resolved and project.pbxproj at compile time
to generate static Swift structs for all package dependencies.
Contains NO hardcoded package catalogs or static metadata.
"""

import sys
import os
import json
import re
import subprocess

def clean_url(url_str):
    if not url_str:
        return None
    url_str = url_str.strip()
    if url_str.endswith(".git"):
        url_str = url_str[:-4]
    return url_str

def escape_swift_string(s):
    if s is None:
        return ""
    return str(s).replace('\\', '\\\\').replace('"', '\\"')

def parse_package_resolved(resolved_path):
    if not os.path.exists(resolved_path):
        return []
    try:
        with open(resolved_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return []

    pins = []
    # v2 / v3
    if "pins" in data and isinstance(data["pins"], list):
        for p in data["pins"]:
            identity = p.get("identity")
            location = p.get("location")
            state = p.get("state") or {}
            version = state.get("version") or state.get("branch")
            if identity:
                pins.append((identity, location, version))
    # v1
    elif "object" in data and isinstance(data["object"], dict):
        obj_pins = data["object"].get("pins") or []
        for p in obj_pins:
            identity = p.get("package")
            location = p.get("repositoryURL")
            state = p.get("state") or {}
            version = state.get("version") or state.get("branch")
            if identity:
                pins.append((identity, location, version))

    return pins

def parse_pbxproj(pbxproj_path, project_dir):
    if not os.path.exists(pbxproj_path):
        return {}, [], []

    try:
        with open(pbxproj_path, "r", encoding="utf-8") as f:
            content = f.read()
    except Exception:
        return {}, [], []

    # Extract all target package product dependencies
    target_products = []
    for block in re.findall(r'packageProductDependencies\s*=\s*\((.*?)\);', content, re.DOTALL):
        for line in block.splitlines():
            line_m = re.search(r'/\*\s*([^\*]+?)\s*\*/', line)
            if line_m:
                prod = line_m.group(1).strip()
                if prod and prod not in target_products:
                    target_products.append(prod)

    # Initial mapping from package references: e.g. "FFmpegKit", "SDWebImageSwiftUI"
    remote_product_map = {}
    for m in re.finditer(r'XCRemoteSwiftPackageReference\s+"([^"]+)"', content):
        pkg_ref = m.group(1).strip()
        key = pkg_ref.lower()
        remote_product_map[key] = pkg_ref

    # Specific product mappings: e.g. package = ... /* XCRemoteSwiftPackageReference "jellyfin-sdk-swift" */; productName = JellyfinAPI;
    for m in re.finditer(r'XCRemoteSwiftPackageReference\s+"([^"]+)"\s*\*/;\s*productName\s*=\s*([^;]+);', content):
        pkg_ref, prod_name = m.group(1).strip(), m.group(2).strip()
        key = pkg_ref.lower()
        # If the product name matches the package reference or is a primary target product, use it
        if prod_name.lower() == key or prod_name in target_products:
            remote_product_map[key] = prod_name
        elif key not in remote_product_map:
            remote_product_map[key] = prod_name

    # Extract local package references
    # e.g.: /* XCLocalSwiftPackageReference "../../Packages/BaseColors" */
    local_packages = []
    for m in re.finditer(r'XCLocalSwiftPackageReference\s+"([^"]+)"', content):
        rel_path = m.group(1).strip()
        pkg_name = os.path.basename(rel_path.rstrip("/"))
        if pkg_name and not any(p["name"] == pkg_name for p in local_packages):
            # Attempt to resolve git remote if available on disk
            candidate_paths = [
                os.path.normpath(os.path.join(project_dir, rel_path)),
                os.path.normpath(os.path.join(project_dir, "..", "..", "Packages", pkg_name)),
                os.path.normpath(os.path.join(os.path.expanduser("~"), "Documents/Projects/Apps/iOS/Packages", pkg_name))
            ]
            git_url = None
            for cp in candidate_paths:
                if os.path.isdir(cp):
                    try:
                        res = subprocess.run(
                            ["git", "-C", cp, "config", "--get", "remote.origin.url"],
                            capture_output=True,
                            text=True,
                            timeout=2
                        )
                        if res.returncode == 0 and res.stdout.strip():
                            git_url = res.stdout.strip()
                            break
                    except Exception:
                        pass

            local_packages.append({
                "id": pkg_name.lower(),
                "name": pkg_name,
                "url": clean_url(git_url),
                "version": None
            })

    return remote_product_map, target_products, local_packages

def format_fallback_name(identity):
    trimmed = identity.strip()
    if trimmed.startswith("swift-"):
        rest = trimmed[6:].replace("-", " ").title()
        return f"Swift {rest}"
    return trimmed.replace("-", " ").title()

def generate_dependencies(resolved_path, pbxproj_path, output_path):
    project_dir = os.path.abspath(os.path.join(os.path.dirname(resolved_path), "..", "..", ".."))

    remote_product_map, target_products, local_packages = parse_pbxproj(pbxproj_path, project_dir)
    raw_pins = parse_package_resolved(resolved_path)

    items = []
    seen_ids = set()

    for identity, location, version in raw_pins:
        key = identity.lower()
        seen_ids.add(key)

        # Name from pbxproj product mapping if available, otherwise formatted identity
        name = remote_product_map.get(key)
        if not name:
            name = format_fallback_name(identity)

        items.append({
            "id": identity,
            "name": name,
            "version": version,
            "url": clean_url(location)
        })

    # Add local packages from pbxproj
    for local in local_packages:
        if local["id"] not in seen_ids:
            items.append(local)
            seen_ids.add(local["id"])

    # Sort: Target products first in target order, followed alphabetically
    def sort_key(item):
        name = item["name"]
        try:
            priority = target_products.index(name)
        except ValueError:
            priority = 1000
        return (priority, name.lower())

    items.sort(key=sort_key)

    swift_lines = [
        "//",
        "//  PackageDependencies.generated.swift",
        "//  JellyBoi",
        "//",
        "//  Generated at compile time from Package.resolved and project.pbxproj.",
        "//  DO NOT EDIT MANUALLY - Automatically regenerated on build.",
        "//",
        "",
        "import Foundation",
        "",
        "public struct DependencyItem: Identifiable, Sendable {",
        "    public let id: String",
        "    public let name: String",
        "    public let version: String?",
        "    public let url: URL?",
        "",
        "    public init(",
        "        id: String? = nil,",
        "        name: String,",
        "        version: String? = nil,",
        "        url: URL? = nil",
        "    ) {",
        "        self.id = id ?? name",
        "        self.name = name",
        "        self.version = version",
        "        self.url = url",
        "    }",
        "",
        "    public var hasGitHubLink: Bool {",
        "        guard let url, let host = url.host?.lowercased() else { return false }",
        "        return host.contains(\"github.com\")",
        "    }",
        "}",
        "",
        "public enum PackageDependencies {",
        "    public static let all: [DependencyItem] = ["
    ]

    for item in items:
        id_esc = escape_swift_string(item["id"])
        name_esc = escape_swift_string(item["name"])
        ver_val = f'"{escape_swift_string(item["version"])}"' if item.get("version") else "nil"
        if item.get("url"):
            url_val = f'URL(string: "{escape_swift_string(item["url"])}")'
        else:
            url_val = "nil"

        swift_lines.append("        DependencyItem(")
        swift_lines.append(f'            id: "{id_esc}",')
        swift_lines.append(f'            name: "{name_esc}",')
        swift_lines.append(f'            version: {ver_val},')
        swift_lines.append(f'            url: {url_val}')
        swift_lines.append("        ),")

    swift_lines.append("    ]")
    swift_lines.append("}")
    swift_lines.append("")

    content = "\n".join(swift_lines)

    if os.path.exists(output_path):
        with open(output_path, "r", encoding="utf-8") as f:
            existing = f.read()
        if existing == content:
            print("PackageDependencies.generated.swift is up to date.")
            return

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"Generated {len(items)} package dependencies at compile time into {output_path}")

if __name__ == "__main__":
    project_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    resolved_arg = sys.argv[1] if len(sys.argv) > 1 else os.path.join(project_dir, "JellyBoi.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
    output_arg = sys.argv[2] if len(sys.argv) > 2 else os.path.join(project_dir, "JellyBoi/utility/PackageDependencies.generated.swift")
    pbxproj_arg = os.path.join(project_dir, "JellyBoi.xcodeproj/project.pbxproj")

    generate_dependencies(resolved_arg, pbxproj_arg, output_arg)
