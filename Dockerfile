FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    LANG=C.UTF-8 \
    JAVA_HOME=/usr/lib/jvm/default-java \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_NDK_HOME=/opt/android-sdk/ndk/28.2.13676358 \
    PATH=/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/emulator:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
        # Core / fetch
        ca-certificates curl wget gnupg gnupg2 openssl \
        # VCS
        git git-lfs openssh-client \
        # Build toolchain
        build-essential pkg-config make cmake autoconf automake libtool patch \
        # Editors
        vim nano \
        # Shells & multiplexers
        bash bash-completion zsh tmux screen \
        # Text processing / search
        gawk sed grep less jq yq ripgrep fd-find fzf tree file \
        # Process / system inspection
        procps psmisc htop lsof strace \
        # Archive tools
        tar gzip bzip2 xz-utils zip unzip zstd \
        # Networking
        iproute2 iptables ipset iputils-ping dnsutils \
        netcat-openbsd socat rsync \
        # Python (Node added separately below)
        python3 python3-pip python3-venv python3-dev python3-wheel \
        python-is-python3 pipx \
        # Java 17 (default, required by AGP / Android SDK) + Java 21 LTS, side by side.
        openjdk-17-jdk openjdk-21-jdk maven gradle \
        # Diff / patch / misc
        diffutils patchutils bsdmainutils man-db manpages \
        # Container essentials
        sudo locales tzdata tini ca-certificates \
    && locale-gen en_US.UTF-8 \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat 2>/dev/null || true \
    # Architecture-agnostic per-version symlinks (work on amd64 and arm64).
    # Switch with e.g. `export JAVA_HOME=/usr/lib/jvm/java-21 PATH=$JAVA_HOME/bin:$PATH`.
    && ln -sf "$(ls -d /usr/lib/jvm/java-17-openjdk-* | head -n1)" /usr/lib/jvm/java-17 \
    && ln -sf "$(ls -d /usr/lib/jvm/java-21-openjdk-* | head -n1)" /usr/lib/jvm/java-21 \
    # Default `java`/`javac` to JDK 17 (Android tooling); JDK 21 stays on disk.
    && update-alternatives --set java  /usr/lib/jvm/java-17/bin/java \
    && update-alternatives --set javac /usr/lib/jvm/java-17/bin/javac \
    && ln -sf /usr/lib/jvm/java-17 /usr/lib/jvm/default-java \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS via NodeSource + Claude Code CLI + corepack (pnpm/yarn shims).
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && corepack enable \
    && npm install -g @anthropic-ai/claude-code

# Bun, installed system-wide to /usr/local/bin so every user has it on PATH.
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash \
    && /usr/local/bin/bun --version

# uv = fast Python package/venv manager. Plays nicely with PEP 668.
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# ngrok agent — for exposing in-container dev servers via a public HTTPS URL.
# Auth via NGROK_AUTHTOKEN env var (passed through compose), no config file.
RUN curl -fsSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
        | gpg --dearmor -o /usr/share/keyrings/ngrok.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/ngrok.gpg] https://ngrok-agent.s3.amazonaws.com buster main" \
        > /etc/apt/sources.list.d/ngrok.list \
    && apt-get update && apt-get install -y --no-install-recommends ngrok \
    && rm -rf /var/lib/apt/lists/*

# Headless Chromium (arm64) via Playwright's prebuilt browser bundles.
# Exposed on PATH as `chrome` / `chromium` so tools like `claude --chrome` find it.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libnss3 libnspr4 libdbus-1-3 \
        libatk1.0-0t64 libatk-bridge2.0-0t64 libatspi2.0-0t64 \
        libcups2t64 libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 \
        libgbm1 libpango-1.0-0 libcairo2 libasound2t64 \
        libxshmfence1 libdrm2 fonts-liberation xdg-utils; \
    rm -rf /var/lib/apt/lists/*; \
    PLAYWRIGHT_BROWSERS_PATH=/opt/playwright \
        npx --yes playwright@latest install chromium; \
    chrome_bin="$(find /opt/playwright -maxdepth 4 -type f -path '*/chrome-linux/chrome' | head -n1)"; \
    [ -x "$chrome_bin" ] || { echo "Chromium binary not found under /opt/playwright" >&2; exit 1; }; \
    ln -sf "$chrome_bin" /usr/local/bin/chromium; \
    ln -sf "$chrome_bin" /usr/local/bin/chrome; \
    chmod -R a+rX /opt/playwright

ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright \
    PUPPETEER_EXECUTABLE_PATH=/usr/local/bin/chrome \
    CHROME_PATH=/usr/local/bin/chrome

# Android SDK: cmdline-tools + platforms 35 & 36, matching build-tools, NDK r28b.
# JDK 17 is required by the Android Gradle Plugin and by sdkmanager itself.
ARG ANDROID_CMDLINE_TOOLS_VERSION=11076708
ARG ANDROID_NDK_VERSION=28.2.13676358
ARG ANDROID_BUILD_TOOLS_35=35.0.1
ARG ANDROID_BUILD_TOOLS_36=36.0.0
RUN set -eux; \
    mkdir -p "${ANDROID_HOME}/cmdline-tools"; \
    curl -fsSL -o /tmp/cmdline-tools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip"; \
    unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_HOME}/cmdline-tools"; \
    mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest"; \
    rm /tmp/cmdline-tools.zip; \
    yes | "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null; \
    "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" \
        "platform-tools" \
        "platforms;android-35" \
        "platforms;android-36" \
        "build-tools;${ANDROID_BUILD_TOOLS_35}" \
        "build-tools;${ANDROID_BUILD_TOOLS_36}" \
        "ndk;${ANDROID_NDK_VERSION}"; \
    chmod -R a+rX "${ANDROID_HOME}"

ARG USERNAME=dev
ARG UID=1000
ARG GID=1000
# Ubuntu 24.04 ships with a default `ubuntu` user at UID/GID 1000 — remove
# it (and its group) before creating ours so the IDs are free.
RUN { id ubuntu >/dev/null 2>&1 && userdel -r ubuntu 2>/dev/null || true; } \
    && { getent group ubuntu >/dev/null 2>&1 && groupdel ubuntu 2>/dev/null || true; } \
    && groupadd -g ${GID} ${USERNAME} \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME} \
    && chown -R ${UID}:${GID} ${ANDROID_HOME}

COPY init-firewall.sh    /usr/local/bin/init-firewall.sh
COPY setup-host-claude.sh /usr/local/bin/setup-host-claude.sh
COPY entrypoint.sh       /usr/local/bin/entrypoint.sh
# Wrapper so plain `claude` runs with --dangerously-skip-permissions.
# Shadows /usr/bin/claude via PATH order (/usr/local/bin comes first).
COPY claude-wrapper.sh   /usr/local/bin/claude
RUN chmod +x /usr/local/bin/init-firewall.sh \
             /usr/local/bin/setup-host-claude.sh \
             /usr/local/bin/entrypoint.sh \
             /usr/local/bin/claude

USER dev
WORKDIR /home/dev
RUN mkdir -p /home/dev/Projects /home/dev/.claude /home/dev/.config

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
