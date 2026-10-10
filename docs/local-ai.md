# Using a local AI model with Kandil

Kandil can chat with a language model that runs on your own computer. Questions
and answers stay on the machine; no account or API key is needed. Kandil is
already set up for this: it talks to [Ollama](https://ollama.com) at
`http://localhost:11434`, so the only work is installing Ollama and
downloading a model.

## 1. Install Ollama

The official install script works on every distribution and installs the
latest version together with a systemd service:

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

Distribution packages also exist, but they can be older than the official
release:

| Distribution | Command |
|---|---|
| Fedora | `sudo dnf install ollama` |
| Arch Linux | `sudo pacman -S ollama` (add `ollama-rocm` for AMD, `ollama-cuda` for NVIDIA, or `ollama-vulkan`) |

Make sure the service is running:

```bash
systemctl status ollama
```

If it is not, start it with `sudo systemctl enable --now ollama`.

## 2. Download a model

Pick a model that fits your hardware. As a rule of thumb, a model in Ollama's
default (4-bit) format needs about 0.6 GB of memory per billion parameters:
video memory if it runs on the graphics card, otherwise system RAM.

| Memory available | Model size | Examples |
|---|---|---|
| 4 GB | 1–3 billion parameters | `llama3.2:3b` |
| 8 GB | 7–8 billion parameters | `qwen2.5:7b` |
| 12 GB or more | 12–14 billion parameters | `gemma3:12b` |

The full list of models is at [ollama.com/library](https://ollama.com/library).
Download one with:

```bash
ollama pull qwen2.5:7b
```

You can try it in the terminal with `ollama run qwen2.5:7b`.

## 3. Ask Kandil

Open Kandil, type `ai`, a space and your question, then press Enter:

```
ai how do I see disk usage on Linux?
```

The answer appears in the panel while it is being written. The next question
continues the same conversation.

| Keys | Action |
|---|---|
| Enter | Send the question |
| Esc | Stop the answer |
| Alt+C | Copy the last answer |
| Ctrl+N | Start a new chat |

If no model is selected, Kandil uses the first model Ollama offers. To choose
one, open Kandil's settings, go to the **AI** page, press **Fetch models** on
the Ollama card and select a model from the list.

## What to expect

- **The first answer is slow.** Ollama loads the model into memory on the
  first question, which can take from a few seconds to a minute, depending on
  the model size and the disk. Kandil shows "Loading the model…" meanwhile.
  Later answers start almost immediately.
- **The model is unloaded after five minutes** of inactivity to free memory.
  To keep it loaded longer, set `OLLAMA_KEEP_ALIVE` for the service, for example
  to `30m` or `-1` (never unload):

  ```bash
  sudo systemctl edit ollama
  ```

  ```ini
  [Service]
  Environment="OLLAMA_KEEP_ALIVE=30m"
  ```

- **Graphics card support.** Ollama uses NVIDIA (CUDA) and AMD (ROCm) cards
  when the drivers are available, and falls back to the processor otherwise.
  `ollama ps` shows where a loaded model runs (`100% GPU` or `CPU`). On the
  processor, smaller models are much more comfortable.
- **Conversations are not saved.** They stay in Kandil's memory until you
  start a new chat or Kandil restarts.

## Other local servers

Any server with an OpenAI-compatible API works the same way. On Kandil's **AI**
settings page, use **Add provider** and pick a preset:

| Server | Default address | Note |
|---|---|---|
| LM Studio | `http://localhost:1234/v1` | Start the local server in LM Studio's Developer tab |
| llama.cpp | `http://localhost:8080/v1` | Run `llama-server -m model.gguf` |

Each provider has its own keyword, so several can be used side by side.

## Troubleshooting

| Problem | Solution |
|---|---|
| "Connection refused" | Ollama is not running: `sudo systemctl start ollama` |
| "The server reported no models" | No model is downloaded yet: `ollama pull qwen2.5:7b` |
| Answers are very slow | The model runs on the processor or is too large for the graphics card; check `ollama ps` and try a smaller model |
| The answer is in the wrong language | Change the system prompt on the **AI** settings page |

## Privacy

Kandil connects only to the address set on the AI settings page. With Ollama
on `localhost`, nothing leaves the computer. If you set `OLLAMA_HOST` to
`0.0.0.0` to use Ollama from other devices, it is reachable from the network,
depending on your firewall.
