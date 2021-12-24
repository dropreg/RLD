#!/bin/bash

TRAIN_FLAG=false
TEST_FLAG=false

SRC_LNG=de
TGT_LNG=en

GPU=7
export CUDA_VISIBLE_DEVICES=$GPU

ROOT_DIR=/data/lxb
if [ $SRC_LNG == en ]; then
    DATA_DIR=$ROOT_DIR/dataset/small_nmt_data/iwslt_data/${TGT_LNG}-${SRC_LNG}_file/databin
else
    DATA_DIR=$ROOT_DIR/dataset/small_nmt_data/iwslt_data/${SRC_LNG}-${TGT_LNG}_file/databin
fi

CKPT_DIR=$ROOT_DIR/checkpoints/submodule_kd/${SRC_LNG}-${TGT_LNG}-ckpt/rld_td_xbaseline
# CKPT_DIR=$ROOT_DIR/checkpoints/submodule_kd/${SRC_LNG}-${TGT_LNG}-ckpt/rld_ad_xbaseline
GEN_DIR=$ROOT_DIR/sm_gen_data/${SRC_LNG}-${TGT_LNG}-data/baseline_td_new

mkdir -p $CKPT_DIR

if [ $TRAIN_FLAG == true ]; then

    echo "[SubModule_KD info]: train nmt model from lang $SRC_LNG to $TGT_LNG "
    rm $CKPT_DIR/train.log
    touch $CKPT_DIR/train.log
    
    # --share-decoder-input-output-embed \ --share-all-embeddings \
    # --attention-dropout 0.1 --relu-dropout 0.1
    fairseq-train $DATA_DIR \
        --user-dir examples/submodule_kd/kd_src \
        --arch x_transformer \
        --task kd_translation \
        --train-tec \
        -s $SRC_LNG -t $TGT_LNG \
        --share-all-embeddings \
        --dropout 0.3 --relu-dropout 0.1 \
        --optimizer adam --lr 0.0005 --warmup-init-lr 1e-07 --adam-betas '(0.9,0.98)' \
        --label-smoothing 0.1 --criterion kd_label_smoothed_cross_entropy \
        --max-update 100000 --warmup-updates 4000 --max-tokens 4096 \
        --lr-scheduler inverse_sqrt --weight-decay 0.0001 \
        --no-progress-bar \
        --keep-best-checkpoints 10 \
        --no-epoch-checkpoints \
        --fp16 \
        --eval-bleu \
        --eval-bleu-args '{"beam": 5, "max_len_a": 1.2, "max_len_b": 10}' \
        --eval-bleu-detok moses \
        --eval-bleu-remove-bpe \
        --best-checkpoint-metric bleu --maximize-best-checkpoint-metric \
        --save-dir $CKPT_DIR | tee -a $CKPT_DIR/train.log \
    
elif [ $TEST_FLAG == true ]; then

    echo "[SubModule_KD info]: test nmt model from lang $SRC_LNG to $TGT_LNG "

    if [ $SRC_LNG == de ] || [ $TGT_LNG == de ]; then
        
        # fairseq evaluation code
        fairseq-generate $DATA_DIR \
            --user-dir examples/submodule_kd/kd_src \
            --task kd_translation \
            -s $SRC_LNG -t $TGT_LNG \
            --path $CKPT_DIR/checkpoint_best.pt \
            --batch-size 128 --beam 5 --remove-bpe --quiet \

        # fairseq-generate $DATA_DIR \
        #     -s $SRC_LNG -t $TGT_LNG \
        #     --path $CKPT_DIR/checkpoint_best.pt \
        #     --batch-size 128 --beam 5 --remove-bpe > gen.out

        # bash ../../scripts/compound_split_bleu.sh gen.out
        # rm gen.out
    
    elif [ $SRC_LNG == es ] || [ $TGT_LNG == es ]; then

        BPE_REF=$DATA_DIR/../test.$TGT_LNG.debpe.detok
        BPE_IN=$DATA_DIR/../test.$SRC_LNG
        cat $BPE_IN | fairseq-interactive $DATA_DIR \
            --user-dir examples/submodule_kd/kd_src \
            --task kd_translation \
            --source-lang $SRC_LNG --target-lang $TGT_LNG \
            --path $CKPT_DIR/checkpoint_best.pt \
            --buffer-size 2000 --batch-size 128 \
            --beam 5 --remove-bpe > iwslt17.test.$SRC_LNG-$TGT_LNG.$TGT_LNG.sys
        grep ^H iwslt17.test.$SRC_LNG-$TGT_LNG.$TGT_LNG.sys | cut -f3 > out.log
        sacremoses -l $TGT_LNG detokenize < out.log > deout.log
        cat deout.log | sacrebleu $BPE_REF --language-pair $SRC_LNG-$TGT_LNG
        
        rm iwslt17.test.$SRC_LNG-$TGT_LNG.$TGT_LNG.sys
        rm out.log
        rm deout.log

    else

        BPE_IN=$DATA_DIR/../test.$SRC_LNG
        cat $BPE_IN | fairseq-interactive $DATA_DIR \
            --user-dir examples/submodule_kd/kd_src \
            --task kd_translation \
            --source-lang $SRC_LNG --target-lang $TGT_LNG \
            --path $CKPT_DIR/checkpoint_best.pt \
            --buffer-size 2000 --batch-size 128 \
            --beam 5 --remove-bpe > iwslt17.test.$SRC_LNG-$TGT_LNG.$TGT_LNG.sys
        grep ^H iwslt17.test.$SRC_LNG-$TGT_LNG.$TGT_LNG.sys | cut -f3 > out.log
        sacremoses -l $TGT_LNG detokenize < out.log > deout.log
        cat deout.log | sacrebleu --test-set iwslt17  --language-pair $SRC_LNG-$TGT_LNG
        
        rm iwslt17.test.$SRC_LNG-$TGT_LNG.$TGT_LNG.sys
        rm out.log
        rm deout.log

    fi

else

    echo "[SubModule_KD info]: generate KD data from lang $SRC_LNG to $TGT_LNG "
    mkdir -p $GEN_DIR
    echo "[SubModule_KD info]: output file $GEN_DIR/best_${SRC_LNG}_${TGT_LNG}.log "

    SEED=$GPU
    
    fairseq-generate $DATA_DIR \
        --user-dir examples/submodule_kd/kd_src \
        --task kd_translation \
        -s $SRC_LNG -t $TGT_LNG \
        --generate-random $SEED \
        --gen-subset 'train' \
        --path $CKPT_DIR/checkpoint_best.pt \
        --batch-size 256 --beam 5 > $GEN_DIR/${SRC_LNG}_${TGT_LNG}_$SEED.log

fi
