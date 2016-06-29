#!/bin/bash

echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh # source the path.
. parse_options.sh || exit 1;

if [ $# != 0 ]; then
   echo "usage: train_word_models.sh"
   exit 1;
fi

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.

. common/slurm_dep_graph.sh

JOB_PREFIX=$(cat id)_

mkdir -p data/segmentation/word
job make_word_segm 4 4 NONE -- common/preprocess_corpus.py data-prep/text/text.orig.xz data/segmentation/word/corpus.xz
for size in "20" "50" "100" "150"; do
    mkdir -p data/dicts/word_${size}k
    mkdir -p data/langs/word_${size}k
    job make_vocab_${size}k 4 4 make_word_segm -- common/count_words.py --nmost=${size}000 data/segmentation/word/corpus.xz data/dicts/word_${size}k/vocab
    job make_lex_${size}k 4 4 make_vocab_${size}k -- common/make_dict.sh data/dicts/word_${size}k/vocab data/dicts/word_${size}k
    job make_lang_${size}k 4 4 make_lex_${size}k -- utils/prepare_lang.sh --phone-symbol-table data/lang_train/phones.txt data/dicts/word_${size}k "<UNK>" data/langs/word_${size}k/local data/langs/word_${size}k

    for order in "2" "3" "5"; do
        mkdir -p data/lm/word/srilm/${size}k_${order}g
        job srilm_${size}k_${order}g $(expr ${order} \* 15) 4 make_vocab_${size}k -- common/train_srilm_model.sh data/segmentation/word/corpus.xz data/dicts/word_${size}k/vocab ${order} data/lm/word/srilm/${size}k_${order}g/arpa.xz
        job recog_lang _${size}k_${order}g 16 1 srilm_${size}k_${order}g -- common/make_recog_lang.sh data/lm/word/srilm/${size}k_${order}g/arpa.xz data/langs/word_${size}k data/recog_langs/word_s_${size}k_${order}gram
    done
done
