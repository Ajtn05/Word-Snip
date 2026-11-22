const preview = document.querySelector("#capture-preview");
const selectionButtons = [...preview.querySelectorAll("[data-mode]")];
const copyButton = preview.querySelector(".copy-button");
const copyStatus = preview.querySelector(".copy-status");
const clipboardText = preview.querySelector(".clipboard-text");
let resetCopyLabel;

for (const control of preview.querySelectorAll("[data-interactive]")) {
  control.hidden = false;
}

for (const button of selectionButtons) {
  button.addEventListener("click", () => {
    preview.dataset.shape = button.dataset.mode;
    for (const option of selectionButtons) {
      option.setAttribute("aria-pressed", String(option === button));
    }
  });
}

copyButton.addEventListener("click", async () => {
  window.clearTimeout(resetCopyLabel);
  try {
    await navigator.clipboard.writeText(clipboardText.textContent);
    copyButton.textContent = "Copied";
    copyStatus.textContent = "Sample text copied to the clipboard.";
    resetCopyLabel = window.setTimeout(() => {
      copyButton.textContent = "Copy sample";
      copyStatus.textContent = "";
    }, 2500);
  } catch {
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(clipboardText);
    selection.removeAllRanges();
    selection.addRange(range);
    copyStatus.textContent = "Sample selected. Press Command+C or Ctrl+C to copy it.";
    copyButton.textContent = "Text selected";
  }
});
