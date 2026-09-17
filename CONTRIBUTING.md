# Contributing

## How to Contribute

1. Fork the repo
2. Create a feature branch: `git checkout -b fix/my-bug`
3. Make your changes
4. Run validation: `bash -n scripts/*.sh && python3 -m py_compile scripts/selfcheck.py`
5. Commit with a clear message: `fix: description` or `feat: description`
6. Push and open a PR

## Code Style

- Shell scripts: `set -euo pipefail`, functions for repeated patterns
- Python: keep it simple, no external deps except stdlib
- Templates: use `YOUR_` prefix for all user-configurable values
- Docs: write for someone who has never seen this project

## Testing

Before submitting:
```bash
bash -n scripts/*.sh
python3 -m py_compile scripts/selfcheck.py
python3 -c "import json; json.load(open('templates/openclaw.json'))"
```

## License

By contributing, you agree your code will be licensed under MIT.
