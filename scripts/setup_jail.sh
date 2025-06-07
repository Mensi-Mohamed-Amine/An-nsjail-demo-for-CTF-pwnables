#!/usr/bin/env bash
set -euo pipefail

# General paths (customize as needed)
BASE_DIR="${HOME}/nsjail-demo"           # top-level demo directory
CHALLENGE_NAME="broken_shell"            # name of your binary
CHALLENGE_DIR="${BASE_DIR}/chroot"       # will become the jail root
BIN_DIR="/usr/bin"                       # inside the jail

# 0️⃣ Create directories
mkdir -p "${CHALLENGE_DIR}${BIN_DIR}"

# 1️⃣ Copy your binary into jail
cp "challenges/${CHALLENGE_NAME}" "${CHALLENGE_DIR}${BIN_DIR}/"

# 2️⃣ Copy all required commands + libs
COMMANDS=( "nohup" "cat" "socat" "ls" "clear" "sh" "nc" "bash" "${CHALLENGE_NAME}" )
for cmd in "${COMMANDS[@]}"; do
  cmd_path="$(which "${cmd}" 2>/dev/null || true)"
  if [[ -z "${cmd_path}" ]]; then
    echo "⚠️  ${cmd} not found on host; skipping."
    continue
  fi

  # create path inside jail and copy executable
  mkdir -p "${CHALLENGE_DIR}$(dirname "${cmd_path}")"
  cp "${cmd_path}" "${CHALLENGE_DIR}${cmd_path}"

  # copy all shared-object dependencies
  ldd "${cmd_path}" | awk '/\// {print $1}' | while read -r lib; do
    mkdir -p "${CHALLENGE_DIR}$(dirname "${lib}")"
    cp "${lib}" "${CHALLENGE_DIR}${lib}"
  done
done

# 3️⃣ Mount proc filesystem
sudo mkdir -p "${CHALLENGE_DIR}/proc"
sudo mount -t proc proc "${CHALLENGE_DIR}/proc"

# 4️⃣ Provide /dev/null for nohup
sudo mkdir -p "${CHALLENGE_DIR}/dev"
sudo mknod -m 666 "${CHALLENGE_DIR}/dev/null" c 1 3
sudo mount --bind /dev/null "${CHALLENGE_DIR}/dev/null"

echo "✅ Jail environment prepared at ${CHALLENGE_DIR}"