#!/bin/bash

# Ensure that two arguments are provided
if [ $# -ne 2 ]; then
 echo "Usage: $0 <input_pdf> <bitmap_image>"
 exit 1
fi

INPUT_PDF="$1"
BITMAP_IMAGE="$2"
OUTPUT_PDF="stamp_$1"

# Create a temporary directory for intermediate files
TEMP_DIR="tmp"
mkdir -p "$TEMP_DIR"
rm -f "$TEMP_DIR"/*

# Get number of pages in the PDF
PAGE_COUNT=$(pdfinfo "$INPUT_PDF" | grep "Pages" | awk '{print $2}')

# Get the dimensions of the PDF (assuming all pages have the same dimensions)
PDF_WIDTH=$(pdfinfo "$INPUT_PDF" | grep "Page size" | awk '{print $3}')
PDF_HEIGHT=$(pdfinfo "$INPUT_PDF" | grep "Page size" | awk '{print $5}')

# Get the dimensions of the resized bitmap
ORIGINAL_BITMAP_WIDTH=$(identify -format "%w" "$BITMAP_IMAGE")
ORIGINAL_BITMAP_HEIGHT=$(identify -format "%h" "$BITMAP_IMAGE")

# Ensure the bitmap image fits the page size (resize if necessary)
if (( $(echo "$ORIGINAL_BITMAP_WIDTH > $PDF_WIDTH" | bc -l) )) || (( $(echo "$ORIGINAL_BITMAP_HEIGHT > $PDF_HEIGHT" | bc -l) )); then
    mogrify -resize "${PDF_WIDTH}x${PDF_HEIGHT}" "$BITMAP_IMAGE"
fi

# Split the PDF into individual pages
pdftk "$INPUT_PDF" burst output "$TEMP_DIR/page_%04d.pdf"

# Process each page
for i in $(seq -f "%04g" 1 $PAGE_COUNT); do
    PAGE_PDF="$TEMP_DIR/page_$i.pdf"

    # Generate a random rotation angle between 0 and 32
    ROTATE_ANGLE=$((RANDOM % 34))

    # And sometimes make the rotation angle 360 - ROTATE_ANGLE (50% chance)
    if [ "$((RANDOM % 2))" -eq 1 ]; then
        ROTATE_ANGLE=$((360 - ROTATE_ANGLE))
    fi

    # Create a temporary rotated bitmap
    convert "$BITMAP_IMAGE" -background transparent -rotate "$ROTATE_ANGLE" -gravity northwest "$TEMP_DIR/bitmap_page_$i.png"

   # Get the dimensions of the resized bitmap
   BITMAP_WIDTH=$(identify -format "%w" "$BITMAP_IMAGE")
   BITMAP_HEIGHT=$(identify -format "%h" "$BITMAP_IMAGE") 
 
   # Round dimensions
   X=$(echo "scale=0; ($PDF_WIDTH - $BITMAP_WIDTH)/1" | bc)
   Y=$(echo "scale=0; ($PDF_HEIGHT - $BITMAP_HEIGHT)/1" | bc)

   # Calculate random X and Y coordinates, ensuring the bitmap doesn't overflow the page
   RAND_X=$((RANDOM % X))
   RAND_Y=$((RANDOM % Y)) 

    # Generate the overlay PDF
    convert -size "${PDF_WIDTH}x${PDF_HEIGHT}" xc:transparent \
        "$TEMP_DIR/bitmap_page_$i.png" -geometry +${RAND_X}+${RAND_Y} -composite "$TEMP_DIR/overlay_$i.pdf"

    # Overlay the original page with the bitmap
    pdftk "$PAGE_PDF" stamp "$TEMP_DIR/overlay_$i.pdf" output "$TEMP_DIR/final_page_$i.pdf"
done

# Combine all the processed pages into the final output PDF
pdftk "$TEMP_DIR/final_page_"*.pdf cat output "$OUTPUT_PDF"

echo "Overlay PDF created: $OUTPUT_PDF"
