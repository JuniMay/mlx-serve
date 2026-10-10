# Model packs and runtime controls

## Model pack compatibility

Compatibility depends on tensor encoding, architecture, tensor names, and any
extra files. A `.safetensors` filename alone does not establish compatibility.
The descriptions below are based on published model cards and source code, not
test loads in another runtime.

| Pack | Encoding and additional requirements |
| --- | --- |
| [ddalcu Qwen3.6 27B 4-bit MTP](https://huggingface.co/ddalcu/Qwen3.6-27B-4bit-MTP-MLX-Serve) | Its author states that the main weights and configuration match the mlx-community 4-bit pack. It adds an INT8 MTP draft-head sidecar. A runtime supporting the main Qwen architecture can ignore the optional sidecar. |
| [ddalcu Qwen Flash-Next iQ 4.7 bpw](https://huggingface.co/ddalcu/Qwen3.8-Flash-Next-MLX-Serve-iQ-MLX-4.7bpw) | Importance-calibrated MLX affine quantization: 4-bit experts and mostly 8-bit remaining projections. The pack also needs the `qwen4_exp` architecture and its separate `ngram_table.bin`. |
| [ddalcu Qwen Flash-Next iQ 3.3 bpw](https://huggingface.co/ddalcu/Qwen3.8-Flash-Next-MLX-Serve-iQ-MLX-3.3bpw) | Calibrated mixed 2-, 3-, 4-, and 8-bit MLX affine tensors. It has the same architecture and n-gram-file requirements. |
| [ddalcu DeepSeek V4 Flash iQ 3.3 bpw](https://huggingface.co/ddalcu/DeepSeek-V4-Flash-0731-iQ-MLX-3.3bpw) | Calibrated affine tensors with per-layer bit allocation and included DSpark stages. Loading requires DeepSeek V4 support; draft acceleration also requires DSpark support. |
| [beamster Qwen Flash-Next Sushi 3 bpw](https://huggingface.co/beamster/Qwen3.8-Flash-Next-Sushi-3bpw) | EXL3 routed experts, 8-bit affine dense tensors, and a 4-bit affine n-gram table. This is a separate expert encoding served through mlx-serve's Sushi integration. This pack is published by beamster. |

Quantization stores weights with fewer bits. Calibration uses sample activations
to choose scales and bit allocations that reduce quantization error. The iQ-MLX
cards describe standard MLX affine tensor layouts; the `iQ` name here does not
mean GGUF IQ encoding. Fractional **bits per weight (bpw)** describes an aggregate
storage cost, not a fractional integer bit width for every tensor.

[MLX also supports NVFP4, MXFP4, and MXFP8](https://ml-explore.github.io/mlx/build/html/python/_autosummary/mlx.core.quantize.html).
Those formats alone do not establish architecture or tensor-layout compatibility.
Runtime optimizations, such as fused affine expert kernels, are another layer:
an engine can read the weights without implementing the same acceleration.

## Context size

Context includes the prompt, conversation history, tool results, and generated
tokens. **Auto** is stored as zero. For the native MLX path, the server computes
a memory-based ceiling at model load, keeps 85% of that token capacity, rounds
down to a 1,024-token boundary, and then caps the result at the model's supported
window. Very small ceilings use a positive value below 1,024 instead of zero.
The estimate accounts for the model's memory use and cache geometry.

The server pins this result until the next model load. It therefore remains
stable while a client uses it. Auto does not promise the checkpoint's largest
advertised window. A positive per-model context setting takes precedence over
the global setting. Settings shows the active limit separately from the chosen
default because a running model may still use the value selected at load time.
See `safeAutoContext`, `autoContextFrom`, `pinAutoContext`, and `manualContext`
in `src/server.zig`.

## Speculative decoding

Speculative decoding proposes several tokens and lets the main model verify
them together. Its speed depends on acceptance rate, verification cost, model,
and workload.

- **Prompt Lookup Decoding (PLD)** copies candidate continuations after a matching
  token sequence in the existing prompt or output. It needs no separate model
  and can help repetitive text or code edits.
- **Multi-Token Prediction (MTP)** uses a trained prediction head to propose
  future tokens. Supported models supply compatible head weights in the pack
  or a sidecar. The app enables available native heads by default; a depth of
  zero lets the server choose the draft length.
- **Assistant models** use separate draft weights. They require a compatible
  main model and consume additional memory.
- **DeepSeek DSpark** uses DeepSeek-specific draft stages and rollback behavior.
  It is separate from Qwen MTP. Loading its stages is off by default in the app
  because they add substantial memory use.

These methods share a purpose but have different compatibility and memory
requirements. Controls are grouped by mechanism in Speculative Decoding.

## Terminals

A terminal runs a real process. Host terminals run a shell or an installed
coding-agent CLI on macOS. Sandbox terminals connect over SSH to the Linux
guest. A terminal session survives navigation away from its view. Terminal
input is separate from a chat request, and host commands can change host files.

## Voice

Voice mode transcribes microphone input, sends a turn to the selected chat or
agent, and reads the response aloud. It uses on-device speech recognition when
the required language support and permissions are available. System speech is
the default output. Optional Kokoro and Qwen voice-clone output use local models;
a neural synthesis failure falls back to system speech for that utterance.

No wake phrase is supplied by default. A user can choose a global phrase in
Voice settings, and an agent can supply its own phrase. Wake-word mode requires
a configured phrase before listening starts. Existing saved phrases remain
available. Turning the wake-word requirement off permits speech without a wake
phrase while the voice session is active.

## Tools and sandboxing

Settings defines default Tools and MCP access. Each conversation can override
those two independent choices and use them together. Plain Chat appears above
them as an override that disables both and attached-folder search. An
agent's capability restrictions still apply. Enabling access does not approve
a tool action. MCP servers added by the user default to enabled in their server
configuration.

When Agent Sandbox is enabled, shell commands run in a Linux virtual machine
using Apple's Virtualization framework. The Developer ID build defaults this
option off; the App Store build requires guest execution. Workspace folders are
shared real folders: guest edits affect those files. They are not disposable
copies. Network access is a separate setting; disabling it removes the guest's
network device. Host-side file tools retain workspace checks, and not every
tool runs inside the VM. See `AgentSandbox`, `VzGuest`, and `ToolExecutor` in
`app/Sources/MLXServe/Services`.

## Settings and model sources

Settings groups Cache controls by prompt preparation, memory reuse, disk reuse,
and the applicable GGUF engine. Engines uses the same native grouped layout.
Options show a short caption, with the complete explanation beside the option
name. Search includes both texts. Tools groups expand with brief motion and
respect the system Reduce Motion preference.

Providers contains Nearby Macs as a built-in source and separately configured
OpenAI-compatible chat services. Nearby Macs uses LAN discovery and requires a
server restart after a change. Models run on the Mac that hosts them; that Mac
can read the prompts sent to it. Discovery does not create a chat-service entry
or change provider credentials. LAN Sharing controls which models this Mac
publishes. Reset Nearby Macs turns discovery off and preserves publishing and
configured chat services.

Disable vision skips language-model vision weights on the MLX path. Supported
models use different image towers, projectors, or patch embedders, so memory
savings depend on the model. Unified Gemma models also omit audio embedding
weights. This setting does not disable separate image or video generation.
