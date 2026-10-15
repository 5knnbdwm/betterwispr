import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuLinkItem,
  DropdownMenuTrigger,
} from "@betterwispr-frontend/ui/components/dropdown-menu";
import { track } from "@databuddy/sdk";
import {
  ArrowUpRightIcon,
  CaretDownIcon,
  DownloadSimpleIcon,
} from "@phosphor-icons/react";

import AppleLogo from "@/components/apple-logo";
import DownloadCount, {
  COUNT_FORMAT,
  useDownloadCount,
} from "@/components/download-count";
import { DOWNLOAD_URL, INTEL_DOWNLOAD_URL } from "@/lib/links";

const DOWNLOADS = [
  { href: DOWNLOAD_URL, chip: "Apple Silicon", macs: "M1 or newer" },
  { href: INTEL_DOWNLOAD_URL, chip: "Intel", macs: "Intel-based Macs" },
];

const FEATURED_QUOTE = {
  name: "GodelNumbering",
  postUrl: "https://news.ycombinator.com/item?id=50046250",
  before:
    "Just tried it out as I was looking for something that does this exact thing well (macbook). So far I dictated about 5 different things in different contexts, ",
  highlight: "it worked without a single error!",
};

export default function DownloadCTA({
  compact = false,
}: {
  compact?: boolean;
}) {
  const downloads = useDownloadCount();
  if (compact) {
    return (
      <DropdownMenu>
        <DropdownMenuTrigger className="download-cta group cursor-pointer text-sm">
          <AppleLogo className="size-4" />
          Download
          <CaretDownIcon
            weight="bold"
            className="size-3.5 transition-transform duration-300 ease-fluid group-data-popup-open:rotate-180"
            aria-hidden="true"
          />
        </DropdownMenuTrigger>
        <DropdownMenuContent
          align="end"
          sideOffset={8}
          className="w-60 rounded-xl bg-white p-1 text-zinc-900 shadow-lg ring-zinc-200"
        >
          {DOWNLOADS.map(({ href, chip, macs }) => (
            <DropdownMenuLinkItem
              key={href}
              href={href}
              closeOnClick
              onClick={() => track("download_started")}
              className="cursor-pointer gap-3 rounded-lg px-3 py-2 text-sm focus:bg-zinc-100 focus:text-zinc-900"
            >
              <span className="flex-1">
                <span className="block font-semibold">{chip}</span>
                <span className="block text-xs text-zinc-600">{macs}</span>
              </span>
              <DownloadSimpleIcon className="text-zinc-500" />
            </DropdownMenuLinkItem>
          ))}
          {downloads !== undefined && (
            <p className="mt-1 border-t border-zinc-100 px-3 pt-2 pb-1.5 text-xs text-zinc-500 tabular-nums">
              {COUNT_FORMAT.format(downloads)} downloads so far
            </p>
          )}
        </DropdownMenuContent>
      </DropdownMenu>
    );
  }
  return (
    <div className="inline-flex flex-col items-center gap-3">
      <a
        href={DOWNLOAD_URL}
        onClick={() => track("download_started")}
        className="download-cta text-base"
      >
        <AppleLogo className="size-5" />
        Download for Apple Silicon
      </a>
      <a
        href={INTEL_DOWNLOAD_URL}
        onClick={() => track("download_started")}
        className="text-sm text-zinc-600 underline underline-offset-4 hover:text-zinc-900"
      >
        Download for Intel
      </a>
    </div>
  );
}

export function ClosingCTA() {
  return (
    <section
      className="bg-paper px-6 py-20 text-center"
      aria-labelledby="start-title"
    >
      <p className="eyebrow">Your next thought, in your own words</p>
      <h2
        id="start-title"
        className="mx-auto mt-4 max-w-[680px] text-4xl tracking-tight sm:text-5xl"
      >
        Give your keyboard a break.
      </h2>
      <p className="mx-auto mt-6 max-w-xl text-lg text-zinc-600">
        Local speech models. The apps you already use. A little more room to
        think.
      </p>
      <figure className="mx-auto mt-12 max-w-2xl">
        <figcaption className="flex flex-col items-center">
          <span className="text-base font-semibold text-zinc-900">
            {FEATURED_QUOTE.name}
          </span>
          <a
            href={FEATURED_QUOTE.postUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex min-h-6 items-center gap-1 text-xs text-zinc-500 hover:text-zinc-900"
            aria-label={`Read ${FEATURED_QUOTE.name}’s comment on Hacker News (opens in a new tab)`}
          >
            on Hacker News
            <ArrowUpRightIcon className="size-3" aria-hidden="true" />
          </a>
        </figcaption>
        <blockquote className="mt-6 font-serif text-2xl leading-snug text-zinc-800 italic sm:text-3xl">
          <span className="text-yellow-700">“</span>
          {FEATURED_QUOTE.before}
          <mark className="rounded-sm bg-yellow-200/70 box-decoration-clone px-1 text-inherit">
            {FEATURED_QUOTE.highlight}
          </mark>
          <span className="text-yellow-700">”</span>
        </blockquote>
      </figure>
      <div className="mt-10">
        <DownloadCTA />
      </div>
      <p className="mt-4 text-sm text-zinc-600">
        <DownloadCount className="font-semibold text-zinc-900" />
        macOS 14+ · Apple Silicon recommended · No account in the app
      </p>
    </section>
  );
}
