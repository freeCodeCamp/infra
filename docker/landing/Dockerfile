FROM node:20-alpine

LABEL org.opencontainers.image.source=https://github.com/freecodecamp/infra
LABEL org.opencontainers.image.description="A quick landing page for the freeCodeCamp.org Docker containers."
LABEL org.opencontainers.image.licenses=BSD-3-Clause

RUN npm install -g --progress=false serve@14

ARG BUILD_LANGUAGE

WORKDIR /var/www/html/
COPY html .

WORKDIR /app
COPY serve.json .

EXPOSE 3000
CMD serve --config /app/serve.json --cors --no-clipboard --no-port-switching -p 3000 /var/www/html
