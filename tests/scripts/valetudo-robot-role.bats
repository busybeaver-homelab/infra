#!/usr/bin/env bats
# Static checks for the valetudo_robot role skeleton: artifact pins and their
# checksums, network masking in defaults, and argument_specs coverage.

load 'helpers/test_helper'

ROLE_DIR="${REPO_ROOT}/configuration/roles/valetudo_robot"
DEFAULTS="${ROLE_DIR}/defaults/main.yml"
SPECS="${ROLE_DIR}/meta/argument_specs.yml"

@test "every pinned version has a 64-hex sha256" {
  [ -f "${DEFAULTS}" ]
  local versions name artifact sha prev count=0
  versions=$(grep -E '^valetudo_robot_[a-z0-9_]+_version:' "${DEFAULTS}" | cut -d: -f1)
  [ -n "${versions}" ]
  while IFS= read -r name; do
    artifact="${name%_version}"
    sha=$(yq eval ".${artifact}_sha256" "${DEFAULTS}")
    [[ "${sha}" =~ ^[0-9a-f]{64}$ ]] || {
      echo "${artifact}_sha256 is not 64 lowercase hex characters: ${sha}"
      return 1
    }
    [[ "$(yq eval ".${name}" "${DEFAULTS}")" =~ ^[0-9]+(\.[0-9]+)+$ ]] || {
      echo "${name} is not a plain version number"
      return 1
    }
    prev=$(grep -B1 -E "^${name}:" "${DEFAULTS}" | head -n1)
    [[ "${prev}" =~ ^\#\ renovate:\ datasource=github-releases\ depName=[^[:space:]]+$ ]] || {
      echo "${name} is not preceded by a renovate annotation: ${prev}"
      return 1
    }
    count=$((count + 1))
  done <<<"${versions}"
  [ "${count}" -eq 2 ]
  grep -qxF '# renovate: datasource=github-releases depName=Hypfer/Valetudo' "${DEFAULTS}"
  grep -qxF '# renovate: datasource=github-releases depName=tailscale/tailscale' "${DEFAULTS}"
}

@test "defaults contain no IPv4 outside TEST-NET" {
  [ -f "${DEFAULTS}" ]
  local ip
  while IFS= read -r ip; do
    [ -n "${ip}" ] || continue
    [[ "${ip}" =~ ^(192\.0\.2|198\.51\.100|203\.0\.113)\. ]] || {
      echo "non TEST-NET IPv4 address in defaults"
      return 1
    }
  done < <(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "${DEFAULTS}" || true)
}

@test "argument_specs covers every default" {
  [ -f "${DEFAULTS}" ]
  [ -f "${SPECS}" ]
  local keys key
  keys=$(yq eval 'keys | .[]' "${DEFAULTS}")
  [ -n "${keys}" ]
  while IFS= read -r key; do
    [[ "${key}" == valetudo_robot_* ]] || {
      echo "default ${key} is not role-prefixed"
      return 1
    }
    [ "$(yq eval ".argument_specs.main.options | has(\"${key}\")" "${SPECS}")" = true ] || {
      echo "argument_specs is missing ${key}"
      return 1
    }
    [ "$(yq eval ".argument_specs.main.options.${key} | (has(\"type\") and has(\"description\"))" "${SPECS}")" = true ] || {
      echo "argument_specs entry ${key} lacks type or description"
      return 1
    }
  done <<<"${keys}"
}

@test "tasks/main.yml imports the preflight (always), backup, install, wifi and configure phases" {
  local main="${ROLE_DIR}/tasks/main.yml"
  [ -f "${main}" ]
  [ "$(yq eval '[.[] | .["ansible.builtin.import_tasks"]] | join(",")' "${main}")" = "preflight.yml,backup.yml,install.yml,wifi.yml,configure.yml" ]
  [ "$(yq eval '.[0].tags | sort | join(",")' "${main}")" = "always,preflight" ]
  [ "$(yq eval '.[1].tags | join(",")' "${main}")" = "backup" ]
  [ "$(yq eval '.[2].tags | join(",")' "${main}")" = "install" ]
  [ "$(yq eval '.[3].tags | join(",")' "${main}")" = "wifi" ]
  [ "$(yq eval '.[4].tags | join(",")' "${main}")" = "configure" ]
}

@test "backup phase runs the git-crypt guard before pulling calibration data" {
  local backup="${ROLE_DIR}/tasks/backup.yml"
  [ -f "${backup}" ]
  local guard pull
  guard=$(grep -n 'assert-git-crypt-target.sh' "${backup}" | head -n1 | cut -d: -f1)
  pull=$(grep -n 'pull-calibration' "${backup}" | head -n1 | cut -d: -f1)
  [ -n "${guard}" ]
  [ -n "${pull}" ]
  [ "${guard}" -lt "${pull}" ]
}

@test "install phase validates every pin before the first download" {
  local install="${ROLE_DIR}/tasks/install.yml"
  [ -f "${install}" ]
  local assert_ln download_ln
  assert_ln=$(grep -n 'must be a non-empty, 64 character lowercase hex SHA-256' "${install}" | head -n1 | cut -d: -f1)
  download_ln=$(grep -n 'ansible.builtin.get_url' "${install}" | head -n1 | cut -d: -f1)
  [ -n "${assert_ln}" ]
  [ -n "${download_ln}" ]
  [ "${assert_ln}" -lt "${download_ln}" ]
  grep -qF 'valetudo_robot_valetudo_sha256' "${install}"
  grep -qF 'valetudo_robot_tailscale_sha256' "${install}"
}

@test "install phase hides transport output and skips binaries already at their pin" {
  local install="${ROLE_DIR}/tasks/install.yml"
  [ -f "${install}" ]
  [ "$(grep -c 'no_log: true' "${install}")" -eq 2 ]
  run grep -E '^[[:space:]]+creates:' "${install}"
  [ "$status" -ne 0 ]
  grep -qF 'ansible_check_mode' "${install}"
  grep -qF 'valetudo_robot_installed_map' "${install}"
  grep -qF 'valetudo_robot_push_plan' "${install}"
}

@test "managed postboot block starts tailscaled with the required flags behind an executable guard" {
  local tpl="${ROLE_DIR}/templates/root_postboot.managed.sh.j2"
  [ -f "${tpl}" ]
  grep -qF '[ -x /data/tailscale/tailscaled ]' "${tpl}"
  grep -qF -- '--tun=userspace-networking --statedir=/data/tailscale/state --socket=/tmp/tailscaled.sock --no-logs-no-support' "${tpl}"
  run grep -E '^[[:space:]]*/data/tailscale/tailscaled .*&[[:space:]]*$' "${tpl}"
  [ "$status" -eq 0 ]
}

@test "Reboot robot handler waits on SSH then HTTP and honours valetudo_robot_reboot_enabled" {
  local handlers="${ROLE_DIR}/handlers/main.yml"
  [ -f "${handlers}" ]
  [ "$(yq eval '.[0].name' "${handlers}")" = "Reboot robot" ]
  [ "$(yq eval '[.[] | select(.listen == "Reboot robot") | .["ansible.builtin.wait_for"].port] | map(select(. != null)) | join(",")' "${handlers}")" = "22,22,80" ]
  [ "$(yq eval '[.[] | select(has("ansible.builtin.wait_for")) | .no_log] | map(select(. == true)) | length' "${handlers}")" -eq 3 ]
  [ "$(yq eval '[.[] | select(.listen == "Reboot robot") | .["ansible.builtin.wait_for"].timeout] | map(select(. != null)) | join(",")' "${handlers}")" = "60,300,300" ]
  grep -qF 'valetudo_robot_reboot_enabled' "${handlers}"
}

@test "wifi and configure phases keep credentials out of logs and the Wi-Fi phase ends the host" {
  local wifi="${ROLE_DIR}/tasks/wifi.yml" configure="${ROLE_DIR}/tasks/configure.yml"
  [ -f "${wifi}" ]
  [ -f "${configure}" ]
  # Every uri task carries no_log: no task may call uri without it.
  [ "$(yq eval '[.. | select(tag == "!!map" and has("ansible.builtin.uri")) | select(.no_log != true)] | length' "${wifi}")" = "0" ]
  [ "$(yq eval '[.. | select(tag == "!!map" and has("ansible.builtin.uri")) | select(.no_log != true)] | length' "${configure}")" = "0" ]
  grep -qF 'ansible.builtin.meta: end_host' "${wifi}"
  grep -qF 'Wi-Fi submitted. Reconnect this machine to the home network and re-run with --tags configure,tailscale.' "${wifi}"
  grep -qF 'basic auth could not be set: Valetudo rejects the SOPS credentials' "${configure}"
}

@test "argument_specs covers the API inputs the wifi and configure phases consume" {
  local key
  for key in valetudo_robot_api_base_url valetudo_robot_on_lan valetudo_robot_basic_auth_username \
    valetudo_robot_basic_auth_password valetudo_robot_wifi_ssid valetudo_robot_wifi_psk valetudo_robot_settings; do
    [ "$(yq eval ".argument_specs.main.options | has(\"${key}\")" "${SPECS}")" = true ] || {
      echo "argument_specs is missing ${key}"
      return 1
    }
  done
  # Secrets and the LAN flag are never defaulted (R2-GOV-05).
  for key in valetudo_robot_api_base_url valetudo_robot_on_lan valetudo_robot_basic_auth_username \
    valetudo_robot_basic_auth_password valetudo_robot_wifi_ssid valetudo_robot_wifi_psk; do
    [ "$(yq eval "has(\"${key}\")" "${DEFAULTS}")" = false ] || {
      echo "${key} must not be defaulted"
      return 1
    }
  done
}
