<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8.0 |
| <a name="requirement_github"></a> [github](#requirement\_github) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_github"></a> [github](#provider\_github) | ~> 6.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [github_actions_environment_secret.backup_secrets](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_environment_secret) | resource |
| [github_actions_environment_secret.ci_secrets](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_environment_secret) | resource |
| [github_actions_repository_permissions.repo](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_repository_permissions) | resource |
| [github_repository.repo](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository) | resource |
| [github_repository_dependabot_security_updates.repo](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_dependabot_security_updates) | resource |
| [github_repository_deploy_key.deploy_keys](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_deploy_key) | resource |
| [github_repository_environment.backup](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_environment) | resource |
| [github_repository_environment.ci](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_environment) | resource |
| [github_repository_ruleset.main_protection](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_ruleset) | resource |
| [github_repository_vulnerability_alerts.repo](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_vulnerability_alerts) | resource |
| [github_workflow_repository_permissions.repo](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/workflow_repository_permissions) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allow_merge_commit"></a> [allow\_merge\_commit](#input\_allow\_merge\_commit) | Whether to allow merge commits on the repository (must be false to enforce linear trunk-based history). | `bool` | `false` | no |
| <a name="input_allow_rebase_merge"></a> [allow\_rebase\_merge](#input\_allow\_rebase\_merge) | Whether to allow rebase merge on the repository (must be false to enforce squash-merge policy). | `bool` | `false` | no |
| <a name="input_backup_secrets"></a> [backup\_secrets](#input\_backup\_secrets) | A map of sensitive secrets to inject into the 'backup' environment. | `map(string)` | `{}` | no |
| <a name="input_ci_secrets"></a> [ci\_secrets](#input\_ci\_secrets) | A map of sensitive secrets to inject into the 'ci' environment. | `map(string)` | `{}` | no |
| <a name="input_deploy_keys"></a> [deploy\_keys](#input\_deploy\_keys) | A map of deploy keys to register on the repository. | <pre>map(object({<br/>    title     = string<br/>    key       = string<br/>    read_only = bool<br/>  }))</pre> | `{}` | no |
| <a name="input_description"></a> [description](#input\_description) | A description of the repository. | `string` | `""` | no |
| <a name="input_enable_prevent_destroy"></a> [enable\_prevent\_destroy](#input\_enable\_prevent\_destroy) | Whether to prevent destruction of the repository resource (defaults to true for production safety). | `bool` | `true` | no |
| <a name="input_repository_name"></a> [repository\_name](#input\_repository\_name) | The name of the target GitHub repository. | `string` | n/a | yes |
| <a name="input_topics"></a> [topics](#input\_topics) | A list of topics of the repository. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_actions_permissions"></a> [actions\_permissions](#output\_actions\_permissions) | Actions repository permissions. |
| <a name="output_allow_merge_commit"></a> [allow\_merge\_commit](#output\_allow\_merge\_commit) | Whether merge commits are enabled. |
| <a name="output_allow_rebase_merge"></a> [allow\_rebase\_merge](#output\_allow\_rebase\_merge) | Whether rebase merge is enabled. |
| <a name="output_allow_squash_merge"></a> [allow\_squash\_merge](#output\_allow\_squash\_merge) | Whether squash merge is enabled. |
| <a name="output_delete_branch_on_merge"></a> [delete\_branch\_on\_merge](#output\_delete\_branch\_on\_merge) | Whether head branches are automatically deleted upon merge. |
| <a name="output_deploy_keys"></a> [deploy\_keys](#output\_deploy\_keys) | Managed deploy keys. |
| <a name="output_environments"></a> [environments](#output\_environments) | Managed GitHub Actions environments. |
| <a name="output_repository_git_clone_url"></a> [repository\_git\_clone\_url](#output\_repository\_git\_clone\_url) | The URL that can be provided to git clone over HTTPS. |
| <a name="output_repository_html_url"></a> [repository\_html\_url](#output\_repository\_html\_url) | The HTML URL of the managed GitHub repository. |
| <a name="output_repository_name"></a> [repository\_name](#output\_repository\_name) | The name of the managed GitHub repository. |
| <a name="output_repository_node_id"></a> [repository\_node\_id](#output\_repository\_node\_id) | The GraphQL Node ID of the managed GitHub repository. |
| <a name="output_repository_ssh_clone_url"></a> [repository\_ssh\_clone\_url](#output\_repository\_ssh\_clone\_url) | The URL that can be provided to git clone over SSH. |
| <a name="output_ruleset_enforcement"></a> [ruleset\_enforcement](#output\_ruleset\_enforcement) | Enforcement level of the main branch ruleset. |
<!-- END_TF_DOCS -->
