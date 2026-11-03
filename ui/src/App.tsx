import { useTranslation } from "react-i18next";

function App() {
  const { t } = useTranslation();

  return (
    <main className="mx-auto max-w-5xl p-8">
      <h1 className="text-3xl font-semibold">{t("app.title")}</h1>
      <p className="mt-2 text-muted-foreground">{t("app.subtitle")}</p>
    </main>
  );
}

export default App;
