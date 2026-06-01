#!/usr/bin/env bash
# =============================================================================
# setup-elementor-mcp.sh — Wire up the Elementor MCP server against a
# WordPress site (Local-by-Flywheel or live host) and write a .mcp.json
# in the current directory so Claude Code can drive Elementor.
#
# Usage:  bash scripts/setup-elementor-mcp.sh
#
# What it does:
#   1. Asks Local vs live host
#   2. Validates connectivity + REST auth
#   3. Confirms Elementor + Hello Elementor are installed (warns if not)
#   4. Downloads + installs WordPress MCP Adapter and elementor-mcp plugins
#   5. Verifies the /mcp/elementor-mcp-server route appears
#   6. Writes .mcp.json in the current directory
#
# Idempotent: safe to re-run.
# =============================================================================

set -uo pipefail

BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
RED=$'\033[31m'; CYAN=$'\033[36m'; RESET=$'\033[0m'

step()  { printf "\n${BOLD}${CYAN}▸ %s${RESET}\n" "$*"; }
ok()    { printf "  ${GREEN}✓${RESET} %s\n" "$*"; }
warn()  { printf "  ${YELLOW}⚠${RESET} %s\n" "$*"; }
fail()  { printf "  ${RED}✗${RESET} %s\n" "$*"; }
info()  { printf "  ${DIM}%s${RESET}\n" "$*"; }
ask()   { printf "${BOLD}? %s${RESET} " "$*"; }

abort() { fail "$1"; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || abort "Missing required command: $1"; }
need curl
need python3
need unzip
need zip

JQ_LENIENT_PY='
import sys, json, re
def _sanitize(s):
    valid = set("\"\\/bfnrtu")
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i+1 < len(s) and s[i+1] not in valid:
            out.append("\\\\")
        else:
            out.append(c)
        i += 1
    return "".join(out)
def _load(s):
    try: return json.loads(s)
    except json.JSONDecodeError: return json.loads(_sanitize(s))
'

jq_lenient() {
  python3 -c "$JQ_LENIENT_PY"'
import sys, json
data = _load(sys.stdin.read())
path = sys.argv[1].lstrip(".").split(".") if sys.argv[1] != "." else []
cur = data
for p in path:
    if p == "": continue
    if p.startswith("[") and p.endswith("]"):
        cur = cur[int(p[1:-1])]
    else:
        cur = cur.get(p) if isinstance(cur, dict) else None
    if cur is None: break
if isinstance(cur, (dict, list)):
    print(json.dumps(cur))
else:
    print("" if cur is None else cur)
' "$1"
}

jq_lenient_contains() {
  python3 -c "$JQ_LENIENT_PY"'
import sys
data = _load(sys.stdin.read())
path = sys.argv[1].lstrip(".").split(".")
needle = sys.argv[2]
cur = data
for p in path:
    if p == "": continue
    cur = cur.get(p) if isinstance(cur, dict) else None
    if cur is None: break
if isinstance(cur, list):
    print("yes" if any(needle in str(x) for x in cur) else "no")
elif isinstance(cur, dict):
    print("yes" if any(needle in str(k) for k in cur.keys()) else "no")
else:
    print("no")
' "$1" "$2"
}

clear 2>/dev/null || true
cat <<'BANNER'

  ╭───────────────────────────────────────────────╮
  │   Elementor MCP — Setup Wizard                │
  │   ───────────────────────────                 │
  │   Wires Claude Code to a WordPress site so    │
  │   it can build Elementor pages directly.      │
  ╰───────────────────────────────────────────────╯

BANNER

step "1/8  Site type"
echo "    [1] Local-by-Flywheel  (sites under ~/Local Sites/)"
echo "    [2] Live host          (any WordPress site reachable over HTTP/HTTPS)"
ask "Pick (1 or 2):"
read -r SITE_TYPE
case "$SITE_TYPE" in
  1) MODE="local"; ok "Local-by-Flywheel mode" ;;
  2) MODE="live";  ok "Live-host mode" ;;
  *) abort "Invalid choice. Run again with 1 or 2." ;;
esac

step "2/8  Site URL"

if [ "$MODE" = "local" ]; then
  if [ -d "$HOME/Local Sites" ]; then
    info "Sites detected in ~/Local Sites/:"
    for d in "$HOME/Local Sites"/*/; do
      [ -d "$d" ] && printf "      ${CYAN}•${RESET} %s\n" "$(basename "$d")"
    done
  fi
  ask "Local site name (folder under ~/Local Sites/):"
  read -r SITE_NAME
  SITE_PATH="$HOME/Local Sites/$SITE_NAME/app/public"
  [ -f "$SITE_PATH/wp-config.php" ] || abort "No wp-config.php at $SITE_PATH"
  SITE_URL="http://${SITE_NAME}.local"
  ok "Site path:  $SITE_PATH"
  ok "Site URL:   $SITE_URL"
else
  ask "Full site URL (e.g. https://example.com — no trailing slash):"
  read -r SITE_URL
  SITE_URL="${SITE_URL%/}"
  [[ "$SITE_URL" =~ ^https?:// ]] || abort "URL must start with http:// or https://"
  ok "Site URL:   $SITE_URL"
fi

step "3/8  Connectivity"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$SITE_URL/wp-json/" || echo "000")
case "$HTTP_CODE" in
  200|301|302) ok "Reached WP REST API ($HTTP_CODE)" ;;
  000) abort "Could not reach $SITE_URL — is the site running?" ;;
  401|403) warn "REST returned $HTTP_CODE — may be auth-gated; continuing" ;;
  *) abort "Got HTTP $HTTP_CODE from $SITE_URL/wp-json/" ;;
esac

step "4/8  Authentication"
cat <<EOF
    You need a WordPress Application Password.
    To create one:
      1. Log in to ${SITE_URL}/wp-admin
      2. Users → Profile → scroll to "Application Passwords"
      3. Name it (e.g. "ClaudeMCP"), click Add — copy the password shown
      4. The password NAME is just a label. The username is your WP login.
EOF
ask "WordPress username (your login, NOT the app-password label):"
read -r WP_USER
ask "Application password (24 chars with spaces is OK):"
read -r WP_APP_PWD

USERS_ME=$(curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 10 "$SITE_URL/wp-json/wp/v2/users/me" || echo "{}")
USER_ID=$(echo "$USERS_ME" | jq_lenient '.id' 2>/dev/null || echo "")
if [ -n "$USER_ID" ] && [ "$USER_ID" != "" ]; then
  USER_NAME=$(echo "$USERS_ME" | jq_lenient '.name')
  ok "Authenticated as: $USER_NAME"
else
  fail "Auth failed. Listing public users to help find the right slug:"
  USERS_LIST=$(curl -s --max-time 10 "$SITE_URL/wp-json/wp/v2/users?per_page=10" 2>/dev/null || echo "[]")
  echo "$USERS_LIST" | python3 -c "$JQ_LENIENT_PY"'
import sys
data = _load(sys.stdin.read())
if isinstance(data, list):
    for u in data:
        print(f"     • {u.get(\"slug\",\"?\")} — {u.get(\"name\",\"?\")}")
' 2>/dev/null || warn "Could not list users."
  abort "Re-run with the correct username."
fi

step "5/8  Plugin baseline"

plugin_is_active() {
  local slug="$1"
  echo "$PLUGINS_JSON" | python3 -c "$JQ_LENIENT_PY"'
import sys
slug = sys.argv[1]
d = _load(sys.stdin.read())
if isinstance(d, list):
    print("yes" if any(p.get("plugin","").startswith(slug+"/") and p.get("status")=="active" for p in d) else "no")
else:
    print("no")
' "$slug" 2>/dev/null || echo "no"
}

plugin_is_installed() {
  local slug="$1"
  echo "$PLUGINS_JSON" | python3 -c "$JQ_LENIENT_PY"'
import sys
slug = sys.argv[1]
d = _load(sys.stdin.read())
if isinstance(d, list):
    print("yes" if any(p.get("plugin","").startswith(slug+"/") for p in d) else "no")
else:
    print("no")
' "$slug" 2>/dev/null || echo "no"
}

refresh_plugins_json() {
  PLUGINS_JSON=$(curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 10 \
    "$SITE_URL/wp-json/wp/v2/plugins" || echo "[]")
}

install_wp_plugin() {
  local slug="$1"
  local label="$2"
  if [ "$(plugin_is_active "$slug")" = "yes" ]; then
    ok "$label already active"; return 0
  fi
  if [ "$(plugin_is_installed "$slug")" = "yes" ]; then
    info "$label already installed — activating..."
    local plugin_path
    plugin_path=$(echo "$PLUGINS_JSON" | python3 -c "$JQ_LENIENT_PY"'
import sys
slug = sys.argv[1]
d = _load(sys.stdin.read())
if isinstance(d, list):
    for p in d:
        if p.get("plugin","").startswith(slug+"/"):
            print(p["plugin"]); break
' "$slug" 2>/dev/null)
    if [ -n "$plugin_path" ]; then
      curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 30 \
        -H "Content-Type: application/json" \
        -X POST "$SITE_URL/wp-json/wp/v2/plugins/$plugin_path" \
        -d '{"status":"active"}' >/dev/null
    fi
  else
    info "Installing + activating $label from wordpress.org..."
    local result err
    result=$(curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 60 \
      -H "Content-Type: application/json" \
      -X POST "$SITE_URL/wp-json/wp/v2/plugins" \
      -d "{\"slug\":\"$slug\",\"status\":\"active\"}" || echo '{"code":"network_error"}')
    err=$(echo "$result" | jq_lenient '.code' 2>/dev/null || echo "")
    if [ -n "$err" ] && [ "$err" != "" ]; then
      fail "Could not install $label: $err"; return 1
    fi
  fi
  refresh_plugins_json
  if [ "$(plugin_is_active "$slug")" = "yes" ]; then
    ok "Installed + activated $label"; return 0
  fi
  warn "$label installed but not active yet — retrying..."
  local plugin_path
  plugin_path=$(echo "$PLUGINS_JSON" | python3 -c "$JQ_LENIENT_PY"'
import sys
slug = sys.argv[1]
d = _load(sys.stdin.read())
if isinstance(d, list):
    for p in d:
        if p.get("plugin","").startswith(slug+"/"):
            print(p["plugin"]); break
' "$slug" 2>/dev/null)
  if [ -n "$plugin_path" ]; then
    curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 30 \
      -H "Content-Type: application/json" \
      -X POST "$SITE_URL/wp-json/wp/v2/plugins/$plugin_path" \
      -d '{"status":"active"}' >/dev/null
    sleep 1; refresh_plugins_json
  fi
  if [ "$(plugin_is_active "$slug")" = "yes" ]; then
    ok "Installed + activated $label (after retry)"; return 0
  fi
  fail "$label installed but could NOT auto-activate."
  info "Activate manually: ${SITE_URL}/wp-admin/plugins.php"
  return 1
}

PLUGINS_JSON=$(curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 10 "$SITE_URL/wp-json/wp/v2/plugins" || echo "[]")
THEME_JSON=$(curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 10 "$SITE_URL/wp-json/wp/v2/themes?status=active" || echo "[]")
ACTIVE_THEME=$(echo "$THEME_JSON" | python3 -c "$JQ_LENIENT_PY"'
import sys
d = _load(sys.stdin.read())
print(d[0]["stylesheet"] if isinstance(d, list) and d else "?")
' 2>/dev/null || echo "?")

HAS_ELEMENTOR=$(plugin_is_active "elementor")
HAS_UAE=$(plugin_is_active "header-footer-elementor")
HAS_EA=$(plugin_is_active "essential-addons-for-elementor-lite")
HAS_FF=$(plugin_is_active "fluentform")

[ "$HAS_ELEMENTOR" = "yes" ] && ok "Elementor (free) — active" || warn "Elementor — not active"
[ "$ACTIVE_THEME" = "hello-elementor" ] && ok "Theme: Hello Elementor — active" || warn "Theme: $ACTIVE_THEME (Hello Elementor recommended)"
[ "$HAS_UAE" = "yes" ] && ok "UAE / Header Footer Elementor — active" || warn "UAE / Header Footer Elementor — not active (needed for headers/footers)"

step "6/8  Auto-install baseline plugins?"

NEEDS_ANY="no"
[ "$HAS_ELEMENTOR" != "yes" ] && NEEDS_ANY="yes"
[ "$HAS_UAE" != "yes" ] && NEEDS_ANY="yes"
[ "$ACTIVE_THEME" != "hello-elementor" ] && NEEDS_ANY="yes"

if [ "$NEEDS_ANY" = "no" ]; then
  ok "All baseline plugins + theme already in place — skipping."
else
  cat <<EOF
    Some baseline plugins/theme aren't active. The wizard can install them:
      • Elementor (free), Hello Elementor (theme), UAE / Header Footer Elementor
      • Essential Addons (lite) + Fluent Forms (optional)
EOF
  ask "Auto-install Elementor + UAE? [Y/n]"
  read -r DO_INSTALL
  if [[ ! "$DO_INSTALL" =~ ^[Nn]$ ]]; then
    [ "$HAS_ELEMENTOR" != "yes" ] && install_wp_plugin "elementor" "Elementor (free)"
    [ "$HAS_UAE" != "yes" ] && install_wp_plugin "header-footer-elementor" "UAE / Header Footer Elementor"
    ask "Also install Essential Addons + Fluent Forms (optional)? [y/N]"
    read -r DO_OPT
    if [[ "$DO_OPT" =~ ^[Yy]$ ]]; then
      install_wp_plugin "essential-addons-for-elementor-lite" "Essential Addons (lite)"
      install_wp_plugin "fluentform" "Fluent Forms"
    fi
  fi
fi

step "7/8  Installing MCP plugins"

NS_JSON=$(curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 10 "$SITE_URL/wp-json/" || echo "{}")
HAS_MCP=$(echo "$NS_JSON" | jq_lenient_contains '.namespaces' 'mcp' 2>/dev/null || echo "no")

if [ "$HAS_MCP" = "yes" ]; then
  ok "MCP namespace already registered — skipping plugin install."
else
  info "Downloading WordPress MCP Adapter..."
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT

  ADAPTER_URL=$(curl -s "https://api.github.com/repos/WordPress/mcp-adapter/releases/latest" \
    | python3 -c "$JQ_LENIENT_PY"'
import sys
d = _load(sys.stdin.read())
a = [a for a in d.get("assets",[]) if a["name"].endswith(".zip")]
print(a[0]["browser_download_url"] if a else d.get("zipball_url",""))
')
  [ -n "$ADAPTER_URL" ] || abort "Could not fetch mcp-adapter download URL."
  curl -sL -o "$WORK/mcp-adapter.zip" "$ADAPTER_URL" || abort "Adapter download failed."
  ok "Downloaded mcp-adapter.zip"

  info "Downloading elementor-mcp..."
  EM_ZIPBALL=$(curl -s "https://api.github.com/repos/msrbuilds/elementor-mcp/releases/latest" \
    | python3 -c "$JQ_LENIENT_PY"'
import sys
d = _load(sys.stdin.read())
a = [a for a in d.get("assets",[]) if a["name"].endswith(".zip")]
print(a[0]["browser_download_url"] if a else d.get("zipball_url",""))
')
  [ -n "$EM_ZIPBALL" ] || abort "Could not fetch elementor-mcp download URL."
  curl -sL -o "$WORK/elementor-mcp-src.zip" "$EM_ZIPBALL" || abort "elementor-mcp download failed."

  ( cd "$WORK" && unzip -q elementor-mcp-src.zip )
  EM_DIR=$(find "$WORK" -maxdepth 1 -type d -name "*elementor-mcp*" 2>/dev/null | head -1)
  if [ -n "$EM_DIR" ] && [ "$(basename "$EM_DIR")" != "elementor-mcp" ]; then
    mv "$EM_DIR" "$WORK/elementor-mcp"
  fi
  ( cd "$WORK" && rm -f elementor-mcp.zip && zip -qr elementor-mcp.zip elementor-mcp )
  ok "Repacked elementor-mcp.zip"

  if [ "$MODE" = "local" ]; then
    info "Installing via Local's bundled WP-CLI..."
    LOCAL_PHP=$(find "$HOME/Library/Application Support/Local/lightning-services" -maxdepth 6 -name "php" -type f 2>/dev/null | head -1)
    LOCAL_WP="/Applications/Local.app/Contents/Resources/extraResources/bin/wp-cli/posix/wp"
    [ -x "$LOCAL_PHP" ] || abort "Local's PHP binary not found. Is Local installed?"
    [ -f "$LOCAL_WP"  ] || abort "Local's WP-CLI binary not found at $LOCAL_WP"
    SOCK=$(find "$HOME/Library/Application Support/Local/run" -name "mysqld.sock" 2>/dev/null | while read s; do
      if "$LOCAL_PHP" -d "mysqli.default_socket=$s" -d "pdo_mysql.default_socket=$s" "$LOCAL_WP" --path="$SITE_PATH" --skip-plugins --skip-themes core version >/dev/null 2>&1; then
        echo "$s"; break
      fi
    done)
    [ -n "$SOCK" ] || abort "Could not find MySQL socket for $SITE_NAME. Is the site started in Local?"
    ok "MySQL socket: $SOCK"
    PHPRUN=( "$LOCAL_PHP" -d "mysqli.default_socket=$SOCK" -d "pdo_mysql.default_socket=$SOCK" )
    "${PHPRUN[@]}" "$LOCAL_WP" --path="$SITE_PATH" --skip-plugins --skip-themes plugin install "$WORK/mcp-adapter.zip" --activate --force >/dev/null 2>&1 \
      && ok "mcp-adapter installed + activated" || fail "mcp-adapter install failed"
    "${PHPRUN[@]}" "$LOCAL_WP" --path="$SITE_PATH" --skip-plugins --skip-themes plugin install "$WORK/elementor-mcp.zip" --activate --force >/dev/null 2>&1 \
      && ok "elementor-mcp installed + activated" || fail "elementor-mcp install failed"
  else
    warn "Live hosts: REST API can't install arbitrary plugin zips."
    info "Upload these two zips manually via: ${SITE_URL}/wp-admin/plugin-install.php?tab=upload"
    info "  $WORK/mcp-adapter.zip"
    info "  $WORK/elementor-mcp.zip"
    ask "Press Enter once both are uploaded and activated..."
    read -r _
  fi
fi

info "Verifying /mcp/elementor-mcp-server route..."
sleep 2

verify_mcp_namespace() {
  local ns_json
  ns_json=$(curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 10 "$SITE_URL/wp-json/" || echo "{}")
  local has_mcp has_em
  has_mcp=$(echo "$ns_json" | jq_lenient_contains '.namespaces' 'mcp' 2>/dev/null || echo "no")
  has_em=$(echo "$ns_json" | jq_lenient_contains '.routes' 'elementor-mcp-server' 2>/dev/null || echo "no")
  [ "$has_mcp" = "yes" ] && [ "$has_em" = "yes" ] && return 0
  return 1
}

if verify_mcp_namespace; then
  ok "Elementor MCP server route registered ✓"
else
  warn "MCP namespace not yet registered."
  info "Open WP Admin → Plugins and confirm both MCP plugins are active:"
  info "  ${SITE_URL}/wp-admin/plugins.php"
  ask "Press Enter when both are active (or 'skip' to bypass)..."
  read -r RECOVER
  if [ "$RECOVER" != "skip" ]; then
    sleep 1
    verify_mcp_namespace && ok "Elementor MCP route now registered ✓" || warn "Still not visible — proceeding anyway. Fix activation before using Claude."
  fi
fi

step "8/8  Writing .mcp.json"
PROJECT_DIR="$(pwd)"
MCP_FILE="$PROJECT_DIR/.mcp.json"
AUTH_B64=$(printf "%s:%s" "$WP_USER" "$WP_APP_PWD" | python3 -c "import sys,base64; sys.stdout.write(base64.b64encode(sys.stdin.buffer.read()).decode())")

SKIP_WRITE=0
if [ -f "$MCP_FILE" ]; then
  warn ".mcp.json already exists"
  ask "Overwrite? [y/N]"
  read -r OVR
  [[ "$OVR" =~ ^[Yy]$ ]] || SKIP_WRITE=1
fi

NEW_CONFIG=$(cat <<JSON
{
  "mcpServers": {
    "elementor": {
      "type": "http",
      "url": "${SITE_URL}/wp-json/mcp/elementor-mcp-server",
      "headers": {
        "Authorization": "Basic ${AUTH_B64}"
      }
    }
  }
}
JSON
)

if [ "$SKIP_WRITE" != "1" ]; then
  printf "%s\n" "$NEW_CONFIG" > "$MCP_FILE"
  ok "Wrote $MCP_FILE"
else
  info "Suggested config:"; echo "$NEW_CONFIG" | sed 's/^/      /'
fi

cat <<EOF

  ${BOLD}${GREEN}✓ Setup complete${RESET}

  Next steps:
    1. ${CYAN}Quit Claude Code${RESET} (Cmd-Q or Ctrl-C)
    2. ${CYAN}Reopen in this directory${RESET}
    3. Approve the 'elementor' MCP server when prompted

  Then run:
    ${CYAN}/clone-website --output=elementor https://your-target-site.com${RESET}

EOF
