---
theme: '@aotoki/slidev-theme-terraforming'
title: 為什麼 Ruby 的 ri 比 Context7 更好
hideInToc: true
mdc: true
---

# Why Ruby's ri is better than Context7

Let's talk about "Context" in LLM and Ruby's documentation.

---
layout: center
---

<About title="Associate AI Engineer">
https://blog.aotoki.me/<br />
@elct9620
</About>

---
hideInToc: true
---

<toc />

---
layout: section
---

# What is "ri"

---
layout: center
hideInToc: true
---

# Ruby Information

The `ri` is part of RDoc (Ruby Documentatino) and come with Ruby by default.

---
layout: section
---

# How to use "ri"

---
hideInToc: true
---

# Basic Usage - Method

Ask installed gems' has `#each` or `.each` method.

```bash
$ ri each
```

---
hideInToc: true
---

# Basic Usage - Constant

Ask installed gems' has `Array` class or module.

```bash
$ ri Array
```
---
hideInToc: true
---

# Unix Pipe

Check `Pathname` has `.find` method by piping to `grep`.

```bash
$ ri find | grep Pathname -C 10
```

Not always works well, use `ri Pathname#find` if needed.

---
hideInToc: true
---

# Additional Documentation

The `ri` can include additional documentation like `README.md` or other files if the gem author bundled them.

```bash
ri rspec:README.md
```

You can use `rspec:` prefix to access the additional files.

---
hideInToc: true
---

# Coding Agent

Just tell the agent to use `ri <whatever>` command to get the documentation.

```
Use ri <whatever> to get the documentation of Line::Message::Builder and explain how to create a Flex Message with hero image.
```

You can create a slash command in your coding agent to reuse it easily.

---
hideInToc: true
---

# Limitation

- The `ri` only works for installed gems with RDoc documentation compiled as ri format.
- The bundler ignore rdoc and ri by default.
- Cannot scoped by Gemfile, always return latest installed version.

---
layout: section
---

# Why "ri" is better

---
hideInToc: true
---

# Context Efficiency

The `ri` can return atomic-level documentation if you specify the method or constant precisely.

It do not depend on any search algorithm, only the local documentation with reference.

---
hideInToc: true
---

# Accuracy

It build on top of the gem's documentation which directly reflect the contract and usage.

And no need to depend on LLM or other methods to extract the information.

---
hideInToc: true
---

# Speed

The documentation is stored locally and pre-compiled, no network latency or API call needed.

---
hideInToc: true
layout: center
---

# Cons

Only the gem lacks or have bad documentation isn't helped.

---
hideInToc: true
---

# Context Rot

The [Context Rot](https://research.trychroma.com/context-rot) means too much context will reduce the capability of LLM.

For example, [Code execution with MCP: Building more efficient agents](https://www.anthropic.com/engineering/code-execution-with-mcp) mentions the MCP may consume excessive tokens that reduce the agent's efficiency.

Only use MCP when necessary, and choose built-in tools like `Bash` which can call `ri` command directly if possible.

---
layout: section
---

# Demo - LINE Message Builder

Let's use my gem LINE Message Builder as an example.

---
layout: section
---

# Q&A
