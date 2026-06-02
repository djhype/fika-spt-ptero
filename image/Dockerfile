# Pterodactyl-compatible runtime image for SPT + Fika.
# Base: official .NET 9 ASP.NET runtime (correct OpenSSL 3 / ICU, required by SPT.Server.Linux).
# Adds: the tools startup.sh needs, a non-root 'container' user, and a Pterodactyl
#       entrypoint that evaluates the $STARTUP environment variable (the mechanism
#       Wings uses to launch a server).
FROM mcr.microsoft.com/dotnet/aspnet:9.0-bookworm-slim

RUN apt-get update -y \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      jq \
      7zip \
      unzip \
      tar \
      tzdata \
      iproute2 \
      libimage-exiftool-perl \
 && rm -rf /var/lib/apt/lists/*

# Pterodactyl runs game servers as a non-root user with HOME=/home/container
RUN useradd -m -d /home/container container

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

CMD ["/bin/bash", "/entrypoint.sh"]
