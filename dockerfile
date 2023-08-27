FROM node:16-alpine as build
WORKDIR /usr/app
COPY /shoestop/. /usr/app
RUN npm install
COPY . .
RUN npm run build



FROM nginx:1.21-alpine
RUN rm /usr/share/nginx/html/index.html
WORKDIR /usr/share/nginx/html/
COPY --from=build /usr/app/build/ ./
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
