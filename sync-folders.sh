#!/bin/bash

sync_directories() {
  if [ -z "${REMOTE_PASS}" ]; then
    rsync -avzq --delete --exclude-from="${EXCLUDE_FILE}" -e "ssh -p ${REMOTE_PORT}" "$LOCAL_DIR" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"
  else
    sshpass -p "${REMOTE_PASS}" rsync -avzq --delete --exclude-from="${EXCLUDE_FILE}" -e "ssh" "$LOCAL_DIR" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"
  fi
}

check_host() {
  nc -q0 -w1 -d "${REMOTE_HOST}" "${REMOTE_PORT}"

  if [ "$?" -ne 0 ]; then
    echo "Unable to reach remote host ${REMOTE_HOST} on port ${REMOTE_PORT}."
    exit 1
  fi
}

show_help() {
  cat <<- EOF
Usage: ssh-sync-folders [OPTIONS]

Options:
  -l, --local-dir=DIR           Local directory to be synced (default: current directory)
  -u, --remote-user=USER        Remote SSH user
  -p, --remote-pass=PASSWORD    Remote SSH password (optional)
  -h, --remote-host=HOST        Remote SSH host
  -o, --remote-port=port        Remote SSH port (default: 22)
  -d, --remote-dir=DIR          Remote directory to sync to (default: /shared)
  -e, --exclude=PATTERNS        Comma-separated list of file/folder patterns to exclude
  --help                        Show this help message and exit

EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -l|--local-dir=*)
      LOCAL_DIR="${1#*=}"
      shift
      ;;
    -u|--remote-user=*)
      REMOTE_USER="${1#*=}"
      shift
      ;;
    -p|--remote-pass=*)
      REMOTE_PASS="${1#*=}"
      shift
      ;;
    -h|--remote-host=*)
      REMOTE_HOST="${1#*=}"
      shift
      ;;
    -o|--remote-port=*)
      REMOTE_PORT="${1#*=}"
      shift
      ;;
    -d|--remote-dir=*)
      REMOTE_DIR="${1#*=}"
      shift
      ;;
    -e|--exclude=*)
      EXCLUDE_PATTERNS="${1#*=}"
      shift
      ;;
    --help)
      show_help
      exit 0
      ;;
    *)
      echo "Invalid option: ${1}. Run with --help for usage information." >&2
      exit 1
      ;;
  esac
  shift
done

LOCAL_DIR=${LOCAL_DIR:-${SSH_SYNC_LOCAL_DIR:-$PWD}}
REMOTE_USER=${REMOTE_USER:-${SSH_SYNC_REMOTE_USER}}
REMOTE_PASS=${REMOTE_PASS:-${SSH_SYNC_REMOTE_PASS}}
REMOTE_HOST=${REMOTE_HOST:-${SSH_SYNC_REMOTE_HOST}}
REMOTE_PORT=${REMOTE_PORT:-${SSH_SYNC_REMOTE_PORT:-22}}
REMOTE_DIR=${REMOTE_DIR:-${SSH_SYNC_REMOTE_DIR:-/ssh-sync}}

EXCLUDE_FILE=$(mktemp)
IFS=',' read -ra EXCLUDE_PATTERNS_ARRAY <<< "${EXCLUDE_PATTERNS:-${SSH_SYNC_EXCLUDE_PATTERNS}}"
for pattern in "${EXCLUDE_PATTERNS_ARRAY[@]}"; do
  echo "${pattern}" >> "${EXCLUDE_FILE}"
done

if [ -z "${LOCAL_DIR}" ] || [ -z "${REMOTE_USER}" ] || [ -z "${REMOTE_HOST}" ]; then
  echo "All arguments or environment variables (except remote directory, remote password, and exclude patterns) are required." >&2
  exit 1
fi

echo "Confirming remote host is reachable..."
check_host

echo "Running initial sync, local dir: ${LOCAL_DIR}; remote dir: ${REMOTE_DIR}"
sync_directories

if [ "$?" -ne 0 ]; then
  echo "Initial sync failed. Exiting."
  exit 1
fi

echo "Initial sync done."

while inotifywait -qr -e 'modify,create,delete,move' "${LOCAL_DIR}"; do
  sync_directories
done

rm "${EXCLUDE_FILE}"
