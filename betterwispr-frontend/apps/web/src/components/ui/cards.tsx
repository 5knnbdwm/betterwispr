import { cn } from "@betterwispr-frontend/ui/lib/utils";
import { ArrowUpRight } from "lucide-react";

import DownloadCount from "@/components/download-count";

export type Testimonial = {
  name: string;
  handle?: string;
  quote: string;
  postUrl: string;
  image?: string;
};

const SOURCES = [
  { name: "X", label: "X", pattern: /^https:\/\/(?:x\.com|twitter\.com)\/\w+\/status\/\d+\/?(?:[?#].*)?$/ },
  { name: "Hacker News", label: "HN", pattern: /^https:\/\/news\.ycombinator\.com\/item\?id=\d+$/ },
];

function TestimonialCard({
  testimonial,
  preview,
}: {
  testimonial: Testimonial;
  preview: boolean;
}) {
  const { name, handle, quote, postUrl, image } = testimonial;
  const source = SOURCES.find(({ pattern }) => pattern.test(postUrl));

  return (
    <figure className="testimonial-card flex h-full flex-col rounded-2xl border border-zinc-200 bg-white p-6 transition-colors hover:border-zinc-300">
      <figcaption className="flex items-center gap-3">
        <div className="relative flex size-10 shrink-0 items-center justify-center overflow-hidden rounded-full bg-paper text-sm font-medium text-zinc-600">
          <span aria-hidden="true">{name.slice(0, 1)}</span>
          {image && (
            <img
              src={image}
              alt=""
              width={40}
              height={40}
              loading="lazy"
              decoding="async"
              className="absolute inset-0 size-full object-cover"
              onError={(event) => { event.currentTarget.hidden = true; }}
            />
          )}
        </div>
        <div className="min-w-0 flex-1">
          <p className="break-words text-sm font-semibold text-zinc-900">{name}</p>
          {handle && <p className="break-all text-xs text-zinc-500">{handle}</p>}
        </div>
        {source && (
          <span className="text-sm font-medium text-zinc-400" aria-label={source.name}>{source.label}</span>
        )}
      </figcaption>
      <blockquote className="my-6 whitespace-pre-line break-words text-base leading-relaxed text-zinc-700">
        {quote}
      </blockquote>
      <div className="mt-auto border-t border-zinc-100 pt-4 text-xs">
        {preview ? (
          <span className="text-zinc-500">Sample testimonial · preview only</span>
        ) : source ? (
          <a
            href={postUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex min-h-6 items-center gap-1.5 rounded-sm font-medium text-zinc-600 hover:text-[#00159d]"
            aria-label={`Read ${name}’s post on ${source.name} (opens in a new tab)`}
          >
            Read on {source.name} <ArrowUpRight className="size-3.5" aria-hidden="true" />
          </a>
        ) : (
          <span className="text-zinc-500">Post link unavailable</span>
        )}
      </div>
    </figure>
  );
}

export default function Testimonials({
  testimonials,
  preview = false,
}: {
  testimonials: readonly Testimonial[];
  preview?: boolean;
}) {
  if (testimonials.length === 0) return null;

  const scrolling = testimonials.length >= 6;
  const midpoint = Math.ceil(testimonials.length / 2);

  return (
    <section
      id="testimonials"
      aria-labelledby="testimonials-title"
      className="border-y border-zinc-200 bg-zinc-50/70 py-16 sm:py-20"
    >
      <div className="page-shell">
        <div className="mx-auto max-w-xl text-center">
          <p className="eyebrow">What people are saying</p>
          <h2 id="testimonials-title" className="mt-4 text-3xl tracking-tight sm:text-4xl">
            Your voice. In your words.
          </h2>
          <p className="mt-4 text-base text-zinc-600">
            {preview ? (
              "A preview with sample quotes and stock photos, not real endorsements."
            ) : (
              <>
                <DownloadCount className="font-semibold text-zinc-900" />
                Posts and replies about BetterWispr on Hacker News and X.
              </>
            )}
          </p>
        </div>

        {scrolling ? (
          <div className="testimonials-marquee mt-10 space-y-4">
            {[testimonials.slice(0, midpoint), testimonials.slice(midpoint)].map((row, index) => (
              <div className="testimonials-window overflow-hidden" key={index}>
                <div className={cn("testimonials-track flex w-max", index === 1 && "testimonials-track-reverse")}>
                  {[false, true].map((duplicate) => (
                    <div
                      key={String(duplicate)}
                      className="testimonials-group flex gap-4 pr-4"
                      aria-hidden={duplicate || undefined}
                      inert={duplicate || undefined}
                    >
                      {row.map((testimonial, cardIndex) => (
                        <TestimonialCard key={cardIndex} testimonial={testimonial} preview={preview} />
                      ))}
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {testimonials.map((testimonial, index) => (
              <TestimonialCard key={index} testimonial={testimonial} preview={preview} />
            ))}
          </div>
        )}
      </div>
    </section>
  );
}
