#!/usr/bin/env bash
set -euo pipefail
LENGTH="${1:-64}"
TOKEN=$(openssl rand -base64 48 | tr -d "=+/" | cut -c1-"$LENGTH")
echo "ADMIN_TOKEN=$TOKEN"

if [[ -f ./settings.env ]]; then
  if grep -q "^ADMIN_TOKEN=" ./settings.env; then
    sed -i.bak_phase4 "s/^ADMIN_TOKEN=.*/ADMIN_TOKEN=$TOKEN/" ./settings.env
    echo "Updated ADMIN_TOKEN in settings.env"
  else
    echo "ADMIN_TOKEN=$TOKEN" >> ./settings.env
    echo "Added ADMIN_TOKEN to settings.env"
  fi
else
  echo "settings.env not found - paste the above line into your env file"
fi
