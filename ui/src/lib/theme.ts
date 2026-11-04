export type Theme = "dark" | "light";
const key = "khala.theme";

export function initialTheme(): Theme {
  try {
    const saved = localStorage.getItem(key);
    if (saved === "dark" || saved === "light") return saved;
  } catch {
    // Storage is optional.
  }
  return window.matchMedia("(prefers-color-scheme: light)").matches
    ? "light"
    : "dark";
}

export function applyTheme(theme: Theme): void {
  document.documentElement.classList.toggle("light", theme === "light");
  try {
    localStorage.setItem(key, theme);
  } catch {
    // Storage is optional.
  }
}
