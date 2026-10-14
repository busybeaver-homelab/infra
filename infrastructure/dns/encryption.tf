terraform {
  encryption {
    key_provider "pbkdf2" "state_passphrase" {
      passphrase    = var.state_encryption_passphrase
      key_length    = 32
      iterations    = 600000
      hash_function = "sha256"
    }

    method "aes_gcm" "state_method" {
      keys = key_provider.pbkdf2.state_passphrase
    }

    state {
      method   = method.aes_gcm.state_method
      enforced = true
    }

    plan {
      method   = method.aes_gcm.state_method
      enforced = true
    }
  }
}
