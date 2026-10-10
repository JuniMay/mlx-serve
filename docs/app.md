[English](app.md) · [简体中文](zh-CN/app.md)

# MLX Core (macOS app)

Menu-bar app that wraps the server with a full UI. [Download the latest release](https://github.com/ddalcu/mlx-serve/releases/latest) or `brew install --cask mlx-serve`. Chat, media generation, models, agents and tasks share one main window and a stable sidebar. Settings opens in its own resizable window from the app menu or **⌘,**.

- **Model browser** — download from HuggingFace with resumable multi-connection transfers (up to 16 connections per file), auto-discovers LM Studio's existing model folder (`~/.lmstudio/settings.json`) and your Hugging Face cache (wherever `HF_HOME` / `HF_HUB_CACHE` point) so you don't re-download what's on disk, GGUF rows show a min–max RAM-estimate range. Multi-variant repos let you pick your quant, and **Settings ▸ Model Folders** chooses where downloads land.
- **Model switching without a restart** — picking a chat model loads it into the running server and makes it the default (`POST /v1/load-model` with `"default": true` over the API).
- **Chat interface** — multi-session chat with markdown rendering. Drop in PDFs (PDFKit-extracted) or images alongside text.
- **Tool-enabled chat** — built-in tools for files, shell commands, web access, media, memory and tasks, with an automatic tool calling loop and a per-tool approval dialog (**Allow** / **Deny** / **Always allow this session**). Configure defaults in **Settings ▸ Tools & MCP**; use the composer's **Tools & MCP** popover to change them for one conversation or turn on **Plain Chat**.
- **Agents** — named assistants with their own personality, voice, model, tools, workspace and wake phrase, plus their own pinned sampling (temperature, top-p, top-k, penalties, reasoning budget). The app can write the persona prompt for you. Use an agent in chat, hands-free voice or scheduled tasks.
- **MCP client** — curated marketplace of stdio + HTTP MCP servers (GitHub, Azure DevOps, DBHub, Docker, Kubernetes, Playwright, Slack, Notion, Filesystem, Shell) plus your own from `~/.mlx-serve/mcp.json`.
- **Agent Sandbox** — run agent shell commands in a Linux VM through Apple's Virtualization framework. Workspace folders are shared with the guest, so changes there affect the real files on your Mac. With guest networking enabled, listening guest ports are available through localhost. The direct-distribution build can also run host commands; the App Store build requires guest execution.
- **Hands-free Voice Mode** — on-device speech recognition, spoken replies, interruption and agent tools from the menu bar. Replies use the macOS system voice by default. Settings ▸ Voice also offers Kokoro voices and Qwen3-TTS voice cloning. A new installation has no wake phrase: choose one or turn off **Require Wake Phrase** before starting. Agents can supply their own phrase.
- **LAN Sharing** — share chosen models with the other Macs in your house and use theirs: peers appear automatically, shared models show up in the tray and every generation pane as "model · peer", and requests stream to the Mac that hosts the weights — chat, image, speech, music, video, and 3D alike, with models loading on demand on the host. Configure publishing in Settings ▸ LAN Sharing and discovery in Settings ▸ Providers ▸ Nearby Macs. Prompts sent to a shared model run on and are visible to the hosting Mac.
- **Scheduled tasks** — hand the agent a goal and a schedule in plain English ("weekdays at 8am, check my watched sites and write a briefing") and it runs unattended, with saved transcripts.
- **Document folder RAG** — attach a folder of mixed files and ask questions about them; GPU-batched embeddings index ~500 files in ~7 s, everything in memory, nothing leaves the Mac.
- **Editable system prompt + persistent memory** — `~/.mlx-serve/system-prompt.md` and `~/.mlx-serve/memory.md`.
- **Prompt-based skills** — drop `.md` files into `~/.mlx-serve/skills/` with YAML frontmatter to teach the agent custom capabilities triggered by keywords, or type `/` in the chat box to pick one and run it by name in any chat, whether tools are enabled or not.
- **Engine-aware Settings window** (⌘,) — a category sidebar and grouped controls for server-launch flags and per-request defaults, showing the options relevant to your loaded engine (MLX vs GGUF vs ds4). Information buttons beside setting names explain the controls. Cache and Performance have separate sections; Neural Engine controls are in Performance. Appearance contains Text Size. Search includes setting names and their help text.
- **Server management** — start/stop, live log buffer, restart-on-flag-change banner and version details in **Settings ▸ About MLX-Serve**.
- **Image / Video / Music / Speech / Sound / 3D generation** — FLUX.2, Krea-2, Mage-Flow, LTX-Video 2.3 / 2.5, MiniMax-H3, ACE-Step, MiniMax Music 3, Qwen3-TTS, Kokoro, Stable Audio 3 and Hunyuan3D, all through the native server.

## Interaction workspaces

Use **New** in the sidebar to start an interaction. Choose a model from the dock or with **⌘L**. Supported local models open the
workspace for their capability: chat, image, video, voice, music, sound or 3D.
Decision models open their decision interface. Media selection keeps chat model
selection separate and does not start generation. The model browser remains the
place to find and download models. Network media models are available from each
media workspace's model popover.

Generation workspaces put results above a floating input dock in the same centered column. The dock contains
the prompt, model picker, supported attachments and Generate or Cancel. Open
**Generation settings** in the toolbar for the current model's quality, size, sampler and other
parameters. The trailing inspector starts closed and keeps input and output
visible when opened. The attachment and model popovers preserve model-specific inputs
and download controls. Voice, Music and Sound keep their own input requirements.
The Audio toolbar switches between these three workspaces. Prompt action menus
provide templates and enhancement where supported.

Chat and media share the editor's font and insets, model-pill styling and circular
attachment and action controls. Media prompts grow as you type, then scroll
within a bounded area. Return inserts a newline; **⌘Return** starts generation
when the required inputs are ready.

Changing the model within a workspace preserves its draft inputs. Model defaults
and capability limits still apply to generation parameters.

The sidebar stays in place when opening Models, Agents or Tasks. Their lists and
page controls occupy the main pane. App-wide server, engine, tool and appearance
preferences stay in **Settings**; parameters for the current generation stay with
that workspace.

Terminal sessions appear alongside conversations and remain running when you switch
workspaces. A host session runs its coding agent on macOS; a sandbox session
connects to the Linux guest. The terminal pane shows the session's workspace and
provides its session controls.

## Chat controls and tool defaults

Click the model control in the composer to open thinking settings. The first page has one **Off / Low / Medium / High** slider: Off disables thinking, and choosing an effort level enables it. The app remembers thinking and effort for each model; **Settings ▸ Generation Defaults** manages these saved choices. Reset turns thinking off and returns that model's remembered effort to Low. Click the current model name to open **Select model** in the same popover, and **Back** to return. The list includes available local, LAN, provider and Apple on-device models. Opening the picker does not load a model; when the server is stopped, use **Start** in the same control to start it.

**Settings ▸ Tools & MCP** controls the built-in tool and MCP defaults for new conversations. Expand the tool groups to choose which built-in tools are available, and use **Configure…** to manage MCP servers. Saved agents retain their own tool capabilities and MCP choice; individual tool exclusions can further restrict their available tools, but cannot grant a capability the agent excludes. Scheduled tasks keep their own tool settings, and tool approval rules still apply.

The composer's **Tools & MCP** popover provides separate Tools and MCP switches for the conversation. These switches override Settings defaults within the saved agent's capabilities. Turning a switch off applies to upcoming tool calls. **Use Settings Defaults** clears these overrides while preserving the Plain Chat choice.

**Plain Chat** disables built-in tools, MCP and attached-folder search for that conversation, including conversations with saved agents. Turning it off uses the conversation's saved choices or current Settings defaults again. Thinking remains a separate preference: when an agent fixes its value, the popover names that agent and links to its settings. Apple's on-device model has no thinking or MCP support and limits built-in tools to browsing and web search.

The main window uses a native title bar. Conversations show their title and a
**Conversation actions** menu with Rename and Branch Chat. Branch Chat uses
the latest completed conversation boundary and is unavailable during a turn.
The sidebar and detail pane share the window toolbar.

Thinking and tool headers use quiet gray text that darkens on hover or press.
A chevron beside the label shows whether the details are expanded. The header
stays outside the details frame, whose content scrolls within a 240-point height
limit. Detail text follows the conversation's **Text Size** setting, including
in the larger Reader; code and tool identifiers can retain a monospaced face.
**Open in Reader** provides the full text, Copy and Close; Escape closes it.
Reader and background-process Stop buttons act independently of the header.
Plans keep approval actions outside the scrolling content.

The conversation and composer share a centered reading column. Custom message
surfaces use shared corner and spacing values; native controls keep their
system shape. Tables use horizontal row dividers, and numbered lists align
their text across single- and multi-digit markers.

For model formats, context sizing and speculative decoding, see
[Models and runtime settings](models-and-runtime.md).

## Image / Video / Music / Speech / Sound / 3D generation

The **Image**, **Video**, **Audio** (speech, music and sound) and **3D** workspaces run [FLUX.2](https://huggingface.co/black-forest-labs) / Krea-2 / Microsoft Mage-Flow, [LTX-Video 2.3 and 2.5](https://github.com/dgrauet/ltx-2-mlx) / [MiniMax-H3](https://huggingface.co/ddalcu/MiniMax-H3-FL2VA-MLX-Serve-8bit), [ACE-Step 1.5](https://huggingface.co/ddalcu/ACE-Step-1.5-XL-Turbo-MLX-Serve-8bit) / MiniMax Music 3, [Qwen3-TTS](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-Base) / [Kokoro-82M](https://huggingface.co/ddalcu/Kokoro-82M-MLX-Serve), Stable Audio 3, and [Hunyuan3D-2.1](https://huggingface.co/ddalcu/Hunyuan3D-2.1-MLX-Serve-8bit) natively on MLX. Choose a model in its popover. If it is unavailable, use the explicit Download action. Open the attachment popover to choose or drop supported reference files into their slots. Each pane remembers your last-used model, quality, resolution, steps and seed between sessions.

The panes also list checkpoints you added yourself: anything in your model folders with a family the server can run shows under **On This Mac** with that family's controls, and the Model Browser offers community packs of those families, layout-checked before the Download button appears.

With the relevant media tools enabled, you can also **generate media straight from chat**: ask for an image, a spoken line, a music track or a short clip and it renders inline in the conversation with a progress bar, using bounded preview settings and supported saved defaults for that modality. Use the media workspace for editing, reference inputs and full generation parameters. Double-click any chat image to open it full-size in Preview.

And it goes well beyond text-to-X:

- **Edit photos with instructions** — attach a picture, type *"make the hair blue"* or *"remove the monitor in the background"*, and FLUX.2-klein or Mage-Flow Edit changes it while keeping subject, pose, and scene intact (in-context reference conditioning — 0.97 structural correlation measured live). Mage-Flow Edit also composes multiple references ("put the object from image 2 into image 1") and does control maps, restoration and relighting from plain instructions. The source keeps its own aspect ratio, never squished. Works from the OpenAI SDK too: `client.images.edit(image=…, prompt=…)` against `POST /v1/images/edits`.
- **Image-to-image variations** — every image model (Krea-2 included) takes a source image plus a strength slider, from subtle remix to full re-imagination.
- **Animate your photos** — drop a picture into the Video pane's First-frame slot and LTX animates forward from it, starting exactly on your image.
- **Talking characters** — put spoken lines in quotes in the video prompt, attach a real speech or music clip, or type a line for Qwen3-TTS to voice — the video is generated *against* that soundtrack, performance synced, and the original audio (not a re-synthesis) lands in the mp4.
- **Clone a voice from seconds of audio** — record or pick a clip in Settings ▸ Voice and Qwen3-TTS speaks in that voice — in the AudioGen panel, in hands-free Voice Mode, everywhere.
- **Compose full music tracks** — ACE-Step 1.5 turns a style prompt (and optional lyrics) into a 48 kHz stereo track: a 30-second song renders in about 4 seconds.
- **Turn a photo into a 3D model** — Hunyuan3D-2.1 converts an image into a watertight GLB mesh, optionally with full PBR textures — drops straight into a game engine or slicer.
- **Video with its own soundtrack** — MiniMax-H3 (Hailuo 3.0) denoises the clip and a stereo soundtrack together in one pass, so the sound is produced with the video rather than dubbed on after. Describe the scene, then what you want to hear after `overall_soundscape:`. The REF2VA build builds the clip around pictures, clips or audio you attach (`<Picture 1>`, `<Video 1>`, `<Audio 1>` in the prompt); the FL2VA build takes first/last keyframes and chains windows into longer clips. **Turbo** renders in 4 steps instead of 30. It is slow either way: 1344×768 at 124 frames is about 50 minutes on an M4 Max.
- **Style LoRAs** — attach diffusers, kohya or PEFT `.safetensors` adapters to restyle FLUX, Krea, Mage-Flow, LTX or MiniMax-H3 generations at runtime. Up to 8 at once, summed rather than merged, so nothing is re-quantized and there is zero quality loss on the base weights. Each adapter runs at the strength its own file declares.

### Models

| Feature | Default | Other options | Approx. RAM |
|---|---|---|---|
| Image | FLUX.2-klein 4B 4-bit (mflux, ~5 GB pre-quantized) | FLUX.2-klein 9B (10 GB), Krea-2-Turbo, Mage-Flow Turbo / Edit 8-bit (8.5 / 9.1 GB) | 8 / 12 / 16 GB |
| Video | LTX-Video 2.5 4-bit (36 GB, bundled text encoder) | LTX-Video 2.5 8-bit (59 GB, sharper + diffusion decoder), LTX-Video 2.3 Q4 (~50 GB), MiniMax-H3 (Hailuo 3.0) 4-bit / 8-bit, video **and** matching soundtrack in one pass | LTX 24 GB RAM; H3 26 GB (40 GB) or 44 GB (69 GB) |
| Speech | Qwen3-TTS 1.7b (voice cloning) | Qwen3-TTS 0.6b, Kokoro-82M (54 voices, ~345 MB) | 8 GB RAM, ~3.5 GB first-run download |
| Music | ACE-Step 1.5 XL Turbo 8-bit (fast, 8 steps) | MiniMax Music 3 8-bit (sings your lyrics, songs up to 6 min, strongest vocals) | ACE 8 GB RAM, ~6.2 GB download; Music 3 ~20 GB RAM, 13.6 GB download |
| 3D | Hunyuan3D-2.1 8-bit (shape + PBR texture) | — | 16 GB RAM |

> The 41 GB LTX 2.3 snapshot ships **both** transformer variants (1-stage distilled + 2-stage dev, ~11 GB each) plus a 7.6 GB distillation LoRA, so you can switch between Fast/Good/Quality/Super offline without re-downloading.

> LTX-Video 2.5 brings its own text encoder, so there is no separate 8 GB download on first use. The 8-bit pack keeps detail the 4-bit one loses and adds a **Diffusion decoder** toggle (the decoder Lightricks' own published clips use, `"decoder": "diffusion"` over the API) for sharper texture and edges. The default canvas and frame ladder are sized per Mac; two-stage tiers denoise at half the chosen size and upscale.

> MiniMax Music 3 requires lyrics; structure tags like `[verse]` and `[chorus]` go on their own lines. ACE-Step's tempo, key, meter and language controls don't exist on it, so put those facts in the caption instead. The bundled **music3** skill writes the caption format the model was trained on when you ask the chat for a song.

Outputs go to `~/.mlx-serve/generations/` under per-modality, per-date folders.

> The app won't let you start a generation if there isn't enough free RAM. If the mlx-serve server is running and competing for memory, you'll be prompted to stop it first.
