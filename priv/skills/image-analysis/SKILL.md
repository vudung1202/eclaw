---
name: image-analysis
description: Analyze images, screenshots, diagrams, OCR
triggers: [image, screenshot, picture, photo, diagram, ocr, visual, png, jpg, svg, chart, graph]
---

## Image Analysis

### Capabilities
- Describe what's in an image (UI, diagrams, charts)
- Extract text from screenshots (OCR-like)
- Analyze UI layouts and suggest improvements
- Read error messages from screenshots
- Interpret charts and graphs

### Working with images
```bash
# Check image info
file image.png
identify image.png                    # ImageMagick

# Convert formats
convert input.png output.jpg          # ImageMagick
sips -s format jpeg input.png --out output.jpg  # macOS

# Resize
convert input.png -resize 800x600 output.png
sips -Z 800 input.png --out output.png  # macOS (max dimension)

# Screenshots (macOS)
screencapture -x screenshot.png       # full screen, no sound
screencapture -i region.png           # interactive selection
```

### SVG
```bash
# View SVG structure
head -20 image.svg

# Optimize SVG
npx svgo input.svg -o output.svg
```

### When user shares a screenshot
1. Describe what you see (UI elements, text, errors)
2. If it's an error — identify the error and suggest fixes
3. If it's a UI — describe layout, suggest improvements
4. If it's a diagram — explain the flow/architecture

### Rules
- Always describe images in the language the user is using
- Focus on actionable information (error messages, UI issues)
- For charts/graphs, report the key data points and trends
