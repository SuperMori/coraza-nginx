ARG FEDORA_IMAGE=fedora:44@sha256:6c75d5bf57cb0fa5aa4b92c6a83c86c791644496d9ac230de7711f5b8ec3b898
FROM ${FEDORA_IMAGE}

RUN dnf -y --setopt=install_weak_deps=False install \
      autoconf \
      automake \
      binutils \
      ca-certificates \
      curl \
      file \
      findutils \
      gcc \
      gcc-c++ \
      golang \
      gzip \
      jq \
      libtool \
      make \
      openssl-devel \
      patch \
      pcre2-devel \
      perl \
      python3 \
      tar \
      unzip \
      which \
      zlib-ng-compat-devel \
    && dnf clean all
