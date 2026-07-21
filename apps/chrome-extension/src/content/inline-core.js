(function installRecallInlineCore(global) {
  "use strict";

  if (global.RecallInlineCore) {
    return;
  }

  const STATES = Object.freeze({
    idle: "idle",
    pill: "pill",
    composer: "composer",
    submitting: "submitting",
    success: "success",
    error: "error",
  });

  function normalizeText(value) {
    return String(value ?? "")
      .replace(/\r\n/g, "\n")
      .replace(/\r/g, "\n")
      .trim();
  }

  function unicodeLength(value) {
    return Array.from(String(value ?? "")).length;
  }

  function truncateUnicode(value, maximum) {
    const characters = Array.from(normalizeText(value));
    return {
      text: characters.slice(0, maximum).join(""),
      characterCount: characters.length,
      truncated: characters.length > maximum,
    };
  }

  function createUUID(cryptoImpl = global.crypto) {
    if (!cryptoImpl?.getRandomValues) {
      throw new Error("secure_random_unavailable");
    }
    const bytes = cryptoImpl.getRandomValues(new Uint8Array(16));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0"));
    return [
      hex.slice(0, 4).join(""),
      hex.slice(4, 6).join(""),
      hex.slice(6, 8).join(""),
      hex.slice(8, 10).join(""),
      hex.slice(10, 16).join(""),
    ].join("-");
  }

  function clamp(value, minimum, maximum) {
    return Math.min(Math.max(value, minimum), Math.max(minimum, maximum));
  }

  function placeOverlay(
    anchor,
    size,
    viewport,
    {
      gap = 8,
      padding = 8,
    } = {},
  ) {
    const maximumLeft = viewport.width - size.width - padding;
    const maximumTop = viewport.height - size.height - padding;
    let top = anchor.bottom + gap;
    let placement = "below";

    if (top > maximumTop) {
      top = anchor.top - size.height - gap;
      placement = "above";
    }

    return {
      left: clamp(anchor.right - size.width, padding, maximumLeft),
      top: clamp(top, padding, maximumTop),
      placement,
    };
  }

  function placeAdjacentOverlay(
    anchor,
    size,
    viewport,
    {
      gap = 8,
      padding = 8,
    } = {},
  ) {
    const maximumTop = viewport.height - size.height - padding;
    const top = clamp(anchor.top, padding, maximumTop);
    const rightSpace = viewport.width - anchor.right - padding;
    if (rightSpace >= size.width + gap) {
      return {
        left: anchor.right + gap,
        top,
        placement: "right",
      };
    }

    const leftSpace = anchor.left - padding;
    if (leftSpace >= size.width + gap) {
      return {
        left: anchor.left - size.width - gap,
        top,
        placement: "left",
      };
    }

    return placeOverlay(anchor, size, viewport, { gap, padding });
  }

  function createLatestTaskGate() {
    let generation = 0;
    return Object.freeze({
      next() {
        generation += 1;
        return generation;
      },
      isCurrent(candidate) {
        return candidate === generation;
      },
    });
  }

  function createSuspensionGate() {
    let generation = 0;
    let suspended = false;

    return Object.freeze({
      get suspended() {
        return suspended;
      },
      suspend() {
        generation += 1;
        suspended = true;
        return generation;
      },
      resume(candidate, enabled) {
        if (!suspended || candidate !== generation || enabled !== true) {
          return false;
        }
        suspended = false;
        return true;
      },
      invalidate() {
        generation += 1;
        suspended = true;
      },
    });
  }

  function createListenerRegistry() {
    const removers = [];
    return Object.freeze({
      listen(target, type, listener, options) {
        target.addEventListener(type, listener, options);
        removers.push(() => target.removeEventListener(type, listener, options));
      },
      clear() {
        for (const remove of removers.splice(0).reverse()) {
          remove();
        }
      },
    });
  }

  function shouldObserveKeyboardSelection(event) {
    if (!event || event.key === "Escape") {
      return false;
    }
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "a") {
      return true;
    }
    return Boolean(event.shiftKey) && [
      "ArrowLeft",
      "ArrowRight",
      "ArrowUp",
      "ArrowDown",
      "Home",
      "End",
      "PageUp",
      "PageDown",
    ].includes(event.key);
  }

  function shouldDismissForOutsidePointer(state) {
    return state === STATES.pill || state === STATES.composer;
  }

  function dismissOnEscape(event, state, dismiss) {
    if (event?.key !== "Escape" || ![
      STATES.pill,
      STATES.composer,
      STATES.success,
      STATES.error,
    ].includes(state)) {
      return false;
    }

    // Deliberately do not prevent or stop the event. Recall may close its own
    // surface, but the host page must retain its normal Escape behavior.
    return dismiss({ restoreFocus: state !== STATES.pill });
  }

  function focusErrorAction(error, retryButton, cancelButton) {
    const target = error?.retryable === false ? cancelButton : retryButton;
    target?.focus?.({ preventScroll: true });
    return target ?? null;
  }

  function createStateMachine() {
    let state = STATES.idle;
    let snapshot = null;
    let attempt = null;
    let error = null;

    function reset() {
      state = STATES.idle;
      snapshot = null;
      attempt = null;
      error = null;
    }

    return Object.freeze({
      get state() {
        return state;
      },
      get snapshot() {
        return snapshot;
      },
      get attempt() {
        return attempt;
      },
      get error() {
        return error;
      },
      showPill(nextSnapshot) {
        if (!nextSnapshot || [
          STATES.composer,
          STATES.submitting,
          STATES.success,
          STATES.error,
        ].includes(state)) {
          return false;
        }
        state = STATES.pill;
        snapshot = nextSnapshot;
        attempt = null;
        error = null;
        return true;
      },
      openComposer() {
        if (state !== STATES.pill || !snapshot) {
          return false;
        }
        state = STATES.composer;
        return true;
      },
      beginSubmit(createAttempt) {
        if (![STATES.composer, STATES.error].includes(state) || !snapshot) {
          return null;
        }
        if (error?.retryable === false) {
          return null;
        }
        if (!attempt) {
          attempt = createAttempt(snapshot);
        }
        state = STATES.submitting;
        error = null;
        return attempt;
      },
      fail(nextError) {
        if (state !== STATES.submitting) {
          return false;
        }
        state = STATES.error;
        error = nextError;
        return true;
      },
      succeed() {
        if (state !== STATES.submitting) {
          return false;
        }
        state = STATES.success;
        error = null;
        return true;
      },
      dismiss() {
        if (state === STATES.submitting) {
          return false;
        }
        reset();
        return true;
      },
      reset,
    });
  }

  global.RecallInlineCore = Object.freeze({
    STATES,
    createLatestTaskGate,
    createListenerRegistry,
    createStateMachine,
    createSuspensionGate,
    createUUID,
    dismissOnEscape,
    focusErrorAction,
    normalizeText,
    placeAdjacentOverlay,
    placeOverlay,
    shouldDismissForOutsidePointer,
    shouldObserveKeyboardSelection,
    truncateUnicode,
    unicodeLength,
  });
})(globalThis);
