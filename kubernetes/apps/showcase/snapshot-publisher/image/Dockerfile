# The publisher's toolbox: kubectl to read, jq to transform, check-jsonschema
# to gate, git and ssh to push. Built by .github/workflows/publisher-image.yaml
# on merge to main and pushed to ghcr.io/pragalvaxfrez/snapshot-publisher.
# kubectl is pinned to the cluster's minor version.
FROM alpine:3.21

LABEL org.opencontainers.image.source="https://github.com/PragalvaXFREZ/lab"
LABEL org.opencontainers.image.description="devata snapshot publisher: kubectl, jq, git, ssh, check-jsonschema"

RUN apk add --no-cache git jq curl openssh-client python3 py3-pip \
 && pip install --break-system-packages --no-cache-dir check-jsonschema \
 && curl -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/v1.34.1/bin/linux/amd64/kubectl" \
 && chmod +x /usr/local/bin/kubectl
