#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBESPRAY_DIR="$ROOT_DIR/state/kubespray"
VENV_DIR="$ROOT_DIR/state/venv"

if [[ -f "$ROOT_DIR/inventory.env" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT_DIR/inventory.env"
fi

KUBESPRAY_VERSION="${KUBESPRAY_VERSION:-v2.31.0}"

command -v git >/dev/null || { echo "git is required"; exit 1; }
mkdir -p "$ROOT_DIR/state"

if [[ ! -d "$KUBESPRAY_DIR/.git" ]]; then
  git clone --depth 1 --branch "$KUBESPRAY_VERSION" \
    https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_DIR"
else
  current_version="$(git -C "$KUBESPRAY_DIR" describe --tags --exact-match 2>/dev/null || true)"
  if [[ "$current_version" != "$KUBESPRAY_VERSION" ]]; then
    echo "Existing Kubespray checkout is ${current_version:-unversioned}; expected $KUBESPRAY_VERSION."
    echo "Remove state/kubespray and rerun this command to change versions."
    exit 1
  fi
fi

python_bin=""
for interpreter in python3.13 python3.12 python3.11 python3; do
  if command -v "$interpreter" >/dev/null 2>&1 && \
    "$interpreter" -c 'import sys; raise SystemExit(sys.version_info < (3, 11))'; then
    python_bin="$(command -v "$interpreter")"
    break
  fi
done

if [[ -n "$python_bin" ]]; then
  if [[ ! -x "$VENV_DIR/bin/python" ]] || \
    ! "$VENV_DIR/bin/python" -c 'import pip, sys; raise SystemExit(sys.version_info < (3, 11))'; then
    "$python_bin" -m venv --clear "$VENV_DIR"
  fi
elif command -v uv >/dev/null 2>&1; then
  uv python install 3.13
  if [[ ! -x "$VENV_DIR/bin/python" ]] || \
    ! "$VENV_DIR/bin/python" -c 'import pip, sys; raise SystemExit(sys.version_info < (3, 11))'; then
    uv venv --python 3.13 --clear --seed "$VENV_DIR"
  fi
else
  echo "Kubespray $KUBESPRAY_VERSION requires Python 3.11 or newer."
  echo "Install a current Python release or uv, then rerun make setup."
  exit 1
fi

"$VENV_DIR/bin/python" -m pip install --upgrade pip
"$VENV_DIR/bin/python" -m pip install -r "$KUBESPRAY_DIR/requirements.txt"

echo "Kubespray $KUBESPRAY_VERSION and its Python environment are ready."
