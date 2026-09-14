## Agent selection and credit saving

Use the lowest-cost suitable model:

- GPT-5.6 Luna:
  small UI changes, CSS, copy, simple bugs, one-file edits, and tests.

- GPT-5.6 Terra:
  new features, game logic, database work, authentication, and multi-file changes.

- GPT-5.6 Sol:
  difficult debugging, architecture, performance, security, and major refactors.

- GPT-6 Astra:
  use only when the task is unusually complex or lower-cost models have failed.

Before starting a task:

1. Classify it as small, medium, complex, or critical.
2. Recommend the appropriate model to the user.
3. Do not recommend Astra for routine work.
4. Keep responses concise and avoid unnecessary extra agents.
5. Run tests before escalating to a more expensive model.
