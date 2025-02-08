ARG GO_IMAGE=rancher/hardened-build-base:v1.23.6b1
ARG BASE_IMAGE_MINIMAL=registry.suse.com/bci/bci-micro:latest

######
FROM ${GO_IMAGE} AS builder
# Build and install the grpc-health-probe binary
ENV GRPC_HEALTH_PROBE_VERSION=v0.4.18
ARG GHP_PKG="github.com/grpc-ecosystem/grpc-health-probe"
RUN git clone --depth=1 https://${GHP_PKG} $GOPATH/src/${GHP_PKG}
WORKDIR $GOPATH/src/${GHP_PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${GRPC_HEALTH_PROBE_VERSION} -b ${GRPC_HEALTH_PROBE_VERSION}        
RUN go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/ .
RUN go-assert-static.sh bin/*
RUN go-assert-boring.sh bin/*

# Build node feature discovery
ARG ARCH="amd64"
ARG TAG=v0.15.7
ARG PKG="github.com/kubernetes-sigs/node-feature-discovery"
RUN git clone --depth=1 https://${PKG}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
RUN go mod download

# Do actual build
ARG K8S_NAMESPACE=node-feature-discovery
ARG IMAGE_REGISTRY=rancher
RUN ./hack/kustomize.sh ${K8S_NAMESPACE} ${IMAGE_REGISTRY}/node-feature-discovery ${TAG}
ENV GO_LDFLAGS="-X sigs.k8s.io/node-feature-discovery/pkg/version.version=${TAG} -X sigs.k8s.io/node-feature-discovery/pkg/utils/hostpath.pathPrefix=/host-"
ENV GO111MODULE=on
RUN go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/ ./cmd/... 
RUN go-assert-static.sh bin/*
RUN go-assert-boring.sh bin/*

######
# Create minimal variant of the production image
FROM ${BASE_IMAGE_MINIMAL} AS minimal
# Run as unprivileged user
USER 65534:65534
# Use more verbose logging of gRPC
ENV GRPC_GO_LOG_SEVERITY_LEVEL="INFO"
ARG PKG="github.com/kubernetes-sigs/node-feature-discovery"
ARG GHP_PKG="github.com/grpc-ecosystem/grpc-health-probe"
COPY --from=builder /go/src/${PKG}/deployment/components/worker-config/nfd-worker.conf.example /etc/kubernetes/node-feature-discovery/nfd-worker.conf
COPY --from=builder /go/src/${PKG}/bin/* /usr/bin/
# Rename it as it's referenced as grpc_health_probe in the deployment yamls
# and in its own project https://github.com/grpc-ecosystem/grpc-health-probe
COPY --from=builder /go/src/${GHP_PKG}/bin/grpc-health-probe /usr/bin/grpc_health_probe
