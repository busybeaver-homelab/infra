provider "sops" {}

provider "nextdns" {
  alias   = "account_1"
  api_key = local.account_api_keys["account_1"]
}

provider "nextdns" {
  alias   = "account_2"
  api_key = local.account_api_keys["account_2"]
}

provider "nextdns" {
  alias   = "account_3"
  api_key = local.account_api_keys["account_3"]
}

provider "nextdns" {
  alias   = "account_4"
  api_key = local.account_api_keys["account_4"]
}

provider "nextdns" {
  alias   = "account_5"
  api_key = local.account_api_keys["account_5"]
}
