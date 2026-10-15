data "sops_file" "secrets" {
  source_file = var.secrets_file_path
}

module "account_1" {
  source = "./modules/profile"
  providers = {
    nextdns = nextdns.account_1
  }

  profile_name           = local.effective_accounts["account_1"].profile_name
  enable_prevent_destroy = var.enable_prevent_destroy
  security               = local.effective_accounts["account_1"].security
  privacy                = local.effective_accounts["account_1"].privacy
  parental_control       = local.effective_accounts["account_1"].parental_control
  settings               = local.effective_accounts["account_1"].settings
  rewrites               = local.effective_accounts["account_1"].rewrites
  allowlist              = local.effective_accounts["account_1"].allowlist
  denylist               = local.effective_accounts["account_1"].denylist
}

module "account_2" {
  source = "./modules/profile"
  providers = {
    nextdns = nextdns.account_2
  }

  profile_name           = local.effective_accounts["account_2"].profile_name
  enable_prevent_destroy = var.enable_prevent_destroy
  security               = local.effective_accounts["account_2"].security
  privacy                = local.effective_accounts["account_2"].privacy
  parental_control       = local.effective_accounts["account_2"].parental_control
  settings               = local.effective_accounts["account_2"].settings
  rewrites               = local.effective_accounts["account_2"].rewrites
  allowlist              = local.effective_accounts["account_2"].allowlist
  denylist               = local.effective_accounts["account_2"].denylist
}

module "account_3" {
  source = "./modules/profile"
  providers = {
    nextdns = nextdns.account_3
  }

  profile_name           = local.effective_accounts["account_3"].profile_name
  enable_prevent_destroy = var.enable_prevent_destroy
  security               = local.effective_accounts["account_3"].security
  privacy                = local.effective_accounts["account_3"].privacy
  parental_control       = local.effective_accounts["account_3"].parental_control
  settings               = local.effective_accounts["account_3"].settings
  rewrites               = local.effective_accounts["account_3"].rewrites
  allowlist              = local.effective_accounts["account_3"].allowlist
  denylist               = local.effective_accounts["account_3"].denylist
}

module "account_4" {
  source = "./modules/profile"
  providers = {
    nextdns = nextdns.account_4
  }

  profile_name           = local.effective_accounts["account_4"].profile_name
  enable_prevent_destroy = var.enable_prevent_destroy
  security               = local.effective_accounts["account_4"].security
  privacy                = local.effective_accounts["account_4"].privacy
  parental_control       = local.effective_accounts["account_4"].parental_control
  settings               = local.effective_accounts["account_4"].settings
  rewrites               = local.effective_accounts["account_4"].rewrites
  allowlist              = local.effective_accounts["account_4"].allowlist
  denylist               = local.effective_accounts["account_4"].denylist
}

module "account_5" {
  source = "./modules/profile"
  providers = {
    nextdns = nextdns.account_5
  }

  profile_name           = local.effective_accounts["account_5"].profile_name
  enable_prevent_destroy = var.enable_prevent_destroy
  security               = local.effective_accounts["account_5"].security
  privacy                = local.effective_accounts["account_5"].privacy
  parental_control       = local.effective_accounts["account_5"].parental_control
  settings               = local.effective_accounts["account_5"].settings
  rewrites               = local.effective_accounts["account_5"].rewrites
  allowlist              = local.effective_accounts["account_5"].allowlist
  denylist               = local.effective_accounts["account_5"].denylist
}
