# highlight-share

A KOReader plugin that lets you send book highlights directly to a Discord channel. Select text on your e-reader, tap "Send to Discord", and the quote appears in your server.

## How it works

```
KOReader plugin  →  Cloudflare Worker  →  Discord bot  →  Discord channel
```

1. A Discord bot issues tokens to users via slash commands
2. The user enters their token in the KOReader plugin settings
3. When a highlight is sent, the plugin POSTs to a Cloudflare Worker
4. The Worker validates the token and forwards the quote to Discord via the bot

---

## Setup

There are three components to set up: the Discord bot, the Cloudflare Worker, and the KOReader plugin.

### 1. Discord bot

**Create the bot**

1. Go to [discord.com/developers](https://discord.com/developers/applications) and create a new application
2. Under **Bot**, create a bot and copy the token
3. Under **OAuth2**, copy the Client ID
4. Enable the `applications.commands` and `bot` scopes, and invite the bot to your server
5. Copy the ID of the Discord channel you want highlights posted in (right-click channel → Copy Channel ID)

**Configure**

Create `bot/.env` from the example:

```bash
cp bot/.env.example bot/.env
```

Fill in your values:

```env
BOT_TOKEN=your_discord_bot_token
WORKER_URL=https://your-worker.your-subdomain.workers.dev
CLIENT_ID=your_discord_app_client_id
GUILD_ID=your_discord_server_id
```

**Run**

```bash
cd bot
npm install
node bot.js
```

For persistent hosting, run this on a VPS or any always-on machine using something like `pm2` or a systemd service.

---

### 2. Cloudflare Worker

**Prerequisites:** A [Cloudflare account](https://cloudflare.com) and [Wrangler CLI](https://developers.cloudflare.com/workers/wrangler/) installed.

**Create a KV namespace**

```bash
cd worker
wrangler kv namespace create TOKENS
```

Copy the `id` from the output and paste it into `wrangler.jsonc` under the top-level `kv_namespaces`:

```jsonc
"kv_namespaces": [
  {
    "binding": "TOKENS",
    "id": "your-kv-namespace-id-here"
  }
]
```

**Set the bot token secret**

```bash
wrangler secret put BOT_TOKEN
```

Paste your Discord bot token when prompted. This keeps it out of your config files.

**Deploy**

```bash
npm install
wrangler deploy
```

Copy the worker URL from the output (e.g. `https://your-worker.your-subdomain.workers.dev`) and add it to `bot/.env` as `WORKER_URL`.

**Local development**

```bash
wrangler dev --env dev
```

This uses the `dev` KV namespace defined in `wrangler.jsonc` so your production data stays untouched.

---

### 3. KOReader plugin

**If you're self-hosting the worker**, update the URL at the top of `highlightshare.koplugin/main.lua`:

```lua
local worker_url = "https://your-worker.your-subdomain.workers.dev/quote"
```

**Install the plugin**

Copy the `highlightshare.koplugin` folder to your KOReader plugins directory:

```
/path/to/koreader/plugins/highlightshare.koplugin/
```

The plugins directory location varies by device — on Kindle it's typically `/mnt/us/koreader/plugins/`, on Kobo `/mnt/onboard/.adds/koreader/plugins/`.

**Get a token**

In your Discord server, run `/token` in any channel the bot has access to. The bot will reply with a token (only visible to you).

**Enter the token in KOReader**

Go to the KOReader menu → **Highlight Share Token**, enter the token from Discord, and tap Save.

---

## Usage

Select any text while reading. In the highlight dialog you'll see two new options:

- **Highlight and Send to Discord** — saves the highlight in KOReader and posts it to Discord
- **Send to Discord** — posts to Discord without saving the highlight locally

The quote will appear in the Discord channel formatted as:

```
username highlighted:

Book Title
by Author Name

Selected text here
```

**Token expiry**

Tokens expire after 90 days. Run `/refresh` in Discord to get a new one, then update it in the KOReader plugin settings.

---

## Project structure

```
├── bot/                        # Discord bot (Node.js)
│   ├── bot.js
│   ├── .env.example
│   └── package.json
├── worker/                     # Cloudflare Worker (TypeScript)
│   ├── src/index.ts
│   ├── wrangler.jsonc
│   └── package.json
└── highlightshare.koplugin/    # KOReader plugin (Lua)
    ├── main.lua
    └── _meta.lua
```
