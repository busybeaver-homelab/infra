#!/usr/bin/env bats
# Behavioral tests for mise secret:*:set, secret:*:get, and secret:*:delete tasks (REV2-P3-8 / R2-GATE-04)

load 'helpers/test_helper'

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  MISE_TOML="$REPO_ROOT/mise.toml"
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
}

# Helper to extract a mise task's run script into a standalone executable script
extract_task_script() {
  local task_name="$1"
  local out_script="$2"
  python3 - "$MISE_TOML" "$task_name" "$out_script" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
run_body = data["tasks"][sys.argv[2]]["run"]
with open(sys.argv[3], "w") as out:
    out.write("#!/usr/bin/env bash\nset -euo pipefail\n")
    out.write(run_body)
    out.write("\n")
PY
  chmod +x "$out_script"
}

@test "secret:ci:set converts dotted keys to bracket paths and passes value via --value-stdin without exposing secret in argv" {
  local script="$BATS_TEST_TMPDIR/secret_ci_set.sh"
  extract_task_script "secret:ci:set" "$script"

  local spy_args="$BATS_TEST_TMPDIR/sops_args.txt"
  local spy_stdin="$BATS_TEST_TMPDIR/sops_stdin.txt"
  cat >"$STUB_BIN/sops" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$spy_args"
cat >"$spy_stdin"
EOF
  chmod +x "$STUB_BIN/sops"

  local secret_file="$BATS_TEST_TMPDIR/input_secret.txt"
  printf 'synthetic-secret-value-never-in-argv\n' >"$secret_file"
  export SOPS_CI_FILE="$BATS_TEST_TMPDIR/dummy.ci.sops.yaml"
  : >"$SOPS_CI_FILE"

  run env PATH="$STUB_BIN:$PATH" "$script" "cloudflare.config.account_id" "$secret_file"
  [ "$status" -eq 0 ]

  local recorded_args recorded_stdin
  recorded_args="$(cat "$spy_args")"
  recorded_stdin="$(cat "$spy_stdin")"

  [[ "$recorded_args" == *"set --value-stdin"* ]] || false
  [[ "$recorded_args" == *'["cloudflare"]["config"]["account_id"]'* ]] || false
  [[ "$recorded_args" != *"synthetic-secret-value-never-in-argv"* ]] || false
  [ "$recorded_stdin" = '"synthetic-secret-value-never-in-argv"' ]
}

@test "secret:ci:set, secret:ci:get, and secret:ci:delete round-trip nested dotted keys against a synthetic age-encrypted SOPS file" {
  local set_script="$BATS_TEST_TMPDIR/secret_ci_set.sh"
  local get_script="$BATS_TEST_TMPDIR/secret_ci_get.sh"
  local del_script="$BATS_TEST_TMPDIR/secret_ci_delete.sh"
  extract_task_script "secret:ci:set" "$set_script"
  extract_task_script "secret:ci:get" "$get_script"
  extract_task_script "secret:ci:delete" "$del_script"

  local key_file="$BATS_TEST_TMPDIR/age.txt"
  age-keygen -o "$key_file" 2>/dev/null
  local pub
  pub="$(awk '/^# public key:/ {print $4}' "$key_file")"

  local sops_cfg="$BATS_TEST_TMPDIR/.sops.yaml"
  cat >"$sops_cfg" <<EOF
creation_rules:
  - path_regex: .*\.sops\.yaml$
    age: ${pub}
EOF

  local sops_file="$BATS_TEST_TMPDIR/test.ci.sops.yaml"
  cat >"$sops_file" <<'EOF'
existing:
  key: initial
EOF
  SOPS_AGE_KEY_FILE="$key_file" sops --config "$sops_cfg" -e -i "$sops_file"

  local val_file="$BATS_TEST_TMPDIR/val.txt"
  printf 'nested-synthetic-val-42\n' >"$val_file"

  # Set nested key a.b.c using sops wrapper that injects --config
  cat >"$STUB_BIN/sops" <<EOF
#!/usr/bin/env bash
exec "$(command -v sops)" --config "$sops_cfg" "\$@"
EOF
  chmod +x "$STUB_BIN/sops"

  run env PATH="$STUB_BIN:$PATH" SOPS_AGE_KEY_FILE="$key_file" SOPS_CI_FILE="$sops_file" "$set_script" "a.b.c" "$val_file"
  [ "$status" -eq 0 ]

  run env PATH="$STUB_BIN:$PATH" SOPS_AGE_KEY_FILE="$key_file" SOPS_CI_FILE="$sops_file" "$get_script" "a.b.c"
  [ "$status" -eq 0 ]
  [ "$output" = "nested-synthetic-val-42" ]

  run env PATH="$STUB_BIN:$PATH" SOPS_AGE_KEY_FILE="$key_file" SOPS_CI_FILE="$sops_file" "$del_script" "a.b.c"
  [ "$status" -eq 0 ]

  run env PATH="$STUB_BIN:$PATH" SOPS_AGE_KEY_FILE="$key_file" SOPS_CI_FILE="$sops_file" "$get_script" "a.b.c"
  [ "$status" -ne 0 ]
}

@test "secret:ci:set rejects malformed key paths before invoking sops" {
  local script="$BATS_TEST_TMPDIR/secret_ci_set.sh"
  extract_task_script "secret:ci:set" "$script"

  for bad_key in ".leading" "trailing." "double..dot" "space in key" "semi;colon"; do
    run "$script" "$bad_key"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid secret key"* ]] || false
  done
}
