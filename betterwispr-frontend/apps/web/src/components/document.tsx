import type { ReactNode } from "react";

/** Share the complete document so React can hydrate route metadata in the head. */
export default function Document({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <head>
        <meta charSet="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <script
          defer
          data-website-id="dc_lvglnnwjg48q57"
          data-domain="betterwispr.com"
          src="https://databull-analytics.kartik-labhshetwar.workers.dev/js/script.js"
        ></script>
      </head>
      <body>
        <div id="app">{children}</div>
      </body>
    </html>
  );
}
