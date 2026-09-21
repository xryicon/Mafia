# Tutorial narration

Eight locally generated Kokoro clips, using the approved 85% `am_michael` / 15% `im_nicola` voice blend, English phonemes, speed 0.98, and full-precision inference. This is synthetic narration, not an actor imitation or a guaranteed New York Italian-American accent. Subtitles use the same text in `lib/tutorial-steps.json`.

Generate again with Node.js: run `npm install` in `scripts/voice`, then `npm run generate`. The first run downloads the model and voices; inference runs locally on CPU. No API key is required. Generator dependencies are separate from the game build. Only the WAV clips ship to players.

Sources: https://huggingface.co/hexgrad/Kokoro-82M and https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX (Apache 2.0); JavaScript implementation: https://github.com/hexgrad/kokoro/tree/main/kokoro.js (Apache 2.0). Model weights are not included in this repository.

Tutorial starts only on request and never performs game actions. Progress is stored per player in this browser, not synced across devices. Skip preserves the current step; Finish enables replay from the beginning. Audio failure leaves all instructions readable.

