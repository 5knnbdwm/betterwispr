# Local transcription accuracy

Research reviewed 2026-10-08. Measured below are read speech, accented
video-call conversation, held-out Indian English, recorded meetings with speaker
labels, long talks and an interview transcribed from video files, meeting notes
judged against their transcripts, and Light cleanup on 290 dictations saved on
the development Mac. Recognition accuracy on natural
dictation is still not measured: BetterWispr keeps no dictation audio, so there
is nothing to score a reference against.
The goal is to reduce real dictation errors on the user's hardware and languages;
neither a model leaderboard nor a paper justifies claiming "best accuracy" for
this application. A network-denied Tiny-model file smoke test and digital-silence
check passed; [the validation record](testing.md) documents their narrow scope.
The consented dictation corpus under Reproducible evaluation remains a plan.

## What the evidence supports

| Primary source | Finding and practical implication |
| --- | --- |
| [Radford et al., Whisper, arXiv:2212.04356](https://arxiv.org/abs/2212.04356) | Large multilingual weak supervision produced strong zero-shot generalization. Use Whisper as a credible baseline, then measure accent, language, microphone and domain errors rather than assuming every subgroup performs equally. |
| [Gandhi et al., Distil-Whisper, arXiv:2311.00430](https://arxiv.org/abs/2311.00430) | Distillation reduces inference cost while retaining much of the teacher's performance on the evaluated English tasks. This makes distilled models useful latency candidates; the reported numbers are not a guarantee for multilingual dictation or this Mac. |
| [Bain et al., WhisperX, arXiv:2303.00747](https://arxiv.org/abs/2303.00747) | VAD-based segmentation improves long-form transcription and enables batching. Preserve speech boundaries and context when segmenting; forced alignment helps timestamps but does not independently repair wrong words. |
| [Barański et al., arXiv:2501.11378](https://arxiv.org/abs/2501.11378) | Non-speech audio can produce recurring hallucinations. Include silent/noisy negative examples in the benchmark. The paper's phrase filtering motivates evaluation, not unconditional deletion of phrases a user may actually say. |
| [Romana et al., arXiv:2311.00867](https://arxiv.org/abs/2311.00867) | Filled pauses were the easiest disfluency to detect (recall 1.00 in the authors' setup), repetitions came next and restarts were the hardest. A fixed English filler list is a sound first step. Repairs and restarts need a trained model, not rules. |
| [Zayats et al., arXiv:1904.04388](https://arxiv.org/abs/1904.04388) | Repetitions were 46% of disfluent words in their data, and intended repetitions were only 4% of all repetitions, usually emphasis such as "a long long time ago". Collapsing adjacent repeats is usually right when emphatic and grammatical doubles are protected. |
| [Andrusenko et al., arXiv:2406.07096](https://arxiv.org/abs/2406.07096) | A CTC word spotter that rescores a transducer's output raised recall of listed terms at a small precision cost. This is the route for names and jargon with Parakeet. FluidAudio implements it with a separate CTC model that must be installed explicitly. |
| [Jogi et al., arXiv:2502.11572](https://arxiv.org/abs/2502.11572); [Peng et al., arXiv:2305.11095](https://arxiv.org/abs/2305.11095) | A Whisper keyword-list prompt helped rare words but raised average WER, and word-list prompts hurt multilingual models. The comma-joined Whisper vocabulary prompt should be measured with and without hints before it stays on by default. |
| [Andrusenko et al., TurboBias, arXiv:2508.07014](https://arxiv.org/abs/2508.07014) | A phrase-boosting tree applied during greedy decoding of an attention encoder-decoder (Canary) raised listed-phrase F-score from 52.6 to 75.6 with precision falling from 97 to 93. Whisper is the same model family, so a WhisperKit logits filter is the candidate replacement for the keyword prompt. The transfer to Whisper is unmeasured. |
| [Jamshid Lou and Johnson, arXiv:2004.05323](https://arxiv.org/abs/2004.05323) | Filled pauses and discourse markers "belong to a finite set of words and phrases" and are trivial to detect in parsed transcripts, while self-repairs need a trained model. This supports a closed filler list and no rule-based repair guessing. |
| [arXiv:2509.20321](https://arxiv.org/abs/2509.20321) | On a deletion-only disfluency benchmark, LLM cleaners were weakest on fillers and discourse markers, and reasoning models over-deleted fluent words. Over-deletion is the main failure to guard against. |
| [arXiv:2307.04008](https://arxiv.org/abs/2307.04008) | Shipping dictation products edit with flat templates invoked by trigger words, and open-ended spoken editing reached 30% to 55% end-state accuracy. Spoken edit commands should be a closed trigger set. |
| [arXiv:2503.06924](https://arxiv.org/abs/2503.06924) | Prompting Whisper large-v3 with filler words ("um, uh") caused inserted sentences, loops and invented text. Never put fillers in a Whisper prompt. |
| [arXiv:2402.08021](https://arxiv.org/abs/2402.08021) | About 1% of Whisper transcripts contained hallucinated phrases, and longer non-vocal duration predicted them. Trimming long pauses before decoding is the evidenced mitigation. |
| [Gu et al., arXiv:2405.15216](https://arxiv.org/abs/2405.15216); [Pu et al., arXiv:2310.11532](https://arxiv.org/abs/2310.11532) | Zero-shot LLM correction degraded strong recognizer output, and correcting every utterance raised WER. A general LLM rewrite is not an accuracy fix. |
| [Orhon et al., WhisperKit, arXiv:2507.10860](https://arxiv.org/abs/2507.10860) | On-device inference optimization can combine useful latency with low WER in the authors' benchmark. Treat it as evidence that local execution is viable, not a measurement of BetterWispr or proof that every feature is in the public OSS SDK. |

## Models to compare

Start with the same recordings and identical scoring for Whisper small, large-v3
turbo, and large-v3. Small is a practical low-resource starting point; turbo is
the latency candidate; large-v3 is the quality candidate. These roles are
hypotheses to test on target Macs. The publisher describes turbo as a pruned
large-v3 with four decoder layers instead of 32 and a speed/quality tradeoff.
[Whisper large-v3-turbo model card](https://huggingface.co/openai/whisper-large-v3-turbo).

WhisperKit provides a native Swift/Core ML route on Apple Silicon, while
whisper.cpp provides a separate local inference route. Quantized and unquantized
weights should have separate benchmark rows. A model file cached locally is
required for offline use; downloading an engine/model is an explicit setup step.
[Argmax OSS](https://github.com/argmaxinc/argmax-oss-swift),
[whisper.cpp](https://github.com/ggml-org/whisper.cpp).

For a later provider, compare Parakeet TDT 0.6B v3 on its supported languages. Its
publisher lists 25 European languages; it is not a universal replacement for
Whisper and does not list Hindi. A published server benchmark does not establish
latency on a Mac or preserve accuracy after conversion/quantization.
[NVIDIA model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3).

## Accuracy work, in order

1. **Preserve the audio.** Resample once to the engine's required rate; avoid
   clipping, incorrect channel mixing and sample loss during start/stop. Include
   very short utterances and speech at both recording boundaries. Keep a visible
   microphone level and actionable permission/device errors.
2. **Reject empty input carefully.** A signal-energy gate catches silence, not
   speech reliably: keyboard noise can pass and quiet speech can fail. Measure a
   trained VAD with onset padding and trailing hangover before relying on it to
   remove audio. Tune false rejection and hallucination rates together. The
   current shared Whisper provider rejects digital silence before decoding;
   this fixed an observed Tiny-model insertion on an all-zero WAV. That guard
   and the recorder's adjustable RMS gate are not learned noise classifiers.
   WhisperKit's built-in VAD chunking is also energy-based (`EnergyVAD`).
3. **Control decoding.** Offer the spoken language when known, retain an automatic
   option for mixed use, and transcribe rather than translate. Start deterministic
   decoding; evaluate fallback, no-speech/log-probability thresholds and context
   independently. Whisper's reference implementation exposes these controls and
   notes that previous-text conditioning can cause repetition/failure loops.
   [Reference implementation](https://github.com/openai/whisper/blob/main/whisper/transcribe.py).
4. **Use vocabulary conservatively.** Small user-supplied name/product lists can
   seed supported decoders; a prompt is a hint, not guaranteed recognition. Measure
   exact entity recall and false insertions both with and without hints. Explicit
   user dictionary replacements should respect word boundaries and retain the
   original transcript for correction. Do not rewrite arbitrary near-matches.
   Parakeet uses vocabulary only when the optional phrase booster is installed.
   The booster is FluidAudio's CTC word spotter (arXiv:2406.07096): a separate
   110M CTC model (about 99 MB) scores each listed term against the audio, and a
   decoded word is replaced only when a term fits the audio better. BetterWispr
   uses FluidAudio's stricter `itnDefaultConfig` similarity floors, because the
   default config replaced "We should render" with "Supabase" on a synthetic
   clip, and keeps the punctuation the decoder put around a replaced word. It
   also raises the spelling similarity a replacement needs to 0.65, and keeps
   the decoded words when they already contain the term, because the lower
   floor swapped everyday words for listed terms in conversation (see
   [Phrase booster floor](#phrase-booster-floor-2026-10-10)). Boosting runs
   when the language is English, or automatic and the decoded text reads as English,
   since the booster is English-only. Before that check, automatic mode with a
   vocabulary rewrote a German clip, turning "meine" into "Mike" and "Zauber" into
   "Zowber".
   On two `say`-synthesized clips it corrected the eight listed terms Parakeet v3
   had misspelled and changed nothing when no vocabulary was given. That is a
   smoke test, not an accuracy measurement. WhisperKit 1.1.0 transcribes with
   its greedy sampler only, so biasing methods that need beam search do not
   apply to it without upstream work.
   Spoken commands are not boosted. On 16 `say` clips in two Indian English
   voices, boosting "comma", "at the rate", "question mark", "exclamation mark"
   and "hyphen" with Parakeet v2 fixed 2 clips and broke 11. "In a coma" became
   "in a comma", "the red light" became "the rate light", and the word before a
   command was dropped ("Is this right question mark" became "Is this question
   mark?"). Instead, a vocabulary entry whose replacement is wholly a voice
   command, such as "Kocia Mark" written as "question mark", is applied before
   voice commands, so a user's own mishearing still becomes "?". Those entries
   are not sent as hints. Mishearings such as "coma" and "at the red" are not
   built in, because "in a coma" and "at the red light" are real phrases.
5. **Separate recognition from rewriting.** First measure verbatim output. Local
   formatting or an optional local LLM must be scored separately and must not
   silently change negation, numbers, names or intent. Preserve raw and edited
   text. Broad hallucination blocklists can delete intended speech.
   `TranscriptCleaner` removes only a fixed list of English filled pauses (uh,
   um, er, hmm, mm and their spellings), the discourse marker "you know" when
   commas or a sentence boundary set it off on both sides, and back-to-back
   repeats of one to three words that no punctuation separates. "mm" after a
   number stays as a unit, and "you know?" stays because removing it would turn
   a statement into a question. Digits, number words and a short list of
   grammatical or emphatic doubles ("that that", "had had", "long long") are
   kept. Language detection ignores the fillers, and non-English text is only
   trimmed. It also resolves one narrow self-repair shape: after a comma, a cue
   containing "no" or "I mean" ("sorry, no", "no wait", ", no,", ", I mean,"),
   followed by a word that also appears in the last four words of the same
   sentence. The cleaner deletes from that earlier word through the cue, so "go
   to Pune, sorry, no, to Delhi" becomes "go to Delhi". "Sorry" paired with "no"
   or "I mean" needs no comma, because Parakeet often writes none, so "I live in
   Delhi no sorry I live in Ahmedabad" becomes "I live in Ahmedabad". A repair
   that restarts on a subject pronoun counts only when the word after the
   pronoun repeats too ("I live ... I live"). A lone "sorry", with or without
   commas, counts only when the repair restarts on in, at, on, from, near, into,
   by or with, so "I live in Ahmedabad sorry in Delhi" becomes "I live in
   Delhi" and "meet at 5 sorry at 6" becomes "meet at 6". Otherwise a lone
   "sorry" is an apology ("sorry for the wait", "sorry, the train was late"),
   and "so sorry in" or "sorry in advance" stays.
   "Yes to X, no to Y" and "no wait at all" have no set-off cue, and a repair
   that shares no word ("Pune, sorry, no, Delhi") or repeats only a pronoun ("we
   go, no, we should stay", "I said no sorry I can't") is left alone. "Like",
   "basically", "sort of" and other repairs and restarts are left alone too. A
   closed list covers fillers, but general repairs need a trained model and
   deleting hedges changes meaning ("it basically works").
   History keeps the raw output. On the 38 saved Parakeet transcripts available
   on 2026-10-08, the cleaner removed all 47 uh/um and 4 mm tokens and otherwise
   only collapsed four one-word stutters; no set-off "you know" occurred. Adding
   the repair rule changed one of those 38 outputs, the "Mdabad, sorry, no to
   Dilli" dictation it was written for. Adding the lone "sorry" rule changed none
   of the 190 saved transcripts available on 2026-10-09; three contain "sorry"
   and none restarts on a preposition it shares with the words before it.
   Pairing "sorry" without commas and allowing two-word pronoun restarts changed
   one of the 277 saved transcripts available on 2026-10-11, the "Delhi no sorry
   I live in Ahmedabad" dictation it was written for.

   `VoiceCommands` then writes spoken numbers as digits and spoken symbols as
   @, # and %. "two hundred and fifty thousand" becomes "250,000", "ten
   percent" becomes "10%" and "two point five million" becomes "2.5 million".
   Indian English scales follow the models' own style: "one lakh" becomes "1
   lakh", "two lakh fifty thousand" becomes "2,50,000" with Indian grouping and
   "two point five crore" becomes "2.5 crore". "Twelve hundred" becomes "1200".
   When a larger scale or "hundred" cannot join the number before it, the
   readable part is written as digits and the rest stays as spoken, so "ten
   thousand hundred" becomes "10,000 hundred" and "ten thousand one lakh"
   becomes "10,000 1 lakh".
   "at the rate KV" becomes "@KV", "hashtag launch" becomes "#launch", "issue
   hash forty two" becomes "issue #42" and "kartik at the rate gmail dot com"
   becomes "kartik@gmail.com". Formatting changes how a number is written, not
   its value. A lone digit word ("give me five minutes"), "a hundred times",
   ordinals, spoken digit strings ("5 5 5") and neighbouring number words that
   do not form one number ("nineteen ninety nine", "fifty fifty") stay as
   spoken. These rules run only when the language is English or automatic. The
   raw transcript keeps the model's words, and only the final text changes.

   `EmailDictation` then lays out an explicit spoken request such as "write an
   email to Sarah saying …, best regards, Kartik" as a greeting, a body and a
   sign-off on their own lines. It needs "write", "draft" or "compose" at the
   start and "saying", "that", "telling her" or a similar word after the name,
   so "I will write an email to Sarah" stays as spoken. A sign-off after
   "thanks" or "cheers" needs a capitalized name, because "thanks, see you
   soon" is part of the body. A composed email skips the tone and the Medium
   edit. `TranscriptPolisher` will not follow instructions in the dictation and
   rejects output much longer than the input, so it cannot write the email
   itself.
6. **Measure streaming separately.** Partial text is provisional. Finalize with
   sufficient context, and measure final WER, first-text latency, stop-to-final
   latency and dropped/repeated boundary words. Re-transcribing the full growing
   recording has rising cost; use bounded overlapping chunks only after measuring
   the resulting boundary errors.

These are engineering recommendations inferred from the sources and failure
modes above. They do not imply that VAD, model adaptation, streaming decoding or
an LLM rewrite pipeline are already implemented in BetterWispr.

## Parakeet TDT v3 baseline, 2026-10-09

Measured on an Apple M5 with macOS 26.6.2, a release build of `BetterWisprCLI`
from commit 33f726a plus the uncommitted 0.1.4 changes, FluidAudio 0.17.5 and a
warm model cache. The corpus is 355 read-speech clips fetched by
`scripts/fetch_bench_corpus.py`: 40 evenly spaced clips from each test split of
LibriSpeech (clean and other) and Multilingual LibriSpeech (German, French,
Spanish, Italian, Portuguese, Dutch and Polish), with 35 for German after one
fetch batch failed. This is audiobook speech, not dictation. It measures
recognition and language handling, not the app's cleanup.

| Language | Clips | WER, language chosen | WER, automatic | CER, language chosen | Recognition p50 / p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| English | 80 | 2.46% | 2.46% | 0.79% | 0.046 s / 0.117 s |
| German | 35 | 9.76% | 9.76% | 3.61% | 0.079 s / 0.129 s |
| French | 40 | 5.21% | 4.86% | 2.02% | 0.116 s / 0.133 s |
| Spanish | 40 | 7.50% | 7.50% | 3.21% | 0.105 s / 0.134 s |
| Italian | 40 | 16.49% | 16.49% | 3.27% | 0.102 s / 0.121 s |
| Portuguese | 40 | 5.38% | 5.38% | 2.03% | 0.106 s / 0.129 s |
| Dutch | 40 | 12.85% | 12.85% | 3.82% | 0.080 s / 0.124 s |
| Polish | 40 | 5.35% | 5.35% | 1.16% | 0.108 s / 0.134 s |
| All | 355 | 7.98% | 7.93% | 2.44% | 0.078 s / 0.129 s |

- English splits into 2.30% WER on test-clean and 2.62% on test-other.
- Choosing the language matched automatic detection on every set except French,
  where automatic was better. Parakeet uses the choice only to filter tokens by
  script, so on this corpus it changed nothing that matters.
- Italian and Dutch WER is high while CER stays under 4%. Their most frequent
  differences are archaic spellings in the audiobook references ("esser" for
  "essere", "pria" for "prima", "z n" for "zijn") that the model writes in
  modern form. Read those two rows as an upper bound.
- Recognition took at most 0.28 s on clips of 5 to 17 seconds, 132 to 182 times
  faster than real time, and preparing the cached model took 0.25 to 0.38 s.
  Recognition is not where dictation latency comes from on this Mac.
- Light cleanup changed 2 of the 80 English clips, both by collapsing a doubled
  word the reader said ("And and", "Truly truly"). WER against the verbatim
  reference rose to 2.57%, which is the intended dictation behavior.

### Small language model cleanup experiment

The question was whether a small local model that rewrites the transcript after
recognition helps. The candidate was Superwhisper's
[S1-mini](https://huggingface.co/superwhisper/s1-mini-GGUF), a Qwen3 0.6B
fine-tune, run as GGUF Q4_K_M through Ollama with its published prompt,
temperature 0 and semi-formal styling. It ran after Light cleanup, and its
output had to pass `TranscriptPolisher`'s acceptance check.

- On 20 `say`-synthesized clips in three voices with fillers, repeats,
  self-repairs and fluent controls, scored against the intended clean text,
  WER was 20.3% raw, 16.9% after Light and 2.8% after Light then S1-mini, which
  fixed every repair and repeat clip. The current Medium path with llama3.1:8b
  through Ollama scored 12.4% and raised fluent-control WER to 15.3%. Apple's
  on-device model could not be tested because Apple Intelligence was off.
- On the 80 fluent English clips above, S1-mini changed 7 and raised WER from
  2.57% to 2.98%. In one it deleted a real clause, so "as I could not let you, I
  did not wish to let you go away" became "as I could not let you go away". The
  acceptance check passed all 80 rewrites because it checks length and new
  words, not deletions.
- S1-mini took 0.12 to 0.16 s per call at the median and 0.50 s at most.

S1-mini fixes self-repairs that rules cannot and is fast enough, but it deletes
fluent speech that looks like a restart. It is not part of the app. Shipping it
would need a deletion check measured on both sets, an explicit model download
and a native runtime.

## Accented conversational English, 2026-10-10

Measured on the same Mac with a release build of `BetterWisprCLI` from commit
cd8e2ca and Light cleanup. The corpus is 300 segments of
[EdAcc](https://huggingface.co/datasets/edinburghcstr/edacc) fetched by
`scripts/fetch_bench_corpus.py --accents`: 100 evenly spaced segments per accent
from the validation and test splits, each with at least four words, skipping
segments marked as overlapping, foreign, DTMF or no speech. Tags and the fillers
um, uh, er, hmm and mm are removed from the reference. Segments run 0.5 to 52 s,
4.6 s at the median. This is unscripted video-call conversation with verbatim
references, not dictation, and each accent has few speakers.

| Accent | Speakers | Reference words | v3 | v3, Light | v2 | v2, Light | 110M | 110M, Light |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Indian English | 5 | 1751 | 14.51% | 13.65% | 14.45% | 14.85% | 15.71% | 17.13% |
| Nigerian English | 3 | 2186 | 16.42% | 17.98% | 16.70% | 18.98% | 22.00% | 24.34% |
| Mainstream US English | 16 | 1895 | 16.78% | 14.83% | 17.68% | 17.52% | 16.89% | 18.36% |
| All | 24 | 5832 | 15.96% | 15.66% | 16.34% | 17.27% | 18.45% | 20.23% |

- Bootstrap 95% intervals over clips put v2 minus v3 between -0.7 and +1.4
  points overall and across zero for every accent, so this corpus does not
  separate the two. 110M minus v3 is +1.2 to +3.8 points overall and +3.8 to +7.5
  points on Nigerian English.
- Speakers vary more than accents. Among speakers with more than one segment,
  v3 WER runs from 12.7% to 19.8% for Indian English, 8.0% to 18.0% for Nigerian
  English and 10.0% to 32.5% for US English.
- WER is six to seven times the LibriSpeech figure above for every accent, including
  US English, so conversational speech rather than accent drives most of it.
- With v3, Light cleanup lowered errors on 74 segments by 135 and raised them on
  51 by 117. Most rises are removals of "you know", stutters and repeated words
  that the verbatim reference keeps, which is the intended dictation behavior.
  One is not: "drinking more and more and more" became "drinking more and more".
- Real misrecognitions are mostly similar-sounding words, such as pick for speak,
  pocket for bucket, frames for flames and globe for club, and are most frequent
  in Nigerian English.
- Recognition p50 / p95 was 0.042 s / 0.118 s for v3, 0.041 s / 0.074 s for v2
  and 0.016 s / 0.040 s for 110M. Preparing each model took 4 to 22 s on the
  first load after the rebuild and 0.20 to 0.26 s when run again.

## Parakeet Ultra on conversational English, 2026-10-11

Measured on an Apple M5 with macOS 27.0.1, a release build of `BetterWisprCLI`
from commit 089b2f5 plus the uncommitted 0.1.5 changes, FluidAudio 0.17.5 and
Light cleanup, on the same 300 EdAcc segments as above, fetched again with
`scripts/fetch_bench_corpus.py --accents`. v3 reproduced its earlier row exactly,
so the two runs share clips and scoring.

| Accent | v3 | v3, Light | Ultra | Ultra, Light | Ultra minus v3, 95% interval |
| --- | ---: | ---: | ---: | ---: | ---: |
| Indian English | 14.51% | 13.65% | 13.42% | 13.36% | -2.16 to +0.06 |
| Nigerian English | 16.42% | 17.98% | 14.41% | 16.83% | -3.22 to -0.98 |
| Mainstream US English | 16.78% | 14.83% | 15.46% | 14.25% | -2.36 to -0.31 |
| All | 15.96% | 15.66% | 14.45% | 14.95% | -2.14 to -0.86 |

- Intervals are a 2000-sample bootstrap over segments of the recognition WER
  difference. Ultra had fewer errors on 75 segments, more on 28 and the same on 197.
- Recognition p50 / p95 was 0.041 s / 0.114 s for v3 and 0.041 s / 0.112 s for
  Ultra, so Ultra costs no speed. Preparing Ultra from the cache took 0.30 s.
- On this evidence Ultra replaced v3 as the recommended model. The meeting
  notetaker transcribes 3 to 11 second chunks of call audio, close to these
  segments. Recorded meetings are scored under Meetings and speakers below.

## Trailing silence and VAD before Parakeet, 2026-10-12

Measured on an Apple M5 with macOS 27.0.1, release builds of `BetterWisprCLI`
from commit 18bbac4, FluidAudio 0.17.5, `--language en` and Light cleanup, on
the same 300 EdAcc segments as above. VoiceInk appends one second of silence
before transcribing, and the question was whether Parakeet gains from it. In
VoiceInk's source the 16,000-sample pad sits on the Nemotron streaming path
only. Its Parakeet path runs FluidAudio's Silero VAD at threshold 0.7, joins
the speech segments and pads only up to FluidAudio's minimum length. Both ideas
were measured anyway, because FluidAudio masks its own 15 s zero padding by the
original length, so appended zeros are decoded as audio.

Each variant replaced the plain Parakeet path in a bench-only build. The
variants were the resampled samples with 16,000 zeros appended, and VAD
(threshold 0.7, FluidAudio's segmentation defaults) followed by the same
padding. A control that passed the resampled samples without padding
reproduced the unchanged URL path on every clip, so resampling itself changes
nothing. The unchanged path reproduced itself exactly on three runs.

| Accent | Ultra | Padded | Padded minus Ultra, 95% interval | VAD, padded | VAD minus Ultra, 95% interval |
| --- | ---: | ---: | ---: | ---: | ---: |
| Indian English | 13.42% | 13.42% | -0.60 to +0.75 | 13.48% | -0.58 to +0.82 |
| Nigerian English | 14.41% | 15.05% | -0.08 to +1.38 | 15.05% | -0.10 to +1.38 |
| Mainstream US English | 15.46% | 16.09% | -0.22 to +1.59 | 15.94% | -0.52 to +1.54 |
| All | 14.45% | 14.90% | +0.02 to +0.91 | 14.87% | -0.05 to +0.89 |

| Accent | v3 | Padded | Padded minus v3, 95% interval | VAD, padded | VAD minus v3, 95% interval |
| --- | ---: | ---: | ---: | ---: | ---: |
| Indian English | 14.51% | 14.62% | -0.63 to +0.86 | 14.68% | -0.63 to +0.97 |
| Nigerian English | 16.42% | 16.33% | -1.10 to +0.92 | 16.79% | -0.70 to +1.39 |
| Mainstream US English | 16.78% | 18.21% | +0.14 to +3.10 | 18.15% | +0.11 to +3.08 |
| All | 15.96% | 16.43% | -0.16 to +1.17 | 16.60% | +0.00 to +1.34 |

- Intervals are a 2000-sample bootstrap over segments of the recognition WER
  difference. Padding gave Ultra fewer errors on 25 segments, more on 36 and
  the same on 239. VAD with padding gave 31, 42 and 227. For v3 the counts are
  31, 43 and 226 with padding and 33, 52 and 215 with VAD. With Light cleanup
  every difference stays positive: +0.45 for padded Ultra, +0.65 for VAD Ultra,
  +0.63 and +0.79 for v3.
- The loss sits in 5 to 15 s segments, where the appended second is no longer
  masked. Ultra went from 11.15% to 11.90% there, with 7 segments better and 20
  worse. Segments over 15 s moved by less than 0.3 points either way. Segments
  under 2 s did not change with Ultra, but with v3 three of them collapsed.
  "They just have to like keep it." became "Yeah." and "Okay, no, it's it's
  okay." became empty.
- Other changes are formatting flips rather than recognition. With padded Ultra
  "C eleven dash P two" became "C11 dash P2" and "a hundred percent" became
  "100%". The one clear gain, "Hawaii." becoming "to think is made in Hawaii.",
  is a single segment.
- VAD removed audio from 13 of 300 segments and emptied one 0.4 s segment. The
  other 287 only received the padding, so VAD with padding differs from padding
  alone on 20 segments, -0.21 to +0.14 points. The EdAcc segments are already
  cut to speech, so this corpus cannot show what VAD does to the room tone a
  dictation recording keeps around the hotkey press and release.
- Recognition p50 / p95 stayed between 0.065 s / 0.140 s and 0.105 s / 0.248 s
  for every variant, including identical baseline runs, with the Mac at a load
  average of 4 to 6 on 10 cores from parallel builds. No speed claim is made.
- VAD needs the `silero-vad` CoreML model, which FluidAudio downloads on first
  use. For the bench it was fetched into a temporary directory, never into the
  app's model folder.
- Nothing shipped. The rule for keeping a variant was an upper bound at or
  below +0.3 points with a mean no worse than the baseline on Ultra. Padding is
  +0.45 with an upper bound of +0.91 and VAD is +0.41 with +0.89. The provider
  is unchanged.

## Phrase booster floor, 2026-10-10

Measured on the same Mac with release builds of `BetterWisprCLI`, Parakeet v3,
English and Light cleanup, using `--bench MANIFEST --model parakeet-v3
--vocabulary "A,B,…"`. Three runs per setting:

- **Absent.** The 300 EdAcc segments above with 20 product and name terms that
  none of them say (Granola, Vercel, Supabase, Kubernetes, Postgres, Figma,
  Notion, Linear, Slack, Mem0, BetterWispr, Parakeet, Claude, Anthropic,
  Tailwind, Ollama, Sparkle, Labhshetwar, Kartik, MDX). Any change is a false
  replacement.
- **Present.** The same segments with 14 names they do say (Eragon, Paolini,
  Cinna, Dubai, Thai, Arabian, Harry Potter, Edinburgh, Instagram, Wikipedia,
  Manchester, Glasgow, London, Lisbon). A replacement is counted true when the
  new words appear in the reference.
- **Synthetic.** 84 clips from macOS `say`: 12 sentences using the absent
  terms, read by Rishi and Aman (Indian English), Daniel, Karen, Moira, Tessa
  and Samantha. The clips are not committed.

| Setting | Absent WER | Absent clips changed | Present WER | Present true / false | Synthetic WER | Synthetic true / false |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| No vocabulary | 16.22% | 0 | 16.22% | 0 / 0 | 14.29% | 0 / 0 |
| `itnDefaultConfig` (0.1.4 before this fix) | 17.42% | 44 | 16.90% | 4 / 47 | 7.14% | 41 / 7 |
| Floor 0.60 | 16.74% | 23 | 16.54% | 4 / 27 | 7.14% | 41 / 7 |
| Floor 0.65 | 16.31% | 5 | 16.29% | 4 / 7 | 6.44% | 40 / 0 |
| Floor 0.70 | 16.22% | 0 | 16.27% | 3 / 5 | 8.82% | 25 / 0 |
| Floor 0.75 | 16.22% | 0 | 16.22% | 3 / 3 | 9.10% | 25 / 0 |
| Floor 0.65, decoded words kept when they contain the term | 16.31% | 5 | 16.23% | 4 / 4 | 6.44% | 40 / 0 |

- FluidAudio picks a similarity floor of 0.50 for up to 10 terms and 0.55 for
  11 to 100, and the stricter config does not raise it. At that floor the
  booster turned "not like" and "not seen" into "Notion" and "Thank" into
  "Thai" in conversation that never said them.
- 0.65 is the lowest floor tried that kept all but one synthetic fix and
  removed most false replacements. 0.70 lost 16 of the 41 synthetic fixes.
  The floor was chosen on these same three sets, so it may be tuned to them.
- The rescorer sometimes widened a replacement to a neighbouring word, writing
  "Harry Potter" over "seven Harry Potter", "to Harry Potter" and "with Harry
  Potter". When the decoded words already contain the term, BetterWispr now
  keeps them and does not count a vocabulary fix.
- Remaining false replacements include "list one" to "Lisbon", "cinema" to
  "Cinna" and "Dragon" to "Eragon" in the present set, and "option" to
  "Notion", "cause" to "Claude" and "lines" to "Linear" in the absent set.
- With a non-empty vocabulary, recognition took 0.105 s longer per clip at the
  median than without one (0.153 s against 0.045 s), measured on the absent
  set after the first clip. The first clip also builds the boosting session.
- Turning off FluidAudio's spotter rescue (`FLUID_SPOTTER_RESCUE=0`), tapering
  the weight for short terms, or both, left absent WER at 17.33% to 17.42% and
  present WER at 16.90%, so neither is used.

## Held-out Indian English, 2026-10-12

Measured on an Apple M5 with macOS 27.0.1, release builds of `BetterWisprCLI`
with the 0.1.5 changes, FluidAudio 0.17.5, `--language en` and Light cleanup.
The corpus is every Indian English segment in the EdAcc validation and test
splits with at least four words that the 100 segments above did not use: 597
segments and 12,757 scored words. The segments are new but the speakers are
not, because EdAcc has few Indian English speakers.

| Text scored | v3 | Ultra | Ultra minus v3, 95% interval |
| --- | ---: | ---: | ---: |
| Recognition | 12.33% | 11.51% | -1.33 to -0.38 |
| Light cleanup | 12.11% | 12.05% | -0.63 to +0.41 |

- Intervals are a 2000-sample bootstrap over segments. Shared speakers make
  segments less independent than the bootstrap assumes, so the true intervals
  are wider. Ultra had fewer recognition errors on 115 segments, more on 60 and
  the same on 422.
- Light cleanup cancels Ultra's lead on this set. EdAcc references drop fillers
  but keep repeated words and phrases such as "you know". v3 writes more
  fillers, so cleanup removed 408 fillers and 403 other words from v3 output,
  against 330 and 426 from Ultra. Removing a filler fixes an error against these
  references; removing anything else adds one. Apart from the two repairs below,
  this is a reference convention, not a cleanup fault.

## Light cleanup audit, 2026-10-12

Every segment that Light cleanup changed in the held-out Ultra output was read
against its reference. Two self-correction repairs deleted words the speaker
meant: "in the last book, no, the whole thing with the houses" and "closest to
like, I mean, the first one was obviously very close". Both restart on a recent
word, which was all the repair rule asked for. A real correction such as "to
Pune, sorry, no, to Delhi" ends its clause about as soon as the words it
replaces. The rule now also requires the repair to reach a clause break or the
end of the text within one word more than the words it drops.

- On held-out Ultra the change touched only those 2 segments, and cleaned WER
  fell from 12.12% to 12.05%. It changed no v3 segment. Tests cover both
  lookalikes and "Let's meet at 5, no, at 6 pm."
- Light cleanup was also run on the raw text of 290 dictations saved on the
  development Mac, 35.6 minutes in total. It changed 115 of them and removed 380
  of 5,566 words. Reading every edit found none that dropped meaning, and the
  repair change altered none of them. These dictations have no audio, so their
  recognition WER is not verified.

## Phrase booster on held-out speech, 2026-10-12

The 0.65 floor above was chosen on the sets it was tested on. It was checked on
the 597 held-out segments with the same 20 absent terms and 12 terms those
segments say (Diwali, YouTube, Rowling, Wonderland, COVID, Kerala, Mumbai,
Disney, Google, Christmas, Shakespeare, Hindi). A swap now counts as true when
applying it alone lowers that segment's edit distance to the reference, and
false when it raises it. The earlier count called a swap true when its new words
appeared anywhere in the reference, which scored "Christian countries" to
"Christmas countries" as true in a sentence that also says Christmas.

| Model and terms | No vocabulary | Floor 0.65 (0.1.4), WER and true / false | With the spelling guard |
| --- | ---: | ---: | ---: |
| v3, absent | 12.33% | 12.42%, 0 / 11 | 12.33%, 0 / 0 |
| v3, present | 12.33% | 12.41%, 0 / 10 | 12.34%, 0 / 1 |
| Ultra, absent | 11.51% | 11.61%, 0 / 12 | 11.51%, 0 / 0 |
| Ultra, present | 11.51% | 11.58%, 1 / 10 | 11.51%, 1 / 1 |

- WER is recognition WER. Floor 0.65 alone raised it on all four runs, with
  every 95% interval above zero (0.02 to 0.17 points). It replaced ordinary
  words that sound like a term, such as growing with Rowling and Hindus with
  Hindi.
- The spelling guard keeps the decoded words when they already contain the
  term, or when macOS spell checking accepts them and their letters are less
  than 75% alike to the term. A misspelled name still changes, as "Rivali" did
  to Diwali.
- On the earlier sets the guard removed every false swap. Synthetic went from
  38 true / 7 false to 37 / 0 for v3 and from 35 / 7 to 34 / 0 for Ultra; the
  false swaps wrote Claude where the speaker said "cloud". Absent went from 4
  false and 1 neutral to none for both models. Present went from 4 / 4 to 3 / 2
  for v3 and from 3 / 4 to 3 / 2 for Ultra, and the two left are "Dragon" to
  "Eragon". The fixes lost were "vessel" to Vercel in one synthetic clip and
  "era one" to Eragon for v3.
- The 0.75 threshold was set after the held-out term lists had been seen, so
  the held-out result is not blind. Spell checking uses the macOS English
  dictionary, which includes words the user has taught macOS.

## Names read from the screen, 2026-10-14

Synthetic speech only, on an M4 Pro. macOS `say` read 24 sentences that say
none of 20 names and 10 sentences that say two each, in 7 English voices
(Rishi, Aman, Daniel, Karen, Moira, Tessa, Samantha): 168 absent and 70 present
clips. The names were Joris, Pannekeet, Supabase, Vercel, Mem0, Ollama, Figma,
Raycast, Jira, Kubectl, Qwen3, Kaggle, Opennook, BetterWispr, Prisma, Deno,
Groq, WhisperKit, FluidAudio and PostHog. Most absent sentences use words close
to a name, such as vessel, prism, memo, llama, denote and whisper kit. Every clip got all 20 names with Parakeet Ultra,
`--language en`, the phrase booster installed and no cleanup. Repeated runs
gave identical text.

| Names used as | Absent WER | Absent clips changed, worse | Present WER | Names spelled exactly |
| --- | ---: | ---: | ---: | ---: |
| Not used | 2.15% | | 30.43% | 38 / 140 |
| Vocabulary, with the spelling guard | 7.96% | 55, 54 | 12.63% | 99 / 140 |
| Screen terms, misspelled words only | 2.15% | 1, 0 | 24.64% | 63 / 140 |

- As vocabulary, the names made 54 absent clips worse. All 54 came from the
  eight sentences with prism, Doris, super base, ray cast, grok, better whisper,
  whisper kit and fluid audio, such as prism to Prisma, Doris to Joris and
  whisper kit to WhisperKit. A name on screen is no
  evidence it was said, so screen terms only replace words macOS spell
  checking rejects, such as superbase to Supabase and versal to Vercel.
- That rule loses names Parakeet decodes as real words. BetterWispr, Deno,
  Groq, WhisperKit, FluidAudio and PostHog went from 7, 7, 4, 3, 7 and 7 of 7
  as vocabulary to none as screen terms, heard as "better whisper", Dino, Grog
  or Grott, Whisperkit, "fluid audio" and "post hog". Listing a name in
  Vocabulary still uses the looser guard.
- The one absent change was "jiro rice" to "Jira rice" for "jeera rice", at the
  same edit distance.
- The phrase booster pass cost about 12 ms per second of audio, nearly
  independent of the number of names. A 79 second clip took 0.22 s without
  names, 1.19 s with 20 and 1.11 s with one. With screen terms alone, the pass
  now runs only when the first pass has a misspelled word. That left text
  identical on all 238 clips and kept the 20, 39 and 79 second clips within 3 ms
  of no names. Short clips that say a name usually trigger the pass, so their
  median went from 0.04 s to 0.15 s. Over 0.12 s were 20 of 167 absent and 58 of
  69 present short clips with names, against 3 and 0 without. These counts
  leave out each run's first clip as a warm-up.
- Real speech is not measured. A real window lists fewer, unrelated names, and
  macOS accepts words the user has taught it, so such a capitalized name is not
  passed unless it is mixed-case.

Reproduce with `.build/release/BetterWisprCLI --bench MANIFEST --model
parakeet-ultra --language en --screen-terms "Joris,Pannekeet,…"` against the
same manifest without `--screen-terms`. The clip sentences and the script that
writes the clips and manifest are not committed.

## Meetings and speakers, 2026-10-12

Measured on an Apple M5 with macOS 27.0.1, release builds of `BetterWisprCLI`
with the 0.1.5 changes, FluidAudio 0.17.5, `--language en` and Light cleanup.
Speaker detection here is 0.1.5's FluidAudio 0.17.5 `OfflineDiarizerManager`.
0.1.6 replaced it with Argmax SpeakerKit. Nothing in this section has been
measured with SpeakerKit, including the WER of the split rows, which depends on
where speaker detection hears the voice change.
`--meeting` plays a file through the app's meeting chunker as call audio,
transcribes each chunk as a meeting does and labels voices with Speaker
detection. `scripts/evaluate_meetings.py` scores the segments against
speaker-timed references. `scripts/fetch_bench_corpus.py DIR --meetings` builds
two corpora:

- **AMI.** The first 10 minutes of four test meetings (ES2004a, IS1009a,
  TS3003a, EN2002a), four speakers each, every headset mixed into one track at
  its original time, so speakers overlap as they did in the room. 5,917
  reference words.
- **EdAcc.** Up to 5 minutes from each of six two-person video calls (C05, C09,
  C29, C34, C36, C41), turns joined with 0.3 s gaps. 5,008 reference words.

WER is on cleaned text and raw WER on the recognized text. Voices are paired
with reference speakers one to one, choosing the pairing that credits the most
words. Accuracy is the share of words in segments labelled with the voice
paired to the segment's main speaker. Attribution credits each segment by how
much of it the paired speaker said, so a chunk that holds two speakers loses
the words of the second. Purity is the share of each segment said by its main
speaker, the most attribution can reach with one label per segment.

| AMI, 4 meetings | WER | Raw WER | Accuracy | Purity | Attribution |
| --- | ---: | ---: | ---: | ---: | ---: |
| v3 | 25.65% | 26.64% | 92.8% | 81.0% | 78.6% |
| Ultra, chunks as 0.1.4 | 22.76% | 22.87% | 91.8% | 79.7% | 77.3% |
| Ultra, split at voice changes | 23.20% | 23.39% | 95.4% | 84.9% | 82.4% |

| EdAcc, 6 calls, Ultra | WER | Raw WER | Accuracy | Purity | Attribution |
| --- | ---: | ---: | ---: | ---: | ---: |
| Chunks as 0.1.4 | 13.72% | 13.02% | 92.8% | 86.7% | 85.1% |
| Split at voice changes | 14.08% | 13.32% | 98.1% | 93.8% | 93.3% |

- A chunk ends at a 0.6 s pause once it is at least 3 s long, or at 20 s, so
  one chunk often held two speakers under one label. BetterWispr now cuts a chunk where
  Speaker detection hears the voice change and transcribes each piece again.
  Turns shorter than 1 s stay with their neighbour. Attribution rose on all six
  calls and on three of the four meetings, and WER rose by about 0.4 points
  because the pieces are shorter. TS3003a, mostly one speaker, fell from 96.0%
  to 95.2%. No interval was computed for these differences.
- Shorter chunks were tried first and not kept. On AMI a 0.3 s pause with a 3 s
  minimum gave 23.3% WER and 80.4% attribution, and a 0.2 s pause with a 1 s
  minimum gave 27.1% and 82.6%. Shortest turns of 0.5 s and 2 s gave 82.6% and
  80.9% attribution, against 82.4% at 1 s.
- Per AMI meeting with the split: ES2004a 20.2% WER and 79.9% attribution,
  IS1009a 21.8% and 82.5%, TS3003a 13.5% and 95.2% with one speaker saying 96%
  of the words, EN2002a 30.8% and 76.6%.
- Speaker detection found 4 voices for the 2 people in call C05. Splitting
  sends each piece through recognition again, which adds requests and cost when
  an API connection is selected.
- Mixed headsets are cleaner than a laptop microphone in a room, and the EdAcc
  calls are rejoined turns rather than continuous call audio. Neither corpus
  went through the app's live capture.
- The EdAcc rows were scored on a corpus built by an earlier version of the
  fetcher. Rebuilt with the committed `--meetings`, Ultra with the split scored
  14.20% WER, 13.36% raw WER, 97.9% accuracy, 94.1% purity and 93.2%
  attribution, each within 0.3 points of its row.

## Meeting notes, 2026-10-12

Notes came from Apple Intelligence through `BetterWisprCLI --meeting
SEGMENTS.jsonl --notes OUT.md`, on the Ultra segments of seven meetings, three
runs each, with the builds before and after the notes changes. Three meetings
(IS1009a, ES2004a, EN2002a) were used while making the changes and four
(TS3003a, C05, C09, C41) were held out. One Claude model judged each file blind
against its transcript, with before and after shuffled as A and B per meeting.
It counted claims the transcript does not support, filler items such as "No
explicit decisions were made", statements given to the wrong person, factual
errors and missed follow-ups, and rated usefulness from 1 to 5. Numbers are per
file.

| Measure | Before, all (19 files) | After, all (21) | Before, held out (12) | After, held out (12) |
| --- | ---: | ---: | ---: | ---: |
| Unsupported claims | 4.05 | 1.33 | 2.75 | 0.58 |
| Filler items | 1.37 | 0.24 | 1.75 | 0.25 |
| Misattributed | 2.16 | 0.95 | 2.25 | 0.33 |
| Factual errors | 0.42 | 0.29 | 0.25 | 0.17 |
| Missed follow-ups | 0.11 | 0.19 | 0.08 | 0.17 |
| Usefulness | 2.53 | 3.29 | 2.67 | 3.83 |

- Before the changes, 2 of 3 EN2002a runs failed with "couldn't condense". The
  condense prompt made the model copy transcript lines, so each round came back
  as long as it went in. Condensing now asks for a third-person summary with a
  word target, and never writes as Me.
- The notes prompt now defines a decision as something the group agreed on and
  an action item as a follow-up someone took on, and gives Me a task only when
  Me's own words take it on. Items such as "None" or "No decisions were made",
  which the model wrote instead of an empty list, are dropped. An item that
  starts with "None of", such as "None of the current vendors will be renewed",
  stays, but a real decision that starts with "Nothing" or "No decision" is
  still dropped. Every decision and action item starting with "no", "none" or
  "nothing" in these runs, in the drafts made while changing the notes and in
  21 more runs was filler, and the filter drops all of them.
- IS1009a got worse on misattribution, 4 before and 12 after across three
  runs. Every run before and after wrote "12.50 euro" as 1250.
- One judge model scored the notes, and no person checked its counts.

## Files and links, 2026-10-14

Measured on an Apple M4 Pro with macOS 27.0.1, release builds of
`BetterWisprCLI`, FluidAudio 0.17.5, Parakeet Ultra, `--language en` and Light
cleanup. The corpus is the audio and English captions of three TED videos on
YouTube: a 20 minute talk, a 41 minute interview between two people
(`zIwLWfaAg-8`) and a 21 minute talk (`iCvmsMzlF7o`). Each reference is the
caption text without cue timings, speaker prefixes, tags or parenthesized sound
notes. Both sides are normalized as `scripts/evaluate_transcripts.py` does, and
the cleanup's filler words (uh, um, er, hm, mm and their spellings) are removed
from both. Word errors are the word edit distance. The captions are edited and
leave out disfluencies, so insertions are high and about the same for every
policy. The audio and captions are not committed.

The chunk policy came first. Each pause-cut row cut a 16 kHz WAV copy of the
file at the quietest point of a 300 ms moving average of 10 ms levels inside its
window and sent the pieces through `--bench`. The whole-file row sent the file
in one call, and the meeting chunker row played it through `--meeting`.

| Policy | TED talk, 3,249 words | Interview, 6,139 | Talk 2, 3,204 | Total |
| --- | ---: | ---: | ---: | ---: |
| Whole file in one call | 243 | 873 | 166 | 1,282 |
| Pause cut, 8 to 14.5 s | 244 | 865 | 158 | 1,267 |
| Pause cut, 15 to 29.5 s | 240 | 843 | 173 | 1,256 |
| Pause cut, 30 to 59.5 s | 230 | 840 | 159 | 1,229 |
| Pause cut, 60 to 119.5 s | 233 | 847 | 157 | 1,237 |
| Meeting chunker, 3 to 20 s | 257 | 909 | 169 | 1,335 |

- The meeting chunker loses words. It deleted 42, 95 and 35 words against 17,
  74 and 26 for the 60 to 119.5 s cut. Its 3 s minimum, forced 20 s cuts and
  speech gate suit live calls, not files.
- Files and links are cut at the quietest point 30 to 59.5 s after the previous
  cut, and every chunk is transcribed. 59.5 s fits in one 125 s request of an
  API connection and stays under the 120 s base timeout of Apple speech.
- No interval was computed. The 30 and 60 second rows differ by 8 errors in
  12,592 words, which does not establish that either is better. The shorter
  chunks were kept for the engine limits.

The Swift `--media` command, which the app shares, on 2026-10-15:

| Input | Word errors | Substituted | Deleted | Inserted |
| --- | ---: | ---: | ---: | ---: |
| TED talk, m4a | 235 | 45 | 18 | 172 |
| Interview, m4a | 839 | 132 | 79 | 633 |
| Talk 2, m4a | 159 | 28 | 26 | 106 |
| TED talk, mp3 | 241 | 41 | 17 | 183 |
| TED talk, mp4 with a video track | 249 | 43 | 19 | 187 |

- The three m4a files total 1,233 errors against 1,229 for the prototype's
  30 to 59.5 s row, at most 5 apart on any file. The port decodes with
  AVFoundation and `AVAudioConverter` instead of `afconvert`, so its levels and
  cut points can differ slightly.
- A second m4a run of the TED talk gave the same text, raw text and timings.
- The mp3 and mp4 are ffmpeg conversions of the TED m4a. The mp4's cuts land
  about 48 ms after the m4a's, likely AAC encoder priming, so a few words around
  each cut change. Neither row is a claim about format accuracy.
- The substituted, deleted and inserted counts come from a difflib alignment and
  only approximate the split of the edit distance.
- Whisper, Apple speech and API connections were not measured. No Whisper model
  is installed on this Mac.

Speaker detection, after the rebase onto the SpeakerKit detection from #34, on
2026-10-15. The interview captions name the speaker of each turn, so each
second of a labelled segment was compared with the captioned speaker under that
second. A turn change inside a cue was placed by its character position.

| Input | Captioned seconds | Agree with the captions | Voices |
| --- | ---: | ---: | --- |
| Interview, m4a | 2,259 | 94.3% | 1 and 3 for the host, 2 for the guest |
| TED talk, m4a, one speaker | none | | 1 for 96.2% of the audio, 2 for 0.7%, 3 for 3.0% |

- The agreement uses the voice to speaker mapping that agrees best. Segments
  are 30 to 59.5 s chunks, or the pieces a chunk is split into when several
  voices speak in it, so a segment that still holds both people counts against
  the score.
- The TED talk scored 237 word errors with detection, against 235 without it.
  Detection transcribes a split chunk again in pieces, so the text changes a
  little. This was one run, not a measurement of either way.

## Reproducible evaluation

Create a consented local corpus of natural 3–30 second dictation clips, with a
smaller set of longer clips, spanning built-in/USB/Bluetooth microphones, quiet
and noisy rooms, accents, English/Hindi and code-switching where relevant, names,
technical vocabulary, numbers, negation, soft speech, restarts, repeated words
and silence. Keep validation and test speakers separate. Write transcripts by
listening to the audio, not by editing one model's output. Keep audio and private
transcripts outside Git; publish only recordings you have permission to share.

Record the app commit, engine/version, model ID and checksum, precision, language,
vocabulary, decoding/VAD settings, hardware, OS, audio checksum, sample rate and
whether the model was warm. Run the same clips through each candidate. Save one
UTF-8 JSON object per line:

```json
{"id":"001","reference":"Send the draft tomorrow","hypothesis":"Send a draft tomorrow"}
{"id":"silence-001","reference":"","hypothesis":""}
```

`BetterWisprCLI --bench` writes these lines for a manifest of clips, and
`scripts/fetch_bench_corpus.py` builds the read-speech manifest used above, with
`--accents` the EdAcc manifest, or with `--meetings` the AMI meetings and EdAcc
calls, each a WAV file and a JSON file of speaker turns.

```sh
python3 -I scripts/fetch_bench_corpus.py /tmp/bench 40
python3 -I scripts/fetch_bench_corpus.py /tmp/accents 100 --accents
python3 -I scripts/fetch_bench_corpus.py /tmp/meetings --meetings
swift build -c release --product BetterWisprCLI
.build/release/BetterWisprCLI --bench /tmp/bench/manifest.jsonl --model parakeet-v3 > results.jsonl
.build/release/BetterWisprCLI --meeting /tmp/meetings/ami-ES2004a.wav --model parakeet-ultra --language en > ES2004a.jsonl
python3 scripts/evaluate_meetings.py /tmp/meetings/ami-ES2004a.json ES2004a.jsonl
.build/release/BetterWisprCLI --meeting ES2004a.jsonl --notes ES2004a.md
.build/release/BetterWisprCLI --media talk.m4a --model parakeet-ultra --language en > talk.jsonl
python3 scripts/evaluate_transcripts.py results.jsonl --group language
python3 scripts/evaluate_transcripts.py /path/to/pairs.jsonl
python3 scripts/evaluate_transcripts.py /path/to/pairs.jsonl --raw
python3 Tests/evaluate_check.py
```

The dependency-free evaluator reports corpus-weighted WER (total word edit
distance / total reference words), CER (Unicode code-point edit distance /
reference code points, excluding whitespace), and the fraction of annotated
silent clips with any non-whitespace output. WER can exceed 1. Insertions on
silent clips count in corpus errors; all-silence input reports `null` WER/CER
because their denominators are zero. An empty file or invalid text fields fail.

Default scoring lowercases, normalizes to NFC, preserves letters/marks/numbers
and replaces punctuation/symbols with spaces. `--raw` preserves case,
punctuation and symbols, while word splitting and CER still ignore whitespace.
Neither mode normalizes spoken numbers or abbreviations. This is not Whisper's
official English normalizer, so scores are not directly comparable to published
leaderboards. Whitespace WER is unsuitable for unsegmented languages; use the
documented CER, and introduce a fixed language-specific tokenizer before making
word-based comparisons. CER here counts code points, not grapheme clusters.

Run per-language/accent/device subsets separately; do not let an easy majority
hide regressions. Add exact-match rates for names and numbers, human correction
time, false speech rejection, hallucinated words per silent minute, p50/p95
latency, real-time factor and peak memory. The script measures text errors only;
timing, memory, entity analysis and bootstrap confidence intervals require a
separate experiment log. Retain individual clip pairs to support paired
resampling. Do not accept a default-model change until accuracy and usability
improve on the held-out corpus and silence/boundary tests still pass.
