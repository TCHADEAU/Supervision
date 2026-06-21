#!/bin/bash
# Génère le PDF brandé STE à partir de la source Markdown.
# Pipeline : Markdown --pandoc--> fragment HTML --(template charte STE)--> HTML --Chrome headless--> PDF
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/Guide_supervision_STE.md"
OUT_PDF="$DIR/Guide_supervision_STE.pdf"
LOGO="$DIR/.logo_seureca_veolia.png"
TITLE="Guide d'installation des outils de supervision"
SUBTITLE="Société Tchadienne des Eaux (STE) — Note technique"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP_HTML="$(mktemp /tmp/ste_build.XXXXXX.html)"
LOGO_B64="$(base64 -i "$LOGO" | tr -d '\n')"
# Le bandeau + la ligne meta portent déjà le titre, le sous-titre et la mention
# « Document interne… » : on les retire du corps pour éviter la redondance.
BODY="$(sed -e '1{/^# /d;}' \
            -e '/^### Société Tchadienne des Eaux/d' \
            -e '/^Document interne — Service informatique \/ SIG$/d' \
            "$SRC" | pandoc -f gfm -t html --syntax-highlighting=none)"

cat > "$TMP_HTML" <<HTML
<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8">
<style>
  :root{
    --violet:#6E5A92; --violet-d:#4C3B6B; --violet-l:#8064A2;
    --row-alt:#F3F0F8; --border:#DCD5E8; --ink:#333; --muted:#666;
    --callout-bg:#FFF8E6; --callout-border:#E0A92E; --link:#6A4C93;
  }
  @page{ size:A4; margin:18mm 16mm 20mm 16mm; }
  *{ box-sizing:border-box; }
  body{ font-family:-apple-system,"Segoe UI",Helvetica,Arial,sans-serif;
        color:var(--ink); font-size:10.5pt; line-height:1.5; margin:0; }

  .header{ background:linear-gradient(110deg,var(--violet) 0%,var(--violet-d) 100%);
           border-radius:14px; padding:26px 30px; color:#fff;
           display:flex; align-items:center; justify-content:space-between; gap:20px; }
  .header .h-title{ font-size:23pt; font-weight:700; line-height:1.15; margin:0 0 8px; }
  .header .h-sub{ font-size:10.5pt; opacity:.9; margin:0; }
  .header .logo{ background:#fff; border-radius:10px; padding:12px 16px;
                 flex:0 0 auto; }
  .header .logo img{ height:30px; display:block; }

  .meta{ color:var(--muted); font-size:9.5pt; margin:14px 2px 0;
         border-bottom:1px solid var(--border); padding-bottom:14px; }
  .meta a{ color:var(--link); }

  h2{ color:var(--violet); font-size:15pt; margin:26px 0 10px;
      padding-bottom:4px; border-bottom:2px solid var(--border); }
  h3{ color:var(--violet-d); font-size:12pt; margin:18px 0 6px; }
  h2,h3{ page-break-after:avoid; }
  p{ margin:7px 0; }
  a{ color:var(--link); }

  table{ border-collapse:collapse; width:100%; margin:12px 0; font-size:9.7pt;
         page-break-inside:avoid; }
  th{ background:var(--violet-l); color:#fff; text-align:left;
      padding:7px 10px; font-weight:600; }
  td{ padding:6px 10px; border-bottom:1px solid var(--border);
      vertical-align:top; }
  tr:nth-child(even) td{ background:var(--row-alt); }

  code{ font-family:"SF Mono",Menlo,Consolas,monospace; font-size:9pt;
        background:#F0EDF5; padding:1px 5px; border-radius:4px; color:#5A3F86; }
  pre{ background:#F6F4FA; border:1px solid var(--border); border-left:4px solid var(--violet-l);
       border-radius:6px; padding:12px 14px; overflow:auto; page-break-inside:avoid;
       font-size:8.7pt; line-height:1.45; }
  pre code{ background:none; padding:0; color:#2E2A36; }

  blockquote{ background:var(--callout-bg); border-left:4px solid var(--callout-border);
              margin:12px 0; padding:9px 14px; border-radius:0 6px 6px 0;
              page-break-inside:avoid; }
  blockquote p{ margin:3px 0; }

  ul,ol{ margin:7px 0; padding-left:22px; }
  li{ margin:3px 0; }
  ul li::marker{ color:var(--violet-l); }

  hr{ border:none; border-top:1px solid var(--border); margin:20px 0; }

  /* Le titre de section 1 commence sur la première page après l'en-tête */
  h2:first-of-type{ margin-top:18px; }
</style></head>
<body>
  <div class="header">
    <div class="h-text">
      <div class="h-title">$TITLE</div>
      <p class="h-sub">$SUBTITLE</p>
    </div>
    <div class="logo"><img src="data:image/png;base64,$LOGO_B64" alt="SEURECA VEOLIA"></div>
  </div>
  <div class="meta">Document interne — Service informatique / SIG · Diffusion restreinte · Version 1.0</div>
  $BODY
</body></html>
HTML

"$CHROME" --headless --disable-gpu --no-pdf-header-footer \
  --print-to-pdf="$OUT_PDF" "file://$TMP_HTML" 2>/dev/null

rm -f "$TMP_HTML"
echo "PDF généré : $OUT_PDF"
