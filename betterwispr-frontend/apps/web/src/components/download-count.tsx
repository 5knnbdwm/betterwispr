import { useEffect, useState } from "react";

import { GITHUB_API_URL } from "@/lib/links";

export const COUNT_FORMAT = new Intl.NumberFormat("en-US");

type Release = { assets: { name: string; download_count: unknown }[] };

/** Sums DMG downloads, leaving out appcast.xml fetches, which are update checks rather than installs. */
export function countInstallerDownloads(releases: Release[]) {
  return releases
    .flatMap(({ assets }) => assets)
    .filter(({ name }) => name.endsWith(".dmg"))
    .reduce((total, { download_count }) => {
      if (
        typeof download_count !== "number" ||
        !Number.isSafeInteger(download_count) ||
        download_count < 0
      ) {
        throw new Error("Invalid download count");
      }
      return total + download_count;
    }, 0);
}

let installerDownloads: Promise<number> | undefined;

/** Fetches the newest 100 GitHub releases once per page load. */
function fetchInstallerDownloads() {
  installerDownloads ??= fetch(`${GITHUB_API_URL}/releases?per_page=100`, {
    headers: { Accept: "application/vnd.github+json" },
  })
    .then((response) =>
      response.ok
        ? response.json()
        : Promise.reject(new Error(`GitHub ${response.status}`)),
    )
    .then(countInstallerDownloads);
  return installerDownloads;
}

/** Live installer download total, or undefined until GitHub answers with a positive count. */
export function useDownloadCount() {
  const [count, setCount] = useState<number>();

  useEffect(() => {
    let active = true;
    fetchInstallerDownloads().then(
      (total) => {
        if (active && total > 0) setCount(total);
      },
      () => {},
    );
    return () => {
      active = false;
    };
  }, []);

  return count;
}

/** Download total followed by a separator, for the start of a "·" list. Hidden until it loads. */
export default function DownloadCount({ className }: { className?: string }) {
  const count = useDownloadCount();
  if (count === undefined) return null;
  return (
    <>
      <span className={`tabular-nums ${className ?? ""}`}>
        {COUNT_FORMAT.format(count)} downloads
      </span>
      {" · "}
    </>
  );
}
