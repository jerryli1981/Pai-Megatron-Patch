#!/bin/bash
# bash run_text_generation_megatron_qwen.sh dsw ../../ /mnt/workspace/latest/qianwen/models--Qwen--Qwen2-beta-1_8B-Chat-hf2mg21 1.8B 2 1 1024 80 0 fp16 0 512 512 /mnt/qwen-datasets/gen.jsonl /mnt/qwen-datasets/cn_output.txt 0.85 1 1
set -e
ENV=$1
export CUDA_VISIBLE_DEVICES=0,1,2,3
MASTER_ADDR=localhost
MASTER_PORT=$(shuf -n 1 -i 10000-65535)
GPUS_PER_NODE=4
NNODES=1
NODE_RANK=0
export CUDA_DEVICE_MAX_CONNECTIONS=1
MEGATRON_PATCH_PATH=$2
MEGATRON_PATCH_PATH=$( dirname $( dirname ${CURRENT_DIR}))
export PYTHONPATH=${MEGATRON_PATCH_PATH}:${MEGATRON_PATCH_PATH}/backends/megatron/PAI-Megatron-LM-240718:$PYTHONPATH

DISTRIBUTED_ARGS="--nproc_per_node $GPUS_PER_NODE --nnodes $NNODES --node_rank $NODE_RANK --master_addr $MASTER_ADDR --master_port $MASTER_PORT"

CHECKPOINT_PATH=$3
MODEL_SIZE=$4  #7B, 14B
TP=$5
BS=$6
SEQ_LEN=$7
PAD_LEN=$8
EXTRA_VOCAB_SIZE=$9 # 293 for models smaller than 32b, 421 for those larger
PR=${10}
TOP_K=${11}
INPUT_SEQ_LEN=${12}
OUTPUT_SEQ_LEN=${13}
INPUT_FILE=${14}
OUTPUT_FILE=${15}
TOP_P=${16}
TEMPERATURE=${17}
# set this penalty between 1.1 and 1.5 to reduce repetition, default is 1.2
REPETITION_PENALTY=${18}

gqa_options=""
if [ $MODEL_SIZE = 0.5B ]; then

NUM_LAYERS=24
HIDDEN_SIZE=1024
NUM_ATTN_HEADS=16
INTERMEDIATE_SIZE=2816

elif [ $MODEL_SIZE = 1.8B ]; then

NUM_LAYERS=24
HIDDEN_SIZE=2048
NUM_ATTN_HEADS=16
INTERMEDIATE_SIZE=5504

elif [ $MODEL_SIZE = 4B ]; then

NUM_LAYERS=40
HIDDEN_SIZE=2560
NUM_ATTN_HEADS=20
INTERMEDIATE_SIZE=6912

elif [ $MODEL_SIZE = 7B ]; then

NUM_LAYERS=32
HIDDEN_SIZE=4096
NUM_ATTN_HEADS=32
INTERMEDIATE_SIZE=11008

elif [ $MODEL_SIZE = 14B ]; then

NUM_LAYERS=40
HIDDEN_SIZE=5120
NUM_ATTN_HEADS=40
INTERMEDIATE_SIZE=13696

elif [ $MODEL_SIZE = 32B ]; then

NUM_LAYERS=64
HIDDEN_SIZE=5120
NUM_ATTN_HEADS=40
INTERMEDIATE_SIZE=27392

gqa_options=" \
		    --group-query-attention \
		    --num-query-groups 8"

elif [ $MODEL_SIZE = 72B ]; then

NUM_LAYERS=80
HIDDEN_SIZE=8192
NUM_ATTN_HEADS=64
INTERMEDIATE_SIZE=24576

fi

if [ $CHECKPOINT_PATH != none ]; then
    load_options=" \
		    --load $CHECKPOINT_PATH"
fi

if [ $INPUT_FILE = none ]; then
    input_options=" \
		               "
else
    input_options=" \
        --text-generate-output-file ${OUTPUT_FILE}\
        --text-generate-input-file ${INPUT_FILE} \
        "
fi

if [ $PR = fp16 ]; then
    pr_options=" \
		    --fp16"
elif [ $PR = bf16 ]; then
    pr_options=" \
        --bf16"
fi

rapidformer_options="  \
        --micro-batch-size ${BS} \
        --num-layers ${NUM_LAYERS}  \
        --hidden-size ${HIDDEN_SIZE}  \
        --num-attention-heads ${NUM_ATTN_HEADS}  \
        --ffn-hidden-size ${INTERMEDIATE_SIZE} \
        --seq-length ${SEQ_LEN} \
        --max-position-embeddings ${SEQ_LEN} \
        --tensor-model-parallel-size ${TP} \
        --pipeline-model-parallel-size 1 \
        --no-load-optim \
        --no-load-rng \
        --top-p ${TOP_P} \
        --temperature ${TEMPERATURE}  \
        --top-k ${TOP_K} \
        --input-len ${INPUT_SEQ_LEN} \
        --out-seq-length ${OUTPUT_SEQ_LEN}  \
        --extra-vocab-size ${EXTRA_VOCAB_SIZE} \
        --max-padding-length ${PAD_LEN} \
        --use-distributed-optimizer \
        --swiglu \
        --use-llama2-rotary-position-embeddings \
        --position-embedding-type rope \
        --untie-embeddings-and-output-weights \
        --patch-tokenizer-type LLamaTokenizer \
        --normalization RMSNorm \
        --repetition-penalty ${REPETITION_PENALTY} \
        --rotary-base 1000000 \
        --rotary-scale-factor 1 \
    "

run_cmd="torchrun $DISTRIBUTED_ARGS ../llama2/generate_text_megatron_llama.py
 ${rapidformer_options} ${load_options} ${input_options} ${pr_options} ${gqa_options}"

echo ${run_cmd}
eval ${run_cmd}
set +x
