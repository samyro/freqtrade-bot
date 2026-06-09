# Thin overlay on the official Freqtrade image: copy in our config + strategies.
# Secrets are NOT baked in — they're mounted at runtime from a k8s Secret.
FROM freqtradeorg/freqtrade:stable

USER root

# Build metadata for traceability.
ARG GIT_SHA=dev
ARG BUILD_TIME=unknown
ENV GIT_SHA=${GIT_SHA}
ENV BUILD_TIME=${BUILD_TIME}
LABEL org.opencontainers.image.source="https://github.com/your-org/quant-3rd-lib"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIME}"

# Overlay our config + strategies.
COPY --chown=ftuser:ftuser user_data/config.json /freqtrade/user_data/config.json
COPY --chown=ftuser:ftuser user_data/strategies/ /freqtrade/user_data/strategies/

# Pre-create db + logs dirs (PVC mount overlays these at runtime).
RUN mkdir -p /freqtrade/user_data/db /freqtrade/user_data/logs \
 && chown -R ftuser:ftuser /freqtrade/user_data

USER ftuser

# ENTRYPOINT is ["freqtrade"] from the base image. CMD provides the args.
# Two --config flags layer the secrets file (mounted from k8s Secret)
# on top of the baked-in config.json.
CMD ["trade", \
     "--config", "/freqtrade/user_data/config.json", \
     "--config", "/freqtrade/user_data/config.secrets.json", \
     "--strategy", "SampleStrategy"]
