FROM ruby:3.3-slim
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libpq-dev \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY server.rb ./
CMD ["ruby", "--yjit", "server.rb"]
