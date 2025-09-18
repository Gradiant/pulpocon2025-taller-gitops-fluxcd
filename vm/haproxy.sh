#!/usr/bin/env bash
set -euo pipefail

LISTEN_PORT="${LISTEN_PORT:-80}"
BACKEND_ADDR="${BACKEND_ADDR:-127.0.0.1}"
BACKEND_PORT="${BACKEND_PORT:-30080}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y haproxy
systemctl enable haproxy

cat > /etc/haproxy/haproxy.cfg <<EOF
global
    daemon
    maxconn 2048

defaults
    mode http
    option httplog
    option dontlognull
    timeout connect 5s
    timeout client  50s
    timeout server  50s

frontend http
    bind *:${LISTEN_PORT}
    mode http
    default_backend apisix_http

backend apisix_http
    mode http
    option http-keep-alive
    option forwardfor
    http-request set-header Host %[req.hdr(Host)]
    http-request set-header X-Forwarded-Host %[req.hdr(Host)]
    http-request set-header X-Forwarded-Proto http if !{ ssl_fc }
    server apisix ${BACKEND_ADDR}:${BACKEND_PORT} check
EOF

haproxy -c -V -f /etc/haproxy/haproxy.cfg
systemctl restart haproxy
