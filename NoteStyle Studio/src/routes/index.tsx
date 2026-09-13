import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import {
  Search,
  Mic,
  Upload,
  Plus,
  Users,
  Clock,
  FileText,
  Sparkles,
  CheckSquare,
  Mail,
  Copy,
  Highlighter,
  Pen,
  StickyNote,
  Settings,
  ChevronRight,
  Play,
} from "lucide-react";
import { meetings, formatDate, relativeDay, type Meeting } from "@/lib/mock-meetings";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Meeting Mind — Notes that write themselves" },
      { name: "description", content: "A calm, paper-inspired workspace for recording, transcribing, and summarizing meetings." },
    ],
  }),
  component: MeetingMindApp,
});

type Tab = "transcript" | "summary" | "decisions" | "actions" | "email";

const TAG_STYLES: Record<Meeting["tag"], string> = {
  product: "bg-highlight-yellow/70 text-ink",
  design: "bg-highlight-pink/70 text-ink",
  sales: "bg-highlight-mint/80 text-ink",
  "1:1": "bg-tab-manila text-ink",
  sync: "bg-secondary text-ink",
};

function MeetingMindApp() {
  const [selectedId, setSelectedId] = useState(meetings[0].id);
  const [tab, setTab] = useState<Tab>("summary");
  const [query, setQuery] = useState("");
  const [recording, setRecording] = useState(false);

  const filtered = useMemo(
    () =>
      meetings.filter((m) =>
        (m.title + " " + m.participants.join(" ")).toLowerCase().includes(query.toLowerCase()),
      ),
    [query],
  );

  const meeting = meetings.find((m) => m.id === selectedId)!;

  return (
    <div className="flex h-screen w-full overflow-hidden bg-background text-foreground">
      {/* Sidebar */}
      <aside className="flex w-[320px] shrink-0 flex-col border-r border-border/60 bg-[oklch(0.94_0.02_80)]">
        <div className="flex items-center gap-2 px-5 pt-6 pb-4">
          <div className="grid h-9 w-9 place-items-center rounded-lg bg-accent text-accent-foreground shadow-paper">
            <StickyNote className="h-5 w-5" strokeWidth={2.2} />
          </div>
          <div className="leading-tight">
            <div className="font-serif text-xl tracking-tight">Meeting Mind</div>
            <div className="text-[11px] uppercase tracking-[0.18em] text-muted-foreground">
              Notebook
            </div>
          </div>
        </div>

        <div className="px-4 pb-3">
          <div className="flex items-center gap-2 rounded-md border border-border/70 bg-paper/70 px-3 py-2 text-sm shadow-paper">
            <Search className="h-4 w-4 text-muted-foreground" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search meetings…"
              className="w-full bg-transparent outline-none placeholder:text-muted-foreground/70"
            />
          </div>
        </div>

        <div className="flex items-center justify-between px-5 pb-2 pt-1">
          <div className="font-hand text-2xl text-ink/80">Meetings</div>
          <button className="grid h-7 w-7 place-items-center rounded-md text-muted-foreground hover:bg-paper hover:text-ink">
            <Plus className="h-4 w-4" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto px-3 pb-4">
          <ul className="space-y-1.5">
            {filtered.map((m) => (
              <li key={m.id}>
                <button
                  onClick={() => setSelectedId(m.id)}
                  className={cn(
                    "group w-full rounded-md border px-3 py-3 text-left transition-all",
                    selectedId === m.id
                      ? "border-accent/40 bg-paper shadow-paper"
                      : "border-transparent hover:bg-paper/60",
                  )}
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <span
                          className={cn(
                            "rounded-sm px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide",
                            TAG_STYLES[m.tag],
                          )}
                        >
                          {m.tag}
                        </span>
                        <span className="text-[11px] text-muted-foreground">
                          {relativeDay(m.date)}
                        </span>
                      </div>
                      <div className="mt-1.5 truncate font-serif text-[17px] leading-snug text-ink">
                        {m.title}
                      </div>
                      <div className="mt-1 flex items-center gap-3 text-[11px] text-muted-foreground">
                        <span className="inline-flex items-center gap-1">
                          <Clock className="h-3 w-3" /> {m.duration}
                        </span>
                        <span className="inline-flex items-center gap-1">
                          <Users className="h-3 w-3" /> {m.participants.length}
                        </span>
                      </div>
                    </div>
                    <ChevronRight
                      className={cn(
                        "mt-1 h-4 w-4 shrink-0 text-muted-foreground/40 transition-opacity",
                        selectedId === m.id ? "text-accent opacity-100" : "opacity-0 group-hover:opacity-60",
                      )}
                    />
                  </div>
                </button>
              </li>
            ))}
          </ul>
        </div>

        <div className="border-t border-border/60 p-3">
          <button className="flex w-full items-center gap-2 rounded-md px-2 py-2 text-sm text-muted-foreground hover:bg-paper hover:text-ink">
            <Settings className="h-4 w-4" /> Settings
          </button>
        </div>
      </aside>

      {/* Main canvas */}
      <main className="relative flex flex-1 flex-col overflow-hidden">
        {/* Toolbar */}
        <div className="flex items-center justify-between border-b border-border/60 bg-[oklch(0.955_0.015_80)] px-6 py-3">
          <div className="flex items-center gap-1">
            <ToolIcon icon={Pen} label="Pen" active />
            <ToolIcon icon={Highlighter} label="Highlight" />
            <ToolIcon icon={FileText} label="Text" />
            <div className="mx-2 h-6 w-px bg-border" />
            <div className="flex items-center gap-1.5">
              {["#e05e4a", "#f0c14a", "#7aa87a", "#4a6ea8", "#2a2a2a"].map((c) => (
                <button
                  key={c}
                  className="h-4 w-4 rounded-full ring-1 ring-black/10 transition-transform hover:scale-110"
                  style={{ backgroundColor: c }}
                  aria-label={`Ink ${c}`}
                />
              ))}
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button className="inline-flex items-center gap-1.5 rounded-md border border-border bg-paper px-3 py-1.5 text-sm text-ink hover:bg-paper/70">
              <Upload className="h-3.5 w-3.5" /> Import audio
            </button>
            <button
              onClick={() => setRecording((r) => !r)}
              className={cn(
                "inline-flex items-center gap-2 rounded-md px-3.5 py-1.5 text-sm font-medium shadow-paper transition-colors",
                recording
                  ? "bg-accent text-accent-foreground"
                  : "bg-ink text-primary-foreground hover:bg-ink/90",
              )}
            >
              {recording ? (
                <>
                  <span className="relative flex h-2 w-2">
                    <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-accent-foreground opacity-75" />
                    <span className="relative inline-flex h-2 w-2 rounded-full bg-accent-foreground" />
                  </span>
                  Recording
                </>
              ) : (
                <>
                  <Mic className="h-3.5 w-3.5" /> Record
                </>
              )}
            </button>
          </div>
        </div>

        {/* Paper area */}
        <div className="flex-1 overflow-y-auto">
          <div className="mx-auto max-w-4xl px-8 py-10">
            <article className="paper-plain rounded-lg shadow-paper">
              {/* Page header */}
              <header className="border-b border-rule/60 px-12 pt-12 pb-8">
                <div className="flex items-center gap-2 text-[11px] uppercase tracking-[0.2em] text-muted-foreground">
                  <span
                    className={cn(
                      "rounded-sm px-1.5 py-0.5 text-[10px] font-medium",
                      TAG_STYLES[meeting.tag],
                    )}
                  >
                    {meeting.tag}
                  </span>
                  <span>{formatDate(meeting.date)}</span>
                  <span>·</span>
                  <span>{meeting.duration}</span>
                </div>
                <h1 className="mt-3 font-serif text-4xl leading-tight tracking-tight text-ink">
                  {meeting.title}
                </h1>
                <div className="mt-4 flex flex-wrap items-center gap-2">
                  {meeting.participants.map((p) => (
                    <span
                      key={p}
                      className="inline-flex items-center gap-1.5 rounded-full border border-border bg-secondary/60 px-2.5 py-0.5 text-xs text-ink"
                    >
                      <span className="grid h-4 w-4 place-items-center rounded-full bg-accent/80 text-[9px] font-semibold text-accent-foreground">
                        {p[0]}
                      </span>
                      {p}
                    </span>
                  ))}
                </div>

                {recording && <WaveformBanner />}
              </header>

              {/* Tabs — manila folder style */}
              <div className="flex items-end gap-1 px-8 pt-4">
                {(
                  [
                    { id: "summary", label: "Summary", icon: Sparkles },
                    { id: "decisions", label: "Decisions", icon: CheckSquare },
                    { id: "actions", label: "Action Items", icon: CheckSquare },
                    { id: "email", label: "Follow-up", icon: Mail },
                    { id: "transcript", label: "Transcript", icon: FileText },
                  ] as { id: Tab; label: string; icon: typeof Sparkles }[]
                ).map((t) => (
                  <button
                    key={t.id}
                    onClick={() => setTab(t.id)}
                    className={cn(
                      "inline-flex items-center gap-1.5 rounded-t-md border border-b-0 border-border/70 px-4 py-2 text-sm transition-colors",
                      tab === t.id
                        ? "translate-y-px bg-paper text-ink"
                        : "bg-tab-manila/60 text-ink/70 hover:bg-tab-manila",
                    )}
                  >
                    <t.icon className="h-3.5 w-3.5" />
                    {t.label}
                  </button>
                ))}
              </div>

              <section className="border-t border-border/70 px-12 py-10">
                {tab === "summary" && <SummaryView meeting={meeting} />}
                {tab === "decisions" && <DecisionsView meeting={meeting} />}
                {tab === "actions" && <ActionsView meeting={meeting} />}
                {tab === "email" && <EmailView meeting={meeting} />}
                {tab === "transcript" && <TranscriptView meeting={meeting} />}
              </section>
            </article>

            <p className="mt-8 text-center font-hand text-xl text-muted-foreground/70">
              — end of page —
            </p>
          </div>
        </div>
      </main>
    </div>
  );
}

function ToolIcon({
  icon: Icon,
  label,
  active,
}: {
  icon: typeof Pen;
  label: string;
  active?: boolean;
}) {
  return (
    <button
      title={label}
      className={cn(
        "grid h-8 w-8 place-items-center rounded-md transition-colors",
        active ? "bg-paper text-ink shadow-paper" : "text-muted-foreground hover:bg-paper/60 hover:text-ink",
      )}
    >
      <Icon className="h-4 w-4" />
    </button>
  );
}

function WaveformBanner() {
  return (
    <div className="mt-6 flex items-center gap-3 rounded-md border border-accent/30 bg-accent/5 px-4 py-3">
      <div className="flex items-end gap-[3px] h-6">
        {Array.from({ length: 28 }).map((_, i) => (
          <span
            key={i}
            className="wave-bar w-[3px] rounded-full bg-accent"
            style={{
              height: `${20 + ((i * 37) % 80)}%`,
              animationDelay: `${(i % 8) * 90}ms`,
            }}
          />
        ))}
      </div>
      <div className="flex-1 text-sm text-ink">
        <span className="font-medium">Recording in progress</span>
        <span className="ml-2 text-muted-foreground">— Whisper will transcribe on stop</span>
      </div>
      <span className="font-hand text-2xl text-accent">00:42</span>
    </div>
  );
}

function SummaryView({ meeting }: { meeting: Meeting }) {
  return (
    <div className="space-y-6">
      <SectionHeader icon={Sparkles} title="Summary" subtitle="Generated by Gemini · 3 Flash" />
      <ul className="space-y-3 font-serif text-[19px] leading-relaxed text-ink">
        {meeting.summary.map((s, i) => (
          <li key={i} className="flex gap-3">
            <span className="mt-2.5 inline-block h-1.5 w-1.5 shrink-0 rounded-full bg-accent" />
            <span>{i === 0 ? <span className="hl-yellow">{s}</span> : s}</span>
          </li>
        ))}
      </ul>

      <div className="mt-8 rounded-md border border-dashed border-border/80 bg-secondary/40 p-4 font-hand text-lg text-ink/70">
        “Calmer we make this, the better. It should feel like a notebook, not a dashboard.” — Lena
      </div>
    </div>
  );
}

function DecisionsView({ meeting }: { meeting: Meeting }) {
  return (
    <div className="space-y-6">
      <SectionHeader icon={CheckSquare} title="Decisions" subtitle="Locked-in outcomes" />
      <ol className="space-y-4">
        {meeting.decisions.map((d, i) => (
          <li
            key={i}
            className="flex gap-4 rounded-md border border-border/60 bg-paper px-4 py-3 shadow-paper"
          >
            <span className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-ink font-serif text-sm text-primary-foreground">
              {i + 1}
            </span>
            <p className="pt-0.5 font-serif text-[18px] leading-relaxed text-ink">{d}</p>
          </li>
        ))}
      </ol>
    </div>
  );
}

function ActionsView({ meeting }: { meeting: Meeting }) {
  return (
    <div className="space-y-6">
      <SectionHeader icon={CheckSquare} title="Action items" subtitle="Owners and due dates" />
      <ul className="divide-y divide-border/60">
        {meeting.actions.map((a, i) => (
          <li key={i} className="flex items-start gap-4 py-4">
            <span
              className={cn(
                "mt-1 grid h-5 w-5 shrink-0 place-items-center rounded border-2 transition-colors",
                a.done ? "border-accent bg-accent text-accent-foreground" : "border-ink/40",
              )}
            >
              {a.done && (
                <svg viewBox="0 0 12 12" className="h-3 w-3">
                  <path d="M2 6l3 3 5-6" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              )}
            </span>
            <div className="flex-1">
              <p
                className={cn(
                  "font-serif text-[18px] leading-snug text-ink",
                  a.done && "text-ink/50 line-through decoration-accent decoration-2",
                )}
              >
                {a.what}
              </p>
              <div className="mt-1 flex items-center gap-3 text-xs text-muted-foreground">
                <span className="inline-flex items-center gap-1">
                  <span className="grid h-4 w-4 place-items-center rounded-full bg-accent/80 text-[9px] font-semibold text-accent-foreground">
                    {a.who[0]}
                  </span>
                  {a.who}
                </span>
                {a.due && (
                  <span className="font-hand text-base text-accent">due {a.due}</span>
                )}
              </div>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

function EmailView({ meeting }: { meeting: Meeting }) {
  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-4">
        <SectionHeader icon={Mail} title="Follow-up email" subtitle="Drafted from the transcript" />
        <button className="inline-flex items-center gap-1.5 rounded-md border border-border bg-paper px-3 py-1.5 text-xs text-ink hover:bg-secondary">
          <Copy className="h-3 w-3" /> Copy
        </button>
      </div>
      <div className="rounded-md border border-border/70 bg-paper shadow-paper">
        <div className="space-y-1 border-b border-border/60 px-5 py-3 text-sm">
          <div className="flex gap-2">
            <span className="w-16 text-muted-foreground">To</span>
            <span className="text-ink">{meeting.email.to}</span>
          </div>
          <div className="flex gap-2">
            <span className="w-16 text-muted-foreground">Subject</span>
            <span className="font-medium text-ink">{meeting.email.subject}</span>
          </div>
        </div>
        <pre className="whitespace-pre-wrap px-5 py-5 font-serif text-[17px] leading-relaxed text-ink">
          {meeting.email.body}
        </pre>
      </div>
    </div>
  );
}

function TranscriptView({ meeting }: { meeting: Meeting }) {
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <SectionHeader icon={FileText} title="Transcript" subtitle={`${meeting.transcript.length} segments · Whisper base.en`} />
        <button className="inline-flex items-center gap-1.5 rounded-md bg-ink px-3 py-1.5 text-xs text-primary-foreground hover:bg-ink/90">
          <Play className="h-3 w-3" /> Play audio
        </button>
      </div>

      <div className="paper-ruled rounded-md border border-border/60 pl-24 pr-8 py-6">
        <ul className="space-y-[13px] font-serif text-[19px] leading-[32px] text-ink">
          {meeting.transcript.map((line, i) => (
            <li key={i} className="flex gap-3">
              <span className="w-14 shrink-0 pt-0.5 font-hand text-lg text-accent">
                {line.t}
              </span>
              <span className="w-24 shrink-0 pt-0.5 text-sm font-medium uppercase tracking-wide text-muted-foreground">
                {line.speaker}
              </span>
              <span className="flex-1">
                {i === 1 ? (
                  <>
                    I think the core loop is: <span className="hl-yellow">record, transcribe on-device, and get a summary with action items</span>. Everything else is nice-to-have.
                  </>
                ) : i === 3 ? (
                  <>
                    From a design side — the calmer we make this, the better.{" "}
                    <span className="hl-mint">It should feel like a notebook, not a dashboard.</span>
                  </>
                ) : (
                  line.text
                )}
              </span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

function SectionHeader({
  icon: Icon,
  title,
  subtitle,
}: {
  icon: typeof Sparkles;
  title: string;
  subtitle?: string;
}) {
  return (
    <div className="flex items-center gap-3">
      <span className="grid h-9 w-9 place-items-center rounded-md bg-accent/10 text-accent">
        <Icon className="h-4 w-4" />
      </span>
      <div>
        <h2 className="font-serif text-2xl leading-none text-ink">{title}</h2>
        {subtitle && <p className="mt-1 text-xs text-muted-foreground">{subtitle}</p>}
      </div>
    </div>
  );
}
