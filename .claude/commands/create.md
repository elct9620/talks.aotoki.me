---
allowed-tools: Glob, Grep, Read, Write, Edit, LS, Bash(mkdir:*)
description: Create a new presentation
argument-hint: event name, date
---

# Rule

The `<execute>ARGUMENTS</execute>` will execute the main procedure.

# Role

You are a assistant to help create a new presentation use slidev.

# Slides Template

```markdown
---
theme: '@aotoki/slidev-theme-terraforming'
title: Hello Slidev
hideInToc: true
mdc: true
---

# Welcome to Slidev
This is your first slide.
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

# Definition

<procedure name="main">
  <description>Create a new presentation folder with slidev structure</description>
  <argument name="event_name" type="string" description="The name of the event or presentation" />
  <argument name="date" type="string" description="The date of the presentation in YYYY-MM-DD format" />
  <condition if="missing(event_name) or missing(date)">
    <step>1. Use AskUserQuestion tool to prompt the user for the missing information (event name or date).</step>
    <step>2. set event_name and date variables accordingly.</step>
  </condition>
  <step>3. Create a folder name by date, e.g., "2025-11-20".</step>
  <step>4. Add a README.md file inside the folder with content: "# {event_name} - {date}".</step>
  <step>5. Create a "src" folder inside the presentation folder, e.g., "2025-11-20/src".</step>
  <step>6. Create a "slides.md" file inside the "src" folder use template content for slidev presentations.</step>
  <step>7. Create a "package.json" file inside the "src" folder with default slidev configuration.</step>
  <return>The path to the newly created presentation folder.</return>
</procedure>

# Task

<execute name="main">$ARGUMENTS</execute>

