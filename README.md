# FuldFokus

**FuldFokus** is a combined World of Warcraft addon that brings together custom guild emotes and a betting system for the **FuldFokus** guild on EU–Draenor.

This addon merges two previously separate addons:
- **FuldFokusEmotes** - Custom guild emotes that extend [Twitch Emotes v2](https://www.curseforge.com/wow/addons/twitch-emotes-v2)
- **FuldStonks** - Guild betting system for raid-related wagers

Maintained by [Eraxter](https://github.com/EraxterCodes).

---

## 📦 Features

### Guild Emotes
- Adds unique **FuldFokus guild emotes** alongside existing Twitch/Discord emotes
- Full integration with:
  - **Chat replacement**: type `:EmoteName:` and see it render
  - **Dropdown menu**: emotes appear under a new `FuldFokus` category
  - **Autocomplete**: start typing `:Em...` and suggestions like `:EmilOk:` will show
- Completely non-invasive: does not override or modify Twitch Emotes v2, only appends
- **Details!** integration for custom profile icons

### Guild Betting System (FuldStonks)
- Create and participate in raid-related bets using in-game gold
- Simple UI for bet creation and management
- Real-time synchronization across guild members
- Decentralized gold trading system (no central bank required)
- Automatic payout calculations
- Bet history tracking

**Commands:**
- `/ff` or `/ffe` - Emote commands (status, test, list, set, sync, clear, size, options)
- `/fs` - FuldStonks betting UI and commands (create, cancel, resolve, sync, help)

---

## 🛠️ Installation

### Option 1: Manual Installation
1. Download the latest release from the [Releases page](https://github.com/EraxterCodes/FuldFokusEmotes/releases).
2. Extract the `.zip` into your WoW `_retail_/Interface/AddOns/` folder.
3. Make sure [Twitch Emotes v2](https://www.curseforge.com/wow/addons/twitch-emotes-v2) is installed and enabled.
4. Enable **FuldFokus** from the AddOn list in-game.

### Option 2: Install via WowUp
1. Open [WowUp](https://wowup.io/).
2. Go to the **Get Addons** tab.
3. Click **Install from URL**.
4. Paste the repository URL: https://github.com/EraxterCodes/FuldFokusEmotes
5. Click **Install**. WowUp will fetch the addon and place it in the correct folder automatically.

---

## 🎮 Usage

### Emotes
Type `/ff help` to see all emote commands:
- `/ff status` - Show current emote selection and settings
- `/ff test` - Test emote rendering in chat
- `/ff list` - List available emotes
- `/ff set <emote>` - Set Details! icon to specific emote
- `/ff size <n>` - Set icon size (8-64)
- `/ff clear` - Reset to defaults
- `/ff options` - Open options panel

### Betting
Type `/fs help` to see all betting commands:
- `/fs` - Toggle betting UI
- `/fs create` - Create a new bet
- `/fs cancel` - Cancel your pending bet
- `/fs resolve` - Resolve a bet you created
- `/fs sync` - Request sync from guild/group
- `/fs peers` - Show connected peers
- `/fs debug` - Toggle debug mode

**How to place a bet:**
1. Open the betting UI with `/fs`
2. Click "Yes" or "No" on an active bet
3. Enter your gold amount
4. Trade the gold to the bet creator
5. Your bet confirms automatically when the trade completes

---

## 🤝 Contributing

### Guild Emotes
For members of **FuldFokus** who want to add guild-specific emotes:

#### Option 1: Pull Request
1. Place the new `.tga` file in `Emotes/FuldFokus/`
   - The image **must** use dimensions that are powers of 2 (e.g. `64x64`, `128x128`)
2. Open `FuldFokus.lua` and add the emote name to the local `EMOTES` list
3. Submit a Pull Request on GitHub

#### Option 2: Discord Submission
Send me a DM on Discord with the image you'd like added.
- Remember: the file **must** have pixel dimensions that are powers of 2 (e.g. `64x64`, `128x128`)

### Betting System
Contributions to the betting system are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly in-game
5. Submit a pull request with detailed description

---

## 📋 Credits

**Emotes:**
All credit for the original Twitch Emotes v2 addon goes to **Ren – Illidan (US)** and **Jons – MirageRaceway (EU)**. This addon simply injects additional emotes into their system.

**Betting System:**
Original FuldStonks addon developed by EraxterCodes for the FuldFokus guild.

---

## 📄 License

This project is open source. Please check the LICENSE file for details.
