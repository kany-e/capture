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

  function truncateUnicode(value, maximum) {
    const characters = Array.from(normalizeText(value));
    return {
      text: characters.slice(0, maximum).join(""),
      truncated: characters.length > maximum,
    };
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

  function createStateMachine() {
    let state = STATES.idle;
    let snapshot = null;
    let attempt = null;
    let error = null;

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
        if (!nextSnapshot || state === STATES.submitting) {
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
        state = STATES.idle;
        snapshot = null;
        attempt = null;
        error = null;
        return true;
      },
    });
  }

  global.RecallInlineCore = Object.freeze({
    STATES,
    createStateMachine,
    normalizeText,
    placeAdjacentOverlay,
    placeOverlay,
    truncateUnicode,
  });
})(globalThis);
