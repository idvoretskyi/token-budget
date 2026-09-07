FROM swift:6.3.3-noble@sha256:56ef1be2c1ca36f4c52440357dc1fcdfdb5e113587134fcadeef57c225c71b54

RUN apt-get update \
    && apt-get install -y --no-install-recommends libsqlite3-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
