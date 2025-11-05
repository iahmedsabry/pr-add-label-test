## add-pr-label.sh

Minimal script that adds a single label to the current pull request.

### Requirements

- bash, curl, jq

### Inputs (environment variables)

- `GITHUB_TOKEN` (required): GitHub token with `pull-requests: write` permission
- `GITHUB_EVENT_PATH` (required): Path to the GitHub event payload (provided by Actions)
- `LABEL` (required): The label name to add (e.g., `size/M`)
- `GITHUB_API_URL` (optional): Override API base URL (defaults to `https://api.github.com`)

### Usage in GitHub Actions

```yaml
name: add-label
on: pull_request_target
jobs:
  add-label:
    permissions:
      contents: read
      pull-requests: write
    runs-on: ubuntu-latest
    steps:
      - name: Checkout (only needed to fetch this script if stored in repo)
        uses: actions/checkout@v4

      - name: Add label to PR
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          LABEL: size/M
        run: |
          bash size-label-action-main/add-pr-label.sh
```

If you host the script elsewhere, download it first:

```yaml
      - name: Add label to PR
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          LABEL: size/M
        run: |
          curl -sSfL -o add-pr-label.sh https://example.com/add-pr-label.sh
          chmod +x add-pr-label.sh
          ./add-pr-label.sh
```

## size-label-by-size.sh

Adds a size label based on the number of changed lines in the pull request.

### Inputs (environment variables)

- `GITHUB_TOKEN` (required)
- `GITHUB_EVENT_PATH` (required)
- `INPUT_SIZES` (optional) JSON mapping of thresholds to sizes; defaults to:

```json
{
  "0": "XS",
  "10": "S",
  "30": "M",
  "100": "L",
  "500": "XL",
  "1000": "XXL"
}
```

- `IGNORED` (optional) newline-separated globs; lines starting with `!` force-include

### Usage in GitHub Actions

```yaml
name: size-label
on: pull_request_target
jobs:
  size-label:
    permissions:
      contents: read
      pull-requests: write
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Label PR by size
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          INPUT_SIZES: >
            {"0":"XS","20":"S","50":"M","200":"L","800":"XL","2000":"XXL"}
          # Optional: IGNORED: ".*\n!.gitignore\nyarn.lock\ngenerated/*"
        run: |
          bash size-label-action-main/size-label-by-size.sh
```

### Local testing (outside Actions)

You can simulate by saving an event payload to a file and setting envs:

```bash
export GITHUB_TOKEN=ghp_yourtoken
export GITHUB_EVENT_PATH=./event.json
export LABEL="size/M"
bash size-label-action-main/add-pr-label.sh
```

`event.json` must look like a pull_request event payload and include:

```json
{
  "pull_request": {
    "number": 123,
    "base": {
      "repo": {
        "name": "your-repo",
        "owner": { "login": "your-owner" }
      }
    }
  }
}
```


