#!/bin/bash
#
# ==================================================
# EML Processor for Linux Mint 22
# Extracts attachments (using ripmime or munpack)
# and saves each .eml as a nicely formatted PDF.
# ==================================================

set -e

# ----------- Function to check/install missing tools ------------
check_and_install() {
    for pkg in "$@"; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            case "$pkg" in
                munpack)
                    echo "Installing package providing munpack (mimtools)..."
                    sudo apt-get update -qq
                    sudo apt-get install -y mimtools
                    ;;
                *)
                    echo "Installing missing package: $pkg"
                    sudo apt-get update -qq
                    sudo apt-get install -y "$pkg"
                    ;;
            esac
        fi
    done
}

# ----------- Check for required tools ------------
check_and_install ripmime pandoc wkhtmltopdf
# munpack is optional, handled gracefully below
if ! command -v munpack >/dev/null 2>&1; then
    echo "Note: 'munpack' not found. Will continue with 'ripmime' only."
fi

# ----------- Ask user for input/output folders ------------
read -rp "Enter path to folder containing .eml files: " INPUT_DIR
read -rp "Enter path to output folder: " OUTPUT_DIR

# ----------- Validate input folder ------------
if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: Input directory not found!"
    exit 1
fi

# ----------- Create output folders ------------
mkdir -p "$OUTPUT_DIR/attachments"
mkdir -p "$OUTPUT_DIR/pdfs"

# ----------- Process each .eml file ------------
for eml_file in "$INPUT_DIR"/*.eml; do
    [[ -e "$eml_file" ]] || { echo "No .eml files found in $INPUT_DIR"; exit 0; }

    base_name=$(basename "$eml_file" .eml)
    echo "Processing: $base_name.eml"

    tmp_dir=$(mktemp -d)

    # --- Try extracting attachments ---
    ATTACH_OK=false
    if command -v ripmime >/dev/null 2>&1; then
        ripmime --name-by-type --no-nameless --unique-names \
            --verbose=0 --prefix="$tmp_dir/" --output="$tmp_dir" --input="$eml_file" >/dev/null 2>&1 \
            && ATTACH_OK=true
    fi

    if [[ "$ATTACH_OK" == false && -x "$(command -v munpack)" ]]; then
        munpack -q -C "$tmp_dir" "$eml_file" >/dev/null 2>&1 && ATTACH_OK=true
    fi

    if [[ "$ATTACH_OK" == true && $(ls -A "$tmp_dir" 2>/dev/null) ]]; then
        mkdir -p "$OUTPUT_DIR/attachments/$base_name"
        mv "$tmp_dir"/* "$OUTPUT_DIR/attachments/$base_name"/ 2>/dev/null || true
        echo "  📎 Attachments extracted."
    else
        echo "  ⚠️  No attachments found or extraction failed."
    fi

    # --- Extract headers ---
    FROM=$(grep -m1 -i "^From:" "$eml_file" | sed 's/^From:[[:space:]]*//I')
    TO=$(grep -m1 -i "^To:" "$eml_file" | sed 's/^To:[[:space:]]*//I')
    SUBJECT=$(grep -m1 -i "^Subject:" "$eml_file" | sed 's/^Subject:[[:space:]]*//I')
    DATE=$(grep -m1 -i "^Date:" "$eml_file" | sed 's/^Date:[[:space:]]*//I')

    [[ -z "$FROM" ]] && FROM="(unknown sender)"
    [[ -z "$TO" ]] && TO="(unknown recipient)"
    [[ -z "$SUBJECT" ]] && SUBJECT="(no subject)"
    [[ -z "$DATE" ]] && DATE="(no date)"

    # --- Extract email body to HTML ---
    BODY_FILE="$tmp_dir/body.html"
    if ! pandoc "$eml_file" -t html -o "$BODY_FILE" >/dev/null 2>&1; then
        echo "<pre>$(cat "$eml_file")</pre>" > "$BODY_FILE"
    fi

    # --- Build full HTML with headers ---
    FINAL_HTML="$tmp_dir/final.html"
    cat > "$FINAL_HTML" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>$SUBJECT</title>
<style>
body { font-family: Arial, sans-serif; margin: 20px; }
.header { background: #f4f4f4; padding: 15px; border-radius: 8px; margin-bottom: 20px; }
.header b { display: inline-block; width: 80px; }
pre { white-space: pre-wrap; word-wrap: break-word; }
</style>
</head>
<body>
<div class="header">
  <p><b>From:</b> $FROM</p>
  <p><b>To:</b> $TO</p>
  <p><b>Date:</b> $DATE</p>
  <p><b>Subject:</b> $SUBJECT</p>
</div>
<div class="body">
$(cat "$BODY_FILE")
</div>
</body>
</html>
EOF

    # --- Convert to PDF ---
    PDF_FILE="$OUTPUT_DIR/pdfs/$base_name.pdf"
    wkhtmltopdf "$FINAL_HTML" "$PDF_FILE" >/dev/null 2>&1

    echo "  ✅ Saved PDF: $PDF_FILE"

    rm -rf "$tmp_dir"
done

echo
echo "🎉 All done!"
echo "PDFs saved in: $OUTPUT_DIR/pdfs"
echo "Attachments saved in: $OUTPUT_DIR/attachments"
