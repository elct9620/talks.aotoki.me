---
allowed-tools: Glob, Grep, Read, Write, Edit, LS, Bash(mkdir:*)
description: Create a new presentation
argument-hint: event_name  date [description]
---

# Rule

The `<execute>ARGUMENTS</execute>` will execute the main procedure.

# Role

You are a assistant to help create a new presentation use slidev.

# README Template

```markdown
# {event_name} - {date}

{description}
```

# Slides Template

```markdown
---
theme: '@aotoki/slidev-theme-terraforming'
title: [suggested title inferred from description]
hideInToc: true
mdc: true
---

# [suggested title inferred from description]
This is your first slide.

---
layout: center
---

<About>
https://blog.aotoki.me/<br />
@elct9620
</About>

```

# Package Template

```json
{
  "type": "module",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "slidev",
    "build": "slidev build --base /[date]-[event_name]/ --out ../../dist/[date]-[event_name]",
    "export": "slidev export --per-slide --output ../[date]-[event_name].pdf"
  }
}
```

> Use snake_case for folder and file names.

# Definition

<procedure name="main">
  <description>Create a new presentation folder with slidev structure</description>
  <argument name="event_name" type="string" description="The name of the event or presentation" />
  <argument name="date" type="string" description="The date of the presentation in YYYY-MM-DD format" />
  <argument name="description" type="string" description="Optional description of the presentation" optional="true" />
  <condition if="missing(event_name) or missing(date)">
    <step>1. Use AskUserQuestion tool to prompt the user for the missing information (event name or date).</step>
    <step>2. set event_name and date variables accordingly.</step>
  </condition>
  <step>4. Identity extra information from description argument if provided.</step>
  <step>4. Create a folder name by date, e.g., "2025-11-20".</step>
  <step>5. Add a README.md file inside the folder with template content including event name, date, and optional description.</step>
  <step>6. Create a "src" folder inside the presentation folder, e.g., "2025-11-20/src".</step>
  <step>7. Create a "slides.md" file inside the "src" folder use template content for slidev presentations.</step>
  <step>8. Create a "package.json" file inside the "src" folder with default slidev configuration.</step>
  <return>The path to the newly created presentation folder.</return>
</procedure>

# Task

<execute name="main">$ARGUMENTS</execute>

