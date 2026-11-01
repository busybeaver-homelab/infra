#!/usr/bin/env bats
# Static checks for the valetudo_robot role skeleton: artifact pins and their
# checksums, network masking in defaults, and argument_specs coverage.

load 'helpers/test_helper'

ROLE_DIR="${REPO_ROOT}/configuration/roles/valetudo_robot"
DEFAULTS="${ROLE_DIR}/defaults/main.yml"
SPECS="${ROLE_DIR}/meta/argument_specs.yml"
TAILSCALE="${ROLE_DIR}/tasks/tailscale.yml"

# Templated references to secret material: the Tailscale auth key (and the raw
# helper output that carries it), the robot SSH key and the transport
# environment that holds its path, the Wi-Fi PSK and the basic-auth password.
SECRET_REF_PATTERN='\{\{[^}]*(tofu_robot_auth_key|tofu_vars_raw\.stdout|private_key_file|ROBOT_SSH_KEY|transport_env|wifi_psk|basic_auth_password)[^}]*\}\}'

# Prints the name of every task in a task file that templates secret material
# without no_log: true. A block is judged without its block/rescue/always lists,
# whose tasks are judged on their own.
secret_tasks_without_no_log() {
  PATTERN="${SECRET_REF_PATTERN}" yq eval '
    [.. | select(tag == "!!map" and has("name"))
        | with_entries(select(.key != "block" and .key != "rescue" and .key != "always"))
        | select(.no_log != true)
        | select([.. | select(tag == "!!str") | select(test(strenv(PATTERN)))] | length > 0)
        | .name] | .[]' "$1"
}

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

@test "tasks/main.yml imports the preflight (always), backup, install, wifi, configure and tailscale phases" {
  local main="${ROLE_DIR}/tasks/main.yml"
  [ -f "${main}" ]
  [ "$(yq eval '[.[] | select(has("ansible.builtin.import_tasks")) | .["ansible.builtin.import_tasks"]] | join(",")' "${main}")" = "preflight.yml,backup.yml,install.yml,wifi.yml,configure.yml,tailscale.yml" ]
  [ "$(yq eval '.[] | select(.["ansible.builtin.import_tasks"] == "preflight.yml") | .tags | sort | join(",")' "${main}")" = "always,preflight" ]
  [ "$(yq eval '.[] | select(.["ansible.builtin.import_tasks"] == "backup.yml") | .tags | join(",")' "${main}")" = "backup" ]
  [ "$(yq eval '.[] | select(.["ansible.builtin.import_tasks"] == "install.yml") | .tags | join(",")' "${main}")" = "install" ]
  [ "$(yq eval '.[] | select(.["ansible.builtin.import_tasks"] == "wifi.yml") | .tags | join(",")' "${main}")" = "wifi" ]
  [ "$(yq eval '.[] | select(.["ansible.builtin.import_tasks"] == "configure.yml") | .tags | join(",")' "${main}")" = "configure" ]
  [ "$(yq eval '.[] | select(.["ansible.builtin.import_tasks"] == "tailscale.yml") | .tags | join(",")' "${main}")" = "tailscale" ]
}

@test "main.yml flushes handlers (always) between the install and wifi imports" {
  local main="${ROLE_DIR}/tasks/main.yml"
  [ "$(yq eval '[.[] | .["ansible.builtin.import_tasks"] // .["ansible.builtin.meta"]] | join(",")' "${main}")" = "preflight.yml,backup.yml,install.yml,flush_handlers,wifi.yml,configure.yml,tailscale.yml" ]
  [ "$(yq eval '.[3].tags | join(",")' "${main}")" = "always" ]
}

@test "wifi phase treats a response-less PUT as submitted and fails on an HTTP error" {
  local wifi="${ROLE_DIR}/tasks/wifi.yml"
  grep -qF 'failed_when: false' "${wifi}"
  grep -qF 'Valetudo rejected the Wi-Fi configuration (HTTP status' "${wifi}"
  grep -qF "not in [-1, 200, 204]" "${wifi}"
}

@test "configure phase uses distinct messages for a rejected and an accepted-but-ineffective auth PUT" {
  local configure="${ROLE_DIR}/tasks/configure.yml"
  grep -qF "basic auth PUT was accepted but the re-probe still fails; re-run with --tags configure" "${configure}"
  grep -qF 'basic auth could not be set: Valetudo rejects the SOPS credentials' "${configure}"
}

@test "secret role inputs are no_log in argument_specs" {
  local key
  for key in valetudo_robot_basic_auth_username valetudo_robot_basic_auth_password valetudo_robot_wifi_psk; do
    [ "$(yq eval ".argument_specs.main.options.${key}.no_log" "${SPECS}")" = true ] || {
      echo "${key} lacks no_log"
      return 1
    }
  done
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

@test "every task in valetudo_robot touching tofu_robot_auth_key, ssh key, wifi psk or basic auth password has no_log: true" {
  [ -f "${TAILSCALE}" ]
  # The guard must see the auth key, or it proves nothing for the tailscale phase.
  grep -qF 'tofu_robot_auth_key' "${TAILSCALE}"
  local f offenders checked=0
  for f in "${ROLE_DIR}"/tasks/*.yml "${ROLE_DIR}"/handlers/*.yml; do
    offenders=$(secret_tasks_without_no_log "${f}")
    [ -z "${offenders}" ] || {
      echo "$(basename "${f}"): secret-bearing tasks without no_log: ${offenders}"
      return 1
    }
    checked=$((checked + 1))
  done
  [ "${checked}" -ge 7 ]
}

@test "no_log guard flags a synthetic secret-bearing task that lacks no_log" {
  local fixture="${BATS_TEST_TMPDIR}/tasks.yml"
  cat >"${fixture}" <<'YAML'
- name: Outer block
  block:
    - name: Leaky copy
      ansible.builtin.copy:
        content: "{{ (valetudo_robot_tofu_vars_raw.stdout | from_json).tofu_robot_auth_key }}"
        dest: /tmp/example
        mode: "0600"
    - name: Hidden copy
      ansible.builtin.copy:
        content: "{{ valetudo_robot_wifi_psk }}"
        dest: /tmp/example
        mode: "0600"
      no_log: true
YAML
  run secret_tasks_without_no_log "${fixture}"
  [ "$status" -eq 0 ]
  [ "$output" = "Leaky copy" ]
}

@test "tailscale phase runs the robot vars helper like cloud.yml: no_log, run_once, check_mode false, on localhost" {
  [ -f "${TAILSCALE}" ]
  local helper='.. | select(tag == "!!map" and has("ansible.builtin.command")) | select(.["ansible.builtin.command"].argv | tostring | test("valetudo_robot_tofu_vars_script"))'
  [ "$(yq eval "[${helper}] | length" "${TAILSCALE}")" -eq 1 ]
  [ "$(yq eval "${helper} | .no_log" "${TAILSCALE}")" = true ]
  [ "$(yq eval "${helper} | .run_once" "${TAILSCALE}")" = true ]
  [ "$(yq eval "${helper} | .check_mode" "${TAILSCALE}")" = false ]
  [ "$(yq eval "${helper} | .changed_when" "${TAILSCALE}")" = false ]
  [ "$(yq eval "${helper} | .delegate_to" "${TAILSCALE}")" = localhost ]
  [ "$(yq eval "${helper} | .become" "${TAILSCALE}")" = false ]
  # Its block rescues with a pointer that never surfaces the helper's stderr.
  local rescue='.. | select(tag == "!!map" and has("block") and has("rescue")) | select([.block[] | .["ansible.builtin.command"].argv // "" | tostring | test("valetudo_robot_tofu_vars_script")] | any) | .rescue'
  [ "$(yq eval "${rescue} | .[0].[\"ansible.builtin.fail\"].msg | test(\"get-tofu-robot-vars.sh\")" "${TAILSCALE}")" = true ]
  [ "$(yq eval "[${rescue} | .[] | .. | select(tag == \"!!str\") | select(test(\"[.](stderr|stdout|msg)\"))] | length" "${TAILSCALE}")" -eq 0 ]
  [[ "$(yq eval '.valetudo_robot_tofu_vars_script' "${DEFAULTS}")" == */scripts/get-tofu-robot-vars.sh ]] || false
  [ "$(yq eval '.valetudo_robot_tofu_vars_args | length' "${DEFAULTS}")" -eq 0 ]
}

@test "tailscale phase is gated on valetudo_robot_tailscale_enabled and keeps the key off argv and out of check mode" {
  [ -f "${TAILSCALE}" ]
  [ "$(yq eval 'length' "${TAILSCALE}")" -eq 1 ]
  yq eval '.[0].when | tostring' "${TAILSCALE}" | grep -qF 'valetudo_robot_tailscale_enabled'
  # Key file: controller tempfile written 0600 with no_log and diff false, removed in always.
  [ "$(yq eval '[.. | select(tag == "!!map" and has("ansible.builtin.tempfile"))] | length' "${TAILSCALE}")" -eq 1 ]
  [ "$(yq eval '.. | select(tag == "!!map" and has("ansible.builtin.copy")) | [.["ansible.builtin.copy"].mode, .no_log, .diff] | join(",")' "${TAILSCALE}")" = "0600,true,false" ]
  [ "$(yq eval '[.. | select(tag == "!!map" and has("always")) | .always[] | select(.["ansible.builtin.file"].state == "absent")] | length' "${TAILSCALE}")" -ge 1 ]
  # The key travels as a file: robot-transport.sh push to the staging path, then tailscale-join reads it.
  grep -qF '/data/.incoming/tskey' "${TAILSCALE}"
  grep -qF 'sh -s -- tailscale-join {{ valetudo_robot_tailscale_hostname | quote }}' "${TAILSCALE}"
  grep -qE '\{\{ valetudo_robot_tailscale_tag \| quote \}\} data/\.incoming/tskey <<.VALETUDO_EOF.$' "${TAILSCALE}"
  [ "$(yq eval '[.. | select(tag == "!!map" and has("ansible.builtin.raw")) | select(.["ansible.builtin.raw"] | test("tailscale-join")) | .no_log] | join(",")' "${TAILSCALE}")" = true ]
  # Check mode reports the tag only; the hostname is sensitive.
  grep -qF 'would join tailnet as {{ valetudo_robot_tailscale_tag }}' "${TAILSCALE}"
  # The hostname value is templated only into the tailscale-join command, never into a message.
  [ "$(grep -cE '\{\{[^}]*valetudo_robot_tailscale_hostname' "${TAILSCALE}")" -eq 1 ]
  grep -E '\{\{[^}]*valetudo_robot_tailscale_hostname' "${TAILSCALE}" | grep -qF 'sh -s -- tailscale-join'
}

@test "tailscale phase explains a rejected key, a stopped tailscaled and a usage error" {
  [ -f "${TAILSCALE}" ]
  grep -qF "tofu apply -replace='tailscale_tailnet_key.robot'" "${TAILSCALE}"
  grep -qF 'may be expired or already used' "${TAILSCALE}"
  grep -qF 're-run with --tags tailscale' "${TAILSCALE}"
  grep -qF 'tailscaled is not running' "${TAILSCALE}"
  grep -qF 'reboot' "${TAILSCALE}"
  grep -qF 'invalid arguments' "${TAILSCALE}"
}

@test "argument_specs declares valetudo_robot_tailscale_hostname without a default" {
  [ "$(yq eval '.argument_specs.main.options | has("valetudo_robot_tailscale_hostname")' "${SPECS}")" = true ]
  [ "$(yq eval '.argument_specs.main.options.valetudo_robot_tailscale_hostname.type' "${SPECS}")" = str ]
  [ "$(yq eval '.argument_specs.main.options.valetudo_robot_tailscale_hostname | has("default")' "${SPECS}")" = false ]
  [ "$(yq eval 'has("valetudo_robot_tailscale_hostname")' "${DEFAULTS}")" = false ]
}

@test "tailscale phase stages the auth key 0600 in a 0700 staging directory" {
  [ -f "${TAILSCALE}" ]
  local push='.. | select(tag == "!!map" and has("ansible.builtin.command")) | select(.["ansible.builtin.command"].argv | tostring | test("robot-transport.sh"))'
  [ "$(yq eval "[${push}] | length" "${TAILSCALE}")" -eq 1 ]
  [ "$(yq eval "${push} | .[\"ansible.builtin.command\"].argv | .[1:] | join(\" \")" "${TAILSCALE}")" = 'push {{ valetudo_robot_tskey_tmp.path }} /data/.incoming/tskey 0600' ]
  [ "$(yq eval '[.. | select(tag == "!!map" and has("ansible.builtin.raw")) | select(.["ansible.builtin.raw"] | test("mkdir -p /data/.incoming"))] | .[] | .["ansible.builtin.raw"]' "${TAILSCALE}")" = 'umask 077; mkdir -p /data/.incoming && chmod 0700 /data/.incoming' ]
}

@test "tailscale phase shows the key check failure and refuses more than one robot before the key fetch" {
  [ -f "${TAILSCALE}" ]
  # The visible assert works on a boolean computed by a no_log set_fact; it never touches the key.
  local check='.. | select(tag == "!!map" and has("ansible.builtin.assert")) | select(.["ansible.builtin.assert"].that | tostring | test("valetudo_robot_tailscale_key_ok"))'
  [ "$(yq eval "[${check}] | length" "${TAILSCALE}")" -eq 1 ]
  [ "$(yq eval "${check} | .no_log // false" "${TAILSCALE}")" = false ]
  [ "$(yq eval "${check} | .[\"ansible.builtin.assert\"].that | tostring | test(\"tofu_robot_auth_key|tofu_vars_raw\")" "${TAILSCALE}")" = false ]
  [ "$(yq eval "${check} | tostring | test(\"[{][{][^}]*(tofu_robot_auth_key|tofu_vars_raw)\")" "${TAILSCALE}")" = false ]
  yq eval "${check} | .[\"ansible.builtin.assert\"].fail_msg" "${TAILSCALE}" | grep -qF 'R2-GOV-05'
  [ "$(yq eval '.. | select(tag == "!!map" and has("ansible.builtin.set_fact")) | select(.["ansible.builtin.set_fact"] | has("valetudo_robot_tailscale_key_ok")) | .no_log' "${TAILSCALE}")" = true ]
  # One robot per run: asserted before the run_once helper.
  local hosts_ln helper_ln
  hosts_ln=$(grep -n 'ansible_play_hosts | length == 1' "${TAILSCALE}" | head -n1 | cut -d: -f1)
  helper_ln=$(grep -n 'valetudo_robot_tofu_vars_script' "${TAILSCALE}" | head -n1 | cut -d: -f1)
  [ -n "${hosts_ln}" ]
  [ -n "${helper_ln}" ]
  [ "${hosts_ln}" -lt "${helper_ln}" ]
}

@test "wifi phase probes the version endpoint, sends the PUT without credentials and retries with them only after a 401" {
  local wifi="${ROLE_DIR}/tasks/wifi.yml"
  local ready='.. | select(tag == "!!map" and has("ansible.builtin.uri")) | select(.["ansible.builtin.uri"].url | test("valetudo_robot_api_version_path"))'
  local first='.. | select(tag == "!!map" and has("ansible.builtin.uri")) | select(.["ansible.builtin.uri"].method == "PUT") | select(.register == "valetudo_robot_wifi_put")'
  local retry='.. | select(tag == "!!map" and has("ansible.builtin.uri")) | select(.["ansible.builtin.uri"].method == "PUT") | select(.register == "valetudo_robot_wifi_put_retry")'
  [ "$(yq eval "[${ready}] | length" "${wifi}")" -eq 1 ]
  [ "$(yq eval "[${first}] | length" "${wifi}")" -eq 1 ]
  [ "$(yq eval "[${retry}] | length" "${wifi}")" -eq 1 ]
  # The probe and the first PUT never carry the basic-auth credentials.
  [ "$(yq eval "${ready} | .[\"ansible.builtin.uri\"] | has(\"url_password\")" "${wifi}")" = false ]
  [ "$(yq eval "${first} | .[\"ansible.builtin.uri\"] | (has(\"url_password\") or has(\"url_username\") or has(\"force_basic_auth\"))" "${wifi}")" = false ]
  # The retry carries them and runs only after an HTTP 401.
  [ "$(yq eval "${retry} | .[\"ansible.builtin.uri\"] | has(\"url_password\")" "${wifi}")" = true ]
  yq eval "${retry} | .when | tostring" "${wifi}" | grep -qF 'valetudo_robot_wifi_put.status | default(-1) == 401'
  # Order: reachability probe, credential-free PUT, retry.
  local ready_ln first_ln retry_ln
  ready_ln=$(grep -n 'Check that the robot API answers' "${wifi}" | head -n1 | cut -d: -f1)
  first_ln=$(grep -n 'without credentials$' "${wifi}" | head -n1 | cut -d: -f1)
  retry_ln=$(grep -n 'Retry the Wi-Fi configuration with the basic-auth credentials' "${wifi}" | head -n1 | cut -d: -f1)
  [ -n "${ready_ln}" ] && [ -n "${first_ln}" ] && [ -n "${retry_ln}" ]
  [ "${ready_ln}" -lt "${first_ln}" ]
  [ "${first_ln}" -lt "${retry_ln}" ]
  # An unreachable robot API is a sanitized failure, not a "Wi-Fi dropped" success.
  grep -qF 'The robot API is not reachable;' "${wifi}"
  [ "$(grep -c 'valetudo_robot_api_base_url' <(grep -A3 'The robot API is not reachable;' "${wifi}"))" -eq 0 ]
}

@test "configure phase re-reads the auth configuration and requires enabled with the SOPS username" {
  local configure="${ROLE_DIR}/tasks/configure.yml"
  local recheck='.. | select(tag == "!!map" and has("ansible.builtin.uri")) | select(.register == "valetudo_robot_auth_recheck")'
  [ "$(yq eval "[${recheck}] | length" "${configure}")" -eq 1 ]
  [ "$(yq eval "${recheck} | .[\"ansible.builtin.uri\"].method" "${configure}")" = GET ]
  [ "$(yq eval "${recheck} | .[\"ansible.builtin.uri\"].url | test(\"valetudo_robot_api_auth_config_path\")" "${configure}")" = true ]
  [ "$(yq eval "${recheck} | .no_log" "${configure}")" = true ]
  local fail='.. | select(tag == "!!map" and has("ansible.builtin.fail")) | select(.when | tostring | test("valetudo_robot_auth_recheck"))'
  [ "$(yq eval "[${fail}] | length" "${configure}")" -eq 1 ]
  yq eval "${fail} | .when | tostring" "${configure}" | grep -qF 'json.enabled'
  yq eval "${fail} | .when | tostring" "${configure}" | grep -qF 'json.username'
  [ "$(yq eval "${fail} | .[\"ansible.builtin.fail\"].msg | test(\"[{][{]\")" "${configure}")" = false ]
}

@test "mock Valetudo generates its preset credentials at runtime instead of committing literals" {
  local mock="${ROLE_DIR}/molecule/default/mock_valetudo.py"
  grep -qxF 'PRESET_USERNAME = f"mock-preset-{secrets.token_hex(4)}"' "${mock}"
  grep -qxF 'PRESET_PASSWORD = secrets.token_hex(16)' "${mock}"
  [ "$(grep -cE '^PRESET_[A-Z]+ = ' "${mock}")" -eq 2 ]
}

@test "tailscale key tempfile lives in the gitignored controller cache with the swept robot_key prefix" {
  local tmpf='.. | select(tag == "!!map" and has("ansible.builtin.tempfile")) | .["ansible.builtin.tempfile"]'
  [ "$(yq eval "${tmpf} | .path" "${TAILSCALE}")" = '{{ valetudo_robot_controller_cache_dir }}' ]
  [ "$(yq eval "${tmpf} | .prefix" "${TAILSCALE}")" = 'robot_key.' ]
  [ "$(yq eval '.valetudo_robot_controller_cache_dir' "${DEFAULTS}")" = '{{ playbook_dir }}/../../.cache/ansible' ]
  # The directory is created 0700 before the tempfile and the file is removed in always.
  local dir='.. | select(tag == "!!map" and has("ansible.builtin.file")) | select(.["ansible.builtin.file"].path == "{{ valetudo_robot_controller_cache_dir }}")'
  [ "$(yq eval "${dir} | .[\"ansible.builtin.file\"] | [.state, .mode] | join(\",\")" "${TAILSCALE}")" = 'directory,0700' ]
  [ "$(yq eval '[.. | select(tag == "!!map" and has("always")) | .always[] | select(.["ansible.builtin.file"].path == "{{ valetudo_robot_tskey_tmp.path }}" and .["ansible.builtin.file"].state == "absent")] | length' "${TAILSCALE}")" -eq 1 ]
  [ "$(yq eval '[.. | select(tag == "!!map" and has("ansible.builtin.tempfile")) | .["ansible.builtin.tempfile"] | select(has("path") | not)] | length' "${TAILSCALE}")" -eq 0 ]
}

@test "tailscale always-cleanup removes the staged key and its .part file" {
  [ "$(yq eval '[.. | select(tag == "!!map" and has("always")) | .always[] | select(.["ansible.builtin.raw"] == "rm -f /data/.incoming/tskey /data/.incoming/tskey.part")] | length' "${TAILSCALE}")" -eq 1 ]
}

@test "every block in the role rescues, and each phase block fails again through reraise.yml (CKV2_ANSIBLE_3)" {
  local f checked=0
  for f in "${ROLE_DIR}"/tasks/*.yml; do
    [ "$(yq eval '[.. | select(tag == "!!map" and has("block") and (has("rescue") | not))] | length' "${f}")" -eq 0 ] || {
      echo "$(basename "${f}"): block without rescue"
      return 1
    }
    [ "$(yq eval '[.[] | select(has("block")) | select(.rescue[-1]["ansible.builtin.import_tasks"] != "reraise.yml")] | length' "${f}")" -eq 0 ] || {
      echo "$(basename "${f}"): phase block rescue does not end by importing reraise.yml"
      return 1
    }
    checked=$((checked + 1))
  done
  [ "${checked}" -ge 7 ]
}

@test "reraise.yml repeats only messages authored by fail/assert and otherwise names the task" {
  local reraise="${ROLE_DIR}/tasks/reraise.yml"
  [ "$(yq eval 'length' "${reraise}")" -eq 1 ]
  local msg
  msg=$(yq eval '.[0]["ansible.builtin.fail"].msg' "${reraise}")
  [[ "${msg}" == *"if valetudo_robot_reraise_authored"[[:space:]]* ]] || false
  [[ "${msg}" == *"ansible_failed_task.name"* ]] || false
  [[ "$(yq eval '.[0].vars.valetudo_robot_reraise_authored' "${reraise}")" == *"in ['fail', 'assert']"* ]] || false
  # Raw module output never reaches the message.
  [ "$(yq eval '[.. | select(tag == "!!str") | select(test("[.](stderr|stdout)"))] | length' "${reraise}")" -eq 0 ]
}

ROBOTS_PLAYBOOK="${REPO_ROOT}/configuration/playbooks/robots.yml"
ROBOT_KEY_DIR="${REPO_ROOT}/.cache/ansible"

# Skips unless the CI SOPS file can be decrypted with a key from the environment
# or the default age key location. Only a non-secret flag is extracted, to /dev/null.
require_ci_sops() {
  if [ -z "${SOPS_AGE_KEY:-}" ] && [ -z "${SOPS_AGE_KEY_FILE:-}" ] && [ -f "${HOME}/.config/sops/age/keys.txt" ]; then
    export SOPS_AGE_KEY_FILE="${HOME}/.config/sops/age/keys.txt"
  fi
  sops decrypt --extract '["is_production"]' "${REPO_ROOT}/secrets/credentials.ci.sops.yaml" >/dev/null 2>&1 \
    || skip "needs SOPS_AGE_KEY for the CI SOPS file (shell-bats CI job has none; run locally)"
}

# Removes the seeded stale key even when a test fails before its own checks.
teardown() {
  if [ -n "${STALE_KEY:-}" ]; then
    rm -f "${STALE_KEY}"
  fi
}

# Number of controller key tempfiles that Play 1 of robots.yml leaves behind.
robot_key_tempfiles() {
  find "${ROBOT_KEY_DIR}" -maxdepth 1 -name 'robot_key.*' 2>/dev/null | wc -l | tr -d ' '
}

@test "robots.yml preflight fails on placeholder values" {
  require_ci_sops
  local before
  before=$(robot_key_tempfiles)
  cd "${REPO_ROOT}"
  # Synthetic override of the whole valetudo_robot map; only wifi.psk is a placeholder.
  local robot_vars='{"valetudo_robot": {"lan_host": "203.0.113.5", "ap_host": "203.0.113.6", "ssh_private_key": "synthetic", "wifi": {"ssid": "example-ssid", "psk": "PLACEHOLDER-x"}, "basic_auth": {"username": "example-user", "password": "example-pass"}, "tailscale_hostname": "example-robot"}}'
  run mise exec -- ansible-playbook -i "localhost," "${ROBOTS_PLAYBOOK}" \
    -e custom_sops_secrets_file=credentials.ci.sops.yaml -e is_production=false -e is_ci_environment=true \
    -e valetudo_robot_force_placeholder_check=true -e valetudo_robot_probe_timeout=1 \
    -e "${robot_vars}"
  [ "$status" -ne 0 ] || false
  [[ "${output}" == *"wifi.psk"* ]] || false
  [[ "${output}" != *"PLACEHOLDER-x"* ]] || false
  [[ "${output}" != *"203.0.113"* ]] || false
  [ "$(robot_key_tempfiles)" -eq "${before}" ] || false
}

@test "robots.yml preflight flags a TEST-NET-1 address as a placeholder by key name" {
  require_ci_sops
  cd "${REPO_ROOT}"
  local robot_vars='{"valetudo_robot": {"lan_host": "192.0.2.77", "ap_host": "203.0.113.6", "ssh_private_key": "synthetic", "wifi": {"ssid": "example-ssid", "psk": "example-psk"}, "basic_auth": {"username": "example-user", "password": "example-pass"}, "tailscale_hostname": "example-robot"}}'
  run mise exec -- ansible-playbook -i "localhost," "${ROBOTS_PLAYBOOK}" \
    -e custom_sops_secrets_file=credentials.ci.sops.yaml -e is_production=false -e is_ci_environment=true \
    -e valetudo_robot_force_placeholder_check=true -e valetudo_robot_probe_timeout=1 \
    -e "${robot_vars}"
  [ "$status" -ne 0 ] || false
  [[ "${output}" == *"lan_host"* ]] || false
  [[ "${output}" != *"192.0.2.77"* ]] || false
}

@test "preflight fails when neither address answers" {
  require_ci_sops
  cd "${REPO_ROOT}"
  run mise exec -- ansible-playbook -i "localhost," "${ROBOTS_PLAYBOOK}" \
    -e custom_sops_secrets_file=credentials.ci.sops.yaml -e is_production=false -e is_ci_environment=true \
    -e valetudo_robot_probe_timeout=1
  [ "$status" -ne 0 ] || false
  # Ansible folds long messages across lines; compare on whitespace-normalised output.
  local flat
  flat=$(printf '%s' "${output}" | tr '\n' ' ' | tr -s ' ')
  [[ "${flat}" == *"robot not reachable at lan_host or ap_host (asleep, off Wi-Fi, or placeholder address)"* ]] || false
  [[ "${output}" != *"198.51.100."* ]] || false
  [[ "${output}" != *"PRIVATE KEY"* ]] || false
  # The failed run removes the controller key tempfile it created.
  [ "$(robot_key_tempfiles)" -eq 0 ] || false
}

@test "robots.yml preflight shape: sentinel, load_vars, placeholder check, no_log key, probe, add_host, cleanup" {
  [ -f "${ROBOTS_PLAYBOOK}" ]
  [ "$(yq eval 'length' "${ROBOTS_PLAYBOOK}")" -eq 3 ]
  [ "$(yq eval '.[0].hosts' "${ROBOTS_PLAYBOOK}")" = localhost ]
  [ "$(yq eval '.[0].connection' "${ROBOTS_PLAYBOOK}")" = local ]
  [ "$(yq eval '.[1].hosts' "${ROBOTS_PLAYBOOK}")" = robots ]
  [ "$(yq eval '.[1].gather_facts' "${ROBOTS_PLAYBOOK}")" = false ]
  [ "$(yq eval '[.[1].tasks[].block[] | select(has("ansible.builtin.import_role")) | .["ansible.builtin.import_role"].name] | .[0]' "${ROBOTS_PLAYBOOK}")" = valetudo_robot ]
  # Order inside Play 1: sentinel, load_vars, placeholder check, key tempfile, probe, add_host.
  local sentinel load placeholder tempfile probe add
  first_code_line() { grep -n '' "${ROBOTS_PLAYBOOK}" | grep -v '^[0-9]*:[[:space:]]*#' | grep -F -- "$1" | head -n1 | cut -d: -f1; }
  sentinel=$(first_code_line 'environment sentinel')
  load=$(first_code_line 'community.sops.load_vars')
  placeholder=$(first_code_line 'PLACEHOLDER-')
  tempfile=$(first_code_line 'ansible.builtin.tempfile')
  probe=$(first_code_line 'robot-transport.sh')
  add=$(first_code_line 'ansible.builtin.add_host')
  [ -n "${sentinel}" ] && [ -n "${load}" ] && [ -n "${placeholder}" ] && [ -n "${tempfile}" ] && [ -n "${probe}" ] && [ -n "${add}" ]
  [ "${sentinel}" -lt "${load}" ]
  [ "${load}" -lt "${placeholder}" ]
  [ "${placeholder}" -lt "${tempfile}" ]
  [ "${tempfile}" -lt "${probe}" ]
  [ "${probe}" -lt "${add}" ]
}

@test "robots.yml refuses is_ci_environment with the production SOPS file before loading it" {
  cd "${REPO_ROOT}"
  run mise exec -- ansible-playbook -i "localhost," "${ROBOTS_PLAYBOOK}" \
    -e custom_sops_secrets_file=credentials.sops.yaml -e is_production=false -e is_ci_environment=true
  [ "$status" -ne 0 ] || false
  local flat
  flat=$(printf '%s' "${output}" | tr '\n' ' ' | tr -s ' ')
  [[ "${flat}" == *"is_ci_environment may only be combined with credentials.ci.sops.yaml"* ]] || false
  # The refusal comes before any SOPS decryption or robot contact.
  [[ "${output}" != *"Load SOPS credentials"* ]] || false
}

@test "preflight sweeps stale robot key tempfiles from the controller cache" {
  require_ci_sops
  cd "${REPO_ROOT}"
  mkdir -p "${ROBOT_KEY_DIR}"
  STALE_KEY="${ROBOT_KEY_DIR}/robot_key.bats-stale-$$"
  : >"${STALE_KEY}"
  run mise exec -- ansible-playbook -i "localhost," "${ROBOTS_PLAYBOOK}" \
    -e custom_sops_secrets_file=credentials.ci.sops.yaml -e is_production=false -e is_ci_environment=true \
    -e valetudo_robot_probe_timeout=1
  # Checked before any cleanup: only the playbook's sweep can have removed the seeded file.
  [ ! -e "${STALE_KEY}" ] || false
  [ "$status" -ne 0 ] || false
  [[ "${output}" == *"Remove stale controller SSH key tempfiles"* ]] || false
  [[ "${output}" != *"bats-stale"* ]] || false
  [ "$(robot_key_tempfiles)" -eq 0 ] || false
}

@test "robots.yml refuses is_production with the CI SOPS file before loading it" {
  cd "${REPO_ROOT}"
  run mise exec -- ansible-playbook -i "localhost," "${ROBOTS_PLAYBOOK}" \
    -e custom_sops_secrets_file=credentials.ci.sops.yaml -e is_production=true -e is_ci_environment=false
  [ "$status" -ne 0 ] || false
  local flat
  flat=$(printf '%s' "${output}" | tr '\n' ' ' | tr -s ' ')
  [[ "${flat}" == *"is_production may only be combined with credentials.sops.yaml"* ]] || false
  [[ "${output}" != *"Load SOPS credentials"* ]] || false
}

@test "add_host ssh args keep accept-new host keys and LogLevel=ERROR next to the dedicated known-hosts file" {
  [ "$(yq eval '[.[0].tasks[].block[]? | select(has("ansible.builtin.add_host")) | .["ansible.builtin.add_host"].ansible_ssh_common_args] | .[0]' "${ROBOTS_PLAYBOOK}")" != null ]
  local args
  args=$(yq eval '[.[0].tasks[].block[]? | select(has("ansible.builtin.add_host")) | .["ansible.builtin.add_host"].ansible_ssh_common_args] | .[0]' "${ROBOTS_PLAYBOOK}")
  [[ "${args}" == *'-o StrictHostKeyChecking=accept-new'* ]] || false
  [[ "${args}" == *'-o LogLevel=ERROR'* ]] || false
  [[ "${args}" == *'-o "UserKnownHostsFile={{ _robot_known_hosts }}"'* ]] || false
}

@test "robots.yml removes the key in a localhost Play 3 and sweeps stale keys at the start of Play 1" {
  [ -f "${ROBOTS_PLAYBOOK}" ]
  # Play 3: runs after the robot play even when Play 2's always section is skipped (end_host, unreachable).
  [ "$(yq eval '.[2].hosts' "${ROBOTS_PLAYBOOK}")" = localhost ]
  [ "$(yq eval '.[2].connection' "${ROBOTS_PLAYBOOK}")" = local ]
  [ "$(yq eval '.[2].gather_facts' "${ROBOTS_PLAYBOOK}")" = false ]
  [ "$(yq eval '.[2].tags | join(",")' "${ROBOTS_PLAYBOOK}")" = always ]
  [ "$(yq eval '.[2].tasks[0]["ansible.builtin.file"].state' "${ROBOTS_PLAYBOOK}")" = absent ]
  [ "$(yq eval '.[2].tasks[0].no_log' "${ROBOTS_PLAYBOOK}")" = true ]
  yq eval '.[2].tasks[0]["ansible.builtin.file"].path' "${ROBOTS_PLAYBOOK}" | grep -qF '_robot_key_tmp.path'
  # Play 2 keeps its own always cleanup.
  [ "$(yq eval '.[1].tasks[0].always | length' "${ROBOTS_PLAYBOOK}")" -eq 1 ]
  # Sweep: finds robot_key.* in the cache dir after the dir exists and before the tempfile is created.
  local dir find tmp
  first_code_line() { grep -n '' "${ROBOTS_PLAYBOOK}" | grep -v '^[0-9]*:[[:space:]]*#' | grep -F -- "$1" | head -n1 | cut -d: -f1; }
  dir=$(first_code_line 'Ensure the controller cache directory exists')
  find=$(first_code_line 'ansible.builtin.find')
  tmp=$(first_code_line 'ansible.builtin.tempfile')
  [ "${dir}" -lt "${find}" ]
  [ "${find}" -lt "${tmp}" ]
  grep -qF 'patterns: robot_key.*' "${ROBOTS_PLAYBOOK}"
}

@test "robots.yml asserts CI mode never contacts a robot after TCP reachability and before the SSH probe" {
  [ -f "${ROBOTS_PLAYBOOK}" ]
  first_code_line() { grep -n '' "${ROBOTS_PLAYBOOK}" | grep -v '^[0-9]*:[[:space:]]*#' | grep -F -- "$1" | head -n1 | cut -d: -f1; }
  local reach guard probe add
  reach=$(first_code_line 'robot not reachable at lan_host or ap_host')
  guard=$(first_code_line 'CI mode never contacts a robot')
  probe=$(first_code_line 'robot-transport.sh')
  add=$(first_code_line 'ansible.builtin.add_host')
  [ -n "${reach}" ] && [ -n "${guard}" ] && [ -n "${probe}" ] && [ -n "${add}" ]
  [ "${reach}" -lt "${guard}" ]
  [ "${guard}" -lt "${probe}" ]
  [ "${probe}" -lt "${add}" ]
}

@test "robots group_vars stay minimal and the known-hosts path is defined once in Play 1" {
  local gv="${REPO_ROOT}/configuration/group_vars/robots.yml"
  [ "$(yq eval 'keys | sort | join(",")' "${gv}")" = "ansible_connection,ansible_user" ]
  [ "$(grep -c 'robot_known_hosts"' "${ROBOTS_PLAYBOOK}")" -eq 1 ]
  grep -qF -- '-o "UserKnownHostsFile={{ _robot_known_hosts }}"' "${ROBOTS_PLAYBOOK}"
}
