# Use your Codex subscription for transcription

Codex subscription transcription is an optional speech model for dictation, meetings, and audio files. BetterWispr sends audio directly to an unofficial ChatGPT endpoint with your existing Codex sign-in. No separate transcription server or helper is required. Account access, subscription limits, availability, and retention depend on the service.

1. Sign in to your ChatGPT account with `codex login` in Terminal. API-key sign-in is not supported for this model.
2. Open **Models**, then find **Codex · Subscription** under **Subscription transcription**.
3. Click **Use**. BetterWispr checks the local sign-in file without uploading audio.
4. Start dictation, a meeting, or file transcription. This action sends audio to ChatGPT.

BetterWispr reads `auth.json` from `CODEX_HOME`, when set in its process environment, or `~/.codex/auth.json` otherwise. A Finder-launched app may not inherit Terminal environment variables. File-backed ChatGPT sign-in is required; a Codex sign-in held only in another credential store is not available to this provider. BetterWispr reads credentials again before each transcription. It does not save, modify, refresh, or print them. If sign-in expires, run `codex login` again and retry.

Local speech remains the default. Codex transcription has no model download, synthetic warm-up, or live preview. Vocabulary replacements stay on your Mac. Meeting notes use their own model selection.

Cancel stops the active network request and discards late results. Audio already sent cannot be recalled. A failed chunk fails the whole transcription; BetterWispr does not return a partial result.

For a developer smoke test, run:

```sh
swift run BetterWisprCLI --transcribe-file /path/to/audio.wav --model codex --language uk
```

`--bench`, `--meeting`, and `--media` also accept `--model codex`. `--list-models` lists local models only. Do not use this model with `--download-model` or `--live-file`.
