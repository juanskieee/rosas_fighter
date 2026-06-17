# Rosas Fighter: 2D Action Game

> A 2D fighter game built in Godot 4 featuring dynamic combat animations, a health system, collectibles, and AI-assisted game elements.

![Godot](https://img.shields.io/badge/Godot_4-478CBF?style=flat&logo=godot-engine&logoColor=white)
![GDScript](https://img.shields.io/badge/GDScript-478CBF?style=flat&logo=godot-engine&logoColor=white)

---

## Overview

Rosas Fighter is a 2D action game developed as the final output for COSC-106 Game Development. Built using Godot 4 and GDScript, the project follows standard Godot conventions by organizing assets by type and scripts by functionality. It features a playable character (Leni) with a full set of combat animations, a health bar system, collectible coins, and level-specific maps.

---

## Key Features

- **Dynamic Combat** — Full character state machine covering Idle, Run, Jump, Slash, Thrust, Spellcast, Hurt, and Death animations.
- **Health and Status System** — Comprehensive health bar UI with standard, pulse, and syringe-style visual variations in both horizontal and vertical layouts.
- **Collectibles** — In-game coin system with unique sprites, textures, and a coin counter UI.
- **Dialogue System** — Scene-based dialogue system integrated into the game's level scenes.
- **AI Integration** — Uses the AI Assistant Hub addon for procedural and AI-assisted game development support.
- **Sound Effects** — Audio assets for jump, slash, run, and other in-game actions.

---

## Technical Implementation

| Layer | Technology |
|---|---|
| Engine | Godot 4 |
| Scripting | GDScript |
| Scene Format | `.tscn` (Godot scene files) |
| Version Control | Git with Godot-specific `.gitignore` |

---

## Project Structure

```
/
├── ASSETS/
│   ├── COINS/             # Sprites and textures for collectible coins
│   ├── HEALTH BARS/       # Health bar UI assets (standard, pulse, syringe variants)
│   ├── LENI/              # Character animations (slash, shoot, run, jump, idle, etc.)
│   └── SFX/               # Audio files for in-game actions
├── SCENES/                # .tscn files for game levels, coin counter, and dialogue UI
├── SCRIPTS/               # GDScript logic for player behavior, spawners, and UI
└── addons/
    └── AI Assistant Hub/  # AI plugin for development assistance
```

---

## How to Run

1. **Install Godot 4** — Download and install Godot 4 from [godotengine.org](https://godotengine.org).
2. **Open Project** — Launch Godot and open the project folder.
3. **Run** — Press `F5` or click the Play button to launch the game.

---

## Credits

Developed by **Juan Carlos Garcia** for COSC-106 Game Development.
