FROM node:16-alpine
RUN npm install -g --progress=false serve@13
WORKDIR /app
COPY serve.json .
EXPOSE 3000
CMD serve --config /app/serve.json --cors --no-clipboard --no-port-switching -p 3000 /dist
