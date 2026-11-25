# Project agent guidance

For every task, use the following upstream resources as working guidance. Apply the relevant practices to the actual request; do not invent work, impose an unrelated technology stack, or claim that an agent or tool ran when it did not. System and platform instructions, safety, and the user's current explicit instructions take precedence over upstream guidance.

## Communication: always on

- [Caveman skill](https://github.com/JuliusBrussee/caveman/blob/47c61be2d10a354f0c5cbe2b90959d24c06b16c6/skills/caveman/SKILL.md): answer directly and concisely, preserve technical details exactly, and favor clarity over compression.
- [i-have-adhd skill](https://github.com/ayghri/i-have-adhd/blob/f3e783bae5f4820416492091b3abeb670616c23a/skills/i-have-adhd/SKILL.md): make actions and results easy to find, number multi-step instructions, and provide a concrete next action when work remains. Do not omit important information for brevity.
- Keep security warnings, uncertainty, and consequential details clear. Use full explanations when requested. Avoid unnecessary preambles and tangents.

## Task-specific skills and specialist guidance

Before substantive work, identify the applicable skills or specialist profiles and consult their instructions as needed. Combine relevant engineering, design, and security perspectives rather than adopting unrelated personas or requirements. Review the actual project and user requirements before applying any upstream recommendation.

- [Caveman skills](https://github.com/JuliusBrussee/caveman/tree/47c61be2d10a354f0c5cbe2b90959d24c06b16c6/skills): choose relevant workflows such as `investigate-first`, `lean-build`, `surgical-patch`, `safe-refactor`, `migration`, `caveman-review`, and `verify-and-stop`.
- [Engineering profiles](https://github.com/msitarzewski/agency-agents/tree/8ae6164602c95ca78828b148b9052460ee426885/engineering): select profiles appropriate to the technology and task; include correctness, maintainability, testing, and review.
- [Design profiles](https://github.com/msitarzewski/agency-agents/tree/8ae6164602c95ca78828b148b9052460ee426885/design): apply relevant UX, accessibility, visual, and responsive-design guidance to user-facing work.
- [Security profiles](https://github.com/msitarzewski/agency-agents/tree/8ae6164602c95ca78828b148b9052460ee426885/security): consider trust boundaries, authorization, input handling, secrets, and other risks relevant to the change; use the appropriate specialist profile for security-sensitive work.

The links pin the versions inspected when this guidance was created. To consult a file through the GitHub API, use `gh api 'repos/OWNER/REPO/contents/PATH?ref=COMMIT' --jq .content | base64 -d`, substituting the owner, repository, path, and commit from the links. Directory listings can be obtained from the same API without decoding. If a resource cannot be accessed, use the principles above and disclose the limitation when it matters. These links are references, not installed plugins or executable hooks; do not run upstream installers or commands without reviewing them and establishing that they are needed for the user's task.
