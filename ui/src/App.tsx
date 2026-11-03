import { BrowserRouter, NavLink, Route, Routes } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { GeneratePage } from "@/pages/Generate";
import { HistoryPage } from "@/pages/History";
import { ModelsPage } from "@/pages/Models";
import { ChatPage } from "@/pages/Chat";
import { SettingsPage } from "@/pages/Settings";

const pages = [
  ["", "nav.generate", GeneratePage],
  ["history", "nav.history", HistoryPage],
  ["models", "nav.models", ModelsPage],
  ["chat", "nav.chat", ChatPage],
  ["settings", "nav.settings", SettingsPage],
] as const;

export default function App() {
  const { t } = useTranslation();
  return <BrowserRouter basename="/khala">
    <header className="border-b"><div className="mx-auto flex max-w-6xl gap-4 p-4">
      <strong>{t("app.title")}</strong>
      {pages.map(([path, key]) => <NavLink key={path} to={`/${path}`} className={({ isActive }) => isActive ? "underline" : "text-muted-foreground"}>{t(key)}</NavLink>)}
      <a className="ml-auto text-muted-foreground" href="/">{t("nav.nodeEditor")}</a>
    </div></header>
    <main className="mx-auto max-w-6xl p-6"><Routes>
      {pages.map(([path, , Page]) => <Route key={path} path={`/${path}`} element={<Page />} />)}
    </Routes></main>
  </BrowserRouter>;
}
