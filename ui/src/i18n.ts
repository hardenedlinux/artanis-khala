import i18n from "i18next";
import { initReactI18next } from "react-i18next";
import en from "./locales/en.json";
import ja from "./locales/ja.json";
import zh from "./locales/zh.json";

export const languages = ["zh", "en", "ja"] as const;
export type Language = (typeof languages)[number];

const storageKey = "khala.language";

function storedLanguage(): Language | undefined {
  try {
    const value = localStorage.getItem(storageKey);
    return languages.includes(value as Language) ? (value as Language) : undefined;
  } catch {
    return undefined;
  }
}

function browserLanguage(): Language {
  const preferred = navigator.languages?.length ? navigator.languages : [navigator.language];
  for (const locale of preferred) {
    const base = locale.toLowerCase().split("-")[0];
    if (languages.includes(base as Language)) return base as Language;
  }
  return "en";
}

void i18n.use(initReactI18next).init({
  resources: {
    en: { translation: en },
    zh: { translation: zh },
    ja: { translation: ja },
  },
  lng: storedLanguage() ?? browserLanguage(),
  fallbackLng: "en",
  interpolation: { escapeValue: false },
});

export async function setLanguage(language: Language): Promise<void> {
  await i18n.changeLanguage(language);
  try {
    localStorage.setItem(storageKey, language);
  } catch {
    // Storage can be disabled; the in-memory language still changes.
  }
}

export default i18n;
