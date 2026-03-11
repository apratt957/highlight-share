const DISCORD_API = 'https://discord.com/api/v10';

export interface Env {
	BOT_TOKEN: string;
	TOKENS: KVNamespace;
}

export interface TokenRecord {
	channelID: string;
	guildID: string;
	userID: string;
	token: string;
	username: string;
	createdAt: number;
}

export default {
	async fetch(request: Request, env: Env): Promise<Response> {
		const url = new URL(request.url);

		if (request.method !== 'POST') {
			return new Response('Use POST', { status: 405 });
		}

		let data: any;
		try {
			data = await request.json();
		} catch {
			return new Response('Invalid JSON', { status: 400 });
		}

		// -----------------------------
		// /register endpoint
		// -----------------------------
		if (url.pathname === '/register') {
			const { token, guildID, channelID, userID, username, createdAt } = data;

			if (!token || !guildID || !channelID || !userID || !username || !createdAt) {
				return new Response('Missing required fields', { status: 400 });
			}

			const list = await env.TOKENS.list({ limit: 1000 });

			// Check if user already has a token for this channel
			for (const key of list.keys) {
				const valueRaw = await env.TOKENS.get(key.name);
				if (valueRaw) {
					const value: TokenRecord = JSON.parse(valueRaw);
					if (value.userID === userID && value.channelID === channelID) {
						return new Response(JSON.stringify({ success: false, error: 'duplicateToken', token: key.name }), {
							status: 400,
							headers: { 'Content-Type': 'application/json' },
						});
					}
				}
			}

			// Store the mapping in KV
			await env.TOKENS.put(token, JSON.stringify({ guildID, channelID, userID, username, createdAt }));

			return new Response(JSON.stringify({ ok: true }), {
				headers: { 'Content-Type': 'application/json' },
			});
		}

		// -----------------------------
		// /quote endpoint
		// -----------------------------
		if (url.pathname === '/quote') {
			const { token, text, title, author } = data;
			const MAX_AGE_MS = 90 * 24 * 60 * 60 * 1000;

			if (!token) {
				return new Response(JSON.stringify({ success: false, error: 'missingToken' }), { status: 400 });
			}

			// Lookup the mapping from KV
			const record = await env.TOKENS.get<TokenRecord>(token, { type: 'json' });
			if (!record || !record.channelID || !record.createdAt) {
				return new Response(JSON.stringify({ success: false, error: 'invalidToken' }), { status: 403 });
			} else if (Date.now() - record.createdAt > MAX_AGE_MS) {
				return new Response(JSON.stringify({ success: false, error: 'expiredToken' }), { status: 403 });
			}

			// Format Discord message
			const isMessage = text && title && author && record.username;
			const message = isMessage ? `\`\`\`\n${record.username} highlighted:\n\n${title}\nby ${author}\n\n${text}\n\`\`\`` : 'No message';

			// Post to Discord
			const discordResp = await fetch(`${DISCORD_API}/channels/${record.channelID}/messages`, {
				method: 'POST',
				headers: {
					Authorization: `Bot ${env.BOT_TOKEN}`,
					'Content-Type': 'application/json',
				},
				body: JSON.stringify({ content: message }),
			});

			if (!discordResp.ok) {
				const err = await discordResp.text();
				return new Response(`Discord API error: ${err}`, { status: 500 });
			}

			return new Response(JSON.stringify({ ok: true }), {
				headers: { 'Content-Type': 'application/json' },
			});
		}

		// -----------------------------
		// /refresh endpoint
		// -----------------------------
		if (url.pathname === '/refresh') {
			const { token, guildID, channelID, userID, username, createdAt } = data;

			if (!token || !guildID || !channelID || !userID || !username || !createdAt) {
				return new Response('Missing required fields', { status: 400 });
			}

			const list = await env.TOKENS.list({ limit: 1000 });

			// Find user's old token
			let oldToken = '';
			for (const key of list.keys) {
				const valueRaw = await env.TOKENS.get(key.name);
				if (valueRaw) {
					const value: TokenRecord = JSON.parse(valueRaw);
					if (value.userID === userID && value.channelID === channelID) {
						oldToken = key.name;
						break;
					}
				}
			}

			//Delete user's old token
			await env.TOKENS.delete(oldToken);

			//Create new token
			await env.TOKENS.put(token, JSON.stringify({ guildID, channelID, userID, username, createdAt }));

			return new Response(JSON.stringify({ ok: true }), {
				headers: { 'Content-Type': 'application/json' },
			});
		}

		return new Response('Unknown endpoint', { status: 404 });
	},
};
