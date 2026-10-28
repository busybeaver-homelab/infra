make_routing_fixture() {
  python3 - "$BATS_TMPDIR" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); roles=['coordinator','implementer','simple','reviewer']
models={'codex':['gpt-6.1-sol','gpt-6.1-terra','gpt-6-luna','gpt-6.1-sol'], 'claude':['opus','sonnet','haiku','opus'], 'antigravity':['pro','flash','flash','pro']}
resolved={'codex':models['codex'], 'claude':['claude-opus-5-5','claude-sonnet-5-5','claude-haiku-5-5','claude-opus-5-5'], 'antigravity':['gemini-4-argon','gemini-3.8-flash','gemini-3.8-flash','gemini-4-argon']}
urls={'codex':['https://learn.chatgpt.com/docs/agent-configuration/subagents'], 'claude':['https://code.claude.com/docs/en/model-config'], 'antigravity':['https://antigravity.google/docs/models/','https://antigravity.google/docs/subagents']}
providers={}
for provider in models:
    entries={}
    for i,role in enumerate(roles):
        entry={'native_model':models[provider][i], 'approved_resolved_models':[resolved[provider][i]], 'source_urls':urls[provider]}
        if provider=='codex': entry['reasoning_effort']='high' if i in (0,3) else 'medium'
        if provider=='antigravity' and i in (0,3): entry['approved_resolved_models'].append('gemini-3.1-pro-preview')
        entries[role]=entry
    providers[provider]={'roles':entries}
(p/'.agent-models.json').write_text(json.dumps({'schema_version':1,'reviewed_on':'2026-10-28','review_after_days':30,'providers':providers}))
def write(path, content):
    f=p/path; f.parent.mkdir(parents=True,exist_ok=True); f.write_text(content)
write('.codex/config.toml','model = "gpt-6.1-sol"\nmodel_reasoning_effort = "high"\n[agents]\nenabled = true\nmax_concurrent_threads_per_session = 1\ndefault_subagent_model = "gpt-6.1-terra"\ndefault_subagent_reasoning_effort = "medium"\n')
write('.claude/settings.json',json.dumps({'model':'opus'}))
write('CLAUDE.md','@AGENTS.md\n')
write('.agents/rules/model-routing.md','---\ntrigger: always_on\n---\nFollow AGENTS.md\n')
for i,role in enumerate(roles):
    if role != 'coordinator':
        write(f'.codex/agents/routing-{role}.toml',f'name = "routing-{role}"\ndescription = "Routing role"\ndeveloper_instructions = "Follow policy"\nmodel = "{models["codex"][i]}"\nmodel_reasoning_effort = "{"high" if i==3 else "medium"}"\n')
        tools='Read, Grep, Glob' if role=='reviewer' else 'Read, Edit, Write'
        write(f'.claude/agents/routing-{role}.md',f'---\nname: routing-{role}\ndescription: Routing role\nmodel: {models["claude"][i]}\ntools: {tools}\n---\nFollow policy\n')
    tools='[view_file, grep_search]' if role=='reviewer' else '[view_file, replace_file_content, run_command]'
    write(f'.agents/agents/routing-{role}.md',f'---\nname: routing-{role}\ndescription: Routing role\nmodel: {models["antigravity"][i]}\ntools: {tools}\nmainAgent: {str(i==0).lower()}\nsubagent: {str(i!=0).lower()}\ncommandExecutionPolicy: sandbox\n---\nFollow policy\n')
PY
}
