#!/usr/bin/env bash
# ==========================================
#  TICC-DASH Installer
#  - Installs into /opt/ticc-dash
#  - Creates dedicated ticc-user system account
#  - Creates venv and installs Flask + Gunicorn
#  - Downloads ticc-dash.py + logo from GitHub
#  - Sets up and enables a systemd service
# ==========================================

set -euo pipefail

APP_NAME="TICC-DASH"
APP_DIR="/opt/ticc-dash"
VENV_DIR="$APP_DIR/venv"
SERVICE_NAME="ticc-dash.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"

# Sources in repo
REPO_RAW_PY="https://raw.githubusercontent.com/arunderwood/ticc-dash/main/ticc-dash.py"
REPO_RAW_LOGO="https://raw.githubusercontent.com/arunderwood/ticc-dash/main/static/img/ticc-dash-logo.png"

USER_NAME="ticc-user"

log()  { printf "\n\033[1;34m%s\033[0m\n" "$*"; }
ok()   { printf "\033[1;32m%s\033[0m\n" "$*"; }
warn() { printf "\n\033[1;33m%s\033[0m\n" "$*"; }
run()  { echo "  $*"; eval "$*"; }

trap 'echo "❌ Installation aborted."; exit 1' ERR

echo "=========================================="
echo "  🚀 Installing $APP_NAME"
echo "=========================================="

# 1) Dependencies
log "📦 Installing dependencies..."
run "sudo apt update -y"
run "sudo apt install -y python3 python3-venv python3-pip chrony nginx curl"
ok "✅ Dependencies installed."

# 2) Create dedicated system user
log "👤 Creating dedicated system user '$USER_NAME'..."
if id "$USER_NAME" >/dev/null 2>&1; then
  ok "✅ User '$USER_NAME' already exists."
else
  run "sudo useradd --system --no-create-home --shell /usr/sbin/nologin '$USER_NAME'"
  ok "✅ System user '$USER_NAME' created."
fi

# 3) Add ticc-user to chrony group for socket access
log "🔐 Adding user to chrony group for chronyd socket access..."
# Detect chrony group name (may vary by distro)
CHRONY_GROUP=""
if getent group chrony >/dev/null 2>&1; then
  CHRONY_GROUP="chrony"
elif getent group _chrony >/dev/null 2>&1; then
  CHRONY_GROUP="_chrony"
fi

if [ -z "$CHRONY_GROUP" ]; then
  warn "⚠️  Warning: Could not find chrony group. chronyc may not work without sudo."
  warn "    Continuing installation, but you may need to manually configure access."
else
  # Check if user is already in group
  if groups "$USER_NAME" | grep -q "\b$CHRONY_GROUP\b"; then
    ok "✅ User '$USER_NAME' already in group '$CHRONY_GROUP'."
  else
    run "sudo usermod -a -G '$CHRONY_GROUP' '$USER_NAME'"
    ok "✅ User '$USER_NAME' added to group '$CHRONY_GROUP'."
    warn "⚠️  IMPORTANT: You must log out and back in (or run 'newgrp $CHRONY_GROUP') for group membership to take effect!"
  fi

  # Verify chronyd socket exists and has correct permissions
  if [ -S "/var/run/chrony/chronyd.sock" ] || [ -S "/run/chrony/chronyd.sock" ]; then
    ok "✅ chronyd socket detected."
  else
    warn "⚠️  Warning: chronyd socket not found. Ensure chronyd is running."
  fi
fi

# 4) Project dir
log "📁 Creating project directory at $APP_DIR..."
run "sudo mkdir -p '$APP_DIR/static/img'"
run "sudo chown -R '$USER_NAME':'$USER_NAME' '$APP_DIR'"
ok "✅ Project directory ready."

# 5) venv + Python deps
log "🐍 Setting up Python virtual environment..."
if [ ! -d "$VENV_DIR" ]; then
  run "sudo python3 -m venv '$VENV_DIR'"
  run "sudo chown -R '$USER_NAME':'$USER_NAME' '$VENV_DIR'"
fi
run "sudo -u '$USER_NAME' '$VENV_DIR/bin/pip' install --no-cache-dir --upgrade pip"
run "sudo -u '$USER_NAME' '$VENV_DIR/bin/pip' install --no-cache-dir flask gunicorn"
ok "✅ Virtual environment ready."

# 6) App + Logo
log "⬇️  Downloading application file..."
if [ -f "$APP_DIR/ticc-dash.py" ]; then
  warn "ℹ️  ticc-dash.py already exists, skipping download."
else
  run "sudo curl -fsSL '$REPO_RAW_PY' -o '$APP_DIR/ticc-dash.py'"
  run "sudo chown '$USER_NAME':'$USER_NAME' '$APP_DIR/ticc-dash.py'"
  ok "✅ ticc-dash.py downloaded."
fi

log "🎨 Downloading logo asset..."
if [ -f "$APP_DIR/static/img/ticc-dash-logo.png" ]; then
  warn "ℹ️  Logo already exists, skipping download."
else
  run "sudo curl -fsSL '$REPO_RAW_LOGO' -o '$APP_DIR/static/img/ticc-dash-logo.png'"
  run "sudo chown '$USER_NAME':'$USER_NAME' '$APP_DIR/static/img/ticc-dash-logo.png'"
  ok "✅ Logo downloaded to $APP_DIR/static/img/ticc-dash-logo.png"
fi

# 7) systemd service
log "⚙️  Creating systemd service..."
run "sudo bash -c 'cat > \"$SERVICE_FILE\" <<EOF
[Unit]
Description=$APP_NAME - Time Information of Chrony Clients Dashboard
After=network.target

[Service]
User=$USER_NAME
WorkingDirectory=$APP_DIR
ExecStart=$VENV_DIR/bin/gunicorn --bind 0.0.0.0:5000 ticc-dash:app
Restart=always
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF'"

run "sudo systemctl daemon-reload"
run "sudo systemctl enable '$SERVICE_NAME'"
run "sudo systemctl restart '$SERVICE_NAME'"
ok "✅ Service started successfully."

# 8) Summary
echo
echo "=========================================="
ok "🎉 Installation complete!"
echo
echo "📍 Directory:     $APP_DIR"
echo "📄 App file:      $APP_DIR/ticc-dash.py"
echo "🖼️  Logo:          $APP_DIR/static/img/ticc-dash-logo.png"
echo "🧠 App object:    ticc-dash:app"
echo "🧩 Service:       $SERVICE_NAME"
echo "👤 System user:   $USER_NAME"
echo
IP_ADDR="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo "🌐 Access via:    http://$IP_ADDR:5000/"
echo
echo "🔎 Manage service:"
echo "  • sudo systemctl status $SERVICE_NAME"
echo "  • sudo systemctl restart $SERVICE_NAME"
echo "  • sudo journalctl -u $SERVICE_NAME -f"
echo "=========================================="
