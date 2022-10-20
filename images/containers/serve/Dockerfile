FROM node:18-alpine

LABEL org.opencontainers.image.source=https://github.com/freecodecamp/infra
LABEL org.opencontainers.image.description="A vercel/serve container, for use as a base image for other containers."
LABEL org.opencontainers.image.licenses=BSD-3-Clause

RUN npm install -g --progress=false serve@14
WORKDIR /app
COPY serve.json .
EXPOSE 3000
CMD serve --config /app/serve.json --cors --no-clipboard --no-port-switching -p 3000 /dist
