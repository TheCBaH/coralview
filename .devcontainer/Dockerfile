ARG VARIANT=13
FROM debian:${VARIANT}
# python3 runs the subsystem simulators' loader.
RUN set -eux;\
    apt-get update;\
    env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends\
  ca-certificates\
  curl\
  gcc\
  git\
  libc6-dev\
  make\
  python3\
;\
    apt-get autoremove -y; apt-get clean -y; rm -rf /var/lib/apt/lists/*;\
    echo DONE
# Coral NPU simulators from a devcontainer.coralnpu release, checked against the hashes
# committed in coralnpu.sha256. /opt/coralnpu/<archive> links to the host's architecture.
ARG CORAL_RELEASE=v0.0.4
COPY coralnpu.sha256 /tmp/coralnpu/
RUN set -eux;\
    arch=$(uname -m);\
    cd /tmp/coralnpu;\
    mkdir -p /opt/coralnpu;\
    for a in emulators subsystem; do\
      n=coralnpu-$a-linux-$arch;\
      curl -fsSLO https://github.com/TheCBaH/devcontainer.coralnpu/releases/download/$CORAL_RELEASE/$n.tar.gz;\
      grep " $n.tar.gz\$" coralnpu.sha256 | sha256sum -c;\
      tar -xzf $n.tar.gz -C /opt/coralnpu;\
      ln -s $n /opt/coralnpu/$a;\
    done;\
    echo $CORAL_RELEASE > /opt/coralnpu/RELEASE;\
    rm -rf /tmp/coralnpu
