#!/bin/bash
set -e

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
for size in "100" "200" "400" "600" "800" "1000" "1200" "1400" "1600" "1800" "2000"; do
    if [ -e data/dicts/word_${size}k ]; then rm -Rf data/dicts/word_${size}k; fi
    if [ -e data/langs/word_${size}k ]; then rm -Rf data/langs/word_${size}k; fi
    mkdir -p data/dicts/word_${size}k
    mkdir -p data/langs/word_${size}k
    job make_vocab_${size}k 4 4 make_word_segm -- common/count_words.py --lexicon=data/lexicon/lexicon.txt --nmost=${size}000 data/segmentation/word/corpus.xz data/dicts/word_${size}k/vocab
    job make_lex_${size}k 4 4 make_vocab_${size}k -- common/make_dict.sh data/dicts/word_${size}k/vocab data/dicts/word_${size}k
    job make_lang_${size}k 4 4 make_lex_${size}k -- utils/prepare_lang.sh --phone-symbol-table data/lang/phones.txt data/dicts/word_${size}k "<UNK>" data/langs/word_${size}k/local data/langs/word_${size}k

    for order in "2" "3" "5"; do
        mkdir -p data/lm/word/srilm/${size}k_${order}g
        job srilm_${size}k_${order}g $(expr ${order} \* 15) 4 make_vocab_${size}k -- common/train_srilm_model.sh data/segmentation/word/corpus.xz data/dicts/word_${size}k/vocab ${order} data/lm/word/srilm/${size}k_${order}g/arpa.xz
        job recog_lang_${size}k_${order}g 25 1 srilm_${size}k_${order}g,make_lang_${size}k -- common/make_recog_lang.sh data/lm/word/srilm/${size}k_${order}g/arpa.xz data/langs/word_${size}k data/recog_langs/word_s_${size}k_${order}gram
    done
done
