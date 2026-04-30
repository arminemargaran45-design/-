const express = require('express');
const { Telegraf } = require('telegraf');

const bot = new Telegraf(process.env.BOT_TOKEN);

const app = express();

bot.start((ctx) => ctx.reply('Бот работает 🚀'));

app.use(bot.webhookCallback('/bot'));

const PORT = process.env.PORT || 3000;

app.listen(PORT, async () => {
  console.log('Server started');
  await bot.telegram.setWebhook(`${process.env.DOMAIN}/bot`);
});
