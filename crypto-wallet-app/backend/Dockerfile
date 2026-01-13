## Builder for Rust binary
FROM rust:1.72-slim as builder
WORKDIR /usr/src/app
COPY ./rust/Cargo.toml ./rust/Cargo.toml
COPY ./rust/Cargo.lock ./rust/Cargo.lock
COPY ./rust/src ./rust/src
WORKDIR /usr/src/app/rust
RUN cargo build --release

## Node stage
FROM node:20-slim
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm install --production
COPY . .
## Copy Rust binary
COPY --from=builder /usr/src/app/rust/target/release/crypto_wallet_cli /usr/src/app/rust/target/release/crypto_wallet_cli
RUN chmod +x /usr/src/app/rust/target/release/crypto_wallet_cli || true

EXPOSE 3000
ENV NODE_ENV=production
CMD ["node", "server.js"]
