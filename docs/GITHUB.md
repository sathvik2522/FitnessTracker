# GitHub checkout and publishing

Remote: https://github.com/sathvik2522/FitnessTracker

The remote was public and empty when inspected on October 16, 2026. The existing project directory is now a local Git repository on branch `main`, with this remote configured. The first publishing check failed because Git had no HTTPS credentials available; do not assume source is online until a push succeeds and the remote commit is verified.

## Authenticate without sharing secrets

One route is GitHub Desktop: sign in through its browser flow, then **File > Add Local Repository** and choose the folder containing `PersonalFitness.xcodeproj` and `.git`. Use **Publish branch** or **Push origin**, depending on what Desktop displays for this existing remote. Confirm the target is `sathvik2522/FitnessTracker`, not a new repository. [Add a local repository](https://docs.github.com/en/desktop/adding-and-cloning-repositories/adding-a-repository-from-your-local-computer-to-github-desktop), [sign in](https://docs.github.com/en/desktop/installing-and-authenticating-to-github-desktop/authenticating-to-github-in-github-desktop).

Alternatively, if GitHub CLI is installed, run `gh auth login --hostname github.com --git-protocol https --web`, complete browser sign-in yourself, then `gh auth setup-git`. The CLI was not installed in the inspected environment. Do not paste passwords/tokens into chat or put them in a remote URL.

## Push the prepared project

From the project directory after authentication:

```sh
git status
git remote -v
git push -u origin main
git ls-remote origin refs/heads/main
```

A non-fast-forward error means the remote gained commits; fetch and review them rather than force-pushing. No remote history should be erased to publish this project.

## Clone on another Mac after publishing

```sh
git clone https://github.com/sathvik2522/FitnessTracker.git
cd FitnessTracker
open PersonalFitness.xcodeproj
```

Set up your own ignored local signing configuration and follow the iPhone installation guide. GitHub provides source code, not a directly installable iPhone app or Android package. A clone does not contain the original phone's food diary/workouts.

## Before future pushes

Review `git diff` and `git diff --cached`. Keep `Configuration/Local.xcconfig`, databases, credentials, signing profiles, build logs and device diagnostics out of Git. Commit only intended source/doc changes. The repository uses a public GitHub noreply author address locally, rather than the development account's email.
