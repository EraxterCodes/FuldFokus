# FuldFokus

FuldFokus is a combined World of Warcraft addon that includes:
1. **FuldFokus Emotes** - Custom guild emotes integrated with TwitchEmotes
2. **FuldStonks** - Guild betting system for raid-related wagers

Maintained by [Eraxter](https://github.com/EraxterCodes) for the guild **FuldFokus** on EU–Draenor.

---

## 📦 Features

### FuldFokus Emotes
- Adds unique **FuldFokus guild emotes** alongside existing Twitch/Discord emotes
- Full integration with [Twitch Emotes v2](https://www.curseforge.com/wow/addons/twitch-emotes-v2)
  - **Chat replacement**: type `:EmoteName:` and see it render
  - **Dropdown menu**: emotes appear under a new `FuldFokus` category
  - **Autocomplete**: start typing `:Em...` and suggestions like `:EmilOk:` will show
- Completely non-invasive: does not override or modify Twitch Emotes v2, only appends
- **Note**: Details integration has been removed as of the Midnight prepatch update

### FuldStonks (Guild Betting System)
- Create betting pools on raid outcomes (e.g., "Will we one-shot the boss?")
- Place wagers using in-game gold through direct trades
- Automatic payout calculations with proportional winnings
- State-based peer-to-peer synchronization for seamless multi-player experience
- Full bet history and inspection system
- Commands: `/fs` or `/FuldStonks`

---

## 🛠️ Installation

### Option 1: Manual Installation
1. Download the latest release from the [Releases page](https://github.com/EraxterCodes/FuldFokusEmotes/releases)
2. Extract the `.zip` into your WoW `_retail_/Interface/AddOns/` folder
3. The addon folder should be named `FuldFokus`
4. Make sure [Twitch Emotes v2](https://www.curseforge.com/wow/addons/twitch-emotes-v2) is installed and enabled (required for emotes)
5. Enable **FuldFokus** from the AddOn list in-game

### Option 2: Install via WowUp
1. Open [WowUp](https://wowup.io/)
2. Go to the **Get Addons** tab
3. Click **Install from URL**
4. Paste the repository URL: https://github.com/EraxterCodes/FuldFokusEmotes
5. Click **Install**

---

## 💻 Usage

### FuldFokus Emotes Commands
- `/ffe help` - Show help message
- `/ffe list` - Show where emotes are located
- `/ffe options` - Open the emote options panel

Emotes are automatically integrated into TwitchEmotes and accessible via the emote menu.

### FuldStonks Commands
- `/fs` or `/FuldStonks` - Toggle main betting UI
- `/fs help` - Show help message
- `/fs create` - Create a new bet
- `/fs pending` - Show pending bets (bet creator only)
- `/fs cancel` - Cancel your pending bet
- `/fs resolve` - Resolve a bet you created
- `/fs sync` - Request sync from guild/group
- `/fs peers` - Show connected peers
- `/fs debug` - Toggle debug mode
- `/fs showhidden` - Show list of hidden bets
- `/fs unhideall` - Unhide all hidden bets

---

## 🎮 How FuldStonks Works

### Creating a Bet
1. Click "Create Bet" button or type `/fs create`
2. Enter your bet question (e.g., "Will Oscar stand in fire?")
3. Click "Create" - bet syncs to all guild members instantly

### Placing a Bet
1. Open main UI and see active bets
2. Click "Yes" or "No" button on a bet
3. Enter gold amount in dialog
4. Trade the gold to the bet creator (shown in message)
5. Bet confirms automatically when trade completes

### As Bet Creator
- You can participate in your own bet (no trade required)
- Use "Inspect" to see who owes you gold (pending bets)
- Use "Resolve" to resolve your bet when outcome is known
- Review payout preview before confirming resolution

---

## 📋 Contributing

### Emotes
For members of **FuldFokus** who want to add guild-specific emotes:

#### Option 1: Pull Request
1. Place the new `.tga` file in `Emotes/FuldFokus/`
   - The image **must** use dimensions that are powers of 2 (e.g. `64x64`, `128x128`)
2. Open `FuldFokusEmotes.lua` and add the emote name to the local `EMOTES` list
3. Submit a Pull Request on GitHub

#### Option 2: Discord Submission
Send me a DM on Discord with the image you'd like added.
- Remember: the file **must** have pixel dimensions that are powers of 2 (e.g. `64x64`, `128x128`)

### FuldStonks
Contributions to the betting system are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly in-game
5. Submit a pull request with detailed description

---

## 📝 Credits

- **Emotes**: Original addon concept and TwitchEmotes integration by **Ren – Illidan (US)** and **Jons – MirageRaceway (EU)**. FuldFokus emotes added by Eraxter.
- **FuldStonks**: Designed and developed by Eraxter for the FuldFokus guild.

---

## 🔗 Links

- [CurseForge Page](https://www.curseforge.com/wow/addons/fuldfokusemotes)
- [Wago.io Page](https://addons.wago.io/addons/fuldfokusemotes)
- [GitHub Issues](https://github.com/EraxterCodes/FuldFokusEmotes/issues)
