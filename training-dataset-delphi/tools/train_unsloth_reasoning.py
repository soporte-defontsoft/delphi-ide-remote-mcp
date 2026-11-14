"""Train a LoRA on the dataset WITH its reasoning learned, for a model that thinks before it answers (Qwen3.8-27B and
its kind), with the Unsloth library.

    python train_unsloth_reasoning.py --dataset <a reasoning JSONL> --out delphi-lora \
        --reasoning-effort medium [--full-text]

Why a script and not Unsloth Studio (2026.11.4, measured 12-nov): to train on the answers only, Studio finds where an
answer starts by the marker of an EMPTY reasoning block ('<|im_start|>assistant\\n<think>\\n\\n</think>\\n\\n').
Trained that way on answers alone, the model never practised writing </think>, and when it reasoned it ended some
turns without ever closing its reasoning; with the reasoning in the examples (a JSONL whose assistant messages carry
reasoning_content - this folder does not ship one: see the README) that marker is in no example and Studio stops
("masked every label"). Here the marker is the start of what the model
writes when it thinks, '<|im_start|>assistant\\n<think>\\n': it learns its reasoning, the </think> that closes it, the
answer and the end of the turn - and not the question.

It runs in the Python environment Unsloth runs in (Unsloth Studio installs one). The recipe is Unsloth's own for
Qwen3.8 (unsloth.ai/docs/models/qwen3.8/train); the marker and the split over every GPU are what it adds. The adapter
is saved in PEFT format in --out and, when llama.cpp's converter is found, as a GGUF LoRA for llama.cpp's --lora.

The reasoning effort the examples are written with is chosen, never left to the template: Qwen3.8's template writes
the level as a system line, and with none given it writes xhigh ("think carefully..."). Measured 13-nov: trained that
way (Studio has no option for it), with short reasoning after that line, the model thought ~320 characters at every
level and lost answers it had right at medium. --full-text learns the whole text, the question too: Studio's recipe
with train_on_completions off, and the one in Unsloth's Qwen3.8 guide.

Measured with Qwen3.8-27B (13-nov): no adapter trained with this script or with Studio beat the base model on the
held-out questions - the README says what was tried and what each run gave.
"""
import argparse
import glob
import os
import subprocess
import sys

# unsloth first: it patches transformers and trl when it is imported before them
from unsloth import FastModel  # noqa: I001
from unsloth.chat_templates import train_on_responses_only
from datasets import load_dataset
from trl import SFTConfig, SFTTrainer

INSTRUCTION = "<|im_start|>user\n"
RESPONSE = "<|im_start|>assistant\n<think>\n"
END = "<|im_end|>"
# what Qwen3.8's template writes for each level: medium has no line at all
EFFORT_LINE = {"low": "Reasoning effort is set to low.", "medium": None, "xhigh": "Reasoning effort is set to xhigh."}

p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
p.add_argument("--dataset", required=True, help="the reasoning JSONL (messages with reasoning_content)")
p.add_argument("--out", required=True, help="folder for the adapter (its checkpoints go to <out>-checkpoints)")
p.add_argument("--model", default="unsloth/Qwen3.8-27B-unsloth-bnb-4bit")
p.add_argument("--gguf-base", default="unsloth/Qwen3.8-27B",
               help="the UNquantized repo the GGUF converter reads the config from: it cannot read a bitsandbytes one "
                    "(measured 12-nov: 'Quant method is not yet supported')")
p.add_argument("--epochs", type=float, default=3)
p.add_argument("--lr", type=float, default=2e-4)
p.add_argument("--grad-accum", type=int, default=4)
p.add_argument("--rank", type=int, default=16)
p.add_argument("--max-seq", type=int, default=2048)
p.add_argument("--reasoning-effort", required=True, choices=sorted(EFFORT_LINE),
               help="the level the examples are written with (the template's own line; medium = no line). The model "
                    "learns its reasoning AS this level: train at the level the model will be used at, or at one "
                    "set apart for it")
p.add_argument("--full-text", action="store_true",
               help="learn the whole text, the question included (Studio with train_on_completions off, and Unsloth's "
                    "Qwen3.8 guide); without it, only what the model writes: reasoning, answer and end of turn")
p.add_argument("--device-map", default="",
               help="'balanced' or 'auto' to split over every GPU; empty = Unsloth places it. Measured 12-nov on 2 x 16 GB: "
                    "both put part of the 4-bit 27B on the CPU, which 4-bit loading refuses")
p.add_argument("--offload-layers", default="",
               help="'auto' = the decoder layers the GPU cannot hold stay in RAM and are streamed in while training "
                    "(Unsloth's own advice when the model does not fit; slower, and it needs that much free RAM)")
p.add_argument("--offload-embedding", action="store_true",
               help="keep the input embedding in RAM (in Unsloth's one-GPU recipe); off by default: with it on, the "
                    "two-GPU load of 12-nov failed with part of the model on the CPU, which 4-bit loading refuses")
p.add_argument("--max-gpu-gb", type=float, default=0,
               help="memory budget of EACH GPU for the split, in GB (0 = transformers decides)")
p.add_argument("--check-only", action="store_true",
               help="render and check the examples with the tokenizer alone (no GPU, no model), and stop")
args = p.parse_args()


def stop(why):
    raise SystemExit("STOPPED: " + why)


def rendered(tok):
    """The examples as the model will see them, with the model's own chat template, checked: the marker once, a
    reasoning that is not empty and is closed, and an answer that ends the turn."""
    # a multimodal model comes with a processor; the chat template of its text is the same one
    templater = tok if getattr(tok, "chat_template", None) else getattr(tok, "tokenizer", tok)

    def render(example):
        text = templater.apply_chat_template(example["messages"], tokenize=False, add_generation_prompt=False,
                                             reasoning_effort=args.reasoning_effort)
        # the last answer has to END, or the model never learns to stop
        if not text.rstrip().endswith(END):
            text = text.rstrip("\n") + END + "\n"
        return {"text": text}

    data = load_dataset("json", data_files=args.dataset, split="train")
    data = data.map(render, remove_columns=data.column_names)
    for n, row in enumerate(data):
        t = row["text"]
        if t.count(RESPONSE) != 1:
            stop("example %d: the answer marker appears %d times, not once" % (n, t.count(RESPONSE)))
        answer = t.split(RESPONSE, 1)[1]
        if "</think>" not in answer or answer.startswith("\n</think>"):
            stop("example %d: its reasoning is empty or not closed - is this the reasoning JSONL?" % n)
        if not answer.rstrip().endswith(END):
            stop("example %d: the answer does not end the turn" % n)
        # the level has to be the one asked for: a template that ignored it would write xhigh in silence
        line = EFFORT_LINE[args.reasoning_effort]
        if line and line not in t or not line and "Reasoning effort is set to" in t:
            stop("example %d: the text is not written at reasoning effort %s" % (n, args.reasoning_effort))
    return data


# checked first with the tokenizer alone: a wrong dataset or template stops here, before any GPU time
from transformers import AutoTokenizer  # noqa: E402

check = rendered(AutoTokenizer.from_pretrained(args.model))
print("%d examples rendered at reasoning effort %s; the first one, as the model will learn it:\n%s\n%s" % (
    len(check), args.reasoning_effort, "-" * 60, check[0]["text"][:1200]))
if args.check_only:
    raise SystemExit(0)

budget = {}
if args.device_map:
    budget["device_map"] = args.device_map
if args.offload_layers:
    budget["offload_layers"] = args.offload_layers
if args.max_gpu_gb:
    import torch  # noqa: E402

    budget["max_memory"] = {i: "%gGiB" % args.max_gpu_gb for i in range(torch.cuda.device_count())}
    print("GPU budget:", budget["max_memory"])
model, tokenizer = FastModel.from_pretrained(
    model_name=args.model,
    max_seq_length=args.max_seq,
    load_in_4bit=True,
    full_finetuning=False,
    offload_embedding=args.offload_embedding,
    **budget,
)
# and again with the tokenizer the trainer uses
dataset = rendered(tokenizer)
if dataset["text"] != check["text"]:
    print("note: Unsloth's tokenizer renders the examples differently from the plain one; training on its rendering")

model = FastModel.get_peft_model(
    model,
    finetune_vision_layers=False,
    finetune_language_layers=True,
    finetune_attention_modules=True,
    finetune_mlp_modules=True,
    r=args.rank,
    lora_alpha=args.rank,
    lora_dropout=0,
    bias="none",
    use_gradient_checkpointing="unsloth",
    random_state=3407,
    use_rslora=False,
    loftq_config=None,
)
trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=dataset,
    args=SFTConfig(
        dataset_text_field="text",
        max_seq_length=args.max_seq,
        per_device_train_batch_size=1,
        gradient_accumulation_steps=args.grad_accum,
        warmup_ratio=0.1,
        num_train_epochs=args.epochs,
        learning_rate=args.lr,
        lr_scheduler_type="linear",
        weight_decay=0.001,
        logging_steps=1,
        optim="adamw_8bit",
        output_dir=args.out + "-checkpoints",
        save_steps=20,
        seed=3407,
        dataset_num_proc=1,
        report_to="none",
    ),
)
if not args.full_text:
    trainer = train_on_responses_only(trainer, instruction_part=INSTRUCTION, response_part=RESPONSE)

# every example must keep something to learn: a marker that does not match masks a row in silence
if args.full_text:
    # the whole text is learned: the labels are the tokens themselves, made by the collator at train time (measured
    # 13-nov: without train_on_responses_only the tokenized dataset has no "labels" column)
    rows = trainer.train_dataset["input_ids"]
    if len(rows) != len(dataset) or not all(rows):
        stop("%d rows reached the trainer for %d examples, or a row is empty" % (len(rows), len(dataset)))
    total = sum(len(row) for row in rows)
    print("learned tokens: %d of %d (100 %%) - the whole text" % (total, total))
else:
    labels = trainer.train_dataset["labels"]
    empty = [n for n, row in enumerate(labels) if all(x == -100 for x in row)]
    if empty or len(labels) != len(dataset):
        stop("%d of %d examples are left with nothing to learn (rows %s); %d rows reached the trainer" % (
            len(empty), len(dataset), empty[:10], len(labels)))
    learned = sum(sum(1 for x in row if x != -100) for row in labels)
    total = sum(len(row) for row in labels)
    print("learned tokens: %d of %d (%d %%) - the rest is the question" % (learned, total, 100 * learned // total))

trainer.train()
model.save_pretrained(args.out)
tokenizer.save_pretrained(args.out)
print("adapter saved to", os.path.abspath(args.out))

# the GGUF LoRA for llama.cpp, with the converter Unsloth installs next to its own llama.cpp
found = sorted(glob.glob(os.path.join(os.path.expanduser("~"), ".unsloth", "**", "convert_lora_to_gguf.py"),
                         recursive=True))
outfile = os.path.join(args.out, "lora-f16.gguf")
if found:
    r = subprocess.run([sys.executable, found[0], args.out, "--base-model-id", args.gguf_base, "--outtype", "f16",
                        "--outfile", outfile])
    print("GGUF LoRA:", outfile if r.returncode == 0 else "the conversion failed (exit %d)" % r.returncode)
else:
    print("convert_lora_to_gguf.py not found under ~/.unsloth: run llama.cpp's converter on", os.path.abspath(args.out))
