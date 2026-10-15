#!/usr/bin/env bats
# Tests for scripts/verify-sops-encryption.sh

load 'helpers/test_helper'

VERIFY_SCRIPT="${REPO_ROOT}/scripts/verify-sops-encryption.sh"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "verify-sops-encryption.sh succeeds on valid repo secrets/credentials.ci.sops.yaml" {
  run bash "${VERIFY_SCRIPT}" "${REPO_ROOT}/secrets/credentials.ci.sops.yaml"
  [ "$status" -eq 0 ]
}

@test "verify-sops-encryption.sh skips .sops.yaml config file" {
  run bash "${VERIFY_SCRIPT}" "${REPO_ROOT}/.sops.yaml"
  [ "$status" -eq 0 ]
}

@test "verify-sops-encryption.sh fails on non-canonical file path" {
  mkdir -p "${BATS_TMPDIR}/other"
  touch "${BATS_TMPDIR}/other/test.sops.yaml"
  run bash "${VERIFY_SCRIPT}" "${BATS_TMPDIR}/other/test.sops.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Non-canonical" ]]
}

@test "verify-sops-encryption.sh fails on plaintext YAML with .sops.yaml extension" {
  # Setup temporary git repo simulating repo root with canonical path
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  echo "foo: bar" > "${mock_repo}/secrets/credentials.ci.sops.yaml"

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Missing or empty .sops.mac" ]]
}

@test "verify-sops-encryption.sh fails when sops: keyword is only in a comment or key name" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  cat <<'EOF' > "${mock_repo}/secrets/credentials.ci.sops.yaml"
# sops: metadata comment
sops_token: plaintext_value
EOF

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Missing or empty .sops.mac" ]]
}

@test "verify-sops-encryption.sh fails on partially encrypted YAML" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  cat <<'EOF' > "${mock_repo}/secrets/credentials.ci.sops.yaml"
encrypted_field: ENC[AES256_GCM,data:MTIzNDU=,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
plaintext_leak: dangerous_plain_value
sops:
  mac: ENC[AES256_GCM,data:bWFjMTIz,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
  age:
    - recipient: age1znxravd7ehfaqk6reqr7tdr5wrzmx9zw7f3uyhqc9g5mt0wyxsss2jpr2v
EOF

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Unencrypted scalar data found" ]]
}

@test "verify-sops-encryption.sh inspects staged blob: passes valid staged blob even if working copy is unencrypted" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cp "${REPO_ROOT}/secrets/credentials.ci.sops.yaml" "${mock_repo}/secrets/credentials.ci.sops.yaml"
  cd "${mock_repo}"
  git init -q
  git add secrets/credentials.ci.sops.yaml
  # Now overwrite working tree with plaintext
  echo "unencrypted: true" > secrets/credentials.ci.sops.yaml

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -eq 0 ]
}

@test "verify-sops-encryption.sh inspects staged blob: fails unencrypted staged blob even if working copy is encrypted" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  echo "plaintext: leak" > secrets/credentials.ci.sops.yaml
  git add secrets/credentials.ci.sops.yaml
  # Now overwrite working tree with valid encrypted file
  cp "${REPO_ROOT}/secrets/credentials.ci.sops.yaml" "${mock_repo}/secrets/credentials.ci.sops.yaml"

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -ne 0 ]
}

@test ".sops.yaml contains secondary offline age recovery recipient for credentials.sops.yaml" {
  local age_recipients
  age_recipients=$(mise exec -- yq eval '.creation_rules[] | select(.path_regex == "^secrets/credentials\.sops\.ya?ml$") | .key_groups[].age // []' "${REPO_ROOT}/.sops.yaml")
  [ -n "$age_recipients" ]
  [[ "$age_recipients" =~ "age1" ]]
}

@test "verify-sops-encryption.sh fails on empty 0-byte canonical secret file" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  touch "${mock_repo}/secrets/credentials.ci.sops.yaml"
  git add secrets/credentials.ci.sops.yaml

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -ne 0 ]
}

@test "verify-sops-encryption.sh fails when sops.mac is empty string or whitespace" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  cat <<'EOF' > "${mock_repo}/secrets/credentials.ci.sops.yaml"
foo: bar
sops:
  mac: "   "
  age:
    - recipient: age1znxravd7ehfaqk6reqr7tdr5wrzmx9zw7f3uyhqc9g5mt0wyxsss2jpr2v
EOF
  git add secrets/credentials.ci.sops.yaml

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Missing or empty .sops.mac" ]]
}

@test "verify-sops-encryption.sh succeeds with zero arguments on clean repo" {
  run bash "${VERIFY_SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "verify-sops-encryption.sh fails with zero arguments when canonical file has unencrypted secret" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  cat <<'EOF' > "${mock_repo}/secrets/credentials.ci.sops.yaml"
leak: unencrypted_secret
sops:
  mac: ENC[AES256_GCM,data:bWFjMTIz,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
  age:
    - recipient: age1znxravd7ehfaqk6reqr7tdr5wrzmx9zw7f3uyhqc9g5mt0wyxsss2jpr2v
EOF
  cat <<'EOF' > "${mock_repo}/secrets/credentials.sops.yaml"
safe: ENC[AES256_GCM,data:YWJj,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
sops:
  mac: ENC[AES256_GCM,data:bWFjMTIz,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
  pgp:
    - fp: 1234567890ABCDEF1234567890ABCDEF12345678
EOF

  run bash "${VERIFY_SCRIPT}"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "leak" ]]
}

@test "verify-sops-encryption.sh reports exact key paths when unencrypted scalar is present" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  cat <<'EOF' > "${mock_repo}/secrets/credentials.ci.sops.yaml"
nested:
  leak: dangerous_plain_value
  safe: ENC[AES256_GCM,data:MTIzNDU=,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
sops:
  mac: ENC[AES256_GCM,data:bWFjMTIz,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
  age:
    - recipient: age1znxravd7ehfaqk6reqr7tdr5wrzmx9zw7f3uyhqc9g5mt0wyxsss2jpr2v
EOF

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "nested.leak" ]]
}

@test "verify-sops-encryption.sh fails and reports unencrypted int, bool, and float scalars without crashing yq" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  cat <<'EOF' > "${mock_repo}/secrets/credentials.ci.sops.yaml"
app:
  port: 8080
  enabled: true
  ratio: 3.14
  empty_val: null
sops:
  mac: ENC[AES256_GCM,data:bWFjMTIz,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
  age:
    - recipient: age1znxravd7ehfaqk6reqr7tdr5wrzmx9zw7f3uyhqc9g5mt0wyxsss2jpr2v
EOF

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "app.port" ]] || false
  [[ "$output" =~ "app.enabled" ]] || false
  [[ "$output" =~ "app.ratio" ]] || false
  [[ ! "$output" =~ "app.empty_val" ]]
}

@test "verify-sops-encryption.sh passes on encrypted non-string scalars" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  cat <<'EOF' > "${mock_repo}/secrets/credentials.ci.sops.yaml"
app:
  port: ENC[AES256_GCM,data:azFzPQ==,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:int]
  enabled: ENC[AES256_GCM,data:Mmc9PQ==,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:bool]
  ratio: ENC[AES256_GCM,data:M18xNA==,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:float]
sops:
  mac: ENC[AES256_GCM,data:bWFjMTIz,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
  age:
    - recipient: age1znxravd7ehfaqk6reqr7tdr5wrzmx9zw7f3uyhqc9g5mt0wyxsss2jpr2v
EOF

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -eq 0 ]
}

@test "verify-sops-encryption.sh rejects plaintext comments in SOPS file (R2-SEC-04 bypass 1)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  cat <<'EOF' > "${mock_repo}/secrets/credentials.ci.sops.yaml"
# password: leaked_in_comment
token: ENC[AES256_GCM,data:YWJj,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
sops:
  mac: ENC[AES256_GCM,data:bWFjMTIz,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
  age:
    - recipient: age1znxravd7ehfaqk6reqr7tdr5wrzmx9zw7f3uyhqc9g5mt0wyxsss2jpr2v
EOF

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Plaintext comment found" ]]
}

@test "verify-sops-encryption.sh rejects forged ENC prefix with invalid base64 or short iv/tag (R2-SEC-04 bypass 2)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  cat <<'EOF' > "${mock_repo}/secrets/credentials.ci.sops.yaml"
forged: ENC[AES256_GCM,data:notbase64!,iv:x,tag:y,type:str]
sops:
  mac: ENC[AES256_GCM,data:bWFjMTIz,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
  age:
    - recipient: age1znxravd7ehfaqk6reqr7tdr5wrzmx9zw7f3uyhqc9g5mt0wyxsss2jpr2v
EOF

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "forged" ]]
}

@test "verify-sops-encryption.sh rejects unauthorized key under .sops metadata (R2-SEC-04 bypass 3)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  cat <<'EOF' > "${mock_repo}/secrets/credentials.ci.sops.yaml"
token: ENC[AES256_GCM,data:YWJj,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
sops:
  leaked: secret_smuggled_in_sops
  mac: ENC[AES256_GCM,data:bWFjMTIz,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
  age:
    - recipient: age1znxravd7ehfaqk6reqr7tdr5wrzmx9zw7f3uyhqc9g5mt0wyxsss2jpr2v
EOF

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" =~ ".sops.leaked" ]]
}

@test "verify-sops-encryption.sh rejects recipient mismatch against .sops.yaml creation rule (R2-SEC-04 bypass 4)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  cat <<'EOF' > "${mock_repo}/.sops.yaml"
creation_rules:
  - path_regex: ^secrets/credentials\.ci\.sops\.ya?ml$
    key_groups:
      - age:
          - age1znxravd7ehfaqk6reqr7tdr5wrzmx9zw7f3uyhqc9g5mt0wyxsss2jpr2v
          - age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
EOF
  cat <<'EOF' > "${mock_repo}/secrets/credentials.ci.sops.yaml"
token: ENC[AES256_GCM,data:YWJj,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
sops:
  mac: ENC[AES256_GCM,data:bWFjMTIz,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
  age:
    - recipient: age1znxravd7ehfaqk6reqr7tdr5wrzmx9zw7f3uyhqc9g5mt0wyxsss2jpr2v
EOF

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Recipient set" ]]
}

@test "verify-sops-encryption.sh rejects empty string and unencrypted array item outside .sops (R2-SEC-04 bypass 5)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  cat <<'EOF' > "${mock_repo}/secrets/credentials.ci.sops.yaml"
empty_str: ""
items:
  - ENC[AES256_GCM,data:YWJj,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
  - plain_item
sops:
  mac: ENC[AES256_GCM,data:bWFjMTIz,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
  age:
    - recipient: age1znxravd7ehfaqk6reqr7tdr5wrzmx9zw7f3uyhqc9g5mt0wyxsss2jpr2v
EOF

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "empty_str" ]] || false
  [[ "$output" =~ "items.1" ]]
}

@test "verify-sops-encryption.sh rejects custom and explicit YAML tags outside .sops (R2-SEC-04 bypass 6)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  cat <<'EOF' > "${mock_repo}/secrets/credentials.ci.sops.yaml"
tagged_val: !custom secret_value
tagged_null: !!null secret_in_null
sops:
  mac: ENC[AES256_GCM,data:bWFjMTIz,iv:AAAAAAAAAAAAAAAAAAAAAA==,tag:BBBBBBBBBBBBBBBBBBBBBB==,type:str]
  age:
    - recipient: age1znxravd7ehfaqk6reqr7tdr5wrzmx9zw7f3uyhqc9g5mt0wyxsss2jpr2v
EOF

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Custom or explicit YAML tag found" ]] || false
  [[ "$output" =~ "tagged_val" ]] || false
  [[ "$output" =~ "tagged_null" ]]
}

@test ".sops.yaml enforces disjoint CI recipient and exact prod rule structure (R2-SEC-04)" {
  local prod_pgp_count prod_age_count ci_only_in_prod
  prod_pgp_count=$(mise exec -- yq eval '.creation_rules[] | select(.path_regex == "^secrets/credentials\.sops\.ya?ml$") | .key_groups[0].pgp | length' "${REPO_ROOT}/.sops.yaml")
  prod_age_count=$(mise exec -- yq eval '.creation_rules[] | select(.path_regex == "^secrets/credentials\.sops\.ya?ml$") | .key_groups[0].age | length' "${REPO_ROOT}/.sops.yaml")
  [ "$prod_pgp_count" -eq 1 ]
  [ "$prod_age_count" -eq 1 ]

  # The recovery age key is shared, but the CI-only age key must never appear in the prod rule
  ci_only_in_prod=$(mise exec -- yq eval -r '
    (.creation_rules[] | select(.path_regex == "^secrets/credentials\\.sops\\.ya?ml$") | .key_groups[0].age[]) as $prod_age
    | [.creation_rules[] | select(.path_regex == "^secrets/credentials\\.ci\\.sops\\.ya?ml$") | .key_groups[0].age[] | select(. != $prod_age)]
    | length
  ' "${REPO_ROOT}/.sops.yaml")
  [ "$ci_only_in_prod" -eq 1 ]
}

