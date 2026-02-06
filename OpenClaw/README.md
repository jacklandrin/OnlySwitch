# OnlySwitch skill for OpenClaw

This folder contains an [OpenClaw](https://openclaw.ai/)-compatible skill that lets you control OnlySwitch with **natural language** via OpenClaw. For example, you can say:

- *"Empty trash"*
- *"Toggle keep awake"*
- *"Turn on dark mode"*
- *"Clear clipboard"*
- *"Mute the mic"*
- *"Clear Xcode derived data"*

OpenClaw will resolve your request to the right OnlySwitch built-in switch or button and open the deeplink `onlyswitch://run?type=builtIn&id=<id>`.

## Prerequisites

- **OnlySwitch** installed and running (so it can handle `onlyswitch://` URLs).
- **OpenClaw** installed and configured.

## How to use this skill with OpenClaw

Load the skill so OpenClaw can see it. Choose one of the following.

### Option A: Extra skill directory (recommended)

Add this repo’s `skills` folder to OpenClaw’s config so it loads the OnlySwitch skill from here (e.g. after cloning the OnlySwitch repo):

1. Open (or create) `~/.openclaw/openclaw.json`.
2. Under `skills.load`, set `extraDirs` to include the path to this repo’s skills:

   ```json
   {
     "skills": {
       "load": {
         "extraDirs": [
           "/path/to/OnlySwitch/OpenClaw/skills"
         ]
       }
     }
   }
   ```

   Replace `/path/to/OnlySwitch` with your actual path (e.g. `~/Developer/OnlySwitch`).

3. Restart OpenClaw (or start a new session). The skill will be eligible on **macOS** only (`darwin`), as set in the skill metadata.

### Option B: Copy into OpenClaw’s managed skills

Copy the skill into OpenClaw’s local skills directory so all your agents can use it:

```bash
cp -R /path/to/OnlySwitch/OpenClaw/skills/onlyswitch-deeplink ~/.openclaw/skills/
```

Again, use your real path to the OnlySwitch repo. OpenClaw loads skills from `~/.openclaw/skills` automatically.

### Option C: Workspace skills

If you run OpenClaw with a workspace that lives inside the OnlySwitch repo, you can put the skill at `<workspace>/skills/onlyswitch-deeplink`. Workspace skills take precedence over managed and bundled skills.

## What the skill does

- **Input:** Natural language (e.g. “empty trash”, “keep awake”, “dark mode”).
- **Behavior:** The agent uses the skill’s reference table to map your phrase to a built-in switch id, then runs:
  `open "onlyswitch://run?type=builtIn&id=<id>"`.
- **Output:** A short confirmation of which OnlySwitch action was triggered.

The list of built-in switches and their ids comes from `Modules/Sources/Switches/SwitchType.swift` in this repo.
