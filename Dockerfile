FROM swift:5.8-jammy as builder

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true && apt-get -q update && \
    apt-get install -y \
    libpq-dev \
    libpng-dev \
    libjpeg-dev \
    libjavascriptcoregtk-4.0-dev \
    libatomic1 \
    unzip

RUN rm -rf /var/lib/apt/lists/*


WORKDIR /root/Picaroon
COPY ./Makefile ./Makefile
COPY ./.build/repositories ./.build/repositories
COPY ./Package.resolved ./Package.resolved
COPY ./Package.swift ./Package.swift
COPY ./Sources ./Sources
COPY ./Tests ./Tests

RUN swift test
#RUN swift build --configuration release
