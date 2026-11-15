# The local model we use

What we run as a local model - the machine, the engine and the model, with what we measured - as a starting point
for anyone who wants to do the same. It is one setup, not a recommendation for every machine. The numbers are from
November 2026, and the questions that chose the model are the held-out ones of this dataset ([README](README.md)).

Our agent runs on another machine and reaches the model over the local network.

## The machine

| Part | What |
|---|---|
| CPU | Intel Xeon E5-2686 v4, 18 cores and 36 threads, one socket (an X99 board) |
| RAM | 64 GB, DDR4-2133 ECC registered, 4 x 16 GB (one module per channel) |
| GPUs | 2 x NVIDIA GeForce RTX 5060 Ti, 16 GB each (32 GB of VRAM in all) |
| System | Windows Server 2019, CUDA 13 |

## The engine: Strata

[Strata](https://github.com/Niko1221/Strata) (0.1.59 when this was written) serves the model with an
OpenAI-compatible API, text and images, one model at a time. It keeps the experts the model uses most in VRAM (about
17 GB of expert cache across the two cards) and the rest in RAM.

## The model: Qwen3.8 Flash Next at 3 bits

The `Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S` GGUF (two files). Chosen by measuring, not by its card: the 20 held-out
questions of [this dataset](README.md#without-training-another-base-model), never
trained on, asked three times with the same judges.

| Model | Held-out right (of 60) |
|---|---|
| Qwen3.8-27B, dense, 4 bits | 18 |
| Qwen3.8 Flash Next, IQ3_XXS | 29 |
| **Qwen3.8 Flash Next, IQ3_S** | **36** |
| Edge0-145B, NVFP4 (a Flash Next retrained by someone else) | 12 |

The last row is why a model is measured on its own questions: on its card it is ahead of Flash Next
([measured here](README.md#a-flash-next-retrained-by-someone-else)).

## Its settings

As Strata serves them (its `/config` and `/metrics`):

| Setting | Value |
|---|---|
| Context | 262,144 tokens, KV cache in int8 |
| Reasoning budget (`reasoning_budget_tokens`) | 4,096 tokens per request |
| Draft layer | MTP, on |
| Conversation cache | 1,024 MiB, 4 conversations, from 1,024 tokens, keeping 2,560 MiB of RAM free |
| VRAM left free | 1,344 MiB |
| Default sampling | temperature 1.0, top_p 0.95, top_k 20 (the model card's, for thinking) |

Our measurements send their own sampling: temperature 0.6, top_p 0.95, top_k 20.

## What it gives

- About 54 tokens per second of output; with the conversation cache, each turn only reads what is new (about 5 s).
- About 14 seconds per model call while our agent works with its tools.
- About 60.5 of the 64 GB of RAM in use with the model loaded; each card uses about 12.5 of its 16 GB.

## What we learned, each one measured

- **One request at a time.** Strata runs one request; the others wait in its queue. Before the conversation cache, the
  short requests an agent makes between turns (a title, a summary) pushed its conversation out, and each new message
  read 19,000 to 38,000 tokens again: 19 to 32 seconds a turn. With the cache, 0.7 seconds. Anything else sent to
  the same model - a benchmark, a second agent - waits in the same queue.
- **The conversation cache lives in RAM, not in VRAM.** Strata only parks a conversation while it leaves the RAM it
  was told to keep free. A conversation of 86,000 tokens takes about 2 GB; with this model and 64 GB, 1,024 MiB is
  what fits, so a long session is read again when another one has run in between. RAM is the limit.
- **Cap the reasoning.** Without a cap, a model can think for much longer than it needs: the retrained model above
  wrote 19,875 tokens for a batch that Flash Next answered in about 5,500. Two models are compared with the same cap.
- **One model on the cards at a time.** Loading a second model while one is loaded runs out of VRAM.
- **A model's card does not predict Delphi.** Measure a candidate on your own questions before changing anything;
  the dataset's held-out questions and judges are there for that.
