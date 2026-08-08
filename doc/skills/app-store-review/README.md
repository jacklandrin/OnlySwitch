# App Store Review Guidelines Skill

An AI agent skill that exhaustively evaluates iOS, macOS, tvOS, watchOS, and visionOS app code against **every point** in Apple's App Store Review Guidelines.

**Supports:** Swift, Objective-C, **React Native**, and **Expo** apps

**Current through:** Apple's official June 8, 2026 App Review Guidelines update

## Installation

### Codex

Add this repository as a Codex plugin marketplace:

```bash
codex plugin marketplace add safaiyeh/app-store-review-skill
```

Then open Codex, run `/plugins`, choose the App Store Review marketplace, and install the `app-store-review` plugin. Start a new thread and invoke the skill with `$app-store-review` or ask for an App Store compliance review.

Codex also discovers direct local skills from `~/.agents/skills`, but plugins are the recommended distribution path for reusable skills.

### Claude Code Plugin Marketplace

```bash
/plugin marketplace add safaiyeh/app-store-review-skill
/plugin install app-store-review@app-store-review
```

### skills.sh

```bash
npx skills add safaiyeh/app-store-review-skill
```

## Setup

### Supported AI Agents

This skill works with Codex and AI coding agents that support the skills.sh standard:

- [Codex](https://openai.com/codex/)
- [Claude Code](https://claude.ai/code)
- [Cursor](https://cursor.sh)
- [Windsurf](https://codeium.com/windsurf)
- And other compatible agents

### How It Works

1. **Install the skill** in your project using the command above
2. **Start your AI agent** in the project directory
3. **Ask for an App Store review** - the agent will automatically load relevant guidelines
4. **Review the findings** - the agent identifies potential rejection issues with code references

### Example Prompts

```
"Review this app for App Store compliance"
"Check if my IAP implementation follows Apple's guidelines"
"Audit the privacy and data collection in this React Native app"
"What App Store issues might block my submission?"
```

### Telemetry

The skills CLI collects anonymous usage telemetry. To opt out:

```bash
SKILLS_NO_TELEMETRY=1 npx skills add safaiyeh/app-store-review-skill
```

## Structure

```
app-store-review-skill/
├── .agents/
│   └── plugins/marketplace.json # Codex plugin marketplace
├── .claude-plugin/
│   ├── marketplace.json        # Claude Code plugin marketplace
│   └── plugin.json             # Claude Code plugin manifest
├── .codex-plugin/
│   └── plugin.json              # Codex plugin manifest
├── agents/
│   └── openai.yaml             # Codex UI metadata
├── SKILL.md                    # Index with quick reference & checklist
└── rules/
    ├── 1-safety.md             # Section 1: Safety guidelines
    ├── 2-performance.md        # Section 2: Performance guidelines
    ├── 3-business.md           # Section 3: Business guidelines
    ├── 4-design.md             # Section 4: Design guidelines
    └── 5-legal.md              # Section 5: Legal guidelines
```

## Coverage

This skill covers **ALL 5 major sections** with **EVERY guideline point**:

### [1. Safety](rules/1-safety.md)
- 1.1 Objectionable Content (1.1.1-1.1.7)
- 1.2 User-Generated Content & Creator Content
- 1.3 Kids Category (parental gates, privacy, analytics)
- 1.4 Physical Harm (medical apps, drug dosage, substances)
- 1.5 Developer Information
- 1.6 Data Security
- 1.7 Reporting Criminal Activity

### [2. Performance](rules/2-performance.md)
- 2.1 App Completeness (final versions, IAP)
- 2.2 Beta Testing
- 2.3 Accurate Metadata (2.3.1-2.3.13)
- 2.4 Hardware Compatibility (2.4.1-2.4.5)
- 2.5 Software Requirements (2.5.1-2.5.18)

### [3. Business](rules/3-business.md)
- 3.1 Payments (IAP, subscriptions, external links, crypto)
- 3.1.1-3.1.5 In-App Purchase rules
- 3.2 Other Business Models (acceptable/unacceptable)

### [4. Design](rules/4-design.md)
- 4.1 Copycats
- 4.2 Minimum Functionality
- 4.3 Spam
- 4.4 Extensions (keyboard, Safari)
- 4.5 Apple Sites and Services
- 4.7 Mini Apps, Chatbots, Game Emulators
- 4.8 Login Services
- 4.9 Apple Pay
- 4.10 Monetizing Built-In Capabilities

### [5. Legal](rules/5-legal.md)
- 5.1 Privacy (data collection, use, sharing, health, kids, location)
- 5.2 Intellectual Property
- 5.3 Gaming, Gambling, Lotteries
- 5.4 VPN Apps
- 5.5 Mobile Device Management
- 5.6 Developer Code of Conduct (reviews, developer identity, discovery fraud, app quality)

## Features

- **Modular structure** - Agent loads only relevant sections
- **2000+ lines** of comprehensive guidelines
- **Checklists** for every guideline point
- **Code patterns** for Swift AND React Native/Expo
- **Package references** for both Expo and bare React Native
- **Quick reference** for high-risk rejection patterns
- **Pre-submission checklist** in main SKILL.md

## React Native / Expo Support

Each rule file includes:
- TypeScript/JavaScript code patterns to flag
- Expo package recommendations (preferred)
- Bare React Native package alternatives
- React Native-specific checklists

Key packages covered:
- `react-native-purchases` (RevenueCat — recommended for IAP) / `react-native-iap`
- `expo-tracking-transparency` / `react-native-tracking-transparency`
- `expo-secure-store` / `react-native-keychain`
- `expo-apple-authentication` / `@invertase/react-native-apple-authentication`
- `expo-local-authentication` / `react-native-biometrics`

## What It Checks

### Critical Issues (Immediate Rejection)
- Private API usage
- Hardcoded secrets/credentials
- External payment for digital goods
- On-device cryptocurrency mining
- Dynamic code execution

### High-Risk Issues
- Missing App Tracking Transparency
- Account creation without deletion
- IAP without restore purchases
- UGC without moderation
- UGC without removal workflows or a compliance improvement plan
- Kids apps without parental gates
- Live Activities or push notifications used for spam, phishing, or unsolicited messages

### Medium-Risk Issues
- Vague purpose strings
- Over-requesting permissions
- Unjustified background modes
- References to other platforms
- Custom review prompts instead of the system API

## When It Triggers

The skill activates when working on:
- App Store submission preparation
- Code compliance review
- Payment/StoreKit implementation
- Privacy and data handling
- User-generated content features
- Kids Category apps
- Health/medical apps
- VPN/MDM apps
- Gambling/lottery apps

## License

MIT
