// Three paths measured from outside the runtime, because Workers coarsens its own
// clock (Date.now/performance.now do not advance during synchronous execution), so
// microsecond timing has to come from the client. /baseline is the loopback HTTP
// floor to subtract; the other two differ only by whether the loader's isolate cache
// is hit.
const SANDBOX = `export default {
  fetch(req, env, ctx) { return new Response("42") }
}`

const load = (env, id) =>
  env.LOADER.get(id, async () => ({
    compatibilityDate: "2025-06-01",
    mainModule: "sandbox.js",
    modules: { "sandbox.js": SANDBOX },
    env: {},
    globalOutbound: null,
  }))

export default {
  async fetch(req, env) {
    const path = new URL(req.url).pathname

    if (path === "/baseline")
      return new Response("42")

    if (path === "/warm" || path === "/cold") {
      // A fixed id reuses the cached isolate; a fresh id forces a new one.
      const id = path === "/warm" ? "fixed" : crypto.randomUUID()
      const res = await load(env, id).getEntrypoint().fetch("http://sandbox/")
      return new Response(await res.text())
    }

    return new Response("?", { status: 404 })
  },
}
