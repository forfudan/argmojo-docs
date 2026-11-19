#!/usr/bin/env bash
# Builds the book into book/.
#
#   bash scripts/build.sh                                   # manual from ARGMOJO_REF below
#   ARGMOJO_REF=v0.10.0 bash scripts/build.sh               # from another tag or branch
#   ARGMOJO_MANUAL=../argmojo/docs/user_manual.md bash scripts/build.sh   # a local copy
#
# It splits the manual into src/ (scripts/split_manual.py), then runs
# `mdbook build`. It uses the mdbook on PATH when that is the pinned version.
# Otherwise, as on the Cloudflare build image, it downloads the pinned release
# once into .cache/. Any warning from mdbook fails the build, so a broken page
# cannot reach the site.
set -euo pipefail

# The argmojo branch or tag that the site shows. It should become the latest
# release tag once a release has the `mdbook:` comments in its manual. This is
# the one line to change.
: "${ARGMOJO_REF:=main}"

# The release that theme/index.hbs was copied from. The template has to
# match the mdbook that renders it, so change both together (see README.md).
MDBOOK_VERSION=v0.5.4

# A relative ARGMOJO_MANUAL is read from where you are, not from the book.
if [[ -n ${ARGMOJO_MANUAL:-} ]]; then
    ARGMOJO_MANUAL=$(cd "$(dirname "$ARGMOJO_MANUAL")" && pwd)/$(basename "$ARGMOJO_MANUAL")
fi
cd "$(dirname "$0")/.."

if [[ -n ${ARGMOJO_MANUAL:-} ]]; then
    python3 scripts/split_manual.py --manual "$ARGMOJO_MANUAL" --ref "$ARGMOJO_REF"
else
    python3 scripts/split_manual.py --ref "$ARGMOJO_REF"
fi

if command -v mdbook > /dev/null && [[ $(mdbook --version) == "mdbook $MDBOOK_VERSION" ]]; then
    MDBOOK=mdbook
else
    case "$(uname -s)-$(uname -m)" in
        Linux-x86_64) target=x86_64-unknown-linux-gnu ;;
        Linux-aarch64) target=aarch64-unknown-linux-musl ;;
        Darwin-arm64) target=aarch64-apple-darwin ;;
        Darwin-x86_64) target=x86_64-apple-darwin ;;
        *)
            echo "build.sh: no mdbook release for this machine; install mdbook $MDBOOK_VERSION" >&2
            exit 1
            ;;
    esac
    MDBOOK=.cache/mdbook-$MDBOOK_VERSION/mdbook
    if [[ ! -x $MDBOOK ]]; then
        mkdir -p "$(dirname "$MDBOOK")"
        url=https://github.com/rust-lang/mdBook/releases/download/$MDBOOK_VERSION/mdbook-$MDBOOK_VERSION-$target.tar.gz
        echo "build.sh: downloading $url"
        curl -sSfL "$url" | tar -xz -C "$(dirname "$MDBOOK")"
    fi
fi

mkdir -p .cache
"$MDBOOK" build 2>&1 | tee .cache/build.log
if grep -E 'WARN|ERROR' .cache/build.log > /dev/null; then
    echo "build.sh: mdbook printed a warning; see above" >&2
    exit 1
fi
# The search finds a method by its own name: `get_flag` finds
# `result.get_flag()` (see scripts/patch_search.js). Node is on the Cloudflare
# build image, which needs it for wrangler.
if ! command -v node > /dev/null; then
    echo "build.sh: node is needed to patch the search index; install Node.js" >&2
    exit 1
fi
node scripts/patch_search.js book

# A page at each old path in redirects.txt that sends the reader on, once
# the old page is gone.
python3 - <<'PY'
import html, os
for line in open("redirects.txt", encoding="utf-8"):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    old, new = line.split()
    path = os.path.join("book", old)
    if os.path.exists(path):
        continue
    url = "/" + new
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as out:
        out.write(
            '<!DOCTYPE html>\n<meta charset="utf-8">\n<title>Moved</title>\n'
            '<meta http-equiv="refresh" content="0; url=%s">\n'
            '<link rel="canonical" href="%s">\n'
            '<p>This page has moved to <a href="%s">%s</a>.</p>\n'
            % ((html.escape(url),) * 4)
        )
PY

# A sitemap and a robots.txt for search engines, from the pages SUMMARY.md
# lists. A page `a/index.md` is served at `a/`, any other `a/b.md` at `a/b`.
python3 - <<'PY'
import re
site = "https://argmojo.mojo-lang.com/"
files = re.findall(r"\]\(([^)]+\.md)\)", open("src/SUMMARY.md", encoding="utf-8").read())
urls = [site]
for f in files[1:]:
    urls.append(site + (f[: -len("index.md")] if f.endswith("index.md") else f[:-3]))
with open("book/sitemap.xml", "w", encoding="utf-8") as out:
    out.write('<?xml version="1.0" encoding="UTF-8"?>\n')
    out.write('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n')
    out.writelines("  <url><loc>%s</loc></url>\n" % u for u in urls)
    out.write("</urlset>\n")
with open("book/robots.txt", "w", encoding="utf-8") as out:
    out.write("User-agent: *\nAllow: /\nSitemap: %ssitemap.xml\n" % site)
PY
echo "build.sh: the book is in book/"
