FROM registry.access.redhat.com/ubi9/ubi:latest

RUN dnf install -y jq python3-pip && \
    dnf clean all && \
    pip3 install --no-cache-dir azure-cli && \
    curl -sL https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz | tar xz -C /usr/local/bin && \
    chmod +x /usr/local/bin/rosa

ENTRYPOINT ["/bin/bash"]
