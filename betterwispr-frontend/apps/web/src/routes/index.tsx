import { ArrowRightIcon, CheckIcon, CoffeeIcon } from "@phosphor-icons/react";
import { Link, createFileRoute } from "@tanstack/react-router";
import { useEffect, useRef } from "react";
import DownloadCTA, { ClosingCTA } from "@/components/download-cta";
import DownloadCount from "@/components/download-count";
import HeroDemo from "@/components/hero-demo";
import FeatureBento from "@/components/feature-bento";
import Testimonials, { type Testimonial } from "@/components/ui/cards";
import { comparisons } from "@/lib/comparisons";
import { BUY_ME_A_COFFEE_URL } from "@/lib/links";
import { pageHead } from "@/lib/seo";

export const Route = createFileRoute("/")({
  component: HomeComponent,
  head: () =>
    pageHead(
      "BetterWispr: local dictation for macOS",
      "Hold a shortcut, speak, and BetterWispr types clean text into any Mac app. Local speech models, a style for each app, meeting notes and insights. Free and open source, with no account required.",
      "/",
    ),
});

const FAQS = [
  [
    "Is BetterWispr free?",
    "Yes. BetterWispr is free and open source under Apache 2.0, with no dictation subscription, account or API key requirement. Model files use storage on your Mac.",
  ],
  [
    "Which Macs does it support?",
    "BetterWispr requires macOS 14 or later. Apple Silicon is recommended for local model inference. Model availability and performance depend on your hardware and language.",
  ],
  [
    "Does it work without internet?",
    "Yes, once a compatible local model and its required assets are installed. Downloadable models need an explicit installation first. Apple on device speech also depends on supported languages and OS assets. There is no cloud transcription fallback.",
  ],
  [
    "How do I dictate?",
    "Focus a text field, hold Option + Space, speak, and release to transcribe. You can switch to press to toggle or choose a different shortcut in Settings. Transcription begins after recording stops, rather than appearing word by word while you talk.",
  ],
  [
    "Why does it need permissions?",
    "Microphone permission lets BetterWispr record your voice. Accessibility permission allows automatic insertion into another app. Apple speech also requires Speech Recognition permission. You control these in System Settings.",
  ],
  [
    "What if automatic paste does not work?",
    "BetterWispr checks the target app before inserting text. If it cannot safely paste, retrieve the transcript from the dashboard and copy it yourself. Secure fields and some apps may block automatic insertion.",
  ],
  [
    "Which languages are supported?",
    "Language support depends on the selected model. Parakeet TDT v3 covers 25 European languages, Parakeet Japanese covers Japanese, and Whisper offers broader multilingual recognition. Apple speech depends on your locale and installed assets. Filler cleanup, styles and voice commands work in English. Test your chosen model with your own speech.",
  ],
  [
    "Does it rewrite everything I say?",
    "Only as much as you choose. Auto cleanup starts at Light, which removes English filler words, repeats and false starts. Choose None to keep every word, or Medium to also edit English for clarity with the notes model you chose in Models. Apple Intelligence and Ollama do that on your Mac. Claude Code, Codex and API connections send the dictation to that provider, and only if you pick one. Styles adjust punctuation and capitalization for each kind of app. History keeps the raw transcript, and Use Original restores it.",
  ],
  [
    "Can it take meeting notes?",
    "Yes. Notetaker transcribes your microphone as Me and, on macOS 14.2 or later, other apps’ audio as Them, while you write your own notes. Afterwards, Apple Intelligence on supported Macs running macOS 26 or a local Ollama model writes the summary, decisions and action items on your Mac. Claude Code, Codex and OpenAI compatible endpoints are optional and send the transcript to that provider. Without a notes model, the transcript and your notes are still saved.",
  ],
  [
    "Does it learn my words?",
    "Yes. Add names and terms in Vocabulary, or fix a misheard word in History or right after it is pasted. BetterWispr adds the correction to Vocabulary and spells it your way next time. You can turn learning off in Settings.",
  ],
];

const TESTIMONIALS: Testimonial[] = [
  {
    name: "GodelNumbering",
    quote: "Just tried it out as I was looking for something that does this exact thing well (macbook). So far I dictated about 5 different things in different contexts, it worked without a single error! Good choice to pick parakeet v3.\nNice work, thanks for building it!",
    postUrl: "https://news.ycombinator.com/item?id=50046250",
  },
  {
    name: "Ed | supersetapp.com",
    handle: "@edsonboldrini",
    quote: "I'm using this one and it's amazing",
    postUrl: "https://x.com/edsonboldrini/status/2110483450759127044",
    image: "https://pbs.twimg.com/profile_images/1950971738004520960/x6P9r8Bk_200x200.jpg",
  },
  {
    name: "Adetola Solesi",
    handle: "@adetola_solesi",
    quote: "ok so someone made a free, open source dictation app for Mac. Hold Option and Space, talk, let go, and it types into whatever app you're in. The speech models run on your Mac, unless you plug in an API yourself. No account needed.",
    postUrl: "https://x.com/adetola_solesi/status/2109431458519548036",
    image: "https://pbs.twimg.com/profile_images/1980046673611988992/1Y-CcolV_200x200.jpg",
  },
  {
    name: "apparent",
    quote: "Interested to give this a try. I've tried Wispr Flow and found it to be quite good, but a bit pricey for my taste. I guess I assumed there were equally good models that were cheaper, and I suppose this is one of them.",
    postUrl: "https://news.ycombinator.com/item?id=50051742",
  },
  {
    name: "予知言 Lucian",
    handle: "@YuzhiyanLucian",
    quote: "语音输入也要按月订阅，我有点受不了。\n\nBetterWispr 是个免费的 Mac 语音输入工具。按住快捷键说话，松开，文字就填进当前输入框。\n\n选内置模型，下载好以后可以离线转写，录音不用上传。",
    postUrl: "https://x.com/YuzhiyanLucian/status/2109842025994506677",
    image: "https://pbs.twimg.com/profile_images/2109250064698753024/5fYTY_yO_200x200.jpg",
  },
  {
    name: "Sameer Vanjari",
    handle: "@VanjariSameer",
    quote: "I just read your post in the morning. and now you have the app. Amazing.",
    postUrl: "https://x.com/VanjariSameer/status/2108248442770534481",
    image: "https://pbs.twimg.com/profile_images/1595780430233743362/2e1GDWhj_200x200.jpg",
  },
  {
    name: "小弟调调",
    handle: "@jaywcjlove",
    quote: "BetterWispr - 免费开源、本地优先的 Wispr Flow 替代品：用 Whisper、Parakeet 和 Apple 语音在设备端听写",
    postUrl: "https://x.com/jaywcjlove/status/2109855640743280671",
    image: "https://pbs.twimg.com/profile_images/764536725750165504/DFOYV1w3_200x200.jpg",
  },
  {
    name: "frenchie4111",
    quote: "This is awesome. I really want to get something like this integrated directly into my agent IDE.",
    postUrl: "https://news.ycombinator.com/item?id=50044781",
  },
  {
    name: "AI 极客新闻",
    handle: "@aigeeknews",
    quote: "开源的 macOS 离线听写\n\nBetterWispr 按住 ⌥ Space 说话，松开后文字落进当前应用，转写在本机用 Whisper、Parakeet 或 Apple 的语音识别跑。",
    postUrl: "https://x.com/aigeeknews/status/2109847316614217748",
    image: "https://pbs.twimg.com/profile_images/2101566279299809280/ETiRfmNX_200x200.jpg",
  },
  {
    name: "Nikhil Bhima",
    handle: "@nikhilbhima",
    quote: "haha, product looks good btw\n\ngoodluck :)",
    postUrl: "https://x.com/nikhilbhima/status/2108231675977384037",
    image: "https://pbs.twimg.com/profile_images/2043046755663749120/weEgP_gC_200x200.jpg",
  },
  {
    name: "Na6z",
    quote: "This is pretty neat, I built something similar a couple months ago.",
    postUrl: "https://news.ycombinator.com/item?id=50044482",
  },
  {
    name: "Rahul Karajgikar",
    handle: "@Road_Kill11",
    quote: "sick stuff man",
    postUrl: "https://x.com/Road_Kill11/status/2108238524323643466",
    image: "https://pbs.twimg.com/profile_images/1940948153450004480/Fpdxv7On_200x200.jpg",
  },
];

function HomeComponent() {
  return (
    <>
      <section
        className="home-hero relative isolate overflow-hidden bg-[#00159d] text-white"
        aria-labelledby="hero-title"
      >
        <div className="page-shell relative z-10 pt-10 pb-6 text-center sm:pt-14 sm:pb-8 lg:flex lg:min-h-[640px] lg:items-center lg:py-20 lg:text-left">
          <div className="mx-auto max-w-xl lg:mx-0 lg:w-1/2">
            <p className="eyebrow text-white/75">
              Open source dictation for Mac
            </p>
            <h1
              id="hero-title"
              className="mt-5 text-[clamp(2.125rem,10vw,3.5rem)] leading-[1.08] tracking-tight lg:mt-6 lg:text-6xl xl:text-7xl"
            >
              Speak it messy.
              <br />
              Send it clean.
            </h1>
            <p className="mx-auto mt-5 max-w-md text-base leading-relaxed text-white/85 sm:text-lg lg:mx-0 lg:mt-6">
              Hold{" "}
              <kbd className="whitespace-nowrap font-medium text-white">
                ⌥ Space
              </kbd>{" "}
              in any app and just talk. BetterWispr drops the ums and false
              starts, spells names your way and writes in the style you set for
              each app. Speech stays on your Mac.
            </p>
            <div className="mt-6 lg:mt-8">
              <DownloadCTA />
            </div>
            <p className="mt-3 text-xs leading-relaxed text-white/75 sm:text-sm lg:mt-4">
              <DownloadCount className="font-semibold text-white" />
              Free · macOS 14+
              <span className="block sm:inline">
                <span className="hidden sm:inline"> · </span>
                Apple Silicon recommended
              </span>
            </p>
            <ul
              className="mt-6 flex flex-wrap justify-center gap-x-4 gap-y-2 text-xs text-white/85 sm:text-sm lg:mt-8 lg:justify-start lg:gap-x-6"
              aria-label="Product essentials"
            >
              {["No account", "Local speech models", "Meeting notes built in"].map(
                (text) => (
                  <li key={text} className="flex items-center gap-2">
                    <CheckIcon className="size-4" />
                    {text}
                  </li>
                ),
              )}
            </ul>
          </div>
        </div>
        <img
          src="/assets/hero-statue.png"
          alt=""
          width={1672}
          height={941}
          fetchPriority="high"
          className="h-[clamp(240px,75vw,360px)] w-full object-cover object-right lg:absolute lg:inset-0 lg:h-full"
        />
      </section>
      <section className="page-shell py-12 sm:py-20">
        <HeroDemo />
      </section>

      <section aria-labelledby="features" className="page-shell pb-24">
        <h2
          id="features"
          className="mx-auto max-w-[680px] text-center text-3xl tracking-tight text-zinc-900"
        >
          Speak in any app. BetterWispr handles the rest.
        </h2>
        <FeatureBento />
      </section>

      <section
        id="how-it-works"
        className="page-shell pb-24"
        aria-labelledby="how-title"
      >
        <div className="grid gap-8 border-t border-zinc-200 pt-12 md:grid-cols-[1fr_2fr]">
          <div>
            <p className="eyebrow">From thought to text</p>
            <h2 id="how-title" className="mt-4 text-3xl tracking-tight">
              One shortcut.
              <br />
              Your everyday apps.
            </h2>
          </div>
          <ol className="grid gap-8 sm:grid-cols-3">
            {[
              [
                "Set up once",
                "Install BetterWispr and follow the welcome guide through permissions and your first local speech model.",
              ],
              [
                "Hold and speak",
                "Place your cursor in a text field. Hold Option + Space and say what you want to write.",
              ],
              [
                "Release to type",
                "Let go to transcribe. Clean text arrives in the app you were using, in the style you set for it.",
              ],
            ].map(([title, body], index) => (
              <li key={title}>
                <span className="font-mono text-sm text-zinc-400">
                  0{index + 1}
                </span>
                <h3 className="mt-4 text-base font-semibold">{title}</h3>
                <p className="mt-3 text-sm text-zinc-600">{body}</p>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <Testimonials testimonials={TESTIMONIALS} />

      <section className="bg-paper py-20" aria-labelledby="local-title">
        <div className="page-shell grid items-start gap-12 md:grid-cols-2">
          <div>
            <p className="eyebrow">Local by design</p>
            <Tagline />
          </div>
          <div>
            <p className="mt-6 max-w-lg text-base text-zinc-600">
              Models run on your Mac. Downloads happen when you choose to
              install them. Your speech doesn’t need a round trip to a
              transcription server.
            </p>
            <Link
              to="/privacy"
              className="mt-6 inline-flex items-center gap-2 text-sm font-semibold hover:text-zinc-600"
            >
              How your data is handled
              <ArrowRightIcon />
            </Link>
          </div>
        </div>
      </section>

      <section className="page-shell py-24" aria-labelledby="blog-title">
        <div className="flex flex-col justify-between gap-6 sm:flex-row sm:items-end">
          <div>
            <p className="eyebrow">From the blog</p>
            <h2
              id="blog-title"
              className="mt-4 text-3xl tracking-tight sm:text-4xl"
            >
              Your voice. Your call.
            </h2>
            <p className="mt-4 max-w-xl text-base text-zinc-600">
              There’s more than one good dictation app. Our comparisons cover
              local processing, offline use and writing workflows, with
              official sources.
            </p>
          </div>
          <Link
            to="/blog"
            className="inline-flex shrink-0 items-center gap-2 text-sm font-semibold hover:text-zinc-600"
          >
            All posts
            <ArrowRightIcon />
          </Link>
        </div>
        <div className="mt-8 border-t border-zinc-200">
          {comparisons.slice(0, 4).map((item) => (
            <Link
              key={item.slug}
              to="/blog/$slug"
              params={{ slug: item.slug }}
              className="group flex items-center justify-between gap-4 border-b border-zinc-200 py-6 transition-colors duration-700 ease-fluid hover:bg-zinc-50"
            >
              <div>
                <h3 className="text-lg font-medium">
                  BetterWispr vs {item.name}
                </h3>
                <p className="mt-2 text-sm text-zinc-600">{item.summary}</p>
              </div>
              <ArrowRightIcon className="size-5 shrink-0 transition-transform duration-700 ease-fluid group-hover:translate-x-1" />
            </Link>
          ))}
        </div>
      </section>

      <section className="page-shell pb-24" aria-labelledby="faq-title">
        <div className="grid gap-8 md:grid-cols-[1fr_2fr]">
          <div>
            <p className="eyebrow">Before you download</p>
            <h2 id="faq-title" className="mt-4 text-3xl tracking-tight">
              A few good questions.
            </h2>
          </div>
          <div className="border-t border-zinc-200">
            {FAQS.map(([question, answer]) => (
              <details
                key={question}
                className="group border-b border-zinc-200 py-6"
              >
                <summary className="cursor-pointer text-base font-medium marker:text-zinc-400 hover:text-zinc-600">
                  {question}
                </summary>
                <p className="mt-4 text-base text-zinc-600">{answer}</p>
              </details>
            ))}
          </div>
        </div>
      </section>

      <section
        id="support"
        className="page-shell pb-24"
        aria-labelledby="support-title"
      >
        <div className="grid gap-8 border-t border-zinc-200 pt-12 md:grid-cols-[1fr_2fr]">
          <div>
            <p className="eyebrow">Support the project</p>
            <h2 id="support-title" className="mt-4 text-3xl tracking-tight">
              Free to use.
              <br />
              Fueled by coffee.
            </h2>
          </div>
          <div>
            <p className="max-w-lg text-base text-zinc-600">
              BetterWispr has no subscription and no account. If it saves you
              some typing, you can support its development with a donation of
              any amount.
            </p>
            <a
              href={BUY_ME_A_COFFEE_URL}
              className="mt-6 inline-flex min-h-11 items-center gap-2 rounded-lg bg-[#ffdd00] px-3 py-2 text-base font-semibold text-zinc-900 transition-all duration-700 ease-fluid hover:bg-[#ffe54d] active:scale-[0.98]"
            >
              <CoffeeIcon weight="fill" className="size-5" aria-hidden="true" />
              Buy me a coffee
            </a>
          </div>
        </div>
      </section>
      <ClosingCTA />
    </>
  );
}

function Tagline() {
  const ref = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const words = ref.current?.querySelectorAll("span");
    const observer = new IntersectionObserver(
      (entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return;
        words?.forEach((word, index) => {
          word.style.transitionDelay = `${index * 90}ms`;
          word.style.opacity = "1";
        });
        observer.disconnect();
      },
      { threshold: 0.6 },
    );
    words?.forEach((word) => {
      word.style.opacity = "0.3";
    });
    if (ref.current) observer.observe(ref.current);
    return () => observer.disconnect();
  }, []);
  return (
    <h2
      id="local-title"
      ref={ref}
      className="mt-6 max-w-[680px] text-4xl tracking-tight sm:text-5xl"
    >
      {"Your words stay ".split(" ").map((word, index) => (
        <span
          key={index}
          className="transition-opacity duration-700 ease-fluid"
        >
          {word}{" "}
        </span>
      ))}
      <br />
      {"on your Mac.".split(" ").map((word, index) => (
        <span
          key={index}
          className="transition-opacity duration-700 ease-fluid"
        >
          {word}{" "}
        </span>
      ))}
    </h2>
  );
}
