#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
case "${1:-status}" in
  start) docker compose up -d ;;
  stop) docker compose stop ;;
  restart) docker compose restart ;;
  status) docker compose ps ;;
  logs) shift; docker compose logs --tail=100 "$@" ;;
  verify) python3 scripts/verify.py ;;
  backup) python3 scripts/backup.py ;;
  *) echo '用法：scripts/manage.sh start|stop|restart|status|logs [服务名]|verify|backup'; exit 2 ;;
esac
