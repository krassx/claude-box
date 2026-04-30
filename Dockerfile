FROM --platform=linux/arm64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    LANG=C.UTF-8 \
    JAVA_HOME=/usr/lib/jvm/default-java

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
        # Java 21 LTS (JDK = compiler + JRE + tools)
        openjdk-21-jdk maven gradle \
        # Diff / patch / misc
        diffutils patchutils bsdmainutils man-db manpages \
        # Container essentials
        sudo locales tzdata tini ca-certificates \
    && locale-gen en_US.UTF-8 \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat 2>/dev/null || true \
    # Architecture-agnostic JAVA_HOME symlink (works on amd64 and arm64).
    && ln -sf "$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")" /usr/lib/jvm/default-java \
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
    && chmod 0440 /etc/sudoers.d/${USERNAME}

COPY init-firewall.sh    /usr/local/bin/init-firewall.sh
COPY setup-host-claude.sh /usr/local/bin/setup-host-claude.sh
COPY entrypoint.sh       /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/init-firewall.sh \
             /usr/local/bin/setup-host-claude.sh \
             /usr/local/bin/entrypoint.sh

USER dev
WORKDIR /home/dev
RUN mkdir -p /home/dev/Projects /home/dev/.claude /home/dev/.config

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
