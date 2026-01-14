#!/usr/bin/env bash
# ==========================================
#  TICC-DASH Uninstaller
#  - Stops & disables the systemd service (ticc-dash.service)
#  - Removes the unit & symlink and reloads systemd
#  - Frees TCP port $PORT (default 5000) and kills app processes
#  - Optionally removes ticc-user system account (with confirmation)
#  - Deletes application directory (/opt/ticc-dash)
#  - Idempotent: safe to re-run if parts are already gone
# ==========================================

set -euo pipefail

APP_DIR="/opt/ticc-dash"
SERVICE_NAME="ticc-dash.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
WANTS_LINK="/etc/systemd/system/multi-user.target.wants/$SERVICE_NAME"
PORT="${PORT:-5000}"
USER_NAME="ticc-user"

log()  { printf "\n\033[1;34m%s\033[0m\n" "$*"; }
ok()   { printf "\033[1;32m%s\033[0m\n" "$*"; }
warn() { printf "\n\033[1;33m%s\033[0m\n" "$*"; }
run()  { echo "  $*"; eval "$*" >/dev/null 2>&1 || true; }

trap 'echo "❌ Uninstall aborted."; exit 1' ERR

echo "=========================================="
echo "  🧹 Uninstalling TICC-DASH"
echo "=========================================="

# 1️⃣ Stop & disable the systemd service (if it exists)
if systemctl list-unit-files | grep -q "^$SERVICE_NAME"; then
  log "🛑 Stopping and disabling systemd service..."
  run "sudo systemctl stop '$SERVICE_NAME'"
  run "sudo systemctl disable '$SERVICE_NAME'"
  ok "✅ Service stopped and disabled."
fi

# 2️⃣ Remove service symlink & unit
log "🗑️  Removing service symlink & unit..."
run "sudo rm -f '$WANTS_LINK'"
run "sudo rm -f '$SERVICE_FILE'"
run "sudo systemctl reset-failed"
run "sudo systemctl daemon-reload"
ok "✅ Service removed and systemd reloaded."

# 3️⃣ Kill any process listening on the app port
log "🔌 Killing any process listening on TCP port $PORT..."
run "sudo fuser -k ${PORT}/tcp"
ok "✅ Port cleanup done."

# 4️⃣ Kill any process started from /opt/ticc-dash (TERM → KILL)
log "🪓 Killing processes started from $APP_DIR..."
run "sudo pkill -f '$APP_DIR'"
sleep 0.5
run "sudo pkill -9 -f '$APP_DIR'"
ok "✅ Process cleanup done."

# 5️⃣ System user cleanup (optional)
log "👤 Checking system user '$USER_NAME'..."
if id "$USER_NAME" >/dev/null 2>&1; then
  echo "⚠️  System user '$USER_NAME' exists (created for TICC-DASH)."
  echo "    Remove user account? This will prevent service restart. [y/N]"
  read -r response
  if [[ "$response" =~ ^[Yy]$ ]]; then
    # User is automatically removed from all groups when deleted
    run "sudo userdel '$USER_NAME'"
    ok "✅ System user '$USER_NAME' removed."
  else
    ok "ℹ️  Skipped user removal. User remains in chrony group."
  fi
else
  ok "✅ No system user to clean up."
fi

# Clean up old sudoers file if it exists from previous installation
if [ -f "/etc/sudoers.d/ticc-dash" ]; then
  log "🧹 Removing old sudoers rule from previous installation..."
  run "sudo rm -f '/etc/sudoers.d/ticc-dash'"
  run "sudo visudo -c"
  ok "✅ Old sudoers rule removed."
fi

# 6️⃣ Remove application directory
log "📁 Removing application directory: $APP_DIR ..."
run "sudo rm -rf '$APP_DIR'"
ok "✅ Application directory removed."

# 7️⃣ Summary
echo
echo "=========================================="
ok "🎉 Uninstall completed."
echo "Removed/cleaned:"
echo "  • Service/unit/symlink: $SERVICE_NAME"
echo "  • App dir:              $APP_DIR"
echo "  • System user:          checked and optionally removed"
echo "  • Port ${PORT}:          freed"
echo
echo "Verify:"
echo "  • systemctl status $SERVICE_NAME"
echo "  • pgrep -a gunicorn"
echo "  • ss -lptn 'sport = :${PORT}'"
echo "  • ls -la $APP_DIR"
echo "=========================================="
