FROM node:18-alpine
WORKDIR /app
COPY gitops-nodejs-app/package*.json ./
RUN npm install
COPY gitops-nodejs-app/server.js .
EXPOSE 3000
CMD ["node", "server.js"]