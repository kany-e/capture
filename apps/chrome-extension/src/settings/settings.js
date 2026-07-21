import { createInlinePermissionController } from "../popup/inline-permission.js";


const shortcutValue = document.querySelector("#shortcut-value");
const shortcutButton = document.querySelector("#shortcut-button");
const inlineToggle = document.querySelector("#inline-capture-toggle");
const inlinePermissionStatus = document.querySelector(
  "#inline-permission-status",
);

const inlinePermissionController = createInlinePermissionController();


function showInlinePermissionStatus(message, kind = "information") {
  inlinePermissionStatus.hidden = !message;
  inlinePermissionStatus.textContent = message;
  inlinePermissionStatus.dataset.kind = kind;
}


async function initializeShortcut() {
  try {
    const commands = await chrome.commands.getAll();
    const captureCommand = commands.find(
      (command) => command.name === "_execute_action",
    );
    shortcutValue.textContent = captureCommand?.shortcut || "Not assigned";
  } catch (_error) {
    shortcutValue.textContent = "Unavailable";
  }
}


async function initializeInlinePermission() {
  if (!chrome.permissions?.contains || !chrome.runtime?.sendMessage) {
    inlineToggle.disabled = true;
    showInlinePermissionStatus(
      "Inline capture is unavailable in this version of Chrome.",
      "error",
    );
    return;
  }

  inlineToggle.disabled = true;
  try {
    inlineToggle.checked = await inlinePermissionController.currentEnabled();
  } catch (_error) {
    showInlinePermissionStatus(
      "Inline capture access could not be checked.",
      "error",
    );
  } finally {
    inlineToggle.disabled = false;
  }
}


async function setInlinePermission(enabled) {
  inlineToggle.disabled = true;
  showInlinePermissionStatus("");
  try {
    const result = await inlinePermissionController.setEnabled(enabled);
    inlineToggle.checked = result.enabled;
    if (result.reason === "denied") {
      showInlinePermissionStatus("Website access was not granted.", "error");
      return;
    }
    showInlinePermissionStatus(
      result.enabled
        ? "Enabled on open web pages; no refresh is needed."
        : "Inline capture is off; toolbar capture still works.",
    );
  } catch (_error) {
    inlineToggle.checked = await inlinePermissionController.currentEnabled()
      .catch(() => !enabled);
    showInlinePermissionStatus(
      "Mema could not update website access.",
      "error",
    );
  } finally {
    inlineToggle.disabled = false;
  }
}


shortcutButton.addEventListener("click", () => {
  void chrome.tabs.create({ url: "chrome://extensions/shortcuts" });
});

inlineToggle.addEventListener("change", () => {
  void setInlinePermission(inlineToggle.checked);
});

window.addEventListener("focus", () => {
  void initializeShortcut();
});

void Promise.all([initializeShortcut(), initializeInlinePermission()]);
