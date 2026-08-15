const DEFAULT_LOCALE = undefined;

export function formatRelativeTime(value, now = Date.now(), locale = DEFAULT_LOCALE) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Unknown publication time";

  const differenceSeconds = Math.round((date.getTime() - now) / 1000);
  const absoluteSeconds = Math.abs(differenceSeconds);
  const formatter = new Intl.RelativeTimeFormat(locale, { numeric: "auto" });

  if (absoluteSeconds < 10) return "just now";

  const ranges = [
    { limit: 60, divisor: 1, unit: "second" },
    { limit: 3600, divisor: 60, unit: "minute" },
    { limit: 86400, divisor: 3600, unit: "hour" },
    { limit: 604800, divisor: 86400, unit: "day" },
    { limit: 2629800, divisor: 604800, unit: "week" },
    { limit: 31557600, divisor: 2629800, unit: "month" },
    { limit: Number.POSITIVE_INFINITY, divisor: 31557600, unit: "year" },
  ];

  const range = ranges.find((candidate) => absoluteSeconds < candidate.limit);
  return formatter.format(Math.round(differenceSeconds / range.divisor), range.unit);
}

export function formatExactDateTime(value, locale = DEFAULT_LOCALE) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Unknown publication time";
  return new Intl.DateTimeFormat(locale, {
    year: "numeric",
    month: "long",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZoneName: "short",
  }).format(date);
}

export function createRelativeTimeElement(value, { prefix = "", className = "" } = {}) {
  const date = new Date(value);
  const time = document.createElement("time");
  if (className) time.className = className;

  if (Number.isNaN(date.getTime())) {
    time.textContent = `${prefix}Unknown publication time`;
    return time;
  }

  const iso = date.toISOString();
  time.dateTime = iso;
  time.dataset.relativeTime = iso;
  time.dataset.relativePrefix = prefix;
  time.title = formatExactDateTime(iso);
  time.textContent = `${prefix}${formatRelativeTime(iso)}`;
  return time;
}

export function updateRelativeTimeElements(root = document, now = Date.now()) {
  root.querySelectorAll("[data-relative-time]").forEach((element) => {
    const prefix = element.dataset.relativePrefix || "";
    element.textContent = `${prefix}${formatRelativeTime(
      element.dataset.relativeTime,
      now,
    )}`;
  });
}
