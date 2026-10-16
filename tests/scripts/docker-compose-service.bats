#!/usr/bin/env bats
# Tests for configuration/roles/docker_compose_service/ scripts and templates:
#   - files/homelab-compose-credential-sync.sh
#   - files/homelab-compose-notify.sh
#   - templates/homelab-compose-reconcile.sh.j2
#   - templates/homelab-docker-cleanup.sh.j2

load 'helpers/test_helper'

ROLE_DIR="${REPO_ROOT}/configuration/roles/docker_compose_service"
CRED_SYNC_SCRIPT="${ROLE_DIR}/files/homelab-compose-credential-sync.sh"
NOTIFY_SCRIPT="${ROLE_DIR}/files/homelab-compose-notify.sh"
RECONCILE_TEMPLATE="${ROLE_DIR}/templates/homelab-compose-reconcile.sh.j2"
CLEANUP_TEMPLATE="${ROLE_DIR}/templates/homelab-docker-cleanup.sh.j2"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

render_templates() {
  local allow_macvlan="${1:-false}"
  python3 -c 'import jinja2' 2>/dev/null || skip "python3 with jinja2 is required (run via mise exec)"

  mkdir -p \
    "${BATS_TMPDIR}/bin" \
    "${BATS_TMPDIR}/libexec" \
    "${BATS_TMPDIR}/etc/containers" \
    "${BATS_TMPDIR}/creds" \
    "${BATS_TMPDIR}/opt/containers/releases" \
    "${BATS_TMPDIR}/var/lib/homelab-compose" \
    "${BATS_TMPDIR}/mock_server"

  printf 'PUBLIC_KEY_STUB\n' > "${BATS_TMPDIR}/etc/containers/cosign.pub"
  printf 'APP_SECRET=synthetic_value\nVOLUME_BASE_DIRECTORY=/srv/data\n' > "${BATS_TMPDIR}/creds/homelab_compose_env"
  printf 'https://hc-ping.example.test/00000000-0000-0000-0000-000000000001' > "${BATS_TMPDIR}/creds/compose_healthchecks_ping_url"

  python3 - "${RECONCILE_TEMPLATE}" "${CLEANUP_TEMPLATE}" "${BATS_TMPDIR}" "${allow_macvlan}" <<'PY'
import sys
import jinja2

reconcile_tpl, cleanup_tpl, tmp, allow_macvlan_arg = sys.argv[1:5]
allow_macvlan = allow_macvlan_arg.lower() == "true"

ctx = {
    "docker_compose_service_base_dir": f"{tmp}/opt/containers",
    "docker_compose_service_state_dir": f"{tmp}/var/lib/homelab-compose",
    "docker_compose_service_libexec_dir": f"{tmp}/libexec",
    "docker_compose_service_cosign_bin": f"{tmp}/bin/cosign",
    "docker_compose_service_cosign_public_key_path": f"{tmp}/etc/containers/cosign.pub",
    "docker_compose_service_cosign_next_public_key_path": f"{tmp}/etc/containers/cosign-next.pub",
    "docker_compose_service_allow_macvlan": allow_macvlan,
    "docker_compose_service_curl_proto": "=https",
    "docker_compose_service_release_api_url": "https://api.example.test/repos/busybeaver/homelab-services/releases/latest",
    "docker_compose_service_target": "gcp",
    "docker_compose_service_project_name": "homelab",
    "docker_compose_service_wait_timeout": 180,
    "docker_compose_service_keep_releases": 3,
}

for src, dst in [(reconcile_tpl, f"{tmp}/reconcile.sh"), (cleanup_tpl, f"{tmp}/cleanup.sh")]:
    with open(src, encoding="utf-8") as handle:
        tpl = jinja2.Template(handle.read(), keep_trailing_newline=True)
    with open(dst, "w", encoding="utf-8") as handle:
        handle.write(tpl.render(**ctx))
PY
  chmod +x "${BATS_TMPDIR}/reconcile.sh" "${BATS_TMPDIR}/cleanup.sh"

  if [ -f "${NOTIFY_SCRIPT}" ]; then
    cp "${NOTIFY_SCRIPT}" "${BATS_TMPDIR}/libexec/homelab-compose-notify"
    chmod +x "${BATS_TMPDIR}/libexec/homelab-compose-notify"
  fi

  # Stub flock: runs the remaining command or acquires fd lock via real flock if present, else pass-through.
  cat > "${BATS_TMPDIR}/bin/flock" <<'SH'
#!/usr/bin/env bash
echo "flock $*" >> "${BATS_TMPDIR}/flock.log"
exit 0
SH

  # Stub cosign: checks STUB_COSIGN_RC or STUB_COSIGN_ACCEPT_KEY.
  cat > "${BATS_TMPDIR}/bin/cosign" <<'SH'
#!/usr/bin/env bash
echo "cosign $*" >> "${BATS_TMPDIR}/cosign.log"
key_arg=""
for ((i=1; i<=$#; i++)); do
  if [ "${!i}" = "--key" ]; then
    next=$((i + 1))
    key_arg="${!next}"
  fi
done
if [ -n "${STUB_COSIGN_ACCEPT_KEY:-}" ]; then
  if [ "${key_arg}" = "${STUB_COSIGN_ACCEPT_KEY}" ]; then
    exit 0
  fi
  exit 1
fi
exit "${STUB_COSIGN_RC:-0}"
SH

  # Stub curl: serves mock release metadata and assets, or records Healthchecks --config - stdin.
  cat > "${BATS_TMPDIR}/bin/curl" <<'SH'
#!/usr/bin/env bash
echo "curl $*" >> "${BATS_TMPDIR}/curl.argv.log"
out_file=""
use_stdin_config=false
url=""
for ((i=1; i<=$#; i++)); do
  arg="${!i}"
  case "${arg}" in
    -o)
      next=$((i + 1))
      out_file="${!next}"
      i="${next}"
      ;;
    --config)
      next=$((i + 1))
      if [ "${!next}" = "-" ]; then
        use_stdin_config=true
      fi
      i="${next}"
      ;;
    https://*|http://*)
      url="${arg}"
      ;;
  esac
done

if [ "${use_stdin_config}" = "true" ]; then
  stdin_cfg="$(cat)"
  echo "${stdin_cfg}" >> "${BATS_TMPDIR}/curl.stdin.log"
  exit "${STUB_NOTIFY_CURL_RC:-0}"
fi

if [ "${STUB_CURL_RC:-0}" -ne 0 ]; then
  exit "${STUB_CURL_RC}"
fi

case "${url}" in
  */releases/latest)
    cat "${BATS_TMPDIR}/mock_server/latest.json"
    ;;
  https://assets.example.test/*)
    asset_name="${url##*/}"
    if [ ! -f "${BATS_TMPDIR}/mock_server/${asset_name}" ]; then
      exit 22
    fi
    if [ -n "${out_file}" ]; then
      cp "${BATS_TMPDIR}/mock_server/${asset_name}" "${out_file}"
    else
      cat "${BATS_TMPDIR}/mock_server/${asset_name}"
    fi
    ;;
  *)
    exit 22
    ;;
esac
SH

  # Stub docker: handles `docker compose ...` and cleanup subcommands (`ps`, `create`, `rm`, `container`, `image`, `network`, `builder`, `volume`).
  cat > "${BATS_TMPDIR}/bin/docker" <<'SH'
#!/usr/bin/env bash
echo "docker $*" >> "${BATS_TMPDIR}/docker.log"

if [ "${1:-}" = "compose" ]; then
  shift
  compose_file=""
  project_name=""
  env_file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -f|--file) compose_file="$2"; shift 2 ;;
      --project-name|-p) project_name="$2"; shift 2 ;;
      --env-file) env_file="$2"; shift 2 ;;
      config|pull|up|ps|logs)
        subcmd="$1"
        shift
        break
        ;;
      *) shift ;;
    esac
  done

  case "${subcmd:-}" in
    config)
      if [[ " $* " == *" --services "* ]]; then
        if [ -n "${STUB_SERVICES_OUT:-}" ]; then
          printf '%s\n' "${STUB_SERVICES_OUT}"
        else
          printf 'web\nworker\n'
        fi
        exit 0
      fi
      if [[ " $* " == *" --images "* ]]; then
        if [[ "${compose_file}" == *"v2026.10.16-1"* ]]; then
          printf 'ghcr.io/example/web:v1@sha256:1111111111111111111111111111111111111111111111111111111111111111\n'
        else
          printf 'ghcr.io/example/web:v2@sha256:2222222222222222222222222222222222222222222222222222222222222222\n'
        fi
        exit 0
      fi
      if [[ " $* " == *" --variables "* ]]; then
        if [ -n "${STUB_VARIABLES_JSON:-}" ]; then
          printf '%s\n' "${STUB_VARIABLES_JSON}"
        else
          cat <<'JSON'
{
  "APP_SECRET": {"Name": "APP_SECRET", "DefaultValue": "", "PresenceValue": ""},
  "OPTIONAL_VAR": {"Name": "OPTIONAL_VAR", "DefaultValue": "default_val", "PresenceValue": ""}
}
JSON
        fi
        exit 0
      fi
      if [[ " $* " == *" --format json "* ]]; then
        if [ -n "${STUB_CONFIG_JSON:-}" ]; then
          printf '%s\n' "${STUB_CONFIG_JSON}"
        else
          cat <<'JSON'
{
  "services": {
    "web": {
      "image": "ghcr.io/example/web:v1@sha256:1111111111111111111111111111111111111111111111111111111111111111",
      "volumes": [
        {"type": "bind", "source": "/srv/data/web", "target": "/data"}
      ]
    },
    "worker": {
      "image": "ghcr.io/example/worker:v1@sha256:2222222222222222222222222222222222222222222222222222222222222222"
    }
  },
  "networks": {
    "default": {"driver": "bridge"}
  }
}
JSON
        fi
        exit 0
      fi
      if [[ " $* " == *" -q "* ]]; then
        exit "${STUB_CONFIG_Q_RC:-0}"
      fi
      exit 0
      ;;
    pull)
      exit "${STUB_PULL_RC:-0}"
      ;;
    up)
      echo "up project=${project_name} file=${compose_file} args=$*" >> "${BATS_TMPDIR}/docker_up.log"
      if [ -n "${STUB_FAIL_UP_FOR_TAG:-}" ] && [[ "${compose_file}" == *"${STUB_FAIL_UP_FOR_TAG}"* ]]; then
        exit 1
      fi
      exit "${STUB_UP_RC:-0}"
      ;;
    ps)
      if [ -n "${STUB_FAIL_PS_FOR_TAG:-}" ] && [[ "${compose_file}" == *"${STUB_FAIL_PS_FOR_TAG}"* ]]; then
        cat <<'JSON'
[{"Service":"web","State":"running","Health":"unhealthy","ExitCode":0,"Labels":""},{"Service":"worker","State":"running","Health":"healthy","ExitCode":0,"Labels":""}]
JSON
        exit 0
      fi
      if [ -n "${STUB_PS_JSON:-}" ]; then
        printf '%s\n' "${STUB_PS_JSON}"
        exit 0
      fi
      cat <<'JSON'
[{"Service":"web","State":"running","Health":"healthy","ExitCode":0,"Labels":""},{"Service":"worker","State":"running","Health":"","ExitCode":0,"Labels":""}]
JSON
      exit 0
      ;;
    logs)
      echo "container logs tail"
      exit 0
      ;;
  esac
  exit 0
fi

case "${1:-}" in
  ps)
    if [[ " $* " == *"homelab.compose.hold=true"* ]]; then
      if [ -f "${BATS_TMPDIR}/stale_holds.txt" ]; then
        cat "${BATS_TMPDIR}/stale_holds.txt"
        rm -f "${BATS_TMPDIR}/stale_holds.txt"
      fi
    fi
    exit 0
    ;;
  create)
    echo "create $*" >> "${BATS_TMPDIR}/docker_holds.log"
    if [ -n "${STUB_MISSING_IMAGE:-}" ] && [[ " $* " == *"${STUB_MISSING_IMAGE}"* ]]; then
      echo "Error: No such image" >&2
      exit 1
    fi
    for arg in "$@"; do
      if [[ "${arg}" == homelab-hold-* ]]; then
        echo "${arg}" >> "${BATS_TMPDIR}/active_holds.txt"
      fi
    done
    exit 0
    ;;
  rm)
    echo "rm $*" >> "${BATS_TMPDIR}/docker_holds.log"
    exit 0
    ;;
  container|network|builder)
    echo "$*" >> "${BATS_TMPDIR}/docker_prune.log"
    exit 0
    ;;
  image)
    echo "$*" >> "${BATS_TMPDIR}/docker_prune.log"
    exit "${STUB_IMAGE_PRUNE_RC:-0}"
    ;;
  volume)
    echo "FORBIDDEN: docker volume $*" >> "${BATS_TMPDIR}/docker_volume_forbidden.log"
    exit 99
    ;;
esac
exit 0
SH

  chmod +x "${BATS_TMPDIR}/bin/flock" "${BATS_TMPDIR}/bin/cosign" "${BATS_TMPDIR}/bin/curl" "${BATS_TMPDIR}/bin/docker"
}

prepare_mock_release() {
  local tag="${1:-v2026.10.16-1}"
  local target="${2:-gcp}"
  local content="${3:-services: {web: {image: 'ghcr.io/example/web:v1@sha256:1111111111111111111111111111111111111111111111111111111111111111'}}}"
  local release_file_content="${4:-${tag}}"

  mkdir -p "${BATS_TMPDIR}/mock_server"
  printf '%s\n' "${release_file_content}" > "${BATS_TMPDIR}/mock_server/RELEASE"
  printf '%s\n' "${content}" > "${BATS_TMPDIR}/mock_server/docker-compose.${target}.yaml"
  printf 'services: {}\n' > "${BATS_TMPDIR}/mock_server/docker-compose.homelab.yaml"
  (
    cd "${BATS_TMPDIR}/mock_server"
    LC_ALL=C sha256sum RELEASE "docker-compose.${target}.yaml" docker-compose.homelab.yaml | LC_ALL=C sort -k2 > SHA256SUMS
  )
  printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}\n' > "${BATS_TMPDIR}/mock_server/SHA256SUMS.sigstore.json"

  cat > "${BATS_TMPDIR}/mock_server/latest.json" <<JSON
{
  "tag_name": "${tag}",
  "assets": [
    {"name": "RELEASE", "browser_download_url": "https://assets.example.test/RELEASE"},
    {"name": "SHA256SUMS", "browser_download_url": "https://assets.example.test/SHA256SUMS"},
    {"name": "SHA256SUMS.sigstore.json", "browser_download_url": "https://assets.example.test/SHA256SUMS.sigstore.json"},
    {"name": "docker-compose.${target}.yaml", "browser_download_url": "https://assets.example.test/docker-compose.${target}.yaml"},
    {"name": "docker-compose.homelab.yaml", "browser_download_url": "https://assets.example.test/docker-compose.homelab.yaml"}
  ]
}
JSON
}

run_reconcile() {
  run env \
    PATH="${BATS_TMPDIR}/bin:${PATH}" \
    CREDENTIALS_DIRECTORY="${BATS_TMPDIR}/creds" \
    COMPOSE_RELEASE_API_URL="https://api.example.test/repos/busybeaver/homelab-services/releases/latest" \
    COMPOSE_TARGET="${COMPOSE_TARGET:-gcp}" \
    COMPOSE_PROJECT_NAME="homelab" \
    COMPOSE_WAIT_TIMEOUT="180" \
    KEEP_RELEASES="3" \
    bash "${BATS_TMPDIR}/reconcile.sh"
}

run_cleanup() {
  run env \
    PATH="${BATS_TMPDIR}/bin:${PATH}" \
    CREDENTIALS_DIRECTORY="${BATS_TMPDIR}/creds" \
    COMPOSE_PROJECT_NAME="homelab" \
    bash "${BATS_TMPDIR}/cleanup.sh"
}

@test "helper scripts and rendered templates pass bash -n and shellcheck" {
  render_templates
  for f in "${CRED_SYNC_SCRIPT}" "${NOTIFY_SCRIPT}" "${BATS_TMPDIR}/reconcile.sh" "${BATS_TMPDIR}/cleanup.sh"; do
    [ -f "${f}" ]
    run bash -n "${f}"
    [ "$status" -eq 0 ]
    if command -v shellcheck >/dev/null 2>&1; then
      run shellcheck -s bash "${f}"
      [ "$status" -eq 0 ]
    fi
  done
}

@test "homelab-compose-notify sends heartbeat via curl --config - without leaking URL in argv" {
  render_templates
  run env \
    PATH="${BATS_TMPDIR}/bin:${PATH}" \
    CREDENTIALS_DIRECTORY="${BATS_TMPDIR}/creds" \
    bash "${NOTIFY_SCRIPT}" success homelab-compose-reconcile.service
  [ "$status" -eq 0 ]
  run grep -F "hc-ping.example.test" "${BATS_TMPDIR}/curl.argv.log"
  [ "$status" -eq 1 ]
  run grep -F 'url = "https://hc-ping.example.test/00000000-0000-0000-0000-000000000001"' "${BATS_TMPDIR}/curl.stdin.log"
  [ "$status" -eq 0 ]
}

@test "homelab-compose-notify sends /fail and handles missing sentinel per STD-AN-58" {
  render_templates
  run env \
    PATH="${BATS_TMPDIR}/bin:${PATH}" \
    CREDENTIALS_DIRECTORY="${BATS_TMPDIR}/creds" \
    bash "${NOTIFY_SCRIPT}" fail homelab-compose-reconcile.service
  [ "$status" -eq 0 ]
  run grep -F 'url = "https://hc-ping.example.test/00000000-0000-0000-0000-000000000001/fail"' "${BATS_TMPDIR}/curl.stdin.log"
  [ "$status" -eq 0 ]

  printf 'missing' > "${BATS_TMPDIR}/creds/compose_healthchecks_ping_url"
  run env \
    PATH="${BATS_TMPDIR}/bin:${PATH}" \
    CREDENTIALS_DIRECTORY="${BATS_TMPDIR}/creds" \
    bash "${NOTIFY_SCRIPT}" fail homelab-compose-reconcile.service
  [ "$status" -eq 1 ]

  run env \
    PATH="${BATS_TMPDIR}/bin:${PATH}" \
    CREDENTIALS_DIRECTORY="${BATS_TMPDIR}/creds" \
    bash "${NOTIFY_SCRIPT}" success homelab-compose-reconcile.service
  [ "$status" -eq 0 ]
}

@test "homelab-compose-credential-sync validates inputs and syncs idempotently without echoing secrets" {
  mkdir -p "${BATS_TMPDIR}/bin" "${BATS_TMPDIR}/credstore"
  cat > "${BATS_TMPDIR}/bin/systemd-creds" <<'SH'
#!/usr/bin/env bash
case "$1" in
  encrypt)
    cat > "$5"
    ;;
  decrypt)
    cat "$2"
    ;;
esac
SH
  chmod +x "${BATS_TMPDIR}/bin/systemd-creds"

  run env PATH="${BATS_TMPDIR}/bin:${PATH}" bash "${CRED_SYNC_SCRIPT}" "bad-name!" "${BATS_TMPDIR}/credstore"
  [ "$status" -eq 2 ]

  run env PATH="${BATS_TMPDIR}/bin:${PATH}" bash "${CRED_SYNC_SCRIPT}" "homelab_compose_env" "${BATS_TMPDIR}/credstore" <<<""
  [ "$status" -eq 2 ]

  run bash -c "printf 'SECRET_TOKEN=topsecret' | PATH='${BATS_TMPDIR}/bin:${PATH}' bash '${CRED_SYNC_SCRIPT}' homelab_compose_env '${BATS_TMPDIR}/credstore' host"
  [ "$status" -eq 0 ]
  [ "$output" = "changed" ]

  run bash -c "printf 'SECRET_TOKEN=topsecret' | PATH='${BATS_TMPDIR}/bin:${PATH}' bash '${CRED_SYNC_SCRIPT}' homelab_compose_env '${BATS_TMPDIR}/credstore' host"
  [ "$status" -eq 0 ]
  [ "$output" = "unchanged" ]
}

@test "reconcile: first deploy verifies bundle, deploys stack, sets current symlink without previous, and sends heartbeat" {
  render_templates
  prepare_mock_release "v2026.10.16-1" "gcp"
  run_reconcile
  [ "$status" -eq 0 ]
  [ -L "${BATS_TMPDIR}/opt/containers/current" ]
  [ ! -e "${BATS_TMPDIR}/opt/containers/previous" ]
  [ "$(readlink "${BATS_TMPDIR}/opt/containers/current")" = "${BATS_TMPDIR}/opt/containers/releases/v2026.10.16-1" ]
  [ ! -e "${BATS_TMPDIR}/var/lib/homelab-compose/deploying" ]
  run grep -F "up project=homelab" "${BATS_TMPDIR}/docker_up.log"
  [ "$status" -eq 0 ]
  run grep -F 'url = "https://hc-ping.example.test/00000000-0000-0000-0000-000000000001"' "${BATS_TMPDIR}/curl.stdin.log"
  [ "$status" -eq 0 ]
}

@test "reconcile: upgrade deploy rotates previous=v1, current=v2 and prunes old releases keeping current and previous" {
  render_templates
  prepare_mock_release "v2026.10.16-1" "gcp" "services: {web: {image: 'v1'}}"
  run_reconcile
  [ "$status" -eq 0 ]

  prepare_mock_release "v2026.10.16-2" "gcp" "services: {web: {image: 'v2'}}"
  run_reconcile
  [ "$status" -eq 0 ]
  [ "$(readlink "${BATS_TMPDIR}/opt/containers/previous")" = "${BATS_TMPDIR}/opt/containers/releases/v2026.10.16-1" ]
  [ "$(readlink "${BATS_TMPDIR}/opt/containers/current")" = "${BATS_TMPDIR}/opt/containers/releases/v2026.10.16-2" ]

  prepare_mock_release "v2026.10.16-3" "gcp" "services: {web: {image: 'v3'}}"
  run_reconcile
  [ "$status" -eq 0 ]
  prepare_mock_release "v2026.10.16-4" "gcp" "services: {web: {image: 'v4'}}"
  run_reconcile
  [ "$status" -eq 0 ]
  # KEEP_RELEASES=3: v1 should be pruned, v2, v3, v4 kept
  [ ! -d "${BATS_TMPDIR}/opt/containers/releases/v2026.10.16-1" ]
  [ -d "${BATS_TMPDIR}/opt/containers/releases/v2026.10.16-2" ]
  [ -d "${BATS_TMPDIR}/opt/containers/releases/v2026.10.16-3" ]
  [ -d "${BATS_TMPDIR}/opt/containers/releases/v2026.10.16-4" ]
}

@test "reconcile: rejects tampered cosign bundle and falls back to cosign-next.pub during key rotation" {
  render_templates
  prepare_mock_release "v2026.10.16-1" "gcp"
  STUB_COSIGN_RC=1 run_reconcile
  [ "$status" -ne 0 ]
  [ ! -e "${BATS_TMPDIR}/opt/containers/current" ]
  [ ! -e "${BATS_TMPDIR}/docker_up.log" ]
  [ ! -e "${BATS_TMPDIR}/var/lib/homelab-compose/quarantined-release" ]

  # With cosign-next.pub present, fallback succeeds
  printf 'NEXT_PUBLIC_KEY\n' > "${BATS_TMPDIR}/etc/containers/cosign-next.pub"
  STUB_COSIGN_ACCEPT_KEY="${BATS_TMPDIR}/etc/containers/cosign-next.pub" run_reconcile
  [ "$status" -eq 0 ]
  [ -L "${BATS_TMPDIR}/opt/containers/current" ]
}

@test "reconcile: rejects RELEASE mismatch, downgrade tag, malformed tag, missing target line, and checksum mismatch" {
  render_templates
  prepare_mock_release "v2026.10.16-2" "gcp" "services: {web: {image: 'v2'}}"
  run_reconcile
  [ "$status" -eq 0 ]
  rm -f "${BATS_TMPDIR}/docker_up.log"

  # 1. RELEASE != tag
  prepare_mock_release "v2026.10.16-3" "gcp" "services: {web: {image: 'v3'}}" "v2026.10.16-99"
  run_reconcile
  [ "$status" -ne 0 ]
  [ "$(readlink "${BATS_TMPDIR}/opt/containers/current")" = "${BATS_TMPDIR}/opt/containers/releases/v2026.10.16-2" ]
  [ ! -e "${BATS_TMPDIR}/docker_up.log" ]

  # 2. Downgrade tag (v2026.10.16-1 < v2026.10.16-2)
  prepare_mock_release "v2026.10.16-1" "gcp" "services: {web: {image: 'v1'}}"
  run_reconcile
  [ "$status" -ne 0 ]
  [ "$(readlink "${BATS_TMPDIR}/opt/containers/current")" = "${BATS_TMPDIR}/opt/containers/releases/v2026.10.16-2" ]
  [ ! -e "${BATS_TMPDIR}/docker_up.log" ]

  # 3. Malformed tag (path traversal)
  prepare_mock_release "../evil" "gcp"
  run_reconcile
  [ "$status" -ne 0 ]
  [ ! -e "${BATS_TMPDIR}/docker_up.log" ]

  # 4. Missing target line in SHA256SUMS
  prepare_mock_release "v2026.10.16-4" "gcp" "services: {web: {image: 'v4'}}"
  grep -v "docker-compose.gcp.yaml" "${BATS_TMPDIR}/mock_server/SHA256SUMS" > "${BATS_TMPDIR}/mock_server/SHA256SUMS.tmp"
  mv "${BATS_TMPDIR}/mock_server/SHA256SUMS.tmp" "${BATS_TMPDIR}/mock_server/SHA256SUMS"
  run_reconcile
  [ "$status" -ne 0 ]
  [ ! -e "${BATS_TMPDIR}/docker_up.log" ]

  # 5. Checksum mismatch
  prepare_mock_release "v2026.10.16-5" "gcp" "services: {web: {image: 'v5'}}"
  printf 'tampered\n' >> "${BATS_TMPDIR}/mock_server/docker-compose.gcp.yaml"
  run_reconcile
  [ "$status" -ne 0 ]
  [ ! -e "${BATS_TMPDIR}/docker_up.log" ]
}

@test "reconcile: rejects build:, relative bind mounts, macvlan when disallowed, missing required variable, pull failure, and API 404" {
  render_templates "false"
  prepare_mock_release "v2026.10.16-1" "gcp"

  # 1. build: present
  STUB_CONFIG_JSON='{"services":{"web":{"build":{"context":"."},"image":"ghcr.io/example/web@sha256:1111111111111111111111111111111111111111111111111111111111111111"}}}' \
    run_reconcile
  [ "$status" -ne 0 ]
  [ ! -e "${BATS_TMPDIR}/docker_up.log" ]

  # 2. relative bind mount
  STUB_CONFIG_JSON='{"services":{"web":{"image":"ghcr.io/example/web@sha256:1111111111111111111111111111111111111111111111111111111111111111","volumes":[{"type":"bind","source":"./local","target":"/data"}]}}}' \
    run_reconcile
  [ "$status" -ne 0 ]
  [ ! -e "${BATS_TMPDIR}/docker_up.log" ]

  # 3. macvlan network driver when allow_macvlan=false
  macvlan_json='{"services":{"web":{"image":"ghcr.io/example/web@sha256:1111111111111111111111111111111111111111111111111111111111111111","mac_address":"02:42:ac:11:00:02"}},"networks":{"lan":{"driver":"macvlan"}}}'
  STUB_CONFIG_JSON="${macvlan_json}" run_reconcile
  [ "$status" -ne 0 ]
  [ ! -e "${BATS_TMPDIR}/docker_up.log" ]

  # 4. Missing required variable (no default in config --variables, absent from homelab_compose_env)
  STUB_VARIABLES_JSON='{"MISSING_SECRET":{"Name":"MISSING_SECRET","DefaultValue":"","PresenceValue":""}}' \
    run_reconcile
  [ "$status" -ne 0 ]
  [ ! -e "${BATS_TMPDIR}/docker_up.log" ]

  # 5. Pull failure -> transient failure (exit 1, no quarantine)
  STUB_PULL_RC=1 run_reconcile
  [ "$status" -ne 0 ]
  [ ! -e "${BATS_TMPDIR}/var/lib/homelab-compose/quarantined-release" ]

  # 6. API 404
  STUB_CURL_RC=22 run_reconcile
  [ "$status" -ne 0 ]

  # 7. macvlan accepted when allow_macvlan=true
  render_templates "true"
  prepare_mock_release "v2026.10.16-1" "gcp"
  STUB_CONFIG_JSON="${macvlan_json}" run_reconcile
  [ "$status" -eq 0 ]
}

@test "reconcile: unchanged-manifest fast path skips pull and up, updates current, and preserves previous" {
  render_templates
  prepare_mock_release "v2026.10.16-1" "gcp" "services: {web: {image: 'v1'}}"
  run_reconcile
  [ "$status" -eq 0 ]

  prepare_mock_release "v2026.10.16-2" "gcp" "services: {web: {image: 'v2'}}"
  run_reconcile
  [ "$status" -eq 0 ]
  [ "$(readlink "${BATS_TMPDIR}/opt/containers/previous")" = "${BATS_TMPDIR}/opt/containers/releases/v2026.10.16-1" ]
  [ "$(readlink "${BATS_TMPDIR}/opt/containers/current")" = "${BATS_TMPDIR}/opt/containers/releases/v2026.10.16-2" ]

  rm -f "${BATS_TMPDIR}/docker_up.log" "${BATS_TMPDIR}/docker.log"
  # v2026.10.16-3 has identical content for gcp ("services: {web: {image: 'v2'}}")
  prepare_mock_release "v2026.10.16-3" "gcp" "services: {web: {image: 'v2'}}"
  run_reconcile
  [ "$status" -eq 0 ]
  [ ! -e "${BATS_TMPDIR}/docker_up.log" ]
  run grep -F " pull" "${BATS_TMPDIR}/docker.log"
  [ "$status" -eq 1 ]
  [ "$(readlink "${BATS_TMPDIR}/opt/containers/current")" = "${BATS_TMPDIR}/opt/containers/releases/v2026.10.16-3" ]
  # previous MUST stay v2026.10.16-1, not v2026.10.16-2!
  [ "$(readlink "${BATS_TMPDIR}/opt/containers/previous")" = "${BATS_TMPDIR}/opt/containers/releases/v2026.10.16-1" ]
}

@test "reconcile: failed deploy rolls back to current, quarantines broken tag, and skips quarantined tag until newer release" {
  render_templates
  prepare_mock_release "v2026.10.16-1" "gcp" "services: {web: {image: 'v1'}}"
  run_reconcile
  [ "$status" -eq 0 ]

  # Deploy v2026.10.16-2 which fails healthcheck
  prepare_mock_release "v2026.10.16-2" "gcp" "services: {web: {image: 'v2-broken'}}"
  STUB_FAIL_PS_FOR_TAG="v2026.10.16-2" run_reconcile
  [ "$status" -eq 1 ]
  [ "$(cat "${BATS_TMPDIR}/var/lib/homelab-compose/quarantined-release")" = "v2026.10.16-2" ]
  [ ! -e "${BATS_TMPDIR}/var/lib/homelab-compose/deploying" ]
  [ "$(readlink "${BATS_TMPDIR}/opt/containers/current")" = "${BATS_TMPDIR}/opt/containers/releases/v2026.10.16-1" ]
  # Verify rollback up ran on v2026.10.16-1
  run tail -n 1 "${BATS_TMPDIR}/docker_up.log"
  [[ "$output" == *"v2026.10.16-1"* ]]

  # Next cycle while v2026.10.16-2 is still latest: skips download/deploy and exits 1
  rm -f "${BATS_TMPDIR}/docker_up.log"
  run_reconcile
  [ "$status" -eq 1 ]
  [ ! -e "${BATS_TMPDIR}/docker_up.log" ]

  # Newer release v2026.10.16-3 succeeds and clears quarantine
  prepare_mock_release "v2026.10.16-3" "gcp" "services: {web: {image: 'v3-fixed'}}"
  run_reconcile
  [ "$status" -eq 0 ]
  [ ! -e "${BATS_TMPDIR}/var/lib/homelab-compose/quarantined-release" ]
  [ "$(readlink "${BATS_TMPDIR}/opt/containers/current")" = "${BATS_TMPDIR}/opt/containers/releases/v2026.10.16-3" ]
}

@test "reconcile: first-deploy failure writes quarantine and does not attempt restore" {
  render_templates
  prepare_mock_release "v2026.10.16-1" "gcp" "services: {web: {image: 'v1-broken'}}"
  STUB_FAIL_UP_FOR_TAG="v2026.10.16-1" run_reconcile
  [ "$status" -eq 1 ]
  [ "$(cat "${BATS_TMPDIR}/var/lib/homelab-compose/quarantined-release")" = "v2026.10.16-1" ]
  [ ! -e "${BATS_TMPDIR}/opt/containers/current" ]
  [ "$(wc -l < "${BATS_TMPDIR}/docker_up.log" | tr -d ' ')" -eq 1 ]
}

@test "reconcile: steady-state unhealthy current runs one repair up without rollback and exits 1" {
  render_templates
  prepare_mock_release "v2026.10.16-1" "gcp" "services: {web: {image: 'v1'}}"
  run_reconcile
  [ "$status" -eq 0 ]
  prepare_mock_release "v2026.10.16-2" "gcp" "services: {web: {image: 'v2'}}"
  run_reconcile
  [ "$status" -eq 0 ]

  rm -f "${BATS_TMPDIR}/docker_up.log"
  # Same tag v2026.10.16-2, but ps reports unhealthy
  STUB_PS_JSON='[{"Service":"web","State":"running","Health":"unhealthy","ExitCode":0,"Labels":""},{"Service":"worker","State":"running","Health":"healthy","ExitCode":0,"Labels":""}]' \
    run_reconcile
  [ "$status" -eq 1 ]
  [ "$(wc -l < "${BATS_TMPDIR}/docker_up.log" | tr -d ' ')" -eq 1 ]
  [[ "$(cat "${BATS_TMPDIR}/docker_up.log")" == *"v2026.10.16-2"* ]]
  [ "$(readlink "${BATS_TMPDIR}/opt/containers/current")" = "${BATS_TMPDIR}/opt/containers/releases/v2026.10.16-2" ]
}

@test "reconcile: stale deploying marker quarantines interrupted tag and restores current before proceeding" {
  render_templates
  prepare_mock_release "v2026.10.16-1" "gcp" "services: {web: {image: 'v1'}}"
  run_reconcile
  [ "$status" -eq 0 ]

  rm -f "${BATS_TMPDIR}/docker_up.log"
  printf 'v2026.10.16-2\n' > "${BATS_TMPDIR}/var/lib/homelab-compose/deploying"
  prepare_mock_release "v2026.10.16-2" "gcp" "services: {web: {image: 'v2'}}"
  run_reconcile
  # Because v2026.10.16-2 was marked deploying, it gets quarantined, current (v1) is restored, and since latest==v2 (quarantined), it exits 1
  [ "$status" -eq 1 ]
  [ ! -e "${BATS_TMPDIR}/var/lib/homelab-compose/deploying" ]
  [ "$(cat "${BATS_TMPDIR}/var/lib/homelab-compose/quarantined-release")" = "v2026.10.16-2" ]
  [[ "$(cat "${BATS_TMPDIR}/docker_up.log")" == *"v2026.10.16-1"* ]]
}

@test "reconcile: verify_stack_health supports NDJSON output and homelab.compose.oneshot=true services" {
  render_templates
  prepare_mock_release "v2026.10.16-1" "gcp" "services: {web: {image: 'v1'}}"
  ndjson_ps='{"Service":"web","State":"running","Health":"healthy","ExitCode":0,"Labels":""}
{"Service":"worker","State":"exited","Health":"","ExitCode":0,"Labels":"homelab.compose.oneshot=true"}'
  STUB_PS_JSON="${ndjson_ps}" run_reconcile
  [ "$status" -eq 0 ]

  # Restarting or starting service fails health check
  prepare_mock_release "v2026.10.16-2" "gcp" "services: {web: {image: 'v2'}}"
  STUB_PS_JSON='{"Service":"web","State":"restarting","Health":"starting","ExitCode":0,"Labels":""}
{"Service":"worker","State":"running","Health":"","ExitCode":0,"Labels":""}' \
    run_reconcile
  [ "$status" -eq 1 ]
}

@test "cleanup: removes stale holds, prunes containers, holds current+previous images, prunes images/networks/builders, cleans holds on exit, and never prunes volumes" {
  render_templates
  prepare_mock_release "v2026.10.16-1" "gcp" "services: {web: {image: 'v1'}}"
  run_reconcile
  [ "$status" -eq 0 ]
  prepare_mock_release "v2026.10.16-2" "gcp" "services: {web: {image: 'v2'}}"
  run_reconcile
  [ "$status" -eq 0 ]

  printf 'stale_hold_id_123\n' > "${BATS_TMPDIR}/stale_holds.txt"
  STUB_MISSING_IMAGE="ghcr.io/example/web:v1" run_cleanup
  [ "$status" -eq 0 ]
  [ ! -e "${BATS_TMPDIR}/docker_volume_forbidden.log" ]

  run cat "${BATS_TMPDIR}/docker_holds.log"
  [[ "$output" == *"rm -f stale_hold_id_123"* ]]
  [[ "$output" == *"create --pull=never --label homelab.compose.hold=true"* ]]
  [[ "$output" == *"rm -f homelab-hold-"* ]]

  run cat "${BATS_TMPDIR}/docker_prune.log"
  [[ "$output" == *"container prune --force --filter until=168h"* ]]
  [[ "$output" == *"image prune --all --force --filter until=720h"* ]]
  [[ "$output" == *"network prune --force --filter until=168h"* ]]
  [[ "$output" == *"builder prune --all --force --filter until=720h"* ]]

  # Verify EXIT trap still cleans up hold containers when image prune fails
  rm -f "${BATS_TMPDIR}/docker_holds.log"
  STUB_IMAGE_PRUNE_RC=1 run_cleanup
  [ "$status" -ne 0 ]
  run grep -F "rm -f homelab-hold-" "${BATS_TMPDIR}/docker_holds.log"
  [ "$status" -eq 0 ]
}
