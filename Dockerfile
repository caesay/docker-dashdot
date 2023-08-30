# BASE #
FROM nvidia/cuda:12.2.0-base-ubuntu20.04 AS base
 
WORKDIR /app
ARG TARGETPLATFORM
ENV DASHDOT_RUNNING_IN_DOCKER=true
# ENV NVIDIA_VISIBLE_DEVICES=all
# ENV NVIDIA_DRIVER_CAPABILITIES="compute,video,utility"
ENV TZ=Europe/London
 
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
 
RUN \
  /bin/echo ">> installing dependencies" &&\
  apt-get update &&\
  apt-get install -y \
    wget \
    mdadm \
    dmidecode \
    util-linux \
    pciutils \
    curl \
    lm-sensors \
   speedtest-cli &&\
  if [ "$TARGETPLATFORM" = "linux/amd64" ] || [ "$(uname -m)" = "x86_64" ]; \
    then \
      /bin/echo ">> installing dependencies (amd64)" &&\
      wget -qO- https://install.speedtest.net/app/cli/ookla-speedtest-1.1.1-linux-x86_64.tgz \
        | tar xmoz -C /usr/bin speedtest; \
  elif [ "$TARGETPLATFORM" = "linux/arm64" ] || [ "$(uname -m)" = "aarch64" ]; \
    then \
      /bin/echo ">> installing dependencies (arm64)" &&\
      wget -qO- https://install.speedtest.net/app/cli/ookla-speedtest-1.1.1-linux-aarch64.tgz \
        | tar xmoz -C /usr/bin speedtest &&\
      apk --no-cache add raspberrypi; \
  elif [ "$TARGETPLATFORM" = "linux/arm/v7" ]; \
    then \
      /bin/echo ">> installing dependencies (arm/v7)" &&\
      wget -qO- https://install.speedtest.net/app/cli/ookla-speedtest-1.1.1-linux-armhf.tgz \
        | tar xmoz -C /usr/bin speedtest &&\
      apk --no-cache add raspberrypi; \
  else /bin/echo "Unsupported platform"; exit 1; \
  fi
 
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
RUN curl -sL https://deb.nodesource.com/setup_19.x | bash -
 
RUN \
  /bin/echo ">>installing yarn" &&\
  apt-get update &&\
  apt-get install -y \
  yarn
 
# DEV #
FROM base AS dev
 
EXPOSE 3001
EXPOSE 3000
 
RUN \
  /bin/echo -e ">> installing dependencies (dev)" &&\
  apt-get install -y \
    git &&\
  git config --global --add safe.directory /app
 
# BUILD #
FROM base as build
 
ARG BUILDHASH
ARG VERSION
 
RUN \
  /bin/echo -e ">> installing dependencies (build)" &&\
  apt-get install -y \
    git \
    make \
    clang \
    build-essential &&\
  git config --global --add safe.directory /app &&\
  /bin/echo -e "{\"version\":\"$VERSION\",\"buildhash\":\"$BUILDHASH\"}" > /app/version.json
 
RUN \
  /bin/echo -e ">> clean-up" &&\
  apt-get clean && \
  rm -rf \
    /tmp/* \
	/var/tmp/*
 
COPY . ./
 
RUN \
  yarn --immutable --immutable-cache &&\
  yarn build:prod
 
# PROD #
FROM base as prod
 
EXPOSE 3001
 
COPY --from=build /app/package.json .
COPY --from=build /app/version.json .
COPY --from=build /app/.yarn/releases/ .yarn/releases/
COPY --from=build /app/dist/apps/server dist/apps/server
COPY --from=build /app/dist/apps/cli dist/apps/cli
COPY --from=build /app/dist/apps/view dist/apps/view
 
CMD ["yarn", "start"]