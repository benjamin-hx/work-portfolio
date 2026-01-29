# Work Portfolio

A self-updating portfolio that aggregates your work data from JIRA and GitHub to track accomplishments and visualize impact over time.

## Features

- Pulls JIRA issues (assigned, reported, commented)
- Pulls GitHub activity (commits, PRs, reviews)
- Auto-categorizes work by theme
- Tracks changes with diff reports ("Completed 3 issues since last week")
- Static site on GitHub Pages
- Auto-refreshes weekdays at 8am

## Quick Start

### 1. Fork this repo

### 2. Configure your profile

Edit `config.json`:

```json
{
  "profile": {
    "name": "Your Name",
    "title": "Your Title",
    "company": "Your Company",
    "email": "your@email.com",
    "github": "your-github-username",
    "linkedin": "your-linkedin-username",
    "start_date": "2024-01-01"
  },
  "themes": {
    "your-theme": {
      "label": "Your Theme Label",
      "patterns": ["keyword1", "keyword2"]
    }
  }
}
```

### 3. Add repository secrets

Go to Settings → Secrets and variables → Actions, add:

| Secret | Description |
|--------|-------------|
| `JIRA_EMAIL` | Your JIRA email |
| `JIRA_TOKEN` | JIRA API token ([create here](https://id.atlassian.com/manage-profile/security/api-tokens)) |
| `JIRA_DOMAIN` | Your JIRA domain (e.g., `company.atlassian.net`) |
| `GH_PAT` | GitHub personal access token |
| `GH_ORG` | Your GitHub org name |
| `GH_USER` | Your GitHub username |

### 4. Enable GitHub Pages

Settings → Pages → Source: GitHub Actions

### 5. Trigger a refresh

Actions → Refresh Data and Deploy → Run workflow

## Local Development

```bash
# Set environment variables
export JIRA_EMAIL=you@company.com
export JIRA_DOMAIN=company.atlassian.net
export GITHUB_ORG=your-org
export GITHUB_USER=your-username

# Create token files
echo "your-jira-token" > ~/.jira-token
echo "your-github-token" > ~/.github-token
chmod 600 ~/.jira-token ~/.github-token

# Run refresh
./scripts/refresh.sh

# View locally
python3 -m http.server 8000
# Open http://localhost:8000/site/
```

## Customization

### Work Themes

Edit `config.json` to categorize your work:

```json
"themes": {
  "frontend": {
    "label": "Frontend Development",
    "patterns": ["react", "vue", "css", "ui"]
  },
  "backend": {
    "label": "Backend / API",
    "patterns": ["api", "server", "database"]
  }
}
```

## License

MIT
