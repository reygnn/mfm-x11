FROM debian:stable-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential pkg-config libx11-dev libxft-dev xvfb xdotool x11-xkb-utils \
    xkb-data fonts-dejavu-core procps util-linux imagemagick \
    && rm -rf /var/lib/apt/lists/*
# As root, permission checks would not fail where the test wants them to.
RUN useradd -m -u 1000 tester
USER tester
