FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y bash curl git openssh-client openssl jq && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m certbotuser
USER certbotuser
WORKDIR /home/certbotuser

COPY ./ /home/certbotuser/cert-manager/
WORKDIR /home/certbotuser/cert-manager

RUN curl -sL https://get.acme.sh | sh -s email=certs@pund-it.ca

ENV PATH="$PATH:/home/certbotuser/.acme.sh"

CMD ["./scripts/full-renewal.sh"]
