using Workerd = import "/workerd/workerd.capnp";

# Serves the same Worker as wrangler.jsonc, but under the workerd binary directly.
# wrangler dev puts its own proxy in front of the runtime, and that hop would be
# charged to Cloudflare in the measurement; this config is what makes the figure
# attributable to workerd itself.
const config :Workerd.Config = (
  services = [ (name = "main", worker = .mainWorker) ],
  sockets = [ (name = "http", address = "127.0.0.1:8793", http = (), service = "main") ],
);

const mainWorker :Workerd.Worker = (
  modules = [ (name = "index.js", esModule = embed "src/index.js") ],
  compatibilityDate = "2025-06-01",
  bindings = [ (name = "LOADER", workerLoader = ()) ],
);
