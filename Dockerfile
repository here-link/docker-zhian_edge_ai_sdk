ARG BASE_IMAGE=ghcr.io/here-link/docker-zhian_edge_ai_sdk:base-BE3V120
FROM ${BASE_IMAGE}

LABEL maintainer="here.link" \
      org.opencontainers.image.title="zhian_edge_ai_sdk BE3V120 optimized" \
      org.opencontainers.image.description="Optimized wrapper for Zhian BE3V120 / ZF-BP3-X face feature extraction API" \
      org.opencontainers.image.source="https://github.com/here-link/docker-zhian_edge_ai_sdk"

WORKDIR /workspace

# BE3V120 already contains the new algorithm server at /workspace/doorlock_api.py.
# Do not copy the old /workspace/apiservice/doorapiserver.py, otherwise ZF-BP3-X
# support from the new vendor image will be overwritten.
COPY run.sh /workspace/run.sh
COPY api_app.py /workspace/api_app.py
COPY zhian_concurrency.py /workspace/zhian_concurrency.py
COPY auto-del-3-days-ago-image.sh /workspace/apiservice/auto-del-3-days-ago-image.sh

RUN test -f /workspace/doorlock_api.py \
    && chmod +x /workspace/run.sh /workspace/apiservice/auto-del-3-days-ago-image.sh \
    && mkdir -p /workspace/tmp

EXPOSE 8008

CMD ["/bin/bash", "/workspace/run.sh"]
