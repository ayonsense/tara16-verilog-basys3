# Contributing

Keep changes focused and retain existing author and license notices.
Run the checks listed in README.md before submitting a change.
Never commit credentials, personal settings, generated build output, or
unlisted release assets. The supplied ROM initialization files are release
inputs and should remain unchanged.

Enable the release guard after cloning:

```sh
git config core.hooksPath .githooks
```

The guard audits staged files for private/build material and common credential
patterns, permits only the supplied ROM initialization files under
`tools/assets/`, and checks them against their SHA-256 manifest. It is a
safeguard against accidental commits, not a guarantee that every secret can be
detected.
