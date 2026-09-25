# `IMAGE` must stay declared before the FIRST `FROM` (global scope) so the IRIS
# stage below can still consume it; an ARG declared between two FROMs is
# scoped only to the stage that follows it, not to a later one.
ARG IMAGE=intersystemsdc/irishealth-community:2020.3.0.200.0-zpm
ARG IMAGE=intersystemsdc/iris-community:2020.4.0.547.0-zpm
ARG IMAGE=containers.intersystems.com/intersystems/iris:2021.1.0.215.0
ARG IMAGE=intersystemsdc/irishealth-community
ARG IMAGE=intersystemsdc/iris-community
ARG IMAGE=intersystemsdc/iris-community:preview
ARG IMAGE=intersystems/iris-community:latest-cd

# --- Frontend build stage -------------------------------------------------
# Builds the SvelteKit + Svelte Flow static bundle. This stage's Node runtime
# is discarded from the final image (specs/002-canvas-ui/research.md R-002) —
# only its `build/` output is copied into the IRIS stage below.
FROM node:20-alpine AS frontend-builder

WORKDIR /app

COPY frontend/package.json frontend/package-lock.json* ./
RUN npm ci

COPY frontend/ ./
# The token generator's single source of truth (see frontend/scripts/generate-tokens.mjs)
# lives outside frontend/ in the real repo; mirror that same relative position here so the
# generator's path resolution doesn't need a build-context-specific branch.
COPY specs/002-canvas-ui/contracts/tokens.json /specs/002-canvas-ui/contracts/tokens.json
RUN npm run build

# --- IRIS stage --------------------------------------------------------
FROM $IMAGE

WORKDIR /home/irisowner/dev

## install git
## USER root
##RUN apt update && apt-get -y install git
##USER ${ISC_PACKAGE_MGRUSER}

ARG TESTS=0
ARG MODULE="dc-sample"
ARG NAMESPACE="IRISAPP"

## Embedded Python environment
ENV IRISUSERNAME "_SYSTEM"
ENV IRISPASSWORD "SYS"
ENV IRISNAMESPACE $NAMESPACE
ENV PYTHON_PATH=/usr/irissys/bin/
ENV PATH "/usr/irissys/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/irisowner/bin"

COPY .iris_init /home/irisowner/.iris_init
RUN wget https://pm.community.intersystems.com/packages/zpm/latest/installer -O /tmp/zpm.xml

USER root
RUN mkdir -p /data/IRISAPP_DATA/ /data/IRISAPP_DATA/irisapp_dataenstemp /data/IRISAPP_DATA/irisapp_datasecondary && \
    chown irisowner:irisowner /data/ -R

# Demo/acceptance fixture for the FR-008 precondition: a directory IRIS cannot write to, so
# validation reports "Database mounted read-only" against a real instance, not a mock.
RUN mkdir -p /data/READONLY_DEMO && chmod 555 /data/READONLY_DEMO

# Static frontend assets, served by IRIS's own private web server as a CSP
# application with "Serve files" enabled (research.md R-001) — no Nginx, no
# second container. Placed OUTSIDE /home/irisowner/dev on purpose: that
# directory is bind-mounted over by docker-compose.yml for live ObjectScript
# development, which would otherwise shadow this baked-in build output for
# anyone who hasn't run `npm run build` on the host.
COPY --from=frontend-builder /app/build /opt/sentai-web
RUN chown -R irisowner:irisowner /opt/sentai-web
USER ${ISC_PACKAGE_MGRUSER}


RUN --mount=type=bind,src=.,dst=. \
    iris start IRIS && \
    iris merge iris ./merge.cpf && \
	iris session IRIS < iris.script && \
    ([ $TESTS -eq 0 ] || iris session iris -U $NAMESPACE "##class(%ZPM.PackageManager).Shell(\"test $MODULE -v -only\",1,1)") && \
    iris stop IRIS quietly
