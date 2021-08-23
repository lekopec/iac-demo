FROM node:14.15-alpine as build

WORKDIR '/app'

COPY package*.json ./

RUN npm ci --no-progress

COPY . .

EXPOSE 3000

CMD ["node", "index.js"]