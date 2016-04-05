#!/bin/bash
set -e
export LC_ALL=C

# Begin configuration section.
lowercase_text=false
# End configuration options.

echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh # source the path.
. parse_options.sh || exit 1;

if [ $# != 3 ]; then
   echo "usage: spr_local/spr_make_arpa.sh out_file vocabsize(in thousands) order"
   echo "e.g.:  steps/spr_make_arpa.sh data/20k_3gram 20 3"
   echo "main options (for others, see top of script file)"
   echo "     --lowercase-text (true|false)   # Lowercase everthing"
   exit 1;
fi

outfile=$1
vocabsize=$2
order=$3

mkdir -p ${outfile}/dict

tmp_dir=$(mktemp -d)
echo "Temporary directories (should be cleaned afterwards):" ${tmp_dir}

spr_local/make_recog_vocab.py data-prep/ngram/vocab ${vocabsize}000 ${outfile}/dict/vocab

spr_local/spr_make_lex.sh ${outfile}/dict ${outfile}/dict/vocab

#spr_local/create_vocab_lex.py data-prep/lexicon/lexicon.txt data-prep/ngram/vocab ${vocabsize}000 ${tmp_dir}/known.lex ${tmp_dir}/oov.list ${outfile}/dict/vocab
#
#phonetisaurus-g2pfst --print_scores=false --model=data-prep/lexicon/g2p_wfsa --wordlist=${tmp_dir}/oov.list | grep -P -v "\t$" > ${tmp_dir}/oov.lex
#cat ${tmp_dir}/oov.lex ${tmp_dir}/known.lex | LC_ALL=C sort -u > ${outfile}/dict/lexicon.txt

utils/prepare_lang.sh ${outfile}/dict "<UNK>" ${outfile}/local ${outfile}


for knd in $(seq ${order} -1 0); do
    INTERPOLATE=$(seq 1 ${order} | sed "s/^/-interpolate/" | tr "\n" " ")
    KNDISCOUNT=""
    if [ $knd -ge 1 ]; then
         KNDISCOUNT=$(seq 1 $knd | sed "s/^/-kndiscount/" | tr "\n" " ")
    fi
    WBDISCOUNT=""
    if [ $knd != ${order} ]; then
        WBDISCOUNT=$(seq $((knd+1)) ${order} | sed "s/^/-wbdiscount/" | tr "\n" " ")
    fi

    echo $KNDISCOUNT $WBDISCOUNT

    cat data-prep/ngram/[1-${order}]count | ngram-count -memuse -read - -lm ${outfile}/arpa -vocab ${outfile}/dict/vocab -order ${order} $INTERPOLATE $KNDISCOUNT $WBDISCOUNT

    if [ $? == 0 ]; then
        break
    fi
done

arpa2fst ${outfile}/arpa | fstprint | utils/eps2disambig.pl | utils/s2eps.pl | fstcompile --isymbols=${outfile}/words.txt \
      --osymbols=${outfile}/words.txt  --keep_isymbols=false --keep_osymbols=false | \
     fstrmepsilon | fstarcsort --sort_type=ilabel > ${outfile}/G.fst

utils/validate_lang.pl ${outfile}