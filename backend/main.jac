# CareGraph backend entry — serve with: jac start main.jac --no_client -p 8000
# (from backend/ so jac.toml + seed_data.json + ./.jac/data resolve here).

include schema;
include llm;
include walkers_core;
include walkers_reports;
