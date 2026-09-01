#!/bin/zsh

set -euo pipefail

readonly public_url="${1:?usage: ValidatePublicReleaseURL.sh https://public.example/path LABEL}"
readonly label="${2:?a short URL label is required}"

fail() {
  print -u2 -- "error: public release URL validation failed for ${label}: $1"
  exit 1
}

validate_url_and_resolution() {
  local candidate_url="$1"
  local observed_remote_ip="${2:-}"
  /usr/bin/python3 - "$candidate_url" "$observed_remote_ip" <<'PY'
import ipaddress
import re
import socket
import sys
import urllib.parse

url, observed_remote_ip = sys.argv[1:]
if any(character.isspace() for character in url):
    raise SystemExit("URL contains whitespace")
parsed = urllib.parse.urlsplit(url)
if parsed.scheme != "https":
    raise SystemExit("URL must use HTTPS")
if parsed.username is not None or parsed.password is not None:
    raise SystemExit("URL must not contain user information")
try:
    port = parsed.port
except ValueError as error:
    raise SystemExit(f"URL port is invalid: {error}")
if port is not None:
    raise SystemExit("URL must not contain an explicit port")
hostname = (parsed.hostname or "").lower()
if not re.fullmatch(r"(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?", hostname):
    raise SystemExit("URL must use a public DNS hostname")
if hostname == "localhost" or hostname.endswith((".local", ".internal", ".invalid", ".test", ".example")):
    raise SystemExit("URL uses a reserved or non-public hostname")

try:
    resolved = sorted({entry[4][0] for entry in socket.getaddrinfo(hostname, 443, type=socket.SOCK_STREAM)})
except OSError as error:
    raise SystemExit(f"public hostname did not resolve: {error}")
if not resolved:
    raise SystemExit("public hostname resolved to no addresses")
for address in resolved:
    if not ipaddress.ip_address(address).is_global:
        raise SystemExit(f"hostname resolved to non-public address {address}")
if observed_remote_ip:
    try:
        remote = ipaddress.ip_address(observed_remote_ip)
    except ValueError:
        raise SystemExit("curl did not report a valid remote IP address")
    if not remote.is_global:
        raise SystemExit(f"curl connected to non-public address {remote}")

print(f"host={hostname} resolved={','.join(resolved)}")
PY
}

initial_resolution="$(validate_url_and_resolution "$public_url")" \
  || fail "initial URL is not publicly resolvable"

readonly curl_receipt="$(/usr/bin/curl \
  --fail \
  --silent \
  --show-error \
  --location \
  --proto '=https' \
  --proto-redir '=https' \
  --connect-timeout 10 \
  --max-time 30 \
  --max-redirs 3 \
  --output /dev/null \
  --write-out $'%{http_code}\t%{url_effective}\t%{remote_ip}' \
  "$public_url")" || fail "HTTPS request did not complete successfully"

readonly http_code="${curl_receipt%%$'\t'*}"
readonly remainder="${curl_receipt#*$'\t'}"
[[ "$remainder" != "$curl_receipt" ]] || fail "curl receipt is malformed"
readonly final_url="${remainder%%$'\t'*}"
readonly remote_ip="${remainder#*$'\t'}"
[[ "$remote_ip" != "$remainder" && -n "$remote_ip" && "$http_code" == <200-299> ]] \
  || fail "curl did not return a successful, well-formed HTTPS receipt"
readonly final_resolution="$(validate_url_and_resolution "$final_url" "$remote_ip")" \
  || fail "final URL or connected address is not public"

print -- "PUBLIC_RELEASE_URL_VALIDATION: PASS"
print -- "label=${label} http=${http_code} initial_url=${public_url} final_url=${final_url} remote_ip=${remote_ip} initial_${initial_resolution} final_${final_resolution}"
