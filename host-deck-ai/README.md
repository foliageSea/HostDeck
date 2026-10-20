# HostDeck pi-ai bridge

AI Agent uses `@earendil-works/pi-ai` (pinned to 0.87.1). Dart starts a private
bridge process for each generation/catalog request and exchanges NDJSON via
stdin/stdout. No additional listening port is needed. API keys stay in the
existing encrypted Dart settings store and are passed only via stdin.

Release builds use a Bun-compiled single executable. The Node.js `.mjs` build is
kept for development, tests, and as a fallback.

## Development

Requires Node.js **>=22.19.0** and Bun **>=1.4** for standalone executables:

```sh
cd host-deck-ai
pnpm install --frozen-lockfile
pnpm run build      # dist/bridge.mjs for Node
pnpm run build:bin  # dist/bridge (or bridge.exe) standalone executable
pnpm test
pnpm run test:bin   # run the same bridge tests against the compiled executable
```

Start HostDeck normally afterwards. Rebuild this package after editing its source.
`HOSTDECK_AI_BRIDGE` overrides the bridge path and accepts either the executable
or a `.mjs` script. `HOSTDECK_AI_NODE` only applies to `.mjs` fallback use.
Otherwise Dart prefers `../ai/bridge` beside its binary, then `../ai/bridge.mjs`,
and in development `host-deck-ai/dist/bridge.mjs` before
`host-deck-ai/dist/bridge`.

## Models

The AI settings UI reads pi-ai's bundled catalog. API-key providers using OpenAI
Chat Completions, OpenAI Responses, Anthropic Messages, and Google Gemini are
supported. Custom endpoints can choose any of these four protocols and enter
model IDs manually. The existing endpoint/key/model settings migrate to custom
OpenAI Chat Completions. Provider profiles persist their endpoint, protocol,
configured models, and encrypted API key independently. One provider/model is
active at a time, while the chat model picker can switch directly between every
configured provider without replacing another provider's key. Catalog entries
carry a display `name` alongside each provider `id`. OpenAI Codex also
supports ChatGPT account login as described below. Other providers' OAuth login
and ambient cloud credentials are not exposed by this integration.

The model catalog is a convenience list, not an allowlist. Every provider's
model selector accepts a custom model ID; catalog entries prefill metadata while
an unknown ID uses that provider profile's configured API protocol and Base URL.

The Base URL is the API root, not the generation endpoint (e.g. OpenAI
`https://api.openai.com/v1`, Anthropic `https://api.anthropic.com`, Gemini
`https://generativelanguage.googleapis.com/v1beta`). Selecting a catalog provider
prefills its endpoint. Provider-native assistant blocks/signatures are retained
privately in conversation metadata for subsequent tool rounds and restored chats.
Tools still execute through HostDeck's existing run manager and approvals.

## OpenAI / ChatGPT login

1. In AI Agent settings select **OpenAI Codex（ChatGPT 登录）**.
2. Click **登录 OpenAI**, open the authorization link, and enter the device code.
3. Complete authorization with your ChatGPT account. If requested by OpenAI,
   enable device-code login in the account's security settings.
4. Wait for **已登录**, choose a Codex model, and save the model settings.

Device-code login works with Electron, Docker, and remote B/S deployments; no
localhost callback port is required. Use a ChatGPT account with Codex access.
Closing the dialog stops browser polling but leaves the pending authorization
available when reopened. **取消登录** cancels the pending attempt; **退出登录**
removes the saved local credentials. It does not revoke the account's sessions
at OpenAI or cancel already-running generations.

Access/refresh tokens are encrypted using HostDeck's existing secret store and
stored separately from API keys in `ai_agent_credentials` (schema v20). Status
endpoints return only login progress, device code, and readiness. Before each
Codex generation Dart refreshes credentials expiring within 60 seconds, sharing
one refresh across concurrent requests. A failed refresh keeps the credential
for retry/re-login. A late refresh/login cannot restore credentials after logout.
Codex subscription tokens always use pi-ai's built-in ChatGPT endpoint; custom
Base URLs are not allowed for this provider.

API-key provider profiles are stored in `ai_agent_provider_settings` (schema
v21). Upgrading copies the previous active provider into this table and removes
the duplicate encrypted key from the legacy global settings row. Clearing a key
only affects the selected provider. Model identity is always the compound
`provider + model id`, so providers may configure identical model IDs safely.

## Distribution

`scripts/build_ai.mjs` installs dependencies and compiles a Bun standalone
executable for the current OS/architecture, then copies only
`ai/bridge` (`ai/bridge.exe` on Windows). Node.js and `node_modules` are no
longer shipped at runtime. Set `HOSTDECK_AI_BUN_TARGET` to cross-compile (for
example `bun-linux-arm64`) and `HOSTDECK_AI_BUN` to use a specific Bun binary.

Docker and the Electron build scripts use the same path. Flutter desktop
distributions built manually also need this `ai/` directory next to the
executable (set `HOSTDECK_AI_BRIDGE` if using another layout); the bridge is a
server resource, not a Flutter web asset. Sign the executable on platforms that
require it, such as macOS notarization or Windows code signing.

Verification uses local mock upstream servers; no provider credentials are
required. Live provider access requires configuring a key or completing OpenAI
Codex login in HostDeck. OAuth tests mock OpenAI's device-code/token endpoints;
they do not sign in to a real account.
