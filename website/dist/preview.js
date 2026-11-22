const preview = document.querySelector("#capture-preview");
const selectionButtons = [...preview.querySelectorAll("[data-mode]")];
const surface = preview.querySelector(".sample-page");
const sampleParagraph = preview.querySelector(".sample-text");
const sampleText = preview.querySelector("#sample-text");
const sampleHint = preview.querySelector(".sample-hint");
const canvas = preview.querySelector(".selection-layer");
const context = canvas.getContext("2d");
const editButton = preview.querySelector(".edit-sample");
const editor = preview.querySelector(".sample-editor");
const input = preview.querySelector("#sample-input");
const copyButton = preview.querySelector(".copy-button");
const selectAllButton = preview.querySelector(".select-all");
const copyStatus = preview.querySelector(".copy-status");
const clipboardText = preview.querySelector(".clipboard-text");
const segmenter = typeof Intl.Segmenter === "function" ? new Intl.Segmenter(undefined, { granularity: "grapheme" }) : null;

let drag;
let selection;
let clipboardValue = sampleText.textContent;
let resetCopyLabel;

for (const control of preview.querySelectorAll("[data-interactive]")) {
  control.hidden = false;
}
surface.classList.add("can-draw");

for (const button of selectionButtons) {
  button.addEventListener("click", () => {
    preview.dataset.shape = button.dataset.mode;
    for (const option of selectionButtons) {
      option.setAttribute("aria-pressed", String(option === button));
    }
  });
}

function selectionPath(shape, width, height) {
  const path = new Path2D();
  const [start, end = start] = shape.points;

  if (shape.mode === "rectangle") {
    path.rect(
      Math.min(start.x, end.x) * width,
      Math.min(start.y, end.y) * height,
      Math.abs(start.x - end.x) * width,
      Math.abs(start.y - end.y) * height
    );
  } else {
    path.moveTo(start.x * width, start.y * height);
    for (const point of shape.points.slice(1)) path.lineTo(point.x * width, point.y * height);
    if (shape.points.length > 2) path.closePath();
  }
  return path;
}

function paintSelection() {
  const { width, height } = surface.getBoundingClientRect();
  const scale = window.devicePixelRatio || 1;
  const pixelWidth = Math.round(width * scale);
  const pixelHeight = Math.round(height * scale);
  if (canvas.width !== pixelWidth) canvas.width = pixelWidth;
  if (canvas.height !== pixelHeight) canvas.height = pixelHeight;
  context.setTransform(scale, 0, 0, scale, 0, 0);
  context.clearRect(0, 0, width, height);

  const shape = editor.hidden ? drag || selection : null;
  surface.classList.toggle("has-drawing", Boolean(shape));
  if (!shape) return;

  const path = selectionPath(shape, width, height);
  context.fillStyle = "rgba(36, 77, 213, .1)";
  context.strokeStyle = "#244dd5";
  context.lineWidth = 1.4;
  context.lineJoin = "round";
  context.fill(path, "evenodd");
  context.stroke(path);
}

function textInSelection(shape) {
  const node = sampleText.firstChild;
  if (!node) return "";

  const { width, height, left, top } = surface.getBoundingClientRect();
  const path = selectionPath(shape, width, height);
  const range = document.createRange();
  const text = node.textContent;
  const parts = segmenter ? Array.from(segmenter.segment(text), part => part.segment) : text;
  const lineHeight = parseFloat(getComputedStyle(sampleText).lineHeight);
  let offset = 0;
  let lastEnd = 0;
  let previousY;
  let result = "";

  context.save();
  context.resetTransform();
  for (const part of parts) {
    const start = offset;
    offset += part.length;
    range.setStart(node, start);
    range.setEnd(node, offset);
    const rect = range.getClientRects()[0];
    if (!rect?.width) continue;

    const x = rect.left + rect.width / 2 - left;
    const y = rect.top + rect.height / 2 - top;
    if (!context.isPointInPath(path, x, y, "evenodd")) continue;

    if (previousY !== undefined && Math.abs(y - previousY) > lineHeight / 2) {
      result += "\n";
    } else if (result && start !== lastEnd && !/\s$/.test(result) && !/^\s/.test(part)) {
      result += " ";
    }
    result += part;
    previousY = y;
    lastEnd = offset;
  }
  context.restore();
  return result.trim();
}

function copyLabel() {
  return selection ? "Copy selection" : "Copy sample";
}

function showClipboard(value, status = "") {
  window.clearTimeout(resetCopyLabel);
  clipboardValue = value.trim();
  clipboardText.textContent = clipboardValue || "No text selected";
  const sampleLanguage = sampleText.getAttribute("lang");
  if (clipboardValue && sampleLanguage) clipboardText.lang = sampleLanguage;
  else clipboardText.removeAttribute("lang");
  clipboardText.classList.toggle("is-empty", !clipboardValue);
  copyButton.disabled = !clipboardValue;
  copyButton.textContent = copyLabel();
  selectAllButton.hidden = !selection;
  copyStatus.textContent = status;
}

function pointerPoint(event) {
  const { left, top, width, height } = surface.getBoundingClientRect();
  return {
    x: Math.max(0, Math.min(1, (event.clientX - left) / width)),
    y: Math.max(0, Math.min(1, (event.clientY - top) / height))
  };
}

function extendDrag(event) {
  const point = pointerPoint(event);
  const start = drag.points[0];
  const { width, height } = surface.getBoundingClientRect();
  drag.moved ||= Math.hypot((point.x - start.x) * width, (point.y - start.y) * height) >= 4;

  if (drag.mode === "rectangle") drag.points[1] = point;
  else drag.points.push(point);
}

surface.addEventListener("pointerdown", event => {
  if (drag || !editor.hidden || !event.isPrimary || event.button !== 0 || event.target.closest("button")) return;

  drag = { mode: preview.dataset.shape || "rectangle", pointerId: event.pointerId, points: [pointerPoint(event)], moved: false };
  surface.setPointerCapture(event.pointerId);
  paintSelection();
});

surface.addEventListener("pointermove", event => {
  if (drag?.pointerId !== event.pointerId) return;
  extendDrag(event);
  paintSelection();
});

surface.addEventListener("pointerup", event => {
  if (drag?.pointerId !== event.pointerId) return;
  extendDrag(event);
  const finished = drag;
  drag = undefined;
  if (finished.moved) {
    selection = finished;
    const text = textInSelection(selection);
    showClipboard(text, text ? "Selection ready to copy." : "No text selected.");
  }
  paintSelection();
});

function cancelDrag(event) {
  if (drag?.pointerId !== event.pointerId) return;
  drag = undefined;
  paintSelection();
}
surface.addEventListener("pointercancel", cancelDrag);
surface.addEventListener("lostpointercapture", cancelDrag);
new ResizeObserver(paintSelection).observe(surface);

selectAllButton.addEventListener("click", () => {
  selection = undefined;
  showClipboard(sampleText.textContent, "All sample text selected.");
  (copyButton.disabled ? editButton : copyButton).focus();
  paintSelection();
});

function toggleEditor(editing) {
  editor.hidden = !editing;
  editButton.hidden = editing;
  sampleParagraph.hidden = editing;
  sampleHint.hidden = editing;
  surface.classList.toggle("can-draw", !editing);
  paintSelection();
  (editing ? input : editButton).focus();
}

editButton.addEventListener("click", () => {
  input.value = sampleText.textContent;
  toggleEditor(true);
});
editor.querySelector(".cancel-edit").addEventListener("click", () => toggleEditor(false));
editor.addEventListener("keydown", event => {
  if (event.key === "Escape") {
    event.preventDefault();
    toggleEditor(false);
  }
});
editor.addEventListener("submit", event => {
  event.preventDefault();
  if (sampleText.textContent !== input.value) {
    sampleText.textContent = input.value;
    sampleText.removeAttribute("lang");
    selection = undefined;
    showClipboard(input.value, "Sample text updated.");
  }
  toggleEditor(false);
});

copyButton.addEventListener("click", async () => {
  const value = clipboardValue;
  window.clearTimeout(resetCopyLabel);
  try {
    await navigator.clipboard.writeText(value);
    if (clipboardValue !== value) return;
    copyButton.textContent = "Copied";
    copyStatus.textContent = "Text copied to the clipboard.";
    resetCopyLabel = window.setTimeout(() => {
      copyButton.textContent = copyLabel();
      copyStatus.textContent = "";
    }, 2500);
  } catch {
    if (clipboardValue !== value) return;
    const textSelection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(clipboardText);
    textSelection.removeAllRanges();
    textSelection.addRange(range);
    copyStatus.textContent = "Text selected. Press Command+C or Ctrl+C to copy it.";
    copyButton.textContent = "Text selected";
  }
});
