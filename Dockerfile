# install npm package
FROM node:10.14.2-alpine AS install-npm

RUN mkdir /app
WORKDIR /app

COPY package.json /app/package.json
COPY yarn.lock /app/yarn.lock
RUN yarn install

# install ruby gems
FROM ruby:2.6.3-alpine AS install-gem

RUN apk add --no-cache tzdata sqlite-dev && \
  cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime

RUN mkdir /app
WORKDIR /app

ARG BUNDLE_OPTIONS

COPY Gemfile /app/Gemfile
COPY Gemfile.lock /app/Gemfile.lock
RUN apk add --no-cache --virtual .rails-builddeps alpine-sdk && \
  bundle install -j4 --path vendor/bundle ${BUNDLE_OPTIONS} && \
  apk del .rails-builddeps

# build JavaScript for webpack
FROM node:10.14.2-alpine AS build-webpack

ENV NODE_ENV production

RUN mkdir /app
WORKDIR /app

COPY package.json /app/package.json
COPY yarn.lock /app/yarn.lock
COPY --from=install-npm /app/node_modules /app/node_modules

## webpack build
COPY ./app/javascript /app/app/javascript
COPY ./config/webpack /app/config/webpack
COPY ./config/webpacker.yml /app/config/webpacker.yml
COPY ./.browserslistrc /app/.browserslistrc
COPY ./babel.config.js /app/babel.config.js
COPY ./postcss.config.js /app/postcss.config.js
RUN yarn run webpack --config config/webpack/${NODE_ENV}.js

# build JavaScript for assets precompile
FROM ruby:2.6.3-alpine AS build-asset

RUN apk add --no-cache tzdata sqlite-dev && \
  cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime

ENV LANG C.UTF-8
ENV RAILS_ENV production
ENV WEBPACKER_PRECOMPILE=false

RUN mkdir /app
WORKDIR /app

ARG BUNDLE_OPTIONS

COPY Gemfile /app/Gemfile
COPY Gemfile.lock /app/Gemfile.lock
COPY --from=install-gem /app/vendor/bundle /app/vendor/bundle
RUN bundle install -j4 --path vendor/bundle ${BUNDLE_OPTIONS}

## asset build
COPY ./app/assets /app/app/assets
COPY ./config/environments /app/config/environments
COPY ./config/initializers/assets.rb /app/config/initializers/assets.rb
COPY ./config/application.rb /app/config/application.rb
COPY ./config/boot.rb /app/config/boot.rb
COPY ./config/cable.yml /app/config/cable.yml
COPY ./config/credentials.yml.enc /app/config/credentials.yml.enc
COPY ./config/database.yml /app/config/database.yml
COPY ./config/environment.rb /app/config/environment.rb
COPY ./config/master.key /app/config/master.key
COPY ./config/webpacker.yml /app/config/webpacker.yml
COPY ./lib /app/lib
COPY ./config.ru /app/config.ru
COPY ./Rakefile /app/Rakefile
RUN bundle exec rake assets:precompile

# exec docker image
FROM ruby:2.6.3-alpine

RUN apk add --no-cache tzdata sqlite-dev && \
  cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime

ENV LANG C.UTF-8
ENV RAILS_ENV production

RUN mkdir /app
WORKDIR /app

COPY Gemfile /app/Gemfile
COPY Gemfile.lock /app/Gemfile.lock
COPY --from=install-gem /app/vendor/bundle /app/vendor/bundle
RUN bundle install -j4 --path vendor/bundle ${BUNDLE_OPTIONS}

COPY --from=build-asset /app/public /app/public
COPY --from=build-webpack /app/public /app/public

COPY . /app

EXPOSE 3000
CMD ["bundle", "exec", "rails", "s", "-b", "0.0.0.0"]
