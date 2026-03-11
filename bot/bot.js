require("dotenv").config();

const {
  Client,
  GatewayIntentBits,
  REST,
  MessageFlags,
  Routes,
} = require("discord.js");
const crypto = require("crypto");

const BOT_TOKEN = process.env.BOT_TOKEN;
const WORKER_URL = process.env.WORKER_URL;
const CLIENT_ID = process.env.CLIENT_ID;
const GUILD_ID = process.env.GUILD_ID;

const client = new Client({ intents: [GatewayIntentBits.Guilds] });

function generateToken(length = 8) {
  const bytes = crypto.randomBytes(length);
  const chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  let token = "";
  for (let i = 0; i < length; i++) {
    token += chars[bytes[i] % chars.length];
  }
  return token;
}

client.once("clientReady", () => {
  console.log(`Logged in as ${client.user.tag}`);
});

// Register /token command
const commands = [
  { name: "token", description: "Get your highlight token" },
  { name: "refresh", description: "Get a new token that isn't expired" },
];
const rest = new REST({ version: "10" }).setToken(BOT_TOKEN);
(async () => {
  await rest.put(Routes.applicationCommands(CLIENT_ID, GUILD_ID), {
    body: commands,
  });
})();

client.on("interactionCreate", async (interaction) => {
  if (!interaction.isChatInputCommand()) return;

  if (interaction.commandName === "token") {
    await interaction.deferReply({ flags: MessageFlags.Ephemeral });

    const payload = {
      token: generateToken(),
      guildID: interaction.guildId,
      channelID: interaction.channelId,
      userID: interaction.user.id,
      username: interaction.user.username,
      createdAt: Date.now(),
    };

    const res = await fetch(`${WORKER_URL}/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    const parsedResponse = await res.json();

    if (parsedResponse.error === "duplicateToken") {
      return interaction.editReply(
        `Your token is: \`${parsedResponse.token}\`\n\nPlease navigate to "Highlight Share Token" in koreader's menu and enter the token to share your highlights!`,
      );
    }

    if (!res.ok) {
      return interaction.editReply("Failed to register token.");
    }

    await interaction.editReply(
      `Your token is: \`${payload.token}\`\n\nPlease navigate to "Highlight Share Token" in koreader's menu and enter the token to share your highlights!`,
    );
  } else if (interaction.commandName === "refresh") {
    await interaction.deferReply({ flags: MessageFlags.Ephemeral });

    const payload = {
      token: generateToken(),
      guildID: interaction.guildId,
      channelID: interaction.channelId,
      userID: interaction.user.id,
      username: interaction.user.username,
      createdAt: Date.now(),
    };

    const res = await fetch(`${WORKER_URL}/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!res.ok) {
      return interaction.editReply("Failed to register token.");
    }

    await interaction.editReply(
      `Your new token is: \`${payload.token}\`\n\nPlease navigate to "Highlight Share Token" in koreader's menu and enter the token to share your highlights!`,
    );
  }
});

client.login(BOT_TOKEN);
