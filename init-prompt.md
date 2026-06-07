We are scarfolding a new project and want to set up a new git repository. This repository is hosted on github and will use github actions for ci (and maybe eventually for
  cd). Since we are setting everything up from scratch, we have to do things step by step (we don't want to do all tasks at once).

  important: the most important directive is to always follow best practics w.r.t. performance, security, scalability, maintainabiliy, maintainability.

  goal is the following:
  - a repo hosting terraform and ansible. we want to setup things like cloud infrastructure (gcp, oci, cloudflare, etc.) as well as "local" infrastructure like bare-metal or VM
  machines, unifi networks (https://developer.ui.com/network/v10.1.84/quick_start.ansible), cloudflare/gcp functions. and maybe other things that we are not yet aware of.
  - all specific information (like names, ips, ip ranges, etc.) need to be stored separately (i.e. not in e.g. the terraform files itself). those information should never be
  stored in plain text in the git repo or git history. we use env variables (stored encrypted e.g. via git crypt) or some other vault like solution.
  - for ci verification, we use dummy values for those specific information, so we can use ci for verification, but don't expose the actual (sensitive) information publically
  - the ci pipeline should run linting, sanity checks, (unit and integration) tests with the dummy data

  we have multipe tasks to set up (we do those step by step, not all at once):
  - define a best-practices AGENTS.md (for AI/LLM agents) and README.md (for humans/developers) file
  - create pre-commit hooks via lefthook
  - init terraform and ansible
  - create the templates for the ci pipeline
  - additional tasks that you can think of.

  first we want to create a detailed plan and store it to a file (plans are stored in `docs/plans/<yyyy-mm-dd_short-plan-name>.md`. we do not want to execute the plan yet. the
  plan file should contain the tasks and items that need to be completed and checkboxes that will be later used to track the plan execution

  if you have questions, ask, don't assume. before writing the plan, ask follow up questions, to make sure the plan fits the goal.
