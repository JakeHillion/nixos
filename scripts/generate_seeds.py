#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3Packages.nltk

import random
from nltk.corpus import wordnet as wn

# TODO: can I make a Nix derivation for this and point nltk at it?
# import nltk; nltk.download('wordnet')

def get_adjectives_and_nouns():
    adjectives = [word for word in wn.all_lemma_names(pos='a') if len(word) > 1 and '_' not in word and '-' not in word]
    nouns = [word for word in wn.all_lemma_names(pos='n') if len(word) > 1 and '_' not in word and '-' not in word]
    return adjectives, nouns

adjectives, nouns = get_adjectives_and_nouns()

def generate_random_word_list(N):
    selected_adjectives = random.sample(adjectives, N)
    noun = random.choice(nouns)
    return selected_adjectives + [noun]

while True:
    random_word_list = generate_random_word_list(2)
    input(' '.join(random_word_list))
