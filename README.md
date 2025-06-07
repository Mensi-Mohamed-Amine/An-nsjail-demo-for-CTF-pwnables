# 🛡️ An nsjail demo for CTF pwnables

I’ve put together a self-contained demo you can push to GitHub. In it, I walk through:

- How I install **nsjail** from source
- How I prepare my challenge and build a minimal chroot jail
- How I launch the jailed service
- How you can wrap it all in Docker for a fully repeatable environment

Feel free to swap in your own pwnables and tweak any paths or flags to fit your CTF setup!

–––

## 📁 Repository Layout

```
.
├── README.md
├── scripts
│   └── setup_jail.sh
└── challenges
    └── broken_shell               # Your vulnerable binary
```

---

## 🔧 1. Installing nsjail from Source

```bash
# 1. Install build dependencies
sudo apt update
sudo apt install -y build-essential cmake git libcap-dev libprotobuf-dev protobuf-compiler

# 2. Clone and build
git clone https://github.com/google/nsjail.git
cd nsjail
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j"$(nproc)"

# 3. Optionally install to /usr/local/bin
sudo make install
```

Now you should have `nsjail` available on your `$PATH`.

---

## 🛠 2. Preparing the Jail

Place your challenge binary under `challenges/`. In this demo it’s `broken_shell`.

### scripts/setup_jail.sh

```bash
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
```

Make it executable:

```bash
chmod +x scripts/setup_jail.sh
```

Run it:

```bash
./scripts/setup_jail.sh
```

---

## 🚀 3. Launching the Jailed Service

With your jail ready, start an interactive shell inside nsjail:

```bash
nsjail \
  --chroot "${HOME}/nsjail-demo/chroot" \
  --disable_clone_newnet \
  --mount_proc \
  --port 15027:15027 \
  --user 9999 --group 9999 \
  --exec "/usr/bin/sh"
```

Inside the jail shell:

```sh
cd /usr/bin
# start your broken_shell exploit service on TCP port 15027
nohup socat TCP-LISTEN:15027,reuseaddr,fork EXEC:./broken_shell \
     > /dev/null 2>&1 &
```

Now your CTF service is reachable on `localhost:15027` (or via your host’s IP if allowed).

---

## 🐳 4. Combining with Docker

To ensure full reproducibility and isolate your host from root-mount operations, wrap everything in Docker:

1. **Dockerfile** in your repo root:

   ```dockerfile
   FROM ubuntu:24.04
   RUN apt update && apt install -y \
       build-essential cmake git libcap-dev libprotobuf-dev protobuf-compiler socat procps iproute2
   COPY . /opt/nsjail-demo
   WORKDIR /opt/nsjail-demo
   RUN ./scripts/setup_jail.sh && \
       cd nsjail/build && make install
   CMD ["nsjail", "--chroot", "/opt/nsjail-demo/chroot",
        "--disable_clone_newnet", "--mount_proc",
        "--port", "15027:15027", "--user", "9999", "--group", "9999",
        "--exec", "/usr/bin/sh"]
   ```

2. **Build & Run**:

   ```bash
   docker build -t nsjail-demo:latest .
   docker run --rm -it -p 15027:15027 --cap-add=SYS_PTRACE nsjail-demo:latest
   ```

Inside the container you’ll get a shell in the jail; from there you can `cd /usr/bin` and launch your challenge the same way.

---

## 🎯 Summary

- **`setup_jail.sh`** automates creating a minimal chroot & copying binaries/libs.
- **nsjail** gives you lightweight, namespace-based jails.
- **Docker** adds a layer of reproducibility and host isolation.

Feel free to fork this repo, swap in your own pwnables, and adjust flags (UID/GID, network namespaces, seccomp filters) to tighten your CTF environment. Good luck!
