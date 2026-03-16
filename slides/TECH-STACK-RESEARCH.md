# Presentation Tech Stack Research: Quarto + Reveal.js + Mermaid

Research date: 2026-03-15. Focused on Quarto 1.8.x capabilities.

Current config: `_quarto.yml` uses `theme: [default, custom.scss]`, `transition: slide`, `mermaid-format: svg`, `mermaid.theme: neutral`.

---

## 1. Quarto Reveal.js Features Beyond Basic Slides

### Auto-Animate (High Value for This Talk)

Smoothly animate matching elements between adjacent slides. This replaces the current pattern of manually duplicating slides with `data-transition="none"` to simulate progressive builds.

Add `auto-animate=true` to two adjacent slide headings and Reveal.js will smoothly animate matching elements between them. Elements are matched by text content, `src` attributes (images/video), or explicit `data-id` attributes.

Basic example — animating a div's position and style:

    ## {auto-animate=true}

    ::: {style="margin-top: 100px;"}
    Animating content
    :::

    ## {auto-animate=true}

    ::: {style="margin-top: 200px; font-size: 3em; color: red;"}
    Animating content
    :::

Code animation — animate code changes between slides (lines appearing, moving, highlighting). Use matching `data-id` attributes on code blocks across two `auto-animate=true` slides. Reveal.js will animate the diff between the two code blocks.

Configuration (add to `_quarto.yml`):

```yaml
format:
  revealjs:
    auto-animate-easing: ease-in-out
    auto-animate-duration: 0.8
    auto-animate-unmatched: false
```

**Relevance to our talk**: The architecture build-up slides (lines 79-173 in index.qmd) currently duplicate the full Mermaid diagram 5 times. Auto-animate could make the transitions smooth rather than abrupt. However, auto-animate with Mermaid diagrams may not work reliably since Mermaid renders as SVG — test before committing to this approach.

### Tabsets

Tabbed content within a single slide. Use `::: {.panel-tabset}` with `###` sub-headings for each tab:

    ## Collector Pipeline

    ::: {.panel-tabset}

    ### Traces In
    OTLP receiver accepts spans from both variants.

    ### Transform
    Promote span event attributes to parent span.

    ### Metrics Out
    Spanmetrics connector produces `gen_ai_calls_total`.

    :::

**Relevance**: Could be used for the collector pipeline slide (line 362) or the "What We Built Together" recap, letting the audience click through components.

### Code Highlighting with Line-by-Line Reveal

Progressive highlighting using pipes (`|`) as step separator in the `code-line-numbers` attribute. Format: `code-line-numbers="|1-3|5-8|10-12"` — the first `|` shows all lines unhighlighted, then highlights 1-3, then 5-8, then 10-12 as you advance. Non-highlighted lines dim.

Example — walk through an OTel Collector config section by section:

    ```{.yaml code-line-numbers="|1-3|5-8|10-12"}
    receivers:
      otlp:
        protocols: { grpc: {}, http: {} }

    processors:
      transform:
        trace_statements:
          - context: spanevent

    connectors:
      spanmetrics:
        namespace: gen_ai
    ```

**Relevance**: Ideal for walking through the OTel Collector config, Flagger Canary resource YAML, or Knative Service manifests. Much better than static code blocks.

### Callout Blocks

Five types: `note`, `tip`, `warning`, `caution`, `important`. Use `::: {.callout-tip}` syntax:

    ::: {.callout-tip}
    ## Why span events, not metrics?
    Span events carry trace context — you get correlation for free.
    :::

Note: `collapse` is not supported in Reveal.js.

### Columns (Side-by-Side Layout)

Use nested `::::` and `:::` divs with `.columns` and `.column` classes:

    :::: {.columns}
    ::: {.column width="50%"}
    **Variant A**
    - Dry tone
    - Sonnet 4
    - 45% thumbs up
    :::
    ::: {.column width="50%"}
    **Variant B**
    - Funny tone
    - Sonnet 4
    - 72% thumbs up
    :::
    ::::

**Relevance**: The "Reveal" slides (lines 219-231, 427-436) with variant comparison tables could be more visual as side-by-side columns.

### r-stack (Overlapping Elements)

Stack elements on top of each other, revealing one at a time. Use `::: {.r-stack}` with `.fragment` on each child:

    ::: {.r-stack}
    ![](diagram-step1.png){.fragment width="600"}
    ![](diagram-step2.png){.fragment width="600"}
    ![](diagram-step3.png){.fragment width="600"}
    :::

Elements appear in the same position, replacing each other. Combined with `.fragment` classes like `.fade-in-then-out`, this creates clean progressive builds.

### r-fit-text (Auto-Sizing)

Text that automatically scales to fill the slide:

    ::: {.r-fit-text}
    Does expensive mean better?
    :::

**Relevance**: Dramatic statement slides (lines 305-311, 438-448) would benefit from this instead of manually setting `font-size`.

### Absolute Positioning

Place elements anywhere on the slide using `.absolute` with position attributes:

    ![](image.png){.absolute top=200 left=0 width="350" height="300"}

Already used in the existing slides for decorative images. Can also be used for overlapping diagrams and annotations.

### Slide Backgrounds

Five types of backgrounds are supported on any slide heading:

**Color/gradient**: `## {background-color="#00897B"}` or `## {background-color="linear-gradient(to right, #00897B, #4DB6AC)"}`

**Image**: `## Slide Title {background-image="images/architecture.png" background-size="contain" background-opacity="0.3"}`

**Video** (looping, muted): `## {background-video="video.mp4" background-video-loop="true" background-video-muted="true"}`

**iframe** (embed a live webpage as the slide background): `## {background-iframe="https://app.datadoghq.com/dashboard/68y-xeg-j6s" background-interactive="true"}`

**Relevance**: The Datadog dashboard slides (lines 209, 417) could use `background-iframe` with `background-interactive="true"` to embed the live dashboard as a full-slide background instead of just linking to it.

### Content Overflow

Two classes for slides with too much content:

- `## Long Slide {.smaller}` — reduces font size
- `## Long Slide {.scrollable}` — adds scroll bar

### Fragments (Animation Effects)

Beyond simple `.fragment` (fade-in), these classes are available:

| Class | Effect |
|---|---|
| `.fade-out` | Fade out |
| `.fade-up` / `.fade-down` / `.fade-left` / `.fade-right` | Directional fade in |
| `.fade-in-then-out` | Fade in, then out on next step |
| `.grow` | Scale up |
| `.shrink` | Scale down |
| `.strike` | Strikethrough |
| `.highlight-red` / `.highlight-green` / `.highlight-blue` | Color highlight |
| `.semi-fade-out` | Partial transparency |
| `.custom .blur` | Custom blur-to-focus (requires CSS) |

**Nested fragments** for sequential effects on the same element — wrap three levels of `::: {.fragment .CLASS}` to get: fade in, then turn red, then semi-fade.

**Custom blur effect** (add to `custom.scss`):

```scss
.reveal .slides section .fragment.blur {
  filter: blur(5px);
}
.reveal .slides section .fragment.blur.visible {
  filter: none;
}
```

### Stretch to Fill

Make an image or element fill remaining slide space with `.r-stretch`:

    ![](diagram.png){.r-stretch}

---

## 2. Reveal.js Native Features Accessible Through Quarto

### Speaker View

Press `S` during presentation. Shows: current slide, next slide, elapsed time, speaker notes.

Already in use (`::: {.notes}` blocks throughout index.qmd).

### PDF Export

Press `E` during presentation, then `Ctrl+P` to print. Set landscape, no margins, enable background graphics, save as PDF.

Can also export from CLI: `quarto render slides/index.qmd --to pdf` (requires Chrome/Chromium).

### Scroll View

Press `R` to toggle scroll view (vertical scrolling instead of slide-by-slide). Or append `?view=scroll` to the URL. Or set in YAML:

```yaml
format:
  revealjs:
    scroll-view: true
```

### Multiplex (Audience Follow-Along)

Audience members follow your slides on their own devices:

```yaml
format:
  revealjs:
    multiplex: true
```

Generates two HTML files: `presentation.html` (publish for audience) and `presentation-speaker.html` (presenter controls). When the presenter advances, all audience browsers advance too.

**Relevance**: Not needed for this talk (the audience is using the app, not following slides), but worth knowing.

### Navigation Menu

Press `M` for slide menu. Configure:

```yaml
format:
  revealjs:
    menu:
      side: right
      width: wide
      numbers: true
```

### Overview Mode

Press `O` for thumbnail grid of all slides. Good for jumping to a specific section during Q&A.

### Jump to Slide

Press `G`, type slide number or ID, press Enter.

### Chalkboard (Drawing on Slides)

```yaml
format:
  revealjs:
    chalkboard: true
```

- `C` — draw on current slide
- `B` — open blank chalkboard
- `X`/`Y` — cycle colors
- `BACKSPACE` — reset all drawings
- `D` — download drawings

**Relevance**: Could be useful during the teaching scenes to annotate the architecture diagram live. Not compatible with `embed-resources: true`.

### Auto-Slide

```yaml
format:
  revealjs:
    auto-slide: 5000
    loop: true
```

### Parallax Background

Scrolling background image that shifts as you navigate:

```yaml
format:
  revealjs:
    parallax-background-image: background.png
    parallax-background-size: "2100px 900px"
```

### Keyboard Shortcuts Summary

| Key | Action |
|---|---|
| `S` | Speaker view |
| `O` | Overview (thumbnail grid) |
| `E` | Print/PDF mode |
| `R` | Scroll view toggle |
| `M` | Navigation menu |
| `G` | Jump to slide |
| `F` | Fullscreen |
| `C` | Chalkboard: draw on slide |
| `B` | Chalkboard: blank canvas |
| `Alt+click` | Zoom into element |

---

## 3. Mermaid Diagram Types Beyond Flowcharts

**Quarto 1.8 bundles Mermaid 11.6.0**, which supports all modern diagram types.

### Sequence Diagram (High Value)

Shows interactions between components over time. Ideal for the vote-to-metric pipeline. Place inside a `{mermaid}` code cell:

```text
sequenceDiagram
    participant User as Audience Member
    participant App as Story App
    participant OTel as OTel SDK
    participant Col as Collector
    participant Prom as Prometheus
    participant Flag as Flagger

    User->>App: thumbs up (part 3)
    activate App
    App->>OTel: create span "evaluate UserSatisfaction"
    OTel->>OTel: add span event gen_ai.evaluation.result
    OTel->>Col: export via OTLP
    deactivate App
    Col->>Col: transform: promote attributes
    Col->>Col: spanmetrics: span to counter
    Col->>Prom: gen_ai_calls_total{score_label="thumbs_up"}
    Prom-->>Flag: PromQL query every 30s
    Flag-->>App: shift traffic weight
```

**Relevant features**: `activate`/`deactivate` for processing windows, `Note over` for annotations, `loop`/`alt`/`par` for control flow, `rect rgb()` for background highlighting, `create`/`destroy` for lifecycle.

**Relevance to our talk**: The "How a Vote Becomes Data" teaching section (lines 252-360) currently uses flowcharts. A sequence diagram would show the temporal flow more naturally: user action, app processing, SDK instrumentation, collector transformation, metric export, Flagger decision.

### State Diagram (High Value for Flagger)

Shows state machine transitions. Ideal for the Flagger canary lifecycle:

```text
stateDiagram-v2
    [*] --> Initializing
    Initializing --> Progressing: canary detected
    Progressing --> Progressing: check passed (advance weight)
    Progressing --> Promoting: all checks passed
    Progressing --> Reverting: check failed
    Promoting --> Finalising: traffic at 100%
    Finalising --> Succeeded: cleanup done
    Reverting --> Failed: rollback complete
    Succeeded --> [*]
    Failed --> [*]

    note right of Progressing
      10% to 20% to 30% to ... to 100%
      Each step requires 3 consecutive
      passing metric checks
    end note
```

**Relevance**: The Flagger canary logic slide (line 376) needs a diagram. A state diagram captures the lifecycle (Initializing, Progressing, Promoting, Finalising, Succeeded, or Reverting, Failed) more accurately than a flowchart.

### Timeline Diagram

Chronological events. Place inside a `{mermaid}` code cell:

```text
timeline
    title Canary Rollout Timeline
    section Round 1
      0:00 : Deploy variant B (10% traffic)
      1:00 : First metric check passes
      2:00 : Advance to 20%
      3:00 : Advance to 30%
    section Round 2
      4:00 : Check fails, rollback
      5:00 : 100% back to variant A
```

Note: Timeline is marked "experimental" in Mermaid docs. Rendering in Quarto's SVG mode may have rough edges — test before relying on it.

### Mindmap

Hierarchical concept map using indentation:

```text
mindmap
  root((Scaling on Satisfaction))
    OpenTelemetry
      Spans
      Span Events
      gen_ai conventions
    OTel Collector
      Transform processor
      Spanmetrics connector
      Dual export
    Flagger
      Canary analysis
      PromQL metrics
      Traffic shifting
    Knative
      Serverless runtime
      Scale to zero
```

Node shapes: `[square]`, `(rounded)`, `((circle))`, `)cloud(`, `{{hexagon}}`.

**Relevance**: Could work as a recap/summary slide showing the full technology stack at a glance. Probably too dense for a conference slide, but worth considering.

### GitGraph

Visualize branching and deployment strategy:

```text
gitgraph
    commit id: "main: variant A"
    branch canary
    commit id: "deploy variant B"
    commit id: "10% traffic"
    commit id: "20% traffic"
    commit id: "30% traffic"
    checkout main
    merge canary id: "promote B"
```

**Relevance**: Limited for this talk. The Flagger canary process is not really a git branching model.

### Architecture Diagram (New in Mermaid 11.x)

System architecture layouts:

```text
architecture-beta
    group cluster[GKE Cluster]
    service app_a(server)[Variant A] in cluster
    service app_b(server)[Variant B] in cluster
    service collector(server)[OTel Collector] in cluster
    service prometheus(database)[Prometheus] in cluster
    service flagger(server)[Flagger] in cluster

    app_a:R --> L:collector
    app_b:R --> L:collector
    collector:R --> L:prometheus
    prometheus:R --> L:flagger
```

**Caution**: Architecture diagrams are very new in Mermaid. They may not render well in Quarto's SVG mode. Test thoroughly.

### Quadrant Chart

Two-axis comparison:

```text
quadrantChart
    title Model Selection: Cost vs Satisfaction
    x-axis Low Cost --> High Cost
    y-axis Low Satisfaction --> High Satisfaction
    quadrant-1 Worth it
    quadrant-2 Ideal
    quadrant-3 Avoid
    quadrant-4 Reconsider
    Haiku 4.5: [0.2, 0.6]
    Opus 4.6: [0.8, 0.7]
    Sonnet 4: [0.5, 0.5]
```

**Relevance**: Could be a fun "results" slide after Round 2 — plotting where the models land on cost vs. satisfaction.

### Diagram Types to Avoid in Slides

- **Gantt**: Too dense, too small for projection.
- **ER Diagram**: Not relevant.
- **C4**: Good for architecture docs but too detailed for conference slides. The notation is verbose and the diagrams tend to be large.
- **Sankey**: Interesting for flow visualization but untested in Quarto.
- **Kanban/Packet/Radar**: Not relevant.

### Rendering Compatibility Notes

- **HTML/Reveal.js**: All diagram types render via JavaScript (native Mermaid). Best compatibility.
- **SVG mode** (`mermaid-format: svg`): Our current setting. Renders server-side. May have issues with newer diagram types (timeline, mindmap, architecture). If a diagram looks wrong, try switching to `mermaid-format: js` for that specific document.
- **PDF**: Rendered as PNG via Chrome. Newer diagram types may have font/sizing issues.

---

## 4. Custom HTML/CSS/JS in Quarto Reveal.js

### Raw HTML

Works directly in slides. Already used in index.qmd for styled headings and image positioning.

```html
<div style="display: flex; justify-content: space-around; align-items: center;">
  <div style="text-align: center;">
    <h3 style="color: #00897B;">Variant A</h3>
    <p style="font-size: 3em;">45%</p>
    <p>thumbs up</p>
  </div>
  <div style="text-align: center;">
    <h3 style="color: #00897B;">Variant B</h3>
    <p style="font-size: 3em;">72%</p>
    <p>thumbs up</p>
  </div>
</div>
```

### Custom CSS Animations (in custom.scss)

```scss
/*-- scss:rules --*/

/* Pulse animation for live indicators */
@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.4; }
}
.reveal .live-indicator {
  color: #e53935;
  animation: pulse 1.5s ease-in-out infinite;
}

/* Slide-in from left */
@keyframes slideInLeft {
  from { transform: translateX(-100%); opacity: 0; }
  to { transform: translateX(0); opacity: 1; }
}
.reveal .slide-in-left {
  animation: slideInLeft 0.6s ease-out;
}
```

Usage in slides: `<span class="live-indicator">LIVE</span> Votes streaming in real time`

### Observable JS (Interactive Visualizations)

OJS cells work in Reveal.js slides. Reactive — inputs update outputs automatically. Use `{ojs}` code cells in your `.qmd` file:

```javascript
// Load D3
d3 = require("d3@7")

// Create an input
viewof threshold = Inputs.range([0, 20], {
  value: 5, step: 1, label: "Satisfaction threshold (pp):"
})

// Reactive visualization updates when threshold changes
html`<p style="font-size: 1.5em;">
  If Variant B is <strong>${threshold}pp</strong> ahead,
  Flagger advances the canary.
</p>`
```

### D3.js Visualizations

Load D3 via Observable `require()` and create any SVG visualization. Example skeleton for a vote comparison bar chart:

```javascript
d3 = require("d3@7")

// Create a simple bar chart of vote counts
{
  const data = [
    {variant: "A", thumbsUp: 45, thumbsDown: 55},
    {variant: "B", thumbsUp: 72, thumbsDown: 28}
  ];

  const svg = d3.create("svg")
    .attr("width", 600)
    .attr("height", 300);

  // ... D3 bar chart bindings here ...

  return svg.node();
}
```

**Relevance**: D3 could create animated, interactive visualizations of the canary progression — bar charts updating as votes come in, or a traffic weight slider. However, for a conference talk, simplicity beats interactivity. Mermaid diagrams and static visuals are easier to maintain and more reliable on stage.

### Embedding Iframes

Inline iframe with stretch:

```html
<iframe class="r-stretch" data-src="https://app.datadoghq.com/apm/traces"
        style="border: none;"></iframe>
```

Or as a slide background (add attributes to the slide heading):

    ## {background-iframe="https://app.datadoghq.com/dashboard/68y-xeg-j6s" background-interactive="true"}

### JavaScript in Slides

Inline JS works directly in `.qmd` files:

```html
<script>
document.addEventListener('DOMContentLoaded', () => {
  // Custom behavior
});
</script>
```

Or load external scripts via Reveal.js plugin system.

---

## 5. Flame Graph / Trace Visualization in Quarto

### d3-flame-graph Library

The best option for flame graphs in Quarto. It is a D3.js plugin that produces interactive flame graphs from hierarchical data. Load via Observable JS `require()` in an `{ojs}` cell:

```javascript
d3 = require("d3@7")
flamegraph = require("d3-flame-graph@4")

// Flame graph data (simplified trace representation)
data = ({
  name: "HTTP POST /vote",
  value: 120,
  children: [
    {
      name: "evaluate UserSatisfaction",
      value: 80,
      children: [
        { name: "gen_ai.evaluation.result (span event)", value: 5 },
        { name: "recordVote", value: 15 }
      ]
    },
    { name: "OTel SDK export", value: 30 }
  ]
})

// Render
{
  const chart = flamegraph.flamegraph()
    .width(800)
    .cellHeight(24)
    .minFrameSize(5);

  const div = document.createElement("div");
  d3.select(div).datum(data).call(chart);
  return div;
}
```

**Relevance**: A flame graph could visualize the trace structure of a vote — showing that the HTTP handler spans the full request, with nested spans for evaluation, story generation, and OTel export. This is more intuitive than a sequence diagram for showing span nesting/duration. However, it requires structuring the data correctly and testing the OJS integration.

### Alternative: CSS-Only Trace Visualization

For a simpler approach that does not require JavaScript libraries:

```html
<div style="font-family: monospace; font-size: 0.7em;">
  <div style="background: #4DB6AC; padding: 4px 8px; margin: 2px 0; width: 100%; color: white;">
    HTTP POST /api/vote (120ms)
  </div>
  <div style="background: #00897B; padding: 4px 8px; margin: 2px 0; width: 75%; margin-left: 5%; color: white;">
    evaluate UserSatisfaction (80ms)
  </div>
  <div style="background: #00695C; padding: 4px 8px; margin: 2px 0; width: 15%; margin-left: 10%; color: white;">
    recordVote (15ms)
  </div>
  <div style="background: #80CBC4; padding: 4px 8px; margin: 2px 0; width: 30%; margin-left: 5%; color: #1a1a1a;">
    OTel SDK export (30ms)
  </div>
</div>
```

This is static but dead simple, renders everywhere, and can be styled with fragments for progressive reveal.

**Recommendation**: Use the CSS approach for reliability on stage. Consider d3-flame-graph for the online/shared version of the slides.

### Brendan Gregg's FlameGraph

The original tool generates standalone interactive SVGs from stack trace data. Could pre-generate an SVG and embed it as an image, but it is designed for profiling data, not OTel traces. Not recommended for this use case.

---

## 6. Quarto Extensions Worth Installing

Install with `quarto add <repo>`:

| Extension | Install Command | Purpose |
|---|---|---|
| **Spotlight** | `quarto add mcanouil/quarto-spotlight` | Highlight mouse position — useful for pointing at diagram elements |
| **Codefocus** | `quarto add reuning/codefocus` | Highlight + explain specific code lines with fragments below |
| **Animate** | `quarto add mcanouil/quarto-animate` | CSS animations (animate.css library) on any element |
| **Iconify** | `quarto add mcanouil/quarto-iconify` | 200,000+ icons (FontAwesome, Material, etc.) |

---

## 7. Concrete Recommendations for This Talk

### Immediate Wins (Low effort, high impact)

1. **Code line highlighting** for the collector pipeline and Flagger config slides (TODOs at lines 362 and 376). Walk through YAML configs line-by-line instead of showing them all at once.

2. **r-fit-text** for dramatic statement slides ("What's a span event?", "Does expensive mean better?") instead of manually sizing with inline CSS.

3. **Columns layout** for the variant comparison "Reveal" slides — more visual than tables.

4. **Custom fragment: blur** — blur upcoming content, unblur as you reveal. Adds polish to the progressive build slides.

5. **Chalkboard** enabled for teaching scenes — annotate the architecture diagram live.

### Medium Effort

6. **Sequence diagram** for the vote-to-metric pipeline (Scene 3/4). Shows temporal flow better than the current flowchart chain.

7. **State diagram** for the Flagger canary lifecycle (Scene 5). Captures the state machine nature of canary deployments.

8. **background-iframe** for the Datadog dashboard slides — embed the live dashboard as a full-slide background.

9. **Quadrant chart** for the Round 2 results — cost vs. satisfaction plot.

### Exploratory (Test before committing)

10. **Auto-animate** between architecture build-up slides. Test whether it works smoothly with Mermaid SVG output.

11. **d3-flame-graph** via Observable JS for trace structure visualization. Impressive but fragile — test thoroughly.

12. **Timeline diagram** for canary rollout progression. Experimental in Mermaid — verify rendering.

---

## 8. Mermaid Styling Lessons from Viktor Farcic

Viktor uses simple, flat Mermaid flowcharts with custom styling for his AI architecture content. Key patterns:

- **Dark theme nodes**: `fill:#1a1a2e` (dark navy) on all nodes
- **Colored strokes by type**: purple for agents, green for users, orange for LLMs, cyan for tools, yellow for data stores, blue for policies
- **Flat structure**: No subgraphs, no nesting. Containment is communicated through colors and labels, not visual nesting.
- **Numbered labels in nodes**: "(1) Agent", "(2) User Input" — helps narrate the diagram step by step
- **Edge labels tell the story**: "Tool request", "Execute", "Agentic Loop"
- **Only `graph LR` and `graph TD`**: No exotic diagram types. Uses what Mermaid does reliably.

**Lesson for our slides**: Stop fighting Mermaid's nesting/direction limitations. Use flat flowcharts with good styling. Communicate hierarchy through color and labels, not visual containment. Viktor's diagrams work because they're simple.

**Mermaid block-beta findings**: Block labels on nested blocks are broken (render behind children). Workaround: use a styled title row as the first child with `classDef`. `columns 1` inside a block gives vertical stacking. Trailing spaces don't widen boxes (Mermaid trims them). Box width is determined by the widest child content, not the title.

---

## 9. Datadog as a Slide Visual

Instead of building complex diagrams to show OTel trace structure, use live Datadog views:

- **`background-iframe` with `background-interactive="true"`**: Embeds a live Datadog page as the slide background. Presenter can click around in it.
- **APM trace view**: Shows span hierarchy, span events, attributes — exactly what we're trying to diagram.
- **Query URL**: `https://app.datadoghq.com/apm/traces?query=operation_name:evaluate%20UserSatisfaction` filters to evaluation spans.
- **Requires**: Network access, Datadog authentication in browser, cluster running with traffic.
- **Fallback**: Screenshot of a real trace, embedded as an image. Capture when cluster is up.

---

## Sources

- [Quarto Reveal.js Overview](https://quarto.org/docs/presentations/revealjs/)
- [Quarto Advanced Reveal](https://quarto.org/docs/presentations/revealjs/advanced.html)
- [Quarto Presenting Slides](https://quarto.org/docs/presentations/revealjs/presenting.html)
- [Quarto Reveal.js Options Reference](https://quarto.org/docs/reference/formats/presentations/revealjs.html)
- [Quarto Reveal.js Themes (Custom CSS)](https://quarto.org/docs/presentations/revealjs/themes.html)
- [Quarto Code Annotation](https://quarto.org/docs/authoring/code-annotation.html)
- [Quarto Callout Blocks](https://quarto.org/docs/authoring/callouts.html)
- [Quarto Diagrams (Mermaid)](https://quarto.org/docs/authoring/diagrams.html)
- [Quarto Observable JS](https://quarto.org/docs/interactive/ojs/)
- [Quarto OJS Libraries (D3, etc.)](https://quarto.org/docs/interactive/ojs/libraries.html)
- [Quarto Reveal.js Plugins](https://quarto.org/docs/extensions/revealjs.html)
- [Quarto Extensions Listing](https://quarto.org/docs/extensions/listing-revealjs.html)
- [Quarto 1.8 Release Notes](https://quarto.org/docs/blog/posts/2025-10-13-1.8-release/)
- [Reveal.js Auto-Animate](https://revealjs.com/auto-animate/)
- [Reveal.js Speaker View](https://revealjs.com/speaker-view/)
- [Reveal.js Multiplex](https://revealjs.com/multiplex/)
- [Reveal.js Plugins](https://revealjs.com/plugins/)
- [Mermaid.js Documentation](https://mermaid.js.org/)
- [Mermaid Sequence Diagrams](https://mermaid.js.org/syntax/sequenceDiagram.html)
- [Mermaid State Diagrams](https://mermaid.js.org/syntax/stateDiagram.html)
- [Mermaid Timeline](https://mermaid.js.org/syntax/timeline.html)
- [Mermaid Mindmaps](https://mermaid.js.org/syntax/mindmap.html)
- [Mermaid GitGraph](https://mermaid.js.org/syntax/gitgraph.html)
- [d3-flame-graph (GitHub)](https://github.com/spiermar/d3-flame-graph)
- [d3-flame-graph (npm)](https://www.npmjs.com/package/d3-flame-graph)
- [Quarto Spotlight Extension](https://github.com/mcanouil/quarto-spotlight)
- [Quarto Codefocus Extension](https://github.com/reuning/codefocus)
