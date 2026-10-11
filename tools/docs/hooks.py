"""MkDocs hook of the documentation site: renders the Markdown files of the repository where they are.

The documentation is not copied into a docs folder. This hook adds the files of the repository to the site and
adapts the GitHub-flavoured Markdown to MkDocs:

- ``extra.collect.include`` / ``exclude``: glob patterns, relative to the repository root, of the files that become
  part of the site (Markdown pages and images). Every other file of the repository that a page links to is linked
  on GitHub (blob view, tree view for directories) on the branch named in ``edit_uri``; files in a git submodule
  are linked at the commit the submodule is pinned to.
- A nav entry whose path contains a wildcard expands to one page per file (``doc/ft/*.md``) or, ending with a
  slash, to one section per directory (``hdl/*/``). Files that the nav names explicitly are skipped. Directory
  sections are ordered like ``extra.collect.order_file`` (one directory per line), the pages inside a section like
  ``extra.collect.page_order`` (file stems).
- GitHub alerts (``> [!NOTE]``) become admonitions, ``$$`` display math becomes MathML and lines matching one of
  the regular expressions in ``extra.collect.strip`` are dropped (badges and logos meant for the GitHub view).
  Repeated headings get the anchors GitHub gives them (name, name-1, ...).
- The start page is shown without the navigation sidebar; the "edit" button of every page opens the file in the
  repository.
"""

import fnmatch
import glob
import logging
import os
import posixpath
import re
import subprocess
from urllib.parse import unquote

import markdown.extensions.toc
from mkdocs.structure.files import File

log = logging.getLogger("mkdocs.hooks.docs_site")


def _unique_id(slug, ids):
    """Number repeated headings like GitHub (name, name-1, name-2) so that anchors written for GitHub work."""
    candidate, count = slug, 0
    while candidate in ids or not candidate:
        count += 1
        candidate = f"{slug}-{count}"
    ids.add(candidate)
    return candidate


markdown.extensions.toc.unique = _unique_id

SITE_EXTENSIONS = (".md", ".png", ".svg", ".jpg", ".jpeg", ".gif", ".webp")
DEFAULT_PAGE_ORDER = ["README", "index"]
ALERTS = {
    "NOTE": ("note", "Note"),
    "TIP": ("tip", "Tip"),
    "IMPORTANT": ("info", "Important"),
    "WARNING": ("warning", "Warning"),
    "CAUTION": ("danger", "Caution"),
}

_state = {}


# ------------------------------------------------------------------------------------------------------------------
# Configuration and files
# ------------------------------------------------------------------------------------------------------------------
def on_config(config):
    settings = dict(config.extra.get("collect", {}))
    config_dir = os.path.dirname(os.path.abspath(config.config_file_path))
    root = os.path.normpath(os.path.join(config_dir, settings.get("root", "../..")))
    repo_url = config.repo_url.rstrip("/")
    branch = (config.edit_uri or "edit/main/").strip("/").split("/")[1]

    collected = set()
    for pattern in settings.get("include", []):
        for path in glob.glob(pattern, root_dir=root, recursive=True):
            rel = path.replace(os.sep, "/")
            if os.path.isfile(os.path.join(root, rel)) and rel.lower().endswith(SITE_EXTENSIONS):
                collected.add(rel)
    for pattern in settings.get("exclude", []):
        collected = {rel for rel in collected if not fnmatch.fnmatch(rel, pattern)}

    order = []
    if settings.get("order_file"):
        with open(os.path.join(root, settings["order_file"]), encoding="utf-8") as file:
            order = [line.strip().strip("/") for line in file if line.strip() and not line.startswith("#")]

    _state.clear()
    _state.update(
        root=root,
        docs_dir=os.path.abspath(config.docs_dir),
        repo_url=repo_url,
        branch=branch,
        submodules=_submodules(root),
        collected=collected,
        order=order,
        page_order=settings.get("page_order", DEFAULT_PAGE_ORDER),
        strip=[re.compile(expr) for expr in settings.get("strip", [])],
    )
    if config.nav:
        config.nav = _expand_nav(config.nav, _explicit_paths(config.nav))
    return config


def _submodules(root):
    """Map the path of each git submodule to the GitHub URL of the commit it is pinned to."""
    result = {}
    try:
        with open(os.path.join(root, ".gitmodules"), encoding="utf-8") as file:
            text = file.read()
    except OSError:
        return result
    for block in re.split(r"^\[submodule ", text, flags=re.M)[1:]:
        path = re.search(r"^\s*path\s*=\s*(\S+)", block, re.M)
        url = re.search(r"^\s*url\s*=\s*(\S+)", block, re.M)
        if not (path and url and "github.com" in url.group(1)):
            continue
        try:
            tree = subprocess.run(["git", "-C", root, "ls-tree", "HEAD", path.group(1)],
                                  capture_output=True, text=True, check=True).stdout.split()
            commit = tree[2]
        except (OSError, subprocess.CalledProcessError, IndexError):
            commit = "HEAD"
        result[path.group(1).strip("/")] = f"{url.group(1).removesuffix('.git').rstrip('/')}/blob/{commit}"
    return result


def on_files(files, config):
    for rel in sorted(_state["collected"]):
        if files.get_file_from_path(rel) is None:
            files.append(File(rel, _state["root"], config.site_dir, config.use_directory_urls))
    return files


def on_serve(server, config, builder):
    for rel in sorted({rel.split("/")[0] for rel in _state["collected"]}):
        server.watch(os.path.join(_state["root"], rel))
    return server


# ------------------------------------------------------------------------------------------------------------------
# Navigation
# ------------------------------------------------------------------------------------------------------------------
def _is_glob(value):
    return isinstance(value, str) and any(char in value for char in "*?[")


def _explicit_paths(items):
    paths = set()
    for item in items:
        value = next(iter(item.values())) if isinstance(item, dict) else item
        if isinstance(value, list):
            paths |= _explicit_paths(value)
        elif isinstance(value, str) and not _is_glob(value):
            paths.add(value)
    return paths


def _expand_nav(items, explicit):
    result = []
    for item in items:
        if isinstance(item, dict):
            title, value = next(iter(item.items()))
            if isinstance(value, list):
                result.append({title: _expand_nav(value, explicit)})
            elif _is_glob(value):
                result.append({title: _expand_glob(value, explicit)})
            else:
                result.append(item)
        elif _is_glob(item):
            result.extend(_expand_glob(item, explicit))
        else:
            result.append(item)
    return result


def _stem(path):
    return posixpath.splitext(posixpath.basename(path))[0]


def _page_key(path):
    stem = _stem(path)
    order = _state["page_order"]
    return (order.index(stem) if stem in order else len(order), path.lower())


def _expand_glob(pattern, explicit):
    pages = sorted(_state["collected"])
    if not pattern.endswith("/"):
        matches = [rel for rel in pages if rel.endswith(".md") and fnmatch.fnmatch(rel, pattern)]
        return sorted((rel for rel in matches if rel not in explicit), key=_page_key)

    order = _state["order"]
    dirs = sorted((path.replace(os.sep, "/").rstrip("/") for path in glob.glob(pattern, root_dir=_state["root"])),
                  key=lambda d: (order.index(d) if d in order else len(order), d))
    sections = []
    for directory in dirs:
        members = [rel for rel in pages
                   if rel.endswith(".md") and rel.startswith(directory + "/") and rel not in explicit]
        if not members:
            continue
        entries = []
        for rel in sorted(members, key=_page_key):
            stem = _stem(rel)
            title = "Overview" if stem in ("README", "index") else stem.replace("_", " ").capitalize()
            entries.append({title: rel})
        sections.append({posixpath.basename(directory): entries})
    return sections


# ------------------------------------------------------------------------------------------------------------------
# Markdown
# ------------------------------------------------------------------------------------------------------------------
FENCE = re.compile(r"^\s*(`{3,}|~{3,})")
LINK = re.compile(r"(\]\(\s*<?)([^)\s>]+)(>?(?:\s+\"[^\"]*\")?\s*\))")
HTML_ATTR = re.compile(r"(\b(?:src|href)=\")([^\"]+)(\")")
ALERT = re.compile(r"^>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$")
CODE_SPAN = re.compile(r"(`+[^`]*`+)")


def on_page_markdown(markdown, page, config, files):
    src = page.file.src_uri
    rel_path = os.path.relpath(page.file.abs_src_path, _state["root"]).replace(os.sep, "/")
    page.edit_url = f"{_state['repo_url']}/edit/{_state['branch']}/{rel_path}"
    if page.is_homepage:
        page.meta.setdefault("hide", ["navigation"])

    lines = markdown.split("\n")
    out = []
    fence = None
    index = 0
    while index < len(lines):
        line = lines[index]
        match = FENCE.match(line)
        if fence:
            out.append(line)
            if match and match.group(1)[0] == fence[0] and len(match.group(1)) >= len(fence):
                fence = None
            index += 1
            continue
        if match:
            fence = match.group(1)
            out.append(line)
            index += 1
            continue
        if any(expr.search(line) for expr in _state["strip"]):
            index += 1
            continue
        alert = ALERT.match(line)
        if alert:
            kind, title = ALERTS[alert.group(1)]
            out.append(f'!!! {kind} "{title}"')
            index += 1
            while index < len(lines) and lines[index].startswith(">"):
                out.append("    " + _links(re.sub(r"^>\s?", "", lines[index]), src))
                index += 1
            out.append("")
            continue
        if line.strip() == "$$":
            end = index + 1
            while end < len(lines) and lines[end].strip() != "$$":
                end += 1
            if end < len(lines):
                out.append(_math("\n".join(lines[index + 1:end])))
                index = end + 1
                continue
        out.append(_links(line, src))
        index += 1
    return "\n".join(out)


def _math(latex):
    try:
        from latex2mathml.converter import convert
    except ImportError:
        log.warning("latex2mathml is not installed, display math is shown as source")
        return f"```latex\n{latex}\n```"
    return '<div class="arithmatex">' + convert(latex.strip(), display="block") + "</div>"


def _links(line, src):
    parts = CODE_SPAN.split(line)
    for i in range(0, len(parts), 2):
        part = LINK.sub(lambda m: m.group(1) + _target(m.group(2), src) + m.group(3), parts[i])
        parts[i] = HTML_ATTR.sub(lambda m: m.group(1) + _target(m.group(2), src) + m.group(3), part)
    return "".join(parts)


def _target(target, src):
    if not target or target.startswith(("#", "/")) or re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target):
        return target
    path, _, fragment = target.partition("#")
    path = path.split("?")[0]
    rel = posixpath.normpath(posixpath.join(posixpath.dirname(src), unquote(path)))
    if rel == ".." or rel.startswith("../"):
        return target
    if rel in _state["collected"] or os.path.isfile(os.path.join(_state["docs_dir"], rel)):
        return target
    absolute = os.path.join(_state["root"], rel)
    suffix = "#" + fragment if fragment else ""
    for submodule, url in _state["submodules"].items():
        if rel.startswith(submodule + "/"):
            return f"{url}/{rel[len(submodule) + 1:]}{suffix}"
    if os.path.isdir(absolute):
        readme = posixpath.normpath(posixpath.join(rel, "README.md"))
        if readme in _state["collected"]:
            return posixpath.relpath(readme, posixpath.dirname(src) or ".") + suffix
        return f"{_state['repo_url']}/tree/{_state['branch']}/{rel}"
    if os.path.isfile(absolute):
        view = "raw" if rel.lower().endswith(SITE_EXTENSIONS[1:]) else "blob"
        return f"{_state['repo_url']}/{view}/{_state['branch']}/{rel}{suffix}"
    return target
