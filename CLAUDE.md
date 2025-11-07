# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository manages presentation slides using **Slidev**, organized in a pnpm workspace structure. Each presentation lives in its own dated folder (e.g., `2025-05-27/`) with source content in a `src/` subdirectory.

## Architecture

### Workspace Structure

- **pnpm workspace**: Root manages dependencies centrally via `pnpm-workspace.yaml`
- **Presentation folders**: Each dated folder (YYYY-MM-DD format) contains:
  - `README.md`: Event description in Traditional Chinese
  - `src/slides.md`: Slidev presentation content
  - `src/package.json`: Per-presentation build configuration
- **Shared theme**: Uses `@aotoki/slidev-theme-terraforming` across all presentations
- **Build output**: Generated to `dist/` at root level

### Custom Commands

A `/create` slash command exists for scaffolding new presentations:
- Creates dated folder structure (YYYY-MM-DD)
- Generates README, slides.md, and package.json from templates
- Configures build paths with proper base URLs

## Commands

### Development

```bash
# Start development server for a specific presentation
cd YYYY-MM-DD/src && pnpm dev

# Build all presentations
pnpm build  # From root

# Build specific presentation
cd YYYY-MM-DD/src && pnpm build

# Export to PDF
cd YYYY-MM-DD/src && pnpm export
```

### Dependency Management

```bash
# Install dependencies (uses pnpm catalog)
pnpm install

# Add dependency to catalog
# Edit pnpm-workspace.yaml catalog section
```

## Key Conventions

1. **Dates**: Folder names use YYYY-MM-DD format (e.g., `2025-08-10`)
2. **Build paths**: Each presentation builds with `--base /YYYY-MM-DD-event/` to `dist/YYYY-MM-DD-event/`
3. **Export naming**: PDFs export as `YYYY-MM-DD-event-zhtw.pdf` (Traditional Chinese suffix)
4. **Content language**: README and slides typically in Traditional Chinese
5. **Package versions**: Use catalog references (e.g., `"@slidev/cli": "catalog:"`) not hardcoded versions

## Creating New Presentations

Use the custom slash command:
```
/create event name, date
```

This automates the folder structure, templates, and configuration setup.
