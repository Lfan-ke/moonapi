`moonapi` is a typed web framework for MoonBit — routing, request extraction, validation, and OpenAPI generation, in the shape of FastAPI. It sits on `moonasgi` and is served by `mooncat`.

# Working here

- `moon fmt` before anything else. CI runs `moon fmt && git diff --exit-code`, so an unformatted file fails the build on its own.
- `moon check --target all --deny-warn` is the gate. Warnings are errors, and all four backends (wasm, wasm-gc, js, native) must pass.
- `moon test --target all` runs the suite everywhere; there are no target-specific tests.
- `moon info` regenerates `pkg.generated.mbti`. If that file does not change, your edit is not visible to anyone depending on this package, which usually means the refactor was safe. If it does change, read the diff before committing — that is the public interface moving. The examples regenerate their own `.mbti`, which is why those are gitignored.
- CI installs the latest moon on every run, so a toolchain that is behind will disagree with it. Upgrade locally rather than pinning.

# Layout

`app.mbt` holds the router and the `Route` record every builder fills in. Request-side work is split across `validation.mbt` (query, path, JSON body), `multipart.mbt` (form and file uploads), and `endpoint.mbt` (declared parameters and their constraints). The spec side is `openapi.mbt` plus `schema.mbt` and `constraint.mbt`. Security and crypto live in `security.mbt`, `jwt.mbt`, `rsa.mbt`, `ecdsa.mbt`, `ed25519.mbt`. Tests sit beside their subject as `*_wbtest.mbt`; `examples/NN-topic/` are runnable one-file demos.

# Things worth knowing

- Anything inbound is attacker-controlled, so extraction is total: it returns `None` or a lossy decode rather than raising. Keep that property when adding an extractor.
- Query strings are split over the raw bytes and percent/plus-decoded afterwards, so an escaped `&` or `=` inside a value cannot split a pair. The decoder is `decode_component` in `multipart.mbt` — reuse it rather than writing another.
- `openapi.mbt` emits three dialects (Swagger 2.0, OpenAPI 3.0, 3.1) from one `Route` set. A new field on a route has to be given a home in each, or deliberately skipped for the ones that cannot express it.
- `to_asgi` answers all three scopes. Lifespan runs through `lifespan_handler`, moonasgi's synchronous core, which is why boot and teardown are testable on every backend without a server: startup hooks in registration order, shutdown hooks in reverse, and a failed startup ends the run the way ASGI asks. New lifecycle behaviour belongs in that handler, not in the async loop around it.
- The tests compare emitted JSON verbatim. Reordering keys in a generator will fail them; that is deliberate, since the emitted document is what users read.
